/// @file        gv2_outbox.dart
/// @description Group protocol v2 — the outbox. What this device has to send
///              is written here first (in the same transaction as whatever
///              decided it), then sent: a crash, a lost connection, a missing
///              endorsement or this device's own unconfirmed membership only
///              delay it (design §5.5, §7.3, §8, §9.3). Pairwise
///              messages are sealed when they are sent, each for one
///              recipient; messages to the group are encrypted with the
///              Sender Key of the moment they are sent and go to every
///              confirmed member in one envelope. Both travel the login-free
///              group send path.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (P5.6: the own Sender Key is replaced once older than gv2OwnKeyMaxAge (7 days); what became of a message (sent, given up) is recorded in the transaction that takes its row out of the queue — recordOutcome; a message could read "sending" for good; a row that waits behind an earlier row of its lane loses a time of its own that has passed — the app woke every second behind a row backing off; endorsements for another revision catch the group up and look again in the next pass, once per group and run — not a failed attempt with its backoff; Gv2Outbox.takeBackContent; takeBackContent(): queued content messages taken back (leaving that could not be made)). Earlier 2026-11-21 (P5.6: endorsements are refetched only when the server refused the token — not for its own trouble, "busy"). Earlier 2026-11-20 (a change of this device whose answer never came makes the log stale: the message syncs first). Earlier 2026-11-13
///
/// @functions
///  - Gv2OutboxStore: the only writer of gv2_outbox
///  - Gv2OutboxStore.enqueuePairwise(): queue a pairwise message
///  - Gv2OutboxStore.enqueueContent(): queue a message to the group
///  - Gv2OutboxStore.enqueueChangeNotice() / enqueueMemberNotice(): queue a
///    notice to the group
///  - Gv2OutboxContent: a queued message to the group
///  - Gv2Outbox.flush(): send what is due
///  - Gv2OutboxSend: the send request (Gv2Transport.send in the app)
///  - Gv2SendTokens / Gv2CredentialTokens: send tokens (from the credentials)
///  - Gv2OutboxEvent: what became of a queued message (sent, given up)
///  - Gv2OutboxStore.enqueueCreate() / enqueueInvite() / release(): the
///    create request of a group and its 1:1 invites
///  - Gv2OutboxActions / Gv2ActionOutcome: who runs those rows
///
/// Notes:
///  - Order: rows are sent in queue order, and to one recipient strictly one
///    after the other — the next row goes only once the one before it was
///    accepted by the server. A row that waits, failed or is backing off
///    holds back the later rows to the same recipient, across flushes too
///    (a session reset must reach the peer before what is sealed on the new
///    session). The messages to one group keep their order the same way;
///    notices to a group are a lane of their own (a held message does not
///    hold back the change notice that gets this device confirmed).
///  - Each request of pairwise messages carries one extra entry addressed
///    to this account itself, of the same size as a real one and of random
///    bytes (design §7.3: a sender spreading per-recipient messages would
///    otherwise leave "the group minus the sender" behind). This device's
///    own inbox drops it: it does not unseal.
///  - A message to the group goes to every confirmed member AND to this
///    account itself (the recipient set is the roster, not the roster minus
///    the sender); the request asks for no push to this account.
///  - Before a message to the group is sent:
///      1. the group's log is fresh — a sync that reached the server's head
///         started within [gv2SendFreshness] (design §8) — and every member
///         is checked;
///      2. this device's Sender Key is newer than the last removal it knows
///         of: otherwise a new key is made first (design §8: a key made
///         before a removal never encrypts a later message, also when the
///         app died between applying the removal and making the key);
///      3. every confirmed member has been given the key. Members that have
///         not are queued their key and the message waits for the next
///         pass. Each pass sends the pairwise rows before the rows to the
///         groups, so a key that can go leaves before the message it opens
///         (a key that cannot — its recipient unreachable — does not hold
///         the message back: that recipient asks for the key later).
///    The message is then encrypted and sealed in one transaction that
///    checks all of this again against the state it stamps the envelope
///    with.
///  - A message is encrypted when it is SENT. A failed send is encrypted
///    again on the next attempt (one position of the chain is spent); the
///    message id stays, so receivers that got both copies show one.
///  - A Sender Key and a message leave only once this device's membership is
///    confirmed and the group is on no hold (design §5.5); notices and the
///    other pairwise messages go at once.
///  - A recipient who is no longer a member (or whose account is gone) has
///    its rows dropped. A recipient not confirmed yet is waited for.
///  - The create request of a group and the 1:1 invites do not travel the
///    group send path: the outbox keeps and retries them, Gv2GroupActions runs
///    them. In a pass they come after the pairwise rows, in queue order —
///    the create request before the invites it makes possible.
///  - A row that keeps failing backs off (30 s doubling, at most an hour) and
///    is dropped after 30 days.
///  - Nothing here logs: rows hold message content and recipients.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../storage/database.dart';
import '../storage/tables/gv2_tables.dart';
import 'gv2_codec.dart';
import 'gv2_credentials.dart';
import 'gv2_envelope.dart';
import 'gv2_keys.dart';
import 'gv2_member_check.dart';
import 'gv2_pairwise.dart';
import 'gv2_pairwise_crypto.dart';
import 'gv2_sender_key_store.dart';
import 'gv2_store.dart';
import 'gv2_transport.dart';

part 'gv2_outbox.g.dart';

/// How long a row may wait to be sent.
const Duration gv2OutboxRetention = Duration(days: 30);

/// Entries per send request (one of them the extra entry to this account).
const int gv2OutboxEntriesPerRequest = 100;

const int _backoffBaseMs = 30 * 1000;
const int _backoffMaxMs = 60 * 60 * 1000;

/// While a recipient is not confirmed yet, its rows are looked at again
/// after this long.
const int _waitMs = 60 * 1000;

/// A message to the group is sent only when a sync that reached the
/// server's head started at most this long ago (design §8).
const Duration gv2SendFreshness = Duration(minutes: 10);

/// This device's own Sender Key of a group is replaced before the next
/// message once it is this old (and after a removal). What its keys open of
/// what it sent — should the device be taken — reaches back at most this
/// far, with the records of keys given pruned after the retention on top
/// (Gv2Store.pruneOld). Idle senders replace nothing: the new key is made
/// when there is something to send.
const Duration gv2OwnKeyMaxAge = Duration(days: 7);

