/// @file        gv2_sync.dart
/// @description Group protocol v2 — bringing this device's view of a group
///              up to the server's log WITHOUT trusting the server. Every
///              entry is run through the same rules the server applied
///              (gv2_state_machine.dart); the state is taken only from an
///              anchor this device already trusts (an invite, the backup, or
///              its own last verified point); and what the server signed is
///              kept as evidence when it contradicts itself. Also confirms
///              the account behind each member, once, off the main isolate
///              (design document §5.4 – §5.6).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (P5.6: inviteInLog() — an invite checked against the server's log without storing anything). Earlier 2026-11-21 (the result names who invited each member that joined, for the inviter's head confirm). Earlier 2026-11-20 (an invalid_entry freeze is judged again once per app run). Earlier 2026-11-13
///
/// @functions
///  - Gv2Sync.sync(groupId): load the anchor's state if missing, then follow
///    the log — Gv2SyncResult / Gv2SyncStatus
///  - Gv2Sync.checkMembers(groupId): confirm the accounts of unchecked
///    members and name the pending invitees — Gv2MemberCheckSummary
///  - Gv2Sync.titleMatchesServerKeys(groupId): does the group's title commit
///    to the server keys this device holds
///  - gv2VerifyHead(): the server's signature over a point of a log
///  - gv2StandingAfter(): this account's standing after one entry
///
/// Notes:
///  - What ends a sync, and what it does to the group:
///      upToDate / advanced   the stored anchor is the server's head
///      notReadable           the server says this account may not read the
///                            group (not a member or invitee any more).
///                            Nothing is changed on the server's word.
///      snapshotMismatch      the state the server serves at the anchor does
///                            not hash to the anchor. Nothing is stored.
///      serverBehind          the server's head is BELOW the stored anchor (a
///                            rollback). The anchor stays.
///      badData               something that does not verify and that the
///                            server did not sign. Nothing proves anything;
///                            the verified part before it is kept.
///      updateRequired        an entry of a protocol version this build does
///                            not know. Hold, released by a later sync that
///                            gets through (after an app update).
///      frozen                the SERVER'S OWN SIGNATURE shows it accepted
///                            what the rules forbid, or signed two different
///                            logs. The group is frozen for good and the
///                            signed material is stored as evidence.
///      offline / serverError no answer, or an error answer
///      localCorruption       the stored rows do not match their own hash and
///                            could not be repaired from the anchor
///      retry                 another writer moved the group while this sync
///                            ran; nothing is wrong, run it again
///  - A freeze needs proof. Three cases, each resting on signatures by the
///    server's log key that this device verified itself:
///      invalid_entry  an entry that extends the stored chain, is refused by
///                     the rules, and whose head the server signed
///      fork           the next entry does not extend the chain of the head
///                     the server signed before, yet its own head is signed
///      two_heads      a signed head at the stored revision with another chain
///    Data that merely fails to verify (and carries no valid server
///    signature) never freezes a group: anything could produce it.
///  - Only invalid_entry rests on this build's reading of the rules — the
///    server's (TypeScript) and this device's (Dart) state machines could
///    disagree, and the freeze would then be this build's mistake. Such a
///    freeze is judged again, once per app run, with the rules of the build
///    now running: when they accept the entry, the freeze is lifted and the
///    sync goes on (a fresh device would accept the same log). fork and
///    two_heads are facts about signatures and hashes, not about the rules;
///    they stay. Envelopes that arrived while the group was frozen were
///    dropped and do not come back.
///  - Head signatures are checked for the point that gets stored (the last
///    entry of each stored batch); a later head's chain covers all earlier
///    entries.
///  - Verifying a page of entries costs one Ed25519 verification per entry
///    (2–5 ms on a phone); pages of [verifyInIsolateFrom] entries or more are
///    verified in a worker isolate. Member checks likewise.
///  - Applied entries are returned so the caller can act on them (system
///    lines, dropping a removed member's keys). The one effect that must
///    survive a crash — "a member was taken out, so a new Sender Key is due"
///    — is stored with the state as lastRemovalRevision.
///  - Nothing here logs a group id, a ciphertext or a key.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';

import '../crypto/ed25519_strict.dart';
import '../storage/database.dart';
import '../storage/tables/gv2_tables.dart';
import 'gv2_codec.dart';
import 'gv2_credentials.dart';
import 'gv2_invite.dart' show Gv2InviteMessage;
import 'gv2_keys.dart';
import 'gv2_member_check.dart';
import 'gv2_payloads.dart';
import 'gv2_state_machine.dart';
import 'gv2_store.dart';
import 'gv2_transport.dart';

