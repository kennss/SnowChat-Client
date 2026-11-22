/// @file        gv2_pairwise_service.dart
/// @description Group protocol v2 — pairwise messages between two members of
///              a group: handling the ones that arrive in the inbox, and
///              queueing the ones this device sends (design §5.5, §7.2, §8).
///              A pairwise message is believed only when the sealed
///              envelope's certified sender, the 1:1 session that decrypted
///              it, the sender and recipient it names and this device's own
///              view of the group all agree, and the sender is a confirmed
///              member of that group.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (P5.6: a key request is spaced by half the time its message has waited; a pairwise message for a group the backup is about to bring back, or one still loading, waits for it — groupsKnown; an unknown sender, a head confirm ahead and a "behind" notice wait until a sync that started after them reached the head — a failed sync no longer drops them; earlier same day: head confirmers max(3, ⌈√N⌉) + the inviter). Earlier 2026-11-20 (a point held without a signature is proven by the signed anchor above it)
///
/// @functions
///  - Gv2PairwiseService.handle(): an inbox row of the pairwise kind
///  - Gv2PairwiseService.afterSync(): confirm the head to members who just
///    joined, when this device is one of the members picked for it or the
///    member whose invite the joiner accepted
///  - Gv2PairwiseService.peerLostSessions(): a member's sessions are gone
///  - Gv2PairwiseService.giveKey() / requestKey() / confirmHead() /
///    notifyBehind() / requestHead(): queue a message (prepare*() for use
///    inside an inbox outcome's transaction)
///  - Gv2PairwiseService.giveKeys(): give the current key to every confirmed
///    member that does not have it
///  - Gv2PairwiseService.settleWithheld(): after a sync, release (or turn
///    into a freeze) a withheld hold
///  - gv2HeadConfirmerCount(): how many members confirm, by group size
///  - gv2HeadConfirmersFor(): which members confirm the head to a joiner
///
/// Notes:
///  - Who confirms the head to a member that joined (sender side only; the
///    joiner believes a confirm from any confirmed member): the
///    max(3, ⌈√N⌉) confirmed members ranked first for it (N = confirmed
///    members), so a large group does not hang on three members being
///    online, and the member that invited it, who is usually online.
///  - What each message does on arrival:
///      Sender Key      installed for its sender, in the same transaction as
///                      the inbox row; rows waiting for it wake.
///      key request     answered with the exact key given to that member
///                      before, or — if it never had one — this device's
///                      key from its current position (not from the start
///                      of the chain: a member reads from when it was given
///                      the key). Only by a confirmed (active) member.
///      head confirm    moves this device from awaitingConfirm to active
///                      when the confirmed head is signed by the server,
///                      includes this account's ACCEPT and has the chain
///                      this device verified at that revision. A head ahead
///                      of this device waits for the log first.
///      behind          a member saw an envelope of this device from an
///                      earlier revision: catch up with the log.
///      session reset   nothing more — decrypting it set up the new 1:1
///                      session.
///      head request    answered with this device's signed head.
///      head proof      a signed head behind this device's own is compared
///                      with the point held there; one beyond what a fresh
///                      sync reaches puts the group on the withheld hold
///                      (the server signed changes it does not serve).
///    Two server-signed heads at one revision with different chains — one
///    held here, one relayed by a member — freeze the group (the server
///    signed two logs), as in gv2_sync.dart. A point held here that was
///    passed inside a batch has no signature of its own; the signed anchor
///    above it covers it (every stored point lies on the anchor's chain).
///  - A pairwise envelope that does not decrypt on the 1:1 session means the
///    session is broken: it is reset and a session reset message goes to
///    the sender through a group both are in (instead of the non-sealed 1:1
///    reset row, design §7.2). At most once per peer per 10 minutes.
///  - Requests are rate limited here (in memory): a "no key" can be claimed
///    by anyone holding a group key, so asking is bounded per sender.
///  - No Sender Key is given while the group is on any hold (frozen,
///    update required, withheld): this device does not know the roster then.
///  - Nothing here logs: messages, keys, groups and members.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;

