/// @file        gv2_messaging_test.dart
/// @description Group protocol v2 messages end to end, without an emulator:
///              each device has its real database, inbox, outbox, Sender
///              Key store, pairwise service and messaging layer, real 1:1
///              Signal sessions and real sealed sender envelopes. Stand-ins:
///              the server (checks send tokens, hands envelopes to the
///              recipients' inboxes) and the change-log sync (serves the
///              test group's real signed log up to a revision). Covers
///              sending (keys first, the own row, order, holding back,
///              rotation after a removal, retries, reach), receiving (who
///              is believed, waiting for keys and for the log, replays,
///              unsend, clearing), the notices, and what a sender's place
///              in the log leads to (behind, ahead, withheld, forked).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-22 (SealedSenderService takes trustedServerKeys). Earlier 2026-11-21 (P5.6: the own key replaced after gv2OwnKeyMaxAge; P5.6: outcomes of a message written in the outbox's transaction; P5.6: endorsements for another revision — caught up in the same flush; a server that never agrees backs off). Earlier 2026-11-21 (P5.6: a member notice sealed again acts once; resets drop sessions at most once in ten minutes). Earlier 2026-11-21 (P5.6: a removed member's message after the change notice, on a device that had not synced, is judged after the sync). Earlier 2026-11-21 (a "busy" refusal fetches no endorsements). Earlier 2026-11-20 (P5.3: a point inside a batch is covered by the signed anchor; P5.2: a far-future place claimed on every envelope, a forged message far ahead on the sender's chain)
///
/// @functions
///  - main(): the test groups below.
///  - _World: the stand-in server, the group's history and the devices.
///  - _Device: one account's stores, inbox, outbox, sessions and layers.
///  - _Sync: Gv2LogSync serving a test group's log up to a revision.
///  - _Sink: Gv2MessageSink that records what it is given.
///
/// Notes:
///  - The history of the test group:
///      r0 alice creates, invites bob and carol   r1 bob accepts
///      r2 carol accepts                          r3 alice invites dave
///      r4 dave accepts                           r5 alice removes carol
///      r6 alice makes bob an admin
///    `world.served` is how far the stand-in server serves it.
///  - The world's clock moves one millisecond with every delivered envelope
///    (an arrival is later than the syncs before it) and when a test moves
///    it.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data' show ByteData;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/account_deletion_proof.dart';
import 'package:snowchat/core/crypto/sealed_sender.dart';
import 'package:snowchat/core/crypto/sender_key.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_content.dart';
import 'package:snowchat/core/group_v2/gv2_envelope.dart';
import 'package:snowchat/core/group_v2/gv2_invite.dart' show Gv2InviteMessage;
import 'package:snowchat/core/group_v2/gv2_inbox.dart';
import 'package:snowchat/core/group_v2/gv2_keys.dart';
import 'package:snowchat/core/group_v2/gv2_messaging.dart';
import 'package:snowchat/core/group_v2/gv2_outbox.dart';
import 'package:snowchat/core/group_v2/gv2_pairwise.dart';
import 'package:snowchat/core/group_v2/gv2_pairwise_crypto.dart';
import 'package:snowchat/core/group_v2/gv2_pairwise_service.dart';
import 'package:snowchat/core/group_v2/gv2_store.dart';
import 'package:snowchat/core/group_v2/gv2_sync.dart';
import 'package:snowchat/core/group_v2/gv2_transport.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';

import '../crypto/identity_test_support.dart';
import 'gv2_session_support.dart';
import 'gv2_test_support.dart';

const _names = ['alice', 'bob', 'carol', 'dave', 'eve'];
const _inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// r0..r2 of the test group; [more] appends the rest.
Gv2TestGroup _history(void Function(Gv2TestGroup g) more) {
  final g = Gv2TestGroup('messaging');
  final alice = g.person('alice');
  final bob = g.person('bob');
  final carol = g.person('carol');
  g.create(alice, invite: [bob, carol]);
  g.accept(bob);
  g.accept(carol);
  more(g);
  return g;
}

class _Sink implements Gv2MessageSink {
  final List<Gv2IncomingMessage> messages = [];
  final List<String> unsentIds = [];
  final List<String> waitingIds = [];
  final List<(int, String)> cleared = [];
  final List<Gv2SinkEvent> committedEvents = [];
  final List<List<Gv2Entry>> changes = [];
  bool failNext = false;

  List<String> get texts => [for (final m in messages) utf8.decode(m.payload)];

  @override
  Future<void> message(Gv2IncomingMessage message) async {
    if (failNext) {
      failNext = false;
      throw StateError('the message store failed');
    }
    messages.add(message);
  }

  @override
  Future<void> unsent({
    required String groupId,
    required String localMessageId,
    required String senderSnowId,
  }) async => unsentIds.add(localMessageId);

  @override
  Future<void> historyCleared({
    required String groupId,
    required int beforeMs,
    required String bySnowId,
  }) async => cleared.add((beforeMs, bySnowId));

  @override
  Future<bool> waiting({
    required String groupId,
    required String localMessageId,
    required int sentAtMs,
    required int receivedAtMs,
  }) async {
    if (waitingIds.contains(localMessageId)) return false;
    waitingIds.add(localMessageId);
    return true;
  }

  /// What became of this account's messages, as written with the outbox
  /// row leaving: (local message id, sent).
  final List<(String, bool)> outcomes = [];

  /// The write of an outcome fails (a database error).
  bool failOutgoing = false;

  @override
  Future<void> outgoing({
    required String groupId,
    required String localMessageId,
    required bool sent,
  }) async {
    if (failOutgoing) throw StateError('disk full');
    outcomes.add((localMessageId, sent));
  }

  @override
  void committed(Gv2SinkEvent event) => committedEvents.add(event);

  @override
  void groupChanged(String groupId, List<Gv2Entry> applied) =>
      changes.add(applied);
}

/// Serves a test group's log to one device, up to [limit] (or as far as
/// the world's server serves it).
class _Sync implements Gv2LogSync {
  final _Device device;
  _Sync(this.device);

  bool offline = false;

  /// The highest revision the server serves THIS device (withholding).
  int? limit;

  /// The log this device is served (a fork, when the server shows it
  /// another one).
  Gv2TestGroup? log;
  int runs = 0;

  /// Invites are not this suite's (Gv2GroupActions checks them).
  @override
  Future<bool?> inviteInLog({
    required Gv2InviteMessage invite,
    required Uint8List inviter,
    required Uint8List mine,
  }) async => null;

  @override
  Future<Gv2SyncResult> sync(String groupId) async {
    runs++;
    final world = device.world;
    final started = world.now;
    final store = device.store;
    final row = await store.group(groupId);
    if (row == null) return const Gv2SyncResult(Gv2SyncStatus.unknownGroup);
    Gv2SyncResult end(Gv2SyncStatus status) => Gv2SyncResult(
      status,
      fromRevision: row.revision,
      toRevision: row.revision,
      membership: row.membership,
    );
    if (offline) return end(Gv2SyncStatus.offline);
    if (row.hold == Gv2Hold.frozen) return end(Gv2SyncStatus.frozen);
    final g = log ?? world.group;
    final head = min(limit ?? world.served, g.states.length - 1);
    final from = (await store.loadState(groupId))!;
    var to = row.revision;
    var membership = row.membership;
    int? removal;
    while (to < head && _inside.contains(membership)) {
      to++;
      final entry = g.log[to];
      membership = gv2StandingAfter(
        before: membership,
        myCiphertext: row.myCiphertext,
        entry: entry,
        after: g.states[to],
      );
      if (entry.actions.any((a) => a is Gv2Remove || a is Gv2Leave)) {
        removal = to;
      }
    }
    if (to > row.revision) {
      await store.advance(
        from: from,
        to: g.states[to],
        headSig: g.headSig(to),
        membership: membership,
        removalRevision: removal,
        points: [
          for (var r = row.revision + 1; r <= to; r++)
            Gv2LogPoint(r, g.states[r].chain),
        ],
      );
    }
    await store.markSynced(groupId, started);
    return Gv2SyncResult(
      to > row.revision ? Gv2SyncStatus.advanced : Gv2SyncStatus.upToDate,
      fromRevision: row.revision,
      toRevision: to,
      membership: membership,
      applied: g.log.sublist(row.revision + 1, to + 1),
    );
  }

  @override
  Future<Gv2MemberCheckSummary> checkMembers(String groupId) async {
    await device.confirmAll();
    return const Gv2MemberCheckSummary(0, 0);
  }
}

class _Device {
  final _World world;
  final Gv2TestPerson person;
  final TestParty party;
  final SnowDatabase db;
  final Gv2TestSessions sessions;
  final Gv2TestCountingCrypto crypto;
  final Gv2TestTokens tokens = Gv2TestTokens();
  final _Sink sink = _Sink();
  final List<Gv2OutboxEvent> events = [];
  final List<Duration> sleeps = [];
  late final _Sync sync = _Sync(this);
  late final Gv2PairwiseService service;
  late final Gv2Messaging messaging;
  late final Gv2Inbox inbox;
  late final Gv2Outbox outbox;

  _Device._(
    this.world,
    this.person,
    this.party,
    this.db,
    this.sessions,
    this.crypto,
  );

  String get name => person.name;
  String get snowId => person.snowId;
  Gv2Store get store => db.gv2Store;
  String get groupId => world.group.id;

