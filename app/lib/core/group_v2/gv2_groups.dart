/// @file        gv2_groups.dart
/// @description Group protocol v2 — what this account does to groups:
///              create one, invite an account, take an invite in, accept it
///              or decline it (design document §9.1, §9.2). Every change is
///              an entry this device signs, the server accepts and signs the
///              head of, and this device then stores; an invite is a 1:1
///              message whose claims are checked against the server's log
///              before anything is kept.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (X1: an invite from a blocked account is dropped — isBlocked; P5.6: an invite to a group this account left replaces its record only once the server's log bears it out — checked first (inviteInLog); one that cannot be checked waits in the inbox; removeMember() / revokePending() by ciphertext — a member or invite whose ciphertext names no account can be taken out; the owner's successor is never a deleted account; the changes of one group are made one after the other — two at once cleared each other's mark of an unanswered change; an invite row is dropped as not in the log only when no change of this device is unanswered, not on a recent sync; remove() drains the group's lane first — design §7.4; P5.6: inviteMany — up to 64 invites in one change; a 429 is rateLimited, not unavailable; checkLeave(); P5.6: no automatic accept — every invite waits for the user; an invite holds only when the log names its sender as the inviter; a malformed answer no longer refutes an invite). Earlier 2026-11-21 (a group holds at most gv2GroupSizeLimit = 256 accounts in this build — create() and invite() refuse more with Gv2GroupFailure.full; a refusal read from the stored state that a newer log could lift — full, already there — is checked again once after catching up). Earlier 2026-11-20 (a change whose answer never came: marked before it is sent, settled from the log — _settleUnanswered()). Earlier 2026-11-20
///
/// @functions
///  - Gv2GroupActions.create(): make a group (and invite accounts into it)
///  - Gv2GroupActions.invite() / inviteMany(): invite accounts into a group
///    (up to gv2MaxChangeActions in one change)
///  - Gv2GroupActions.checkLeave(): whether leaving can be made now
///  - Gv2GroupActions.takeInvite(): an invite row of the inbox (kept by the
///    1:1 queue): keep it, then settle it
///  - Gv2GroupActions.receiveInvite(): a 1:1 invite message arrived —
///    keepInvite() (this device only: store it) then settleInvite() (check
///    it against the server's log, accept it when the app says so)
///  - Gv2GroupActions.resume(): settle the invites never checked, and
///    bring the groups taken from the backup into use
///  - Gv2GroupActions.accept() / decline(): answer an invite
///  - Gv2GroupActions.remove() / leave() / setRole() / transferOwner() /
///    setTitle() / revokeInvite() / end(): the other changes
///  - Gv2GroupActions.removeDeleted(): take out a member whose account
///    proved itself deleted
///  - Gv2GroupActions.leaveAll(): leave every group (before the account is
///    deleted)
///  - Gv2GroupActions.refreshNames(): look up the members' display names
///  - Gv2GroupActions.run() / gaveUp(): the outbox rows of the create request and
///    of the 1:1 invite messages (Gv2OutboxActions)
///  - Gv2GroupException / Gv2GroupFailure: why something could not be done
///  - Gv2InviteOutcome: what became of a received invite
///
/// Notes:
///  - Creating: the revision-0 entry is signed first and stored — with the
///    group row (standing "creating") and the invites — in one transaction;
///    the outbox then submits it until the server is known to have it. The
///    answer to a create request can be lost: the same entry is submitted
///    again, and a server that already has the group is asked for its state
///    at revision 0, which must be the one stored here. Nothing is sent to
///    anyone before the server's signature on the head is verified.
///  - A change (INVITE, ACCEPT, DECLINE) is built on the stored state,
///    submitted, and stored only with the server's signed head over exactly
///    the chain this device computed. When the server is ahead (409) this
///    device catches up through the inbox lane, waits a random moment —
///    several invitees accept at once — and builds the change again. A
///    refusal the stored state gives that a newer log could lift (the group
///    full, the account already in it) is given only after catching up
///    once: the stored state may be behind a decline or a leave.
///  - Before a change goes out the group is marked (Gv2Groups.changeSentAtMs)
///    and the mark is cleared by the answer. When the answer is lost the log
///    is fetched: the change counts as made when the log holds it, is built
///    again when it does not, and when the log cannot be read the mark stays
///    — a message syncs before it goes while it stands, so a removal the
///    server took but this device never heard of cannot leave the removed
///    member on the roster of the next message (P5.2).
///  - The invite key: made here, its public half in the INVITE entry, its
///    seed in the outbox row of the 1:1 message. The row is written BEFORE
///    the entry is submitted and held back for a while, so a crash between
///    the server accepting the INVITE and this device storing it loses
///    nothing: when the row comes due it looks at the log and goes out if
///    the invite is there under its key, and is dropped if it is not.
///  - The 1:1 invite message carries the head of the moment it is sent (any
///    verified point at which the invitee is pending serves as its anchor).
///  - A received invite is believed only as far as the server's log bears
///    it out: the state at its anchor must hash to the hash it states and
///    hold this account as pending under the invite key. An invite that
///    fails this is deleted; one that cannot be checked now (offline) is
///    kept and checked again later (resume) or when it is accepted. An
///    invite never replaces the anchor of a group this device already takes
///    part in (design §5.5). A second invite to a group whose first invite
///    is still waiting takes its place only when the log no longer bears
///    the first one out (it was taken back and made again); until that is
///    known it is held in memory only.
///  - Nothing is accepted on its own: every invite waits for the user
///    (Gv2Membership.invited — P5.6, owner 2026-11-21). The conditions an
///    automatic accept stood on (a bound identity, the server's friend list)
///    were both the server's to make.
///  - An invite holds only when the log names its sender as the inviter
///    (the pending entry's `invitedBy` is the sender's member ciphertext):
///    an invite passed on by someone else is not that someone's invite.
///  - A change that takes a member out (REMOVE), or this account itself
///    (LEAVE, DELETE_GROUP), is told to those it concerns in the moment the
///    server accepted it — with the endorsements held from before, which
///    storing the change erases. Best effort: who is not reached learns it
///    from the log. Everyone else gets the ordinary change notice.
///  - Roles and ownership go only to accounts this device has confirmed,
///    and an owner that leaves hands the group to the confirmed member who
///    joined first (design §5.6, §9.7).
///  - After ACCEPT this account is a member by the log but sends nothing
///    until a confirmed member confirms the head (gv2_pairwise_service):
///    the change notice sent here is what makes the members look.
///  - A group taken from the backup (a reinstall; Gv2GroupRow.resetPending)
///    is believed like an invite: its state is fetched at the backup's
///    anchor and its log followed. A server that says this account may not
///    read it, or whose state at the anchor is not the one the backup
///    commits to, has the group dropped. Once the head is reached this
///    device tells the group that its Sender Keys are gone (member_reset):
///    the members give it their keys again and one of them confirms the
///    head — until then it sends nothing (design §9.8).
///  - Nothing here logs: master keys, invite keys, groups and members.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';

import '../crypto/identity_binding.dart';
import '../storage/database.dart';
import '../storage/tables/gv2_tables.dart';
import 'gv2_codec.dart';
import 'gv2_credentials.dart';
import 'gv2_envelope.dart';
import 'gv2_inbox.dart';
import 'gv2_invite.dart';
import 'gv2_keys.dart';
import 'gv2_messaging.dart';
import 'gv2_outbox.dart';
import 'gv2_payloads.dart';
import 'gv2_state_machine.dart';
import 'gv2_store.dart';
import 'gv2_sync.dart';
import 'gv2_transport.dart';

/// Invite messages taken in from one sender, at most this many an hour.
const int gv2InvitesPerSenderPerHour = 10;

/// A group taken from the backup whose log could not be followed (the
/// server answered, but not with what this device can use) is looked at
/// again after this long.
const Duration gv2RestoreRetry = Duration(minutes: 10);

/// How long the outbox row of an invite is held back while its INVITE
/// entry is being submitted.
const Duration gv2InviteReserve = Duration(minutes: 10);

/// Attempts at a change when the server keeps being ahead.
const int gv2ChangeAttempts = 6;

/// How many accounts a group holds in this build: members and pending
/// invites, the creator counted. The protocol allows [gv2MaxGroupSize]
/// (1,024), but at that size the per-invite identity and prekey lookups,
/// the server's per-IP limits on v2 changes, the per-recipient inflow limit
/// and the creation work on the UI thread are not measured yet (P5.5).
const int gv2GroupSizeLimit = 256;

/// Why something could not be done.
enum Gv2GroupFailure {
  /// This account may not do this in the group as it stands (not a member,
  /// not confirmed, the group on hold, not invited).
  notAllowed,

  /// The account is already a member or already invited.
  alreadyThere,

  /// The account is not a member (or has no invite waiting).
  notThere,

  /// An owner cannot leave a group that has members but none whose account
  /// is confirmed: there is nobody to hand the group to.
  noSuccessor,

  /// The invite is no longer there (revoked, used, or never real).
  inviteGone,

  /// The rules of the change log refuse the change ([Gv2GroupException.code]).
  rejected,