/// Passes of one flush. Each pass after the first follows a row that was
/// sent or a state that changed; this only bounds a fault.
const int _maxPasses = 1000;

/// Queues entries; one result per entry, in order (Gv2Transport.send).
/// [noPush]: account ids that get no push for this request.
typedef Gv2OutboxSend =
    Future<List<Gv2SendResult>> Function(
      List<Gv2SendEntry> entries, {
      List<Uint8List> noPush,
    });

/// A queued message to the group: the payload of a content row.
///   messageId(16) ‖ timestampMs(u64) ‖ expiresIn(u32) ‖ silent(1) ‖ plaintext
class Gv2OutboxContent {
  /// The 16-byte message id of the envelope header — the same for every
  /// attempt to send this message.
  final Uint8List messageId;

  /// When the message was written (this device's clock, Unix MILLISECONDS).
  final int timestampMs;

  /// SECONDS until the server drops undelivered copies; 0 = keep.
  final int expiresIn;

  /// No push and no badge (an unsend, a clear).
  final bool silent;

  /// The content plaintext (gv2_content.dart).
  final Uint8List plaintext;

  const Gv2OutboxContent({
    required this.messageId,
    required this.timestampMs,
    required this.expiresIn,
    required this.silent,
    required this.plaintext,
  });

  static const int _headerLen = gv2MessageIdLen + 8 + 4 + 1;

  Uint8List encode() {
    if (messageId.length != gv2MessageIdLen ||
        timestampMs < 0 ||
        expiresIn < 0 ||
        expiresIn > 0xFFFFFFFF ||
        plaintext.isEmpty ||
        plaintext.length > gv2MaxContentPlaintext) {
      throw ArgumentError('gv2 outbox: not a sendable message');
    }
    final out = Uint8List(_headerLen + plaintext.length);
    final view = ByteData.sublistView(out);
    out.setAll(0, messageId);
    view.setUint64(gv2MessageIdLen, timestampMs, Endian.big);
    view.setUint32(gv2MessageIdLen + 8, expiresIn, Endian.big);
    out[gv2MessageIdLen + 12] = silent ? 1 : 0;
    out.setAll(_headerLen, plaintext);
    return out;
  }

  /// The message in [payload], or null when it is not one.
  static Gv2OutboxContent? decode(Uint8List payload) {
    if (payload.length <= _headerLen) return null;
    final view = ByteData.sublistView(payload);
    final timestampMs = view.getInt64(gv2MessageIdLen, Endian.big);
    final silent = payload[gv2MessageIdLen + 12];
    if (timestampMs < 0 || silent > 1) return null;
    return Gv2OutboxContent(
      messageId: Uint8List.fromList(payload.sublist(0, gv2MessageIdLen)),
      timestampMs: timestampMs,
      expiresIn: view.getUint32(gv2MessageIdLen + 8, Endian.big),
      silent: silent == 1,
      plaintext: Uint8List.fromList(payload.sublist(_headerLen)),
    );
  }
}

/// What an action made of a row.
enum Gv2ActionOutcome {
  /// Done: the row leaves the outbox.
  done,

  /// Nothing to do any more: the row leaves the outbox.
  drop,

  /// Not now (the group is not ready for it): looked at again later, not
  /// counted as a failure.
  wait,

  /// Failed: the row backs off.
  failed,
}

/// Runs the rows that do not go through the group send path: the create
/// request of a group and the 1:1 invite messages (Gv2GroupActions).
abstract interface class Gv2OutboxActions {
  /// Run [row] (kind create or invite) now. Throws only on a failure of
  /// this device.
  Future<Gv2ActionOutcome> run(Gv2OutboxRow row);

  /// [row] waited longer than the outbox keeps a row and was removed.
  Future<void> gaveUp(Gv2OutboxRow row);
}

/// What became of a queued message to the group.
sealed class Gv2OutboxEvent {
  final String groupId;

  /// Lowercase hex of the local message id (gv2LocalMessageId).
  final String localMessageId;
  const Gv2OutboxEvent(this.groupId, this.localMessageId);
}

/// The server took the message.
final class Gv2MessageSent extends Gv2OutboxEvent {
  const Gv2MessageSent(super.groupId, super.localMessageId);
}

/// The message will not be sent: this account is no longer in the group,
/// the group is frozen, or it waited longer than the outbox keeps a row.
final class Gv2MessageGivenUp extends Gv2OutboxEvent {
  const Gv2MessageGivenUp(super.groupId, super.localMessageId);
}

/// Send tokens, as the outbox needs them (Gv2Credentials in the app).
abstract interface class Gv2SendTokens {
  /// A token for exactly [ciphertexts] of [groupId], or null when an
  /// endorsement is missing or about to expire.
  Future<Uint8List?> sendToken(String groupId, List<String> ciphertexts);

  /// Fetch the endorsements of [groupId] again; says how that ended.
  Future<Gv2EndorsementOutcome> refreshEndorsements(String groupId);
}

/// [Gv2SendTokens] over this account's credentials.
class Gv2CredentialTokens implements Gv2SendTokens {
  final Gv2Credentials _credentials;
  Gv2CredentialTokens(this._credentials);

  @override
  Future<Uint8List?> sendToken(
    String groupId,
    List<String> ciphertexts,
  ) async => (await _credentials.sendToken(groupId, ciphertexts))?.token;

  @override
  Future<Gv2EndorsementOutcome> refreshEndorsements(String groupId) =>
      _credentials.refreshEndorsements(groupId);
}

