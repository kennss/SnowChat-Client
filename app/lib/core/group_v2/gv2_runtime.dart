/// @file        gv2_runtime.dart
/// @description Group protocol v2 — the parts put together for one signed-in
///              account: transport, credentials, sync, the stores of the
///              account's database, pairwise messages, the messaging layer,
///              the local inbox, the outbox, the group actions (create,
///              invite, accept, …) and the backup of the group keys. The
///              app hands it the rows of
///              the group queue (from the socket and from a REST fetch) and
///              tells it when to work; everything else happens inside.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (X1: isBlocked — invites from blocked accounts are dropped; P5.6: pumps called during a run share it and run once more after; the outbox records what became of a message through the sink, in its own transaction; the pump wakes when the delayed backup write is due; P5.6: until this install has looked at the backup, envelopes of groups it may bring back are kept — groupsKnown for the inbox and the pairwise service). Earlier 2026-11-21 (invite rows of the inbox go to the group actions (messaging.attachInvites)). Earlier 2026-11-21 (P5.6: no autoAccept — every invite waits for the user). Earlier 2026-11-21 (a timer also for rows waiting for the change log (gv2SyncWaitRetry)). Earlier 2026-11-20 (the server keys this build trusts are passed to the credentials)
///
/// @functions
///  - Gv2Runtime.receive(): rows of the group queue — store, acknowledge,
///    then handle
///  - Gv2Runtime.pump(): handle what the inbox holds and send what the
///    outbox holds
///  - Gv2Runtime.groups: create a group, invite, accept or decline an invite
///  - Gv2Runtime.sendEvents: what became of the messages this account queued
///  - Gv2Runtime.leaveAllGroups(): before the account is deleted
///  - Gv2Runtime.conversationOfPush(): the chat a push of the group queue
///    opens
///  - Gv2Runtime.dispose()
///
/// Notes:
///  - One runtime per signed-in account and database. It is built only once
///    everything it needs exists (the sealed sender service and the sender
///    certificate manager come up after sign-in); until then the rows of
///    the group queue stay on the server.
///  - receive() returns once the rows are stored and acknowledged; handling
///    them (which may fetch a change log) goes on without the caller
///    waiting — the 1:1 message queue and call signaling are never held up
///    by a group (design §7.4).
///  - The runtime wakes itself: when an outbox row that backed off (or is
///    held back) comes due, and every ten minutes while envelopes wait for
///    a Sender Key.
///  - Every sync of a group goes through its inbox lane
///    (Gv2Inbox.requestSync): code that needs a group caught up asks the
///    inbox, never Gv2Sync directly.
///  - The backup (gv2_backup.dart): until this install has looked at it
///    once, every pump starts by asking for it, so that a new install knows
///    its groups before it handles what is in the inbox (a pairwise message
///    for a group this device does not hold is dropped). When the backup
///    cannot be had, the pump goes on all the same: invites, new groups and
///    their messages do not depend on the backup route. Every pump, and
///    every send of something this account queued, ends by writing the
///    backup when what it should hold has changed (a comparison on this
///    device; the server is asked only when it has).
///  - Nothing here logs.
library;

import 'dart:async';
import 'dart:typed_data';

import '../storage/database.dart';
import 'gv2_backup.dart';
import 'gv2_credentials.dart';
import 'gv2_groups.dart';
import 'gv2_inbox.dart';
import 'gv2_keys.dart';
import 'gv2_messaging.dart';
import 'gv2_outbox.dart';
import 'gv2_pairwise_crypto.dart';
import 'gv2_pairwise_service.dart';
import 'gv2_sync.dart';
import 'gv2_transport.dart';
import 'gv2_trusted_keys.dart';

class Gv2Runtime {
  final Gv2Transport transport;
  late final Gv2Credentials credentials;
  late final Gv2Sync sync;
  late final Gv2PairwiseService pairwise;
  late final Gv2Messaging messaging;
  late final Gv2Inbox inbox;
  late final Gv2GroupActions groups;
  late final Gv2Outbox outbox;
  late final Gv2Backup backup;