  /// The group would hold more than [gv2GroupSizeLimit] accounts.
  full,

  /// The server asks to slow down (too many changes in a while).
  rateLimited,

  /// The server could not be reached, or answered with an error.
  unavailable,

  /// The server kept moving ahead; try again.
  busy,

  /// The server answered with something that does not verify.
  untrusted,
}

class Gv2GroupException implements Exception {
  final Gv2GroupFailure reason;

  /// With [Gv2GroupFailure.rejected]: the reject code.
  final String? code;
  const Gv2GroupException(this.reason, [this.code]);

  @override
  String toString() => 'Gv2GroupException(${reason.name})';
}

/// What became of a received invite.
enum Gv2InviteOutcome {
  /// Not kept: malformed, not borne out by the server's log, from a sender
  /// over its limit, or for a group this device already takes part in.
  ignored,

  /// Kept, waiting for the user (or for a later check when offline).
  stored,
}

/// Thrown by the builder of a change: [failure], read from the stored
/// state, which a newer log could lift. The change is built again after
/// catching up once; the failure stands when it is still there.
class _UnlessBehind implements Exception {
  final Gv2GroupFailure failure;
  const _UnlessBehind(this.failure);
}

/// What one change consists of.
class _Change {
  final List<Gv2Action> actions;
  final Gv2SigningKey key;
  final Uint8List? memberPayload;
  final Uint8List? titlePayload;

  /// Member ciphertexts (lowercase hex) that are told of the change at
  /// once, with the endorsements this device holds from before it: the
  /// members the change takes out — afterwards this device can no longer
  /// address them — and, when this account itself goes, everyone.
  final List<String> tell;
  const _Change(
    this.actions,
    this.key, {
    this.memberPayload,
    this.titlePayload,
    this.tell = const [],
  });
}

class Gv2GroupActions implements Gv2OutboxActions {
  final Gv2Store _groups;
  final Gv2OutboxStore _outbox;
  final Gv2Transport _transport;
  final Gv2Credentials _credentials;
  final Gv2LogSync _sync;
  final Gv2Inbox _inbox;
  final Gv2Messaging _messaging;
  final Gv2MessageSink _sink;
  final String _me;
  final Future<Uint8List> Function() _accountPublicKey;
  final Future<Gv2SigningKey> Function(Uint8List groupId) _memberKey;
  final Future<Uint8List> Function(Uint8List groupId, int issuedAtMs)
  _memberCert;
  final Future<bool> Function(String recipient, Uint8List invite) _sendInvite;
  final Gv2SendTokens? _tokens;
  final Gv2OutboxSend? _send;
  final Future<String> Function()? _myDeviceId;
  final void Function() _queued;
  final int Function() _nowMs;
  final Random _random;
  final Future<void> Function(Duration) _sleep;

  final Map<String, List<int>> _invitesFrom = {};

  /// Groups taken from the backup that are not looked at again before the
  /// given time.
  final Map<String, int> _restoreRetryAtMs = {};

  /// An invite that arrived while an earlier one to the same group was
  /// waiting, with its sender: looked at by [settleInvite].
  final Map<String, (String, Gv2InviteMessage)> _superseding = {};

  /// [mySnowId] is this device's account; [accountPublicKey] its 32-byte
  /// account key, [memberKey] its member signing key for a group and
  /// [memberCert] the account key's certificate for that member key
  /// (IdentityManager). [sendInvite] sends the bytes of an invite message
  /// to an account over the 1:1 sealed path and returns whether the server
  /// took it. [tokens], [send] and [myDeviceId]
  /// (the outbox's) let this device tell members directly of a change that
  /// takes them out, and look up display names; without them neither
  /// happens. [onQueued] is called after something was queued and committed
  /// (the app flushes the outbox).
  Gv2GroupActions({
    required Gv2Store groups,
    required Gv2OutboxStore outbox,
    required Gv2Transport transport,
    required Gv2Credentials credentials,
    required Gv2LogSync sync,
    required Gv2Inbox inbox,
    required Gv2Messaging messaging,
    required Gv2MessageSink sink,
    required String mySnowId,
    required Future<Uint8List> Function() accountPublicKey,
    required Future<Gv2SigningKey> Function(Uint8List groupId) memberKey,
    required Future<Uint8List> Function(Uint8List groupId, int issuedAtMs)
    memberCert,
    required Future<bool> Function(String recipient, Uint8List invite)
    sendInvite,
    Gv2SendTokens? tokens,
    Gv2OutboxSend? send,
    Future<String> Function()? myDeviceId,
    void Function()? onQueued,
    int Function()? nowMs,
    Random? random,
    Future<void> Function(Duration)? sleep,
    Future<bool> Function(String snowId)? isBlocked,
  }) : _groups = groups,
       _outbox = outbox,
       _transport = transport,
       _credentials = credentials,
       _sync = sync,
       _inbox = inbox,
       _messaging = messaging,
       _sink = sink,
       _me = mySnowId,
       _accountPublicKey = accountPublicKey,
       _memberKey = memberKey,
       _memberCert = memberCert,
       _sendInvite = sendInvite,
       _tokens = tokens,
       _send = send,
       _myDeviceId = myDeviceId,
       _queued = onQueued ?? (() {}),
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _random = random ?? Random.secure(),
       _sleep = sleep ?? Future<void>.delayed,
       _isBlocked = isBlocked ?? ((_) async => false);

  /// X1: whether an account is blocked. An invite it sent — kept before the
  /// block (an invite row of the inbox) — is dropped, not taken in.
  final Future<bool> Function(String snowId) _isBlocked;

  // ---------------------------------------------------------------------------
  // Creating
  // ---------------------------------------------------------------------------

  /// Make a group named [title], with [invite] (snowIds) invited. Returns
  /// its id (lowercase hex) once the group is stored on this device; the
  /// server is told by the outbox, and the group becomes usable
  /// (Gv2Membership.active) when the server has signed its head.
  ///
  /// Throws [Gv2GroupException]: `full` when the creator and [invite] are
  /// more than [gv2GroupSizeLimit]; `unavailable` when the server's keys
  /// cannot be fetched (the group's title commits to them).
  Future<String> create({
    required String title,
    List<String> invite = const [],
  }) async {
    final invitees = <String>{};
    for (final snowId in invite) {
      if (!IdentityBindingV1.isValidSnowId(snowId)) {
        throw ArgumentError('gv2 groups: not a snowId');
      }
      if (snowId != _me) invitees.add(snowId);
    }
    if (invitees.length + 1 > gv2GroupSizeLimit) {
      throw const Gv2GroupException(Gv2GroupFailure.full);
    }
    final Gv2ServerKeysRow keys;
    try {
      keys = await _credentials.serverKeys();
    } on Gv2NetworkException {
      throw const Gv2GroupException(Gv2GroupFailure.unavailable);
    } on Gv2ApiException {
      throw const Gv2GroupException(Gv2GroupFailure.unavailable);
    }

    final masterKey = gv2NewMasterKey();
    final groupId = ZkGroup.groupParams(masterKey).groupId;
    final id = gv2Hex(groupId);
    final memberKey = await _memberKey(groupId);
    final mine = _ciphertext(masterKey, _me);
    final inviteKeys = {
      for (final snowId in invitees) snowId: Gv2SigningKey.generate(),
    };
    final signed = gv2SignEntry(
      state: null,
      groupId: groupId,
      draft: Gv2EntryDraft(
        version: gv2ProtocolVersion,
        revision: 0,
        prevChain: gv2GenesisPrevChain(),
        actor: mine,
        actions: [
          Gv2Create(memberKey.publicKey),
          for (final e in inviteKeys.entries)
            Gv2Invite(_ciphertext(masterKey, e.key), e.value.publicKey),
        ],
        memberPayload: await _memberPayload(masterKey, groupId),
        titlePayload: gv2SealTitlePayload(
          gv2DeriveStateKey(masterKey, groupId),
          Gv2TitlePayload(
            name: title,
            serverKeyHash: gv2ServerKeyHash(
              serverPublicParams: keys.serverPublicParams,
              headPublicKey: keys.headPublicKey,
            ),
          ),
        ),
      ),
      key: memberKey,
    );

    final now = _nowMs();
    await _groups.transaction(() async {
      await _groups.insertCreating(
        masterKey: masterKey,
        myCiphertext: mine,
        state: signed.next,
      );
      await _outbox.enqueueCreate(
        groupId: id,
        entry: gv2EncodeEntry(signed.entry),
        nowMs: now,
      );
      for (final e in inviteKeys.entries) {
        await _outbox.enqueueInvite(
          groupId: id,
          recipient: e.key,
          inviteSeed: e.value.seed,
          nowMs: now,
        );
      }
    });
    _inbox.groupsChanged();
    _queued();
    return id;
  }

  // ---------------------------------------------------------------------------
  // Inviting
  // ---------------------------------------------------------------------------

