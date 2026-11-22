/// @file        gv2_groups_test.dart
/// @description Group protocol v2 from nothing to a conversation, without an
///              emulator: one device creates a group and invites, the other
///              takes the invite in, accepts, is confirmed, and both
///              exchange messages. Each device runs its real stack — store,
///              sync (the real Gv2Sync), inbox, outbox, pairwise service,
///              messaging layer and group actions — on real 1:1 sessions and
///              real zkgroup member ciphertexts. Stand-ins: the server (the
///              real state machine and real head signatures behind the
///              transport's interface, the group queue, and the 1:1 channel
///              that carries invite messages). Covers creating (and a lost
///              answer), inviting (and a crash after the server accepted),
///              what an invite must satisfy, accepting alone or at once,
///              declining, being invited again, and the limits.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-22 (SC-18: Gv2OutboxSend takes the entries only; SealedSenderService takes trustedServerKeys). Earlier 2026-11-21 (X1: invites from a blocked account are dropped; P5.6: an invite row kept while an INVITE answer is unsettled; two changes of one group go one after the other; inviteMany; checkLeave). Earlier 2026-11-21 (P5.6: invites kept by the 1:1 queue are taken in by Gv2GroupActions.takeInvite on a drain). Earlier 2026-11-21 (P5.6: nothing is accepted by itself — acceptsInvites is a stand-in user who taps Accept; an invite passed on by someone else holds nothing). Earlier 2026-11-21 (the 256-account limit on create and invite). Earlier 2026-11-20 (P5.2: lost answers to REMOVE / LEAVE / role changes, the unanswered-change mark)
///
/// @functions
///  - main(): the test groups below.
///  - _Server: Gv2Transport over an in-memory log per group.
///  - _Keys: Gv2Credentials whose presentation is the member ciphertext.
///  - _World / _Device: the devices and what connects them.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/account_deletion_proof.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/crypto/sealed_sender.dart';
import 'package:snowchat/core/group_v2/gv2_backup.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_content.dart';
import 'package:snowchat/core/group_v2/gv2_credentials.dart';
import 'package:snowchat/core/group_v2/gv2_events.dart';
import 'package:snowchat/core/group_v2/gv2_groups.dart';
import 'package:snowchat/core/group_v2/gv2_inbox.dart';
import 'package:snowchat/core/group_v2/gv2_invite.dart';
import 'package:snowchat/core/group_v2/gv2_keys.dart';
import 'package:snowchat/core/group_v2/gv2_messaging.dart';
import 'package:snowchat/core/group_v2/gv2_outbox.dart';
import 'package:snowchat/core/group_v2/gv2_pairwise_crypto.dart';
import 'package:snowchat/core/group_v2/gv2_pairwise_service.dart';
import 'package:snowchat/core/group_v2/gv2_state_machine.dart';
import 'package:snowchat/core/group_v2/gv2_store.dart';
import 'package:snowchat/core/group_v2/gv2_sync.dart';
import 'package:snowchat/core/group_v2/gv2_transport.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';

import '../crypto/identity_test_support.dart';
import 'gv2_session_support.dart';
import 'gv2_test_support.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One group on the stand-in server.
class _Log {
  final List<Gv2Entry> entries = [];
  final List<Gv2GroupState> states = [];

  /// Former members (ciphertext hex) and the revision that took them out:
  /// they may read the log up to there.
  final Map<String, int> removedAt = {};
  Gv2GroupState get state => states.last;

  void add(Gv2Entry entry, Gv2GroupState next) {
    if (states.isNotEmpty) {
      for (final key in state.members.keys) {
        if (!next.members.containsKey(key)) removedAt[key] = next.revision;
      }
    }
    for (final key in next.members.keys) {
      removedAt.remove(key);
    }
    entries.add(entry);
    states.add(next);
  }
}

/// The server's group state API: the real state machine, real head
/// signatures. A presentation is the caller's member ciphertext.
class _Server extends Fake implements Gv2Transport {
  final Gv2SigningKey headKey = Gv2SigningKey.fromSeed(
    gv2TestSha('gv2 groups test — head key'),
  );
  final Map<String, _Log> logs = {};

  bool offline = false;

  /// Take the request, then lose the answer.
  bool loseAnswers = false;

  /// With [loseAnswers]: the network is gone from then on ([offline]).
  bool offlineAfterLoss = false;
  bool rejectCreates = false;

  /// Sign heads with another key.
  bool forgeHeads = false;

  /// Refuse every change with 429 rate_limited.
  bool rateLimitChanges = false;
  int creates = 0;
  int changes = 0;

  /// Called when a change request arrives, before it is looked at.
  Future<void> Function()? onChange;

  /// Reading a log or a state fails on the server's side.
  bool brokenReads = false;
  int reads = 0;

  Gv2Head _head(Uint8List groupId, _Log log) {
    final key = forgeHeads
        ? Gv2SigningKey.fromSeed(gv2TestSha('not the server'))
        : headKey;
    return Gv2Head(
      revision: log.state.revision,
      chain: log.state.chain,
      headSig: key.sign(
        gv2HeadMessage(groupId, log.state.revision, log.state.chain),
      ),
    );
  }

  Uint8List headSig(Uint8List groupId, Gv2GroupState state) =>
      headKey.sign(gv2HeadMessage(groupId, state.revision, state.chain));

  void _online() {
    if (offline) throw const Gv2NetworkException();
  }

  Gv2Entry _decode(Uint8List bytes) {
    try {
      return gv2DecodeEntry(bytes);
    } on Gv2DecodeException {
      throw const Gv2ApiException(400, 'malformed_entry');
    }
  }

  Gv2GroupState _apply(Gv2GroupState? state, Uint8List groupId, Gv2Entry e) {
    try {
      return gv2ApplyEntry(state, groupId, e);
    } on Gv2Reject catch (r) {
      throw Gv2ApiException(422, 'entry_rejected', reason: r.code.wire);
    }
  }

  /// The log and how far [presentation] may read it (null = to its head).
  (_Log, int?) _readable(Uint8List groupId, Uint8List presentation) {
    final log = logs[gv2Hex(groupId)];
    if (log == null) throw const Gv2ApiException(404, 'group_not_found');
    final who = gv2Hex(presentation);
    if (log.state.members.containsKey(who) ||
        log.state.pending.containsKey(who)) {
      return (log, null);
    }
    final removed = log.removedAt[who];
    if (removed == null) throw const Gv2ApiException(403, 'not_a_member');
    return (log, removed);
  }

  /// Display names by snowId, and how often they were asked for.
  final Map<String, String> nicknames = {};
  int nameCalls = 0;

  @override
  Future<Map<String, String?>> names({
    required Uint8List token,
    required List<Uint8List> recipients,
  }) async {
    _online();
    nameCalls++;
    return {
      for (final r in recipients) gv2Hex(r): nicknames['snow${gv2Hex(r)}'],
    };
  }

  @override
  Future<Gv2Head> create({
    required Uint8List groupId,
    required Uint8List publicParams,
    required Uint8List presentation,
    required Uint8List entry,
  }) async {
    _online();
    creates++;
    final id = gv2Hex(groupId);
    if (logs.containsKey(id)) throw const Gv2ApiException(409, 'group_exists');
    if (rejectCreates) {
      throw const Gv2ApiException(422, 'entry_rejected', reason: 'permission');
    }
    final decoded = _decode(entry);
    if (!_same(decoded.actor, presentation)) {
      throw const Gv2ApiException(403, 'actor_mismatch');
    }
    final log = _Log()..add(decoded, _apply(null, groupId, decoded));
    logs[id] = log;
    if (loseAnswers) throw const Gv2NetworkException();
    return _head(groupId, log);
  }

  @override
  Future<Gv2Head> change({
    required Uint8List groupId,
    required Uint8List presentation,
    required Uint8List entry,
  }) async {
    _online();
    changes++;
    await onChange?.call();
    if (rateLimitChanges) throw const Gv2ApiException(429, 'RATE_LIMITED');
    final log = logs[gv2Hex(groupId)];
    if (log == null) throw const Gv2ApiException(404, 'group_not_found');
    final decoded = _decode(entry);
    if (!_same(decoded.actor, presentation)) {
      throw const Gv2ApiException(403, 'actor_mismatch');
    }
    if (decoded.revision != log.state.revision + 1) {
      throw Gv2ApiException(
        409,
        'revision_conflict',
        head: _head(groupId, log),
      );
    }
    final next = _apply(log.state, groupId, decoded);
    log.add(decoded, next);
    if (loseAnswers) {
      if (offlineAfterLoss) offline = true;
      throw const Gv2NetworkException();
    }
    return _head(groupId, log);
  }

  @override
  Future<Gv2LogPage> log({
    required Uint8List groupId,
    required Uint8List presentation,
    required int from,
    int? limit,
  }) async {
    _online();
    reads++;
    if (brokenReads) throw const Gv2ApiException(500, 'internal');
    final (log, upTo) = _readable(groupId, presentation);
    final last = upTo ?? log.entries.length - 1;
    return Gv2LogPage(
      // A former member is shown its removal and nothing after it.
      head: upTo == null ? _head(groupId, log) : null,
      removed: upTo != null,
      entries: [
        for (var r = from; r <= last; r++)
          Gv2LogEntry(
            revision: r,
            entry: gv2EncodeEntry(log.entries[r]),
            headSig: headSig(groupId, log.states[r]),
          ),
      ],
      more: false,
    );
  }

  @override
  Future<Gv2Snapshot> snapshot({
    required Uint8List groupId,
    required Uint8List presentation,
    required int at,
  }) async {
    _online();
    reads++;
    if (brokenReads) throw const Gv2ApiException(500, 'internal');
    final (log, upTo) = _readable(groupId, presentation);
    if (at < 0 || at >= log.states.length || (upTo != null && at > upTo)) {
      throw const Gv2ApiException(403, 'revision_not_readable');
    }
    return Gv2Snapshot(
      state: log.states[at].copy(),
      headSig: headSig(groupId, log.states[at]),
    );
  }
}

class _Keys extends Fake implements Gv2Credentials {
  final _Server server;
  final Uint8List accountId;
  _Keys(this.server, this.accountId);

  @override
  Future<Gv2ServerKeysRow> serverKeys() async {
    if (server.offline) throw const Gv2NetworkException();
    return Gv2ServerKeysRow(
      slot: 0,
      serverPublicParams: gv2TestBytes('server params', 673),
      headPublicKey: server.headKey.publicKey,
    );
  }

  @override
  Future<Uint8List> presentation(Uint8List masterKey) async =>
      ZkGroup.encryptMember(masterKey: masterKey, accountId: accountId);

  @override
  Future<void> renew() async {}
}

/// Send tokens as the real ones behave towards a roster: there is one only
/// for members this device still holds a row of (storing a change erases
/// the endorsements of whoever it takes out).
class _RosterTokens implements Gv2SendTokens {
  final Gv2Store store;
  _RosterTokens(this.store);

  @override
  Future<Uint8List?> sendToken(String groupId, List<String> ciphertexts) async {
    final held = {for (final m in await store.memberRows(groupId)) m.ciphertext};
    if (!ciphertexts.every(held.contains)) return null;
    return Gv2TestTokens.tokenFor(groupId, ciphertexts);
  }

  @override
  Future<Gv2EndorsementOutcome> refreshEndorsements(String groupId) async =>
      Gv2EndorsementOutcome.stored;
}

class _Sink implements Gv2MessageSink {
  final List<Gv2IncomingMessage> messages = [];
  final List<String> changed = [];

  List<String> get texts => [for (final m in messages) utf8.decode(m.payload)];

  @override
  Future<void> message(Gv2IncomingMessage message) async =>
      messages.add(message);

  @override
  Future<void> unsent({
    required String groupId,
    required String localMessageId,
    required String senderSnowId,
  }) async {}

  @override
  Future<void> historyCleared({
    required String groupId,
    required int beforeMs,
    required String bySnowId,
  }) async {}

  @override
  Future<bool> waiting({
    required String groupId,
    required String localMessageId,
    required int sentAtMs,
    required int receivedAtMs,
  }) async => true;

  @override
  Future<void> outgoing({
    required String groupId,
    required String localMessageId,
    required bool sent,
  }) async {}

  @override
  void committed(Gv2SinkEvent event) {}

  @override
  void groupChanged(String groupId, List<Gv2Entry> applied) =>
      changed.add(groupId);
}

/// The server's copy of one account's group key backup.
class _BackupApi implements Gv2BackupApi {
  final _World world;
  final String snowId;
  _BackupApi(this.world, this.snowId);

  static String _tag(Uint8List bytes) =>
      base64Encode(hash.sha256.convert(bytes).bytes);

  @override
  Future<Gv2BackupBlob> fetch() async {
    if (world.server.offline) throw const Gv2BackupUnreachable();
    final blob = world.backups[snowId];
    return blob == null
        ? const Gv2BackupBlob(null, null)
        : Gv2BackupBlob(blob, _tag(blob));
  }

  @override
  Future<String?> store(Uint8List blob, String? ifMatch) async {
    if (world.server.offline) throw const Gv2BackupUnreachable();
    final held = world.backups[snowId];
    if ((held == null ? null : _tag(held)) != ifMatch) return null;
    world.backups[snowId] = blob;
    return _tag(blob);
  }
}

class _InviteInTransit {
  final _Device from;
  final String to;
  final Uint8List bytes;
  const _InviteInTransit(this.from, this.to, this.bytes);
}

class _Device {
  final _World world;
  final String name;
  final Uint8List accountSeed;
  final TestParty party;
  final SnowDatabase db;
  final _Sink sink = _Sink();
  final List<Duration> sleeps = [];
  final List<Gv2InviteOutcome> inviteOutcomes = [];
  late final _RosterTokens tokens = _RosterTokens(db.gv2Store);