/// How a sync ended (see the file notes).
enum Gv2SyncStatus {
  upToDate,
  advanced,
  unknownGroup,
  notReadable,
  snapshotMismatch,
  serverBehind,
  badData,
  updateRequired,
  frozen,
  offline,
  serverError,
  localCorruption,
  retry,
}

class Gv2SyncResult {
  final Gv2SyncStatus status;

  /// The stored revision before and after (null for an unknown group).
  final int? fromRevision;
  final int? toRevision;

  /// This account's standing after the sync.
  final Gv2Membership? membership;

  /// The entries applied by this sync, in order.
  final List<Gv2Entry> applied;

  /// For each member that joined in [applied] (an ACCEPT; ciphertext,
  /// lowercase hex): the member whose invite it accepted. A member that
  /// joined twice in one sync is named with its last invite.
  final Map<String, String> invitedBy;

  /// With [Gv2SyncStatus.serverError]: the server's error code.
  final String? serverCode;

  const Gv2SyncResult(
    this.status, {
    this.fromRevision,
    this.toRevision,
    this.membership,
    this.applied = const [],
    this.invitedBy = const {},
    this.serverCode,
  });
}

class Gv2MemberCheckSummary {
  /// Members whose account was confirmed by this run.
  final int confirmed;

  /// Members that were checked and could not be confirmed.
  final int unconfirmed;
  const Gv2MemberCheckSummary(this.confirmed, this.unconfirmed);
}

/// The account key this device already confirmed for [snowId] (Identity
/// Binding v1), or null when it has none.
typedef Gv2PinnedAccountKey = Future<Uint8List?> Function(String snowId);

/// True only when [headSig] is the server log key's strict signature over
/// ([groupId], [revision], [chain]).
bool gv2VerifyHead({
  required Uint8List headPublicKey,
  required Uint8List groupId,
  required int revision,
  required Uint8List chain,
  required Uint8List headSig,
}) {
  try {
    return verifyEd25519Strict(
        headPublicKey, gv2HeadMessage(groupId, revision, chain), headSig);
  } catch (_) {
    return false;
  }
}

/// This account's standing after [entry] was applied and gave [after].
/// [myCiphertext] is the lowercase hex of its member ciphertext.
Gv2Membership gv2StandingAfter({
  required Gv2Membership before,
  required String myCiphertext,
  required Gv2Entry entry,
  required Gv2GroupState after,
}) {
  const inside = {
    Gv2Membership.active,
    Gv2Membership.awaitingConfirm,
    Gv2Membership.invited,
  };
  if (after.deleted && inside.contains(before)) return Gv2Membership.ended;
  if (after.members.containsKey(myCiphertext)) {
    // A member by the log. Sending waits for a member's confirmation unless
    // this device was already past that.
    return before == Gv2Membership.active
        ? Gv2Membership.active
        : Gv2Membership.awaitingConfirm;
  }
  if (after.pending.containsKey(myCiphertext)) return Gv2Membership.invited;
  switch (before) {
    case Gv2Membership.active:
    case Gv2Membership.awaitingConfirm:
      final mine = gv2Hex(entry.actor) == myCiphertext;
      final left = mine && entry.actions.any((a) => a is Gv2Leave);
      return left ? Gv2Membership.left : Gv2Membership.removed;
    case Gv2Membership.invited:
      return Gv2Membership.declined;
    default:
      return before;
  }
}

/// What the messaging layer uses of [Gv2Sync] (gv2_messaging.dart).
abstract interface class Gv2LogSync {
  Future<Gv2SyncResult> sync(String groupId);
  Future<Gv2MemberCheckSummary> checkMembers(String groupId);

  /// Whether the server's log bears out [invite] at the point it names (see
  /// Gv2Sync.inviteInLog). Stores nothing.
  Future<bool?> inviteInLog({
    required Gv2InviteMessage invite,
    required Uint8List inviter,
    required Uint8List mine,
  });
}

class Gv2Sync implements Gv2LogSync {
  final Gv2Store _store;
  final Gv2Transport _transport;
  final Gv2Credentials _credentials;
  final Gv2PinnedAccountKey _pinnedAccountKey;
  final int Function() _nowMs;

  /// Entries per request (null = the server's maximum).
  final int? pageLimit;

  /// Pages with at least this many entries are verified in a worker isolate.
  final int verifyInIsolateFrom;