  /// Invite [snowId] into [groupId]. Returns once the server accepted the
  /// INVITE; the 1:1 invite message goes out through the outbox.
  ///
  /// Throws [Gv2GroupException]: `alreadyThere` (a member or invited) and
  /// `full` ([gv2GroupSizeLimit]) after the stored state was brought up to
  /// the server's head; `unavailable` when it could not be.
  Future<void> invite(String groupId, String snowId) async {
    await inviteMany(groupId, [snowId]);
  }

  /// Invite [snowIds] (at most [gv2MaxChangeActions]) into [groupId] in ONE
  /// change — a change per account met the server's budget of changes per
  /// member (thirty a minute) long before a roster was invited. Accounts
  /// already in the group or invited are left out. Returns how many were
  /// invited. The 1:1 invite messages go out through the outbox.
  ///
  /// Throws [Gv2GroupException]: `alreadyThere` when every account is
  /// already there, `full` when they do not all fit ([gv2GroupSizeLimit]) —
  /// both after the stored state was brought up to the server's head;
  /// `rateLimited` when the server asks to slow down; `unavailable`.
  Future<int> inviteMany(String groupId, List<String> snowIds) async {
    final accounts = <String>{};
    for (final snowId in snowIds) {
      if (!IdentityBindingV1.isValidSnowId(snowId) || snowId == _me) {
        throw ArgumentError('gv2 groups: not an account to invite');
      }
      accounts.add(snowId);
    }
    if (accounts.isEmpty || accounts.length > gv2MaxChangeActions) {
      throw ArgumentError('gv2 groups: 1 to $gv2MaxChangeActions accounts');
    }
    final group = await _groups.group(groupId);
    if (group == null ||
        group.membership != Gv2Membership.active ||
        group.hold != Gv2Hold.none) {
      throw const Gv2GroupException(Gv2GroupFailure.notAllowed);
    }
    final now = _nowMs();
    final targets = <String, (Uint8List, Gv2SigningKey, int)>{};
    for (final snowId in accounts) {
      final inviteKey = Gv2SigningKey.generate();
      // The invite key is on disk before the server can know its public half.
      final rowId = await _outbox.enqueueInvite(
        groupId: groupId,
        recipient: snowId,
        inviteSeed: inviteKey.seed,
        nowMs: now,
        notBeforeMs: now + gv2InviteReserve.inMilliseconds,
      );
      targets[snowId] = (_ciphertext(group.masterKey, snowId), inviteKey, rowId);
    }
    // The accounts of the change that was made (the last one built).
    var invited = <String>[];
    try {
      final memberKey = await _memberKey(gv2Unhex(groupId));
      await _submit(groupId, (row, state) async {
        if (row.membership != Gv2Membership.active ||
            row.hold != Gv2Hold.none) {
          throw const Gv2GroupException(Gv2GroupFailure.notAllowed);
        }
        invited = [
          for (final e in targets.entries)
            if (!state.members.containsKey(gv2Hex(e.value.$1)) &&
                !state.pending.containsKey(gv2Hex(e.value.$1)))
              e.key,
        ];
        if (invited.isEmpty) {
          throw const _UnlessBehind(Gv2GroupFailure.alreadyThere);
        }
        if (state.members.length + state.pending.length + invited.length >
            gv2GroupSizeLimit) {
          throw const _UnlessBehind(Gv2GroupFailure.full);
        }
        return _Change([
          for (final snowId in invited)
            Gv2Invite(targets[snowId]!.$1, targets[snowId]!.$2.publicKey),
        ], memberKey);
      });
    } on Gv2GroupException catch (e) {
      // Whether the server took the entry is known only for these: the rows
      // of any other failure stay, and decide by the log when they are due.
      const settled = {
        Gv2GroupFailure.notAllowed,
        Gv2GroupFailure.alreadyThere,
        Gv2GroupFailure.full,
        Gv2GroupFailure.rejected,
        Gv2GroupFailure.rateLimited,
      };
      if (settled.contains(e.reason)) {
        for (final t in targets.values) {
          await _outbox.remove(t.$3);
        }
      }
      rethrow;
    }
    for (final e in targets.entries) {
      if (invited.contains(e.key)) {
        await _outbox.release(e.value.$3);
      } else {
        await _outbox.remove(e.value.$3); // already there: no invite
      }
    }
    _queued();
    return invited.length;
  }

  // ---------------------------------------------------------------------------
  // Being invited
  // ---------------------------------------------------------------------------

  /// A 1:1 invite message from [fromSnowId] (the sender its sealed envelope
  /// certified) with the bytes [invite]: [keepInvite], then [settleInvite].
  /// Never throws for what a sender or a server can cause.
  Future<Gv2InviteOutcome> receiveInvite(
    String fromSnowId,
    Uint8List invite,
  ) async {
    final groupId = await keepInvite(fromSnowId, invite);
    return groupId == null
        ? Gv2InviteOutcome.ignored
        : settleInvite(groupId);
  }

  /// An invite row of the inbox (kept by the 1:1 queue): kept now, and once
  /// the row is finished, [settleInvite] — which talks to the server —
  /// without holding up the inbox lane. An invite to a group this account
  /// left that could not be checked yet waits in the inbox (the row stays;
  /// it is looked at again with the group's sync-wait retries).
  Future<Gv2InboxOutcome> takeInvite(String fromSnowId, Uint8List invite) async {
    return switch (await _keep(fromSnowId, invite)) {
      _KeepStored(:final groupId) => Gv2Handled(
          afterCommit: () => unawaited(settleInvite(groupId)),
        ),
      _KeepLater(:final groupId) => Gv2WaitForSync(groupId: groupId),
      _KeepNothing() => const Gv2Handled(),
    };
  }

  /// The part of taking an invite in that touches only this device: check
  /// its form and store it. Returns the group id when there is something to
  /// settle ([settleInvite] — which talks to the server and must not hold
  /// up whoever delivered the message), else null. Once this returns the
  /// invite is on disk: the 1:1 message that carried it can be acknowledged.
  /// (An invite to a group this account left is first checked against the
  /// server's log — see [takeInvite]; here one that cannot be checked now
  /// is not kept.)
  Future<String?> keepInvite(String fromSnowId, Uint8List invite) async =>
      switch (await _keep(fromSnowId, invite)) {
        _KeepStored(:final groupId) => groupId,
        _ => null,
      };

  /// Invites counted against their sender's hourly budget (by digest): one
  /// looked at again — it waited for a check — is not counted twice.
  final Set<String> _invitesCounted = {};

  Future<_Keep> _keep(String fromSnowId, Uint8List invite) async {
    if (!IdentityBindingV1.isValidSnowId(fromSnowId) || fromSnowId == _me) {
      return const _KeepNothing();
    }
    // X1: from an account this user blocked — dropped.
    if (await _isBlocked(fromSnowId)) return const _KeepNothing();
    final digest = gv2Hex(Uint8List.fromList(hash.sha256.convert(invite).bytes));
    if (!_invitesCounted.contains(digest)) {
      if (!_under(
        _invitesFrom.putIfAbsent(fromSnowId, () => []),
        gv2InvitesPerSenderPerHour,
      )) {
        return const _KeepNothing();
      }
      if (_invitesCounted.length > 4096) _invitesCounted.clear();
      _invitesCounted.add(digest);
    }
    final message = Gv2InviteMessage.decode(invite);
    if (message == null) return const _KeepNothing();
    // The group id is whatever the master key gives; a message stating
    // another is not an invite.
    final Uint8List groupId;
    try {
      groupId = ZkGroup.groupParams(message.masterKey).groupId;
    } on ZkGroupException {
      return const _KeepNothing();
    }
    if (!_same(groupId, message.groupId)) return const _KeepNothing();
    final id = gv2Hex(groupId);
    try {
      final existing = await _groups.group(id);
      if (existing != null && existing.membership == Gv2Membership.invited) {
        // An earlier invite waits here. Whether it still holds only the
        // server's log can say: the new one is kept aside until then.
        _superseding[id] = (fromSnowId, message);
        return _KeepStored(id);
      }
      const rejoinable = {
        Gv2Membership.left,
        Gv2Membership.removed,
        Gv2Membership.declined,
      };
      if (existing != null && rejoinable.contains(existing.membership)) {
        // The record of a group this account left goes only for an invite
        // the server's log bears out — checked first. (Replaced first and
        // checked after, a made-up invite from anyone who holds the master
        // key erased it.)
        if (message.revision <= existing.revision) return const _KeepNothing();
        final held = await _sync.inviteInLog(
          invite: message,
          inviter: _ciphertext(message.masterKey, fromSnowId),
          mine: _ciphertext(message.masterKey, _me),
        );
        if (held == null) return _KeepLater(id);
        if (!held) return const _KeepNothing();
      }
      return await _storeInvite(fromSnowId, message)
          ? _KeepStored(id)
          : const _KeepNothing();
    } on Gv2StoreConflict {
      return const _KeepNothing();
    } on ZkGroupException {
      return const _KeepNothing();
    }
  }