@DriftAccessor(tables: [Gv2OutboxRows])
class Gv2OutboxStore extends DatabaseAccessor<SnowDatabase>
    with _$Gv2OutboxStoreMixin {
  Gv2OutboxStore(super.db);

  /// Queue [message] for its recipient in [groupId]. A pending message of
  /// the same kind to the same recipient is replaced (only the latest head
  /// confirmation, key request, ... matters), except Sender Keys: those of
  /// different chains all go, the same key twice does not.
  Future<void> enqueuePairwise({
    required String groupId,
    required Gv2PairwiseMessage message,
    required int nowMs,
  }) {
    final recipient = message.recipientSnowId;
    final payload = message.encode();
    return transaction(() async {
      final pending =
          await (select(gv2OutboxRows)..where(
                (o) =>
                    o.groupId.equals(groupId) &
                    o.kind.equalsValue(Gv2OutboxKind.pairwise) &
                    o.recipient.equals(recipient),
              ))
              .get();
      for (final row in pending) {
        if (row.payload.length < 3 || row.payload[2] != message.body.type) {
          continue;
        }
        if (message.body is Gv2SenderKeyBody) {
          if (_same(row.payload, payload)) return;
        } else {
          await (delete(
            gv2OutboxRows,
          )..where((o) => o.localId.equals(row.localId))).go();
        }
      }
      await into(gv2OutboxRows).insert(
        Gv2OutboxRowsCompanion.insert(
          groupId: groupId,
          kind: Gv2OutboxKind.pairwise,
          recipient: Value(recipient),
          payload: payload,
          createdAtMs: nowMs,
        ),
      );
    });
  }

  /// Queue a message to [groupId].
  Future<void> enqueueContent({
    required String groupId,
    required Gv2OutboxContent content,
    required int nowMs,
  }) => into(gv2OutboxRows).insert(
    Gv2OutboxRowsCompanion.insert(
      groupId: groupId,
      kind: Gv2OutboxKind.content,
      payload: content.encode(),
      createdAtMs: nowMs,
    ),
  );

  /// Queue "the change log has moved" for [groupId]. One waiting notice is
  /// enough: it is sealed with the head of the moment it is sent.
  Future<void> enqueueChangeNotice({
    required String groupId,
    required int nowMs,
  }) =>
      _enqueueNotice(groupId, Gv2OutboxKind.changeNotice, Uint8List(0), nowMs);

  /// Queue a notice signed with this account's member signing key (for
  /// example gv2NoticeMemberReset). The same notice waiting twice is one.
  Future<void> enqueueMemberNotice({
    required String groupId,
    required Uint8List payload,
    required int nowMs,
  }) {
    if (payload.isEmpty || payload.length > gv2MaxMemberNoticePayload) {
      throw ArgumentError('gv2 outbox: not a member notice payload');
    }
    return _enqueueNotice(groupId, Gv2OutboxKind.memberNotice, payload, nowMs);
  }

  Future<void> _enqueueNotice(
    String groupId,
    Gv2OutboxKind kind,
    Uint8List payload,
    int nowMs,
  ) => transaction(() async {
    final pending =
        await (select(gv2OutboxRows)..where(
              (o) => o.groupId.equals(groupId) & o.kind.equalsValue(kind),
            ))
            .get();
    if (pending.any((row) => _same(row.payload, payload))) return;
    await into(gv2OutboxRows).insert(
      Gv2OutboxRowsCompanion.insert(
        groupId: groupId,
        kind: kind,
        payload: payload,
        createdAtMs: nowMs,
      ),
    );
  });

  /// Queue the revision-0 [entry] of a group this device is creating.
  Future<void> enqueueCreate({
    required String groupId,
    required Uint8List entry,
    required int nowMs,
  }) => into(gv2OutboxRows).insert(
    Gv2OutboxRowsCompanion.insert(
      groupId: groupId,
      kind: Gv2OutboxKind.create,
      payload: entry,
      createdAtMs: nowMs,
    ),
  );

  /// Queue the 1:1 invite for [recipient] with its one-time [inviteSeed].
  /// Not sent before [notBeforeMs] (the INVITE entry may still be on its
  /// way to the server — see [release]). Returns the row's local id.
  Future<int> enqueueInvite({
    required String groupId,
    required String recipient,
    required Uint8List inviteSeed,
    required int nowMs,
    int notBeforeMs = 0,
  }) => into(gv2OutboxRows).insert(
    Gv2OutboxRowsCompanion.insert(
      groupId: groupId,
      kind: Gv2OutboxKind.invite,
      recipient: Value(recipient),
      payload: inviteSeed,
      createdAtMs: nowMs,
      notBeforeMs: Value(notBeforeMs),
    ),
  );

  /// [localId] may be sent now.
  Future<void> release(int localId) =>
      (update(gv2OutboxRows)..where((o) => o.localId.equals(localId))).write(
        const Gv2OutboxRowsCompanion(notBeforeMs: Value(0)),
      );

  /// The rows after [after] (a local id; 0 = from the start), in queue
  /// order — due or not: a row that is not due yet still holds back the
  /// later rows to its recipient.
  Future<List<Gv2OutboxRow>> page({required int after, int limit = 200}) =>
      (select(gv2OutboxRows)
            ..where((o) => o.localId.isBiggerThanValue(after))
            ..orderBy([(o) => OrderingTerm.asc(o.localId)])
            ..limit(limit))
          .get();

  /// The earliest time a row that is held back may go (local clock,
  /// milliseconds), or null when no row is held back: when to look at the
  /// outbox again if nothing else happens.
  Future<int?> nextWakeMs() async {
    final earliest = gv2OutboxRows.notBeforeMs.min();
    final row =
        await (selectOnly(gv2OutboxRows)
              ..addColumns([earliest])
              ..where(gv2OutboxRows.notBeforeMs.isBiggerThanValue(0)))
            .getSingle();
    return row.read(earliest);
  }

  /// Every row, in queue order. For diagnostics and tests.
  Future<List<Gv2OutboxRow>> allRows() => (select(
    gv2OutboxRows,
  )..orderBy([(o) => OrderingTerm.asc(o.localId)])).get();

  /// [localId] is sent, or given up.
  Future<void> remove(int localId) =>
      (delete(gv2OutboxRows)..where((o) => o.localId.equals(localId))).go();

  /// Take back the content messages [messageIds] (16-byte envelope ids) of
  /// [groupId] that are still queued. Returns how many were.
  Future<int> takeBackContent(String groupId, List<Uint8List> messageIds) =>
      transaction(() async {
        final rows = await (select(gv2OutboxRows)
              ..where(
                (o) =>
                    o.groupId.equals(groupId) &
                    o.kind.equalsValue(Gv2OutboxKind.content),
              ))
            .get();
        var taken = 0;
        for (final row in rows) {
          if (row.payload.length < 16) continue;
          final id = row.payload.sublist(0, 16);
          if (messageIds.any((m) => _sameBytes(m, id))) {
            await remove(row.localId);
            taken++;
          }
        }
        return taken;
      });

  /// [localId] is not sent before [notBeforeMs]; [failed] counts an attempt.
  Future<void> later(
    int localId, {
    required int notBeforeMs,
    required bool failed,
  }) => customUpdate(
    'UPDATE gv2_outbox SET not_before_ms = ?, '
    'attempts = attempts + ? WHERE local_id = ?',
    variables: [
      Variable.withInt(notBeforeMs),
      Variable.withInt(failed ? 1 : 0),
      Variable.withInt(localId),
    ],
    updates: {gv2OutboxRows},
  );

  /// Rows created before [beforeMs] are given up. Returns the ones somebody
  /// has to be told about: messages to a group, create requests, invites.
  Future<List<Gv2OutboxRow>> expire(int beforeMs) => transaction(() async {
    final old = await (select(
      gv2OutboxRows,
    )..where((o) => o.createdAtMs.isSmallerThanValue(beforeMs))).get();
    if (old.isEmpty) return const <Gv2OutboxRow>[];
    await (delete(
      gv2OutboxRows,
    )..where((o) => o.createdAtMs.isSmallerThanValue(beforeMs))).go();
    const told = {
      Gv2OutboxKind.content,
      Gv2OutboxKind.create,
      Gv2OutboxKind.invite,
    };
    return [
      for (final row in old)
        if (told.contains(row.kind)) row,
    ];
  });
}