  static Future<_Device> create(_World world, Gv2TestPerson person) async {
    final party = await TestParty.create(
      accountSeed: person.accountSeed,
      deviceId: gv2TestDeviceIdOf(person.name),
      opkCount: 8,
    );
    expect(party.snowId, person.snowId);
    party.signal.setLocalIdentityBinding(
      party.localBinding(epoch: gv2TestBindingEpoch),
    );
    final db = SnowDatabase(NativeDatabase.memory());
    final sessions = Gv2TestSessions(party, world);
    final crypto = Gv2TestCountingCrypto(
      Gv2SealedPairwiseCrypto(
        sealed: SealedSenderService(trustedServerKeys: [world.serverVerifyKey]),
        certificate: () async => gv2TestCertificate(world.serverKey, party),
        sessions: sessions,
      ),
    );
    final d = _Device._(world, person, party, db, sessions, crypto);
    d.service = Gv2PairwiseService(
      groups: db.gv2Store,
      keys: db.gv2SenderKeyStore,
      outbox: db.gv2OutboxStore,
      crypto: crypto,
      serverHeadKey: () async => world.group.headKey.publicKey,
      mySnowId: person.snowId,
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
      mySnowId: person.snowId,
      nowMs: () => world.now,
      sleep: (duration) async {
        d.sleeps.add(duration);
        world.now += duration.inMilliseconds;
      },
      keyWaitRowsPerSender: 3,
    );
    d.inbox = Gv2Inbox(
      store: db.gv2InboxStore,
      groups: db.gv2Store,
      handler: d.messaging,
      ack: (_) async {},
      nowMs: () => world.now,
    );
    d.messaging.attach(d.inbox);
    d.outbox = Gv2Outbox(
      store: db.gv2OutboxStore,
      groups: db.gv2Store,
      keys: db.gv2SenderKeyStore,
      tokens: d.tokens,
      crypto: crypto,
      send: (entries, {noPush = const []}) => world.send(d, entries, noPush),
      mySnowId: () async => person.snowId,
      myDeviceId: () async => party.deviceId,
      memberKey: (_) async => person.memberKey,
      giveKeys: d.service.giveKeys,
      prepareGroup: d.messaging.prepareSend,
      recordOutcome: (e) => d.sink.outgoing(
        groupId: e.groupId,
        localMessageId: e.localMessageId,
        sent: e is Gv2MessageSent,
      ),
      onEvent: d.events.add,
      nowMs: () => world.now,
    );
    return d;
  }

  /// Put this device at [revision] of the group ([of]: of that log) with
  /// [membership]; every member is recorded as confirmed and the log counts
  /// as fetched now.
  Future<void> install(
    int revision, {
    Gv2Membership membership = Gv2Membership.active,
    Gv2TestGroup? of,
  }) async {
    final g = of ?? world.group;
    final state = g.states[revision];
    expect(
      await store.insertAnchored(
        groupId: g.groupId,
        masterKey: g.masterKey,
        myCiphertext: person.ciphertext,
        protocolVersion: state.version,
        revision: revision,
        chain: state.chain,
        stateHash: gv2StateHash(state),
        membership: Gv2Membership.awaitingConfirm,
      ),
      isTrue,
    );
    await store.installState(state: state, headSig: g.headSig(revision));
    if (membership != Gv2Membership.awaitingConfirm) {
      await store.setMembership(g.id, membership);
    }
    await confirmAll();
    await store.markSynced(g.id, world.now);
    inbox.groupsChanged();
  }

  Future<void> confirmAll() async {
    final rows = await store.membersToCheck(groupId, limit: 2000);
    if (rows.isEmpty) return;
    await store.saveMemberChecks(groupId, [
      for (final r in rows)
        Gv2MemberCheckResult(
          ciphertext: r.ciphertext,
          joinedRevision: r.joinedRevision,
          state: Gv2MemberCheckState.confirmed,
          snowId: world.personOf(r.ciphertext).snowId,
          accountPublicKey: world.personOf(r.ciphertext).accountPub,
          certIssuedAtMs: gv2TestIssuedAtMs,
        ),
    ]);
  }

  Future<Gv2GroupRow> group() async => (await store.group(groupId))!;

  Future<Gv2QueuedMessage> say(String text, {int expiresInSeconds = 0}) =>
      messaging.send(
        groupId,
        Gv2MessageContent(_utf8(text)),
        expiresInSeconds: expiresInSeconds,
      );

  /// This device's current own Sender Key chain.
  Future<int?> chainId() async =>
      (await db.gv2SenderKeyStore.ownCurrent(groupId, snowId))?.chainId;

  /// Types of the pairwise rows waiting in this device's outbox.
  Future<List<int>> queuedPairwise() async => [
    for (final r in await db.gv2OutboxStore.allRows())
      if (r.kind == Gv2OutboxKind.pairwise) r.payload[2],
  ];

  Future<List<Gv2OutboxKind>> queuedKinds() async => [
    for (final r in await db.gv2OutboxStore.allRows()) r.kind,
  ];
}

class _Delivery {
  final _Device to;
  final Uint8List envelope;
  const _Delivery(this.to, this.envelope);
}

class _Request {
  final _Device from;
  final List<Gv2SendEntry> entries;
  final List<Uint8List> noPush;
  const _Request(this.from, this.entries, this.noPush);

  bool get isGroup => entries.any((e) => e.recipients.length > 1);
}

class _World implements Gv2TestDirectory {
  final ed.SigningKey serverKey = ed.SigningKey(
    seed: gv2TestSha('gv2 messaging test — certificate server'),
  );
  late final Uint8List serverVerifyKey = Uint8List.fromList(
    serverKey.verifyKey.asTypedList,
  );

  late final Gv2TestGroup group = _history((g) {
    final alice = g.person('alice');
    g.invite(alice, g.person('dave'));
    g.accept(g.person('dave'));
    g.change(alice, [Gv2Remove(g.person('carol').ciphertext)]);
    g.change(alice, [Gv2SetRole(g.person('bob').ciphertext, gv2RoleAdmin)]);
  });

  /// How far the server serves the log.
  int served = 4;

  final Map<String, _Device> devices = {};
  final Map<String, int> _opk = {};
  final List<_Request> requests = [];
  final List<_Delivery> delivered = [];
  int now = DateTime.now().millisecondsSinceEpoch;
  int _rows = 0;

  bool failSends = false;

  /// The server takes the request, then the answer is lost.
  bool loseResponses = false;
  bool refuseTokens = false;

  /// The server refuses every entry for its own trouble ("busy").
  bool busy = false;

  /// Swallow envelopes of this first byte (0x01 pairwise, 0x02 group);
  /// what was swallowed is kept in [swallowed].
  final Set<int> swallow = {};
  final List<_Delivery> swallowed = [];

  /// Accounts the server no longer knows, with the proof it shows (if any).
  final Map<String, AccountDeletionProof?> gone = {};

  Gv2TestPerson personOf(String ciphertext) {
    for (final name in _names) {
      final p = group.person(name);
      if (p.key == ciphertext) return p;
    }
    throw StateError('unknown test ciphertext');
  }

  @override
  TestParty party(String snowId) => devices[snowId]!.party;

  @override
  int nextOpk(String snowId) {
    final n = _opk[snowId] ?? 0;
    _opk[snowId] = n + 1;
    return n;
  }

  Future<_Device> add(String name) async {
    final d = await _Device.create(this, group.person(name));
    devices[d.snowId] = d;
    return d;
  }

  String _nameOf(Uint8List accountId) {
    for (final name in _names) {
      if (_same(group.person(name).accountId, accountId)) return name;
    }
    throw StateError('unknown test account');
  }

  /// The stand-in server: checks each entry's token against its recipients
  /// and queues the envelope for each of them it knows.
  Future<List<Gv2SendResult>> send(
    _Device from,
    List<Gv2SendEntry> entries,
    List<Uint8List> noPush,
  ) async {
    if (failSends) throw const Gv2NetworkException();
    requests.add(_Request(from, entries, noPush));
    final results = <Gv2SendResult>[];
    for (final e in entries) {
      final expected = Gv2TestTokens.tokenFor(group.id, [
        for (final r in e.recipients) group.person(_nameOf(r)).key,
      ]);
      if (busy) {
        results.add(
          const Gv2SendResult(
            ok: false,
            error: 'busy',
            delivered: 0,
            unknownRecipients: [],
            throttledRecipients: 0,
            deleted: [],
          ),
        );
        continue;
      }
      if (refuseTokens || !_same(e.token, expected)) {
        results.add(
          const Gv2SendResult(
            ok: false,
            error: 'invalid_token',
            delivered: 0,
            unknownRecipients: [],
            throttledRecipients: 0,
            deleted: [],
          ),
        );
        continue;
      }
      final unknown = <Uint8List>[];
      final deleted = <Gv2DeletedRecipient>[];
      var count = 0;
      for (final r in e.recipients) {
        final snowId = 'snow${gv2Hex(r)}';
        if (gone.containsKey(snowId)) {
          unknown.add(r);
          final proof = gone[snowId];
          if (proof != null) {
            deleted.add(
              Gv2DeletedRecipient(
                accountId: r,
                accountPublicKey: group.person(_nameOf(r)).accountPub,
                proof: proof,
              ),
            );
          }
          continue;
        }
        final to = devices[snowId];
        if (to == null) continue; // an account with no device in this test
        await deliver(to, e.envelope);
        count++;
      }
      results.add(
        Gv2SendResult(
          ok: true,
          error: null,
          delivered: count,
          unknownRecipients: unknown,
          throttledRecipients: 0,
          deleted: deleted,
        ),
      );
    }
    if (loseResponses) throw const Gv2NetworkException();
    return results;
  }

  Future<void> deliver(_Device to, Uint8List envelope) async {
    if (swallow.contains(envelope[0])) {
      swallowed.add(_Delivery(to, envelope));
      return;
    }
    now++;
    _rows++;
    delivered.add(_Delivery(to, envelope));
    await to.inbox.receive([
      Gv2QueueRow(
        id: '00000000-0000-4000-8000-${_rows.toRadixString(16).padLeft(12, '0')}',
        seq: _rows,
        envelope: envelope,
      ),
    ]);
  }

  /// What the world looks like: when a round changes nothing of it, the
  /// world has settled.
  Future<String> _snapshot() async {
    final out = StringBuffer('${requests.length}/${delivered.length}');
    for (final d in devices.values) {
      final group = await d.store.group(this.group.id);
      out.write('|${group?.revision},${group?.membership},${group?.hold}');
      for (final r in await d.db.gv2OutboxStore.allRows()) {
        out.write(';o${r.localId}:${r.attempts}');
      }
      for (final r in await d.db.gv2InboxStore.allRows()) {
        out.write(';i${r.localId}:${r.state.name}:${r.attempts}');
      }
      out.write(
        ';s${d.sink.messages.length},${d.sink.unsentIds.length},'
        '${d.sink.cleared.length},${d.events.length}',
      );
    }
    return out.toString();
  }