  /// Store [message] as the invite to its group: a group this device does
  /// not hold, or one this account left, was removed from or declined (then
  /// only from a later point of its log). Anything else is not touched.
  Future<bool> _storeInvite(String from, Gv2InviteMessage message) async {
    final id = gv2Hex(message.groupId);
    final stored = await _groups.group(id) == null
        ? await _groups.insertAnchored(
            groupId: message.groupId,
            masterKey: message.masterKey,
            myCiphertext: _ciphertext(message.masterKey, _me),
            protocolVersion: gv2ProtocolVersion,
            revision: message.revision,
            chain: message.chain,
            stateHash: message.stateHash,
            membership: Gv2Membership.invited,
            inviteSeed: message.inviteSeed,
            invitedBySnowId: from,
          )
        : await _groups.reinvite(
            groupId: id,
            protocolVersion: gv2ProtocolVersion,
            revision: message.revision,
            chain: message.chain,
            stateHash: message.stateHash,
            inviteSeed: message.inviteSeed,
            invitedBySnowId: from,
          );
    if (stored) _inbox.groupsChanged();
    return stored;
  }

  /// Check the invite stored for [groupId] against the server's log, forget
  /// it when the log does not bear it out, and accept it when the app says
  /// its inviter's invites are accepted without asking. Never throws for
  /// what a sender or a server can cause.
  Future<Gv2InviteOutcome> settleInvite(String groupId) async {
    try {
      var holds = await _inviteHolds(groupId);
      final newer = _superseding.remove(groupId);
      if (newer != null) {
        // A second invite arrived while one was waiting: it takes the
        // place of the first only when the first no longer holds.
        if (holds != false) {
          return await _groups.group(groupId) == null
              ? Gv2InviteOutcome.ignored
              : Gv2InviteOutcome.stored;
        }
        await _forget(groupId);
        if (!await _storeInvite(newer.$1, newer.$2)) {
          return Gv2InviteOutcome.ignored;
        }
        holds = await _inviteHolds(groupId);
      }
      if (holds == false) {
        await _forget(groupId);
        return Gv2InviteOutcome.ignored;
      }
      final row = await _groups.group(groupId);
      if (row == null) return Gv2InviteOutcome.ignored;
      if (row.membership != Gv2Membership.invited) {
        return Gv2InviteOutcome.stored;
      }
      _notify(groupId, const []);
      return await _groups.group(groupId) == null
          ? Gv2InviteOutcome.ignored
          : Gv2InviteOutcome.stored;
    } on Gv2StoreConflict {
      return Gv2InviteOutcome.ignored;
    } on ZkGroupException {
      return Gv2InviteOutcome.ignored;
    }
  }

  /// Settle the invites that were stored but never checked (the device was
  /// offline, or the app stopped in between), and bring the groups taken
  /// from the backup into use. Call when the server can be reached again.
  /// Never throws for what a server can cause. Calls made while one is
  /// running join it: each group is asked about once at a time, however
  /// often the app says "work".
  Future<void> resume() =>
      _resuming ??= _resume().whenComplete(() => _resuming = null);

  Future<void>? _resuming;

  Future<void> _resume() async {
    for (final row in await _groups.groups()) {
      if (row.resetPending) {
        await _settleRestored(row.groupId);
      } else if (row.membership == Gv2Membership.invited && !row.stateLoaded) {
        await settleInvite(row.groupId);
      }
    }
  }

  /// A group taken from the backup: follow its log from the backup's
  /// anchor, then tell the group that this device's Sender Keys are gone.
  /// Dropped when the server's log does not bear the backup out or this
  /// account is no longer in the group; left for a later call when that
  /// cannot be told now.
  Future<void> _settleRestored(String groupId) async {
    final notBefore = _restoreRetryAtMs[groupId];
    if (notBefore != null && _nowMs() < notBefore) return;
    try {
      await _inbox.requestSync(groupId);
    } catch (_) {
      return; // this device failed
    }
    final row = await _groups.group(groupId);
    if (row == null || !row.resetPending) return;
    if (row.hold == Gv2Hold.frozen) {
      // The server signed something this device cannot accept: the group
      // stays, frozen, and nothing is announced.
      await _groups.setResetPending(groupId, false);
      _notify(groupId, const []);
      return;
    }
    final status = _messaging.lastSyncOf(groupId)?.status;
    const refuted = {
      Gv2SyncStatus.snapshotMismatch,
      Gv2SyncStatus.notReadable,
    };
    if (refuted.contains(status)) {
      await _dropRestored(groupId);
      return;
    }
    const reached = {Gv2SyncStatus.upToDate, Gv2SyncStatus.advanced};
    if (!reached.contains(status)) {
      // Offline: the next call tries again. Anything else the server said:
      // not before a while.
      if (status != Gv2SyncStatus.offline) {
        _restoreRetryAtMs[groupId] = _nowMs() + gv2RestoreRetry.inMilliseconds;
      }
      return;
    }
    _restoreRetryAtMs.remove(groupId);
    switch (row.membership) {
      case Gv2Membership.awaitingConfirm:
        try {
          await _messaging.announceReset(
            groupId,
            alsoWrite: () => _groups.setResetPending(groupId, false),
          );
        } on Gv2NotSendable {
          return; // changed meanwhile: the next call looks again
        }
      case Gv2Membership.active:
        // Alone in the group: nobody holds keys of this device, and nobody
        // is there to confirm anything.
        await _groups.setResetPending(groupId, false);
      default:
        // Removed, or the group ended, while this account was away: there
        // is nothing on this device to keep of it.
        await _dropRestored(groupId);
        return;
    }
    _notify(groupId, const []);
  }

  Future<void> _dropRestored(String groupId) async {
    _restoreRetryAtMs.remove(groupId);
    await _groups.deleteGroup(groupId);
    _inbox.groupsChanged();
  }

  /// Accept the invite to [groupId]. Returns once the server accepted the
  /// ACCEPT: this account is then a member waiting for a member's
  /// confirmation of the head (Gv2Membership.awaitingConfirm).
  ///
  /// Throws [Gv2GroupException]: `inviteGone` when the invite is not (or no
  /// longer) in the log — the group is then forgotten.
  Future<void> accept(String groupId) async {
    final inviteKey = await _heldInvite(groupId);
    final groupIdBytes = gv2Unhex(groupId);
    final memberKey = await _memberKey(groupIdBytes);
    await _answering(groupId, (row, state) async {
      _stillInvited(row, state, inviteKey);
      return _Change(
        [
          Gv2Accept(
            memberKey.publicKey,
            gv2SignInviteAccept(
              inviteKey: inviteKey,
              groupId: groupIdBytes,
              ciphertext: gv2Unhex(row.myCiphertext),
              memberPub: memberKey.publicKey,
            ),
          ),
        ],
        memberKey,
        memberPayload: await _memberPayload(row.masterKey, groupIdBytes),
      );
    });
    // The members look at the log, see the ACCEPT and confirm the head.
    try {
      await _messaging.noticeChange(groupId);
    } on Gv2NotSendable {
      // Removed again already: nothing to announce.
    }
  }

  /// Decline the invite to [groupId].
  ///
  /// Throws [Gv2GroupException].
  Future<void> decline(String groupId) async {
    final inviteKey = await _heldInvite(groupId);
    await _answering(groupId, (row, state) async {
      _stillInvited(row, state, inviteKey);
      // A DECLINE is signed with the invite key itself.
      return _Change(const [Gv2Decline()], inviteKey);
    });
  }

  /// Submit the answer to an invite. When the invite turns out to be gone
  /// while it is being answered, the group is forgotten.
  Future<void> _answering(
    String groupId,
    Future<_Change> Function(Gv2GroupRow row, Gv2GroupState state) build,
  ) async {
    try {
      await _submit(groupId, build);
    } on Gv2GroupException catch (e) {
      if (e.reason == Gv2GroupFailure.inviteGone) await _forget(groupId);
      rethrow;
    }
  }

  /// The invite key of [groupId] when its invite holds in the log.
  Future<Gv2SigningKey> _heldInvite(String groupId) async {
    final row = await _groups.group(groupId);
    final seed = row?.inviteSeed;
    if (row == null || row.membership != Gv2Membership.invited || seed == null) {
      throw const Gv2GroupException(Gv2GroupFailure.notAllowed);
    }
    switch (await _inviteHolds(groupId)) {
      case true:
        return Gv2SigningKey.fromSeed(seed);
      case false:
        await _forget(groupId);
        throw const Gv2GroupException(Gv2GroupFailure.inviteGone);
      case null:
        throw const Gv2GroupException(Gv2GroupFailure.unavailable);
    }
  }

  static void _stillInvited(
    Gv2GroupRow row,
    Gv2GroupState state,
    Gv2SigningKey inviteKey,
  ) {
    final pending = state.pending[row.myCiphertext];
    if (row.membership != Gv2Membership.invited ||
        pending == null ||
        !_same(pending.invitePub, inviteKey.publicKey)) {
      throw const Gv2GroupException(Gv2GroupFailure.inviteGone);
    }
  }

