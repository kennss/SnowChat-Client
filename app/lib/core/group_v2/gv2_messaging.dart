/// @file        gv2_messaging.dart
/// @description Group protocol v2 — the messaging layer: handles what comes
///              through the inbox (messages of members, change notices,
///              member notices, pairwise messages), keeps each group caught
///              up with its change log, and queues what this account says to
///              a group (design document §5.5, §7.1, §7.4, §8). A message is
///              shown only when the envelope opens with the group key, its
///              sender is a confirmed member of the group as this device
///              knows it, and that member's Sender Key signed the message
///              together with the envelope header.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (P5.6: at most gv2KeyWaitRowsPerSender rows of a group wait for one claimed sender's key; key requests spaced by how long the message waited; Gv2MessageSink.outgoing — the status of a message of this account, written with its outbox row leaving; a member notice is acted on once — by its signed message id; a member's reset drops its sessions and confirms its head at most once in ten minutes; a change notice ahead and a header ahead hold their lane until the sync — holdsLane; invite rows go to the group actions — attachInvites). Earlier 2026-11-21 (rows waiting for the log are given up only after a sync that started after they arrived reached the head (Gv2InboxItem.syncReachedSince) — a failed sync no longer drops a new member's message; gv2NotAMember()). Earlier 2026-11-20
///
/// @functions
///  - Gv2Messaging.handleGroupEnvelope() / handlePairwise() / syncGroup():
///    the inbox handler
///  - Gv2Messaging.send(): queue a message of this account to a group
///  - Gv2Messaging.noticeChange() / announceReset(): queue a notice
///  - Gv2Messaging.prepareSend(): what the outbox asks for before it sends
///    to a group
///  - Gv2Messaging.lastSyncOf(): how a group's last sync ended
///  - Gv2Messaging.attachInvites() / handleInvite(): invite rows go to the
///    group actions
///  - Gv2Messaging.afterOwnChange(): the key clean-up after a change of
///    this account
///  - Gv2MessageSink: where handled messages go (the app's message store)
///  - Gv2SinkEvent: what was committed there (stored, unsent, cleared,
///    waiting)
///  - Gv2IncomingMessage / Gv2QueuedMessage / Gv2NotSendable
///
/// Notes:
///  - What an envelope may do depends on its kind (gv2_envelope.dart):
///      content        believed once the sender's Sender Key verified it;
///                     without the key the row waits and the key is asked
///                     for. The key of a message is used once: the stored
///                     chain moves in the same transaction that stores the
///                     message, so the same message cannot be read again.
///                     A message whose key has not come after
///                     [gv2KeyWaitShown] is shown as one that cannot be
///                     read (Gv2MessageSink.waiting) — without a sender:
///                     until the key verifies it, the header is only what
///                     some holder of the group key wrote. The message
///                     takes that place when its key comes; when it never
///                     does, the place stays.
///      change notice  believed by nobody: a hint to fetch the log.
///      member notice  believed once the sender's member signing key
///                     verified it. member_reset: forget which key this
///                     device gave that member, and confirm the head to it
///                     when this device is one of the members picked for it.
///  - The sender's place in the log (the revision and chain in the header —
///    authenticated for content and member notices) is compared with the
///    point this device verified at that revision:
///      behind this device   the envelope is handled and the sender told
///                           ("behind", with this device's signed head).
///      ahead of this device the log is fetched first. When a sync that
///                           started after the envelope arrived still ends
///                           short of it, the envelope is handled and the
///                           sender asked for its signed head.
///      another chain        the envelope is handled and the sender asked
///                           for its signed head. A claim alone does
///                           nothing; the server's signature on both heads
///                           freezes the group (gv2_pairwise_service.dart).
///  - A message of a sender this device does not know as a confirmed member
///    waits until a sync that started after it arrived reached the server's
///    head (and the sender was checked), then is dropped (gv2NotAMember) — a
///    sync that failed drops nothing. A member removed by the log is
///    not a member: what it sent before the removal is handled before the
///    sync that applies it (the inbox drains a group before it syncs).
///  - Messages are de-duplicated by local message id, kept apart from the
///    message rows: a second copy of a message (the sender retried) is not
///    shown again, also not after the first was deleted here. An unsend
///    marks its target as handled, so a target that arrives late is never
///    shown.
///  - Every sync of a group goes through its inbox lane (requestSync), so
///    syncs of one group never overlap and each starts after the envelopes
///    that arrived before it were handled. Syncs of one group are at least
///    [gv2SyncFloor] apart: an envelope can make this device sync (a change
///    notice from anyone holding the group key), so the rate is bounded.
///  - After a sync: members are checked, Sender Keys and delivery records
///    of accounts no longer in the group are erased, a withheld hold is
///    settled, and the head is confirmed to members who joined.
///  - Nothing here logs: messages, keys, groups and members.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../crypto/sender_key.dart';
import '../storage/database.dart';
import '../storage/tables/gv2_tables.dart';
import 'gv2_codec.dart';
import 'gv2_content.dart';
import 'gv2_credentials.dart';
import 'gv2_envelope.dart';
import 'gv2_inbox.dart';
import 'gv2_inbox_store.dart';
import 'gv2_outbox.dart';
import 'gv2_pairwise_service.dart';
import 'gv2_sender_key_store.dart';
import 'gv2_store.dart';
import 'gv2_sync.dart';