/// One row on its way.
/// What one pass over the queue already did per group.
class _Pass {
  /// Groups whose endorsements were fetched again in this pass.
  final Set<String> refreshed = {};

  /// Groups caught up in this pass (endorsements for another revision):
  /// their rows wait for the next pass.
  final Set<String> resynced = {};
}

class _Ready {
  final Gv2OutboxRow row;
  final Gv2SendEntry entry;
  const _Ready(this.row, this.entry);
}

/// A message to a group, sealed and ready to go.
class _Sealed {
  final Gv2SendEntry entry;
  final List<Gv2MemberRow> recipients;
  final String? localMessageId;
  const _Sealed(this.entry, this.recipients, this.localMessageId);
}

/// Sends what the outbox holds. One per signed-in account.
class Gv2Outbox {
  final Gv2OutboxStore _store;
  final Gv2Store _groups;
  final Gv2SenderKeyStore _keys;
  final Gv2SendTokens _tokens;
  final Gv2PairwiseCrypto _crypto;
  final Gv2OutboxSend _send;
  final Future<String?> Function() _mySnowId;
  final Future<String> Function() _myDeviceId;
  final Future<Gv2SigningKey> Function(Uint8List groupId) _memberKey;
  final Future<int> Function(String groupId) _giveKeys;
  final Future<void> Function(String groupId, {required bool sync}) _prepare;
  final void Function(Gv2OutboxEvent event) _event;
  final Future<void> Function(Gv2OutboxEvent event) _record;
  final void Function(String groupId, String snowId) _memberDeleted;
  final Gv2OutboxActions? _actions;
  final int Function() _nowMs;
  final Random _random;

  /// Rows read from the queue at a time.
  final int pageSize;

  /// Groups caught up in this run because the server's endorsements were
  /// for another revision of the log: once per group and run, so a server
  /// that never agrees cannot keep the outbox syncing.
  final Set<String> _resynced = {};

  /// [mySnowId] returns this device's account, [myDeviceId] its device id
  /// (36 printable ASCII characters), [memberKey] this account's member
  /// signing key for a group. [giveKeys] queues this device's Sender Key
  /// for every confirmed member of a group that lacks it and returns how
  /// many (Gv2PairwiseService.giveKeys). [prepareGroup] checks the group's
  /// members and, with `sync`, first catches the group up with its log
  /// (Gv2Messaging.prepareSend); it must not throw. [recordOutcome] writes
  /// what became of a message of this account (sent, given up) INSIDE the
  /// transaction that takes its row out of the queue — the app's copy and
  /// the queue never disagree (a status written afterwards was lost when
  /// the app ended in between, and the message read "sending" for good);
  /// it must touch only the database. [onEvent] hears the same after the
  /// commit. [onMemberDeleted] is called when a
  /// member's account turned out to be deleted (its own verified proof came
  /// back from a send). [actions] runs the create and
  /// invite rows (Gv2GroupActions); without it those rows wait.
  Gv2Outbox({
    required Gv2OutboxStore store,
    required Gv2Store groups,
    required Gv2SenderKeyStore keys,
    required Gv2SendTokens tokens,
    required Gv2PairwiseCrypto crypto,
    required Gv2OutboxSend send,
    required Future<String?> Function() mySnowId,
    required Future<String> Function() myDeviceId,
    required Future<Gv2SigningKey> Function(Uint8List groupId) memberKey,
    required Future<int> Function(String groupId) giveKeys,
    required Future<void> Function(String groupId, {required bool sync})
    prepareGroup,
    void Function(Gv2OutboxEvent event)? onEvent,
    Future<void> Function(Gv2OutboxEvent event)? recordOutcome,
    void Function(String groupId, String snowId)? onMemberDeleted,
    Gv2OutboxActions? actions,
    int Function()? nowMs,
    Random? random,
    this.pageSize = 200,
  }) : _store = store,
       _groups = groups,
       _keys = keys,
       _tokens = tokens,
       _crypto = crypto,
       _send = send,
       _mySnowId = mySnowId,
       _myDeviceId = myDeviceId,
       _memberKey = memberKey,
       _giveKeys = giveKeys,
       _prepare = prepareGroup,
       _event = onEvent ?? ((_) {}),
       _record = recordOutcome ?? ((_) async {}),
       _memberDeleted = onMemberDeleted ?? ((_, _) {}),
       _actions = actions,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _random = random ?? Random.secure();

  Future<void>? _flushing;
  bool _again = false;

  /// Take back the content messages [messageIds] of [groupId] that are
  /// still queued (see Gv2OutboxStore.takeBackContent). Returns how many.
  Future<int> takeBackContent(String groupId, List<Uint8List> messageIds) =>
      _store.takeBackContent(groupId, messageIds);