  /// Whether the invite stored for [groupId] is borne out by the server's
  /// log: true, false, or null when that cannot be told now (offline).
  Future<bool?> _inviteHolds(String groupId) async {
    try {
      await _inbox.requestSync(groupId);
    } catch (_) {
      return null; // this device failed
    }
    final status = _messaging.lastSyncOf(groupId)?.status;
    // What the server's own answer refutes. Bad data refutes nothing — a
    // malformed answer is not evidence that the invite is gone, and the
    // invite is checked again later.
    const refuted = {
      Gv2SyncStatus.snapshotMismatch,
      Gv2SyncStatus.notReadable,
      Gv2SyncStatus.unknownGroup,
    };
    if (refuted.contains(status)) return false;
    const reached = {Gv2SyncStatus.upToDate, Gv2SyncStatus.advanced};
    if (!reached.contains(status)) return null;
    final row = await _groups.group(groupId);
    final seed = row?.inviteSeed;
    if (row == null ||
        !row.stateLoaded ||
        row.membership != Gv2Membership.invited ||
        seed == null) {
      return false;
    }
    final state = await _groups.loadState(groupId);
    final pending = state?.pending[row.myCiphertext];
    final sender = row.invitedBySnowId;
    // Under the key of this invite, and made by the account that sent it.
    return pending != null &&
        sender != null &&
        _same(pending.invitePub, Gv2SigningKey.fromSeed(seed).publicKey) &&
        _same(pending.invitedBy, _ciphertext(row.masterKey, sender));
  }

  /// Forget a group this account never took part in.
  Future<void> _forget(String groupId) async {
    final row = await _groups.group(groupId);
    const never = {Gv2Membership.invited, Gv2Membership.declined};
    if (row == null || !never.contains(row.membership)) return;
    await _groups.deleteGroup(groupId);
    _inbox.groupsChanged();
    _notify(groupId, const []);
  }

  // ---------------------------------------------------------------------------
  // Changing a group
  // ---------------------------------------------------------------------------

  /// Remove [snowId] from [groupId] (an owner anyone, an admin a plain
  /// member). The removed member is told at once; everyone else by the
  /// change notice. This device's next message uses a new Sender Key.
  ///
  /// Throws [Gv2GroupException].
  Future<void> remove(String groupId, String snowId) async {
    final group = await _activeGroup(groupId);
    await removeMember(groupId, gv2Hex(_ciphertext(group.masterKey, snowId)));
  }

  /// Remove the member [ciphertext] (lowercase hex) from [groupId] — also
  /// one whose ciphertext names no account (it still takes a place). See
  /// [remove].
  Future<void> removeMember(String groupId, String ciphertext) async {
    _checkCiphertext(ciphertext);
    await _activeGroup(groupId);
    final target = gv2Unhex(ciphertext);
    final targetKey = ciphertext;
    final memberKey = await _memberKey(gv2Unhex(groupId));
    // What the member sent before its removal and is here already is read
    // first, under the roster it was sent to (design §7.4) — the removal
    // erases its keys on this device.
    await _inbox.drainGroup(groupId);
    await _submit(groupId, (row, state) async {
      _stillActive(row);
      if (!state.members.containsKey(targetKey)) {
        throw const Gv2GroupException(Gv2GroupFailure.notThere);
      }
      return _Change([Gv2Remove(target)], memberKey, tell: [targetKey]);
    });
    await _announce(groupId);
  }

  /// Whether [groupId] can be left now, judged on the log as the server has
  /// it: catches up first (`unavailable` when that cannot be done), then
  /// refuses what [leave] would — not a member (`notAllowed`), an owner with
  /// nobody to hand the group to (`noSuccessor`). Returns normally when
  /// leaving can be tried. A frozen group is always left (on this device).
  /// For a caller that does something first that only makes sense when the
  /// leave follows (unsending its messages).
  Future<void> checkLeave(String groupId) async {
    final group = await _groups.group(groupId);
    const inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
    if (group == null || !inside.contains(group.membership)) {
      throw const Gv2GroupException(Gv2GroupFailure.notAllowed);
    }
    if (group.hold == Gv2Hold.frozen) return;
    if (!await _catchUp(groupId)) {
      throw const Gv2GroupException(Gv2GroupFailure.unavailable);
    }
    final row = await _groups.group(groupId);
    final state = await _groups.loadState(groupId);
    final mine = row == null ? null : state?.members[row.myCiphertext];
    if (row == null || state == null || mine == null) {
      throw const Gv2GroupException(Gv2GroupFailure.notAllowed);
    }
    if (mine.role == gv2RoleOwner &&
        state.members.length > 1 &&
        await _successor(groupId, row.myCiphertext, state) == null) {
      throw const Gv2GroupException(Gv2GroupFailure.noSuccessor);
    }
  }

  /// Leave [groupId]. An owner hands the group to the confirmed member who
  /// has been in it longest; the last member's leaving ends the group. The
  /// members are told at once (afterwards this account cannot reach them).
  /// A frozen group is left on this device only: its server signed two
  /// logs, and nothing it would answer counts.
  ///
  /// Throws [Gv2GroupException]: `noSuccessor` when an owner has nobody to
  /// hand the group to.
  Future<void> leave(String groupId) async {
    final group = await _groups.group(groupId);
    const inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
    if (group == null || !inside.contains(group.membership)) {
      throw const Gv2GroupException(Gv2GroupFailure.notAllowed);
    }
    if (group.hold == Gv2Hold.frozen) {
      await _groups.deleteGroup(groupId);
      _inbox.groupsChanged();
      _notify(groupId, const []);
      _queued(); // the backup lets go of it
      return;
    }
    final memberKey = await _memberKey(gv2Unhex(groupId));
    await _submit(groupId, onHold: true, (row, state) async {
      final mine = state.members[row.myCiphertext];
      if (mine == null) {
        throw const Gv2GroupException(Gv2GroupFailure.notAllowed);
      }
      final tell = await _everyone(groupId);
      if (mine.role != gv2RoleOwner || state.members.length == 1) {
        return _Change(const [Gv2Leave()], memberKey, tell: tell);
      }
      final successor = await _successor(groupId, row.myCiphertext, state);
      if (successor == null) {
        throw const Gv2GroupException(Gv2GroupFailure.noSuccessor);
      }
      return _Change(
        [Gv2TransferOwner(gv2Unhex(successor)), const Gv2Leave()],
        memberKey,
        tell: tell,
      );
    });
    await _messaging.afterOwnChange(groupId);
  }

  /// Before this account is deleted (design §9.7): leave every group it is
  /// a member of — an owner hands its group on first — and decline the
  /// invites it holds. Best effort, never throws: a group that cannot be
  /// left now (no server, nobody confirmed to hand it to) is left to the
  /// deletion proof, on which the members drop this account themselves.
  /// Returns the ids of the groups this account is still in by the log.
  Future<List<String>> leaveAll() async {
    final remaining = <String>[];
    for (final row in await _groups.groups()) {
      final groupId = row.groupId;
      try {
        switch (row.membership) {
          case Gv2Membership.active:
          case Gv2Membership.awaitingConfirm:
            if (!row.stateLoaded) {
              // Taken from the backup and never followed: no state to
              // build a change on yet.
              await _settleRestored(groupId);
              if (await _groups.group(groupId) == null) continue;
            }
            await leave(groupId);
          case Gv2Membership.invited:
            await decline(groupId);
          case Gv2Membership.creating:
            // The server may or may not have the group: the outbox row
            // goes with the database, and a group whose only member is a
            // deleted account is nobody's.
            break;
          default:
            break;
        }
      } on Gv2GroupException {
        const inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
        final now = await _groups.group(groupId);
        if (now != null && inside.contains(now.membership)) {
          remaining.add(groupId);
        }
      } catch (_) {
        remaining.add(groupId); // this device failed
      }
    }
    return remaining;
  }

  /// Make [snowId] an admin of [groupId], or a plain member again (owner
  /// only). Only an account this device has confirmed is made an admin.
  ///
  /// Throws [Gv2GroupException].
  Future<void> setRole(
    String groupId,
    String snowId, {
    required bool admin,
  }) async {
    final group = await _activeGroup(groupId);
    final target = _ciphertext(group.masterKey, snowId);
    if (admin) await _confirmedTarget(groupId, snowId);
    final memberKey = await _memberKey(gv2Unhex(groupId));
    await _submit(groupId, (row, state) async {
      _stillActive(row);
      if (!state.members.containsKey(gv2Hex(target))) {
        throw const Gv2GroupException(Gv2GroupFailure.notThere);
      }
      return _Change([
        Gv2SetRole(target, admin ? gv2RoleAdmin : gv2RoleMember),
      ], memberKey);
    });
    await _announce(groupId);
  }

  /// Hand [groupId] over to [snowId] (owner only; this account becomes an
  /// admin). Only to an account this device has confirmed.
  ///
  /// Throws [Gv2GroupException].
  Future<void> transferOwner(String groupId, String snowId) async {
    final group = await _activeGroup(groupId);
    final target = _ciphertext(group.masterKey, snowId);
    await _confirmedTarget(groupId, snowId);
    final memberKey = await _memberKey(gv2Unhex(groupId));
    await _submit(groupId, (row, state) async {
      _stillActive(row);
      return _Change([Gv2TransferOwner(target)], memberKey);
    });
    await _announce(groupId);
  }