/// Syncs of one group are at least this far apart.
const Duration gv2SyncFloor = Duration(seconds: 5);

/// A member notice stamped further in the future than this (by this
/// device's clock) is not believed.
const Duration gv2NoticeClockSkew = Duration(days: 1);

/// A message whose Sender Key has not come for this long is shown as one
/// that cannot be read (yet). The first request for the key is made when
/// the message arrives; by this time it went unanswered.
const Duration gv2KeyWaitShown = Duration(minutes: 10);

/// At most this many rows of a group wait for the key of one (claimed)
/// sender: a message beyond is dropped. The claim is not verified before
/// the key is there — anyone who holds the master key and a send token
/// could otherwise fill this device with envelopes of made-up chains. A
/// real sender's keys leave before its messages; this is far above what
/// waits for a lost one.
const int gv2KeyWaitRowsPerSender = 1000;

/// A message of a member, verified, about to be stored.
class Gv2IncomingMessage {
  /// Lowercase hex of the group id: also the conversation id.
  final String groupId;

  /// Lowercase hex of the local message id (gv2LocalMessageId): the id the
  /// message is stored under.
  final String localMessageId;
  final String senderSnowId;
  final String senderDeviceId;

  /// The sender's clock when it wrote the message (authenticated), Unix
  /// MILLISECONDS.
  final int sentAtMs;

  /// This device's clock when the envelope arrived, MILLISECONDS.
  final int receivedAtMs;

  /// The app's message payload (UTF-8 JSON; gv2_content.dart).
  final Uint8List payload;

  const Gv2IncomingMessage({
    required this.groupId,
    required this.localMessageId,
    required this.senderSnowId,
    required this.senderDeviceId,
    required this.sentAtMs,
    required this.receivedAtMs,
    required this.payload,
  });
}

/// What was committed to the app's message store.
sealed class Gv2SinkEvent {
  final String groupId;
  const Gv2SinkEvent(this.groupId);
}

/// A message was stored.
final class Gv2MessageStored extends Gv2SinkEvent {
  final Gv2IncomingMessage message;
  Gv2MessageStored(this.message) : super(message.groupId);
}

/// A message was taken back by its sender.
final class Gv2MessageUnsent extends Gv2SinkEvent {
  final String localMessageId;
  final String senderSnowId;
  const Gv2MessageUnsent({
    required String groupId,
    required this.localMessageId,
    required this.senderSnowId,
  }) : super(groupId);
}

/// The history before [beforeMs] was cleared by an owner or admin.
final class Gv2HistoryCleared extends Gv2SinkEvent {
  final int beforeMs;
  final String bySnowId;
  const Gv2HistoryCleared({
    required String groupId,
    required this.beforeMs,
    required this.bySnowId,
  }) : super(groupId);
}

/// A message arrived whose key has not come: it is shown as one that
/// cannot be read (yet).
final class Gv2MessageWaiting extends Gv2SinkEvent {
  final String localMessageId;
  const Gv2MessageWaiting({
    required String groupId,
    required this.localMessageId,
  }) : super(groupId);
}