  /// Member batches of at least this size are checked in a worker isolate.
  final int checkInIsolateFrom;

  final Map<String, Future<Gv2SyncResult>> _running = {};

  /// Frozen groups whose invalid_entry evidence this run judged again.
  final Set<String> _rejudged = {};

  Gv2Sync({
    required Gv2Store store,
    required Gv2Transport transport,
    required Gv2Credentials credentials,
    required Gv2PinnedAccountKey pinnedAccountKey,
    int Function()? nowMs,
    this.pageLimit,
    this.verifyInIsolateFrom = 8,
    this.checkInIsolateFrom = 16,
  })  : _store = store,
        _transport = transport,
        _credentials = credentials,
        _pinnedAccountKey = pinnedAccountKey,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  /// Bring [groupId] (lowercase hex) up to the server's log. Concurrent calls
  /// for the same group share one run. Never throws for what a server or a
  /// network can cause; see [Gv2SyncStatus].
  @override
  Future<Gv2SyncResult> sync(String groupId) {
    final running = _running[groupId];
    if (running != null) return running;
    final future = _sync(groupId);
    _running[groupId] = future;
    return future.whenComplete(() => _running.remove(groupId));
  }

  Future<Gv2SyncResult> _sync(String groupId) async {
    final found = await _store.group(groupId);
    if (found == null) return const Gv2SyncResult(Gv2SyncStatus.unknownGroup);
    final row = found.hold == Gv2Hold.frozen &&
            _rejudged.add(groupId) &&
            await _liftMistakenFreeze(found)
        ? (await _store.group(groupId))!
        : found;
    Gv2SyncResult end(Gv2SyncStatus status, {String? code}) => Gv2SyncResult(
          status,
          fromRevision: row.revision,
          toRevision: row.revision,
          membership: row.membership,
          serverCode: code,
        );
    if (row.hold == Gv2Hold.frozen) return end(Gv2SyncStatus.frozen);
    // A sync that reaches the server's head is recorded under the time it
    // STARTED: whatever the server had accepted before then is in it.
    final startedAtMs = _nowMs();

    try {
      final headKey = (await _credentials.serverKeys()).headPublicKey;
      var current = row;
      if (!current.stateLoaded) {
        final failed = await _loadAnchorState(current, headKey);
        if (failed != null) return end(failed);
        current = (await _store.group(groupId))!;
      }

      Gv2GroupState state;
      try {
        state = (await _store.loadState(groupId))!;
      } on Gv2StoreCorruption {
        // Local damage: rebuild the rows from the anchor, which is intact.
        await _store.dropState(groupId);
        current = (await _store.group(groupId))!;
        final failed = await _loadAnchorState(current, headKey);
        if (failed != null) return end(Gv2SyncStatus.localCorruption);
        current = (await _store.group(groupId))!;
        state = (await _store.loadState(groupId))!;
      }
      return await _followLog(current, state, headKey, startedAtMs);
    } on Gv2NetworkException {
      return end(Gv2SyncStatus.offline);
    } on Gv2ApiException catch (e) {
      const unreadable = {'not_a_member', 'revision_not_readable', 'group_not_found'};
      if (unreadable.contains(e.code)) return end(Gv2SyncStatus.notReadable);
      return end(Gv2SyncStatus.serverError, code: e.code);
    } on Gv2ProtocolException {
      return end(Gv2SyncStatus.badData);
    } on Gv2CredentialException {
      return end(Gv2SyncStatus.serverError, code: 'credentials');
    } on Gv2StoreConflict {
      // Another writer moved the group meanwhile; the next sync starts from
      // what is stored now.
      return end(Gv2SyncStatus.retry);
    }
  }

  /// Run [call] with a presentation for [masterKey]. When the server refuses
  /// the presentation, credentials are fetched again once and the call is
  /// repeated.
  Future<T> _presented<T>(
    Uint8List masterKey,
    Future<T> Function(Uint8List presentation) call,
  ) async {
    try {
      return await call(await _credentials.presentation(masterKey));
    } on Gv2ApiException catch (e) {
      if (e.status != 401 || e.code != 'presentation_invalid') rethrow;
      await _credentials.renew();
      return call(await _credentials.presentation(masterKey));
    }
  }