  /// Rename [groupId] (owner or admin).
  ///
  /// Throws [Gv2GroupException]: `unavailable` when the server's keys
  /// cannot be fetched (the title commits to them).
  Future<void> setTitle(String groupId, String title) async {
    final group = await _activeGroup(groupId);
    final groupIdBytes = gv2Unhex(groupId);
    final Gv2ServerKeysRow keys;
    try {
      keys = await _credentials.serverKeys();
    } on Gv2NetworkException {
      throw const Gv2GroupException(Gv2GroupFailure.unavailable);
    } on Gv2ApiException {
      throw const Gv2GroupException(Gv2GroupFailure.unavailable);
    }
    final titlePayload = gv2SealTitlePayload(
      gv2DeriveStateKey(group.masterKey, groupIdBytes),
      Gv2TitlePayload(
        name: title,
        serverKeyHash: gv2ServerKeyHash(
          serverPublicParams: keys.serverPublicParams,
          headPublicKey: keys.headPublicKey,
        ),
      ),
    );
    final memberKey = await _memberKey(groupIdBytes);
    await _submit(groupId, (row, state) async {
      _stillActive(row);
      return _Change(
        const [Gv2SetTitle()],
        memberKey,
        titlePayload: titlePayload,
      );
    });
    await _announce(groupId);
  }

  /// Take back the invite of [snowId] to [groupId] (owner, admin, or the
  /// member who invited).
  ///
  /// Throws [Gv2GroupException].
  Future<void> revokeInvite(String groupId, String snowId) async {
    final group = await _activeGroup(groupId);
    await revokePending(groupId, gv2Hex(_ciphertext(group.masterKey, snowId)));
  }

  /// Take back the invite of [ciphertext] (lowercase hex) — also one whose
  /// ciphertext names no account. See [revokeInvite].
  Future<void> revokePending(String groupId, String ciphertext) async {
    _checkCiphertext(ciphertext);
    await _activeGroup(groupId);
    final target = gv2Unhex(ciphertext);
    final memberKey = await _memberKey(gv2Unhex(groupId));
    await _submit(groupId, (row, state) async {
      _stillActive(row);
      if (!state.pending.containsKey(gv2Hex(target))) {
        throw const Gv2GroupException(Gv2GroupFailure.notThere);
      }
      return _Change([Gv2RevokeInvite(target)], memberKey);
    });
    await _announce(groupId);
  }

  /// End [groupId] for everyone (owner only). The members are told at once.
  ///
  /// Throws [Gv2GroupException].
  Future<void> end(String groupId) async {
    await _activeGroup(groupId);
    final memberKey = await _memberKey(gv2Unhex(groupId));
    await _submit(groupId, (row, state) async {
      _stillActive(row);
      return _Change(
        const [Gv2DeleteGroup()],
        memberKey,
        tell: await _everyone(groupId),
      );
    });
    await _messaging.afterOwnChange(groupId);
  }

  /// A member's account turned out to be deleted (its own verified proof —
  /// the outbox). When this account may remove that member, it does: the
  /// account's own signature is the reason, not the server's word (design
  /// §9.7). Never throws.
  Future<void> removeDeleted(String groupId, String snowId) async {
    try {
      final group = await _groups.group(groupId);
      final target = await _groups.memberBySnowId(groupId, snowId);
      final myRole = await _groups.myRole(groupId);
      if (group == null ||
          target == null ||
          target.reach != Gv2Reach.deleted ||
          group.membership != Gv2Membership.active ||
          group.hold != Gv2Hold.none) {
        return;
      }
      final may =
          myRole == gv2RoleOwner ||
          (myRole == gv2RoleAdmin && target.role == gv2RoleMember);
      if (may) await remove(groupId, snowId);
    } catch (_) {
      // Another member with the right does it, or a later send finds the
      // account deleted again.
    }
  }

  /// Look up the display names of the members of [groupId] whose name was
  /// not looked up today (design §5.7: with a send token — the server
  /// learns nothing a send would not show it). Display only. Never throws.
  Future<void> refreshNames(String groupId) async {
    final tokens = _tokens;
    if (tokens == null) return;
    try {
      final group = await _groups.group(groupId);
      if (group == null ||
          group.membership != Gv2Membership.active ||
          group.hold == Gv2Hold.frozen) {
        return;
      }
      final day = _nowMs() ~/ Duration.millisecondsPerDay;
      final members = [
        for (final m in await _groups.confirmedMembers(groupId))
          if (m.snowId != null &&
              m.reach != Gv2Reach.deleted &&
              m.nicknameFetchedDay != day)
            m,
      ];
      if (members.isEmpty) return;
      final ciphertexts = [for (final m in members) m.ciphertext];
      var token = await tokens.sendToken(groupId, ciphertexts);
      if (token == null) {
        await tokens.refreshEndorsements(groupId);
        token = await tokens.sendToken(groupId, ciphertexts);
      }
      if (token == null) return;
      final names = await _transport.names(
        token: token,
        recipients: [
          for (final m in members) gv2AccountIdOfSnowId(m.snowId!),
        ],
      );
      await _groups.saveNicknames(groupId, {
        for (final m in members)
          m.ciphertext: names[gv2Hex(gv2AccountIdOfSnowId(m.snowId!))],
      }, day: day);
      _notify(groupId, const []);
    } catch (_) {
      // Names are for display: the next look-up tries again.
    }
  }

  /// The group when this account is a confirmed member of it and it is on
  /// no hold.
  Future<Gv2GroupRow> _activeGroup(String groupId) async {
    final group = await _groups.group(groupId);
    if (group == null) {
      throw const Gv2GroupException(Gv2GroupFailure.notAllowed);
    }
    _stillActive(group);
    return group;
  }

  static void _stillActive(Gv2GroupRow row) {
    if (row.membership != Gv2Membership.active || row.hold != Gv2Hold.none) {
      throw const Gv2GroupException(Gv2GroupFailure.notAllowed);
    }
  }

  /// Roles and ownership go only to an account this device has confirmed
  /// (design §5.6).
  Future<void> _confirmedTarget(String groupId, String snowId) async {
    final member = await _groups.memberBySnowId(groupId, snowId);
    if (member == null) {
      throw const Gv2GroupException(Gv2GroupFailure.notThere);
    }
    if (member.checkState != Gv2MemberCheckState.confirmed) {
      throw const Gv2GroupException(Gv2GroupFailure.notAllowed);
    }
  }

  /// The confirmed members of [groupId] (ciphertexts), this account among
  /// them.
  Future<List<String>> _everyone(String groupId) async => [
    for (final m in await _groups.confirmedMembers(groupId))
      if (m.reach != Gv2Reach.deleted) m.ciphertext,
  ];

  /// Who an owner that leaves hands the group to: the confirmed member who
  /// joined first (design §9.7) — never an account this device knows to be
  /// deleted (nobody would hold the group then).
  Future<String?> _successor(
    String groupId,
    String mine,
    Gv2GroupState state,
  ) async {
    final candidates = [
      for (final m in await _groups.confirmedMembers(groupId))
        if (m.ciphertext != mine &&
            m.reach != Gv2Reach.deleted &&
            state.members.containsKey(m.ciphertext))
          m,
    ]..sort((a, b) {
      final byJoin = a.joinedRevision.compareTo(b.joinedRevision);
      return byJoin != 0 ? byJoin : a.ciphertext.compareTo(b.ciphertext);
    });
    return candidates.isEmpty ? null : candidates.first.ciphertext;
  }

  /// After a change of this account that leaves it in the group: erase what
  /// belongs to members who are gone, and tell the group.
  Future<void> _announce(String groupId) async {
    await _messaging.afterOwnChange(groupId);
    try {
      await _messaging.noticeChange(groupId);
    } on Gv2NotSendable {
      // Not in the group any more.
    }
  }

  /// Tell [ciphertexts] directly that the log has moved to [next], with the
  /// endorsements held from before the change. Best effort: whoever is not
  /// reached finds out from the log the next time it looks.
  Future<void> _tell(
    Gv2GroupRow row,
    Gv2GroupState next,
    List<String> ciphertexts,
  ) async {
    final tokens = _tokens;
    final send = _send;
    final deviceId = _myDeviceId;
    if (ciphertexts.isEmpty ||
        tokens == null ||
        send == null ||
        deviceId == null) {
      return;
    }
    try {
      final groupId = gv2Unhex(row.groupId);
      final token = await tokens.sendToken(row.groupId, ciphertexts);
      if (token == null) return;
      final envelope = gv2SealChangeNoticeEnvelope(
        keys: Gv2EnvelopeKeys.derive(row.masterKey, groupId),
        stamp: Gv2EnvelopeStamp(
          senderAccountId: gv2AccountIdOfSnowId(_me),
          senderDeviceId: await deviceId(),
          messageId: gv2NewMessageId(),
          revision: next.revision,
          chain: next.chain,
          timestampMs: _nowMs(),
        ),
      );
      await send([
        Gv2SendEntry(
          token: token,
          recipients: [
            for (final c in ciphertexts)
              ZkGroup.decryptMember(
                masterKey: row.masterKey,
                ciphertext: gv2Unhex(c),
              ),
          ],
          envelope: envelope,
          silent: true,
        ),
      ]);
    } catch (_) {
      // Best effort.
    }
  }