/// Where handled messages go: the app's message store. The write
/// methods run INSIDE the inbox transaction and must touch only the
/// database; what they write commits together with the inbox row leaving
/// and the Sender Key chain moving, or not at all.
abstract interface class Gv2MessageSink {
  /// Store [message]. Called once per local message id.
  Future<void> message(Gv2IncomingMessage message);

  /// [senderSnowId] took back its message [localMessageId] (which this
  /// device may or may not hold).
  Future<void> unsent({
    required String groupId,
    required String localMessageId,
    required String senderSnowId,
  });

  /// An owner or admin ([bySnowId]) cleared the history sent before
  /// [beforeMs] (Unix MILLISECONDS, never later than when it said so).
  Future<void> historyCleared({
    required String groupId,
    required int beforeMs,
    required String bySnowId,
  });

  /// A message arrived in [groupId] that cannot be read: its sender's key
  /// has not come. Keep its place under [localMessageId] — where
  /// [message] stores it should the key come — unless something is stored
  /// there already. Nothing in the header is verified at this point, so
  /// the place names no sender; [sentAtMs] is only where it sorts. Returns
  /// whether a place was made now.
  Future<bool> waiting({
    required String groupId,
    required String localMessageId,
    required int sentAtMs,
    required int receivedAtMs,
  });

  /// A message of this account left for [groupId] ([sent]) or was given
  /// up. Runs INSIDE the transaction that takes it out of the outbox, so
  /// the two never disagree. A message that is not stored (unsent, cleared)
  /// changes nothing.
  Future<void> outgoing({
    required String groupId,
    required String localMessageId,
    required bool sent,
  });

  /// One of the above was committed (never called for what was rolled
  /// back): show it, notify, delete files, refresh what is shown.
  void committed(Gv2SinkEvent event);

  /// Entries were applied to [groupId] — by a sync, or by a change of this
  /// account that the server accepted: its members, roles, title or this
  /// account's standing may have changed. [applied] are the entries, in
  /// order (empty when a group was only stored or removed). Called after
  /// the change is stored.
  void groupChanged(String groupId, List<Gv2Entry> applied);
}

/// A message this account queued for a group.
class Gv2QueuedMessage {
  /// The 16-byte message id of its envelope header (what an unsend names).
  final Uint8List messageId;

  /// Lowercase hex of the local message id: the id to store it under, and
  /// the one [Gv2MessageSent] / [Gv2MessageGivenUp] report.
  final String localMessageId;
  final int timestampMs;

  const Gv2QueuedMessage({
    required this.messageId,
    required this.localMessageId,
    required this.timestampMs,
  });
}

/// This account cannot say anything in the group: it is not in it, or the
/// group is frozen (read-only).
class Gv2NotSendable implements Exception {
  const Gv2NotSendable();

  @override
  String toString() => 'Gv2NotSendable';
}

/// What comparing a sender's place in the log with this device's gave.
class _Place {
  /// The log has to be fetched before the envelope can be handled.
  final bool wait;

  /// Pairwise messages to queue with the envelope's outcome.
  final List<Gv2InboxWrite> writes;
  const _Place.wait() : wait = true, writes = const [];
  const _Place.go(this.writes) : wait = false;
}

class Gv2Messaging implements Gv2InboxHandler {
  final Gv2Store _groups;
  final Gv2SenderKeyStore _keys;
  final Gv2InboxStore _inboxStore;
  final Gv2OutboxStore _outbox;
  final Gv2PairwiseService _pairwise;
  final Gv2LogSync _sync;
  final Gv2MessageSink _sink;
  final String _me;
  final void Function() _queued;
  final int Function() _nowMs;
  final Future<void> Function(Duration) _sleep;

  Gv2Inbox? _inbox;

  /// When the last sync of each group ended (local clock).
  final Map<String, int> _syncedAtMs = {};

  /// How the last sync of each group ended (in this run of the app).
  final Map<String, Gv2SyncResult> _lastSync = {};

  /// How the last sync of [groupId] in this run of the app ended, or null
  /// when there was none. For whoever asked for a sync through the inbox
  /// (Gv2Inbox.requestSync) and needs to know what it found.
  Gv2SyncResult? lastSyncOf(String groupId) => _lastSync[groupId];