import '../crypto/identity_binding.dart';
import '../storage/database.dart';
import '../storage/tables/gv2_tables.dart';
import 'gv2_codec.dart';
import 'gv2_credentials.dart';
import 'gv2_inbox.dart';
import 'gv2_outbox.dart';
import 'gv2_pairwise.dart';
import 'gv2_pairwise_crypto.dart';
import 'gv2_sender_key_store.dart';
import 'gv2_store.dart';
import 'gv2_sync.dart';

/// The fewest members picked to confirm the head to a member who joined.
const int gv2MinHeadConfirmers = 3;

/// How many members confirm the head to a member who joined, in a group of
/// [size] confirmed members: max(3, ⌈√size⌉) — 9 → 3, 256 → 16, 1,024 → 32.
int gv2HeadConfirmerCount(int size) {
  var root = 0;
  while (root * root < size) {
    root++;
  }
  return root < gv2MinHeadConfirmers ? gv2MinHeadConfirmers : root;
}

/// At most one key request per sender of a group this often...
const Duration gv2KeyRequestEvery = Duration(minutes: 1);

/// ...and one per chain this often; the same for answers to one member.
const Duration gv2KeyChainEvery = Duration(minutes: 10);

/// At most one "behind" per member and own revision, one session reset per
/// peer, this often.
const Duration gv2NoticeEvery = Duration(minutes: 10);