  final StreamController<Gv2OutboxEvent> _sendEvents =
      StreamController<Gv2OutboxEvent>.broadcast();
  bool _disposed = false;

  /// True once this install has looked at the backup (see the notes).
  bool _restored = false;
  final SnowDatabase _db;
  Timer? _wake;

  /// [db] is the account's database and [mySnowId] the account.
  /// [authenticatedPost] posts with the account's bearer token (used for
  /// /zk/credentials only). [pinnedAccountKey] returns the account key this
  /// device already confirmed for a snowId. [crypto] seals and opens
  /// pairwise messages on the app's 1:1 sessions. [myDeviceId] returns this
  /// device's id, [memberKey] this account's member signing key for a
  /// group, [memberCert] the account key's certificate for that member key
  /// and [accountPublicKey] the account key itself. [ack] acknowledges rows
  /// of the group queue and throws when it could not. [sink] is the app's
  /// message store. [sendInvite] sends an invite message over the 1:1
  /// sealed path and returns whether the server took it.
  /// [isBlocked] says whether an account is blocked (BlockList): an invite
  /// it sent is dropped. [backupApi] reaches the server's copy of the group
  /// key backup and
  /// [backupKey] returns the key that seals it; [backupWriteDelay] draws
  /// how long after a change of the list it is written (tests: none).
  Gv2Runtime({
    required SnowDatabase db,
    required String mySnowId,
    required Gv2AuthenticatedPost authenticatedPost,
    required Gv2PinnedAccountKey pinnedAccountKey,
    required Gv2PairwiseCrypto crypto,
    required Future<String> Function() myDeviceId,
    required Future<Gv2SigningKey> Function(Uint8List groupId) memberKey,
    required Future<Uint8List> Function(Uint8List groupId, int issuedAtMs)
    memberCert,
    required Future<Uint8List> Function() accountPublicKey,
    required Gv2Ack ack,
    required Gv2MessageSink sink,
    required Future<bool> Function(String recipient, Uint8List invite)
    sendInvite,
    required Gv2BackupApi backupApi,
    required Future<Uint8List> Function() backupKey,
    required Gv2TrustedServerKeys trustedKeys,
    String? baseUrl,
    Duration Function()? backupWriteDelay,
    required Future<bool> Function(String snowId) isBlocked,
  }) : _db = db,
       transport = Gv2Transport(
         authenticatedPost: authenticatedPost,
         baseUrl: baseUrl,
       ) {
    final groups_ = db.gv2Store;
    credentials = Gv2Credentials(
      store: groups_,
      transport: transport,
      snowId: () async => mySnowId,
      trustedKeys: trustedKeys,
    );
    sync = Gv2Sync(
      store: groups_,
      transport: transport,
      credentials: credentials,
      pinnedAccountKey: pinnedAccountKey,
    );
    pairwise = Gv2PairwiseService(
      groups: groups_,
      keys: db.gv2SenderKeyStore,
      outbox: db.gv2OutboxStore,
      crypto: crypto,
      serverHeadKey: () async => (await credentials.serverKeys()).headPublicKey,
      mySnowId: mySnowId,
      onQueued: _flush,
      groupsKnown: () => _restored,
    );
    messaging = Gv2Messaging(
      groups: groups_,
      keys: db.gv2SenderKeyStore,
      inboxStore: db.gv2InboxStore,
      outbox: db.gv2OutboxStore,
      pairwise: pairwise,
      sync: sync,
      sink: sink,
      mySnowId: mySnowId,
      onQueued: _flush,
    );
    inbox = Gv2Inbox(
      store: db.gv2InboxStore,
      groups: groups_,
      handler: messaging,
      ack: ack,
      // Until the backup was looked at, an envelope of a group it may bring
      // back is kept, not dropped.
      groupsKnown: () => _restored,
    );
    messaging.attach(inbox);
    final tokens = Gv2CredentialTokens(credentials);
    groups = Gv2GroupActions(
      groups: groups_,
      outbox: db.gv2OutboxStore,
      transport: transport,
      credentials: credentials,
      sync: sync,
      inbox: inbox,
      messaging: messaging,
      sink: sink,
      mySnowId: mySnowId,
      accountPublicKey: accountPublicKey,
      memberKey: memberKey,
      memberCert: memberCert,
      sendInvite: sendInvite,
      tokens: tokens,
      send: transport.send,
      myDeviceId: myDeviceId,
      onQueued: _flush,
      isBlocked: isBlocked,
    );
    outbox = Gv2Outbox(
      store: db.gv2OutboxStore,
      groups: groups_,
      keys: db.gv2SenderKeyStore,
      tokens: tokens,
      crypto: crypto,
      send: transport.send,
      mySnowId: () async => mySnowId,
      myDeviceId: myDeviceId,
      memberKey: memberKey,
      giveKeys: pairwise.giveKeys,
      prepareGroup: messaging.prepareSend,
      // The app's copy of a message reads what became of it — written with
      // the outbox row leaving, never after.
      recordOutcome: (event) => sink.outgoing(
        groupId: event.groupId,
        localMessageId: event.localMessageId,
        sent: event is Gv2MessageSent,
      ),
      onEvent: (event) {
        if (!_disposed) _sendEvents.add(event);
      },
      // A member whose account proved itself deleted is taken out by
      // whoever may (design §9.7).
      onMemberDeleted: (groupId, snowId) =>
          unawaited(groups.removeDeleted(groupId, snowId)),
      actions: groups,
    );
    // Invites the 1:1 queue kept (inbox rows of the invite kind) are taken
    // in here; checking one against the server goes on afterwards.
    messaging.attachInvites(groups.takeInvite);
    backup = Gv2Backup(
      groups: groups_,
      api: backupApi,
      key: backupKey,
      mySnowId: mySnowId,
      writeDelay: backupWriteDelay,
    );
  }