  /// [mySnowId] is this device's account. [onQueued] is called after
  /// something was queued and committed (the app flushes the outbox).
  /// [sleep] waits (tests pass a fake).
  Gv2Messaging({
    required Gv2Store groups,
    required Gv2SenderKeyStore keys,
    required Gv2InboxStore inboxStore,
    required Gv2OutboxStore outbox,
    required Gv2PairwiseService pairwise,
    required Gv2LogSync sync,
    required Gv2MessageSink sink,
    required String mySnowId,
    void Function()? onQueued,
    int Function()? nowMs,
    Future<void> Function(Duration)? sleep,
    this.keyWaitRowsPerSender = gv2KeyWaitRowsPerSender,
  }) : _groups = groups,
       _keys = keys,
       _inboxStore = inboxStore,
       _outbox = outbox,
       _pairwise = pairwise,
       _sync = sync,
       _sink = sink,
       _me = mySnowId,
       _queued = onQueued ?? (() {}),
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _sleep = sleep ?? Future<void>.delayed;

  /// At most this many rows of a group wait for one claimed sender's key
  /// ([gv2KeyWaitRowsPerSender]; tests pass a small one).
  final int keyWaitRowsPerSender;

  /// The inbox this layer handles for: syncs asked for from outside an
  /// inbox lane (before a send) go through it.
  void attach(Gv2Inbox inbox) => _inbox = inbox;

  /// When a member's reset was last acted on (this device's clock), by
  /// snowId: its 1:1 sessions dropped and its head confirmed.
  final Map<String, int> _resetActedAtMs = {};

  /// Keeps an invite that came on the 1:1 path (set by the runtime: the
  /// group actions).
  Future<Gv2InboxOutcome> Function(String senderSnowId, Uint8List invite)?
  _invites;

  /// [keep] takes in the invite rows of the inbox (Gv2GroupActions).
  void attachInvites(
    Future<Gv2InboxOutcome> Function(String senderSnowId, Uint8List invite)
    keep,
  ) => _invites = keep;

  @override
  Future<Gv2InboxOutcome> handleInvite(String senderSnowId, Uint8List invite) {
    final keep = _invites;
    // Not wired: the row fails and is tried again (never silently dropped).
    if (keep == null) throw StateError('gv2 messaging: invites not attached');
    return keep(senderSnowId, invite);
  }

  int _day() => _nowMs() ~/ Duration.millisecondsPerDay;

  // ---------------------------------------------------------------------------
  // The inbox handler
  // ---------------------------------------------------------------------------

  @override
  Future<Gv2InboxOutcome> handlePairwise(Gv2InboxItem item) =>
      _pairwise.handle(item);

  @override
  Future<Gv2InboxOutcome> handleGroupEnvelope(
    String groupId,
    Gv2OpenedEnvelope envelope,
    Gv2InboxItem item,
  ) async {
    final group = await _groups.group(groupId);
    const inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
    if (group == null ||
        group.hold == Gv2Hold.frozen ||
        !inside.contains(group.membership)) {
      return const Gv2Dropped();
    }
    // The log holds entries this build cannot read: who is in the group is
    // not known until it can (an update). The row waits; it expires with
    // the inbox retention.
    if (group.hold == Gv2Hold.updateRequired || !group.stateLoaded) {
      return const Gv2WaitForSync();
    }

    if (envelope.kind == gv2KindChangeNotice) {
      final revision = gv2ChangeNoticeRevision(envelope);
      if (revision == null || revision != envelope.stamp.revision) {
        return const Gv2Dropped();
      }
      // Nothing vouches for it: it may only make this device look — until a
      // sync that started after it arrived has looked.
      return revision > group.revision &&
              !item.syncReachedSince(group.lastSyncAtMs)
          ? const Gv2WaitForSync(holdsLane: true)
          : const Gv2Handled();
    }
    if (envelope.kind != gv2KindContent &&
        envelope.kind != gv2KindMemberNotice) {
      return const Gv2Dropped(); // a kind this build does not know
    }

    final sender = envelope.stamp.senderSnowId;
    // This account's own copy (the recipient set is the whole roster).
    if (sender == _me) return const Gv2Dropped();
    final from = await _groups.memberBySnowId(groupId, sender);
    if (from == null || from.checkState != Gv2MemberCheckState.confirmed) {
      // Maybe a member this device has not caught up with (or checked) yet.
      return gv2NotAMember(group, from, item)
          ? const Gv2Dropped()
          : const Gv2WaitForSync();
    }
    return envelope.kind == gv2KindContent
        ? _content(group, from, envelope, item)
        : _memberNotice(group, from, envelope, item);
  }