  /// Send every row that is due. Concurrent calls share one run (a call
  /// during a run makes it look once more). Never throws for what the
  /// network or the server can cause.
  Future<void> flush() {
    _again = true;
    return _flushing ??= _run().whenComplete(() => _flushing = null);
  }

  Future<void> _run() async {
    while (_again) {
      _again = false;
      _resynced.clear();
      final me = await _mySnowId();
      final givenUp = <Gv2OutboxEvent>[];
      final expired = await _store.transaction(() async {
        final rows = await _store.expire(
          _nowMs() - gv2OutboxRetention.inMilliseconds,
        );
        for (final row in rows) {
          final event = _outcomeOf(row, me, sent: false);
          if (event != null) {
            await _record(event);
            givenUp.add(event);
          }
        }
        return rows;
      });
      givenUp.forEach(_event);
      for (final row in expired) {
        if (row.kind == Gv2OutboxKind.content) {
          // Recorded above.
        } else {
          try {
            await _actions?.gaveUp(row);
          } catch (_) {
            // The row is gone either way.
          }
        }
      }
      // One row per recipient goes in a pass; passes repeat while rows go.
      for (var i = 0; i < _maxPasses && await _pass(); i++) {}
    }
  }

  /// One pass over the whole queue: first every pairwise row that can go,
  /// then the rows to the groups — a Sender Key that is on its way leaves
  /// before the message it opens, wherever the two stand in the queue.
  /// Returns true when a row was sent, or something changed that lets a row
  /// go in another pass.
  Future<bool> _pass() async {
    final pass = _Pass();
    final pairwise = await _scan(groupRows: false, pass: pass);
    final group = await _scan(groupRows: true, pass: pass);
    return pairwise || group;
  }

  /// One scan of the queue, in order, for the pairwise rows or for the rows
  /// to the groups. For each (group, recipient) — and for the messages and
  /// the notices of each group — only the first row can go: a later one
  /// never overtakes one that waits, failed, is backing off, or whose send
  /// is not confirmed yet.
  Future<bool> _scan({
    required bool groupRows,
    required _Pass pass,
  }) async {
    final blocked = <String>{};
    var sent = false;
    var after = 0;
    while (true) {
      final rows = await _store.page(after: after, limit: pageSize);
      if (rows.isEmpty) return sent;
      after = rows.last.localId;
      final ready = <_Ready>[];

      Future<void> sendReady() async {
        for (var i = 0; i < ready.length; i += gv2OutboxEntriesPerRequest - 1) {
          final chunk = ready.sublist(
            i,
            min(i + gv2OutboxEntriesPerRequest - 1, ready.length),
          );
          if (await _sendChunk(chunk, pass)) sent = true;
        }
        ready.clear();
      }

      for (final row in rows) {
        if ((row.kind != Gv2OutboxKind.pairwise) != groupRows) continue;
        if (groupRows) {
          final lane = switch (row.kind) {
            Gv2OutboxKind.content => '${row.groupId}|m',
            Gv2OutboxKind.create => '${row.groupId}|c',
            Gv2OutboxKind.invite => '${row.groupId}|i:${row.recipient}',
            _ => '${row.groupId}|n',
          };
          if (!blocked.add(lane)) {
            await _parkBehind(row);
            continue;
          }
          if (row.notBeforeMs > _nowMs()) continue; // backing off
          try {
            final isAction =
                row.kind == Gv2OutboxKind.create ||
                row.kind == Gv2OutboxKind.invite;
            if (isAction
                ? await _actionRow(row)
                : await _groupRow(row, pass)) {
              sent = true;
            }
          } catch (_) {
            // This device failed on the row (database, a key that cannot
            // be derived): it backs off like any other failure.
            await _failed(row);
          }
          continue;
        }
        final recipient = row.recipient;
        if (recipient == null) {
          await _store.remove(row.localId); // not a row this build writes
          continue;
        }
        final lane = '${row.groupId}:$recipient';
        if (blocked.contains(lane)) {
          await _parkBehind(row);
          continue;
        }
        final due = row.notBeforeMs <= _nowMs();

        final Gv2MemberRow member;
        switch (await _check(row, recipient)) {
          case _Drop():
            await _store.remove(row.localId);
            continue;
          case _Held():
            // Held for this device's own reason: what else goes to the
            // recipient is not held up by it.
            if (due) {
              await _store.later(
                row.localId,
                notBeforeMs: _nowMs() + _waitMs,
                failed: false,
              );
            }
            continue;
          case _Wait():
            blocked.add(lane);
            if (due) {
              await _store.later(
                row.localId,
                notBeforeMs: _nowMs() + _waitMs,
                failed: false,
              );
            }
            continue;
          case _Go(member: final m):
            member = m;
        }
        // Whatever becomes of this row, nothing later goes to the same
        // recipient in this pass.
        blocked.add(lane);
        if (!due) continue; // backing off
        try {
          if (row.payload[2] == gv2PairwiseTypeSessionReset) {
            await _crypto.resetSession(recipient);
          }
          final (token, resynced) = await _token(row.groupId, [
            member.ciphertext,
          ], pass);
          if (resynced) {
            // Caught up with the log: the next pass looks again.
            sent = true;
            continue;
          }
          if (token == null) {
            await _failed(row);
            continue;
          }
          final sealed = await _crypto.seal(recipient, row.payload);
          ready.add(
            _Ready(
              row,
              Gv2SendEntry(
                token: token,
                recipients: [gv2AccountIdOfSnowId(recipient)],
                envelope: sealed,
                silent: true,
              ),
            ),
          );
        } catch (_) {
          // No session (offline, refused identity), no certificate, ... One
          // row that cannot be sealed must not stop the others; it backs
          // off and is given up after the retention.
          await _failed(row);
        }
      }

      await sendReady();
    }
  }

  /// [row] waits behind an earlier row of its lane. A time of its own that
  /// has passed means nothing any more — it goes when the row before it
  /// does — and is cleared: the wake-up time (Gv2OutboxStore.nextWakeMs) is
  /// the earliest time of a row, and a past one behind a row that backs off
  /// for an hour woke the app every second for that hour.
  Future<void> _parkBehind(Gv2OutboxRow row) async {
    if (row.notBeforeMs > 0 && row.notBeforeMs <= _nowMs()) {
      await _store.release(row.localId);
    }
  }