  /// Send and handle until nothing moves any more.
  Future<void> settle() async {
    var before = await _snapshot();
    for (var round = 0; round < 40; round++) {
      for (final d in devices.values) {
        await d.outbox.flush();
      }
      for (final d in devices.values) {
        await d.inbox.drain();
      }
      final after = await _snapshot();
      if (after == before) return;
      before = after;
    }
    fail('the world does not settle');
  }

  /// The requests that carried a message to the group, oldest first.
  List<_Request> get groupRequests => [
    for (final r in requests)
      if (r.isGroup) r,
  ];

  Future<void> close() async {
    for (final d in devices.values) {
      await d.db.close();
    }
  }
}

/// Seal [body] again under [stamp] with the group's envelope key: what
/// anyone who ever held the group key can do.
Uint8List _rewrap(Gv2TestGroup g, Gv2EnvelopeStamp stamp, Uint8List body) =>
    gv2SealEnvelope(
      keys: Gv2EnvelopeKeys.derive(g.masterKey, g.groupId),
      header: Gv2EnvelopeHeader(
        kind: gv2KindContent,
        stamp: stamp,
        bodyLength: body.length,
      ),
      body: body,
    );

Gv2OpenedEnvelope _open(Gv2TestGroup g, Uint8List envelope) => gv2OpenEnvelope(
  keys: Gv2EnvelopeKeys.derive(g.masterKey, g.groupId),
  envelope: envelope,
)!;