  Future<Gv2InboxOutcome> _content(
    Gv2GroupRow group,
    Gv2MemberRow from,
    Gv2OpenedEnvelope envelope,
    Gv2InboxItem item,
  ) async {
    final groupId = group.groupId;
    final groupIdBytes = gv2Unhex(groupId);
    final sender = from.snowId!;
    final stamp = envelope.stamp;
    Uint8List open(SenderKeyManager keys) => gv2OpenContent(
      groupId: groupIdBytes,
      envelope: envelope,
      senderKeys: keys,
    );

    // A trial read: decides what becomes of the row. Nothing is stored — the
    // read that counts happens in the outcome's transaction.
    final Uint8List plaintext;
    try {
      plaintext = open(await _keys.manager(groupId, sender));
    } on SenderKeyException catch (e) {
      if (e.reason != SenderKeyFailure.noKey) {
        // Not signed by the sender, already read, or beyond reach: dropped.
        // The sender's key is untouched.
        return const Gv2Dropped();
      }
      // The chain the message names (unauthenticated): ask for its key.
      final chainId = ByteData.sublistView(
        envelope.body,
      ).getUint32(1, Endian.big);
      if (chainId > 0x7FFFFFFF) return const Gv2Dropped();
      // Beyond the cap the row is not kept. (Only rows parked now count: a
      // row being looked at again was woken, and is not among them.)
      if (await _inboxStore.keyWaitsOf(
            groupId,
            sender,
            atMost: keyWaitRowsPerSender,
          ) >=
          keyWaitRowsPerSender) {
        return const Gv2Dropped();
      }
      final ask = await _pairwise.prepareRequestKey(
        groupId,
        sender,
        chainId,
        waited: Duration(milliseconds: _nowMs() - item.receivedAtMs),
      );
      // The key did not come for a while: the message gets a place that
      // says it cannot be read. Not for an id that was handled before — a
      // copy of a header with another body must not replace what is shown.
      final waitingId = gv2LocalMessageId(
        groupId: groupIdBytes,
        senderAccountId: stamp.senderAccountId,
        messageId: stamp.messageId,
      );
      final show =
          _nowMs() - item.receivedAtMs >= gv2KeyWaitShown.inMilliseconds &&
          !await _inboxStore.messageHandled(waitingId);
      if (!show) {
        return Gv2WaitForKey(
          sender: sender,
          write: ask,
          afterCommit: ask == null ? null : _queued,
        );
      }
      var placed = false;
      return Gv2WaitForKey(
        sender: sender,
        write: () async {
          placed = false;
          await ask?.call();
          placed = await _sink.waiting(
            groupId: groupId,
            localMessageId: gv2Hex(waitingId),
            sentAtMs: stamp.timestampMs,
            receivedAtMs: item.receivedAtMs,
          );
        },
        afterCommit: () {
          if (ask != null) _queued();
          if (!placed) return; // it has its place since an earlier look
          _sink.committed(
            Gv2MessageWaiting(
              groupId: groupId,
              localMessageId: gv2Hex(waitingId),
            ),
          );
        },
      );
    }

    // The sender signed the header.
    final place = await _placeInLog(group, sender, stamp, item);
    if (place.wait) return const Gv2WaitForSync(holdsLane: true);

    final content = Gv2Content.decode(plaintext);
    final localId = gv2LocalMessageId(
      groupId: groupIdBytes,
      senderAccountId: stamp.senderAccountId,
      messageId: stamp.messageId,
    );
    final day = _day();
    Gv2SinkEvent? committed;
    return Gv2Handled(
      conversationId: content is Gv2MessageContent ? groupId : null,
      write: () async {
        committed = null;
        // The read that counts: the chain moves and the key of this message
        // is gone, together with everything below.
        await _keys.read(groupId, sender, open);
        for (final write in place.writes) {
          await write();
        }
        if (content == null) return; // a type this build does not know
        if (!await _inboxStore.markMessage(localId, day: day)) return;
        switch (content) {
          case Gv2MessageContent(:final payload):
            final message = Gv2IncomingMessage(
              groupId: groupId,
              localMessageId: gv2Hex(localId),
              senderSnowId: sender,
              senderDeviceId: stamp.senderDeviceId,
              sentAtMs: stamp.timestampMs,
              receivedAtMs: item.receivedAtMs,
              payload: payload,
            );
            await _sink.message(message);
            committed = Gv2MessageStored(message);
          case Gv2UnsendContent(:final messageId):
            // The id is built from the UNSENDER's account: it can only name
            // a message of its own.
            final target = gv2LocalMessageId(
              groupId: groupIdBytes,
              senderAccountId: stamp.senderAccountId,
              messageId: messageId,
            );
            // A target that arrives after this is never shown.
            await _inboxStore.markMessage(target, day: day);
            await _sink.unsent(
              groupId: groupId,
              localMessageId: gv2Hex(target),
              senderSnowId: sender,
            );
            committed = Gv2MessageUnsent(
              groupId: groupId,
              localMessageId: gv2Hex(target),
              senderSnowId: sender,
            );
          case Gv2ClearHistoryContent(:final beforeMs):
            if (from.role != gv2RoleAdmin && from.role != gv2RoleOwner) {
              return;
            }
            final until = min(beforeMs, stamp.timestampMs);
            await _sink.historyCleared(
              groupId: groupId,
              beforeMs: until,
              bySnowId: sender,
            );
            committed = Gv2HistoryCleared(
              groupId: groupId,
              beforeMs: until,
              bySnowId: sender,
            );
        }
      },
      afterCommit: () {
        if (place.writes.isNotEmpty) _queued();
        final event = committed;
        if (event != null) _sink.committed(event);
      },
    );
  }