  /// [row] is frozen. When its evidence is an invalid_entry — an entry that
  /// extends the stored anchor and that the rules of the build which froze
  /// the group refused — run that entry through the rules of THIS build.
  /// If they accept it, the freeze was a disagreement between the two state
  /// machines, not the server's doing: it is lifted (only on exactly that
  /// evidence) and true is returned. Anything else keeps the freeze.
  Future<bool> _liftMistakenFreeze(Gv2GroupRow row) async {
    final evidence = row.holdEvidence;
    if (evidence == null) return false;
    final Uint8List entryBytes;
    try {
      final json = jsonDecode(utf8.decode(evidence));
      if (json is! Map || json['kind'] != 'invalid_entry') return false;
      final served = json['served'];
      if (served is! Map) return false;
      final encoded = served['entry'];
      if (encoded is! String) return false;
      entryBytes = base64Decode(encoded);
    } on FormatException {
      return false;
    }

    final Gv2GroupState? state;
    try {
      state = await _store.loadState(row.groupId);
    } on Gv2StoreCorruption {
      return false;
    }
    if (state == null) return false;

    final groupId = gv2Unhex(row.groupId);
    try {
      // Refused as well when the entry does not extend the anchor this
      // device still holds (revision, prev_chain): the evidence must be
      // about this anchor.
      gv2ApplyEntry(state, groupId, gv2DecodeEntry(entryBytes));
    } on Gv2DecodeException {
      return false;
    } on Gv2Reject {
      return false;
    }
    return _store.liftFreeze(row.groupId, evidence);
  }

  /// Whether the server's log bears out [invite] at the point it names: the
  /// state there is the one the invite commits to, under a head the server
  /// signed, with this account ([mine], its member ciphertext) pending under
  /// the invite's key and invited by [inviter] (a member ciphertext). True /
  /// false; null when that cannot be told now (no network, the server's own
  /// trouble, an answer that does not verify — evidence of nothing). Stores
  /// nothing: for a group whose record an unchecked invite must not replace
  /// (one this account left).
  @override
  Future<bool?> inviteInLog({
    required Gv2InviteMessage invite,
    required Uint8List inviter,
    required Uint8List mine,
  }) async {
    try {
      final headKey = (await _credentials.serverKeys()).headPublicKey;
      final snapshot = await _presented(
        invite.masterKey,
        (p) => _transport.snapshot(
          groupId: invite.groupId,
          presentation: p,
          at: invite.revision,
        ),
      );
      final state = snapshot.state;
      if (!gv2VerifyHead(
        headPublicKey: headKey,
        groupId: invite.groupId,
        revision: state.revision,
        chain: state.chain,
        headSig: snapshot.headSig,
      )) {
        return null;
      }
      // A head the server signed: what it holds there is the server's word.
      if (state.revision != invite.revision ||
          !_same(state.chain, invite.chain) ||
          !_same(gv2StateHash(state), invite.stateHash)) {
        return false;
      }
      final pending = state.pending[gv2Hex(mine)];
      return pending != null &&
          _same(
            pending.invitePub,
            Gv2SigningKey.fromSeed(invite.inviteSeed).publicKey,
          ) &&
          _same(pending.invitedBy, inviter);
    } on Gv2NetworkException {
      return null;
    } on Gv2ApiException catch (e) {
      const unreadable = {'not_a_member', 'revision_not_readable', 'group_not_found'};
      return unreadable.contains(e.code) ? false : null;
    } on Gv2ProtocolException {
      return null;
    } on Gv2CredentialException {
      return null;
    }
  }

  /// Fetch the state at the anchor of [row] and store it when it is what the
  /// anchor commits to. Returns null on success, else why not.
  Future<Gv2SyncStatus?> _loadAnchorState(
    Gv2GroupRow row,
    Uint8List headKey,
  ) async {
    final groupId = gv2Unhex(row.groupId);
    final snapshot = await _presented(
      row.masterKey,
      (p) => _transport.snapshot(groupId: groupId, presentation: p, at: row.revision),
    );
    final state = snapshot.state;
    if (state.version != row.protocolVersion ||
        !_same(state.chain, row.chain) ||
        !_same(gv2StateHash(state), row.stateHash)) {
      return Gv2SyncStatus.snapshotMismatch;
    }
    final signed = gv2VerifyHead(
      headPublicKey: headKey,
      groupId: groupId,
      revision: state.revision,
      chain: state.chain,
      headSig: snapshot.headSig,
    );
    if (!signed) return Gv2SyncStatus.badData;
    try {
      await _store.installState(state: state, headSig: snapshot.headSig);
    } on StateError {
      // The anchor's state does not have this account where the invite (or
      // the backup) said it stands.
      return Gv2SyncStatus.badData;
    }
    return null;
  }