  /// What became of the messages this account queued for a group: sent, or
  /// given up.
  Stream<Gv2OutboxEvent> get sendEvents => _sendEvents.stream;

  /// Rows of the group queue as the server delivers them (the `gv2` list of
  /// a REST fetch, or one `gv2_message`): store them, acknowledge them, and
  /// start handling them. Returns true when every row is acknowledged —
  /// only then does the server's queue move on. Never throws.
  Future<bool> receive(List<dynamic> rows) async {
    if (_disposed) return false;
    final parsed = [for (final row in rows) ?Gv2QueueRow.tryParse(row)];
    if (parsed.isEmpty) return true;
    final Gv2ReceiveResult result;
    try {
      result = await inbox.receive(parsed);
    } catch (_) {
      return false; // not stored: the server hands the rows out again
    }
    unawaited(pump());
    return result.acknowledged;
  }

  /// Handle what the inbox holds, then send what the outbox holds. Safe to
  /// call at any time (on connect, on resume, after a receive). Never
  /// throws. Calls during a run share it, and make it run once more after
  /// (each socket row asked for a whole pump of its own).
  Future<void> pump() {
    _pumpAgain = true;
    return _pumping ??= _pumpLoop().whenComplete(() => _pumping = null);
  }

  Future<void>? _pumping;
  bool _pumpAgain = false;

  Future<void> _pumpLoop() async {
    while (_pumpAgain && !_disposed) {
      _pumpAgain = false;
      await _pumpOnce();
    }
  }