  // ---------------------------------------------------------------------------
  // Submitting a change
  // ---------------------------------------------------------------------------

  /// The change of this device under way, per group.
  final Map<String, Future<void>> _changing = {};

  /// Build a change on the stored state with [build], submit it, and store
  /// it with the server's signed head. Catches up and builds again when the
  /// server is ahead.
  ///
  /// The changes of one group are made one after the other. Two at once
  /// shared the group's mark of an unanswered change (changeSentAtMs): the
  /// answer to one cleared the mark of the other, whose answer could still
  /// be lost — and a message would then go without the sync that finds a
  /// removal the server took. Nothing that runs inside a change makes
  /// another change (the inbox lanes it waits on never do).
  Future<void> _submit(
    String groupId,
    Future<_Change> Function(Gv2GroupRow row, Gv2GroupState state) build, {
    bool onHold = false,
  }) async {
    final before = _changing[groupId];
    final done = Completer<void>();
    _changing[groupId] = done.future;
    try {
      if (before != null) await before;
      await _submitNow(groupId, build, onHold: onHold);
    } finally {
      done.complete();
      if (identical(_changing[groupId], done.future)) {
        _changing.remove(groupId);
      }
    }
  }

  Future<void> _submitNow(
    String groupId,
    Future<_Change> Function(Gv2GroupRow row, Gv2GroupState state) build, {
    required bool onHold,
  }) async {
    final groupIdBytes = gv2Unhex(groupId);
    // Whether the stored state was brought up to the server's head during
    // this change (by the catch-up of a stale refusal or after a 409).
    var caughtUp = false;
    var attempt = 0;
    while (attempt < gv2ChangeAttempts) {
      final row = await _groups.group(groupId);
      // On a hold this device does not know the group as it is; the one
      // change it may still try is its own leaving ([onHold]).
      if (row == null ||
          !row.stateLoaded ||
          row.hold == Gv2Hold.frozen ||
          (row.hold != Gv2Hold.none && !onHold)) {
        throw const Gv2GroupException(Gv2GroupFailure.notAllowed);
      }
      final Gv2GroupState state;
      try {
        state = (await _groups.loadState(groupId))!;
      } on Gv2StoreCorruption {
        // The next sync repairs the rows from the anchor.
        throw const Gv2GroupException(Gv2GroupFailure.unavailable);
      }
      final _Change change;
      try {
        change = await build(row, state);
      } on _UnlessBehind catch (e) {
        if (caughtUp) throw Gv2GroupException(e.failure);
        // The stored state may be behind a decline or a leave: catch up
        // once and build again (no attempt at the change was made). A
        // catch-up that does not reach the server's head cannot tell.
        if (!await _catchUp(groupId)) {
          throw const Gv2GroupException(Gv2GroupFailure.unavailable);
        }
        caughtUp = true;
        continue;
      }
      attempt++;
      final ({Gv2Entry entry, Gv2GroupState next}) signed;
      try {
        signed = gv2SignEntry(
          state: state,
          groupId: groupIdBytes,
          draft: Gv2EntryDraft(
            version: gv2ProtocolVersion,
            revision: state.revision + 1,
            prevChain: state.chain,
            actor: gv2Unhex(row.myCiphertext),
            actions: change.actions,
            memberPayload: change.memberPayload ?? Uint8List(0),
            titlePayload: change.titlePayload ?? Uint8List(0),
          ),
          key: change.key,
        );
      } on Gv2Reject catch (e) {
        throw Gv2GroupException(Gv2GroupFailure.rejected, e.code.wire);
      }

      // From here until the answer is in, this device may not know whether
      // the server took the change (the answer can be lost, the app can end
      // meanwhile). Marked first: while the mark stands a message syncs
      // before it goes, so a removal the server took is never missed.
      await _groups.markChangeSent(groupId, _nowMs());
      final Gv2Head head;
      try {
        head = await _presented(
          row.masterKey,
          (p) => _transport.change(
            groupId: groupIdBytes,
            presentation: p,
            entry: gv2EncodeEntry(signed.entry),
          ),
        );
      } on Gv2ApiException catch (e) {
        // The server answered: it did not take the change.
        await _groups.clearChangeSent(groupId);
        if (e.code == 'revision_conflict') {
          // Others changed the group meanwhile (several invitees accepting
          // at once): step aside for a random moment, catch up, try again.
          await _sleep(Duration(milliseconds: 200 + _random.nextInt(1300)));
          caughtUp = await _catchUp(groupId);
          // The server is ahead and no longer lets this account read the
          // log: what changed is that it took this account out (an invite
          // that was taken back — the server shows a former invitee
          // nothing). Building the change again would never get anywhere.
          if (_messaging.lastSyncOf(groupId)?.status ==
              Gv2SyncStatus.notReadable) {
            throw Gv2GroupException(
              row.membership == Gv2Membership.invited
                  ? Gv2GroupFailure.inviteGone
                  : Gv2GroupFailure.notAllowed,
            );
          }
          continue;
        }
        if (e.code == 'entry_rejected') {
          throw Gv2GroupException(Gv2GroupFailure.rejected, e.reason);
        }
        // By the status: the per-address limit in front of the routes says
        // `RATE_LIMITED`, the per-member budget `rate_limited`.
        if (e.status == 429) {
          throw const Gv2GroupException(Gv2GroupFailure.rateLimited);
        }
        throw const Gv2GroupException(Gv2GroupFailure.unavailable);
      } on Gv2NetworkException {
        // No answer: the log tells whether the change was taken.
        if (await _settleUnanswered(row, signed.next, change)) return;
        continue;
      } on Gv2ProtocolException {
        throw const Gv2GroupException(Gv2GroupFailure.untrusted);
      } on Gv2CredentialException {
        // No presentation could be made: nothing went to the server.
        await _groups.clearChangeSent(groupId);
        throw const Gv2GroupException(Gv2GroupFailure.unavailable);
      }

      if (head.revision != signed.next.revision ||
          !_same(head.chain, signed.next.chain) ||
          !await _signed(groupIdBytes, head)) {
        // The server took the entry but does not show the head it gives:
        // nothing is stored from this answer. The log decides.
        throw const Gv2GroupException(Gv2GroupFailure.untrusted);
      }
      // Before the change is stored: storing it erases the endorsements of
      // whoever it takes out.
      await _tell(row, signed.next, change.tell);
      await _store(row, state, signed.entry, signed.next, head.headSig);
      await _groups.clearChangeSent(groupId);
      return;
    }
    throw const Gv2GroupException(Gv2GroupFailure.busy);
  }

  /// Catch up with the log of [groupId] through the inbox lane. True when
  /// the sync reached the server's head. Throws `unavailable` when the sync
  /// could not be asked for at all.
  Future<bool> _catchUp(String groupId) async {
    try {
      await _inbox.requestSync(groupId);
    } catch (_) {
      throw const Gv2GroupException(Gv2GroupFailure.unavailable);
    }
    final status = _messaging.lastSyncOf(groupId)?.status;
    return status == Gv2SyncStatus.upToDate ||
        status == Gv2SyncStatus.advanced;
  }

  /// The answer to this device's change [next] never came: the server may
  /// have taken it. Whoever the change takes out is told first (only a hint
  /// to look at the log — harmless when the change was not taken), then the
  /// log is fetched. True when the log holds the change: it was made. False
  /// when the log shows it was not taken: build it again. Throws
  /// `unavailable` when the log cannot be read now; the mark of the change
  /// stays, the next message syncs before it goes, and a change notice
  /// waits in the outbox for the group.
  Future<bool> _settleUnanswered(
    Gv2GroupRow row,
    Gv2GroupState next,
    _Change change,
  ) async {
    final groupId = row.groupId;
    await _tell(row, next, change.tell);
    try {
      await _inbox.requestSync(groupId);
    } catch (_) {
      // Judged below from what the store holds.
    }
    final now = await _groups.group(groupId);
    if (now == null) {
      throw const Gv2GroupException(Gv2GroupFailure.unavailable);
    }
    if (now.changeSentAtMs != null) {
      // The group is told when the network is back: the notice syncs
      // before it goes (the mark), so it carries the head the log has then.
      try {
        await _messaging.noticeChange(groupId);
      } on Gv2NotSendable {
        // Not in the group as this device has it.
      }
      throw const Gv2GroupException(Gv2GroupFailure.unavailable);
    }
    final point = await _groups.head(groupId, next.revision);
    return point != null && _same(point.chain, next.chain);
  }