  Future<Gv2InboxOutcome> _memberNotice(
    Gv2GroupRow group,
    Gv2MemberRow from,
    Gv2OpenedEnvelope envelope,
    Gv2InboxItem item,
  ) async {
    final groupId = group.groupId;
    final sender = from.snowId!;
    final stamp = envelope.stamp;
    final payload = gv2VerifyMemberNotice(
      groupId: gv2Unhex(groupId),
      envelope: envelope,
      memberPub: from.memberPub,
    );
    if (payload == null) return const Gv2Dropped();
    // The member key is the same in every membership of an account: a
    // notice from before this membership is not about it. And a notice
    // older than the digests of handled envelopes are kept could be a
    // replay this device no longer recognises.
    final age = item.receivedAtMs - stamp.timestampMs;
    if (stamp.revision < from.joinedRevision ||
        age > gv2InboxRetention.inMilliseconds ||
        age < -gv2NoticeClockSkew.inMilliseconds) {
      return const Gv2Dropped();
    }
    // A notice is acted on once. Its message id is under the member
    // signature; sealing the same notice again under a new nonce makes a new
    // digest (the inbox would take it) but not a new id.
    final localId = gv2LocalMessageId(
      groupId: gv2Unhex(groupId),
      senderAccountId: stamp.senderAccountId,
      messageId: stamp.messageId,
    );
    if (await _inboxStore.messageHandled(localId)) return const Gv2Dropped();
    final place = await _placeInLog(group, sender, stamp, item);
    if (place.wait) return const Gv2WaitForSync(holdsLane: true);

    final writes = [...place.writes];
    var again = false;
    int? actedAtMs;
    if (_same(payload, gv2NoticeMemberReset)) {
      // The member lost its keys: it has to be given this device's again —
      // on a new 1:1 session, the old one is gone with them. The session is
      // dropped and the head confirmed at most once a while per member: a
      // member announcing resets without end would otherwise make every
      // device do a new X3DH with it each time.
      final now = _nowMs();
      final last = _resetActedAtMs[sender];
      again = last != null && now - last < gv2NoticeEvery.inMilliseconds;
      // Recorded once the notice is handled (afterCommit): a failed attempt
      // — the session could not be put aside — is tried again in full.
      if (!again) {
        await _pairwise.peerLostSessions(sender);
        actedAtMs = now;
      }
      writes.add(() => _keys.forgetDeliveries(groupId, member: sender));
      if (!again && group.membership == Gv2Membership.active) {
        final confirmed = [
          for (final m in await _groups.confirmedMembers(groupId)) m.ciphertext,
        ];
        if (gv2HeadConfirmersFor(
          from.ciphertext,
          confirmed,
        ).contains(group.myCiphertext)) {
          final confirm = await _pairwise.prepareConfirmHead(groupId, sender);
          if (confirm != null) writes.add(confirm);
        }
      }
    }
    final day = _day();
    return Gv2Handled(
      write: () async {
        if (!await _inboxStore.markMessage(localId, day: day)) return;
        for (final write in writes) {
          await write();
        }
      },
      afterCommit: () {
        final acted = actedAtMs;
        if (acted != null) _resetActedAtMs[sender] = acted;
        _queued();
      },
    );
  }