  Future<Gv2SyncResult> _followLog(
    Gv2GroupRow row,
    Gv2GroupState start,
    Uint8List headKey,
    int startedAtMs,
  ) async {
    final groupId = gv2Unhex(row.groupId);
    var state = start;
    var membership = row.membership;
    var anchorHeadSig = row.headSig;
    final applied = <Gv2Entry>[];
    final invitedBy = <String, String>{};

    Gv2SyncResult end(Gv2SyncStatus status) => Gv2SyncResult(
          status,
          fromRevision: start.revision,
          toRevision: state.revision,
          membership: membership,
          applied: applied,
          invitedBy: invitedBy,
        );

    Future<Gv2SyncResult> freeze(Map<String, Object?> evidence) async {
      await _store.setHold(
        row.groupId,
        Gv2Hold.frozen,
        evidence: Uint8List.fromList(utf8.encode(jsonEncode(evidence))),
      );
      return end(Gv2SyncStatus.frozen);
    }

    Map<String, Object?> headJson(int revision, Uint8List chain, Uint8List? sig) => {
          'revision': revision,
          'chain': base64Encode(chain),
          'headSig': sig == null ? null : base64Encode(sig),
        };

    // Bounded: a server cannot keep this device in the loop for ever.
    for (var pages = 0; pages < 100000; pages++) {
      final page = await _presented(
        row.masterKey,
        (p) => _transport.log(
          groupId: groupId,
          presentation: p,
          from: state.revision + 1,
          limit: pageLimit,
        ),
      );

      if (page.entries.isNotEmpty) {
        final input = _PageInput(
          state: state,
          groupId: groupId,
          headKey: headKey,
          entries: page.entries,
          myCiphertext: row.myCiphertext,
          membership: membership,
          anchorHeadSig: anchorHeadSig,
        );
        final out = page.entries.length >= verifyInIsolateFrom
            ? await _verifyPageInIsolate(input)
            : _verifyPage(input);

        if (out.applied.isNotEmpty) {
          await _store.advance(
            from: state,
            to: out.state,
            headSig: out.headSig!,
            membership: out.membership,
            removalRevision: out.removalRevision,
            points: [
              for (final e in out.applied)
                Gv2LogPoint(e.revision, out.chains[e.revision]!),
            ],
          );
          state = out.state;
          membership = out.membership;
          anchorHeadSig = out.headSig;
          applied.addAll(out.applied);
          invitedBy.addAll(out.invitedBy);
        }
        switch (out.stop) {
          case _PageStop.none:
            break;
          case _PageStop.badData:
            return end(Gv2SyncStatus.badData);
          case _PageStop.updateRequired:
            await _store.setHold(row.groupId, Gv2Hold.updateRequired);
            return end(Gv2SyncStatus.updateRequired);
          case _PageStop.freeze:
            return freeze(out.evidence!);
        }
      }

      if (page.removed) break; // the log ends with this account's removal
      if (page.more) {
        // "More" with nothing in hand would loop without progress.
        if (page.entries.isEmpty) return end(Gv2SyncStatus.badData);
        continue;
      }

      final head = page.head;
      if (head == null) return end(Gv2SyncStatus.badData);
      final signed = gv2VerifyHead(
        headPublicKey: headKey,
        groupId: groupId,
        revision: head.revision,
        chain: head.chain,
        headSig: head.headSig,
      );
      if (!signed) return end(Gv2SyncStatus.badData);
      if (head.revision < state.revision) return end(Gv2SyncStatus.serverBehind);
      if (head.revision > state.revision) {
        // A head beyond what it served, while saying there is no more.
        return end(Gv2SyncStatus.badData);
      }
      if (!_same(head.chain, state.chain)) {
        final mineSigned = anchorHeadSig != null &&
            gv2VerifyHead(
              headPublicKey: headKey,
              groupId: groupId,
              revision: state.revision,
              chain: state.chain,
              headSig: anchorHeadSig,
            );
        if (!mineSigned) return end(Gv2SyncStatus.badData);
        return freeze({
          'kind': 'two_heads',
          'held': headJson(state.revision, state.chain, anchorHeadSig),
          'served': headJson(head.revision, head.chain, head.headSig),
        });
      }
      break;
    }

    if (row.hold == Gv2Hold.updateRequired) {
      await _store.setHold(row.groupId, Gv2Hold.none);
    }
    await _store.markSynced(row.groupId, startedAtMs);
    return end(applied.isEmpty ? Gv2SyncStatus.upToDate : Gv2SyncStatus.advanced);
  }