  /// Removals of members whose account proved itself deleted, in flight.
  final List<Future<void>> removals = [];
  late final Gv2Sync sync;
  late final Gv2PairwiseService service;
  late final Gv2Messaging messaging;
  late final Gv2Inbox inbox;
  late final Gv2GroupActions groups;
  late final Gv2Outbox outbox;
  late final Gv2Backup backup;
  late final Gv2TestSessions sessions;

  /// How often the group actions said "something was queued" (the app
  /// then sends, and looks at the backup).
  int queuedCalls = 0;

  /// Accept every invite as soon as it is stored (a user who taps Accept
  /// at once — the app accepts nothing by itself).
  bool acceptsInvites = false;

  /// The accounts this user blocked (X1).
  final Set<String> blocked = {};

  /// The 1:1 channel takes nothing from this device.
  bool inviteSendFails = false;

  _Device._(this.world, this.name, this.accountSeed, this.party, this.db);

  String get snowId => party.snowId;
  Gv2Store get store => db.gv2Store;

  Uint8List get accountPub => Uint8List.fromList(
    ed.SigningKey(seed: accountSeed).verifyKey.asTypedList,
  );

  Gv2SigningKey memberKey(Uint8List groupId) =>
      Gv2SigningKey.fromSeed(gv2DeriveMemberSeed(accountSeed, groupId));

  /// [epoch]: the binding epoch of this install's session keys (a
  /// reinstall has new keys and binds them later).
  static Future<_Device> create(
    _World world,
    String name, {
    int epoch = gv2TestBindingEpoch,
  }) async {
    final seed = gv2TestSha('gv2 groups test — account $name');
    final party = await TestParty.create(
      accountSeed: seed,
      deviceId: gv2TestDeviceIdOf(name),
      opkCount: 8,
    );
    party.signal.setLocalIdentityBinding(party.localBinding(epoch: epoch));
    gv2TestEpochOf[party] = epoch;
    final db = SnowDatabase(NativeDatabase.memory());
    final d = _Device._(world, name, seed, party, db);
    expect(d.snowId, KeyDerivation.deriveSnowChatId(d.accountPub));
    d.sessions = Gv2TestSessions(party, world);
    final crypto = Gv2SealedPairwiseCrypto(
      sealed: SealedSenderService(trustedServerKeys: [world.serverVerifyKey]),
      certificate: () async => gv2TestCertificate(world.serverKey, party),
      sessions: d.sessions,
    );
    final keys = _Keys(world.server, gv2AccountIdOfSnowId(d.snowId));
    Future<void> sleep(Duration duration) async {
      d.sleeps.add(duration);
      world.now += duration.inMilliseconds;
    }

    d.sync = Gv2Sync(
      store: db.gv2Store,
      transport: world.server,
      credentials: keys,
      pinnedAccountKey: (_) async => null,
      nowMs: () => world.now,
    );
    d.service = Gv2PairwiseService(
      groups: db.gv2Store,
      keys: db.gv2SenderKeyStore,
      outbox: db.gv2OutboxStore,
      crypto: crypto,
      serverHeadKey: () async => world.server.headKey.publicKey,
      mySnowId: d.snowId,
      nowMs: () => world.now,
    );
    d.messaging = Gv2Messaging(
      groups: db.gv2Store,
      keys: db.gv2SenderKeyStore,
      inboxStore: db.gv2InboxStore,
      outbox: db.gv2OutboxStore,
      pairwise: d.service,
      sync: d.sync,
      sink: d.sink,
      mySnowId: d.snowId,
      nowMs: () => world.now,
      sleep: sleep,
    );
    d.inbox = Gv2Inbox(
      store: db.gv2InboxStore,
      groups: db.gv2Store,
      handler: d.messaging,
      ack: (_) async {},
      nowMs: () => world.now,
    );
    d.messaging.attach(d.inbox);
    d.groups = Gv2GroupActions(
      groups: db.gv2Store,
      outbox: db.gv2OutboxStore,
      transport: world.server,
      credentials: keys,
      sync: d.sync,
      inbox: d.inbox,
      messaging: d.messaging,
      sink: d.sink,
      mySnowId: d.snowId,
      accountPublicKey: () async => d.accountPub,
      memberKey: (groupId) async => d.memberKey(groupId),
      memberCert: (groupId, issuedAtMs) async => Uint8List.fromList(
        ed.SigningKey(seed: seed)
            .sign(
              gv2MemberCertMessage(
                groupId: groupId,
                memberPub: d.memberKey(groupId).publicKey,
                issuedAtMs: issuedAtMs,
              ),
            )
            .signature
            .asTypedList,
      ),
      sendInvite: (recipient, invite) async {
        if (d.inviteSendFails) return false;
        world.invites.add(_InviteInTransit(d, recipient, invite));
        return true;
      },
      tokens: d.tokens,
      send: (entries) => world.send(entries),
      myDeviceId: () async => party.deviceId,
      onQueued: () => d.queuedCalls++,
      nowMs: () => world.now,
      sleep: sleep,
      isBlocked: (id) async => d.blocked.contains(id),
    );
    d.messaging.attachInvites(d.groups.takeInvite);
    d.outbox = Gv2Outbox(
      store: db.gv2OutboxStore,
      groups: db.gv2Store,
      keys: db.gv2SenderKeyStore,
      tokens: d.tokens,
      crypto: crypto,
      send: (entries) => world.send(entries),
      onMemberDeleted: (groupId, snowId) =>
          d.removals.add(d.groups.removeDeleted(groupId, snowId)),
      mySnowId: () async => d.snowId,
      myDeviceId: () async => party.deviceId,
      memberKey: (groupId) async => d.memberKey(groupId),
      giveKeys: d.service.giveKeys,
      prepareGroup: d.messaging.prepareSend,
      actions: d.groups,
      nowMs: () => world.now,
    );
    d.backup = Gv2Backup(
      groups: db.gv2Store,
      api: _BackupApi(world, d.snowId),
      key: () async => gv2DeriveBackupKey(seed),
      mySnowId: d.snowId,
      nowMs: () => world.now,
      // The delay of a write is gv2_backup_test's; here it is written at once.
      writeDelay: () => Duration.zero,
    );
    return d;
  }

  /// What the app does when it has a connection (Gv2Runtime.pump), as far
  /// as the backup goes: look at the backup, bring restored groups into
  /// use, write the backup.
  Future<Gv2BackupOutcome> pumpBackup() async {
    final first = await backup.sync();
    if (first.restored.isNotEmpty) inbox.groupsChanged();
    await groups.resume();
    await backup.sync();
    return first;
  }

  Future<Gv2GroupRow?> group(String id) => store.group(id);

  Future<Gv2Membership?> standing(String id) async =>
      (await store.group(id))?.membership;

  Future<List<Gv2OutboxKind>> queued() async => [
    for (final r in await db.gv2OutboxStore.allRows()) r.kind,
  ];

  Future<void> say(String id, String text) =>
      messaging.send(id, Gv2MessageContent(_utf8(text)));
}

class _World implements Gv2TestDirectory {
  final ed.SigningKey serverKey = ed.SigningKey(
    seed: gv2TestSha('gv2 groups test — certificate server'),
  );
  late final Uint8List serverVerifyKey = Uint8List.fromList(
    serverKey.verifyKey.asTypedList,
  );
  final _Server server = _Server();
  final Map<String, _Device> devices = {};
  final Map<String, int> _opk = {};
  final List<_InviteInTransit> invites = [];

  /// The group key backups the server keeps, by account.
  final Map<String, Uint8List> backups = {};

  /// Every invite message that was handed over, for replays.
  final List<_InviteInTransit> delivered = [];
  int now = DateTime.now().millisecondsSinceEpoch;
  int _rows = 0;
  int sends = 0;

  /// The 1:1 channel keeps invites back.
  bool holdInvites = false;

  /// Accounts the server no longer has, with the proof it shows.
  final Map<String, AccountDeletionProof> deletedAccounts = {};

  @override
  TestParty party(String snowId) => devices[snowId]!.party;

  @override
  int nextOpk(String snowId) {
    final n = _opk[snowId] ?? 0;
    _opk[snowId] = n + 1;
    return n;
  }

  Future<_Device> add(String name) async {
    final d = await _Device.create(this, name);
    devices[d.snowId] = d;
    return d;
  }

  /// [old]'s account on a new install: an empty database, new session keys
  /// (bound at a later epoch), the same recovery phrase. The old install is
  /// gone.
  Future<_Device> reinstall(_Device old) async {
    await old.db.close();
    _installs++;
    final d = await _Device.create(
      this,
      old.name,
      epoch: gv2TestBindingEpoch + _installs,
    );
    expect(d.snowId, old.snowId);
    devices[d.snowId] = d;
    _opk.remove(d.snowId);
    return d;
  }

  int _installs = 0;

  /// The group queue: hands each envelope to its recipients' inboxes.
  Future<List<Gv2SendResult>> send(List<Gv2SendEntry> entries) async {
    if (server.offline) throw const Gv2NetworkException();
    sends++;
    for (final e in entries) {
      for (final r in e.recipients) {
        final to = devices['snow${gv2Hex(r)}'];
        if (to == null || deletedAccounts.containsKey(to.snowId)) continue;
        now++;
        _rows++;
        await to.inbox.receive([
          Gv2QueueRow(
            id: '00000000-0000-4000-8000-${_rows.toRadixString(16).padLeft(12, '0')}',
            seq: _rows,
            envelope: e.envelope,
          ),
        ]);
      }
    }
    return [
      for (final e in entries)
        Gv2SendResult(
          ok: true,
          error: null,
          delivered: 1,
          unknownRecipients: [
            for (final r in e.recipients)
              if (deletedAccounts.containsKey('snow${gv2Hex(r)}')) r,
          ],
          throttledRecipients: 0,
          deleted: [
            for (final r in e.recipients)
              if (deletedAccounts['snow${gv2Hex(r)}'] case final proof?)
                Gv2DeletedRecipient(
                  accountId: r,
                  accountPublicKey: devices['snow${gv2Hex(r)}']!.accountPub,
                  proof: proof,
                ),
          ],
        ),
    ];
  }

  /// Hand over the invite messages in transit.
  Future<void> deliverInvites() async {
    if (holdInvites) return;
    while (invites.isNotEmpty) {
      final i = invites.removeAt(0);
      delivered.add(i);
      final to = devices[i.to];
      if (to == null) continue;
      final outcome = await to.groups.receiveInvite(i.from.snowId, i.bytes);
      to.inviteOutcomes.add(outcome);
      final invite = Gv2InviteMessage.decode(i.bytes);
      if (!to.acceptsInvites ||
          outcome != Gv2InviteOutcome.stored ||
          invite == null) {
        continue;
      }
      final groupId = gv2Hex(invite.groupId);
      final row = await to.store.group(groupId);
      if (row?.membership != Gv2Membership.invited || !row!.stateLoaded) {
        continue;
      }
      try {
        await to.groups.accept(groupId);
      } on Gv2GroupException {
        // Stays invited, as it would for a user whose tap failed.
      }
    }
  }

  Future<String> _snapshot() async {
    final out = StringBuffer('$sends/${invites.length}/${delivered.length}');
    out.write('/${server.creates}/${server.changes}');
    for (final d in devices.values) {
      for (final g in await d.store.groups()) {
        out.write('|${g.groupId.substring(0, 6)}:${g.revision},');
        out.write('${g.membership.name},${g.hold.name}');
      }
      for (final r in await d.db.gv2OutboxStore.allRows()) {
        out.write(';o${r.localId}:${r.attempts}');
      }
      for (final r in await d.db.gv2InboxStore.allRows()) {
        out.write(';i${r.localId}:${r.state.name}:${r.attempts}');
      }
      out.write(';s${d.sink.messages.length}');
    }
    return out.toString();
  }

  /// Send, deliver and handle until nothing moves any more.
  Future<void> settle() async {
    var before = await _snapshot();
    for (var round = 0; round < 40; round++) {
      for (final d in devices.values) {
        await d.outbox.flush();
      }
      await deliverInvites();
      for (final d in devices.values) {
        await d.inbox.drain();
        await Future.wait(d.removals);
        d.removals.clear();
      }
      final after = await _snapshot();
      if (after == before) return;
      before = after;
    }
    fail('the world does not settle');
  }

  Future<void> close() async {
    for (final d in devices.values) {
      await d.db.close();
    }
  }
}