  /// Compare the place in the log that [sender] stamped an (authenticated)
  /// envelope with against this device's log. See the file notes.
  Future<_Place> _placeInLog(
    Gv2GroupRow group,
    String sender,
    Gv2EnvelopeStamp stamp,
    Gv2InboxItem item,
  ) async {
    final groupId = group.groupId;
    Future<_Place> ask(Future<Gv2InboxWrite?> prepared) async {
      final write = await prepared;
      return _Place.go([?write]);
    }

    if (stamp.revision > group.revision) {
      // Only a sync that STARTED after the envelope arrived says anything
      // about what the server serves.
      if (!item.syncReachedSince(group.lastSyncAtMs)) {
        return const _Place.wait();
      }
      return ask(_pairwise.prepareRequestHead(groupId, sender));
    }
    final held = await _groups.head(groupId, stamp.revision);
    if (held != null && !_same(held.chain, stamp.chain)) {
      return ask(_pairwise.prepareRequestHead(groupId, sender));
    }
    if (stamp.revision < group.revision) {
      return ask(_pairwise.prepareNotifyBehind(groupId, sender));
    }
    return const _Place.go([]);
  }

  // ---------------------------------------------------------------------------
  // Syncing
  // ---------------------------------------------------------------------------

  /// Catch [groupId] up with its change log and do what follows from it.
  /// Called by the inbox, one call at a time per group.
  @override
  Future<void> syncGroup(String groupId) async {
    final last = _syncedAtMs[groupId];
    if (last != null) {
      final wait = gv2SyncFloor.inMilliseconds - (_nowMs() - last);
      if (wait > 0) await _sleep(Duration(milliseconds: wait));
    }
    final Gv2SyncResult result;
    try {
      result = await _sync.sync(groupId);
    } finally {
      _syncedAtMs[groupId] = _nowMs();
    }
    _lastSync[groupId] = result;
    await _afterSync(groupId, result);
  }

  Future<void> _afterSync(String groupId, Gv2SyncResult result) async {
    await _sync.checkMembers(groupId);
    await _forgetFormerMembers(groupId);
    await _pairwise.settleWithheld(groupId);
    await _confirmAlone(groupId, result);
    await _pairwise.afterSync(groupId, result);
    if (result.applied.isNotEmpty) {
      try {
        _sink.groupChanged(groupId, result.applied);
      } catch (_) {
        // What the app does with the news cannot undo the sync.
      }
    }
    // A removal makes the next message need a new key; a confirmation or a
    // released hold lets held rows go.
    _queued();
  }

  /// A member waiting for a confirmation of the head that is the ONLY
  /// member at the server's head has nobody to ask — and nobody to keep
  /// anything from: keys and messages go to the members of the state this
  /// device holds, and that state has no other member. (A server that hides
  /// later joins only makes this device talk to nobody; one that hides a
  /// removal shows the removed member, and then this device is not alone.)
  /// It counts as confirmed.
  Future<void> _confirmAlone(String groupId, Gv2SyncResult result) async {
    const reached = {Gv2SyncStatus.upToDate, Gv2SyncStatus.advanced};
    if (!reached.contains(result.status)) return;
    final group = await _groups.group(groupId);
    if (group == null ||
        !group.stateLoaded ||
        group.membership != Gv2Membership.awaitingConfirm) {
      return;
    }
    final members = await _groups.memberRows(groupId);
    if (members.length != 1 || members.single.ciphertext != group.myCiphertext) {
      return;
    }
    await _groups.setMembership(groupId, Gv2Membership.active);
  }