  /// Store this account's own accepted [entry].
  Future<void> _store(
    Gv2GroupRow row,
    Gv2GroupState from,
    Gv2Entry entry,
    Gv2GroupState next,
    Uint8List headSig,
  ) async {
    final groupId = row.groupId;
    final removes = entry.actions.any((a) => a is Gv2Remove || a is Gv2Leave);
    try {
      await _groups.advance(
        from: from,
        to: next,
        headSig: headSig,
        membership: gv2StandingAfter(
          before: row.membership,
          myCiphertext: row.myCiphertext,
          entry: entry,
          after: next,
        ),
        removalRevision: removes ? next.revision : null,
        points: [Gv2LogPoint(next.revision, next.chain)],
      );
    } on Gv2StoreConflict {
      // A sync stored the entry first (it read it from the server's log):
      // the same entry, verified the same way.
      final point = await _groups.head(groupId, next.revision);
      if (point == null || !_same(point.chain, next.chain)) rethrow;
    }
    await _sync.checkMembers(groupId);
    _notify(groupId, [entry]);
    _queued();
  }

  // ---------------------------------------------------------------------------
  // The outbox rows: the create request and the 1:1 invite messages
  // ---------------------------------------------------------------------------

  @override
  Future<Gv2ActionOutcome> run(Gv2OutboxRow row) => switch (row.kind) {
    Gv2OutboxKind.create => _runCreate(row),
    Gv2OutboxKind.invite => _runInvite(row),
    _ => Future.value(Gv2ActionOutcome.drop),
  };

  @override
  Future<void> gaveUp(Gv2OutboxRow row) async {
    if (row.kind != Gv2OutboxKind.create) return;
    // The server never got to know the group: nobody else has.
    final group = await _groups.group(row.groupId);
    if (group?.membership == Gv2Membership.creating) {
      await _abandon(row.groupId);
    }
  }

  Future<Gv2ActionOutcome> _runCreate(Gv2OutboxRow row) async {
    final groupId = row.groupId;
    final group = await _groups.group(groupId);
    if (group == null || group.membership != Gv2Membership.creating) {
      return Gv2ActionOutcome.drop; // finished before, or abandoned
    }
    final groupIdBytes = gv2Unhex(groupId);
    Uint8List headSig;
    try {
      try {
        final head = await _presented(
          group.masterKey,
          (p) => _transport.create(
            groupId: groupIdBytes,
            publicParams: ZkGroup.groupParams(group.masterKey).publicParams,
            presentation: p,
            entry: row.payload,
          ),
        );
        if (head.revision != 0 || !_same(head.chain, group.chain)) {
          return Gv2ActionOutcome.failed;
        }
        headSig = head.headSig;
      } on Gv2ApiException catch (e) {
        if (e.code == 'entry_rejected') {
          // It cannot ever be accepted.
          await _abandon(groupId);
          return Gv2ActionOutcome.drop;
        }
        if (e.status != 409) return Gv2ActionOutcome.failed;
        // The server has this group already: an earlier request of this
        // device got through and its answer was lost. Its state at
        // revision 0 must be the one stored here.
        final snapshot = await _presented(
          group.masterKey,
          (p) => _transport.snapshot(
            groupId: groupIdBytes,
            presentation: p,
            at: 0,
          ),
        );
        if (!_same(snapshot.state.chain, group.chain) ||
            !_same(gv2StateHash(snapshot.state), group.stateHash)) {
          // Not this device's group under this id.
          await _abandon(groupId);
          return Gv2ActionOutcome.drop;
        }
        headSig = snapshot.headSig;
      }
    } on Gv2ApiException {
      return Gv2ActionOutcome.failed;
    } on Gv2NetworkException {
      return Gv2ActionOutcome.failed;
    } on Gv2ProtocolException {
      return Gv2ActionOutcome.failed;
    } on Gv2CredentialException {
      return Gv2ActionOutcome.failed;
    }
    final signed = await _signed(
      groupIdBytes,
      Gv2Head(revision: 0, chain: group.chain, headSig: headSig),
    );
    if (!signed) return Gv2ActionOutcome.failed;

    await _groups.finishCreate(
      groupId: groupId,
      headSig: headSig,
      nowMs: _nowMs(),
    );
    await _sync.checkMembers(groupId);
    Gv2Entry? entry;
    try {
      entry = gv2DecodeEntry(row.payload);
    } on Gv2DecodeException {
      entry = null;
    }
    _notify(groupId, [?entry]);
    return Gv2ActionOutcome.done;
  }

  Future<void> _abandon(String groupId) async {
    await _groups.deleteGroup(groupId);
    _inbox.groupsChanged();
    _notify(groupId, const []);
  }

  Future<Gv2ActionOutcome> _runInvite(Gv2OutboxRow row) async {
    final groupId = row.groupId;
    final recipient = row.recipient;
    var group = await _groups.group(groupId);
    const inviting = {
      Gv2Membership.creating,
      Gv2Membership.active,
      Gv2Membership.awaitingConfirm,
    };
    if (recipient == null ||
        row.payload.length != gv2SeedLen ||
        group == null ||
        group.hold == Gv2Hold.frozen ||
        !inviting.contains(group.membership)) {
      return Gv2ActionOutcome.drop;
    }
    // Nobody is told of a group before the server has signed its head.
    if (group.membership == Gv2Membership.creating || !group.stateLoaded) {
      return Gv2ActionOutcome.wait;
    }
    final invitePub = Gv2SigningKey.fromSeed(row.payload).publicKey;
    Future<bool> pending() async {
      await _sync.checkMembers(groupId); // names the pending accounts
      return (await _groups.pendingInvites(groupId)).any(
        (p) => p.snowId == recipient && _same(p.invitePub, invitePub),
      );
    }

    if (!await pending()) {
      // Not in the log as this device has it. Its own INVITE may have been
      // accepted without this device storing it: look once.
      await _inbox.requestSync(groupId);
      if (!await pending()) {
        // Used, revoked or never accepted — known only once no change of
        // this device is unanswered: an answer that never came is settled
        // by a sync that started after it went out, and until then the
        // stored log may lack this very INVITE (a recent sync says nothing
        // of it). Otherwise the row tries again later.
        final now = await _groups.group(groupId);
        return now != null && now.changeSentAtMs == null
            ? Gv2ActionOutcome.drop
            : Gv2ActionOutcome.failed;
      }
      group = await _groups.group(groupId);
      if (group == null) return Gv2ActionOutcome.drop;
    }
    final message = Gv2InviteMessage(
      groupId: gv2Unhex(groupId),
      masterKey: group.masterKey,
      revision: group.revision,
      chain: group.chain,
      stateHash: group.stateHash,
      inviteSeed: row.payload,
    );
    final bool sent;
    try {
      sent = await _sendInvite(recipient, message.encode());
    } catch (_) {
      return Gv2ActionOutcome.failed;
    }
    return sent ? Gv2ActionOutcome.done : Gv2ActionOutcome.failed;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// [ciphertext] is a member ciphertext in lowercase hex (65 bytes).
  static void _checkCiphertext(String ciphertext) {
    if (!RegExp(r'^[0-9a-f]{130}$').hasMatch(ciphertext)) {
      throw ArgumentError('gv2 groups: not a member ciphertext');
    }
  }

  /// The member ciphertext of [snowId] under [masterKey].
  static Uint8List _ciphertext(Uint8List masterKey, String snowId) =>
      ZkGroup.encryptMember(
        masterKey: masterKey,
        accountId: gv2AccountIdOfSnowId(snowId),
      );

  /// This account's sealed member payload for a group: its account key and
  /// the certificate that binds its member key to it, as of now.
  Future<Uint8List> _memberPayload(
    Uint8List masterKey,
    Uint8List groupId,
  ) async {
    final issuedAtMs = _nowMs();
    return gv2SealMemberPayload(
      gv2DeriveStateKey(masterKey, groupId),
      Gv2MemberPayload(
        accountPublicKey: await _accountPublicKey(),
        issuedAtMs: issuedAtMs,
        certSignature: await _memberCert(groupId, issuedAtMs),
      ),
    );
  }

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

  Future<bool> _signed(Uint8List groupId, Gv2Head head) async {
    try {
      return gv2VerifyHead(
        headPublicKey: (await _credentials.serverKeys()).headPublicKey,
        groupId: groupId,
        revision: head.revision,
        chain: head.chain,
        headSig: head.headSig,
      );
    } on Gv2NetworkException {
      return false;
    } on Gv2ApiException {
      return false;
    }
  }

  void _notify(String groupId, List<Gv2Entry> applied) {
    try {
      _sink.groupChanged(groupId, applied);
    } catch (_) {
      // What the app does with the news cannot undo the change.
    }
  }

  /// Count one more event in [times] when fewer than [limit] happened in
  /// the last hour.
  bool _under(List<int> times, int limit) {
    final now = _nowMs();
    times.removeWhere((t) => now - t >= Duration.millisecondsPerHour);
    if (times.length >= limit) return false;
    times.add(now);
    return true;
  }
}

/// What keeping an invite came to.
sealed class _Keep {
  const _Keep();
}

/// Nothing to keep (malformed, over the budget, not borne out, ...).
final class _KeepNothing extends _Keep {
  const _KeepNothing();
}

/// Stored (or kept aside): [groupId] is settled next.
final class _KeepStored extends _Keep {
  final String groupId;
  const _KeepStored(this.groupId);
}

/// An invite to a group this account left that could not be checked now.
final class _KeepLater extends _Keep {
  final String groupId;
  const _KeepLater(this.groupId);
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