void main() {
  // Each device has its own in-memory database, on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late _World world;
  late _Server server;
  late _Device alice;
  late _Device bob;
  late _Device carol;

  setUp(() async {
    world = _World();
    server = world.server;
    alice = await world.add('alice');
    bob = await world.add('bob');
    carol = await world.add('carol');
  });
  tearDown(() => world.close());

  /// A group of alice with bob (and carol when [withCarol]) accepted and
  /// confirmed.
  Future<String> established({bool withCarol = false}) async {
    bob.acceptsInvites = true;
    carol.acceptsInvites = true;
    final id = await alice.groups.create(
      title: 'Snow',
      invite: [bob.snowId, if (withCarol) carol.snowId],
    );
    await world.settle();
    expect(await bob.standing(id), Gv2Membership.active);
    if (withCarol) expect(await carol.standing(id), Gv2Membership.active);
    return id;
  }

  group('creating', () {
    test('the group is stored first, told to the server by the outbox, and '
        'nobody hears of it before the server signed its head', () async {
      world.server.offline = true;
      // The server's keys are needed for the title: nothing without them.
      await expectLater(
        alice.groups.create(title: 'Snow', invite: [bob.snowId]),
        throwsA(
          isA<Gv2GroupException>().having(
            (e) => e.reason,
            'reason',
            Gv2GroupFailure.unavailable,
          ),
        ),
      );
      expect(await alice.store.groups(), isEmpty);

      world.server.offline = false;
      final id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      var row = (await alice.group(id))!;
      expect(row.membership, Gv2Membership.creating);
      expect(row.headSig, isNull);
      expect(row.title, 'Snow');
      expect(await alice.queued(), [
        Gv2OutboxKind.create,
        Gv2OutboxKind.invite,
      ]);
      expect(server.logs, isEmpty);

      // Offline: the request waits, and so does the invite.
      server.offline = true;
      await world.settle();
      expect(await alice.standing(id), Gv2Membership.creating);
      expect(world.delivered, isEmpty);
      // A message written meanwhile is not possible yet.
      await expectLater(alice.say(id, 'x'), throwsA(isA<Gv2NotSendable>()));

      server.offline = false;
      world.now += 3600 * 1000;
      await world.settle();
      row = (await alice.group(id))!;
      expect(row.membership, Gv2Membership.active);
      expect(row.headSig, server.headSig(gv2Unhex(id), server.logs[id]!.state));
      expect((await alice.store.head(id, 0))!.headSig, row.headSig);
      expect(server.logs[id]!.entries, hasLength(1));
      expect(world.delivered.single.to, bob.snowId);
      expect(alice.sink.changed, contains(id));
      // The owner is confirmed by the same check as everyone else.
      final me = (await alice.store.memberBySnowId(id, alice.snowId))!;
      expect(me.checkState, Gv2MemberCheckState.confirmed);
      expect(me.role, gv2RoleOwner);
    });

    test('a lost answer: the same entry is submitted again, and a server that '
        'already has the group is asked for its state', () async {
      server.loseAnswers = true;
      final id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      await world.settle();
      expect(server.logs[id]!.entries, hasLength(1)); // the server has it
      expect(await alice.standing(id), Gv2Membership.creating);
      expect(world.delivered, isEmpty);

      server.loseAnswers = false;
      world.now += 3600 * 1000;
      await world.settle();
      expect(server.creates, 2);
      expect(server.logs[id]!.entries, hasLength(1));
      final row = (await alice.group(id))!;
      expect(row.membership, Gv2Membership.active);
      expect(row.headSig, isNotNull);
      expect(world.delivered.single.to, bob.snowId);
    });

    test('a server that has ANOTHER group under the id: abandoned, nothing of '
        'its state is taken', () async {
      server.loseAnswers = true;
      final id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      await world.settle();
      server.loseAnswers = false;
      // What the server holds under the id is not what alice submitted.
      final other = server.logs[id]!;
      final groupId = gv2Unhex(id);
      final row = (await alice.group(id))!;
      final replaced = gv2SignEntry(
        state: null,
        groupId: groupId,
        draft: Gv2EntryDraft(
          version: gv2ProtocolVersion,
          revision: 0,
          prevChain: gv2GenesisPrevChain(),
          actor: gv2Unhex(row.myCiphertext),
          actions: [Gv2Create(alice.memberKey(groupId).publicKey)],
          memberPayload: other.entries.first.memberPayload,
          titlePayload: other.entries.first.titlePayload,
        ),
        key: alice.memberKey(groupId),
      );
      other.entries
        ..clear()
        ..add(replaced.entry);
      other.states
        ..clear()
        ..add(replaced.next);
      world.now += 3600 * 1000;
      await world.settle();
      expect(await alice.group(id), isNull);
      expect(await alice.queued(), isEmpty);
      expect(world.delivered, isEmpty);
    });

    test(
      'an entry the server refuses for good: the group is abandoned',
      () async {
        server.rejectCreates = true;
        final id = await alice.groups.create(
          title: 'Snow',
          invite: [bob.snowId],
        );
        await world.settle();
        expect(await alice.group(id), isNull);
        expect(await alice.queued(), isEmpty);
        expect(world.delivered, isEmpty);
      },
    );

    test('a head the server did not sign is not taken', () async {
      server.forgeHeads = true;
      final id = await alice.groups.create(title: 'Snow');
      await world.settle();
      expect(await alice.standing(id), Gv2Membership.creating);
      server.forgeHeads = false;
      world.now += 3600 * 1000;
      await world.settle();
      expect(await alice.standing(id), Gv2Membership.active);
    });

    test(
      'a group the server never got to know is given up with its row',
      () async {
        server.offline = true;
        final keysOnline = server.offline;
        expect(keysOnline, isTrue);
        server.offline = false;
        final id = await alice.groups.create(
          title: 'Snow',
          invite: [bob.snowId],
        );
        server.offline = true;
        await world.settle();
        world.now += gv2OutboxRetention.inMilliseconds + 1;
        await alice.outbox.flush();
        expect(await alice.group(id), isNull);
        expect(await alice.queued(), isEmpty);
      },
    );

    test('invites to oneself and twice to the same account are one', () async {
      final id = await alice.groups.create(
        title: 'Snow',
        invite: [bob.snowId, alice.snowId, bob.snowId],
      );
      await world.settle();
      expect(server.logs[id]!.state.pending, hasLength(1));
      await expectLater(
        alice.groups.create(title: 'x', invite: ['not a snow id']),
        throwsArgumentError,
      );
    });
  });

  group('from an invite to a conversation', () {
    test(
      'created, invited, accepted, confirmed — and messages both ways',
      () async {
        bob.acceptsInvites = true;
        final id = await alice.groups.create(
          title: 'Snow',
          invite: [bob.snowId],
        );
        await world.settle();

        expect(bob.inviteOutcomes, [Gv2InviteOutcome.stored]);
        final log = server.logs[id]!;
        expect(log.entries, hasLength(2)); // CREATE+INVITE, ACCEPT
        expect(log.state.pending, isEmpty);
        expect(log.state.members, hasLength(2));

        // Alice followed the log; bob was confirmed by alice.
        expect((await alice.group(id))!.revision, 1);
        final bobRow = (await bob.group(id))!;
        expect(bobRow.membership, Gv2Membership.active);
        expect(bobRow.title, 'Snow');
        expect(bobRow.inviteSeed, isNull);
        expect(bobRow.invitedBySnowId, alice.snowId);
        for (final d in [alice, bob]) {
          final members = await d.store.confirmedMembers(id);
          expect(members.map((m) => m.snowId).toSet(), {
            alice.snowId,
            bob.snowId,
          }, reason: d.name);
        }
        expect(await alice.queued(), isEmpty);
        expect(await bob.queued(), isEmpty);

        await alice.say(id, 'hello bob');
        await world.settle();
        await bob.say(id, 'hello alice');
        await world.settle();
        expect(bob.sink.texts, ['hello bob']);
        expect(alice.sink.texts, ['hello alice']);
      },
    );

    test('an invite waits for the user (nothing is accepted by itself); '
        'accepting it later joins', () async {
      final id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      await world.settle();
      expect(bob.inviteOutcomes, [Gv2InviteOutcome.stored]);
      final row = (await bob.group(id))!;
      expect(row.membership, Gv2Membership.invited);
      expect(row.stateLoaded, isTrue);
      expect(row.title, 'Snow');
      expect(server.logs[id]!.entries, hasLength(1));

      await bob.groups.accept(id);
      expect(await bob.standing(id), Gv2Membership.awaitingConfirm);
      await world.settle();
      expect(await bob.standing(id), Gv2Membership.active);
      await bob.say(id, 'I am in');
      await world.settle();
      expect(alice.sink.texts, ['I am in']);
    });

    test('an invite the 1:1 queue kept before any group runtime ran is '
        'taken in on the next drain', () async {
      final id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      world.holdInvites = true;
      await world.settle();
      final sent = world.invites.single;
      world.invites.clear();
      expect(
        await bob.db.gv2InboxStore.storeInvite(
          serverRowId: 'm1',
          senderSnowId: alice.snowId,
          invite: sent.bytes,
          nowMs: world.now,
        ),
        isTrue,
      );
      expect(await bob.group(id), isNull);
      await bob.inbox.drain();
      // Kept at once; checked against the log right after.
      await world.settle();
      expect(await bob.standing(id), Gv2Membership.invited);
      expect((await bob.group(id))!.stateLoaded, isTrue);
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });

    test('an invite passed on by someone else holds nothing: the log names '
        'another inviter', () async {
      final id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      world.holdInvites = true;
      await world.settle();
      final real = world.invites.single;
      world.invites.clear();
      // Carol hands bob the invite alice made for him.
      world.invites.add(_InviteInTransit(carol, bob.snowId, real.bytes));
      world.holdInvites = false;
      await world.deliverInvites();
      expect(bob.inviteOutcomes, [Gv2InviteOutcome.ignored]);
      expect(await bob.group(id), isNull);
      // The invite alice sent herself holds.
      world.invites.add(real);
      await world.deliverInvites();
      expect(bob.inviteOutcomes.last, Gv2InviteOutcome.stored);
      expect((await bob.group(id))!.invitedBySnowId, alice.snowId);
    });

    test('what is written before the confirmation leaves after it', () async {
      final id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      await world.settle();
      await bob.groups.accept(id);
      await bob.say(id, 'early');
      expect(await bob.queued(), contains(Gv2OutboxKind.content));
      await world.settle();
      world.now += 61 * 1000;
      await world.settle();
      expect(alice.sink.texts, ['early']);
    });

    test('declining takes the invite out of the log', () async {
      final id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      await world.settle();
      await bob.groups.decline(id);
      expect(await bob.standing(id), Gv2Membership.declined);
      expect(server.logs[id]!.state.pending, isEmpty);
      await expectLater(
        bob.groups.accept(id),
        throwsA(
          isA<Gv2GroupException>().having(
            (e) => e.reason,
            'reason',
            Gv2GroupFailure.notAllowed,
          ),
        ),
      );
    });

    test('two invitees accept at once: the one the server is ahead of steps '
        'aside, catches up and gets in', () async {
      final id = await alice.groups.create(
        title: 'Snow',
        invite: [bob.snowId, carol.snowId],
      );
      await world.settle();
      await Future.wait<void>([bob.groups.accept(id), carol.groups.accept(id)]);
      expect(server.logs[id]!.entries, hasLength(3));
      expect(server.logs[id]!.state.members, hasLength(3));
      expect(server.changes, 3); // one of them was sent twice
      expect([...bob.sleeps, ...carol.sleeps], isNotEmpty);
      await world.settle();
      for (final d in [alice, bob, carol]) {
        expect(await d.standing(id), Gv2Membership.active, reason: d.name);
        expect((await d.group(id))!.revision, 2, reason: d.name);
      }
      await carol.say(id, 'three of us');
      await world.settle();
      expect(alice.sink.texts, ['three of us']);
      expect(bob.sink.texts, ['three of us']);
    });
  });

  group('what an invite must satisfy', () {
    late String id;
    late Gv2InviteMessage real;

    setUp(() async {
      id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      world.holdInvites = true;
      await world.settle();
      real = Gv2InviteMessage.decode(world.invites.single.bytes)!;
      world.invites.clear();
    });

    Gv2InviteMessage altered({
      Uint8List? groupId,
      Uint8List? masterKey,
      int? revision,
      Uint8List? chain,
      Uint8List? stateHash,
      Uint8List? inviteSeed,
    }) => Gv2InviteMessage(
      groupId: groupId ?? real.groupId,
      masterKey: masterKey ?? real.masterKey,
      revision: revision ?? real.revision,
      chain: chain ?? real.chain,
      stateHash: stateHash ?? real.stateHash,
      inviteSeed: inviteSeed ?? real.inviteSeed,
    );

    Future<Gv2InviteOutcome> offer(Gv2InviteMessage m, {_Device? from}) =>
        bob.groups.receiveInvite((from ?? alice).snowId, m.encode());

    test('the invite as it was sent is kept', () async {
      expect(await offer(real), Gv2InviteOutcome.stored);
      expect(await bob.standing(id), Gv2Membership.invited);
    });

    test('what is not an invite, or states another group than its key gives, '
        'is ignored', () async {
      expect(
        await bob.groups.receiveInvite(alice.snowId, _utf8('hello')),
        Gv2InviteOutcome.ignored,
      );
      expect(
        await bob.groups.receiveInvite(
          alice.snowId,
          real.encode().sublist(0, gv2InviteLen - 1),
        ),
        Gv2InviteOutcome.ignored,
      );
      expect(
        await offer(altered(groupId: gv2TestSha('another group'))),
        Gv2InviteOutcome.ignored,
      );
      expect(await bob.store.groups(), isEmpty);
      // From this account itself, or from something that is no account.
      expect(
        await bob.groups.receiveInvite(bob.snowId, real.encode()),
        Gv2InviteOutcome.ignored,
      );
      expect(
        await bob.groups.receiveInvite('nobody', real.encode()),
        Gv2InviteOutcome.ignored,
      );
    });

    test('a group the server does not have, an anchor that is not the '
        'server\'s, or a key the log does not hold: forgotten', () async {
      final unknownKey = gv2TestSha('a master key of no group');
      expect(
        await offer(
          altered(
            masterKey: unknownKey,
            groupId: ZkGroup.groupParams(unknownKey).groupId,
          ),
        ),
        Gv2InviteOutcome.ignored,
      );
      expect(
        await offer(altered(stateHash: gv2TestSha('another state'))),
        Gv2InviteOutcome.ignored,
      );
      expect(
        await offer(altered(chain: gv2TestSha('another chain'))),
        Gv2InviteOutcome.ignored,
      );
      expect(
        await offer(altered(inviteSeed: gv2TestSha('another invite key'))),
        Gv2InviteOutcome.ignored,
      );
      expect(await bob.store.groups(), isEmpty);
      // None of them spoils the real one.
      expect(await offer(real), Gv2InviteOutcome.stored);
    });

    test(
      'an account that is not invited cannot use someone else\'s invite',
      () async {
        expect(
          await carol.groups.receiveInvite(alice.snowId, real.encode()),
          Gv2InviteOutcome.ignored,
        );
        expect(await carol.store.groups(), isEmpty);
      },
    );

    test(
      'while offline the invite is kept and checked when it is accepted',
      () async {
        server.offline = true;
        expect(await offer(real), Gv2InviteOutcome.stored);
        expect((await bob.group(id))!.stateLoaded, isFalse);
        await expectLater(
          bob.groups.accept(id),
          throwsA(
            isA<Gv2GroupException>().having(
              (e) => e.reason,
              'reason',
              Gv2GroupFailure.unavailable,
            ),
          ),
        );
        expect(await bob.standing(id), Gv2Membership.invited);
        server.offline = false;
        world.now += 10 * 1000;
        await bob.groups.accept(id);
        expect(await bob.standing(id), Gv2Membership.awaitingConfirm);
      },
    );

    test('an invite that was taken back is gone when it is accepted, and the '
        'group is forgotten', () async {
      expect(await offer(real), Gv2InviteOutcome.stored);
      // Alice revokes it.
      final log = server.logs[id]!;
      final groupId = gv2Unhex(id);
      final revoke = gv2SignEntry(
        state: log.state,
        groupId: groupId,
        draft: Gv2EntryDraft(
          version: gv2ProtocolVersion,
          revision: log.state.revision + 1,
          prevChain: log.state.chain,
          actor: gv2Unhex((await alice.group(id))!.myCiphertext),
          actions: [
            Gv2RevokeInvite(gv2Unhex((await bob.group(id))!.myCiphertext)),
          ],
          memberPayload: Uint8List(0),
          titlePayload: Uint8List(0),
        ),
        key: alice.memberKey(groupId),
      );
      await server.change(
        groupId: groupId,
        presentation: revoke.entry.actor,
        entry: gv2EncodeEntry(revoke.entry),
      );
      world.now += 10 * 1000;
      await expectLater(
        bob.groups.accept(id),
        throwsA(
          isA<Gv2GroupException>().having(
            (e) => e.reason,
            'reason',
            Gv2GroupFailure.inviteGone,
          ),
        ),
      );
      expect(await bob.group(id), isNull);
    });

    test('an invite taken back while it is being accepted: gone, not a rule '
        'violation', () async {
      expect(await offer(real), Gv2InviteOutcome.stored);
      final groupId = gv2Unhex(id);
      final aliceCiphertext = gv2Unhex((await alice.group(id))!.myCiphertext);
      final bobCiphertext = gv2Unhex((await bob.group(id))!.myCiphertext);
      server.onChange = () async {
        server.onChange = null;
        // Bob's ACCEPT is on its way; alice's revocation gets there first.
        final log = server.logs[id]!;
        final revoke = gv2SignEntry(
          state: log.state,
          groupId: groupId,
          draft: Gv2EntryDraft(
            version: gv2ProtocolVersion,
            revision: log.state.revision + 1,
            prevChain: log.state.chain,
            actor: aliceCiphertext,
            actions: [Gv2RevokeInvite(bobCiphertext)],
            memberPayload: Uint8List(0),
            titlePayload: Uint8List(0),
          ),
          key: alice.memberKey(groupId),
        );
        log.add(revoke.entry, revoke.next);
      };
      world.now += 10 * 1000;
      await expectLater(
        bob.groups.accept(id),
        throwsA(
          isA<Gv2GroupException>().having(
            (e) => e.reason,
            'reason',
            Gv2GroupFailure.inviteGone,
          ),
        ),
      );
      expect(server.logs[id]!.state.members, hasLength(1));
      // One step aside, one look at the log — not attempt after attempt.
      expect(server.changes, 1);
      expect(await bob.group(id), isNull);
    });

    test('an invite never replaces the anchor of a group this device takes '
        'part in', () async {
      expect(await offer(real), Gv2InviteOutcome.stored);
      await bob.groups.accept(id);
      final before = (await bob.group(id))!;
      expect(
        await offer(
          altered(revision: 0, inviteSeed: gv2TestSha('another invite key')),
        ),
        Gv2InviteOutcome.ignored,
      );
      final after = (await bob.group(id))!;
      expect(after.revision, before.revision);
      expect(after.chain, before.chain);
      expect(after.membership, Gv2Membership.awaitingConfirm);
    });

    test('a second invite does not displace one that still holds', () async {
      expect(await offer(real), Gv2InviteOutcome.stored);
      world.now += 10 * 1000;
      // The group stays stored — with the invite it had.
      expect(
        await offer(altered(inviteSeed: gv2TestSha('another invite key'))),
        Gv2InviteOutcome.stored,
      );
      expect((await bob.group(id))!.inviteSeed, real.inviteSeed);
    });

    test(
      'a second invite takes the place of one that was taken back',
      () async {
        expect(await offer(real), Gv2InviteOutcome.stored);
        // Alice takes the invite back and invites bob again.
        final log = server.logs[id]!;
        final groupId = gv2Unhex(id);
        final revoke = gv2SignEntry(
          state: log.state,
          groupId: groupId,
          draft: Gv2EntryDraft(
            version: gv2ProtocolVersion,
            revision: log.state.revision + 1,
            prevChain: log.state.chain,
            actor: gv2Unhex((await alice.group(id))!.myCiphertext),
            actions: [
              Gv2RevokeInvite(gv2Unhex((await bob.group(id))!.myCiphertext)),
            ],
            memberPayload: Uint8List(0),
            titlePayload: Uint8List(0),
          ),
          key: alice.memberKey(groupId),
        );
        await server.change(
          groupId: groupId,
          presentation: revoke.entry.actor,
          entry: gv2EncodeEntry(revoke.entry),
        );
        world.now += 10 * 1000;
        await alice.inbox.requestSync(id);
        world.holdInvites = false;
        await alice.groups.invite(id, bob.snowId);
        world.now += 10 * 1000;
        await world.settle();
        final row = (await bob.group(id))!;
        expect(row.membership, Gv2Membership.invited);
        expect(row.revision, 2);
        expect(_same(row.inviteSeed!, real.inviteSeed), isFalse);
        await bob.groups.accept(id);
        expect(await bob.standing(id), Gv2Membership.awaitingConfirm);
      },
    );

    test('taking an invite in needs no server; it is settled when the server '
        'can be reached', () async {
      server.offline = true;
      final kept = await bob.groups.keepInvite(alice.snowId, real.encode());
      expect(kept, id);
      expect(await bob.standing(id), Gv2Membership.invited);
      // One that will not hold is kept just the same, for now.
      final bogusKey = gv2TestSha('a master key of no group');
      final bogus = await bob.groups.keepInvite(
        alice.snowId,
        altered(
          masterKey: bogusKey,
          groupId: ZkGroup.groupParams(bogusKey).groupId,
        ).encode(),
      );
      expect(bogus, isNotNull);
      expect(await bob.store.groups(), hasLength(2));

      await bob.groups.resume(); // still offline: nothing is decided
      expect(await bob.store.groups(), hasLength(2));

      server.offline = false;
      world.now += 10 * 1000;
      await bob.groups.resume();
      expect(await bob.group(bogus!), isNull);
      // The real one holds and waits for bob, who then accepts.
      expect(await bob.standing(id), Gv2Membership.invited);
      await bob.groups.accept(id);
      expect(await bob.standing(id), Gv2Membership.awaitingConfirm);
    });

    test('a malformed answer from the server is no proof the invite is gone: '
        'it is kept and holds once the server answers properly', () async {
      server.forgeHeads = true;
      expect(await offer(real), Gv2InviteOutcome.stored);
      expect(await bob.standing(id), Gv2Membership.invited);
      server.forgeHeads = false;
      world.now += 10 * 1000;
      await bob.groups.resume();
      expect(await bob.standing(id), Gv2Membership.invited);
      expect((await bob.group(id))!.stateLoaded, isTrue);
    });

    test('one sender\'s invites are taken in ten times an hour', () async {
      for (var i = 0; i < gv2InvitesPerSenderPerHour; i++) {
        await bob.groups.receiveInvite(alice.snowId, _utf8('junk $i'));
      }
      expect(await offer(real), Gv2InviteOutcome.ignored);
      // Another sender is not affected (an invite carol made herself)...
      world.holdInvites = true;
      final carols =
          await carol.groups.create(title: 'Carol', invite: [bob.snowId]);
      await world.settle();
      final fromCarol = Gv2InviteMessage.decode(
        world.invites.singleWhere((i) => i.from == carol).bytes,
      )!;
      world.invites.clear();
      world.holdInvites = false;
      expect(await offer(fromCarol, from: carol), Gv2InviteOutcome.stored);
      expect(await bob.standing(carols), Gv2Membership.invited);
      // ...nor is this one an hour later.
      await bob.store.deleteGroup(id);
      bob.inbox.groupsChanged();
      world.now += Duration.millisecondsPerHour;
      expect(await offer(real), Gv2InviteOutcome.stored);
    });
  });

  group('inviting into a group', () {
    test('a member is invited, accepts and talks with everyone', () async {
      final id = await established();
      carol.acceptsInvites = true;
      await alice.groups.invite(id, carol.snowId);
      await world.settle();
      for (final d in [alice, bob, carol]) {
        expect(await d.standing(id), Gv2Membership.active, reason: d.name);
        expect(await d.store.confirmedMembers(id), hasLength(3));
      }
      await carol.say(id, 'hello both');
      await bob.say(id, 'hello carol');
      await world.settle();
      expect(alice.sink.texts.toSet(), {'hello both', 'hello carol'});
      expect(carol.sink.texts, ['hello carol']);
    });

    test('inviteMany: several accounts in one change; one already there is '
        'left out; more than gv2MaxChangeActions is not one change', () async {
      final id = await established();
      carol.acceptsInvites = false; // invited, and left so
      final dave = await world.add('dave');
      final erin = await world.add('erin');
      final entries = server.logs[id]!.entries.length;
      expect(
        await alice.groups.inviteMany(
          id,
          [carol.snowId, dave.snowId, erin.snowId, bob.snowId],
        ),
        3,
      );
      expect(server.logs[id]!.entries, hasLength(entries + 1));
      expect(server.logs[id]!.state.pending, hasLength(3));
      await world.settle();
      for (final d in [carol, dave, erin]) {
        expect(await d.standing(id), Gv2Membership.invited, reason: d.name);
      }
      expect(await alice.queued(), isEmpty, reason: 'every invite went out');

      await expectLater(
        alice.groups.inviteMany(id, [carol.snowId, bob.snowId]),
        throwsA(isA<Gv2GroupException>().having(
            (e) => e.reason, 'reason', Gv2GroupFailure.alreadyThere)),
      );
      expect(await alice.queued(), isEmpty, reason: 'no invite left behind');

      // The server asks to slow down: said so, and nothing is left queued.
      server.rateLimitChanges = true;
      final frank = await world.add('frank');
      await expectLater(
        alice.groups.inviteMany(id, [frank.snowId]),
        throwsA(isA<Gv2GroupException>().having(
            (e) => e.reason, 'reason', Gv2GroupFailure.rateLimited)),
      );
      server.rateLimitChanges = false;
      expect(await alice.queued(), isEmpty);
      expect(
        () => alice.groups.inviteMany(id, [
          for (var i = 0; i <= gv2MaxChangeActions; i++)
            'snow${i.toRadixString(16).padLeft(32, '0')}',
        ]),
        throwsArgumentError,
      );
    });

    test('checkLeave says, before anything is done, whether leaving can be '
        'made: on the log as the server has it', () async {
      final id = await established();
      await bob.groups.checkLeave(id);
      await alice.groups.checkLeave(id); // an owner with a confirmed member
      server.offline = true;
      await expectLater(
        bob.groups.checkLeave(id),
        throwsA(isA<Gv2GroupException>().having(
            (e) => e.reason, 'reason', Gv2GroupFailure.unavailable)),
      );
      server.offline = false;
      await expectLater(
        carol.groups.checkLeave(id),
        throwsA(isA<Gv2GroupException>().having(
            (e) => e.reason, 'reason', Gv2GroupFailure.notAllowed)),
      );
    });

    test('who may not, and whom not', () async {
      final id = await established();
      Future<void> refused(Future<void> call, Gv2GroupFailure reason) =>
          expectLater(
            call,
            throwsA(
              isA<Gv2GroupException>().having(
                (e) => e.reason,
                'reason',
                reason,
              ),
            ),
          );

      await refused(
        alice.groups.invite(id, bob.snowId),
        Gv2GroupFailure.alreadyThere,
      );
      // A plain member: the rules of the log refuse it.
      await refused(
        bob.groups.invite(id, carol.snowId),
        Gv2GroupFailure.rejected,
      );
      await refused(
        carol.groups.invite(id, bob.snowId),
        Gv2GroupFailure.notAllowed,
      );
      await alice.store.setHold(id, Gv2Hold.updateRequired);
      await refused(
        alice.groups.invite(id, carol.snowId),
        Gv2GroupFailure.notAllowed,
      );
      // Nothing of the refused invites is left to be sent.
      expect(await alice.queued(), isEmpty);
      expect(await bob.queued(), isEmpty);
      expect(server.logs[id]!.state.pending, isEmpty);
    });

    test('a group holds up to gv2GroupSizeLimit accounts, invites counted',
        () async {
      bob.acceptsInvites = false;
      // Accounts with no device in this world: their invites go nowhere.
      final strangers = [
        for (var i = 0; i < gv2GroupSizeLimit; i++)
          'snow${i.toRadixString(16).padLeft(32, '0')}',
      ];
      Future<void> full(Future<Object?> call) => expectLater(
            call,
            throwsA(
              isA<Gv2GroupException>().having(
                (e) => e.reason,
                'reason',
                Gv2GroupFailure.full,
              ),
            ),
          );

      // The creator and 256 invites: one too many, and nothing is stored.
      await full(alice.groups.create(
        title: 'Too many',
        invite: [bob.snowId, ...strangers.take(gv2GroupSizeLimit - 1)],
      ));
      expect(await alice.store.groups(), isEmpty);
      expect(await alice.queued(), isEmpty);

      // The creator and 255 invites: exactly full.
      final id = await alice.groups.create(
        title: 'Full',
        invite: [bob.snowId, ...strangers.take(gv2GroupSizeLimit - 2)],
      );
      await world.settle();
      expect((await alice.group(id))!.membership, Gv2Membership.active);
      expect(server.logs[id]!.state.pending, hasLength(gv2GroupSizeLimit - 1));
      await full(alice.groups.invite(id, carol.snowId));
      expect(server.logs[id]!.state.pending, hasLength(gv2GroupSizeLimit - 1));
      expect(await alice.queued(), isEmpty);

      // Room for one again once an invite is declined — which alice's
      // stored state has not seen yet: the refusal it gives is checked
      // again after catching up, and the invite goes through.
      await bob.groups.decline(id);
      expect((await alice.group(id))!.revision,
          lessThan(server.logs[id]!.state.revision));
      await alice.groups.invite(id, carol.snowId);
      await world.settle();
      expect(server.logs[id]!.state.pending, hasLength(gv2GroupSizeLimit - 1));
      expect(
        server.logs[id]!.state.pending.containsKey(
          gv2Hex(gv2Unhex((await alice.group(id))!.myCiphertext)),
        ),
        isFalse,
      );
    });

    test('a refusal from a stale state cannot be checked offline: the server '
        'could not be reached', () async {
      bob.acceptsInvites = false;
      final id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      await world.settle();
      // Bob declines; alice has not seen it and the network is gone.
      await bob.groups.decline(id);
      final deliveredBefore = world.delivered.length;
      server.offline = true;
      await expectLater(
        alice.groups.invite(id, bob.snowId),
        throwsA(
          isA<Gv2GroupException>().having(
            (e) => e.reason,
            'reason',
            Gv2GroupFailure.unavailable,
          ),
        ),
      );
      // Back online: the decline is seen and bob is invited again.
      server.offline = false;
      await alice.groups.invite(id, bob.snowId);
      await world.settle();
      expect(server.logs[id]!.state.pending, hasLength(1));
      // The row of the refused try decides by the log when it comes due:
      // its invite key is not there, so it goes nowhere.
      world.now += gv2InviteReserve.inMilliseconds + 1;
      await world.settle();
      expect(await alice.queued(), isEmpty);
      expect(
        [for (final i in world.delivered.skip(deliveredBefore)) i.to],
        [bob.snowId],
      );
    });

    test('the server moved on meanwhile: the invite is built again on the '
        'log as it is', () async {
      bob.acceptsInvites = false;
      carol.acceptsInvites = false;
      final id = await alice.groups.create(
        title: 'Snow',
        invite: [bob.snowId, carol.snowId],
      );
      await world.settle();
      // Bob accepts; alice does not know yet.
      await bob.groups.accept(id);
      expect((await alice.group(id))!.revision, 0);
      final dave = await world.add('dave');
      await alice.groups.invite(id, dave.snowId);
      expect(alice.sleeps, isNotEmpty);
      expect((await alice.group(id))!.revision, 2);
      expect(server.logs[id]!.state.pending, hasLength(2));
    });

    test('the answer to an INVITE is lost and the network is gone: the invite '
        'key was stored first, and the invite goes out once the log shows it',
        () async {
      final id = await established();
      server.loseAnswers = true;
      server.offlineAfterLoss = true;
      await expectLater(
        alice.groups.invite(id, carol.snowId),
        throwsA(
          isA<Gv2GroupException>().having(
            (e) => e.reason,
            'reason',
            Gv2GroupFailure.unavailable,
          ),
        ),
      );
      server.loseAnswers = false;
      server.offline = false;
      expect(server.logs[id]!.state.pending, hasLength(1)); // the server has it
      expect((await alice.group(id))!.revision, 1); // alice has not
      // The invite message, and the notice the group gets once the log is
      // read again (the outcome is not known here).
      expect(await alice.queued(), [
        Gv2OutboxKind.invite,
        Gv2OutboxKind.changeNotice,
      ]);

      // Held back while the outcome is unknown.
      await world.settle();
      expect(world.delivered.where((i) => i.to == carol.snowId), isEmpty);

      world.now += gv2InviteReserve.inMilliseconds + 1;
      carol.acceptsInvites = true;
      await world.settle();
      expect(await carol.standing(id), Gv2Membership.active);
      expect(await alice.queued(), isEmpty);
    });

    test('an invite whose INVITE answer was lost right after a catch-up: '
        'the row is kept while the log cannot tell (a recent sync says '
        'nothing of this INVITE), and goes out once it can', () async {
      final id = await established();
      await bob.groups.leave(id); // the log moves on; alice does not know
      var calls = 0;
      server.onChange = () async {
        // Time passes before the catch-up after the 409.
        if (++calls == 1) world.now += 5000;
      };
      server.loseAnswers = true;
      server.offlineAfterLoss = true;
      await expectLater(
        alice.groups.invite(id, carol.snowId),
        throwsA(isA<Gv2GroupException>().having(
            (e) => e.reason, 'reason', Gv2GroupFailure.unavailable)),
      );
      expect(calls, 2, reason: 'a 409, then the INVITE whose answer is lost');
      server.onChange = null;
      server.loseAnswers = false;
      expect(server.logs[id]!.state.pending, hasLength(1));

      // Due, still offline, less than ten minutes after the catch-up.
      world.now += gv2InviteReserve.inMilliseconds - 5000;
      await alice.outbox.flush();
      expect(await alice.queued(), contains(Gv2OutboxKind.invite));

      server.offline = false;
      carol.acceptsInvites = true;
      world.now += 3600 * 1000;
      await world.settle();
      expect(await carol.standing(id), Gv2Membership.active);
      expect(await alice.queued(), isEmpty);
    });

    test('a member is removed and an invite taken back by its ciphertext — '
        'what an entry that names no account offers', () async {
      final id = await established(withCarol: true);
      final carolKey =
          (await alice.store.memberBySnowId(id, carol.snowId))!.ciphertext;
      expect(
        () => alice.groups.removeMember(id, 'not hex'),
        throwsArgumentError,
      );
      await alice.groups.removeMember(id, carolKey);
      expect(server.logs[id]!.state.members.containsKey(carolKey), isFalse);

      carol.acceptsInvites = false;
      await alice.groups.invite(id, carol.snowId);
      final pending = server.logs[id]!.state.pending.keys.single;
      await alice.groups.revokePending(id, pending);
      expect(server.logs[id]!.state.pending, isEmpty);
    });

    test('two changes of one group at once go to the server one after the '
        'other', () async {
      final id = await established(withCarol: true);
      var inFlight = 0;
      var most = 0;
      server.onChange = () async {
        inFlight++;
        most = max(most, inFlight);
        await Future<void>.delayed(Duration.zero);
        inFlight--;
      };
      await Future.wait([
        alice.groups.setTitle(id, 'Winter'),
        alice.groups.remove(id, carol.snowId),
      ]);
      server.onChange = null;
      expect(most, 1);
      final state = server.logs[id]!.state;
      expect(state.members, hasLength(2));
      expect((await alice.group(id))!.title, 'Winter');
      expect((await alice.group(id))!.changeSentAtMs, isNull);
    });

    test('the answer to an INVITE is lost but the log can be read: the log '
        'shows the invite, which counts as made and goes out', () async {
      final id = await established();
      server.loseAnswers = true;
      carol.acceptsInvites = true;
      await alice.groups.invite(id, carol.snowId);
      server.loseAnswers = false;
      expect((await alice.group(id))!.revision, 2);
      expect((await alice.group(id))!.changeSentAtMs, isNull);
      await world.settle();
      expect(await carol.standing(id), Gv2Membership.active);
    });

    test('a removal of this device reads first what the member sent before '
        'it and is here already (design §7.4): not dropped by the new '
        'roster', () async {
      final id = await established(withCarol: true);
      // Carol's first message: its Sender Key and the message reach alice's
      // inbox; alice has not handled them yet.
      await carol.say(id, 'last words');
      await carol.outbox.flush();
      expect(alice.sink.texts, isEmpty);
      await alice.groups.remove(id, carol.snowId);
      expect(alice.sink.texts, ['last words']);
      await world.settle();
      expect(bob.sink.texts, ['last words']);
      expect(alice.sink.texts, ['last words']);
    });

    test('the answer to a REMOVE is lost but the log can be read: the removal '
        'counts as made; the next message goes to the others only, with a new '
        'key', () async {
      final id = await established(withCarol: true);
      await alice.say(id, 'before');
      await world.settle();
      final keyBefore = (await alice.db.gv2SenderKeyStore.ownCurrent(
        id,
        alice.snowId,
      ))!.chainId;
      server.loseAnswers = true;
      await alice.groups.remove(id, carol.snowId);
      server.loseAnswers = false;
      expect(server.logs[id]!.state.members, hasLength(2));
      expect((await alice.group(id))!.revision, server.logs[id]!.state.revision);

      await alice.say(id, 'after');
      await world.settle();
      expect(bob.sink.texts, ['before', 'after']);
      expect(carol.sink.texts, ['before']);
      expect(
        (await alice.db.gv2SenderKeyStore.ownCurrent(id, alice.snowId))!.chainId,
        isNot(keyBefore),
      );
    });

    test('the answer to a REMOVE is lost and the network is gone: the change '
        'stays marked, and the next message syncs before it goes — the '
        'removed member never gets it', () async {
      final id = await established(withCarol: true);
      await alice.say(id, 'before');
      await world.settle();
      server.loseAnswers = true;
      server.offlineAfterLoss = true;
      await expectLater(
        alice.groups.remove(id, carol.snowId),
        throwsA(
          isA<Gv2GroupException>().having(
            (e) => e.reason,
            'reason',
            Gv2GroupFailure.unavailable,
          ),
        ),
      );
      server.loseAnswers = false;
      expect(server.logs[id]!.state.members, hasLength(2)); // the server has it
      final row = await alice.group(id);
      expect(row!.changeSentAtMs, isNotNull);
      expect(row.revision, server.logs[id]!.state.revision - 1); // alice has not

      // Still offline: the message waits rather than go on an old roster.
      await alice.say(id, 'after');
      await world.settle();
      expect(carol.sink.texts, ['before']);
      expect(bob.sink.texts, ['before']);

      server.offline = false;
      world.now += 60 * 60 * 1000; // past the outbox's back-off
      await world.settle();
      expect(bob.sink.texts, ['before', 'after']);
      expect(carol.sink.texts, ['before']);
      expect((await alice.group(id))!.changeSentAtMs, isNull);
    });

    test('the answer to a REMOVE is lost and the network is gone: once it is '
        'back the group is told, without anyone writing', () async {
      final id = await established(withCarol: true);
      server.loseAnswers = true;
      server.offlineAfterLoss = true;
      await expectLater(
        alice.groups.remove(id, carol.snowId),
        throwsA(isA<Gv2GroupException>()),
      );
      server.loseAnswers = false;
      server.offline = false;
      world.now += 60 * 60 * 1000; // past the outbox's back-off
      await world.settle();
      final head = server.logs[id]!.state.revision;
      expect((await alice.group(id))!.revision, head);
      expect((await bob.group(id))!.revision, head);
      await bob.say(id, 'carol is gone');
      await world.settle();
      expect(alice.sink.texts, ['carol is gone']);
      expect(carol.sink.texts, isEmpty);
    });

    test('the app ends while a REMOVE is on its way: the mark was written '
        'first, so the next message syncs before it goes', () async {
      final id = await established(withCarol: true);
      await alice.say(id, 'before');
      await world.settle();
      // The server takes the change; the device never hears back (the app
      // was gone before the answer).
      server.loseAnswers = true;
      server.offlineAfterLoss = true;
      await expectLater(
        alice.groups.remove(id, carol.snowId),
        throwsA(isA<Gv2GroupException>()),
      );
      server.loseAnswers = false;
      server.offline = false;
      // A new run of the app: only what is stored counts.
      expect((await alice.group(id))!.changeSentAtMs, isNotNull);
      await alice.say(id, 'after');
      await world.settle();
      expect(carol.sink.texts, ['before']);
      expect(bob.sink.texts, ['before', 'after']);
    });

    test('the answer to a LEAVE is lost but the log can be read: the leave '
        'counts as made; this device sends nothing more to the group',
        () async {
      final id = await established(withCarol: true);
      server.loseAnswers = true;
      await bob.groups.leave(id);
      server.loseAnswers = false;
      expect(server.logs[id]!.state.members, hasLength(2));
      expect(await bob.standing(id), isNot(Gv2Membership.active));
      await expectLater(bob.say(id, 'still here?'), throwsA(anything));
      await alice.say(id, 'bye bob');
      await world.settle();
      expect(carol.sink.texts, ['bye bob']);
      expect(bob.sink.texts, isEmpty);
    });

    test('the answer to a role change is lost but the log can be read: it '
        'counts as made', () async {
      final id = await established(withCarol: true);
      server.loseAnswers = true;
      await alice.groups.setRole(id, bob.snowId, admin: true);
      server.loseAnswers = false;
      final bobKey = gv2Hex(
        ZkGroup.encryptMember(
          masterKey: (await alice.group(id))!.masterKey,
          accountId: gv2AccountIdOfSnowId(bob.snowId),
        ),
      );
      expect((await alice.store.loadState(id))!.members[bobKey]!.role,
          gv2RoleAdmin);
      expect(server.logs[id]!.state.members[bobKey]!.role, gv2RoleAdmin);
      expect(server.changes, 3); // create's accept + this, once
    });

    test(
      'while the INVITE is on its way to the server, the row of its invite '
      'message is not looked at (it would find nothing in the log yet)',
      () async {
        final id = await established();
        carol.acceptsInvites = false;
        server.onChange = () async {
          server.onChange = null;
          // The outbox runs while the server has not accepted the entry.
          await alice.outbox.flush();
        };
        await alice.groups.invite(id, carol.snowId);
        await world.settle();
        expect(await carol.standing(id), Gv2Membership.invited);
      },
    );

    test(
      'an INVITE that never reached the server leaves no invite to send',
      () async {
        final id = await established();
        server.offline = true;
        await expectLater(
          alice.groups.invite(id, carol.snowId),
          throwsA(isA<Gv2GroupException>()),
        );
        server.offline = false;
        // A request that never reached the server looks like an answer that
        // was lost: the notice is only a hint to look at the log.
        expect(await alice.queued(), [
          Gv2OutboxKind.invite,
          Gv2OutboxKind.changeNotice,
        ]);
        world.now += gv2InviteReserve.inMilliseconds + 1;
        await world.settle();
        expect(await alice.queued(), isEmpty);
        expect(world.delivered.where((i) => i.to == carol.snowId), isEmpty);
        expect(await carol.store.groups(), isEmpty);
      },
    );

    test(
      'an invite message the 1:1 channel did not take is sent again',
      () async {
        final id = await established();
        carol.acceptsInvites = false;
        alice.inviteSendFails = true;
        await alice.groups.invite(id, carol.snowId);
        await world.settle();
        expect(await alice.queued(), [Gv2OutboxKind.invite]);
        alice.inviteSendFails = false;
        world.now += 3600 * 1000;
        await world.settle();
        expect(await carol.standing(id), Gv2Membership.invited);
        expect(await alice.queued(), isEmpty);
      },
    );

    test(
      'the invite message carries the head of the moment it is sent',
      () async {
        final id = await established();
        carol.acceptsInvites = false;
        alice.inviteSendFails = true;
        await alice.groups.invite(id, carol.snowId); // r2
        await world.settle();
        final dave = await world.add('dave');
        await alice.groups.invite(id, dave.snowId); // r3
        alice.inviteSendFails = false;
        world.now += 3600 * 1000;
        world.holdInvites = true;
        await world.settle();
        final toCarol = Gv2InviteMessage.decode(
          world.invites.firstWhere((i) => i.to == carol.snowId).bytes,
        )!;
        expect(toCarol.revision, 3);
        expect(toCarol.chain, server.logs[id]!.state.chain);
        world.holdInvites = false;
        await world.settle();
        expect(await carol.standing(id), Gv2Membership.invited);
        expect((await carol.group(id))!.revision, 3);
      },
    );

    test('a made-up invite to a group this account left does not erase its '
        'record; one that cannot be checked waits; a real one is taken',
        () async {
      final id = await established(withCarol: true);
      await bob.groups.leave(id);
      await world.settle();
      await alice.groups.setTitle(id, 'Later'); // the log moves past bob
      await world.settle();
      expect(await bob.standing(id), Gv2Membership.left);
      final masterKey = (await bob.group(id))!.masterKey;
      final state = server.logs[id]!.state;
      // Carol holds the master key and makes up invites: the head as it
      // is, under keys nobody registered.
      Gv2InviteMessage madeUp(String seed) => Gv2InviteMessage(
        groupId: gv2Unhex(id),
        masterKey: masterKey,
        revision: state.revision,
        chain: state.chain,
        stateHash: gv2StateHash(state),
        inviteSeed: gv2TestSha(seed),
      );

      final o = await bob.groups.takeInvite(carol.snowId, madeUp('one').encode());
      expect(o, isA<Gv2Handled>());
      (o as Gv2Handled).afterCommit?.call();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await bob.standing(id), Gv2Membership.left, reason: 'kept');

      server.offline = true;
      expect(
        await bob.groups.takeInvite(carol.snowId, madeUp('two').encode()),
        isA<Gv2WaitForSync>(),
        reason: 'the inbox row stays until it can be checked',
      );
      server.offline = false;
      expect(await bob.standing(id), Gv2Membership.left);

      bob.acceptsInvites = false;
      await alice.groups.invite(id, bob.snowId);
      await world.settle();
      expect(await bob.standing(id), Gv2Membership.invited);
    });

    test('an invite from an account this user blocked is dropped — also one '
        'kept before the block, as an invite row of the inbox', () async {
      bob.blocked.add(alice.snowId);
      final id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      await world.settle();
      expect(await bob.standing(id), isNull);

      // An invite row the 1:1 queue stored before the block.
      world.holdInvites = true;
      final id2 = await alice.groups.create(title: 'Again', invite: [bob.snowId]);
      await world.settle();
      final bytes = world.invites.single.bytes;
      expect(
        await bob.groups.takeInvite(alice.snowId, bytes),
        isA<Gv2Handled>(),
      );
      expect(await bob.standing(id2), isNull);

      // Unblocked: the next one is taken.
      bob.blocked.clear();
      await bob.groups.takeInvite(alice.snowId, bytes);
      expect(await bob.standing(id2), Gv2Membership.invited);
    });

    test('the group messages of a member this user blocked are still shown '
        '(owner decision: a block is about 1:1, invites and calls)', () async {
      final id = await established(withCarol: true);
      bob.blocked.add(carol.snowId);
      await carol.say(id, 'still here');
      await world.settle();
      expect(bob.sink.texts, ['still here']);
    });

    test('declined, then invited again: the new invite is taken from its '
        'later point of the log', () async {
      bob.acceptsInvites = false;
      final id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      await world.settle();
      await bob.groups.decline(id);
      world.now += 10 * 1000;
      await alice.inbox.requestSync(id);
      await alice.groups.invite(id, bob.snowId);
      await world.settle();
      expect(await bob.standing(id), Gv2Membership.invited);
      expect((await bob.group(id))!.revision, 2);
      await bob.groups.accept(id);
      await world.settle();
      expect(await bob.standing(id), Gv2Membership.active);
    });

    test('a head the server did not sign: nothing of the answer is stored, '
        'the log decides', () async {
      final id = await established();
      carol.acceptsInvites = false;
      server.forgeHeads = true;
      await expectLater(
        alice.groups.invite(id, carol.snowId),
        throwsA(
          isA<Gv2GroupException>().having(
            (e) => e.reason,
            'reason',
            Gv2GroupFailure.untrusted,
          ),
        ),
      );
      expect((await alice.group(id))!.revision, 1);
      server.forgeHeads = false;
      world.now += gv2InviteReserve.inMilliseconds + 1;
      await world.settle();
      // The entry is in the server's log; alice read it there and sent the
      // invite it had kept the key of.
      expect((await alice.group(id))!.revision, 2);
      expect(await carol.standing(id), Gv2Membership.invited);
    });
  });

  group('changing a group', () {
    Future<void> refused(Future<void> call, Gv2GroupFailure reason) =>
        expectLater(
          call,
          throwsA(
            isA<Gv2GroupException>().having((e) => e.reason, 'reason', reason),
          ),
        );

    /// Make [of] an account [on]'s device could not confirm.
    Future<void> unconfirm(_Device on, String id, _Device of) =>
        on.db.customUpdate(
          "UPDATE gv2_members SET check_state = 'certificate' "
          'WHERE group_id = ? AND snow_id = ?',
          variables: [Variable.withString(id), Variable.withString(of.snowId)],
          updates: {on.db.gv2Members},
        );

    test('a removed member is told at once, everyone else by the notice; '
        'the next message is not for the removed one', () async {
      final id = await established(withCarol: true);
      await alice.say(id, 'before');
      await world.settle();
      expect(carol.sink.texts, ['before']);
      final keys = alice.db.gv2SenderKeyStore;
      final chain = (await keys.ownCurrent(id, alice.snowId))!.chainId;

      await alice.groups.remove(id, carol.snowId);
      // Stored on alice's device with everything that follows from it.
      final row = (await alice.group(id))!;
      expect(row.lastRemovalRevision, row.revision);
      expect(await keys.delivered(id, carol.snowId, chain), isNull);
      expect(server.logs[id]!.state.members, hasLength(2));

      await world.settle();
      expect(await carol.standing(id), Gv2Membership.removed);
      expect((await bob.group(id))!.revision, row.revision);
      expect(await bob.store.memberBySnowId(id, carol.snowId), isNull);

      world.now += 10 * 1000;
      await alice.say(id, 'after');
      await world.settle();
      expect(bob.sink.texts, ['before', 'after']);
      expect(carol.sink.texts, ['before']);
      expect((await keys.ownCurrent(id, alice.snowId))!.chainId, isNot(chain));
      await expectLater(carol.say(id, 'x'), throwsA(isA<Gv2NotSendable>()));
    });

    test('who may remove whom is decided by the log\'s rules', () async {
      final id = await established(withCarol: true);
      await refused(
        bob.groups.remove(id, carol.snowId),
        Gv2GroupFailure.rejected,
      );
      await refused(
        alice.groups.remove(id, alice.snowId),
        Gv2GroupFailure.rejected,
      );
      final dave = await world.add('dave');
      await refused(
        alice.groups.remove(id, dave.snowId),
        Gv2GroupFailure.notThere,
      );
      await refused(
        dave.groups.remove(id, bob.snowId),
        Gv2GroupFailure.notAllowed,
      );
      expect(server.logs[id]!.state.members, hasLength(3));

      // An admin removes a plain member, not the owner.
      await alice.groups.setRole(id, bob.snowId, admin: true);
      await world.settle();
      await refused(
        bob.groups.remove(id, alice.snowId),
        Gv2GroupFailure.rejected,
      );
      await bob.groups.remove(id, carol.snowId);
      await world.settle();
      expect(await carol.standing(id), Gv2Membership.removed);
      expect(
        (await alice.group(id))!.revision,
        (await bob.group(id))!.revision,
      );
    });

    test('a member leaves: the others are told, its keys are gone, it says '
        'nothing more', () async {
      final id = await established(withCarol: true);
      await bob.say(id, 'hello');
      await alice.say(id, 'hello bob');
      await world.settle();
      expect(
        (await bob.db.gv2SenderKeyStore.manager(id, alice.snowId))
            .hasSenderKey(id, alice.snowId),
        isTrue,
      );
      await bob.groups.leave(id);
      expect(await bob.standing(id), Gv2Membership.left);
      expect(
        await bob.db.gv2SenderKeyStore.ownCurrent(id, bob.snowId),
        isNull,
        reason: 'the own key goes too (a return makes a new one): nothing '
            'it sent can be opened with what this device keeps',
      );
      expect(
        (await bob.db.gv2SenderKeyStore.manager(
          id,
          alice.snowId,
        )).hasSenderKey(id, alice.snowId),
        isFalse,
      );
      await expectLater(bob.say(id, 'x'), throwsA(isA<Gv2NotSendable>()));
      await world.settle();
      for (final d in [alice, carol]) {
        expect(
          await d.store.memberBySnowId(id, bob.snowId),
          isNull,
          reason: d.name,
        );
        expect(await d.standing(id), Gv2Membership.active);
      }
      // A leave is a removal for the keys of those who stay.
      expect((await alice.group(id))!.lastRemovalRevision, isNotNull);
    });

    test('an owner that leaves hands the group to the confirmed member who '
        'joined first', () async {
      final id = await established(withCarol: true);
      final joined = {
        for (final d in [bob, carol])
          d.snowId: (await alice.store.memberBySnowId(
            id,
            d.snowId,
          ))!.joinedRevision,
      };
      final first = joined[bob.snowId]! < joined[carol.snowId]! ? bob : carol;
      await alice.groups.leave(id);
      await world.settle();
      expect(await alice.standing(id), Gv2Membership.left);
      expect(await first.store.myRole(id), gv2RoleOwner);
      expect(server.logs[id]!.state.members, hasLength(2));
      expect(server.logs[id]!.state.deleted, isFalse);
    });

    test('an owner that leaves never hands the group to an account it knows '
        'to be deleted', () async {
      final id = await established(withCarol: true);
      final joined = {
        for (final d in [bob, carol])
          d.snowId: (await alice.store.memberBySnowId(
            id,
            d.snowId,
          ))!.joinedRevision,
      };
      final first = joined[bob.snowId]! < joined[carol.snowId]! ? bob : carol;
      final second = first == bob ? carol : bob;
      final gone = (await alice.store.memberBySnowId(id, first.snowId))!;
      await alice.store.setReach(id, gone.ciphertext, Gv2Reach.deleted);
      await alice.groups.leave(id);
      await world.settle();
      expect(await second.store.myRole(id), gv2RoleOwner);

      // Only deleted accounts left to hand it to: not left.
      final id2 = await established();
      final bobRow = (await alice.store.memberBySnowId(id2, bob.snowId))!;
      await alice.store.setReach(id2, bobRow.ciphertext, Gv2Reach.deleted);
      await refused(alice.groups.leave(id2), Gv2GroupFailure.noSuccessor);
    });

    test('an owner with nobody it could confirm cannot leave; the last '
        'member\'s leaving ends the group', () async {
      final id = await established();
      await unconfirm(alice, id, bob);
      await refused(alice.groups.leave(id), Gv2GroupFailure.noSuccessor);
      expect(await alice.standing(id), Gv2Membership.active);

      await bob.groups.leave(id);
      await world.settle();
      await alice.groups.leave(id);
      expect(server.logs[id]!.state.deleted, isTrue);
      expect(await alice.standing(id), Gv2Membership.ended);
    });

    test('a frozen group is left on this device only', () async {
      final id = await established();
      await bob.store.setHold(id, Gv2Hold.frozen, evidence: _utf8('{}'));
      final changes = server.changes;
      final queued = bob.queuedCalls;
      await bob.groups.leave(id);
      expect(await bob.group(id), isNull);
      expect(server.changes, changes);
      expect(server.logs[id]!.state.members, hasLength(2));
      // The app is told to work: the backup lets go of the group.
      expect(bob.queuedCalls, queued + 1);
      await bob.pumpBackup();
      expect(
        gv2OpenBackup(
          gv2DeriveBackupKey(bob.accountSeed),
          world.backups[bob.snowId]!,
        ),
        isEmpty,
      );
    });

    test(
      'roles and ownership go only to accounts this device confirmed',
      () async {
        final id = await established(withCarol: true);
        await refused(
          bob.groups.setRole(id, carol.snowId, admin: true),
          Gv2GroupFailure.rejected,
        );
        await unconfirm(alice, id, carol);
        await refused(
          alice.groups.setRole(id, carol.snowId, admin: true),
          Gv2GroupFailure.notAllowed,
        );
        await refused(
          alice.groups.transferOwner(id, carol.snowId),
          Gv2GroupFailure.notAllowed,
        );
        final dave = await world.add('dave');
        await refused(
          alice.groups.setRole(id, dave.snowId, admin: true),
          Gv2GroupFailure.notThere,
        );

        await alice.groups.setRole(id, bob.snowId, admin: true);
        await world.settle();
        // Carol is not told by alice (whose device could not confirm her):
        // she finds it in the log.
        world.now += 10 * 1000;
        await carol.inbox.requestSync(id);
        expect(await bob.store.myRole(id), gv2RoleAdmin);
        expect(
          (await carol.store.memberBySnowId(id, bob.snowId))!.role,
          gv2RoleAdmin,
        );
        await alice.groups.setRole(id, bob.snowId, admin: false);
        await world.settle();
        expect(await bob.store.myRole(id), gv2RoleMember);

        await alice.groups.transferOwner(id, bob.snowId);
        await world.settle();
        expect(await bob.store.myRole(id), gv2RoleOwner);
        expect(await alice.store.myRole(id), gv2RoleAdmin);
      },
    );

    test('a new name reaches everyone', () async {
      final id = await established(withCarol: true);
      await refused(carol.groups.setTitle(id, 'no'), Gv2GroupFailure.rejected);
      await alice.groups.setTitle(id, 'Winter');
      await world.settle();
      for (final d in [alice, bob, carol]) {
        expect((await d.group(id))!.title, 'Winter', reason: d.name);
      }
      expect(bob.sink.changed, contains(id));
    });

    test('an invite that was taken back cannot be accepted', () async {
      bob.acceptsInvites = false;
      final id = await alice.groups.create(title: 'Snow', invite: [bob.snowId]);
      await world.settle();
      expect(await bob.standing(id), Gv2Membership.invited);
      await refused(
        alice.groups.revokeInvite(id, carol.snowId),
        Gv2GroupFailure.notThere,
      );
      await alice.groups.revokeInvite(id, bob.snowId);
      expect(server.logs[id]!.state.pending, isEmpty);
      world.now += 10 * 1000;
      await refused(bob.groups.accept(id), Gv2GroupFailure.inviteGone);
      expect(await bob.group(id), isNull);
    });

    test('ending the group ends it for everyone', () async {
      final id = await established(withCarol: true);
      await refused(bob.groups.end(id), Gv2GroupFailure.rejected);
      await alice.groups.end(id);
      expect(await alice.standing(id), Gv2Membership.ended);
      await world.settle();
      for (final d in [bob, carol]) {
        expect(await d.standing(id), Gv2Membership.ended, reason: d.name);
        await expectLater(d.say(id, 'x'), throwsA(isA<Gv2NotSendable>()));
      }
    });

    test('a member whose account proved itself deleted is taken out by whoever '
        'may — the account\'s own signature is the reason', () async {
      final id = await established(withCarol: true);
      await bob.say(id, 'from bob');
      await world.settle();
      const deletedAtMs = 4102444800000; // after any certificate made here
      AccountDeletionProof proof(_Device signer) => AccountDeletionProof(
        deletedAtMs: deletedAtMs,
        signature: Uint8List.fromList(
          ed.SigningKey(seed: signer.accountSeed)
              .sign(
                AccountDeletionProofV1.buildMessage(
                  snowId: carol.snowId,
                  deletedAtMs: deletedAtMs,
                ),
              )
              .signature
              .asTypedList,
        ),
      );

      // A proof someone else signed moves nobody.
      world.deletedAccounts[carol.snowId] = proof(bob);
      await alice.say(id, 'one');
      await world.settle();
      expect(server.logs[id]!.state.members, hasLength(3));

      // A plain member sees the real proof: it may not remove, and does not try.
      world.deletedAccounts[carol.snowId] = proof(carol);
      final changes = server.changes;
      await bob.say(id, 'two');
      await world.settle();
      expect(
        (await bob.store.memberBySnowId(id, carol.snowId))!.reach,
        Gv2Reach.deleted,
      );
      expect(server.changes, changes);

      // The owner sees it: carol is removed.
      await alice.say(id, 'three');
      await world.settle();
      expect(server.logs[id]!.state.members, hasLength(2));
      expect(await bob.store.memberBySnowId(id, carol.snowId), isNull);
    });

    test('display names are looked up with a send token, once a day', () async {
      final id = await established(withCarol: true);
      server.nicknames[bob.snowId] = 'Bob';
      server.nicknames[alice.snowId] = 'Alice';
      await alice.groups.refreshNames(id);
      expect(server.nameCalls, 1);
      expect(
        (await alice.store.memberBySnowId(id, bob.snowId))!.nickname,
        'Bob',
      );
      expect(
        (await alice.store.memberBySnowId(id, carol.snowId))!.nickname,
        isNull,
      );
      await alice.groups.refreshNames(id);
      expect(server.nameCalls, 1);

      server.nicknames[bob.snowId] = 'Robert';
      world.now += Duration.millisecondsPerDay;
      await alice.groups.refreshNames(id);
      expect(server.nameCalls, 2);
      expect(
        (await alice.store.memberBySnowId(id, bob.snowId))!.nickname,
        'Robert',
      );
      // Offline: nothing changes, nothing throws.
      server.offline = true;
      world.now += Duration.millisecondsPerDay;
      await alice.groups.refreshNames(id);
      expect(
        (await alice.store.memberBySnowId(id, bob.snowId))!.nickname,
        'Robert',
      );
    });

    test('every entry of a log reads as what happened, with the accounts '
        'named — also the ones that are gone', () async {
      final id = await established(withCarol: true);
      await alice.groups.setTitle(id, 'Winter');
      await alice.groups.setRole(id, bob.snowId, admin: true);
      final dave = await world.add('dave');
      await alice.groups.invite(id, dave.snowId);
      await alice.groups.revokeInvite(id, dave.snowId);
      await alice.groups.remove(id, carol.snowId);
      await world.settle();
      await bob.groups.leave(id);
      await alice.groups.end(id);

      final masterKey = (await alice.group(id))!.masterKey;
      final events = [
        for (final entry in server.logs[id]!.entries)
          ...gv2DescribeEntry(
            masterKey: masterKey,
            groupId: gv2Unhex(id),
            entry: entry,
          ),
      ];
      String line(Gv2GroupEvent e) => [
        e.name,
        world.devices[e.by]?.name ?? '?',
        if (e.about != null) world.devices[e.about]?.name ?? '?',
      ].join(' ');
      final lines = events.map(line).toList();
      expect(lines.sublist(0, 3), [
        'created alice',
        'invited alice bob',
        'invited alice carol',
      ]);
      expect(lines.sublist(3, 5).toSet(), {'joined bob', 'joined carol'});
      expect(lines.sublist(5), [
        'renamed alice',
        'made_admin alice bob',
        'invited alice dave',
        'invite_revoked alice dave',
        'removed alice carol',
        'left bob',
        'ended alice',
      ]);
      expect((events.first as Gv2Created).title, 'Snow');
      expect(events.whereType<Gv2Renamed>().single.title, 'Winter');
    });
  });

  group('after a reinstall', () {
    List<String> texts(_Device d) => d.sink.texts;

    test('a member that could not put its old session aside handles the '
        'reset again later — the head confirmation never goes out on the '
        'dead session', () async {
      final id = await established();
      await bob.say(id, 'before');
      await world.settle();
      expect((await bob.pumpBackup()).written, isTrue);

      final bob2 = await world.reinstall(bob);
      await bob2.backup.sync();
      bob2.inbox.groupsChanged();
      alice.sessions.failArchives = 1;
      await bob2.groups.resume();
      await world.settle();
      // The failed attempt did not consume the notice: it was handled again,
      // the session went aside, and the head confirmation went out on a new
      // one — so bob is confirmed. (Swallowed, the confirmation would have
      // been sealed on the dead session and bob would wait for ever.)
      expect(alice.sessions.archives, 1);
      expect(alice.sessions.failArchives, 0);
      expect(await bob2.standing(id), Gv2Membership.active);
      await alice.say(id, 'welcome back');
      await world.settle();
      expect(texts(bob2), ['welcome back']);
    });

    test('the groups come back from the backup: the log is followed, the '
        'group is told that the keys are gone, a member confirms the head, '
        'and everyone talks again', () async {
      final id = await established(withCarol: true);
      await bob.say(id, 'before');
      await alice.say(id, 'hello');
      await world.settle();
      expect((await bob.pumpBackup()).written, isTrue);
      expect(world.backups[bob.snowId], isNotNull);
      // The group moves on after the backup was written.
      await alice.groups.setTitle(id, 'Winter');
      await world.settle();
      final head = (await alice.group(id))!.revision;

      final bob2 = await world.reinstall(bob);
      expect(await bob2.store.groups(), isEmpty);
      final outcome = await bob2.backup.sync();
      expect(outcome.restored, [id]);
      var row = (await bob2.group(id))!;
      expect(row.membership, Gv2Membership.awaitingConfirm);
      expect(row.stateLoaded, isFalse);
      expect(row.resetPending, isTrue);
      expect(row.revision, lessThan(head));
      // Nothing can be sent yet.
      await bob2.say(id, 'back');
      await bob2.outbox.flush();
      expect(texts(alice), ['before']);

      bob2.inbox.groupsChanged();
      await bob2.groups.resume();
      row = (await bob2.group(id))!;
      expect(row.stateLoaded, isTrue);
      expect(row.revision, head);
      expect(row.title, 'Winter');
      expect(row.resetPending, isFalse);
      expect(row.membership, Gv2Membership.awaitingConfirm);
      expect(await bob2.queued(), contains(Gv2OutboxKind.memberNotice));

      await world.settle();
      // The members put their dead 1:1 session with bob aside — the head
      // confirmation and the keys go out on a new one.
      expect(alice.sessions.archives, 1);
      expect(carol.sessions.archives, 1);
      expect(await bob2.standing(id), Gv2Membership.active);
      // What was written while waiting leaves after the confirmation (the
      // outbox looks at a waiting row again within a minute).
      world.now += 61 * 1000;
      await world.settle();
      expect(texts(alice), ['before', 'back']);
      expect(texts(carol).toSet(), {'before', 'hello', 'back'});
      expect(texts(carol).last, 'back');

      await alice.say(id, 'welcome back');
      await carol.say(id, 'hi');
      await world.settle();
      // The history from before the reinstall is not recovered.
      expect(texts(bob2).toSet(), {'welcome back', 'hi'});
      for (final d in [alice, carol, bob2]) {
        expect(await d.queued(), isEmpty, reason: d.name);
      }
      // The backup now holds the head this install verified.
      await bob2.backup.sync();
      // Done once: another look restores and announces nothing.
      final sends = world.sends;
      await bob2.pumpBackup();
      await world.settle();
      expect(world.sends, sends);
    });

    test('the server serves an older backup: a group left since comes back '
        'only as far as the log says — not as a member, and nothing reaches it',
        () async {
      final id = await established(withCarol: true);
      expect((await bob.pumpBackup()).written, isTrue);
      final older = world.backups[bob.snowId]!;
      await bob.groups.leave(id);
      await world.settle();
      await bob.pumpBackup();
      expect(world.backups[bob.snowId], isNot(older)); // the group is gone
      world.backups[bob.snowId] = older; // ...and the server rolls it back

      final bob2 = await world.reinstall(bob);
      expect((await bob2.backup.sync()).restored, [id]);
      bob2.inbox.groupsChanged();
      await bob2.groups.resume();
      await world.settle();
      expect(await bob2.standing(id), isNot(Gv2Membership.active));
      expect(server.logs[id]!.state.members, hasLength(2));
      await alice.say(id, 'after bob left');
      await world.settle();
      expect(texts(carol), ['after bob left']);
      expect(texts(bob2), isEmpty);
      await expectLater(bob2.say(id, 'let me in'), throwsA(anything));
    });

    test('the log served below the anchor the backup holds: the group is '
        'dropped as not borne out — never taken back to the older point, and '
        'nothing goes to it', () async {
      final id = await established(withCarol: true);
      await alice.groups.setTitle(id, 'Winter');
      await world.settle();
      expect((await bob.pumpBackup()).written, isTrue);
      final held = server.logs[id]!.state.revision;

      final bob2 = await world.reinstall(bob);
      expect((await bob2.backup.sync()).restored, [id]);
      // The server now shows the log as it was two revisions earlier.
      final log = server.logs[id]!;
      final cut = _Log();
      for (var r = 0; r <= held - 2; r++) {
        cut.add(log.entries[r], log.states[r]);
      }
      server.logs[id] = cut;
      bob2.inbox.groupsChanged();
      await bob2.groups.resume();
      // The server can hide a group this way (it can refuse service anyway);
      // it cannot make this device follow an older log.
      expect(await bob2.group(id), isNull);
      expect(await bob2.store.head(id, held - 2), isNull);
      await expectLater(bob2.say(id, 'anyone?'), throwsA(anything));
      await world.settle();
      expect(texts(alice), isEmpty);
      expect(texts(carol), isEmpty);
    });

    test('while the server cannot be reached the group waits; it is brought '
        'into use by the next call', () async {
      final id = await established();
      await bob.pumpBackup();
      final bob2 = await world.reinstall(bob);

      server.offline = true;
      final offline = await bob2.pumpBackup();
      expect(offline.looked, isFalse);
      expect(await bob2.store.groups(), isEmpty);

      server.offline = false;
      expect((await bob2.backup.sync()).restored, [id]);
      server.offline = true;
      await bob2.groups.resume();
      await bob2.groups.resume();
      var row = (await bob2.group(id))!;
      expect(row.resetPending, isTrue);
      expect(row.stateLoaded, isFalse);

      // Online again: no waiting time after a plain "no network".
      server.offline = false;
      await bob2.groups.resume();
      row = (await bob2.group(id))!;
      expect(row.resetPending, isFalse);
      await world.settle();
      expect(await bob2.standing(id), Gv2Membership.active);
    });

    test('a server that answers with an error: the group stays, and is not '
        'asked about again for ten minutes', () async {
      final id = await established();
      await bob.pumpBackup();
      final bob2 = await world.reinstall(bob);
      expect((await bob2.backup.sync()).restored, [id]);

      server.brokenReads = true;
      await bob2.groups.resume();
      final reads = server.reads;
      expect(reads, greaterThan(0));
      expect((await bob2.group(id))!.resetPending, isTrue);

      server.brokenReads = false;
      await bob2.groups.resume();
      world.now += gv2RestoreRetry.inMilliseconds - 1000;
      await bob2.groups.resume();
      expect(server.reads, reads);
      expect((await bob2.group(id))!.resetPending, isTrue);

      world.now += 1000;
      await bob2.groups.resume();
      expect(server.reads, greaterThan(reads));
      expect((await bob2.group(id))!.resetPending, isFalse);
      await world.settle();
      expect(await bob2.standing(id), Gv2Membership.active);
    });

    test('removed while away: the group is dropped, nothing is announced, '
        'and the backup lets go of it', () async {
      final id = await established(withCarol: true);
      final other = await alice.groups.create(title: 'Two', invite: [bob.snowId]);
      await world.settle();
      await bob.pumpBackup();
      expect(gv2OpenBackup(gv2DeriveBackupKey(bob.accountSeed),
          world.backups[bob.snowId]!), hasLength(2));

      final bob2 = await world.reinstall(bob);
      // Removed before the new install looks.
      await alice.groups.remove(id, bob.snowId);
      await world.settle();
      final sends = world.sends;

      expect((await bob2.pumpBackup()).restored.toSet(), {id, other});
      expect(await bob2.group(id), isNull);
      expect((await bob2.group(other))!.resetPending, isFalse);
      // One notice, for the group it is still in.
      await bob2.outbox.flush();
      expect(world.sends, sends + 1);
      final kept = gv2OpenBackup(
        gv2DeriveBackupKey(bob.accountSeed),
        world.backups[bob.snowId]!,
      )!;
      expect([for (final e in kept) gv2Hex(e.groupId)], [other]);
      await world.settle();
      expect(await bob2.standing(other), Gv2Membership.active);
    });

    test('a group the server no longer has, and an anchor the server\'s log '
        'does not bear out, are dropped', () async {
      final gone = await established();
      final forged = await alice.groups.create(title: 'Two', invite: [bob.snowId]);
      await world.settle();
      // The backup states another state at the anchor of the second group.
      final row = (await bob.group(forged))!;
      final other = (await bob.group(gone))!;
      world.backups[bob.snowId] = gv2SealBackup(
        gv2DeriveBackupKey(bob.accountSeed),
        [
          Gv2BackupEntry(
            groupId: gv2Unhex(gone),
            masterKey: other.masterKey,
            revision: other.revision,
            chain: other.chain,
            stateHash: other.stateHash,
          ),
          Gv2BackupEntry(
            groupId: gv2Unhex(forged),
            masterKey: row.masterKey,
            revision: row.revision,
            chain: row.chain,
            stateHash: gv2TestSha('not the state at this revision'),
          ),
        ],
      );
      final bob2 = await world.reinstall(bob);
      server.logs.remove(gone);
      final sends = world.sends;

      expect((await bob2.pumpBackup()).restored, hasLength(2));
      expect(await bob2.store.groups(), isEmpty);
      await bob2.outbox.flush();
      expect(world.sends, sends);
      expect(
        gv2OpenBackup(
          gv2DeriveBackupKey(bob.accountSeed),
          world.backups[bob.snowId]!,
        ),
        isEmpty,
      );
    });

    test('alone in the group: nobody to tell and nobody to confirm — it is '
        'usable at once', () async {
      final id = await alice.groups.create(title: 'Notes', invite: [bob.snowId]);
      await alice.outbox.flush(); // created; bob has not answered
      await alice.pumpBackup();
      final alice2 = await world.reinstall(alice);
      final sends = world.sends;

      expect((await alice2.pumpBackup()).restored, [id]);
      final row = (await alice2.group(id))!;
      expect(row.membership, Gv2Membership.active);
      expect(row.resetPending, isFalse);
      await alice2.outbox.flush();
      expect(world.sends, sends);
      expect(await alice2.queued(), isEmpty);

      // It still owns the group: the invite it made can be taken back and
      // made again.
      await alice2.groups.revokeInvite(id, bob.snowId);
      await alice2.groups.invite(id, bob.snowId);
      bob.acceptsInvites = true;
      await world.settle();
      expect(await bob.standing(id), Gv2Membership.active);
      await bob.say(id, 'hi');
      await world.settle();
      expect(texts(alice2), ['hi']);
    });

    test('a group that was frozen stays in the backup and is judged again '
        'from the last point this account verified', () async {
      final id = await established();
      await bob.store.setHold(id, Gv2Hold.frozen, evidence: _utf8('{}'));
      await bob.pumpBackup();
      final bob2 = await world.reinstall(bob);
      expect((await bob2.pumpBackup()).restored, [id]);
      await world.settle();
      // The server's log holds up this time.
      final row = (await bob2.group(id))!;
      expect(row.hold, Gv2Hold.none);
      expect(row.membership, Gv2Membership.active);
    });

    test('the server signed a log that leaves the one this account held: '
        'the group stays, frozen, and nothing is announced', () async {
      final id = await established();
      await bob.pumpBackup();
      final bob2 = await world.reinstall(bob);
      expect((await bob2.backup.sync()).restored, [id]);

      // Another history from one revision below the backup's anchor, one
      // entry longer than the real one.
      final log = server.logs[id]!;
      final groupId = gv2Unhex(id);
      final masterKey = (await alice.group(id))!.masterKey;
      final actor = gv2Unhex((await alice.group(id))!.myCiphertext);
      ({Gv2Entry entry, Gv2GroupState next}) inviting(
        Gv2GroupState on,
        String who,
      ) => gv2SignEntry(
        state: on,
        groupId: groupId,
        draft: Gv2EntryDraft(
          version: gv2ProtocolVersion,
          revision: on.revision + 1,
          prevChain: on.chain,
          actor: actor,
          actions: [
            Gv2Invite(
              ZkGroup.encryptMember(
                masterKey: masterKey,
                accountId: gv2TestBytes(who, 16),
              ),
              Gv2SigningKey.fromSeed(gv2TestSha('invite key $who')).publicKey,
            ),
          ],
          memberPayload: Uint8List(0),
          titlePayload: Uint8List(0),
        ),
        key: alice.memberKey(groupId),
      );
      final below = log.states[log.states.length - 2];
      final fork = inviting(inviting(below, 'x').next, 'y');
      log.add(fork.entry, fork.next);
      final sends = world.sends;

      await bob2.groups.resume();
      final row = (await bob2.group(id))!;
      expect(row.hold, Gv2Hold.frozen);
      expect(row.resetPending, isFalse);
      await bob2.outbox.flush();
      expect(world.sends, sends);
      expect(await bob2.queued(), isEmpty);
      // It stays in the backup, at the last point this account verified.
      await bob2.backup.sync();
      final kept = gv2OpenBackup(
        gv2DeriveBackupKey(bob.accountSeed),
        world.backups[bob.snowId]!,
      )!;
      expect(kept.single.revision, below.revision + 1);
    });

    test('alone by a state whose head the server did not sign: still '
        'waiting', () async {
      final id = await alice.groups.create(title: 'Notes', invite: const []);
      await alice.outbox.flush();
      await alice.pumpBackup();
      final alice2 = await world.reinstall(alice);
      expect((await alice2.backup.sync()).restored, [id]);

      server.forgeHeads = true;
      await alice2.groups.resume();
      var row = (await alice2.group(id))!;
      expect(row.stateLoaded, isTrue);
      expect(row.membership, Gv2Membership.awaitingConfirm);
      expect(row.resetPending, isTrue);

      server.forgeHeads = false;
      world.now += gv2RestoreRetry.inMilliseconds;
      await alice2.groups.resume();
      row = (await alice2.group(id))!;
      expect(row.membership, Gv2Membership.active);
      expect(row.resetPending, isFalse);
    });

    test('a member that is waiting for its own confirmation does not '
        'confirm; the notice of a reinstall is not answered twice', () async {
      final id = await established(withCarol: true);
      await bob.pumpBackup();
      await carol.pumpBackup();
      final bob2 = await world.reinstall(bob);
      final carol2 = await world.reinstall(carol);
      await bob2.pumpBackup();
      await carol2.pumpBackup();
      await world.settle();
      // Only alice could confirm; both are back.
      expect(await bob2.standing(id), Gv2Membership.active);
      expect(await carol2.standing(id), Gv2Membership.active);
      expect(alice.sessions.archives, 2);
      await bob2.say(id, 'one');
      await carol2.say(id, 'two');
      await world.settle();
      expect(texts(alice), ['one', 'two']);
      expect(texts(bob2), ['two']);
      expect(texts(carol2), ['one']);
    });
  });

  group('before the account is deleted', () {
    test('every group is left — an owner hands its group on — and invites '
        'are declined', () async {
      final member = await established(withCarol: true);
      carol.acceptsInvites = true;
      final owned = await bob.groups.create(title: 'Mine', invite: [carol.snowId]);
      await world.settle();
      expect(await carol.standing(owned), Gv2Membership.active);
      bob.acceptsInvites = false;
      final invited = await carol.groups.create(title: 'Theirs', invite: [bob.snowId]);
      await world.settle();
      expect(await bob.standing(invited), Gv2Membership.invited);

      expect(await bob.groups.leaveAll(), isEmpty);
      await world.settle();

      expect(server.logs[member]!.state.members, hasLength(2));
      expect(await bob.standing(member), Gv2Membership.left);
      expect(await alice.store.memberBySnowId(member, bob.snowId), isNull);
      // The owned group went to carol.
      final state = server.logs[owned]!.state;
      expect(state.members, hasLength(1));
      expect(state.members.values.single.role, gv2RoleOwner);
      expect(await carol.store.myRole(owned), gv2RoleOwner);
      // The invite is out of the log.
      expect(server.logs[invited]!.state.pending, isEmpty);
      expect(await bob.standing(invited), isNot(Gv2Membership.invited));
    });

    test('what cannot be left now is reported, and nothing throws', () async {
      final id = await established();
      final solo = await bob.groups.create(title: 'Mine', invite: [carol.snowId]);
      await world.settle();
      expect(await carol.standing(solo), Gv2Membership.active);
      await bob.db.customUpdate(
        "UPDATE gv2_members SET check_state = 'certificate' "
        'WHERE group_id = ? AND snow_id = ?',
        variables: [Variable.withString(solo), Variable.withString(carol.snowId)],
        updates: {bob.db.gv2Members},
      );

      server.offline = true;
      expect((await bob.groups.leaveAll()).toSet(), {id, solo});
      server.offline = false;
      // An owner with nobody it could hand the group to stays in it: the
      // deletion proof is what the members act on.
      expect(await bob.groups.leaveAll(), [solo]);
      expect(await bob.standing(id), Gv2Membership.left);
      expect(await bob.standing(solo), Gv2Membership.active);
    });

    test('a group from the backup that was never followed is followed '
        'first, then left', () async {
      final id = await established(withCarol: true);
      await bob.pumpBackup();
      final bob2 = await world.reinstall(bob);
      expect((await bob2.backup.sync()).restored, [id]);
      expect((await bob2.group(id))!.stateLoaded, isFalse);

      expect(await bob2.groups.leaveAll(), isEmpty);
      await world.settle();
      expect(server.logs[id]!.state.members, hasLength(2));
      expect(await alice.store.memberBySnowId(id, bob.snowId), isNull);
    });
  });
}