  // ---------------------------------------------------------------------------
  // Member checks
  // ---------------------------------------------------------------------------

  /// Confirm the account behind every member of [groupId] that has not been
  /// checked yet, and record which accounts the pending invites are for.
  /// Results are stored; a member is checked once per membership.
  @override
  Future<Gv2MemberCheckSummary> checkMembers(String groupId) async {
    final row = await _store.group(groupId);
    if (row == null || !row.stateLoaded) {
      return const Gv2MemberCheckSummary(0, 0);
    }
    final groupIdBytes = gv2Unhex(groupId);
    final stateKey = gv2DeriveStateKey(row.masterKey, groupIdBytes);
    var confirmed = 0;
    var unconfirmed = 0;

    while (true) {
      final batch = await _store.membersToCheck(groupId);
      if (batch.isEmpty) break;
      final input = _CheckInput(
        masterKey: row.masterKey,
        stateKey: stateKey,
        groupId: groupIdBytes,
        members: [
          for (final m in batch)
            _CheckMember(m.ciphertext, m.memberPub, m.memberPayload, m.joinedRevision),
        ],
      );
      final checked = batch.length >= checkInIsolateFrom
          ? await _checkInIsolate(input)
          : _check(input);

      final results = <Gv2MemberCheckResult>[];
      for (final r in checked) {
        var result = r;
        if (r.state == Gv2MemberCheckState.confirmed) {
          // The comparison with a key this device already confirmed for the
          // same snowId needs secure storage, so it is made here.
          final pinned = await _pinnedAccountKey(r.snowId!);
          if (pinned != null && !_same(pinned, r.accountPublicKey!)) {
            result = Gv2MemberCheckResult(
              ciphertext: r.ciphertext,
              joinedRevision: r.joinedRevision,
              state: Gv2MemberCheckState.pinnedKey,
              snowId: r.snowId,
            );
          }
        }
        results.add(result);
      }
      final applied = await _store.saveMemberChecks(groupId, results);
      for (final r in results) {
        if (r.state == Gv2MemberCheckState.confirmed) {
          confirmed++;
        } else {
          unconfirmed++;
        }
      }
      // Nothing applied means the rows changed under this run (members left
      // and joined again); the next sync's check picks them up.
      if (applied == 0) break;
    }

    final unnamed = [
      for (final p in await _store.pendingInvites(groupId))
        if (p.snowId == null) p.ciphertext,
    ];
    if (unnamed.isNotEmpty) {
      final accounts = <String, String>{};
      for (final ciphertext in unnamed) {
        try {
          accounts[ciphertext] = gv2SnowIdOfAccountId(ZkGroup.decryptMember(
              masterKey: row.masterKey, ciphertext: gv2Unhex(ciphertext)));
        } on ZkGroupException {
          // An invite to something that is not an account: it stays unnamed.
        }
      }
      await _store.savePendingAccounts(groupId, accounts);
    }
    return Gv2MemberCheckSummary(confirmed, unconfirmed);
  }