/// The members (ciphertexts, lowercase hex) that confirm the head to
/// [joiner]: the [gv2HeadConfirmerCount] (of the group's size, the joiner
/// counted) of [confirmed] with the lowest SHA256(joiner ‖ member). Every
/// member computes the same set, and it differs from joiner to joiner.
List<String> gv2HeadConfirmersFor(String joiner, Iterable<String> confirmed) {
  final joinerBytes = gv2Unhex(joiner);
  final members = {...confirmed, joiner};
  final ranked = [
    for (final c in members)
      if (c != joiner)
        (
          c,
          gv2Hex(hash.sha256.convert([...joinerBytes, ...gv2Unhex(c)]).bytes),
        ),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [
    for (final r in ranked.take(gv2HeadConfirmerCount(members.length))) r.$1,
  ];
}

/// Kept form of an opened pairwise envelope: version ‖ certified sender
/// (36 ASCII) ‖ plaintext. Local only.
const int _keptVersion = 0x01;
const int _snowIdLen = 36;

class Gv2PairwiseService {
  final Gv2Store _groups;
  final Gv2SenderKeyStore _keys;
  final Gv2OutboxStore _outbox;
  final Gv2PairwiseCrypto _crypto;
  final Future<Uint8List> Function() _serverHeadKey;
  final String _me;
  final void Function() _queued;
  final int Function() _nowMs;

  /// [mySnowId] is this device's account. [serverHeadKey] returns the
  /// server's log signing key. [onQueued] is called after something was
  /// queued and committed (the app flushes the outbox).
  Gv2PairwiseService({
    required Gv2Store groups,
    required Gv2SenderKeyStore keys,
    required Gv2OutboxStore outbox,
    required Gv2PairwiseCrypto crypto,
    required Future<Uint8List> Function() serverHeadKey,
    required String mySnowId,
    void Function()? onQueued,
    int Function()? nowMs,
    bool Function()? groupsKnown,
  }) : _groups = groups,
       _keys = keys,
       _outbox = outbox,
       _crypto = crypto,
       _serverHeadKey = serverHeadKey,
       _me = mySnowId,
       _queued = onQueued ?? (() {}),
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _groupsKnown = groupsKnown ?? (() => true);

  /// Whether this device knows every group it is in (false on a new install
  /// until it has looked at the backup of its groups).
  final bool Function() _groupsKnown;

  final Map<String, int> _sent = {};

  // ---------------------------------------------------------------------------
  // Receiving
  // ---------------------------------------------------------------------------

  /// Handle an inbox row of the pairwise kind.
  Future<Gv2InboxOutcome> handle(Gv2InboxItem item) async {
    final String sender;
    final Uint8List plaintext;
    if (item.unsealed) {
      final kept = _unkeep(item.payload);
      if (kept == null) return const Gv2Dropped();
      (sender, plaintext) = kept;
    } else {
      final Gv2PairwiseOpened opened;
      try {
        opened = await _crypto.open(item.payload);
      } on Gv2PairwiseOpenException catch (e) {
        final peer = e.sender;
        if (e.reason == Gv2PairwiseOpenFailure.session && peer != null) {
          return _brokenSession(peer);
        }
        return const Gv2Dropped();
      }
      sender = opened.senderSnowId;
      plaintext = opened.plaintext;
      // A certificate names its sender in 36 bytes of text; only a snowId
      // can be a member.
      if (!IdentityBindingV1.isValidSnowId(sender)) return const Gv2Dropped();
      // The session has moved: from here on, a failure retries from this.
      await item.keepOpened(_keep(sender, plaintext));
    }

    final message = Gv2PairwiseMessage.decode(plaintext);
    if (message == null ||
        message.senderSnowId != sender ||
        message.recipientSnowId != _me ||
        sender == _me) {
      return const Gv2Dropped();
    }
    final groupId = gv2Hex(message.groupId);
    final group = await _usable(groupId);
    if (group == null) {
      // A group the backup is about to bring back (this install has not
      // looked yet), or one taken from it whose state is still loading: the
      // message waits for the group instead of being lost.
      final row = await _groups.group(groupId);
      const inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
      final loading = row != null &&
          !row.stateLoaded &&
          row.hold != Gv2Hold.frozen &&
          inside.contains(row.membership);
      return (row == null && !_groupsKnown()) || loading
          ? Gv2WaitForSync(groupId: groupId)
          : const Gv2Dropped();
    }
    final from = await _groups.memberBySnowId(groupId, sender);
    if (from == null || from.checkState != Gv2MemberCheckState.confirmed) {
      // Maybe a member this device has not caught up with (or checked) yet.
      return gv2NotAMember(group, from, item)
          ? const Gv2Dropped()
          : Gv2WaitForSync(groupId: groupId);
    }

    return switch (message.body) {
      Gv2SenderKeyBody key => Gv2Handled(
        write: () => _keys.install(groupId, sender, key),
        wake: [Gv2Wake.key(groupId, sender)],
      ),
      Gv2KeyRequestBody(:final chainId) => _answerKeyRequest(
        group,
        sender,
        chainId,
      ),
      Gv2HeadConfirmBody(:final head) => _headConfirmed(group, item, head),
      Gv2BehindBody(:final head) => _behind(group, item, head),
      Gv2SessionResetBody() => const Gv2Handled(),
      Gv2HeadRequestBody() => _answerHeadRequest(group, sender),
      Gv2HeadProofBody(:final head) => _headProof(group, item, head),
    };
  }

  Future<Gv2InboxOutcome> _answerKeyRequest(
    Gv2GroupRow group,
    String requester,
    int chainId,
  ) async {
    if (!_mayGiveKeys(group)) return const Gv2Dropped();
    final groupId = group.groupId;
    final limit = 'answer:$groupId:$requester:$chainId';
    if (_tooSoon(limit, gv2KeyChainEvery)) return const Gv2Dropped();
    var key = await _keys.delivered(groupId, requester, chainId);
    final first = key == null;
    if (first) {
      final own = await _keys.ownCurrent(groupId, _me);
      if (own == null || own.chainId != chainId) return const Gv2Dropped();
      key = own;
    }
    _mark(limit);
    final given = key;
    return Gv2Handled(
      write: () async {
        if (first) {
          await _keys.recordDelivery(
            groupId,
            requester,
            given,
            nowMs: _nowMs(),
          );
        }
        await _enqueue(groupId, requester, given);
      },
      afterCommit: _queued,
    );
  }

  Future<Gv2InboxOutcome> _headConfirmed(
    Gv2GroupRow group,
    Gv2InboxItem item,
    Gv2SignedHead head,
  ) async {
    // Only a device waiting for it has anything to do.
    if (group.membership != Gv2Membership.awaitingConfirm) {
      return const Gv2Handled();
    }
    final groupId = group.groupId;
    if (!await _signed(groupId, head)) return const Gv2Dropped();
    final mine = await _groups.member(groupId, group.myCiphertext);
    // A head before this account's ACCEPT does not show it in the group.
    if (mine == null || head.revision < mine.joinedRevision) {
      return const Gv2Dropped();
    }
    if (head.revision > group.revision) {
      // Ahead of this device: wait for a sync that reaches the head (one
      // that failed says nothing). Still ahead after that: a head the
      // server does not serve — nothing to confirm with.
      return item.syncReachedSince(group.lastSyncAtMs)
          ? const Gv2Dropped()
          : Gv2WaitForSync(groupId: groupId);
    }
    final held = await _groups.head(groupId, head.revision);
    if (held == null) return const Gv2Dropped();
    if (_same(held.chain, head.chain)) {
      return Gv2Handled(
        write: () => _groups.setMembership(groupId, Gv2Membership.active),
        // Keys held back until now can go.
        afterCommit: _queued,
      );
    }
    return _contradicts(groupId, held, head);
  }

  Future<Gv2InboxOutcome> _behind(
    Gv2GroupRow group,
    Gv2InboxItem item,
    Gv2SignedHead head,
  ) async {
    final groupId = group.groupId;
    if (!await _signed(groupId, head)) return const Gv2Dropped();
    if (head.revision > group.revision) {
      // The sync is the point: the notice is done once a sync that started
      // after it arrived reached the head (one that failed has not looked).
      return item.syncReachedSince(group.lastSyncAtMs)
          ? const Gv2Handled()
          : Gv2WaitForSync(groupId: groupId);
    }
    final held = await _groups.head(groupId, head.revision);
    if (held == null || _same(held.chain, head.chain)) {
      return const Gv2Handled();
    }
    return _contradicts(groupId, held, head);
  }

  /// A member asks for the head this device holds: answer with it, signed
  /// by the server (nothing a member could not get from the server itself).
  Future<Gv2InboxOutcome> _answerHeadRequest(
    Gv2GroupRow group,
    String requester,
  ) async {
    final groupId = group.groupId;
    final head = _headOf(group);
    if (head == null) return const Gv2Dropped();
    final limit = 'head:$groupId:$requester';
    if (_tooSoon(limit, gv2NoticeEvery)) return const Gv2Dropped();
    _mark(limit);
    return Gv2Handled(
      write: () => _enqueue(groupId, requester, Gv2HeadProofBody(head)),
      afterCommit: _queued,
    );
  }

  /// A member shows the head it holds. Behind this device's own head it is
  /// compared with the point held there (two signed heads freeze). Beyond
  /// it, the log is fetched; when a sync that started after the proof
  /// arrived still ends short of it, the server is withholding changes —
  /// its own signature says the head exists — and the group is put on the
  /// withheld hold with the head as evidence.
  Future<Gv2InboxOutcome> _headProof(
    Gv2GroupRow group,
    Gv2InboxItem item,
    Gv2SignedHead head,
  ) async {
    final groupId = group.groupId;
    if (!await _signed(groupId, head)) return const Gv2Dropped();
    if (head.revision > group.revision) {
      if (!item.syncReachedSince(group.lastSyncAtMs)) {
        return Gv2WaitForSync(groupId: groupId);
      }
      if (group.hold != Gv2Hold.none) return const Gv2Handled();
      final evidence = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'kind': 'withheld',
            'source': 'pairwise',
            'heldRevision': group.revision,
            'served': _headJson(head.revision, head.chain, head.headSig),
          }),
        ),
      );
      return Gv2Handled(
        write: () =>
            _groups.setHold(groupId, Gv2Hold.withheld, evidence: evidence),
      );
    }
    final held = await _groups.head(groupId, head.revision);
    if (held == null || _same(held.chain, head.chain)) {
      return const Gv2Handled();
    }
    return _contradicts(groupId, held, head);
  }

  /// [head] (signed by the server, relayed by a member) and the point this
  /// device holds at the same revision have different chains. When the
  /// server signed the held point too (itself, or through the anchor above
  /// it), the server signed two logs: the group is frozen. Otherwise
  /// nothing is proven.
  Future<Gv2InboxOutcome> _contradicts(
    String groupId,
    Gv2HeadRow held,
    Gv2SignedHead head,
  ) async {
    final evidence = await _twoHeads(groupId, held, head);
    if (evidence == null) return const Gv2Dropped();
    return Gv2Handled(
      write: () => _groups.setHold(groupId, Gv2Hold.frozen, evidence: evidence),
    );
  }

  /// The evidence that the server signed two logs — the chain of [held] and
  /// the one of [head] — or null when nothing proves the server signed
  /// [held]'s chain.
  ///
  /// [held] proves it by its own signature, or — when it was passed inside
  /// a batch and so stored without one — by the signed anchor above it: the
  /// anchor only moves along entries this device verified, and a re-invite
  /// forgets the points of the earlier membership (Gv2Store), so every
  /// stored point lies on the anchor's chain and the anchor's signature
  /// covers it. The evidence then names that covering head; the entries
  /// between are on the server's own log, which the covering head commits to.
  Future<Uint8List?> _twoHeads(
    String groupId,
    Gv2HeadRow held,
    Gv2SignedHead head,
  ) async {
    Uint8List evidence(Map<String, Object?> proof) => Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'kind': 'two_heads',
          'source': 'pairwise',
          ...proof,
          'served': _headJson(head.revision, head.chain, head.headSig),
        }),
      ),
    );

    final heldSig = held.headSig;
    if (heldSig != null &&
        await _signed(
          groupId,
          Gv2SignedHead(
            revision: held.revision,
            chain: held.chain,
            headSig: heldSig,
          ),
        )) {
      return evidence({'held': _headJson(held.revision, held.chain, heldSig)});
    }

    final anchor = await _groups.group(groupId);
    final anchorSig = anchor?.headSig;
    if (anchor == null || anchorSig == null) return null;
    if (anchor.revision < held.revision ||
        (anchor.revision == held.revision && !_same(anchor.chain, held.chain))) {
      return null;
    }
    final covered = await _signed(
      groupId,
      Gv2SignedHead(
        revision: anchor.revision,
        chain: anchor.chain,
        headSig: anchorSig,
      ),
    );
    if (!covered) return null;
    return evidence({
      'held': {
        'revision': held.revision,
        'chain': base64Encode(held.chain),
        'headSig': null,
      },
      'cover': _headJson(anchor.revision, anchor.chain, anchorSig),
    });
  }

  static Map<String, Object?> _headJson(
    int revision,
    Uint8List chain,
    Uint8List sig,
  ) => {
    'revision': revision,
    'chain': base64Encode(chain),
    'headSig': base64Encode(sig),
  };

  /// After a sync of [groupId]: a withheld hold ends when this device has
  /// reached the head it was shown. With the same chain there, the hold is
  /// released. With another chain, the server signed two logs — the group
  /// is frozen when the server's signature covers this device's point, and
  /// stays on hold otherwise.
  Future<void> settleWithheld(String groupId) async {
    final group = await _groups.group(groupId);
    if (group == null || group.hold != Gv2Hold.withheld) return;
    final head = _withheldHead(group.holdEvidence);
    if (head == null) {
      // Nothing to compare with: a hold cannot rest on unreadable evidence.
      await _groups.setHold(groupId, Gv2Hold.none);
      return;
    }
    if (group.revision < head.revision) return;
    final held = await _groups.head(groupId, head.revision);
    if (held == null || _same(held.chain, head.chain)) {
      await _groups.setHold(groupId, Gv2Hold.none);
      return;
    }
    final evidence = await _twoHeads(groupId, held, head);
    if (evidence != null) {
      await _groups.setHold(groupId, Gv2Hold.frozen, evidence: evidence);
    }
  }

  static Gv2SignedHead? _withheldHead(Uint8List? evidence) {
    if (evidence == null) return null;
    try {
      final json = jsonDecode(utf8.decode(evidence));
      if (json is! Map || json['kind'] != 'withheld') return null;
      final served = json['served'];
      if (served is! Map) return null;
      return Gv2SignedHead(
        revision: served['revision'] as int,
        chain: base64Decode(served['chain'] as String),
        headSig: base64Decode(served['headSig'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  /// The envelope from [peer] did not decrypt: reset the session and tell
  /// [peer] through a group both are in.
  Future<Gv2InboxOutcome> _brokenSession(String peer) async {
    final limit = 'reset:$peer';
    if (_tooSoon(limit, gv2NoticeEvery)) return const Gv2Dropped();
    final groups = (await _groups.groups()).map((g) => g.groupId).toList()
      ..sort();
    for (final groupId in groups) {
      if (await _usable(groupId) == null) continue;
      final m = await _groups.memberBySnowId(groupId, peer);
      if (m == null || m.checkState != Gv2MemberCheckState.confirmed) continue;
      _mark(limit);
      return Gv2Handled(
        write: () => _enqueue(groupId, peer, const Gv2SessionResetBody()),
        afterCommit: _queued,
      );
    }
    return const Gv2Dropped();
  }

  // ---------------------------------------------------------------------------
  // After a sync
  // ---------------------------------------------------------------------------

  /// [result] of syncing [groupId], after its members were checked: for each
  /// member who joined (an applied ACCEPT) and whose account is confirmed,
  /// confirm the head when this device is one of the members picked for it
  /// or the member whose invite it accepted, and is itself active.
  Future<void> afterSync(String groupId, Gv2SyncResult result) async {
    final joiners = {
      for (final e in result.applied)
        if (e.actions.any((a) => a is Gv2Accept)) gv2Hex(e.actor),
    };
    if (joiners.isEmpty) return;
    final group = await _usable(groupId);
    if (group == null || group.membership != Gv2Membership.active) return;
    final confirmed = {
      for (final m in await _groups.confirmedMembers(groupId)) m.ciphertext: m,
    };
    for (final joiner in joiners) {
      final row = confirmed[joiner];
      if (row == null || joiner == group.myCiphertext) continue;
      final inviter = result.invitedBy[joiner] == group.myCiphertext;
      if (!inviter &&
          !gv2HeadConfirmersFor(
            joiner,
            confirmed.keys,
          ).contains(group.myCiphertext)) {
        continue;
      }
      await confirmHead(groupId, row.snowId!);
    }
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// Give [member] this device's key of [groupId]: the key it was given
  /// before for the current chain, else the key from its current position
  /// (recorded). Null when there is nothing to give or nobody to give it to.
  Future<Gv2InboxWrite?> prepareGiveKey(String groupId, String member) async {
    final group = await _usable(groupId);
    if (group == null || !_mayGiveKeys(group)) return null;
    if (!await _confirmedOther(groupId, member)) return null;
    final own = await _keys.ownCurrent(groupId, _me);
    if (own == null) return null;
    final given = await _keys.delivered(groupId, member, own.chainId);
    return () async {
      if (given == null) {
        await _keys.recordDelivery(groupId, member, own, nowMs: _nowMs());
      }
      await _enqueue(groupId, member, given ?? own);
    };
  }

  /// Give this device's current key of [groupId] to every confirmed member
  /// that has not been given it yet (from its current position, recorded).
  /// Returns how many members it was queued for.
  Future<int> giveKeys(String groupId) => _groups.transaction(() async {
    final group = await _usable(groupId);
    if (group == null || !_mayGiveKeys(group)) return 0;
    final own = await _keys.ownCurrent(groupId, _me);
    if (own == null) return 0;
    final have = await _keys.deliveredTo(groupId, own.chainId);
    var queued = 0;
    for (final m in await _groups.confirmedMembers(groupId)) {
      final member = m.snowId;
      if (member == null ||
          member == _me ||
          have.contains(member) ||
          m.reach == Gv2Reach.deleted) {
        continue;
      }
      await _keys.recordDelivery(groupId, member, own, nowMs: _nowMs());
      await _enqueue(groupId, member, own);
      queued++;
    }
    return queued;
  });

  /// Ask [member] for the signed head it holds (its authenticated envelope
  /// header disagrees with this device's log, or is ahead of what the
  /// server serves). Null when asked recently.
  Future<Gv2InboxWrite?> prepareRequestHead(
    String groupId,
    String member,
  ) async {
    if (await _usable(groupId) == null) return null;
    if (!await _confirmedOther(groupId, member)) return null;
    final limit = 'askhead:$groupId:$member';
    if (_tooSoon(limit, gv2NoticeEvery)) return null;
    _mark(limit);
    return () => _enqueue(groupId, member, const Gv2HeadRequestBody());
  }

  /// Ask [sender] for its key of chain [chainId] in [groupId]. Null when
  /// asked too recently, or [sender] is not a confirmed member.
  Future<Gv2InboxWrite?> prepareRequestKey(
    String groupId,
    String sender,
    int chainId, {
    Duration waited = Duration.zero,
  }) async {
    if (await _usable(groupId) == null) return null;
    if (!await _confirmedOther(groupId, sender)) return null;
    final perSender = 'request:$groupId:$sender';
    final perChain = 'request:$groupId:$sender:$chainId';
    // The longer a message has waited for its key ([waited]), the rarer the
    // request: half the wait between two (a chain its sender can no longer
    // answer was asked for every ten minutes for thirty days).
    final chainEvery = waited ~/ 2 > gv2KeyChainEvery
        ? waited ~/ 2
        : gv2KeyChainEvery;
    if (_tooSoon(perSender, gv2KeyRequestEvery) ||
        _tooSoon(perChain, chainEvery)) {
      return null;
    }
    _mark(perSender);
    _mark(perChain);
    return () => _enqueue(groupId, sender, Gv2KeyRequestBody(chainId));
  }

  /// Tell [member] the head of [groupId] as this device holds it (it sees
  /// [member]'s ACCEPT there). Null when this device cannot vouch for it.
  Future<Gv2InboxWrite?> prepareConfirmHead(
    String groupId,
    String member,
  ) async {
    final group = await _usable(groupId);
    if (group == null || group.membership != Gv2Membership.active) return null;
    final head = _headOf(group);
    if (head == null || !await _confirmedOther(groupId, member)) return null;
    return () => _enqueue(groupId, member, Gv2HeadConfirmBody(head));
  }

  /// Tell [member] its envelope came from behind this device's head. Null
  /// when told at this revision recently.
  Future<Gv2InboxWrite?> prepareNotifyBehind(
    String groupId,
    String member,
  ) async {
    final group = await _usable(groupId);
    if (group == null) return null;
    final head = _headOf(group);
    if (head == null || !await _confirmedOther(groupId, member)) return null;
    final limit = 'behind:$groupId:$member:${group.revision}';
    if (_tooSoon(limit, gv2NoticeEvery)) return null;
    _mark(limit);
    return () => _enqueue(groupId, member, Gv2BehindBody(head));
  }

  /// [peer] stated — under its member signing key — that it lost its keys
  /// (member_reset): the 1:1 session with it is gone on its side too. Ours
  /// is put aside, so that what goes to it next (the head confirmation, a
  /// Sender Key) starts a new session instead of being sealed on one the
  /// peer cannot open. Throws when that could not be recorded: the notice
  /// is then handled again later — swallowed, the head confirmation would
  /// go out on the old session and the peer would never be confirmed.
  Future<void> peerLostSessions(String peer) => _crypto.forgetSession(peer);

  Future<bool> giveKey(String groupId, String member) =>
      _now(prepareGiveKey(groupId, member));

  Future<bool> requestKey(String groupId, String sender, int chainId) =>
      _now(prepareRequestKey(groupId, sender, chainId));

  Future<bool> confirmHead(String groupId, String member) =>
      _now(prepareConfirmHead(groupId, member));

  Future<bool> notifyBehind(String groupId, String member) =>
      _now(prepareNotifyBehind(groupId, member));

  Future<bool> requestHead(String groupId, String member) =>
      _now(prepareRequestHead(groupId, member));

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<bool> _now(Future<Gv2InboxWrite?> prepared) async {
    final write = await prepared;
    if (write == null) return false;
    await _groups.transaction(write);
    _queued();
    return true;
  }

  Future<void> _enqueue(
    String groupId,
    String recipient,
    Gv2PairwiseBody body,
  ) => _outbox.enqueuePairwise(
    groupId: groupId,
    message: Gv2PairwiseMessage(
      groupId: gv2Unhex(groupId),
      sender: gv2AccountIdOfSnowId(_me),
      recipient: gv2AccountIdOfSnowId(recipient),
      body: body,
    ),
    nowMs: _nowMs(),
  );

  /// The group when this device takes part in it now (a member, waiting for
  /// confirmation or confirmed, and not frozen), else null.
  Future<Gv2GroupRow?> _usable(String groupId) async {
    final group = await _groups.group(groupId);
    const inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
    if (group == null ||
        group.hold == Gv2Hold.frozen ||
        !group.stateLoaded ||
        !inside.contains(group.membership)) {
      return null;
    }
    return group;
  }

  /// Keys leave only from a confirmed member of a group that is not on any
  /// hold: on hold, this device does not know who is in the group now.
  static bool _mayGiveKeys(Gv2GroupRow group) =>
      group.membership == Gv2Membership.active && group.hold == Gv2Hold.none;

  Future<bool> _confirmedOther(String groupId, String snowId) async {
    if (snowId == _me) return false;
    final m = await _groups.memberBySnowId(groupId, snowId);
    return m != null && m.checkState == Gv2MemberCheckState.confirmed;
  }

  static Gv2SignedHead? _headOf(Gv2GroupRow group) {
    final sig = group.headSig;
    if (sig == null) return null;
    return Gv2SignedHead(
      revision: group.revision,
      chain: group.chain,
      headSig: sig,
    );
  }

  Future<bool> _signed(String groupId, Gv2SignedHead head) async =>
      gv2VerifyHead(
        headPublicKey: await _serverHeadKey(),
        groupId: gv2Unhex(groupId),
        revision: head.revision,
        chain: head.chain,
        headSig: head.headSig,
      );

  bool _tooSoon(String key, Duration every) {
    final at = _sent[key];
    return at != null && _nowMs() - at < every.inMilliseconds;
  }

  void _mark(String key) {
    final now = _nowMs();
    _sent[key] = now;
    if (_sent.length > 4096) {
      // Entries that no longer hold anything back at the shortest spacing;
      // a request spaced by a long wait may go a little earlier after this.
      _sent.removeWhere((_, at) => now - at >= gv2KeyChainEvery.inMilliseconds);
    }
  }

  static Uint8List _keep(String sender, Uint8List plaintext) =>
      Uint8List.fromList([_keptVersion, ...ascii.encode(sender), ...plaintext]);

  static (String, Uint8List)? _unkeep(Uint8List kept) {
    if (kept.length < 1 + _snowIdLen || kept[0] != _keptVersion) return null;
    return (
      ascii.decode(kept.sublist(1, 1 + _snowIdLen)),
      Uint8List.fromList(kept.sublist(1 + _snowIdLen)),
    );
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