  /// Hand a create or invite row to the actions. Returns true when it is
  /// done.
  Future<bool> _actionRow(Gv2OutboxRow row) async {
    final outcome = await _actions?.run(row) ?? Gv2ActionOutcome.wait;
    switch (outcome) {
      case Gv2ActionOutcome.done:
        await _store.remove(row.localId);
        return true;
      case Gv2ActionOutcome.drop:
        await _store.remove(row.localId);
        return false;
      case Gv2ActionOutcome.wait:
        await _store.later(
          row.localId,
          notBeforeMs: _nowMs() + _waitMs,
          failed: false,
        );
        return false;
      case Gv2ActionOutcome.failed:
        await _failed(row);
        return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Rows to the group
  // ---------------------------------------------------------------------------

  static const _inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};

  /// Handle one row that goes to the whole group. Returns true when it was
  /// sent, or when something changed so that it can go in another pass.
  Future<bool> _groupRow(Gv2OutboxRow row, _Pass pass) async {
    final groupId = row.groupId;
    final me = await _mySnowId();
    final isContent = row.kind == Gv2OutboxKind.content;
    final content = isContent ? Gv2OutboxContent.decode(row.payload) : null;

    Future<bool> drop() async {
      await _settle(row, me, sent: false);
      return false;
    }

    Future<bool> wait() async {
      await _store.later(
        row.localId,
        notBeforeMs: _nowMs() + _waitMs,
        failed: false,
      );
      return false;
    }

    Future<bool> fail() async {
      await _failed(row);
      return false;
    }

    // Whether the row can go at all, and whether it has to wait.
    Future<bool?> standing() async {
      final group = await _groups.group(groupId);
      if (me == null ||
          group == null ||
          group.hold == Gv2Hold.frozen ||
          !_inside.contains(group.membership) ||
          (isContent && content == null)) {
        return null; // drop
      }
      if (!group.stateLoaded) return false;
      // A message leaves only from a confirmed member of a group on no
      // hold; a notice goes at once.
      return !isContent ||
          (group.membership == Gv2Membership.active &&
              group.hold == Gv2Hold.none);
    }

    if (await standing() == null) return drop();

    // The log fresh (messages only) and every member checked. A message
    // held back by a withheld hold asks the server again on every attempt:
    // only a sync that reaches the withheld head releases the hold. A change
    // of this device whose answer never came makes the log stale until a
    // sync settles it: the server may have taken a removal this device has
    // not applied (Gv2Groups.changeSentAtMs).
    bool fresh(Gv2GroupRow g) =>
        g.changeSentAtMs == null &&
        _nowMs() - g.lastSyncAtMs <= gv2SendFreshness.inMilliseconds;
    final before = (await _groups.group(groupId))!;
    await _prepare(
      groupId,
      sync:
          before.stateLoaded &&
          // An unanswered change: anything to the group goes from the log
          // as it is now (a notice then carries the head it reached).
          (before.changeSentAtMs != null ||
              (isContent &&
                  before.membership == Gv2Membership.active &&
                  (before.hold == Gv2Hold.withheld ||
                      (before.hold == Gv2Hold.none && !fresh(before))))),
    );
    switch (await standing()) {
      case null:
        return drop();
      case false:
        return wait();
      case true:
        break;
    }
    if (isContent && !fresh((await _groups.group(groupId))!)) return fail();
    if ((await _groups.membersToCheck(groupId, limit: 1)).isNotEmpty) {
      return wait();
    }

    if (isContent) {
      // A key made before the last removal never encrypts this message.
      await _groups.transaction(() async {
        final g = await _groups.group(groupId);
        if (g != null && await _keyIsStale(g, me!)) {
          await _keys.createOwn(groupId, me);
          await _groups.setMyKeyRevision(groupId, g.revision, atMs: _nowMs());
        }
      });
      // The keys leave first: the message goes in the next pass, after
      // the pairwise rows of that pass.
      if (await _giveKeys(groupId) > 0) return true;
    }

    final recipients = await _recipients(groupId);
    final mine = (await _groups.group(groupId))!.myCiphertext;
    if (!recipients.any((m) => m.ciphertext == mine)) {
      // This account is not confirmed in its own view of the group.
      return fail();
    }
    if (recipients.length == 1) {
      // Nobody else to send to: done.
      await _settle(row, me, sent: true);
      return true;
    }
    final (token, resynced) = await _token(groupId, [
      for (final m in recipients) m.ciphertext,
    ], pass);
    // Caught up with the log: looked at again in the next pass, on the
    // roster as it is now — not a failed attempt.
    if (resynced) return true;
    if (token == null) return fail();

    final sealed = await _seal(row, content, me!, recipients, token);
    if (sealed == null) return true; // the state moved meanwhile: next pass

    List<Gv2SendResult>? results;
    try {
      results = await _send([sealed.entry], noPush: [gv2AccountIdOfSnowId(me)]);
    } catch (_) {
      results = null;
    }
    if (results == null || results.length != 1) return fail();
    final result = results.single;
    if (!result.ok) {
      // The server did not take the token: the endorsements this device
      // holds are not the server's any more. Any other refusal ("busy": the
      // server's own trouble) is only tried again later — fetching
      // endorsements for it would add load to a server that is struggling.
      if (result.error == 'invalid_token' && pass.refreshed.add(groupId)) {
        try {
          final outcome = await _tokens.refreshEndorsements(groupId);
          if (await _resyncIf(groupId, outcome, pass)) return true;
        } catch (_) {
          // Tried again with the next attempt.
        }
      }
      return fail();
    }
    // Recipients over their inflow budget got nothing and are not named
    // (design §6.3): the message counts as sent.
    await _settle(row, me, sent: true);
    await _noteReach(groupId, sealed.recipients, result);
    return true;
  }

  /// True when [group] needs a new own Sender Key before a message: it has
  /// none, a member left the group after the key was made, or the key is
  /// older than [gv2OwnKeyMaxAge].
  Future<bool> _keyIsStale(Gv2GroupRow group, String me) async {
    final made = group.myKeyRevision;
    if (made == null || (group.lastRemovalRevision ?? -1) > made) return true;
    final madeAt = group.myKeyAtMs;
    if (madeAt == null ||
        _nowMs() - madeAt > gv2OwnKeyMaxAge.inMilliseconds) {
      return true;
    }
    return await _keys.ownCurrent(group.groupId, me) == null;
  }

  /// Who a row to the group goes to: the confirmed members whose account
  /// still exists — this account among them.
  Future<List<Gv2MemberRow>> _recipients(String groupId) async => [
    for (final m in await _groups.confirmedMembers(groupId))
      if (m.reach != Gv2Reach.deleted && m.snowId != null) m,
  ];

  /// Seal [row] for [recipients] with the group's state of this moment.
  /// One transaction: the state the envelope is stamped with is the state
  /// it was checked against. Null when that state is no longer the one the
  /// row was prepared for (a member joined, left or was removed meanwhile).
  Future<_Sealed?> _seal(
    Gv2OutboxRow row,
    Gv2OutboxContent? content,
    String me,
    List<Gv2MemberRow> recipients,
    Uint8List token,
  ) async {
    final groupId = row.groupId;
    final groupIdBytes = gv2Unhex(groupId);
    final deviceId = await _myDeviceId();
    final memberKey = row.kind == Gv2OutboxKind.memberNotice
        ? await _memberKey(groupIdBytes)
        : null;
    final myAccountId = gv2AccountIdOfSnowId(me);

    return _groups.transaction(() async {
      final group = await _groups.group(groupId);
      if (group == null || group.hold == Gv2Hold.frozen) return null;
      final now = await _recipients(groupId);
      if (now.length != recipients.length) return null;
      for (var i = 0; i < now.length; i++) {
        if (now[i].ciphertext != recipients[i].ciphertext) return null;
      }
      if ((await _groups.membersToCheck(groupId, limit: 1)).isNotEmpty) {
        return null;
      }
      if (content != null) {
        if (group.membership != Gv2Membership.active ||
            group.hold != Gv2Hold.none ||
            await _keyIsStale(group, me)) {
          return null;
        }
        final own = (await _keys.ownCurrent(groupId, me))!;
        final have = await _keys.deliveredTo(groupId, own.chainId);
        for (final m in now) {
          if (m.snowId != me && !have.contains(m.snowId)) return null;
        }
      }

      final keys = Gv2EnvelopeKeys.derive(group.masterKey, groupIdBytes);
      Gv2EnvelopeStamp stamp(Uint8List messageId, int timestampMs) =>
          Gv2EnvelopeStamp(
            senderAccountId: myAccountId,
            senderDeviceId: deviceId,
            messageId: messageId,
            revision: group.revision,
            chain: group.chain,
            timestampMs: timestampMs,
          );
      final Uint8List envelope;
      switch (row.kind) {
        case Gv2OutboxKind.content:
          envelope = await _keys.sealOwn(
            groupId,
            me,
            (senderKeys) => gv2SealContentEnvelope(
              keys: keys,
              stamp: stamp(content!.messageId, content.timestampMs),
              senderKeys: senderKeys,
              plaintext: content.plaintext,
            ),
          );
        case Gv2OutboxKind.changeNotice:
          envelope = gv2SealChangeNoticeEnvelope(
            keys: keys,
            stamp: stamp(gv2NewMessageId(), _nowMs()),
          );
        case Gv2OutboxKind.memberNotice:
          envelope = gv2SealMemberNoticeEnvelope(
            keys: keys,
            stamp: stamp(gv2NewMessageId(), _nowMs()),
            memberKey: memberKey!,
            payload: row.payload,
          );
        case Gv2OutboxKind.pairwise:
        case Gv2OutboxKind.create:
        case Gv2OutboxKind.invite:
          throw StateError('gv2 outbox: not a row to the group');
      }
      final expiresIn = content == null || content.expiresIn == 0
          ? null
          : content.expiresIn;
      return _Sealed(
        Gv2SendEntry(
          token: token,
          recipients: [for (final m in now) gv2AccountIdOfSnowId(m.snowId!)],
          envelope: envelope,
          silent: content == null || content.silent,
          expiresIn: expiresIn,
        ),
        now,
        content == null ? null : _localId(row, me),
      );
    });
  }

  /// What the server said about the recipients of a message that was sent:
  /// an account it does not know is unreachable — and nothing more, unless
  /// the account's OWN deletion proof says it is gone (design §9.7).
  Future<void> _noteReach(
    String groupId,
    List<Gv2MemberRow> recipients,
    Gv2SendResult result,
  ) async {
    final unknown = {for (final id in result.unknownRecipients) gv2Hex(id)};
    final proofs = {
      for (final d in result.deleted) gv2Hex(d.accountId): d.proof,
    };
    for (final m in recipients) {
      final snowId = m.snowId!;
      final accountId = gv2Hex(gv2AccountIdOfSnowId(snowId));
      var reach = unknown.contains(accountId)
          ? Gv2Reach.unreachable
          : Gv2Reach.ok;
      final proof = proofs[accountId];
      final accountKey = m.accountPublicKey;
      final issuedAtMs = m.certIssuedAtMs;
      if (proof != null && accountKey != null && issuedAtMs != null) {
        final verdict = gv2JudgeDeletion(
          member: Gv2ConfirmedMember(
            snowId: snowId,
            accountPublicKey: accountKey,
            issuedAtMs: issuedAtMs,
          ),
          proof: proof,
        );
        if (verdict == Gv2DeletionVerdict.deleted) reach = Gv2Reach.deleted;
      }
      if (reach != m.reach) {
        await _groups.setReach(groupId, m.ciphertext, reach);
        // The account's own proof says it is gone: whoever may remove
        // members takes it out of the group (design §9.7).
        if (reach == Gv2Reach.deleted) {
          try {
            _memberDeleted(groupId, snowId);
          } catch (_) {
            // The message is sent either way.
          }
        }
      }
    }
  }

  String _localId(Gv2OutboxRow row, String me) {
    final content = Gv2OutboxContent.decode(row.payload)!;
    return gv2Hex(
      gv2LocalMessageId(
        groupId: gv2Unhex(row.groupId),
        senderAccountId: gv2AccountIdOfSnowId(me),
        messageId: content.messageId,
      ),
    );
  }

  /// Take [row] out of the queue. For a message of this account, what
  /// became of it ([sent], or given up) is recorded in the same transaction
  /// and then told.
  Future<void> _settle(Gv2OutboxRow row, String? me, {required bool sent}) async {
    final event = _outcomeOf(row, me, sent: sent);
    await _store.transaction(() async {
      await _store.remove(row.localId);
      if (event != null) await _record(event);
    });
    if (event != null) _event(event);
  }

  /// What became of [row] when it is a message of this account; null for
  /// any other row.
  Gv2OutboxEvent? _outcomeOf(
    Gv2OutboxRow row,
    String? me, {
    required bool sent,
  }) {
    if (row.kind != Gv2OutboxKind.content || me == null) return null;
    if (Gv2OutboxContent.decode(row.payload) == null) return null;
    final localId = _localId(row, me);
    return sent
        ? Gv2MessageSent(row.groupId, localId)
        : Gv2MessageGivenUp(row.groupId, localId);
  }

  // ---------------------------------------------------------------------------
  // Pairwise rows
  // ---------------------------------------------------------------------------

  Future<_Verdict> _check(Gv2OutboxRow row, String recipient) async {
    final group = await _groups.group(row.groupId);
    if (group == null ||
        group.hold == Gv2Hold.frozen ||
        !_inside.contains(group.membership) ||
        row.payload.length < 3) {
      return const _Drop();
    }
    if (row.payload[2] == gv2PairwiseTypeSenderKey &&
        (group.membership != Gv2Membership.active ||
            group.hold != Gv2Hold.none)) {
      // No key leaves before the head is confirmed, nor while this device
      // does not know the roster (a hold).
      return const _Held();
    }
    final member = await _groups.memberBySnowId(row.groupId, recipient);
    if (member == null) {
      // Not a member by name — or one whose account is not worked out yet.
      final unchecked = await _groups.membersToCheck(row.groupId, limit: 1);
      return unchecked.isEmpty ? const _Drop() : const _Wait();
    }
    return switch (member.checkState) {
      Gv2MemberCheckState.confirmed => _Go(member),
      Gv2MemberCheckState.unchecked => const _Wait(),
      _ => const _Drop(), // its account could not be confirmed
    };
  }

  /// A send token for [ciphertexts] in [groupId]; endorsements are fetched
  /// again once per group and pass when one is missing. `resynced`: the
  /// server's endorsements were for another revision of the log and the
  /// group was caught up — the row is looked at again in the next pass.
  Future<(Uint8List?, bool resynced)> _token(
    String groupId,
    List<String> ciphertexts,
    _Pass pass,
  ) async {
    var token = await _tokens.sendToken(groupId, ciphertexts);
    if (token != null) return (token, false);
    // Caught up in this pass already: every row of the group waits for the
    // next pass, not only the one that asked first.
    if (pass.resynced.contains(groupId)) return (null, true);
    if (pass.refreshed.add(groupId)) {
      final outcome = await _tokens.refreshEndorsements(groupId);
      if (await _resyncIf(groupId, outcome, pass)) return (null, true);
      token = await _tokens.sendToken(groupId, ciphertexts);
    }
    return (token, false);
  }

  /// When the server's endorsements are for another revision than this
  /// device's log, catch the group up — once per group and run — and return
  /// true: one sync settles it, where a backoff would only wait (rows of
  /// new members, head confirms, keys for them).
  Future<bool> _resyncIf(
    String groupId,
    Gv2EndorsementOutcome outcome,
    _Pass pass,
  ) async {
    if (outcome != Gv2EndorsementOutcome.revisionDiffers ||
        !_resynced.add(groupId)) {
      return false;
    }
    await _prepare(groupId, sync: true);
    pass.resynced.add(groupId);
    return true;
  }

  /// Send [chunk] in one request. Returns true when a row of it was sent.
  Future<bool> _sendChunk(List<_Ready> chunk, _Pass pass) async {
    // The extra entry to this account, sealed-looking and as long as a real
    // one, placed at random.
    final groupId = chunk[_random.nextInt(chunk.length)].row.groupId;
    final group = await _groups.group(groupId);
    final me = await _mySnowId();
    final (selfToken, resynced) = group == null || me == null
        ? (null, false)
        : await _token(groupId, [group.myCiphertext], pass);
    if (resynced) return true; // caught up: the next pass looks again
    if (selfToken == null) {
      for (final r in chunk) {
        await _failed(r.row);
      }
      return false;
    }
    final model = chunk[_random.nextInt(chunk.length)].entry.envelope;
    final decoy = Uint8List(model.length);
    for (var i = 1; i < decoy.length; i++) {
      decoy[i] = _random.nextInt(256);
    }
    decoy[0] = model[0];
    final decoyAt = _random.nextInt(chunk.length + 1);
    final entries = [for (final r in chunk) r.entry]
      ..insert(
        decoyAt,
        Gv2SendEntry(
          token: selfToken,
          recipients: [gv2AccountIdOfSnowId(me!)],
          envelope: decoy,
          silent: true,
        ),
      );

    List<Gv2SendResult>? results;
    try {
      results = await _send(entries);
    } catch (_) {
      results = null;
    }
    if (results == null || results.length != entries.length) {
      for (final r in chunk) {
        await _failed(r.row);
      }
      return false;
    }
    var sent = false;
    for (var i = 0, j = 0; i < entries.length; i++) {
      if (i == decoyAt) continue;
      final r = chunk[j++];
      final result = results[i];
      if (result.ok && result.unknownRecipients.isNotEmpty) {
        await _store.remove(r.row.localId); // the account is gone
      } else if (result.ok && result.throttledRecipients == 0) {
        await _store.remove(r.row.localId);
        sent = true;
      } else {
        await _failed(r.row);
      }
    }
    return sent;
  }

  Future<void> _failed(Gv2OutboxRow row) {
    final delay = min(_backoffBaseMs << min(row.attempts, 20), _backoffMaxMs);
    return _store.later(
      row.localId,
      notBeforeMs: _nowMs() + delay,
      failed: true,
    );
  }
}

sealed class _Verdict {
  const _Verdict();
}

final class _Go extends _Verdict {
  final Gv2MemberRow member;
  const _Go(this.member);
}

/// Waits for the recipient (its account not checked yet).
final class _Wait extends _Verdict {
  const _Wait();
}

/// Waits for this device (its membership not confirmed yet).
final class _Held extends _Verdict {
  const _Held();
}

final class _Drop extends _Verdict {
  const _Drop();
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