void main() {
  // Each device has its own in-memory database, on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late _World world;
  late Gv2TestGroup g;
  late _Device alice;
  late _Device bob;
  late _Device carol;
  late _Device dave;

  setUp(() async {
    world = _World();
    g = world.group;
    alice = await world.add('alice');
    bob = await world.add('bob');
    carol = await world.add('carol');
    dave = await world.add('dave');
  });
  tearDown(() => world.close());

  Future<void> everyoneAt4() async {
    for (final d in [alice, bob, carol, dave]) {
      await d.install(4);
    }
  }

  /// The last group envelope handed to [to].
  Uint8List lastGroupEnvelope(_Device to) => world.delivered
      .lastWhere((d) => d.to == to && d.envelope[0] == gv2EnvelopeVersion)
      .envelope;

  group('sending', () {
    test('a message reaches every confirmed member once: the keys first, then '
        'one envelope for the whole roster, this account included', () async {
      await everyoneAt4();
      final queued = await alice.say('hello');
      await world.settle();

      for (final d in [bob, carol, dave]) {
        expect(d.sink.texts, ['hello'], reason: d.name);
        final m = d.sink.messages.single;
        expect(m.localMessageId, queued.localMessageId);
        expect(m.senderSnowId, alice.snowId);
        expect(m.senderDeviceId, alice.party.deviceId);
        expect(m.sentAtMs, queued.timestampMs);
        expect(d.sink.committedEvents.single, isA<Gv2MessageStored>());
      }
      // The sender's own copy came back and was dropped.
      expect(alice.sink.messages, isEmpty);
      expect(await alice.db.gv2InboxStore.allRows(), isEmpty);
      expect(alice.events.single, isA<Gv2MessageSent>());
      expect(alice.events.single.localMessageId, queued.localMessageId);

      // First the keys (three, and the extra entry to this account), all
      // silent; then the message.
      final fromAlice = [
        for (final r in world.requests)
          if (r.from == alice) r,
      ];
      expect(fromAlice, hasLength(2));
      expect(fromAlice[0].entries, hasLength(4));
      expect(fromAlice[0].entries.every((e) => e.silent), isTrue);
      expect(
        fromAlice[0].entries.every((e) => e.recipients.length == 1),
        isTrue,
      );
      final message = fromAlice[1].entries.single;
      expect(message.silent, isFalse);
      expect(message.expiresIn, isNull);
      expect(
        {for (final r in message.recipients) 'snow${gv2Hex(r)}'},
        {alice.snowId, bob.snowId, carol.snowId, dave.snowId},
      );
      // No push to the sender's own account.
      expect(fromAlice[1].noPush.single, alice.person.accountId);
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
      expect((await alice.group()).myKeyRevision, 4);
      // Reading moved bob's stored copy of alice's chain past the message:
      // its key is spent, the same envelope cannot be read again.
      final opened = _open(g, lastGroupEnvelope(bob));
      expect(
        () async => gv2OpenContent(
          groupId: g.groupId,
          envelope: opened,
          senderKeys: await bob.db.gv2SenderKeyStore.manager(
            g.id,
            alice.snowId,
          ),
        ),
        throwsA(
          isA<SenderKeyException>().having(
            (e) => e.reason,
            'reason',
            SenderKeyFailure.expired,
          ),
        ),
      );
    });

    test('the next message needs no keys: one request', () async {
      await everyoneAt4();
      await alice.say('one');
      await world.settle();
      world.requests.clear();
      await alice.say('two', expiresInSeconds: 3600);
      await world.settle();
      expect(world.requests, hasLength(1));
      expect(world.requests.single.entries.single.expiresIn, 3600);
      expect(bob.sink.texts, ['one', 'two']);
    });

    test('messages keep the order they were written in', () async {
      await everyoneAt4();
      world.failSends = true;
      for (final t in ['a', 'b', 'c']) {
        await alice.say(t);
        await alice.outbox.flush();
      }
      world.failSends = false;
      world.now += 3600 * 1000;
      await alice.store.markSynced(g.id, world.now);
      world.requests.clear();
      await world.settle();
      expect(bob.sink.texts, ['a', 'b', 'c']);
      expect(dave.sink.texts, ['a', 'b', 'c']);
      // The keys — queued behind 'a' and backing off with it — still left
      // before it: a pass sends the pairwise rows first.
      final fromAlice = [
        for (final r in world.requests)
          if (r.from == alice) r,
      ];
      expect(fromAlice.first.isGroup, isFalse);
      expect(fromAlice.skip(1).every((r) => r.isGroup), isTrue);
      expect(fromAlice, hasLength(4));
    });

    test(
      'a message behind one that is backing off does not overtake it',
      () async {
        await everyoneAt4();
        await alice.say('first');
        world.failSends = true;
        await alice.outbox.flush();
        world.failSends = false;
        await alice.say('second');
        await world.settle();
        // 'first' backs off; 'second' waits behind it.
        expect(bob.sink.texts, isEmpty);
        world.now += 3600 * 1000;
        await alice.store.markSynced(g.id, world.now);
        await world.settle();
        expect(bob.sink.texts, ['first', 'second']);
      },
    );

    test(
      'before this device is confirmed nothing it writes leaves; a member\'s '
      'confirmation releases it',
      () async {
        await alice.install(4);
        await dave.install(4);
        await bob.install(4, membership: Gv2Membership.awaitingConfirm);
        await bob.say('too early');
        await world.settle();
        expect(world.requests.where((r) => r.from == bob), isEmpty);
        expect(await bob.queuedKinds(), [Gv2OutboxKind.content]);
        expect(await bob.chainId(), isNull);

        expect(await alice.service.confirmHead(g.id, bob.snowId), isTrue);
        await world.settle();
        expect((await bob.group()).membership, Gv2Membership.active);
        world.now += 61 * 1000; // the held row is looked at again
        await world.settle();
        expect(alice.sink.texts, ['too early']);
        expect(dave.sink.texts, ['too early']);
      },
    );

    test('a removal makes the next message use a new key that the removed '
        'member is not given', () async {
      await everyoneAt4();
      await alice.say('before');
      await world.settle();
      final oldChain = await alice.chainId();
      expect(carol.sink.texts, ['before']);

      world.served = 5; // carol is removed
      await alice.inbox.requestSync(g.id);
      expect((await alice.group()).lastRemovalRevision, 5);
      world.requests.clear();
      await alice.say('after');
      await world.settle();

      final newChain = await alice.chainId();
      expect(newChain, isNot(oldChain));
      expect((await alice.group()).myKeyRevision, 5);
      expect(bob.sink.texts, ['before', 'after']);
      expect(dave.sink.texts, ['before', 'after']);
      expect(carol.sink.texts, ['before']);
      // Nothing was addressed to carol: neither the key nor the message.
      for (final r in world.requests) {
        for (final e in r.entries) {
          expect(
            e.recipients.any((id) => _same(id, carol.person.accountId)),
            isFalse,
          );
        }
      }
      // Handed the envelope anyway, carol cannot read it: it has the group
      // key and the OLD Sender Key only.
      final opened = _open(g, lastGroupEnvelope(bob));
      final carolKeys = await carol.db.gv2SenderKeyStore.manager(
        g.id,
        alice.snowId,
      );
      expect(
        () => gv2OpenContent(
          groupId: g.groupId,
          envelope: opened,
          senderKeys: carolKeys,
        ),
        throwsA(
          isA<SenderKeyException>().having(
            (e) => e.reason,
            'reason',
            SenderKeyFailure.noKey,
          ),
        ),
      );
    });

    test(
      'a removal applied before the app died still forces a new key: the '
      'need is read from the stored state when the message is sent',
      () async {
        await everyoneAt4();
        await alice.say('before');
        await world.settle();
        final oldChain = await alice.chainId();
        // The sync applied the removal; the app died before anything else.
        world.served = 5;
        await alice.sync.sync(g.id);
        final row = await alice.group();
        expect(row.lastRemovalRevision, 5);
        expect(row.myKeyRevision, 4);
        await alice.say('after the restart');
        await world.settle();
        expect(await alice.chainId(), isNot(oldChain));
        expect(bob.sink.texts, ['before', 'after the restart']);
      },
    );

    test('a log older than ten minutes is fetched before a message goes; '
        'without it the message waits', () async {
      await everyoneAt4();
      await alice.say('fresh');
      await world.settle();
      expect(alice.sync.runs, 0);

      world.now += gv2SendFreshness.inMilliseconds + 1;
      alice.sync.offline = true;
      await alice.say('stale');
      await world.settle();
      expect(alice.sync.runs, 1);
      expect(bob.sink.texts, ['fresh']);
      expect(await alice.queuedKinds(), [Gv2OutboxKind.content]);

      alice.sync.offline = false;
      world.now += 3600 * 1000;
      await world.settle();
      expect(bob.sink.texts, ['fresh', 'stale']);
    });

    test('a member who joined since the last sync is found by the sync before '
        'the send and gets the key first', () async {
      await alice.install(2);
      await bob.install(2);
      await carol.install(2);
      await dave.install(4);
      world.now += gv2SendFreshness.inMilliseconds + 1;
      await alice.say('hello dave');
      await world.settle();
      expect((await alice.group()).revision, 4);
      expect(dave.sink.texts, ['hello dave']);
      expect(bob.sink.texts, ['hello dave']);
    });

    test('a send whose answer was lost is sent again under the same message '
        'id: receivers show it once', () async {
      await everyoneAt4();
      await alice.say('warm up');
      await world.settle();
      world.loseResponses = true;
      final queued = await alice.say('once');
      await world.settle();
      expect(bob.sink.texts, ['warm up', 'once']);
      expect(alice.events, hasLength(1)); // not known to be sent yet

      world.loseResponses = false;
      world.now += 60 * 1000;
      await world.settle();
      expect(alice.events, hasLength(2));
      expect(bob.sink.texts, ['warm up', 'once']);
      expect(
        bob.sink.messages.where(
          (m) => m.localMessageId == queued.localMessageId,
        ),
        hasLength(1),
      );
      // The second copy was read (its key is spent) and left the inbox.
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
      // Two envelopes of the same message id, two positions of the chain.
      final copies = [
        for (final d in world.delivered)
          if (d.to == bob && d.envelope[0] == gv2EnvelopeVersion)
            _open(g, d.envelope),
      ].where((e) => _same(e.stamp.messageId, queued.messageId)).toList();
      expect(copies, hasLength(2));
      expect(_same(copies[0].body, copies[1].body), isFalse);
    });

    test('a token the server refuses: endorsements are fetched again and the '
        'message goes later', () async {
      await everyoneAt4();
      world.refuseTokens = true;
      await alice.say('patience');
      await world.settle();
      expect(bob.sink.texts, isEmpty);
      expect(alice.tokens.refreshes, greaterThan(0));
      world.refuseTokens = false;
      world.now += 3600 * 1000;
      await alice.store.markSynced(g.id, world.now);
      await world.settle();
      expect(bob.sink.texts, ['patience']);
    });

    test('endorsements for another revision of the log: the group is caught '
        'up and the message goes in the same flush — not a failed attempt '
        'with its backoff', () async {
      await everyoneAt4();
      world.now += 10 * 1000; // past the distance between two syncs
      final before = (await alice.store.group(g.id))!.lastSyncAtMs;
      alice.tokens.missing.add(g.id);
      alice.tokens.revisionDiffers = (id) async =>
          (await alice.store.group(id))!.lastSyncAtMs == before;
      await alice.say('in step');
      await world.settle();
      expect(bob.sink.texts, ['in step']);
      expect((await alice.store.group(g.id))!.lastSyncAtMs, greaterThan(before));
      expect(await alice.queuedKinds(), isEmpty);
    });

    test('a server whose endorsements never match the log: one sync per '
        'flush, then the row backs off', () async {
      await everyoneAt4();
      world.now += 10 * 1000;
      alice.tokens.missing.add(g.id);
      alice.tokens.revisionDiffers = (_) async => true;
      final refreshes = alice.tokens.refreshes;
      await alice.say('never');
      await world.settle();
      expect(bob.sink.texts, isEmpty);
      // The message and the keys before it: one failed attempt each, and
      // backing off.
      final rows = await alice.db.gv2OutboxStore.allRows();
      expect(rows.map((r) => r.kind), contains(Gv2OutboxKind.content));
      for (final r in rows) {
        expect(r.attempts, 1, reason: '${r.kind}');
        expect(r.notBeforeMs, greaterThan(world.now));
      }
      // Asked twice: before the one sync, and in the pass after it.
      expect(alice.tokens.refreshes - refreshes, 2);
    });

    test('a row behind one that backs off does not wake the app before it: '
        'a time of its own that has passed is cleared', () async {
      await everyoneAt4();
      world.busy = true; // nothing goes
      await alice.say('first');
      await alice.say('second');
      await world.settle();
      final store = alice.db.gv2OutboxStore;
      final content = [
        for (final r in await store.allRows())
          if (r.kind == Gv2OutboxKind.content) r,
      ];
      expect(content, hasLength(2));
      // The first backs off for an hour; the second's own backoff is over.
      await store.later(content[0].localId,
          notBeforeMs: world.now + 3600 * 1000, failed: true);
      await store.later(content[1].localId,
          notBeforeMs: world.now - 1000, failed: true);
      for (final r in await store.allRows()) {
        if (r.kind != Gv2OutboxKind.content) await store.remove(r.localId);
      }
      await alice.outbox.flush();
      expect(await store.nextWakeMs(), world.now + 3600 * 1000);
      world.busy = false;
    });

    test('a refusal for the server\'s own trouble ("busy"): no endorsements '
        'are fetched for it, and the message goes later', () async {
      await everyoneAt4();
      world.busy = true;
      await alice.say('later');
      await world.settle();
      expect(bob.sink.texts, isEmpty);
      expect(alice.tokens.refreshes, 0);
      world.busy = false;
      world.now += 3600 * 1000;
      await alice.store.markSynced(g.id, world.now);
      await world.settle();
      expect(bob.sink.texts, ['later']);
    });

    test('an account the server does not know is marked unreachable, and '
        'nothing more; back again it is reachable', () async {
      await everyoneAt4();
      world.gone[carol.snowId] = null;
      await alice.say('one');
      await world.settle();
      Future<Gv2Reach> reach() async =>
          (await alice.store.memberBySnowId(g.id, carol.snowId))!.reach;
      expect(await reach(), Gv2Reach.unreachable);
      expect(bob.sink.texts, ['one']);

      world.gone.clear();
      await alice.say('two');
      await world.settle();
      expect(await reach(), Gv2Reach.ok);
      // Still a recipient all along.
      expect(world.groupRequests.last.entries.single.recipients, hasLength(4));
    });

    test('a deletion proof counts only when the member\'s own account key '
        'signed it and the membership is older', () async {
      await everyoneAt4();
      AccountDeletionProof proofBy(Gv2TestPerson signer, int deletedAtMs) =>
          AccountDeletionProof(
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
      Future<Gv2Reach> reach() async =>
          (await alice.store.memberBySnowId(g.id, carol.snowId))!.reach;

      // Signed by someone else.
      world.gone[carol.snowId] = proofBy(dave.person, gv2TestIssuedAtMs + 1);
      await alice.say('one');
      await world.settle();
      expect(await reach(), Gv2Reach.unreachable);

      // Signed by carol, but older than her membership (a later re-join).
      world.gone[carol.snowId] = proofBy(carol.person, gv2TestIssuedAtMs - 1);
      await alice.say('two');
      await world.settle();
      expect(await reach(), Gv2Reach.unreachable);

      world.gone[carol.snowId] = proofBy(carol.person, gv2TestIssuedAtMs + 1);
      await alice.say('three');
      await world.settle();
      expect(await reach(), Gv2Reach.deleted);

      // From now on carol is no recipient.
      await alice.say('four');
      await world.settle();
      expect(world.groupRequests.last.entries.single.recipients, hasLength(3));
      expect(bob.sink.texts, ['one', 'two', 'three', 'four']);
    });

    test('nothing can be said in a group this account is not in, or that is '
        'frozen', () async {
      await everyoneAt4();
      await expectLater(
        alice.messaging.send(
          gv2Hex(gv2TestSha('no such group')),
          Gv2MessageContent(_utf8('x')),
        ),
        throwsA(isA<Gv2NotSendable>()),
      );
      await alice.store.setHold(g.id, Gv2Hold.frozen, evidence: _utf8('{}'));
      await expectLater(alice.say('x'), throwsA(isA<Gv2NotSendable>()));
      await expectLater(
        alice.messaging.noticeChange(g.id),
        throwsA(isA<Gv2NotSendable>()),
      );
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
    });

    test('a queued message is given up when this account is removed before it '
        'could go, and the app is told', () async {
      await everyoneAt4();
      world.failSends = true;
      final queued = await carol.say('never');
      await carol.outbox.flush();
      world.failSends = false;
      world.served = 5;
      await carol.inbox.requestSync(g.id);
      expect((await carol.group()).membership, Gv2Membership.removed);
      world.now += 3600 * 1000;
      await world.settle();
      expect(carol.events.single, isA<Gv2MessageGivenUp>());
      expect(carol.events.single.localMessageId, queued.localMessageId);
      expect(carol.sink.outcomes, [(queued.localMessageId, false)]);
      expect(await carol.db.gv2OutboxStore.allRows(), isEmpty);
      expect(bob.sink.texts, isEmpty);
    });

    test('this device\'s own Sender Key is replaced once older than '
        'gv2OwnKeyMaxAge — before the next message, not while idle', () async {
      await everyoneAt4();
      Future<int> chain() async => (await alice.db.gv2SenderKeyStore
          .ownCurrent(g.id, alice.snowId))!.chainId;
      Future<void> later(Duration d) async {
        world.now += d.inMilliseconds;
        await alice.store.markSynced(g.id, world.now);
      }

      await alice.say('one');
      await world.settle();
      final first = await chain();
      await later(const Duration(days: 6));
      await alice.say('two');
      await world.settle();
      expect(await chain(), first);
      await later(const Duration(days: 2));
      await alice.say('three');
      await world.settle();
      expect(await chain(), isNot(first));
      expect(bob.sink.texts, ['one', 'two', 'three']);
    });

    test('a message that waited longer than the outbox keeps a row is given '
        'up', () async {
      await everyoneAt4();
      world.failSends = true;
      await alice.say('late');
      await alice.outbox.flush();
      world.now += gv2OutboxRetention.inMilliseconds + 1;
      await alice.outbox.flush();
      expect(alice.events.single, isA<Gv2MessageGivenUp>());
      expect(alice.sink.outcomes.single.$2, isFalse);
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
    });

    test('what became of a message is written in the transaction that takes '
        'its row out of the queue: when that write fails the row stays, and '
        'goes again', () async {
      await everyoneAt4();
      alice.sink.failOutgoing = true;
      final queued = await alice.say('once');
      await world.settle();
      expect(alice.sink.outcomes, isEmpty);
      expect(alice.events, isEmpty, reason: 'nothing told before the commit');
      expect(await alice.queuedKinds(), contains(Gv2OutboxKind.content));

      alice.sink.failOutgoing = false;
      world.now += 3600 * 1000;
      await alice.store.markSynced(g.id, world.now);
      await world.settle();
      expect(alice.sink.outcomes, [(queued.localMessageId, true)]);
      expect(alice.events.single, isA<Gv2MessageSent>());
      expect(await alice.queuedKinds(), isEmpty);
      // The receivers show it once (the same local message id).
      expect(bob.sink.texts, ['once']);
    });

    test('with nobody else in the group the message is done without a '
        'request', () async {
      await alice.install(0);
      await alice.say('to myself');
      await world.settle();
      expect(world.requests, isEmpty);
      expect(alice.events.single, isA<Gv2MessageSent>());
    });

    test('what the app stores with a message commits with it, or neither '
        'does', () async {
      await everyoneAt4();
      Gv2QueuedMessage? seen;
      await alice.messaging.send(
        g.id,
        Gv2MessageContent(_utf8('kept')),
        alsoWrite: (q) async => seen = q,
      );
      expect(seen, isNotNull);
      expect(await alice.queuedKinds(), [Gv2OutboxKind.content]);
      await expectLater(
        alice.messaging.send(
          g.id,
          Gv2MessageContent(_utf8('lost')),
          alsoWrite: (_) async => throw StateError('the message store failed'),
        ),
        throwsStateError,
      );
      expect(await alice.queuedKinds(), [Gv2OutboxKind.content]);
    });

    test('a group on hold sends neither messages nor keys', () async {
      await everyoneAt4();
      await alice.store.setHold(g.id, Gv2Hold.updateRequired);
      await alice.say('held');
      await world.settle();
      expect(world.requests, isEmpty);
      expect(await alice.chainId(), isNull);
      expect(await alice.service.giveKey(g.id, bob.snowId), isFalse);

      await alice.store.setHold(g.id, Gv2Hold.none);
      world.now += 61 * 1000;
      await world.settle();
      expect(bob.sink.texts, ['held']);

      // A key that was queued before the hold began does not leave either.
      world.served = 5;
      await alice.inbox.requestSync(g.id); // a removal: the next key is new
      await alice.db.gv2SenderKeyStore.createOwn(g.id, alice.snowId);
      await alice.store.setMyKeyRevision(g.id, 5);
      expect(await alice.service.giveKey(g.id, bob.snowId), isTrue);
      await alice.store.setHold(g.id, Gv2Hold.updateRequired);
      world.requests.clear();
      await world.settle();
      expect(world.requests.where((r) => r.from == alice), isEmpty);
      expect(await alice.queuedPairwise(), [gv2PairwiseTypeSenderKey]);
      await alice.store.setHold(g.id, Gv2Hold.none);
      world.now += 61 * 1000;
      await world.settle();
      expect(await alice.queuedPairwise(), isEmpty);
    });

    test(
      'a member whose account is gone for good is not given the key',
      () async {
        await everyoneAt4();
        await alice.store.setReach(g.id, carol.person.key, Gv2Reach.deleted);
        await alice.say('x');
        await world.settle();
        final keys = alice.db.gv2SenderKeyStore;
        final chain = (await alice.chainId())!;
        expect(await keys.deliveredTo(g.id, chain), {bob.snowId, dave.snowId});
        expect(carol.sink.texts, isEmpty);
      },
    );
  });

  group('receiving', () {
    test('a message whose key has not come waits; the key is asked for and '
        'answered with the key first given', () async {
      await everyoneAt4();
      world.swallow.add(0x01); // the keys are lost on the way
      await alice.say('patience');
      await alice.outbox.flush();
      world.swallow.clear();
      final chain = (await alice.chainId())!;
      final given = await alice.db.gv2SenderKeyStore.delivered(
        g.id,
        bob.snowId,
        chain,
      );

      await bob.inbox.drain();
      expect(bob.sink.texts, isEmpty);
      expect(await bob.queuedPairwise(), [gv2PairwiseTypeKeyRequest]);
      final waiting = (await bob.db.gv2InboxStore.allRows()).single;
      expect(waiting.state, Gv2InboxState.waitingKey);
      expect(waiting.waitFor, alice.snowId);

      await world.settle();
      expect(bob.sink.texts, ['patience']);
      expect(carol.sink.texts, ['patience']);
      // The key bob holds is the one recorded as given, not a later one.
      final after = await alice.db.gv2SenderKeyStore.delivered(
        g.id,
        bob.snowId,
        chain,
      );
      expect(after!.encode(), given!.encode());
    });

    test('at most keyWaitRowsPerSender rows of a group wait for one sender\'s '
        'key; beyond, a row is dropped', () async {
      await everyoneAt4();
      world.swallow.add(0x01); // the keys are lost on the way
      for (var i = 0; i < 5; i++) {
        await alice.say('m$i');
      }
      await alice.outbox.flush();
      world.swallow.clear();
      await bob.inbox.drain();
      final waiting = [
        for (final r in await bob.db.gv2InboxStore.allRows())
          if (r.state == Gv2InboxState.waitingKey) r,
      ];
      expect(waiting, hasLength(3));
      expect(await bob.db.gv2InboxStore.allRows(), hasLength(3));
    });

    test('a key request that went missing is made again when the waiting row '
        'is looked at later', () async {
      await everyoneAt4();
      world.swallow.add(0x01);
      await alice.say('patience');
      await alice.outbox.flush();
      await bob.inbox.drain();
      await bob.outbox.flush(); // the request is lost too
      world.swallow.clear();
      await world.settle();
      expect(bob.sink.texts, isEmpty);

      world.now += gv2KeyWaitRetry.inMilliseconds + 1;
      await world.settle();
      expect(bob.sink.texts, ['patience']);
    });

    test('a message whose key has not come for ten minutes gets a place that '
        'says so — once — and the message takes it when the key comes', () async {
      await everyoneAt4();
      world.swallow.add(0x01); // keys and key requests are lost
      await alice.say('late');
      await alice.outbox.flush();
      await bob.inbox.drain();
      await bob.outbox.flush();
      expect(bob.sink.waitingIds, isEmpty); // not at once

      world.now += gv2KeyWaitShown.inMilliseconds - 1000;
      await bob.inbox.keyArrived(g.id, alice.snowId); // looked at again
      await bob.inbox.drain();
      expect(bob.sink.waitingIds, isEmpty); // not before the time

      world.now += gv2KeyWaitRetry.inMilliseconds;
      await bob.inbox.drain();
      await bob.outbox.flush();
      expect(bob.sink.waitingIds, hasLength(1));
      expect(
        bob.sink.committedEvents.whereType<Gv2MessageWaiting>().single
            .localMessageId,
        bob.sink.waitingIds.single,
      );
      expect(bob.sink.messages, isEmpty);
      // The envelope still waits for its key.
      expect(
        (await bob.db.gv2InboxStore.allRows()).single.state,
        Gv2InboxState.waitingKey,
      );

      // Looked at again later: the place is not made, or told, twice.
      world.now += gv2KeyWaitRetry.inMilliseconds + 1;
      await bob.inbox.drain();
      await bob.outbox.flush();
      expect(bob.sink.waitingIds, hasLength(1));
      expect(
        bob.sink.committedEvents.whereType<Gv2MessageWaiting>(),
        hasLength(1),
      );

      world.swallow.clear();
      world.now += gv2KeyWaitRetry.inMilliseconds + 1;
      await world.settle();
      expect(bob.sink.texts, ['late']);
      expect(bob.sink.messages.single.localMessageId, bob.sink.waitingIds.single);
    });

    test('a copy of a shown message\'s header over a body that names an '
        'unknown key gets no place: what is shown stays', () async {
      await everyoneAt4();
      await alice.say('shown');
      await world.settle();
      expect(bob.sink.texts, ['shown']);
      final opened = _open(g, lastGroupEnvelope(bob));
      final body = Uint8List.fromList(opened.body);
      // Another chain id (bytes 1..4): a key this device does not hold.
      body[4] ^= 0x01;
      world.swallow.add(0x01);
      await world.deliver(bob, _rewrap(g, opened.stamp, body));
      await bob.inbox.drain();
      await bob.outbox.flush();
      world.now += gv2KeyWaitRetry.inMilliseconds + 1;
      await bob.inbox.drain();
      expect(
        (await bob.db.gv2InboxStore.allRows()).single.state,
        Gv2InboxState.waitingKey,
      );
      expect(bob.sink.waitingIds, isEmpty);
      expect(bob.sink.committedEvents.whereType<Gv2MessageWaiting>(), isEmpty);
    });

    test('a sender this device does not know as a member is dropped after one '
        'look at the log', () async {
      await alice.install(2);
      await bob.install(2);
      await carol.install(2);
      await dave.install(4);
      world.served = 2; // the server never shows dave's join
      final runs = bob.sync.runs;
      await dave.say('who is this');
      await world.settle();
      expect(bob.sink.texts, isEmpty);
      expect(bob.sync.runs, greaterThan(runs));
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });

    test('a sender who joined after this device last looked is found by the '
        'sync, and then read', () async {
      await alice.install(2);
      await bob.install(2);
      await carol.install(2);
      await dave.install(4);
      await dave.say('hello, I am new');
      await world.settle();
      expect((await bob.group()).revision, 4);
      expect(bob.sink.texts, ['hello, I am new']);
      expect(bob.sink.changes.single.last.revision, 4);
    });

    test('what a member sent before its removal is read; what arrives after '
        'the removal was applied is not, and its key is gone', () async {
      await everyoneAt4();
      await carol.say('goodbye');
      await carol.outbox.flush(); // in the inboxes, not handled yet
      world.served = 5;
      await alice.inbox.requestSync(g.id);
      await alice.messaging.noticeChange(g.id);
      await alice.outbox.flush();

      // One drain: the message first (under the roster it was sent to),
      // then the notice makes bob fetch the log.
      await bob.inbox.drain();
      expect(bob.sink.texts, ['goodbye']);
      expect((await bob.group()).revision, 5);
      final keys = bob.db.gv2SenderKeyStore;
      expect(
        (await keys.manager(
          g.id,
          carol.snowId,
        )).hasSenderKey(g.id, carol.snowId),
        isFalse,
      );

      carol.sync.offline = true; // carol does not learn of it
      await world.settle(); // dave reads 'goodbye' and applies the removal
      await carol.say('still here?');
      await world.settle();
      expect(bob.sink.texts, ['goodbye']);
      expect(dave.sink.texts, ['goodbye']);
    });

    test('a removed member that has not heard of its removal cannot post to '
        'a device that has not either: what arrives after the change notice '
        'is judged after the sync', () async {
      await everyoneAt4();
      await carol.say('goodbye');
      await carol.outbox.flush(); // before the removal
      world.served = 5; // alice removes carol
      await alice.inbox.requestSync(g.id);
      await alice.messaging.noticeChange(g.id);
      await alice.outbox.flush();
      carol.sync.offline = true; // carol does not learn of it
      await carol.say('still here?');
      await carol.outbox.flush(); // in bob's inbox after the notice

      await bob.inbox.drain();
      expect(bob.sink.texts, ['goodbye']);
      expect((await bob.group()).revision, 5);
    });

    test('a message sealed again under a new header is not the sender\'s: '
        'dropped, the key kept', () async {
      await everyoneAt4();
      await alice.say('real');
      await world.settle();
      final opened = _open(g, lastGroupEnvelope(bob));
      final forged = _rewrap(
        g,
        Gv2EnvelopeStamp(
          senderAccountId: opened.stamp.senderAccountId,
          senderDeviceId: opened.stamp.senderDeviceId,
          messageId: gv2NewMessageId(), // would be a new message
          revision: opened.stamp.revision,
          chain: opened.stamp.chain,
          timestampMs: opened.stamp.timestampMs,
        ),
        opened.body,
      );
      await world.deliver(bob, forged);
      await world.settle();
      expect(bob.sink.texts, ['real']);
      expect(await bob.queuedPairwise(), isEmpty);

      await alice.say('next');
      await world.settle();
      expect(bob.sink.texts, ['real', 'next']);
    });

    test('back after the server let its rows expire: what expired is gone, '
        'the missing key is asked for, and the next message is read', () async {
      await everyoneAt4();
      await alice.say('seen');
      await world.settle();
      // Bob is away past the retention: everything queued for anyone in
      // this window never arrives (the server swept it).
      world.swallow.addAll([0x01, gv2EnvelopeVersion]);
      await alice.db.gv2SenderKeyStore.keepOnly(g.id, {}, me: 'nobody');
      await alice.say('expired');
      await world.settle();
      world.swallow.clear();
      world.swallowed.clear();
      expect(bob.sink.texts, ['seen']);

      await alice.say('after');
      await world.settle();
      world.now += gv2KeyWaitShown.inMilliseconds;
      await world.settle();
      expect(bob.sink.texts, ['seen', 'after']);
      expect(carol.sink.texts.last, 'after');
    });

    test('a forged message far ahead on the sender\'s chain (anyone with the '
        'group key) moves nothing: dropped, no key asked for, the next real '
        'message is read', () async {
      await everyoneAt4();
      await alice.say('real');
      await world.settle();
      final opened = _open(g, lastGroupEnvelope(bob));
      final body = Uint8List.fromList(opened.body);
      // version(1) ‖ chainId(4) ‖ iteration(4) ‖ signature(64) ‖ ciphertext
      final view = ByteData.sublistView(body);
      expect(view.getUint32(5), 0); // alice's first message
      for (final jump in [20000, 0x7fffffff]) {
        view.setUint32(5, jump);
        await world.deliver(
          bob,
          _rewrap(
            g,
            Gv2EnvelopeStamp(
              senderAccountId: opened.stamp.senderAccountId,
              senderDeviceId: opened.stamp.senderDeviceId,
              messageId: gv2NewMessageId(),
              revision: opened.stamp.revision,
              chain: opened.stamp.chain,
              timestampMs: world.now,
            ),
            body,
          ),
        );
      }
      await world.settle();
      expect(bob.sink.texts, ['real']);
      expect(await bob.queuedPairwise(), isEmpty);
      expect(
        world.requests.where((r) => r.from == bob && !r.isGroup),
        isEmpty,
      );

      await alice.say('next');
      await world.settle();
      expect(bob.sink.texts, ['real', 'next']);
    });

    test('a message sealed again under the SAME header is not shown twice — '
        'also not after the first was deleted here', () async {
      await everyoneAt4();
      await alice.say('once');
      await world.settle();
      final opened = _open(g, lastGroupEnvelope(bob));
      // The app deleted the message; nothing of it is left but its id.
      bob.sink.messages.clear();
      await world.deliver(bob, _rewrap(g, opened.stamp, opened.body));
      await world.settle();
      expect(bob.sink.messages, isEmpty);
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });

    test('when the message store fails, nothing is committed: the message is '
        'read again and shown once', () async {
      await everyoneAt4();
      bob.sink.failNext = true;
      await alice.say('second try');
      await alice.outbox.flush();
      await bob.inbox.drain();
      expect(bob.sink.texts, isEmpty);
      final row = (await bob.db.gv2InboxStore.allRows()).single;
      expect(row.attempts, 1);
      await bob.inbox.drain();
      expect(bob.sink.texts, ['second try']);
      expect(
        (bob.sink.committedEvents.single as Gv2MessageStored)
            .message
            .localMessageId,
        bob.sink.messages.single.localMessageId,
      );
    });

    test('an unsend reaches only the unsender\'s own message', () async {
      await everyoneAt4();
      final fromAlice = await alice.say('alice wrote this');
      final fromBob = await bob.say('bob wrote this');
      await world.settle();

      // Bob names the message id of alice's message.
      await bob.messaging.send(g.id, Gv2UnsendContent(fromAlice.messageId));
      await world.settle();
      expect(dave.sink.unsentIds, hasLength(1));
      expect(dave.sink.unsentIds.single, isNot(fromAlice.localMessageId));

      await bob.messaging.send(g.id, Gv2UnsendContent(fromBob.messageId));
      await world.settle();
      expect(dave.sink.unsentIds.last, fromBob.localMessageId);
      // An unsend is a control message: silent.
      expect(world.groupRequests.last.entries.single.silent, isTrue);
    });

    test('a message that arrives after its unsend is never shown', () async {
      await everyoneAt4();
      await alice.say('warm up');
      await world.settle();
      world.swallow.add(gv2EnvelopeVersion);
      final late = await alice.say('taken back');
      await alice.outbox.flush();
      world.swallow.clear();
      final delayed = world.swallowed.firstWhere((d) => d.to == bob).envelope;

      await alice.messaging.send(g.id, Gv2UnsendContent(late.messageId));
      await world.settle();
      expect(bob.sink.unsentIds, [late.localMessageId]);

      // Now the message itself arrives.
      await world.deliver(bob, delayed);
      await world.settle();
      expect(bob.sink.texts, ['warm up']);
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });

    test('clearing the history is honoured from an owner or admin only, and '
        'never beyond the time it was said', () async {
      await everyoneAt4();
      await dave.messaging.send(g.id, Gv2ClearHistoryContent(world.now));
      await world.settle();
      expect(bob.sink.cleared, isEmpty);

      final farFuture = world.now + 365 * 86400 * 1000;
      final queued = await alice.messaging.send(
        g.id,
        Gv2ClearHistoryContent(farFuture),
      );
      await world.settle();
      expect(bob.sink.cleared.single, (queued.timestampMs, alice.snowId));

      world.served = 6; // bob becomes an admin
      for (final d in [alice, bob, dave]) {
        await d.inbox.requestSync(g.id);
      }
      await bob.messaging.send(g.id, Gv2ClearHistoryContent(5));
      await world.settle();
      expect(dave.sink.cleared.last, (5, bob.snowId));
    });

    test(
      'a content type this build does not know is used up and not shown',
      () async {
        await everyoneAt4();
        await alice.say('warm up');
        await world.settle();
        // Queue a plaintext of an unknown type the way send() would.
        await alice.db.gv2OutboxStore.enqueueContent(
          groupId: g.id,
          content: Gv2OutboxContent(
            messageId: gv2NewMessageId(),
            timestampMs: world.now,
            expiresIn: 0,
            silent: false,
            plaintext: Uint8List.fromList([gv2ContentVersion, 0x7f, 1, 2, 3]),
          ),
          nowMs: world.now,
        );
        await world.settle();
        expect(bob.sink.texts, ['warm up']);
        expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
        await alice.say('next');
        await world.settle();
        expect(bob.sink.texts, ['warm up', 'next']);
      },
    );

    test('this account\'s own copy is dropped unread — also when the key it '
        'was written with is gone', () async {
      await everyoneAt4();
      await bob.say('mine');
      await world.settle();
      final own = _open(g, lastGroupEnvelope(bob));
      expect(own.stamp.senderSnowId, bob.snowId);
      // A restore: bob's keys are gone, and an old copy of his own message
      // is still on its way to him.
      await bob.db.gv2SenderKeyStore.keepOnly(g.id, {}, me: 'nobody');
      await world.deliver(bob, _rewrap(g, own.stamp, own.body));
      await world.settle();
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
      expect(await bob.queuedPairwise(), isEmpty);
      expect(bob.sink.messages, isEmpty);
    });

    test('a frozen group handles nothing more', () async {
      await everyoneAt4();
      await alice.say('one');
      await world.settle();
      await bob.store.setHold(g.id, Gv2Hold.frozen, evidence: _utf8('{}'));
      await alice.say('two');
      await world.settle();
      expect(bob.sink.texts, ['one']);
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });

    test('while the log needs a newer app, messages wait instead of being '
        'judged by an unknown roster', () async {
      await everyoneAt4();
      await alice.say('one');
      await world.settle();
      await bob.store.setHold(g.id, Gv2Hold.updateRequired);
      await alice.say('two');
      await world.settle();
      expect(bob.sink.texts, ['one']);
      expect(
        (await bob.db.gv2InboxStore.allRows()).single.state,
        Gv2InboxState.waitingSync,
      );
      await bob.store.setHold(g.id, Gv2Hold.none);
      await world.settle();
      expect(bob.sink.texts, ['one', 'two']);
    });
  });

  group('notices', () {
    test(
      'a change notice makes members fetch the log, and nothing else',
      () async {
        await everyoneAt4();
        world.served = 5;
        await alice.inbox.requestSync(g.id);
        await alice.messaging.noticeChange(g.id);
        await world.settle();
        expect((await bob.group()).revision, 5);
        expect((await dave.group()).revision, 5);
        expect(bob.sink.messages, isEmpty);
        final notice = world.groupRequests.single.entries.single;
        expect(notice.silent, isTrue);
        // The same notice again does not make anyone look again.
        final runs = bob.sync.runs;
        await alice.messaging.noticeChange(g.id);
        await world.settle();
        expect(bob.sync.runs, runs);
      },
    );

    test('a notice goes out while this device is not confirmed yet', () async {
      await alice.install(4);
      await bob.install(4, membership: Gv2Membership.awaitingConfirm);
      await bob.messaging.noticeChange(g.id);
      await world.settle();
      expect(world.groupRequests.single.from, bob);
    });

    test('a change notice whose body is not its header\'s revision is '
        'dropped', () async {
      await everyoneAt4();
      world.served = 5;
      final body = Uint8List(4)..[3] = 9;
      final stamp = Gv2EnvelopeStamp(
        senderAccountId: alice.person.accountId,
        senderDeviceId: alice.party.deviceId,
        messageId: gv2NewMessageId(),
        revision: 8,
        chain: g.states[4].chain,
        timestampMs: world.now,
      );
      await world.deliver(
        bob,
        gv2SealEnvelope(
          keys: Gv2EnvelopeKeys.derive(g.masterKey, g.groupId),
          header: Gv2EnvelopeHeader(
            kind: gv2KindChangeNotice,
            stamp: stamp,
            bodyLength: 4,
          ),
          body: body,
        ),
      );
      await world.settle();
      expect(bob.sync.runs, 0);
      expect((await bob.group()).revision, 4);
    });

    test('member_reset: the members forget the key they gave, one of the '
        'picked members confirms the head, and the next message brings the '
        'key again', () async {
      await everyoneAt4();
      await alice.say('before');
      await world.settle();
      final chain = (await alice.chainId())!;
      final keys = alice.db.gv2SenderKeyStore;
      expect(await keys.delivered(g.id, bob.snowId, chain), isNotNull);

      // Bob restores: no keys, waiting for a confirmation.
      await bob.db.gv2SenderKeyStore.keepOnly(g.id, {}, me: 'nobody');
      await bob.store.setMembership(g.id, Gv2Membership.awaitingConfirm);
      await bob.messaging.announceReset(g.id);
      await bob.outbox.flush();
      expect(world.groupRequests.last.entries.single.silent, isTrue);
      await alice.inbox.drain();
      expect(await keys.delivered(g.id, bob.snowId, chain), isNull);
      expect(await keys.delivered(g.id, dave.snowId, chain), isNotNull);

      await world.settle();
      expect((await bob.group()).membership, Gv2Membership.active);

      await alice.say('after');
      await world.settle();
      expect(bob.sink.texts, ['before', 'after']);
    });

    test('a member notice is believed only with the member\'s signature, from '
        'this membership, and of a believable age', () async {
      await everyoneAt4();
      await alice.say('x');
      await world.settle();
      final chain = (await alice.chainId())!;
      final keys = alice.db.gv2SenderKeyStore;
      final envKeys = Gv2EnvelopeKeys.derive(g.masterKey, g.groupId);
      Gv2EnvelopeStamp stamp({int? revision, int? at}) => Gv2EnvelopeStamp(
        senderAccountId: bob.person.accountId,
        senderDeviceId: bob.party.deviceId,
        messageId: gv2NewMessageId(),
        revision: revision ?? 4,
        chain: g.states[revision ?? 4].chain,
        timestampMs: at ?? world.now,
      );
      Future<bool> forgotten(Uint8List envelope) async {
        await world.deliver(alice, envelope);
        await alice.inbox.drain();
        return await keys.delivered(g.id, bob.snowId, chain) == null;
      }

      Uint8List reset(Gv2SigningKey key, Gv2EnvelopeStamp s) =>
          gv2SealMemberNoticeEnvelope(
            keys: envKeys,
            stamp: s,
            memberKey: key,
            payload: gv2NoticeMemberReset,
          );

      // Signed with another member's key.
      expect(await forgotten(reset(dave.person.memberKey, stamp())), isFalse);
      // From before bob joined (r1).
      expect(
        await forgotten(reset(bob.person.memberKey, stamp(revision: 0))),
        isFalse,
      );
      // Older than the digests of handled envelopes are kept.
      expect(
        await forgotten(
          reset(
            bob.person.memberKey,
            stamp(at: world.now - gv2InboxRetention.inMilliseconds - 60000),
          ),
        ),
        isFalse,
      );
      // From the future.
      expect(
        await forgotten(
          reset(bob.person.memberKey, stamp(at: world.now + 2 * 86400 * 1000)),
        ),
        isFalse,
      );
      // An unknown notice does nothing.
      expect(
        await forgotten(
          gv2SealMemberNoticeEnvelope(
            keys: envKeys,
            stamp: stamp(),
            memberKey: bob.person.memberKey,
            payload: Uint8List.fromList([0x7f]),
          ),
        ),
        isFalse,
      );
      // The real one.
      expect(await forgotten(reset(bob.person.memberKey, stamp())), isTrue);
    });

    test('the same notice sealed again acts once; resets without end drop the '
        'sessions at most once in ten minutes', () async {
      await everyoneAt4();
      await alice.say('x');
      await world.settle();
      final envKeys = Gv2EnvelopeKeys.derive(g.masterKey, g.groupId);
      Uint8List reset(Gv2EnvelopeStamp s) => gv2SealMemberNoticeEnvelope(
            keys: envKeys,
            stamp: s,
            memberKey: bob.person.memberKey,
            payload: gv2NoticeMemberReset,
          );
      Gv2EnvelopeStamp stamp() => Gv2EnvelopeStamp(
            senderAccountId: bob.person.accountId,
            senderDeviceId: bob.party.deviceId,
            messageId: gv2NewMessageId(),
            revision: 4,
            chain: g.states[4].chain,
            timestampMs: world.now,
          );
      final forgotten = alice.crypto.forgotten;

      final s = stamp();
      final first = reset(s);
      final again = reset(s); // a new nonce: new bytes, the same signed notice
      expect(_same(first, again), isFalse);
      await world.deliver(alice, first);
      await alice.inbox.drain();
      expect(forgotten.where((p) => p == bob.snowId), hasLength(1));
      await world.deliver(alice, again);
      await alice.inbox.drain();
      expect(forgotten.where((p) => p == bob.snowId), hasLength(1),
          reason: 'the same notice once');

      // A fresh notice (a new id) within ten minutes: not again...
      await world.deliver(alice, reset(stamp()));
      await alice.inbox.drain();
      expect(forgotten.where((p) => p == bob.snowId), hasLength(1));
      // After them the first notice, sealed once more, still acts no more
      // (the id, not the time)...
      world.now += gv2NoticeEvery.inMilliseconds + 1;
      await world.deliver(alice, reset(s));
      await alice.inbox.drain();
      expect(forgotten.where((p) => p == bob.snowId), hasLength(1),
          reason: 'the same notice, later');
      // ...and a fresh one does.
      await world.deliver(alice, reset(stamp()));
      await alice.inbox.drain();
      expect(forgotten.where((p) => p == bob.snowId), hasLength(2));
    });
  });

  group('the sender\'s place in the log', () {
    test('a sender behind this device is read and told so, with this '
        'device\'s signed head', () async {
      await alice.install(4);
      await bob.install(4);
      await dave.install(4);
      world.served = 6;
      await bob.inbox.requestSync(g.id);
      dave.sync.offline = true;
      await alice.say('from behind'); // alice is at r4
      await alice.outbox.flush();
      await bob.inbox.drain();
      expect(bob.sink.texts, ['from behind']);
      expect(await bob.queuedPairwise(), [gv2PairwiseTypeBehind]);
      await world.settle();
      expect((await alice.group()).revision, 6);
    });

    test('a sender ahead of this device: the log is fetched, then the message '
        'is read', () async {
      await alice.install(4);
      await bob.install(4);
      await dave.install(4);
      world.served = 6;
      await alice.inbox.requestSync(g.id);
      await alice.say('from ahead');
      await world.settle();
      expect((await bob.group()).revision, 6);
      expect(bob.sink.texts, ['from ahead']);
      expect(bob.sync.runs, 1);
      expect(await bob.queuedPairwise(), isEmpty);
    });

    test('a member who claims a far-future place on every envelope costs one '
        'sync per floor and one head request per notice period, and the '
        'others are still read in order', () async {
      await everyoneAt4();
      final envKeys = Gv2EnvelopeKeys.derive(g.masterKey, g.groupId);
      await dave.say('d-first');
      await world.settle();
      final start = world.now;
      final syncsBefore = alice.sync.runs;
      final toBobBefore = world.requests
          .where((r) => r.from == alice && !r.isGroup)
          .length;

      final said = <String>[];
      for (var i = 0; i < 30; i++) {
        // Signed by bob's real member key: the claim is authenticated, only
        // its content is a lie.
        await world.deliver(
          alice,
          gv2SealMemberNoticeEnvelope(
            keys: envKeys,
            stamp: Gv2EnvelopeStamp(
              senderAccountId: bob.person.accountId,
              senderDeviceId: bob.party.deviceId,
              messageId: gv2NewMessageId(),
              revision: 999,
              chain: Uint8List(32)..[0] = i + 1,
              timestampMs: world.now,
            ),
            memberKey: bob.person.memberKey,
            payload: Uint8List.fromList([0x7f]),
          ),
        );
        if (i % 3 == 0) {
          said.add('d$i');
          await dave.say('d$i');
        }
        await world.settle();
        world.now += 1000;
      }

      expect(alice.sink.texts, ['d-first', ...said]);
      expect((await alice.group()).revision, 4);
      expect((await alice.group()).hold, Gv2Hold.none);
      final seconds = (world.now - start) ~/ 1000;
      expect(
        alice.sync.runs - syncsBefore,
        lessThanOrEqualTo(seconds ~/ gv2SyncFloor.inSeconds + 2),
      );
      // The only direct traffic alice sends here is asking bob for his head.
      final toBob = world.requests
          .where((r) => r.from == alice && !r.isGroup)
          .length;
      expect(toBob - toBobBefore, 1);
      expect(await alice.db.gv2InboxStore.allRows(), isEmpty);
    });

    test(
      'while the log cannot be fetched, a message from ahead waits',
      () async {
        await alice.install(4);
        await bob.install(4);
        await dave.install(4);
        world.served = 6;
        await alice.inbox.requestSync(g.id);
        bob.sync.offline = true;
        await alice.say('from ahead');
        await world.settle();
        expect(bob.sink.texts, isEmpty);
        expect(
          (await bob.db.gv2InboxStore.allRows()).single.state,
          Gv2InboxState.waitingSync,
        );
        expect(await bob.queuedPairwise(), isEmpty);
        bob.sync.offline = false;
        await world.settle();
        expect(bob.sink.texts, ['from ahead']);
      },
    );

    test('the server withholds changes: the message is read, the sender\'s '
        'signed head puts the group on hold, nothing is sent, and a sync '
        'that reaches the head releases it', () async {
      await alice.install(4);
      await bob.install(4);
      await dave.install(4);
      world.served = 5; // carol was removed...
      bob.sync.limit = 4; // ...and the server does not show bob
      await alice.inbox.requestSync(g.id);
      await alice.say('carol is out');
      await world.settle();

      expect(bob.sink.texts, ['carol is out']);
      var row = await bob.group();
      expect(row.revision, 4);
      expect(row.hold, Gv2Hold.withheld);
      final evidence = jsonDecode(utf8.decode(row.holdEvidence!)) as Map;
      expect(evidence['kind'], 'withheld');
      expect((evidence['served'] as Map)['revision'], 5);
      // The syncs of one group keep their distance.
      expect(bob.sleeps, isNotEmpty);
      expect(
        bob.sleeps.every((d) => d <= gv2SyncFloor && d > Duration.zero),
        isTrue,
      );

      // Bob does not know the roster: no message, no key.
      world.requests.clear();
      await bob.say('to whom?');
      await world.settle();
      expect(world.requests.where((r) => r.from == bob), isEmpty);
      expect(await bob.chainId(), isNull);

      // The server serves the log again.
      bob.sync.limit = null;
      world.now += 61 * 1000;
      await world.settle();
      row = await bob.group();
      expect(row.revision, 5);
      expect(row.hold, Gv2Hold.none);
      expect(row.holdEvidence, isNull);
      expect(alice.sink.texts, ['to whom?']);
      expect(carol.sink.texts, isEmpty);
    });

    test('a head proof nobody signed, or one this device has reached, changes '
        'nothing', () async {
      await alice.install(4);
      await bob.install(4);
      final unsigned = Gv2SignedHead(
        revision: 9,
        chain: gv2TestSha('no such chain'),
        headSig: Uint8List(64),
      );
      Future<void> prove(Gv2SignedHead head) async {
        final sealed = await alice.crypto.seal(
          bob.snowId,
          Gv2PairwiseMessage(
            groupId: g.groupId,
            sender: alice.person.accountId,
            recipient: bob.person.accountId,
            body: Gv2HeadProofBody(head),
          ).encode(),
        );
        await world.deliver(bob, sealed);
        await world.settle();
      }

      await prove(unsigned);
      expect((await bob.group()).hold, Gv2Hold.none);
      expect(bob.sync.runs, 0);
      await prove(
        Gv2SignedHead(
          revision: 4,
          chain: g.states[4].chain,
          headSig: g.headSig(4),
        ),
      );
      expect((await bob.group()).hold, Gv2Hold.none);
    });

    test('a signed head beyond this device while it cannot sync proves '
        'nothing yet', () async {
      await alice.install(4);
      await bob.install(4);
      world.served = 5;
      bob.sync.offline = true;
      final sealed = await alice.crypto.seal(
        bob.snowId,
        Gv2PairwiseMessage(
          groupId: g.groupId,
          sender: alice.person.accountId,
          recipient: bob.person.accountId,
          body: Gv2HeadProofBody(
            Gv2SignedHead(
              revision: 5,
              chain: g.states[5].chain,
              headSig: g.headSig(5),
            ),
          ),
        ).encode(),
      );
      await world.deliver(bob, sealed);
      await world.settle();
      expect((await bob.group()).hold, Gv2Hold.none);
      bob.sync.offline = false;
      await world.settle();
      expect((await bob.group()).revision, 5);
      expect((await bob.group()).hold, Gv2Hold.none);
    });

    group('another chain at the same revision', () {
      late Gv2TestGroup fork;

      setUp(() {
        // The same group, another history from r3 on.
        fork = g.forkAt(2)..invite(g.person('alice'), g.person('eve'));
        expect(fork.id, g.id);
        expect(_same(fork.states[2].chain, g.states[2].chain), isTrue);
        expect(_same(fork.states[3].chain, g.states[3].chain), isFalse);
      });

      test('the message is read, the sender is asked for its signed head, and '
          'two heads signed by the server freeze the group', () async {
        await alice.install(3);
        await bob.install(3); // r3 with the server's signature
        await carol.install(3, of: fork);
        carol.sync.log = fork;
        world.served = 3;
        await carol.say('from the other log');
        await carol.outbox.flush();
        await bob.inbox.drain();
        expect(bob.sink.texts, ['from the other log']);
        expect(await bob.queuedPairwise(), [gv2PairwiseTypeHeadRequest]);
        expect((await bob.group()).hold, Gv2Hold.none); // a claim alone

        await world.settle();
        final row = await bob.group();
        expect(row.hold, Gv2Hold.frozen);
        final evidence = jsonDecode(utf8.decode(row.holdEvidence!)) as Map;
        expect(evidence['kind'], 'two_heads');
        expect(
          base64Decode((evidence['held'] as Map)['chain'] as String),
          g.states[3].chain,
        );
        expect(
          base64Decode((evidence['served'] as Map)['chain'] as String),
          fork.states[3].chain,
        );
      });

      test('a point passed inside a batch is covered by the signed anchor '
          'above it: the other chain freezes', () async {
        await alice.install(4);
        await bob.install(2);
        world.served = 4;
        await bob.inbox.requestSync(g.id); // r3 passed without a signature
        expect((await bob.store.head(g.id, 3))!.headSig, isNull);
        await carol.install(3, of: fork);
        carol.sync.log = fork;
        carol.sync.offline = true;
        await carol.say('from the other log');
        await world.settle();
        expect(bob.sink.texts, ['from the other log']);
        final row = await bob.group();
        expect(row.hold, Gv2Hold.frozen);
        final evidence = jsonDecode(utf8.decode(row.holdEvidence!)) as Map;
        expect(evidence['kind'], 'two_heads');
        expect((evidence['held'] as Map)['revision'], 3);
        expect((evidence['held'] as Map)['headSig'], isNull);
        expect((evidence['cover'] as Map)['revision'], 4);
      });
    });
  });

  group('after a sync', () {
    test('what belonged to a member who is gone is erased: its key, and the '
        'record of the key it was given', () async {
      await everyoneAt4();
      await alice.say('a');
      await carol.say('c');
      await world.settle();
      final keys = bob.db.gv2SenderKeyStore;
      await bob.say('b');
      await world.settle();
      final chain = (await bob.chainId())!;
      expect(await keys.delivered(g.id, carol.snowId, chain), isNotNull);

      world.served = 5;
      await bob.inbox.requestSync(g.id);
      expect(await keys.delivered(g.id, carol.snowId, chain), isNull);
      expect(await keys.delivered(g.id, alice.snowId, chain), isNotNull);
      expect(
        (await keys.manager(
          g.id,
          carol.snowId,
        )).hasSenderKey(g.id, carol.snowId),
        isFalse,
      );
      expect(
        (await keys.manager(
          g.id,
          alice.snowId,
        )).hasSenderKey(g.id, alice.snowId),
        isTrue,
      );
      expect(await keys.ownCurrent(g.id, bob.snowId), isNotNull);
      expect(bob.sink.changes.single.last.revision, 5);
    });

    test('syncs of one group are at least five seconds apart', () async {
      await everyoneAt4();
      await bob.inbox.requestSync(g.id);
      expect(bob.sleeps, isEmpty);
      await bob.inbox.requestSync(g.id);
      expect(bob.sleeps.single, gv2SyncFloor);
      world.now += gv2SyncFloor.inMilliseconds;
      await bob.inbox.requestSync(g.id);
      expect(bob.sleeps, hasLength(1));
    });

    test('a member who joined is confirmed the head by the picked members, '
        'and can then write', () async {
      await alice.install(3);
      await bob.install(3);
      await carol.install(3);
      await dave.install(4, membership: Gv2Membership.awaitingConfirm);
      await dave.say('I am in');
      await dave.messaging.noticeChange(g.id);
      await world.settle();
      expect((await dave.group()).membership, Gv2Membership.active);
      world.now += 61 * 1000;
      await world.settle();
      expect(alice.sink.texts, ['I am in']);
      expect(bob.sink.texts, ['I am in']);
    });
  });
}