  /// Erase the Sender Keys received from, and the records of keys given to,
  /// accounts that are not confirmed members of [groupId] (any more).
  Future<void> _forgetFormerMembers(String groupId) async {
    final group = await _groups.group(groupId);
    if (group == null || !group.stateLoaded) return;
    // While members are unchecked their accounts are not known.
    if ((await _groups.membersToCheck(groupId, limit: 1)).isNotEmpty) return;
    const inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
    final members = inside.contains(group.membership)
        ? {for (final m in await _groups.confirmedMembers(groupId)) ?m.snowId}
        // This account is out: nobody's key, and no record of a key given,
        // is of use any more.
        : <String>{};
    await _keys.keepOnly(groupId, members, me: _me);
  }

  /// A change of this account was accepted and stored for [groupId] (it did
  /// not come through a sync): do what a sync would do afterwards with the
  /// keys — erase what belongs to accounts that are no longer members.
  Future<void> afterOwnChange(String groupId) =>
      _forgetFormerMembers(groupId);

  /// Before the outbox sends to [groupId]: check its members and, with
  /// [sync], first catch it up with its log (after the envelopes that are
  /// waiting in its lane). Never throws.
  Future<void> prepareSend(String groupId, {required bool sync}) async {
    try {
      if (!sync) {
        await _sync.checkMembers(groupId);
        return;
      }
      final inbox = _inbox;
      if (inbox != null) {
        await inbox.requestSync(groupId);
      } else {
        await syncGroup(groupId);
      }
    } catch (_) {
      // The outbox looks at what the group is now and waits when it has to.
    }
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// Queue [content] of this account for [groupId]. [expiresInSeconds]: how
  /// long the server keeps undelivered copies (a disappearing message);
  /// 0 = as long as it keeps anything. [alsoWrite] runs in the same
  /// transaction (the app stores its own copy of the message there). The
  /// message leaves once this account is a confirmed member and the group
  /// is on no hold; until then it waits in the outbox.
  ///
  /// Throws [Gv2NotSendable] when this account is not in the group or the
  /// group is frozen.
  Future<Gv2QueuedMessage> send(
    String groupId,
    Gv2Content content, {
    int expiresInSeconds = 0,
    Future<void> Function(Gv2QueuedMessage queued)? alsoWrite,
  }) async {
    final messageId = gv2NewMessageId();
    final now = _nowMs();
    final queued = Gv2QueuedMessage(
      messageId: messageId,
      localMessageId: gv2Hex(
        gv2LocalMessageId(
          groupId: gv2Unhex(groupId),
          senderAccountId: gv2AccountIdOfSnowId(_me),
          messageId: messageId,
        ),
      ),
      timestampMs: now,
    );
    await _groups.transaction(() async {
      await _sendable(groupId);
      await _outbox.enqueueContent(
        groupId: groupId,
        content: Gv2OutboxContent(
          messageId: messageId,
          timestampMs: now,
          expiresIn: expiresInSeconds,
          silent: content is! Gv2MessageContent,
          plaintext: content.encode(),
        ),
        nowMs: now,
      );
      await alsoWrite?.call(queued);
    });
    _queued();
    return queued;
  }

  /// Tell the group that its change log has moved (after a change of this
  /// account was accepted). Unauthenticated by design: members fetch the
  /// log and believe that.
  Future<void> noticeChange(String groupId) async {
    await _groups.transaction(() async {
      await _sendable(groupId);
      await _outbox.enqueueChangeNotice(groupId: groupId, nowMs: _nowMs());
    });
    _queued();
  }

  /// Tell the group that this device lost its Sender Keys (a restore):
  /// members give it their keys again, and one of them confirms the head.
  /// [alsoWrite] runs in the same transaction.
  Future<void> announceReset(
    String groupId, {
    Future<void> Function()? alsoWrite,
  }) async {
    await _groups.transaction(() async {
      await _sendable(groupId);
      await _outbox.enqueueMemberNotice(
        groupId: groupId,
        payload: gv2NoticeMemberReset,
        nowMs: _nowMs(),
      );
      await alsoWrite?.call();
    });
    _queued();
  }

  Future<void> _sendable(String groupId) async {
    final group = await _groups.group(groupId);
    const inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
    if (group == null ||
        group.hold == Gv2Hold.frozen ||
        !inside.contains(group.membership)) {
      throw const Gv2NotSendable();
    }
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