  /// Whether the title of [groupId] commits to the server keys this device
  /// holds. Null when the title does not open (or the group is unknown). A
  /// mismatch means the group was created under other server keys than the
  /// ones this device was given.
  Future<bool?> titleMatchesServerKeys(String groupId) async {
    final row = await _store.group(groupId);
    if (row == null || !row.stateLoaded) return null;
    final title = gv2OpenTitlePayload(
        gv2DeriveStateKey(row.masterKey, gv2Unhex(groupId)), row.titlePayload);
    if (title == null) return null;
    final keys = await _credentials.serverKeys();
    return _same(
      title.serverKeyHash,
      gv2ServerKeyHash(
        serverPublicParams: keys.serverPublicParams,
        headPublicKey: keys.headPublicKey,
      ),
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

// -----------------------------------------------------------------------------
// Page verification (pure; runs inline or in a worker isolate)
// -----------------------------------------------------------------------------

enum _PageStop { none, badData, updateRequired, freeze }

class _PageInput {
  final Gv2GroupState state;
  final Uint8List groupId;
  final Uint8List headKey;
  final List<Gv2LogEntry> entries;
  final String myCiphertext;
  final Gv2Membership membership;

  /// The server's signature over the head of [state], when this device has it.
  final Uint8List? anchorHeadSig;

  const _PageInput({
    required this.state,
    required this.groupId,
    required this.headKey,
    required this.entries,
    required this.myCiphertext,
    required this.membership,
    required this.anchorHeadSig,
  });
}

class _PageOutput {
  /// The state after the verified entries (the input state when none).
  final Gv2GroupState state;
  final List<Gv2Entry> applied;
  final Gv2Membership membership;

  /// Server signature over the head of [state]; set when [applied] is not
  /// empty.
  final Uint8List? headSig;
  final int? removalRevision;

  /// The chain after each applied entry, by revision.
  final Map<int, Uint8List> chains;

  /// Joiner → inviter (ciphertexts, hex) for the ACCEPTs in [applied].
  final Map<String, String> invitedBy;

  /// Why verification stopped before the end of the page.
  final _PageStop stop;
  final Map<String, Object?>? evidence;

  const _PageOutput({
    required this.state,
    required this.applied,
    required this.membership,
    required this.headSig,
    required this.removalRevision,
    required this.stop,
    this.chains = const {},
    this.invitedBy = const {},
    this.evidence,
  });
}

Future<_PageOutput> _verifyPageInIsolate(_PageInput input) =>
    Isolate.run(() => _verifyPage(input));

_PageOutput _verifyPage(_PageInput input) {
  var state = input.state;
  var membership = input.membership;
  int? removalRevision;
  final applied = <Gv2Entry>[];
  // Heads of the entries applied so far, to find the last SIGNED point.
  final heads = <Uint8List>[];
  final states = <Gv2GroupState>[];
  final standings = <Gv2Membership>[];
  final removals = <int?>[];
  // For each applied entry: the joiner and its inviter when it is an ACCEPT
  // (read from the pending invite before the entry removes it).
  final joins = <(String, String)?>[];

  var stop = _PageStop.none;
  Map<String, Object?>? evidence;

  bool signed(int revision, Uint8List chain, Uint8List sig) => gv2VerifyHead(
        headPublicKey: input.headKey,
        groupId: input.groupId,
        revision: revision,
        chain: chain,
        headSig: sig,
      );

  Map<String, Object?> headJson(int revision, Uint8List chain, Uint8List? sig) => {
        'revision': revision,
        'chain': base64Encode(chain),
        'headSig': sig == null ? null : base64Encode(sig),
      };

  for (final served in input.entries) {
    final Gv2Entry entry;
    try {
      entry = gv2DecodeEntry(served.entry);
    } on Gv2DecodeException {
      // The first byte is the protocol version: a later one means this build
      // is too old to read the entry, not that the entry is wrong.
      stop = served.entry.isNotEmpty && served.entry[0] > gv2ProtocolVersion
          ? _PageStop.updateRequired
          : _PageStop.badData;
      break;
    }

    try {
      final actor = gv2Hex(entry.actor);
      final invite = entry.actions.any((a) => a is Gv2Accept)
          ? state.pending[actor]
          : null;
      final next = gv2ApplyEntry(state, input.groupId, entry);
      membership = gv2StandingAfter(
        before: membership,
        myCiphertext: input.myCiphertext,
        entry: entry,
        after: next,
      );
      if (entry.actions.any((a) => a is Gv2Remove || a is Gv2Leave)) {
        removalRevision = entry.revision;
      }
      state = next;
      applied.add(entry);
      heads.add(served.headSig);
      states.add(next);
      standings.add(membership);
      removals.add(removalRevision);
      joins.add(invite == null ? null : (actor, gv2Hex(invite.invitedBy)));
    } on Gv2Reject catch (reject) {
      if (reject.code == Gv2RejectCode.version) {
        stop = entry.version > gv2ProtocolVersion
            ? _PageStop.updateRequired
            : _PageStop.badData;
        break;
      }
      stop = _PageStop.badData;
      // Is this the server's doing? Only its own signature can say so.
      final Uint8List chain;
      try {
        chain = gv2ChainHash(
          entry.prevChain,
          gv2SignedBytes(input.groupId, entry, entry.stateHashAfter),
          entry.sig,
        );
      } on Gv2DecodeException {
        break;
      }
      if (entry.revision != state.revision + 1 ||
          !signed(entry.revision, chain, served.headSig)) {
        break;
      }
      final heldSig = heads.isEmpty ? input.anchorHeadSig : heads.last;
      final served_ = {
        ...headJson(entry.revision, chain, served.headSig),
        'entry': base64Encode(served.entry),
      };
      if (_same(entry.prevChain, state.chain)) {
        // It extends the chain this device holds, the rules refuse it, and
        // the server signed it.
        stop = _PageStop.freeze;
        evidence = {
          'kind': 'invalid_entry',
          'reject': reject.code.wire,
          'held': headJson(state.revision, state.chain, heldSig),
          'served': served_,
        };
      } else if (heldSig != null && signed(state.revision, state.chain, heldSig)) {
        // The server signed the head this device holds AND an entry that
        // continues some other chain at the same height.
        stop = _PageStop.freeze;
        evidence = {
          'kind': 'fork',
          'held': headJson(state.revision, state.chain, heldSig),
          'served': served_,
        };
      }
      break;
    }
  }

  // Keep only up to the last entry whose head the server signed.
  var keep = applied.length;
  while (keep > 0 &&
      !signed(states[keep - 1].revision, states[keep - 1].chain, heads[keep - 1])) {
    keep--;
  }
  if (keep < applied.length && stop == _PageStop.none) {
    stop = _PageStop.badData;
  }
  if (keep == 0) {
    return _PageOutput(
      state: input.state,
      applied: const [],
      membership: input.membership,
      headSig: null,
      removalRevision: null,
      stop: stop,
      evidence: evidence,
    );
  }
  return _PageOutput(
    state: states[keep - 1],
    applied: applied.sublist(0, keep),
    membership: standings[keep - 1],
    headSig: heads[keep - 1],
    removalRevision: removals[keep - 1],
    stop: stop,
    chains: {for (final s in states.sublist(0, keep)) s.revision: s.chain},
    invitedBy: {
      for (final j in joins.sublist(0, keep))
        if (j != null) j.$1: j.$2,
    },
    evidence: evidence,
  );
}

// -----------------------------------------------------------------------------
// Member checks (pure; runs inline or in a worker isolate)
// -----------------------------------------------------------------------------

class _CheckMember {
  final String ciphertext;
  final Uint8List memberPub;
  final Uint8List memberPayload;
  final int joinedRevision;
  const _CheckMember(
      this.ciphertext, this.memberPub, this.memberPayload, this.joinedRevision);
}

class _CheckInput {
  final Uint8List masterKey;
  final Uint8List stateKey;
  final Uint8List groupId;
  final List<_CheckMember> members;
  const _CheckInput({
    required this.masterKey,
    required this.stateKey,
    required this.groupId,
    required this.members,
  });
}

Future<List<Gv2MemberCheckResult>> _checkInIsolate(_CheckInput input) =>
    Isolate.run(() => _check(input));

List<Gv2MemberCheckResult> _check(_CheckInput input) {
  final out = <Gv2MemberCheckResult>[];
  for (final m in input.members) {
    final Uint8List accountId;
    try {
      accountId = ZkGroup.decryptMember(
          masterKey: input.masterKey, ciphertext: gv2Unhex(m.ciphertext));
    } on ZkGroupException {
      out.add(Gv2MemberCheckResult(
        ciphertext: m.ciphertext,
        joinedRevision: m.joinedRevision,
        state: Gv2MemberCheckState.ciphertext,
      ));
      continue;
    }
    final check = gv2CheckMember(
      stateKey: input.stateKey,
      groupId: input.groupId,
      accountId: accountId,
      member: Gv2MemberState(
        role: gv2RoleMember,
        memberPub: m.memberPub,
        joinedRevision: m.joinedRevision,
        memberPayload: m.memberPayload,
      ),
    );
    final snowId = gv2SnowIdOfAccountId(accountId);
    final confirmed = check.member;
    if (confirmed != null) {
      out.add(Gv2MemberCheckResult(
        ciphertext: m.ciphertext,
        joinedRevision: m.joinedRevision,
        state: Gv2MemberCheckState.confirmed,
        snowId: snowId,
        accountPublicKey: confirmed.accountPublicKey,
        certIssuedAtMs: confirmed.issuedAtMs,
      ));
      continue;
    }
    out.add(Gv2MemberCheckResult(
      ciphertext: m.ciphertext,
      joinedRevision: m.joinedRevision,
      state: switch (check.failure!) {
        Gv2MemberCheckFailure.payload => Gv2MemberCheckState.payload,
        Gv2MemberCheckFailure.accountId => Gv2MemberCheckState.accountId,
        Gv2MemberCheckFailure.pinnedKey => Gv2MemberCheckState.pinnedKey,
        Gv2MemberCheckFailure.certificate => Gv2MemberCheckState.certificate,
      },
      snowId: snowId,
    ));
  }
  return out;
}