  Future<void> _pumpOnce() async {
    if (_disposed) return;
    try {
      // A new install first learns which groups it is in — when the server
      // can be asked; nothing else waits for that.
      if (!_restored) await _syncBackup();
      await inbox.flushAcks();
      await inbox.drain();
      await outbox.flush();
      // Invites that were stored while the server could not be reached,
      // and groups taken from the backup.
      await groups.resume();
      // The list changes with what was just handled. (An install that
      // could not look at the backup above does not ask twice in a pump.)
      if (_restored) await _syncBackup();
    } catch (_) {
      // A failure of this device (the database): the next pump tries again.
    }
    await _scheduleWake();
  }

  /// Restore from the backup (once) and write it when it is out of date.
  Future<void> _syncBackup() async {
    final outcome = await backup.sync();
    if (outcome.restored.isNotEmpty) inbox.groupsChanged();
    if (outcome.looked) _restored = true;
  }

  /// The conversation a push for the group-queue row [serverRowId] opens
  /// (the push carries the row id only — it says nothing about the group):
  /// the row's group once this device knows it. A row that has just been
  /// fetched may not have been given its group yet; the stored rows are
  /// sorted into their groups (nothing handled, nothing asked of the
  /// server — the tap does not wait for that) and the inbox asked again.
  /// Null when the row is unknown, or is not a group message (pairwise
  /// messages are silent: they bring no push). Never throws.
  Future<String?> conversationOfPush(String serverRowId) async {
    if (_disposed) return null;
    try {
      final known = await inbox.conversationOfServerRow(serverRowId);
      if (known != null) return known;
      await inbox.classify();
      return await inbox.conversationOfServerRow(serverRowId);
    } catch (_) {
      return null; // the list is shown instead
    }
  }

  /// Before the account is deleted: leave every group (see
  /// Gv2GroupActions.leaveAll) and send what that queued. Never throws.
  Future<void> leaveAllGroups() async {
    if (_disposed) return;
    try {
      await pump();
      await groups.leaveAll();
      await outbox.flush();
    } catch (_) {
      // The deletion proof tells the members what this could not.
    }
  }

  /// Something was queued (a message, a notice, a change of this account
  /// that was stored): send it — and, as a change may have added or ended a
  /// membership, see whether the backup still lists the right groups.
  void _flush() {
    if (_disposed) return;
    unawaited(() async {
      try {
        await outbox.flush();
        if (_restored && !_disposed) await _syncBackup();
      } catch (_) {
        // A failure of this device: the next pump tries again.
      }
      await _scheduleWake();
    }());
  }

  /// Arrange to work again when the first held-back outbox row comes due,
  /// or — while envelopes wait for a Sender Key — when the keys are asked
  /// for again, or — while envelopes wait for the change log — when their
  /// groups sync again. Without this a row that backed off, or waited
  /// through a sync that failed, would wait for the next connect or the
  /// next envelope to arrive.
  Future<void> _scheduleWake() async {
    if (_disposed) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      var at = await _db.gv2OutboxStore.nextWakeMs();
      if (await _db.gv2InboxStore.hasKeyWaits()) {
        final retry = now + gv2KeyWaitRetry.inMilliseconds;
        if (at == null || retry < at) at = retry;
      }
      if (await _db.gv2InboxStore.hasSyncWaits()) {
        final retry = now + gv2SyncWaitRetry.inMilliseconds;
        if (at == null || retry < at) at = retry;
      }
      // The delayed write of the backup (made by the pump it wakes).
      final backupDue = await backup.writeDueAtMs();
      if (backupDue != null && (at == null || backupDue < at)) at = backupDue;
      _wake?.cancel();
      _wake = null;
      if (at == null || _disposed) return;
      // Not sooner than a second from now: a row due at once was looked at
      // by the flush that just ended.
      final delay = Duration(milliseconds: (at - now).clamp(1000, 3600000));
      _wake = Timer(delay, () => unawaited(pump()));
    } catch (_) {
      // No timer: the next connect or envelope works the queues.
    }
  }

  void dispose() {
    _disposed = true;
    _wake?.cancel();
    transport.close();
    credentials.dispose();
    unawaited(_sendEvents.close());
  }
}
