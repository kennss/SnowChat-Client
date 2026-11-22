/// @file        gv2_pairwise_service_test.dart
/// @description Group protocol v2 pairwise messages end to end: real 1:1
///              Signal sessions (X3DH + Double Ratchet with Identity Binding),
///              real sealed sender envelopes and certificates, the real
///              inbox, outbox and stores of each device, and a stand-in
///              server that checks send tokens and hands envelopes to the
///              recipient's inbox. Covers Sender Keys given from the current
///              position, key requests answered with the key given before,
///              head confirmations (including ones ahead of the device and
///              ones that contradict it), behind notices, every binding a
///              message must satisfy, replays, a failure after decrypting,
///              a broken session, and what the outbox sends and holds back.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-22 (SC-18: Gv2OutboxSend takes the entries only; SealedSenderService takes trustedServerKeys). Earlier 2026-11-21 (P5.6: key requests spaced by the wait; P5.6: a failed sync keeps rows waiting — the stand-in sync marks the group synced only when it does not fail). Earlier 2026-11-21 (head confirmers: max(3, ⌈√N⌉) and the inviter; advanceTo names inviters like the sync). Earlier 2026-11-20 (a point held without a signature is covered by the signed anchor)
///
/// @functions
///  - main(): the test groups below.
///  - _World: the stand-in server, the group's history and the devices.
///  - _Device: one account's database, inbox, outbox, sessions and service.
///  - Gv2TestSessions: Gv2SignalSessions over a test party's SignalProtocolService.
///
/// Notes:
///  - The group's log is built from real signed entries (gv2_test_support);
///    each device's store is put at a revision of it directly, standing in
///    for a sync. Members are recorded as confirmed with their real
///    accounts.
///  - The test inbox handler also reads content envelopes with the device's
///    v4 Sender Keys (a small stand-in for P3.7c), to show that a message
///    waiting for a key wakes when the pairwise Sender Key arrives.
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/sealed_sender.dart';
import 'package:snowchat/core/crypto/sender_key.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_envelope.dart';
import 'package:snowchat/core/group_v2/gv2_inbox.dart';
import 'package:snowchat/core/group_v2/gv2_keys.dart';
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

typedef _OnSync = Future<void> Function(String groupId);

class _Handler implements Gv2InboxHandler {
  final _Device device;
  _Handler(this.device);

  _OnSync onSync = (_) async {};
  bool failNextPairwise = false;
  final List<String> read = [];
  final List<String> syncs = [];

  @override
  Future<Gv2InboxOutcome> handleGroupEnvelope(
    String groupId,
    Gv2OpenedEnvelope envelope,
    Gv2InboxItem item,
  ) async {
    final sender = envelope.stamp.senderSnowId;
    final keys = device.db.gv2SenderKeyStore;
    final manager = await keys.manager(groupId, sender);
    try {
      final plain = gv2OpenContent(
        groupId: gv2Unhex(groupId),
        envelope: envelope,
        senderKeys: manager,
      );
      return Gv2Handled(
        write: () async {
          read.add(utf8.decode(plain));
          await keys.save(groupId, sender, manager);
        },
      );
    } on SenderKeyException catch (e) {
      if (e.reason == SenderKeyFailure.noKey) {
        return Gv2WaitForKey(sender: sender);
      }
      return const Gv2Dropped();
    }
  }

  /// The types of the pairwise messages that reached the service, in order
  /// (read from what the service kept of them).
  final List<int> pairwiseTypes = [];

  @override
  Future<Gv2InboxOutcome> handleInvite(
    String senderSnowId,
    Uint8List invite,
  ) async =>
      throw StateError('no invites in this test');

  @override
  Future<Gv2InboxOutcome> handlePairwise(Gv2InboxItem item) async {
    final outcome = await device.service.handle(item);
    final kept = await device.db.gv2InboxStore.allRows();
    for (final row in kept) {
      // version(1) ‖ sender(36) ‖ message: the type is the message's byte 2.
      if (row.serverRowId == item.serverRowId &&
          row.unsealed &&
          !item.unsealed &&
          row.payload.length > 39) {
        pairwiseTypes.add(row.payload[39]);
      }
    }
    if (failNextPairwise) {
      failNextPairwise = false;
      throw StateError('the app died here');
    }
    return outcome;
  }

  /// A stand-in sync that reaches the server's head: what [onSync] does,
  /// then the group is marked synced as of the start (as Gv2Sync does).
  /// [failSyncs]: the sync fails (offline) — nothing is marked.
  @override
  Future<void> syncGroup(String groupId) async {
    final startedAtMs = device.world.now;
    syncs.add(groupId);
    await onSync(groupId);
    if (failSyncs) return;
    if (await device.store.group(groupId) != null) {
      await device.store.markSynced(groupId, startedAtMs);
    }
  }

  bool failSyncs = false;
}

class _Device {
  final _World world;
  final Gv2TestPerson person;
  final TestParty party;
  final SnowDatabase db;
  final Gv2TestSessions sessions;
  final Gv2TestCountingCrypto crypto;
  final Gv2TestTokens tokens = Gv2TestTokens();
  late final _Handler handler = _Handler(this);

  /// False: a new install that has not looked at its backup yet.
  bool groupsKnown = true;
  late final Gv2PairwiseService service;
  late final Gv2Inbox inbox;
  late final Gv2Outbox outbox;
  int queued = 0;

  _Device._(
    this.world,
    this.person,
    this.party,
    this.db,
    this.sessions,
    this.crypto,
  );

  String get snowId => person.snowId;
  Gv2Store get store => db.gv2Store;

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
      onQueued: () => d.queued++,
      nowMs: () => world.now,
      groupsKnown: () => d.groupsKnown,
    );
    d.inbox = Gv2Inbox(
      store: db.gv2InboxStore,
      groups: db.gv2Store,
      handler: d.handler,
      ack: (_) async {},
      nowMs: () => world.now,
    );
    d.outbox = Gv2Outbox(
      store: db.gv2OutboxStore,
      groups: db.gv2Store,
      keys: db.gv2SenderKeyStore,
      tokens: d.tokens,
      crypto: crypto,
      send: (entries) => world.send(d, entries),
      mySnowId: () async => person.snowId,
      myDeviceId: () async => party.deviceId,
      memberKey: (_) async => person.memberKey,
      giveKeys: (groupId) => d.service.giveKeys(groupId),
      prepareGroup: (_, {required sync}) async {},
      nowMs: () => world.now,
    );
    return d;
  }

  /// Put this device at [revision] of [g] with [membership]; every member is
  /// recorded as confirmed. [Gv2Membership.invited]: as an invitee (the
  /// state has this account pending).
  Future<void> install(
    Gv2TestGroup g,
    int revision, {
    Gv2Membership membership = Gv2Membership.active,
  }) async {
    final state = g.states[revision];
    final invited = membership == Gv2Membership.invited;
    expect(
      await store.insertAnchored(
        groupId: g.groupId,
        masterKey: g.masterKey,
        myCiphertext: g.person(person.name).ciphertext,
        protocolVersion: state.version,
        revision: revision,
        chain: state.chain,
        stateHash: gv2StateHash(state),
        membership: invited
            ? Gv2Membership.invited
            : Gv2Membership.awaitingConfirm,
        inviteSeed: invited ? gv2TestSha('invite ${person.name}') : null,
      ),
      isTrue,
    );
    await store.installState(state: state, headSig: g.headSig(revision));
    if (membership != Gv2Membership.awaitingConfirm && !invited) {
      await store.setMembership(g.id, membership);
    }
    await confirmAll(g);
    inbox.groupsChanged();
  }

  /// Move this device to [revision] of [g], as a sync would. [membership]:
  /// this account's standing afterwards, when it changes.
  Future<Gv2SyncResult> advanceTo(
    Gv2TestGroup g,
    int revision, {
    Gv2Membership? membership,
  }) async {
    final from = (await store.loadState(g.id))!;
    if (from.revision >= revision) {
      return Gv2SyncResult(
        Gv2SyncStatus.upToDate,
        fromRevision: from.revision,
        toRevision: from.revision,
      );
    }
    await store.advance(
      from: from,
      to: g.states[revision],
      headSig: g.headSig(revision),
      membership: membership,
      points: [
        for (var r = from.revision + 1; r <= revision; r++)
          Gv2LogPoint(r, g.states[r].chain),
      ],
    );
    await confirmAll(g);
    // As the sync does: the inviter of each ACCEPT, from the state before it.
    final invitedBy = <String, String>{};
    for (var r = from.revision + 1; r <= revision; r++) {
      final entry = g.log[r];
      if (entry.actions.any((a) => a is Gv2Accept)) {
        final joiner = gv2Hex(entry.actor);
        invitedBy[joiner] = gv2Hex(g.states[r - 1].pending[joiner]!.invitedBy);
      }
    }
    return Gv2SyncResult(
      Gv2SyncStatus.advanced,
      fromRevision: from.revision,
      toRevision: revision,
      applied: g.log.sublist(from.revision + 1, revision + 1),
      invitedBy: invitedBy,
    );
  }

  Future<void> confirmAll(Gv2TestGroup g) async {
    final rows = await store.memberRows(g.id);
    await store.saveMemberChecks(g.id, [
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

  Future<Gv2GroupRow> group(Gv2TestGroup g) async => (await store.group(g.id))!;

  /// Send what is queued, then let every device handle what it got.
  Future<void> flush() async {
    await outbox.flush();
    await world.drainAll();
  }

  /// Seal [message] for [to] on this device's session and hand it over
  /// directly, bypassing the outbox (for crafted messages).
  Future<Uint8List> sendRaw(_Device to, Gv2PairwiseMessage message) async {
    final sealed = await crypto.seal(to.snowId, message.encode());
    await world.deliver(to, sealed);
    return sealed;
  }
}

class _Request {
  final _Device from;
  final List<Gv2SendEntry> entries;
  const _Request(this.from, this.entries);
}

class _World implements Gv2TestDirectory {
  final ed.SigningKey serverKey = ed.SigningKey(
    seed: gv2TestSha('gv2 pairwise test — certificate server'),
  );
  late final Uint8List serverVerifyKey = Uint8List.fromList(
    serverKey.verifyKey.asTypedList,
  );

  final Gv2TestGroup group = Gv2TestGroup('pairwise');
  final Gv2TestGroup other = Gv2TestGroup('pairwise other');
  final Map<String, _Device> devices = {};
  final Map<String, int> _opk = {};
  final List<_Request> requests = [];
  int now = DateTime.now().millisecondsSinceEpoch;
  int _rows = 0;
  bool failSends = false;

  /// Accounts the server no longer knows.
  final Set<String> gone = {};

  static const names = ['alice', 'bob', 'carol', 'dave', 'eve'];

  Gv2TestPerson personOf(String ciphertext) {
    for (final g in [group, other]) {
      for (final name in names) {
        final p = g.person(name);
        if (p.key == ciphertext) return p;
      }
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

  /// The stand-in server: checks each entry's token against its recipients
  /// and queues the envelope for each of them.
  Future<List<Gv2SendResult>> send(
    _Device from,
    List<Gv2SendEntry> entries,
  ) async {
    if (failSends) throw const Gv2NetworkException();
    requests.add(_Request(from, entries));
    final results = <Gv2SendResult>[];
    for (final e in entries) {
      final targets = [
        for (final r in e.recipients)
          gone.contains('snow${gv2Hex(r)}')
              ? null
              : devices['snow${gv2Hex(r)}'],
      ];
      final groupId = utf8.decode(e.token).split('|').first;
      final g = groupId == group.id ? group : other;
      final expected = Gv2TestTokens.tokenFor(groupId, [
        for (final r in e.recipients) g.person(_nameOf(r)).key,
      ]);
      if (!_same(e.token, expected)) {
        results.add(_result(ok: false));
        continue;
      }
      if (targets.any((t) => t == null)) {
        results.add(_result(ok: true, unknown: e.recipients));
        continue;
      }
      for (final t in targets) {
        await deliver(t!, e.envelope);
      }
      results.add(_result(ok: true));
    }
    return results;
  }

  String _nameOf(Uint8List accountId) {
    for (final name in names) {
      if (_same(group.person(name).accountId, accountId)) return name;
    }
    throw StateError('unknown test account');
  }

  Future<void> deliver(_Device to, Uint8List envelope) async {
    _rows++;
    await to.inbox.receive([
      Gv2QueueRow(
        id: '00000000-0000-4000-8000-${_rows.toRadixString(16).padLeft(12, '0')}',
        seq: _rows,
        envelope: envelope,
      ),
    ]);
  }

  Future<void> drainAll() async {
    for (final d in devices.values) {
      await d.inbox.drain();
    }
  }

  static Gv2SendResult _result({
    required bool ok,
    List<Uint8List> unknown = const [],
  }) => Gv2SendResult(
    ok: ok,
    error: ok ? null : 'token',
    delivered: 1,
    unknownRecipients: unknown,
    throttledRecipients: 0,
    deleted: const [],
  );
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List _binding32(String label) => gv2TestSha('binding $label');

Gv2PairwiseMessage _msg(
  Gv2TestGroup g,
  _Device from,
  _Device to,
  Gv2PairwiseBody body, {
  Uint8List? groupId,
  Uint8List? sender,
  Uint8List? recipient,
}) => Gv2PairwiseMessage(
  groupId: groupId ?? g.groupId,
  sender: sender ?? from.person.accountId,
  recipient: recipient ?? to.person.accountId,
  body: body,
);

void main() {
  // Each device has its own in-memory database, on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late _World world;
  late Gv2TestGroup g;
  late _Device alice;
  late _Device bob;
  late _Device carol;

  setUp(() async {
    world = _World();
    g = world.group;
    final a = g.person('alice');
    final b = g.person('bob');
    final c = g.person('carol');
    g.create(a, invite: [b, c]); // r0
    g.accept(b); // r1
    g.accept(c); // r2
    g.change(a, const [Gv2SetTitle()], newTitle: 'later'); // r3
    alice = await world.add('alice');
    bob = await world.add('bob');
    carol = await world.add('carol');
  });

  tearDown(() async {
    for (final d in world.devices.values) {
      await d.db.close();
    }
  });

  group('Sender Keys', () {
    test('a key is given from its current position, and recorded', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      final aliceKeys = alice.db.gv2SenderKeyStore;
      final created = await aliceKeys.createOwn(g.id, alice.snowId);
      expect(created.iteration, 0);

      // One message before Bob has the key.
      var m = await aliceKeys.manager(g.id, alice.snowId);
      final early = m.encryptBoundGroupMessage(
        g.id,
        alice.snowId,
        utf8.encode('early'),
        _binding32('1'),
      );
      await aliceKeys.save(g.id, alice.snowId, m);

      expect(await alice.service.giveKey(g.id, bob.snowId), isTrue);
      expect(alice.queued, 1);
      await alice.flush();

      final given = await aliceKeys.delivered(
        g.id,
        bob.snowId,
        created.chainId,
      );
      expect(given!.iteration, 1);
      m = await aliceKeys.manager(g.id, alice.snowId);
      final later = m.encryptBoundGroupMessage(
        g.id,
        alice.snowId,
        utf8.encode('later'),
        _binding32('2'),
      );
      await aliceKeys.save(g.id, alice.snowId, m);

      final bobView = await bob.db.gv2SenderKeyStore.manager(
        g.id,
        alice.snowId,
      );
      expect(
        utf8.decode(
          bobView.decryptBoundGroupMessage(
            g.id,
            alice.snowId,
            later,
            _binding32('2'),
          ),
        ),
        'later',
      );
      expect(
        () => bobView.decryptBoundGroupMessage(
          g.id,
          alice.snowId,
          early,
          _binding32('1'),
        ),
        throwsA(
          isA<SenderKeyException>().having(
            (e) => e.reason,
            'reason',
            SenderKeyFailure.expired,
          ),
        ),
      );
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });

    test(
      'a message waiting for the key is read once the key arrives',
      () async {
        await alice.install(g, 2);
        await bob.install(g, 2);
        final aliceKeys = alice.db.gv2SenderKeyStore;
        await aliceKeys.createOwn(g.id, alice.snowId);
        // Bob gets the key first-delivered at position 0 (nothing sent yet).
        final m = await aliceKeys.manager(g.id, alice.snowId);
        final envelope = gv2SealContentEnvelope(
          keys: Gv2EnvelopeKeys.derive(g.masterKey, g.groupId),
          stamp: Gv2EnvelopeStamp(
            senderAccountId: alice.person.accountId,
            senderDeviceId: alice.party.deviceId,
            messageId: gv2NewMessageId(),
            revision: 2,
            chain: g.states[2].chain,
            timestampMs: world.now,
          ),
          senderKeys: m,
          plaintext: utf8.encode('hello'),
        );
        // The key Bob is given must cover this message: give it from before.
        final before = (await aliceKeys.ownCurrent(g.id, alice.snowId))!;
        await aliceKeys.save(g.id, alice.snowId, m);
        await alice.db.gv2SenderKeyStore.recordDelivery(
          g.id,
          bob.snowId,
          before,
          nowMs: world.now,
        );

        await world.deliver(bob, envelope);
        await bob.inbox.drain();
        final waiting = await bob.db.gv2InboxStore.allRows();
        expect(waiting.single.state, Gv2InboxState.waitingKey);
        expect(waiting.single.waitFor, alice.snowId);

        expect(await alice.service.giveKey(g.id, bob.snowId), isTrue);
        await alice.flush();
        expect(bob.handler.read, ['hello']);
        expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
      },
    );

    test('a key request is answered with the key given before', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      final aliceKeys = alice.db.gv2SenderKeyStore;
      final own = await aliceKeys.createOwn(g.id, alice.snowId);
      final m = await aliceKeys.manager(g.id, alice.snowId);
      m.encryptBoundGroupMessage(
        g.id,
        alice.snowId,
        Uint8List(1),
        _binding32('x'),
      );
      await aliceKeys.save(g.id, alice.snowId, m);
      expect(await alice.service.giveKey(g.id, bob.snowId), isTrue);
      await alice.flush();
      final first = await aliceKeys.delivered(g.id, bob.snowId, own.chainId);
      expect(first!.iteration, 1);

      // Alice's chain moves on; Bob asks again.
      final m2 = await aliceKeys.manager(g.id, alice.snowId);
      for (var i = 0; i < 3; i++) {
        m2.encryptBoundGroupMessage(
          g.id,
          alice.snowId,
          Uint8List(1),
          _binding32('y$i'),
        );
      }
      await aliceKeys.save(g.id, alice.snowId, m2);
      world.requests.clear();
      expect(
        await bob.service.requestKey(g.id, alice.snowId, own.chainId),
        isTrue,
      );
      await bob.flush(); // Bob → Alice (request); Alice queues the answer
      final answer = await alice.db.gv2OutboxStore.allRows();
      expect(answer, hasLength(1));
      final body =
          Gv2PairwiseMessage.decode(answer.single.payload)!.body
              as Gv2SenderKeyBody;
      expect(
        body.encode(),
        first.encode(),
        reason: 'the same key, not a later one',
      );
      await alice.flush();
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
    });

    test(
      'a member that never had the key gets it from the current position',
      () async {
        await alice.install(g, 2);
        await carol.install(g, 2);
        final aliceKeys = alice.db.gv2SenderKeyStore;
        final own = await aliceKeys.createOwn(g.id, alice.snowId);
        final m = await aliceKeys.manager(g.id, alice.snowId);
        m.encryptBoundGroupMessage(
          g.id,
          alice.snowId,
          Uint8List(1),
          _binding32('a'),
        );
        m.encryptBoundGroupMessage(
          g.id,
          alice.snowId,
          Uint8List(1),
          _binding32('b'),
        );
        await aliceKeys.save(g.id, alice.snowId, m);

        expect(
          await carol.service.requestKey(g.id, alice.snowId, own.chainId),
          isTrue,
        );
        await carol.flush();
        await alice.flush();
        final given = await aliceKeys.delivered(
          g.id,
          carol.snowId,
          own.chainId,
        );
        expect(given!.iteration, 2);
        final carolView = await carol.db.gv2SenderKeyStore.manager(
          g.id,
          alice.snowId,
        );
        expect(carolView.hasSenderKey(g.id, alice.snowId), isTrue);
      },
    );

    test(
      'a request for a chain never given and not current goes unanswered',
      () async {
        await alice.install(g, 2);
        await bob.install(g, 2);
        final own = await alice.db.gv2SenderKeyStore.createOwn(
          g.id,
          alice.snowId,
        );
        expect(
          await bob.service.requestKey(g.id, alice.snowId, own.chainId ^ 1),
          isTrue,
        );
        await bob.flush();
        expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
      },
    );

    test('a device whose head is not confirmed gives no key', () async {
      await alice.install(g, 2, membership: Gv2Membership.awaitingConfirm);
      await bob.install(g, 2);
      final own = await alice.db.gv2SenderKeyStore.createOwn(
        g.id,
        alice.snowId,
      );
      expect(await alice.service.giveKey(g.id, bob.snowId), isFalse);
      expect(
        await bob.service.requestKey(g.id, alice.snowId, own.chainId),
        isTrue,
      );
      await bob.flush();
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
    });

    test('key requests are rate limited per sender and per chain', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      expect(await bob.service.requestKey(g.id, alice.snowId, 7), isTrue);
      expect(await bob.service.requestKey(g.id, alice.snowId, 7), isFalse);
      expect(await bob.service.requestKey(g.id, alice.snowId, 8), isFalse);
      world.now += const Duration(minutes: 2).inMilliseconds;
      expect(await bob.service.requestKey(g.id, alice.snowId, 7), isFalse);
      expect(await bob.service.requestKey(g.id, alice.snowId, 8), isTrue);
      world.now += const Duration(minutes: 11).inMilliseconds;
      expect(await bob.service.requestKey(g.id, alice.snowId, 7), isTrue);
      // Only one pending request is kept per recipient: the latest.
      expect(await bob.db.gv2OutboxStore.allRows(), hasLength(1));
    });

    test('the longer a message has waited for its key, the rarer the '
        'request: half the wait between two', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      // The message arrived at t0; each ask says how long it has waited.
      final t0 = world.now;
      Future<bool> askAt(Duration at) async {
        world.now = t0 + at.inMilliseconds;
        final write = await bob.service.prepareRequestKey(
          g.id,
          alice.snowId,
          7,
          waited: at,
        );
        return write != null;
      }

      expect(await askAt(Duration.zero), isTrue);
      expect(await askAt(const Duration(minutes: 11)), isTrue);
      expect(await askAt(const Duration(hours: 10)), isTrue);
      // Asked at 10 h: the next once the wait is twice that.
      expect(await askAt(const Duration(hours: 19)), isFalse);
      expect(await askAt(const Duration(hours: 20, minutes: 1)), isTrue);
    });

    test('nobody asks itself or a non-member for a key', () async {
      await bob.install(g, 2);
      expect(await bob.service.requestKey(g.id, bob.snowId, 1), isFalse);
      final dave = await world.add('dave');
      expect(await bob.service.requestKey(g.id, dave.snowId, 1), isFalse);
      expect(await bob.service.giveKey(g.id, dave.snowId), isFalse);
    });
  });

  group('head confirmation', () {
    test(
      'a member that joined is confirmed by a picked member and becomes active',
      () async {
        await alice.install(g, 0);
        await bob.install(g, 1, membership: Gv2Membership.awaitingConfirm);
        final result = await alice.advanceTo(g, 1);
        // Two members: Alice is the only one who can confirm Bob.
        await alice.service.afterSync(g.id, result);
        expect(await alice.db.gv2OutboxStore.allRows(), hasLength(1));
        await alice.flush();
        expect((await bob.group(g)).membership, Gv2Membership.active);
      },
    );

    test('a confirmed head ahead of the device waits for the log, then is '
        'compared at its own revision', () async {
      await alice.install(g, 2);
      await bob.install(g, 1, membership: Gv2Membership.awaitingConfirm);
      bob.handler.onSync = (_) async {
        await bob.advanceTo(g, 3); // past the confirmed head
      };
      expect(await alice.service.confirmHead(g.id, bob.snowId), isTrue);
      await alice.flush();
      expect(bob.handler.syncs, [g.id]);
      expect((await bob.group(g)).revision, 3);
      expect((await bob.group(g)).membership, Gv2Membership.active);
    });

    test('a sync that fails keeps a confirmation ahead of the device; the '
        'next one that reaches the head lets it confirm', () async {
      await alice.install(g, 2);
      await bob.install(g, 1, membership: Gv2Membership.awaitingConfirm);
      bob.handler
        ..failSyncs = true
        ..onSync = (_) async {};
      expect(await alice.service.confirmHead(g.id, bob.snowId), isTrue);
      await alice.flush();
      expect(bob.handler.syncs, [g.id]);
      expect((await bob.db.gv2InboxStore.allRows()).single.state,
          Gv2InboxState.waitingSync, reason: 'not dropped');
      expect((await bob.group(g)).membership, Gv2Membership.awaitingConfirm);

      bob.handler
        ..failSyncs = false
        ..onSync = (_) async {
          await bob.advanceTo(g, 2);
        };
      await bob.inbox.drain();
      expect((await bob.group(g)).membership, Gv2Membership.active);
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });

    test('a head before this account\'s ACCEPT confirms nothing', () async {
      await alice.install(g, 2);
      // Bob was invited at r0 and accepted at r1: he holds the point r0,
      // which does not have his ACCEPT.
      await bob.install(g, 0, membership: Gv2Membership.invited);
      await bob.advanceTo(g, 1, membership: Gv2Membership.awaitingConfirm);
      expect((await bob.store.head(g.id, 0))!.chain, g.states[0].chain);
      await alice.sendRaw(
        bob,
        _msg(
          g,
          alice,
          bob,
          Gv2HeadConfirmBody(
            Gv2SignedHead(
              revision: 0,
              chain: g.states[0].chain,
              headSig: g.headSig(0),
            ),
          ),
        ),
      );
      await world.drainAll();
      expect((await bob.group(g)).membership, Gv2Membership.awaitingConfirm);
    });

    test('a head the server did not sign confirms nothing', () async {
      await alice.install(g, 1);
      await bob.install(g, 1, membership: Gv2Membership.awaitingConfirm);
      final forged = Gv2SigningKey.fromSeed(gv2TestSha('not the server'));
      await alice.sendRaw(
        bob,
        _msg(
          g,
          alice,
          bob,
          Gv2HeadConfirmBody(
            Gv2SignedHead(
              revision: 1,
              chain: g.states[1].chain,
              headSig: forged.sign(
                gv2HeadMessage(g.groupId, 1, g.states[1].chain),
              ),
            ),
          ),
        ),
      );
      await world.drainAll();
      expect((await bob.group(g)).membership, Gv2Membership.awaitingConfirm);
      expect((await bob.group(g)).hold, Gv2Hold.none);
    });

    test('a server-signed head with another chain at a revision whose signed '
        'head this device holds freezes the group', () async {
      await alice.install(g, 1);
      await bob.install(g, 1, membership: Gv2Membership.awaitingConfirm);
      final otherChain = gv2TestSha('another log');
      await alice.sendRaw(
        bob,
        _msg(
          g,
          alice,
          bob,
          Gv2HeadConfirmBody(
            Gv2SignedHead(
              revision: 1,
              chain: otherChain,
              headSig: g.headKey.sign(gv2HeadMessage(g.groupId, 1, otherChain)),
            ),
          ),
        ),
      );
      await world.drainAll();
      final row = await bob.group(g);
      expect(row.membership, Gv2Membership.awaitingConfirm);
      expect(row.hold, Gv2Hold.frozen);
      final evidence = jsonDecode(utf8.decode(row.holdEvidence!)) as Map;
      expect(evidence['kind'], 'two_heads');
      expect(evidence['source'], 'pairwise');
      expect((evidence['held'] as Map)['revision'], 1);
    });

    Future<void> confirmOtherChainAt2() async {
      final otherChain = gv2TestSha('another log');
      await alice.sendRaw(
        bob,
        _msg(
          g,
          alice,
          bob,
          Gv2HeadConfirmBody(
            Gv2SignedHead(
              revision: 2,
              chain: otherChain,
              headSig: g.headKey.sign(gv2HeadMessage(g.groupId, 2, otherChain)),
            ),
          ),
        ),
      );
      await world.drainAll();
    }

    test('the same at a point passed inside a batch (no signature of its '
        'own) freezes too: the signed anchor above it covers it', () async {
      await alice.install(g, 3);
      await bob.install(g, 1, membership: Gv2Membership.awaitingConfirm);
      await bob.advanceTo(g, 3); // r2 is held without a signature
      expect((await bob.store.head(g.id, 2))!.headSig, isNull);
      await confirmOtherChainAt2();
      final row = await bob.group(g);
      expect(row.membership, Gv2Membership.awaitingConfirm);
      expect(row.hold, Gv2Hold.frozen);
      final evidence = jsonDecode(utf8.decode(row.holdEvidence!)) as Map;
      expect(evidence['kind'], 'two_heads');
      final held = evidence['held'] as Map;
      expect(held['revision'], 2);
      expect(base64Decode(held['chain'] as String), g.states[2].chain);
      expect(held['headSig'], isNull);
      final cover = evidence['cover'] as Map;
      expect(cover['revision'], 3);
      expect(base64Decode(cover['chain'] as String), g.states[3].chain);
      expect(
        gv2VerifyHead(
          headPublicKey: g.headKey.publicKey,
          groupId: g.groupId,
          revision: 3,
          chain: g.states[3].chain,
          headSig: base64Decode(cover['headSig'] as String),
        ),
        isTrue,
      );
    });

    test('without a valid signature over the anchor either, nothing is '
        'proven and the message is only dropped', () async {
      await alice.install(g, 3);
      await bob.install(g, 1, membership: Gv2Membership.awaitingConfirm);
      await bob.advanceTo(g, 3);
      // An anchor signature that no longer verifies (as after the server's
      // log key was replaced).
      await (bob.db.update(bob.db.gv2Groups)
            ..where((r) => r.groupId.equals(g.id)))
          .write(Gv2GroupsCompanion(headSig: Value(Uint8List(64))));
      await confirmOtherChainAt2();
      final row = await bob.group(g);
      expect(row.membership, Gv2Membership.awaitingConfirm);
      expect(row.hold, Gv2Hold.none);
    });

    test('an active device ignores a confirmation', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      expect(await alice.service.confirmHead(g.id, bob.snowId), isTrue);
      await alice.flush();
      expect((await bob.group(g)).membership, Gv2Membership.active);
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });

    test('only an active device with a signed head vouches', () async {
      await alice.install(g, 2, membership: Gv2Membership.awaitingConfirm);
      await bob.install(g, 2, membership: Gv2Membership.awaitingConfirm);
      expect(await alice.service.confirmHead(g.id, bob.snowId), isFalse);
      final result = Gv2SyncResult(Gv2SyncStatus.advanced, applied: [g.log[1]]);
      await alice.service.afterSync(g.id, result);
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
    });

    test('the number of confirmers grows with the group: max(3, ⌈√N⌉)', () {
      final counts = {
        for (final n in [1, 2, 4, 9, 10, 16, 17, 255, 256, 257, 1024])
          n: gv2HeadConfirmerCount(n),
      };
      expect(counts, {
        1: 3, 2: 3, 4: 3, 9: 3, 10: 4, 16: 4, 17: 5, //
        255: 16, 256: 16, 257: 17, 1024: 32,
      });
      // 100 members (the joiner among them): ten others are picked.
      final members = [
        for (var i = 0; i < 100; i++) gv2Hex(gv2TestBytes('member $i', 65)),
      ];
      final picked = gv2HeadConfirmersFor(members[7], members);
      expect(picked, hasLength(10));
      expect(picked.toSet(), hasLength(10));
      expect(picked, isNot(contains(members[7])));
      // The joiner counts whether or not the caller passed it.
      expect(
        gv2HeadConfirmersFor(members[7], members.where((m) => m != members[7])),
        picked,
      );
    });

    test('the confirming members are the same three for everyone', () {
      final members = [
        for (var i = 0; i < 6; i++) gv2Hex(gv2TestBytes('member $i', 65)),
      ];
      final joiner = members[2];
      final picked = gv2HeadConfirmersFor(joiner, members);
      expect(picked, hasLength(3));
      expect(picked, isNot(contains(joiner)));
      expect(gv2HeadConfirmersFor(joiner, members.reversed), picked);
      expect(gv2HeadConfirmersFor(joiner, [joiner, members[0]]), [members[0]]);
      // Another joiner, another set (with these labels).
      expect(gv2HeadConfirmersFor(members[0], members), isNot(picked));
    });

    const fourOthers = ['alice', 'bob', 'carol', 'dave'];

    /// The members picked to confirm the head to eve in a group of alice,
    /// bob, carol, dave and eve (three of the four others).
    List<String> pickedForEve() {
      final keys = gv2HeadConfirmersFor(g.person('eve').key, [
        for (final n in fourOthers) g.person(n).key,
      ]);
      return [
        for (final n in fourOthers)
          if (keys.contains(g.person(n).key)) n,
      ];
    }

    /// Dave joins (alice invites); [inviterName] — made an admin first when
    /// it is not alice — invites eve, who accepts. Every other member syncs
    /// to the join; returns how many confirms each queued.
    Future<Map<String, int>> eveJoins(String inviterName) async {
      final a = g.person('alice');
      g.invite(a, g.person('dave'));
      g.accept(g.person('dave'));
      final inviter = g.person(inviterName);
      if (inviterName != 'alice') {
        g.change(a, [Gv2SetRole(inviter.ciphertext, gv2RoleAdmin)]);
      }
      g.invite(inviter, g.person('eve'));
      final invited = g.state.revision;
      g.accept(g.person('eve'));
      final joined = g.state.revision;
      final dave = await world.add('dave');
      final eve = await world.add('eve');
      final others = [alice, bob, carol, dave];
      for (final device in others) {
        await device.install(g, invited);
      }
      await eve.install(g, joined, membership: Gv2Membership.awaitingConfirm);
      final queued = <String, int>{};
      for (final device in others) {
        await device.service.afterSync(g.id, await device.advanceTo(g, joined));
        queued[device.person.name] =
            (await device.db.gv2OutboxStore.allRows()).length;
      }
      for (final device in others) {
        await device.flush();
      }
      expect((await eve.group(g)).membership, Gv2Membership.active);
      return queued;
    }

    test('a member neither picked nor the inviter does not confirm', () async {
      // Five members: eve gets three confirmers out of the other four; one
      // of the picked invites her, so the fourth queues nothing.
      final picked = pickedForEve();
      expect(picked, hasLength(3));
      final leftOut = fourOthers.firstWhere((n) => !picked.contains(n));
      final queued = await eveJoins(picked.first);
      expect(queued, {
        for (final n in fourOthers) n: n == leftOut ? 0 : 1,
      });
    });

    test('the member who invited the joiner confirms although not picked',
        () async {
      final picked = pickedForEve();
      final leftOut = fourOthers.firstWhere((n) => !picked.contains(n));
      final queued = await eveJoins(leftOut);
      // The three picked members, and the one who sent the invite.
      expect(queued, {for (final n in fourOthers) n: 1});
    });
  });

  group('behind', () {
    test('a device told it is behind catches up', () async {
      await alice.install(g, 3);
      await bob.install(g, 2);
      bob.handler.onSync = (_) async {
        await bob.advanceTo(g, 3);
      };
      expect(await alice.service.notifyBehind(g.id, bob.snowId), isTrue);
      expect(
        await alice.service.notifyBehind(g.id, bob.snowId),
        isFalse,
        reason: 'once per member and revision',
      );
      await alice.flush();
      expect(bob.handler.syncs, [g.id]);
      expect((await bob.group(g)).revision, 3);
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });

    test('a device that is not behind does not sync', () async {
      await alice.install(g, 2);
      await bob.install(g, 3);
      expect(await alice.service.notifyBehind(g.id, bob.snowId), isTrue);
      await alice.flush();
      expect(bob.handler.syncs, isEmpty);
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });
  });

  group('what a message must satisfy', () {
    Future<void> expectDropped(_Device to) async {
      await world.drainAll();
      expect(await to.db.gv2InboxStore.allRows(), isEmpty);
      final m = await to.db.gv2SenderKeyStore.manager(g.id, alice.snowId);
      expect(m.hasSenderKey(g.id, alice.snowId), isFalse);
    }

    Gv2SenderKeyBody key() => Gv2SenderKeyBody(
      chainId: 5,
      iteration: 0,
      chainKey: gv2TestSha('ck'),
      signingKey: g.person('alice').memberKey.publicKey,
    );

    test('the right message installs the key (control)', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      await alice.sendRaw(bob, _msg(g, alice, bob, key()));
      await world.drainAll();
      final m = await bob.db.gv2SenderKeyStore.manager(g.id, alice.snowId);
      expect(m.hasSenderKey(g.id, alice.snowId), isTrue);
    });

    test('it names another recipient', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      await alice.sendRaw(
        bob,
        _msg(g, alice, bob, key(), recipient: carol.person.accountId),
      );
      await expectDropped(bob);
    });

    test('it names another sender than the certificate', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      await alice.sendRaw(
        bob,
        _msg(g, alice, bob, key(), sender: carol.person.accountId),
      );
      await expectDropped(bob);
      final m = await bob.db.gv2SenderKeyStore.manager(g.id, carol.snowId);
      expect(m.hasSenderKey(g.id, carol.snowId), isFalse);
    });

    test('it names a group this device does not hold', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      await alice.sendRaw(
        bob,
        _msg(g, alice, bob, key(), groupId: gv2TestSha('nowhere')),
      );
      await expectDropped(bob);
    });

    test('its sender is not a member of the group it names', () async {
      final o = world.other;
      o.create(o.person('bob'), invite: [o.person('carol')]);
      o.accept(o.person('carol'));
      await alice.install(g, 2);
      await bob.install(g, 2);
      await bob.install(o, 1);
      await alice.sendRaw(bob, _msg(o, alice, bob, key()));
      await world.drainAll();
      // Waited for one sync of that group, then dropped.
      expect(bob.handler.syncs, [o.id]);
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
      final m = await bob.db.gv2SenderKeyStore.manager(o.id, alice.snowId);
      expect(m.hasSenderKey(o.id, alice.snowId), isFalse);
    });

    test(
      'its sender joined after this device\'s view: wait for the log',
      () async {
        await alice.install(g, 2);
        await carol.install(g, 2);
        await bob.install(g, 1); // Carol is not a member yet at r1
        bob.handler.onSync = (_) async {
          await bob.advanceTo(g, 2);
        };
        await carol.sendRaw(
          bob,
          _msg(
            g,
            carol,
            bob,
            Gv2SenderKeyBody(
              chainId: 9,
              iteration: 0,
              chainKey: gv2TestSha('carol ck'),
              signingKey: g.person('carol').memberKey.publicKey,
            ),
          ),
        );
        await world.drainAll();
        final m = await bob.db.gv2SenderKeyStore.manager(g.id, carol.snowId);
        expect(m.hasSenderKey(g.id, carol.snowId), isTrue);
      },
    );

    test('its sender joined later and the sync fails: the key waits for a '
        'sync that reaches the head (it is not dropped)', () async {
      await alice.install(g, 2);
      await carol.install(g, 2);
      await bob.install(g, 1);
      bob.handler
        ..failSyncs = true
        ..onSync = (_) async {};
      await carol.sendRaw(
        bob,
        _msg(
          g,
          carol,
          bob,
          Gv2SenderKeyBody(
            chainId: 9,
            iteration: 0,
            chainKey: gv2TestSha('carol ck'),
            signingKey: g.person('carol').memberKey.publicKey,
          ),
        ),
      );
      await world.drainAll();
      expect((await bob.db.gv2InboxStore.allRows()).single.state,
          Gv2InboxState.waitingSync);

      bob.handler
        ..failSyncs = false
        ..onSync = (_) async {
          await bob.advanceTo(g, 2);
        };
      await bob.inbox.drain();
      final m = await bob.db.gv2SenderKeyStore.manager(g.id, carol.snowId);
      expect(m.hasSenderKey(g.id, carol.snowId), isTrue);
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });

    test('it is not a pairwise message', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      final sealed = await alice.crypto.seal(
        bob.snowId,
        utf8.encode('{"type":"text"}'),
      );
      await world.deliver(bob, sealed);
      await expectDropped(bob);
    });

    test('a group the backup is about to bring back: the key waits for it '
        'and is installed when it is there', () async {
      await alice.install(g, 2);
      bob.groupsKnown = false; // a new install, its backup not looked at
      await alice.sendRaw(bob, _msg(g, alice, bob, key()));
      await world.drainAll();
      expect((await bob.db.gv2InboxStore.allRows()).single.state,
          Gv2InboxState.waitingSync, reason: 'kept, not dropped');

      bob.groupsKnown = true;
      await bob.install(g, 2);
      await bob.inbox.synced(g.id);
      final m = await bob.db.gv2SenderKeyStore.manager(g.id, alice.snowId);
      expect(m.hasSenderKey(g.id, alice.snowId), isTrue);
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });

    test('a frozen group takes nothing', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      await bob.store.setHold(g.id, Gv2Hold.frozen);
      await alice.sendRaw(bob, _msg(g, alice, bob, key()));
      await expectDropped(bob);
    });

    test('a replay is not handled again, even under a new row id', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      final sealed = await alice.sendRaw(bob, _msg(g, alice, bob, key()));
      await world.drainAll();
      expect(bob.crypto.opens, 1);
      await world.deliver(bob, sealed);
      await world.drainAll();
      expect(bob.crypto.opens, 1);
      expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
    });

    test('an envelope sealed for someone else does not open', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      await carol.install(g, 2);
      final forCarol = await alice.crypto.seal(
        carol.snowId,
        _msg(g, alice, carol, key()).encode(),
      );
      await world.deliver(bob, forCarol);
      await expectDropped(bob);
      expect(bob.sessions.resets, 0, reason: 'nothing certified to reset over');
    });
  });

  group('one decryption per envelope', () {
    test(
      'a failure after decrypting retries from the kept plaintext',
      () async {
        await alice.install(g, 2);
        await bob.install(g, 2);
        bob.handler.failNextPairwise = true;
        await alice.sendRaw(
          bob,
          _msg(
            g,
            alice,
            bob,
            Gv2SenderKeyBody(
              chainId: 5,
              iteration: 0,
              chainKey: gv2TestSha('ck'),
              signingKey: g.person('alice').memberKey.publicKey,
            ),
          ),
        );
        await world.drainAll();
        final kept = (await bob.db.gv2InboxStore.allRows()).single;
        expect(kept.unsealed, isTrue);
        expect(kept.attempts, 1);
        await bob.inbox.drain();
        expect(bob.crypto.opens, 1, reason: 'opened once, handled twice');
        final m = await bob.db.gv2SenderKeyStore.manager(g.id, alice.snowId);
        expect(m.hasSenderKey(g.id, alice.snowId), isTrue);
        expect(await bob.db.gv2InboxStore.allRows(), isEmpty);
      },
    );

    test(
      'a broken session is reset and the peer is told through the group',
      () async {
        await alice.install(g, 2);
        await bob.install(g, 2);
        await alice.db.gv2SenderKeyStore.createOwn(g.id, alice.snowId);
        await bob.db.gv2SenderKeyStore.createOwn(g.id, bob.snowId);
        expect(await alice.service.giveKey(g.id, bob.snowId), isTrue);
        await alice.flush();

        // Bob loses his sessions; Alice's next message cannot be read.
        bob.party.signal.clearAllSessions();
        world.now += const Duration(minutes: 20).inMilliseconds;
        expect(await alice.service.requestKey(g.id, bob.snowId, 1), isTrue);
        await alice.flush();
        final reset = (await bob.db.gv2OutboxStore.allRows()).single;
        expect(reset.payload[2], gv2PairwiseTypeSessionReset);

        await bob.flush();
        expect(bob.sessions.resets, 1);
        expect(await alice.db.gv2InboxStore.allRows(), isEmpty);

        // The new session carries messages both ways.
        world.now += const Duration(minutes: 2).inMilliseconds;
        final bobKey = (await bob.db.gv2SenderKeyStore.ownCurrent(
          g.id,
          bob.snowId,
        ))!;
        expect(
          await alice.service.requestKey(g.id, bob.snowId, bobKey.chainId),
          isTrue,
        );
        await alice.flush();
        await bob.flush();
        final m = await alice.db.gv2SenderKeyStore.manager(g.id, bob.snowId);
        expect(m.hasSenderKey(g.id, bob.snowId), isTrue);
      },
    );

    test('a session is reset at most once in ten minutes per peer', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      await alice.service.notifyBehind(g.id, bob.snowId);
      await alice.flush();
      bob.party.signal.clearAllSessions();
      world.now += const Duration(minutes: 11).inMilliseconds;
      await alice.service.requestKey(g.id, bob.snowId, 1);
      await alice.flush();
      expect(await bob.db.gv2OutboxStore.allRows(), hasLength(1));
      await bob.db.gv2OutboxStore.remove(
        (await bob.db.gv2OutboxStore.allRows()).single.localId,
      );
      world.now += const Duration(minutes: 2).inMilliseconds;
      await alice.service.requestKey(g.id, bob.snowId, 2);
      await alice.flush();
      expect(await bob.db.gv2OutboxStore.allRows(), isEmpty);
    });
  });

  group('the outbox', () {
    test('every request carries one decoy to this account, sized like a real '
        'entry', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      await carol.install(g, 2);
      await alice.service.notifyBehind(g.id, bob.snowId);
      await alice.service.notifyBehind(g.id, carol.snowId);
      await alice.flush();
      final request = world.requests.single;
      expect(request.entries, hasLength(3));
      final toSelf = [
        for (final e in request.entries)
          if (_same(e.recipients.single, alice.person.accountId)) e,
      ];
      expect(toSelf, hasLength(1));
      final decoy = toSelf.single;
      final real = request.entries.where((e) => e != decoy).toList();
      expect(
        real.map((e) => e.envelope.length),
        contains(decoy.envelope.length),
      );
      expect(decoy.envelope[0], 0x01);
      expect(request.entries.every((e) => e.silent), isTrue);
      // The decoy reaches Alice's own inbox and goes nowhere.
      expect(await alice.db.gv2InboxStore.allRows(), isEmpty);
      expect(alice.sessions.resets, 0);
    });

    test('a recipient who is no longer a member: the row is dropped', () async {
      await alice.install(g, 2);
      await alice.db.gv2OutboxStore.enqueuePairwise(
        groupId: g.id,
        message: Gv2PairwiseMessage(
          groupId: g.groupId,
          sender: alice.person.accountId,
          recipient: g.person('dave').accountId,
          body: const Gv2SessionResetBody(),
        ),
        nowMs: world.now,
      );
      await alice.outbox.flush();
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
      expect(world.requests, isEmpty);
    });

    test('a recipient not checked yet is waited for', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      expect(await alice.service.notifyBehind(g.id, bob.snowId), isTrue);
      // Bob's membership is checked again (as after joining again).
      final bobRow = await alice.store.memberBySnowId(g.id, bob.snowId);
      await alice.store.saveMemberChecks(g.id, [
        Gv2MemberCheckResult(
          ciphertext: bobRow!.ciphertext,
          joinedRevision: bobRow.joinedRevision,
          state: Gv2MemberCheckState.unchecked,
        ),
      ]);
      await alice.outbox.flush();
      final row = (await alice.db.gv2OutboxStore.allRows()).single;
      expect(row.attempts, 0);
      expect(row.notBeforeMs, greaterThan(world.now));
      expect(world.requests, isEmpty);
      await alice.confirmAll(g);
      world.now = row.notBeforeMs;
      await alice.flush();
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
    });

    test(
      'a missing endorsement is fetched once, then the row backs off',
      () async {
        await alice.install(g, 2);
        await bob.install(g, 2);
        await alice.service.notifyBehind(g.id, bob.snowId);
        alice.tokens.missing.add(g.id);
        await alice.outbox.flush();
        expect(alice.tokens.refreshes, 1);
        expect(
          await alice.db.gv2OutboxStore.allRows(),
          isEmpty,
          reason: 'the refresh brought the endorsement',
        );

        await alice.service.notifyBehind(g.id, carol.snowId);
        alice.tokens.missing.add(g.id);
        alice.tokens.stuck.add(g.id);
        await alice.outbox.flush();
        expect(alice.tokens.refreshes, 2);
        final row = (await alice.db.gv2OutboxStore.allRows()).single;
        expect(row.attempts, 1);
        expect(row.notBeforeMs, world.now + 30000);
      },
    );

    test('a failed send backs off, doubling', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      await alice.service.notifyBehind(g.id, bob.snowId);
      world.failSends = true;
      await alice.outbox.flush();
      var row = (await alice.db.gv2OutboxStore.allRows()).single;
      expect(row.attempts, 1);
      expect(row.notBeforeMs, world.now + 30000);
      world.now = row.notBeforeMs;
      await alice.outbox.flush();
      row = (await alice.db.gv2OutboxStore.allRows()).single;
      expect(row.attempts, 2);
      expect(row.notBeforeMs, world.now + 60000);
      world.failSends = false;
      world.now = row.notBeforeMs;
      await alice.flush();
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
    });

    test('an account the server does not know: the row is dropped', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      await alice.service.notifyBehind(g.id, bob.snowId);
      world.gone.add(bob.snowId);
      await alice.outbox.flush();
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
    });

    test('a Sender Key waits until this device is confirmed', () async {
      await alice.install(g, 2, membership: Gv2Membership.awaitingConfirm);
      await bob.install(g, 2);
      final own = await alice.db.gv2SenderKeyStore.createOwn(
        g.id,
        alice.snowId,
      );
      await alice.db.gv2OutboxStore.enqueuePairwise(
        groupId: g.id,
        message: _msg(g, alice, bob, own),
        nowMs: world.now,
      );
      await alice.service.notifyBehind(g.id, bob.snowId);
      await alice.outbox.flush();
      final rows = await alice.db.gv2OutboxStore.allRows();
      expect(
        rows.single.payload[2],
        gv2PairwiseTypeSenderKey,
        reason: 'the notice went, the key waits',
      );
      await alice.store.setMembership(g.id, Gv2Membership.active);
      world.now = rows.single.notBeforeMs;
      await alice.flush();
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
      final m = await bob.db.gv2SenderKeyStore.manager(g.id, alice.snowId);
      expect(m.hasSenderKey(g.id, alice.snowId), isTrue);
    });

    test(
      'a row that cannot go holds back later rows to the same recipient',
      () async {
        await alice.install(g, 2);
        await bob.install(g, 2);
        await carol.install(g, 2);
        // A reset row first: its session reset fails (no bundle left).
        await alice.db.gv2OutboxStore.enqueuePairwise(
          groupId: g.id,
          message: _msg(g, alice, bob, const Gv2SessionResetBody()),
          nowMs: world.now,
        );
        await alice.service.notifyBehind(g.id, bob.snowId);
        await alice.service.notifyBehind(g.id, carol.snowId);
        alice.sessions.failResets = true;
        await alice.outbox.flush();
        final left = await alice.db.gv2OutboxStore.allRows();
        expect(
          [for (final r in left) r.payload[2]],
          [gv2PairwiseTypeSessionReset, gv2PairwiseTypeBehind],
        );
        expect(left.first.attempts, 1);
        expect(left.last.attempts, 0, reason: 'held back, not failed');
        expect(
          world.requests.single.entries,
          hasLength(2),
          reason: 'Carol + decoy',
        );
      },
    );

    test('a row that is backing off holds back later rows to the same '
        'recipient across flushes, and they then go in order', () async {
      await alice.install(g, 2);
      await bob.install(g, 3);
      await carol.install(g, 2);
      await alice.service.notifyBehind(g.id, bob.snowId);
      world.failSends = true;
      await alice.outbox.flush();
      world.failSends = false;
      final first = (await alice.db.gv2OutboxStore.allRows()).single;
      expect(first.notBeforeMs, world.now + 30000);

      // Queued later, to the same recipient and to another one.
      expect(await alice.service.requestKey(g.id, bob.snowId, 3), isTrue);
      expect(await alice.service.requestKey(g.id, carol.snowId, 3), isTrue);
      world.now += 5000;
      world.requests.clear();
      await alice.flush();
      final left = await alice.db.gv2OutboxStore.allRows();
      expect(
        [for (final r in left) r.payload[2]],
        [gv2PairwiseTypeBehind, gv2PairwiseTypeKeyRequest],
        reason: 'only Carol\'s row went',
      );
      expect(left.every((r) => r.recipient == bob.snowId), isTrue);
      expect(left.last.attempts, 0);

      // Once the first row is due again, both go — one request each, the
      // earlier row first.
      world.now = first.notBeforeMs;
      world.requests.clear();
      await alice.flush();
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
      expect(world.requests, hasLength(2));
      expect(bob.handler.pairwiseTypes, [
        gv2PairwiseTypeBehind,
        gv2PairwiseTypeKeyRequest,
      ]);
    });

    test(
      'rows beyond the first page go even when the first page is stuck',
      () async {
        await alice.install(g, 2);
        await bob.install(g, 2);
        await carol.install(g, 2);
        final paged = Gv2Outbox(
          store: alice.db.gv2OutboxStore,
          groups: alice.store,
          keys: alice.db.gv2SenderKeyStore,
          tokens: alice.tokens,
          crypto: alice.crypto,
          send: (entries) => world.send(alice, entries),
          mySnowId: () async => alice.snowId,
          myDeviceId: () async => alice.party.deviceId,
          memberKey: (_) async => alice.person.memberKey,
          giveKeys: (groupId) => alice.service.giveKeys(groupId),
          prepareGroup: (_, {required sync}) async {},
          nowMs: () => world.now,
          pageSize: 1,
        );
        // The first row of the queue backs off; the page holds only it.
        await alice.service.notifyBehind(g.id, bob.snowId);
        world.failSends = true;
        await paged.flush();
        world.failSends = false;
        await alice.service.notifyBehind(g.id, carol.snowId);
        await paged.flush();
        final left = await alice.db.gv2OutboxStore.allRows();
        expect(left.single.recipient, bob.snowId);
      },
    );

    test('a row older than 30 days is given up', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      await alice.service.notifyBehind(g.id, bob.snowId);
      world.failSends = true;
      world.now += const Duration(days: 31).inMilliseconds;
      await alice.outbox.flush();
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
    });

    test('leaving a group drops what waits to go to it', () async {
      await alice.install(g, 2);
      await bob.install(g, 2);
      await alice.service.notifyBehind(g.id, bob.snowId);
      await alice.store.deleteGroup(g.id);
      expect(await alice.db.gv2OutboxStore.allRows(), isEmpty);
    });
  });

  group('head requests, proofs and the withheld hold', () {
    Gv2SignedHead headOf(Gv2TestGroup log, int revision) => Gv2SignedHead(
      revision: revision,
      chain: log.states[revision].chain,
      headSig: log.headSig(revision),
    );

    Gv2PairwiseMessage fromAlice(Gv2PairwiseBody body) => Gv2PairwiseMessage(
      groupId: g.groupId,
      sender: alice.person.accountId,
      recipient: bob.person.accountId,
      body: body,
    );

    /// Bob (at [at]) is shown [head] by alice; the sync that follows gets
    /// him nowhere.
    Future<void> showBob(Gv2SignedHead head) async {
      bob.handler.onSync = (_) async {
        world.now += 1;
        await bob.store.markSynced(g.id, world.now);
      };
      await alice.sendRaw(bob, fromAlice(Gv2HeadProofBody(head)));
      await world.drainAll();
    }

    test('a head request is answered with this device\'s signed head, once '
        'in ten minutes per member', () async {
      await alice.install(g, 3);
      await bob.install(g, 3);
      await alice.sendRaw(bob, fromAlice(const Gv2HeadRequestBody()));
      await world.drainAll();
      final row = (await bob.db.gv2OutboxStore.allRows()).single;
      final answer = Gv2PairwiseMessage.decode(row.payload)!;
      expect(answer.recipientSnowId, alice.snowId);
      final head = (answer.body as Gv2HeadProofBody).head;
      expect(head.revision, 3);
      expect(head.chain, g.states[3].chain);
      expect(head.headSig, g.headSig(3));

      await bob.flush();
      await alice.sendRaw(bob, fromAlice(const Gv2HeadRequestBody()));
      await world.drainAll();
      expect(await bob.db.gv2OutboxStore.allRows(), isEmpty);
      world.now += gv2NoticeEvery.inMilliseconds;
      await alice.sendRaw(bob, fromAlice(const Gv2HeadRequestBody()));
      await world.drainAll();
      expect(await bob.db.gv2OutboxStore.allRows(), hasLength(1));
    });

    test(
      'asking for a head is rate limited, and nobody asks a non-member',
      () async {
        await alice.install(g, 3);
        await bob.install(g, 3);
        expect(await bob.service.requestHead(g.id, alice.snowId), isTrue);
        expect(await bob.service.requestHead(g.id, alice.snowId), isFalse);
        expect(await bob.service.requestHead(g.id, bob.snowId), isFalse);
        expect(
          await bob.service.requestHead(g.id, g.person('eve').snowId),
          isFalse,
        );
        world.now += gv2NoticeEvery.inMilliseconds;
        expect(await bob.service.requestHead(g.id, alice.snowId), isTrue);
      },
    );

    test('a signed head beyond what a fresh sync reaches puts the group on '
        'the withheld hold; reaching it releases the hold', () async {
      await alice.install(g, 3);
      await bob.install(g, 2);
      await showBob(headOf(g, 3));
      var row = await bob.group(g);
      expect(row.hold, Gv2Hold.withheld);
      expect(row.revision, 2);

      // Not there yet: the hold stays.
      await bob.service.settleWithheld(g.id);
      expect((await bob.group(g)).hold, Gv2Hold.withheld);

      await bob.advanceTo(g, 3);
      await bob.service.settleWithheld(g.id);
      row = await bob.group(g);
      expect(row.hold, Gv2Hold.none);
      expect(row.holdEvidence, isNull);
    });

    test('reaching the withheld revision on ANOTHER chain freezes, whether '
        'this device\'s point is signed itself or covered by the signed '
        'anchor above it', () async {
      final fork = g.forkAt(2)
        ..change(g.person('alice'), const [Gv2SetTitle()], newTitle: 'other');
      await alice.install(g, 3);
      await bob.install(g, 2);
      await carol.install(g, 2);
      g.change(g.person('alice'), const [Gv2SetTitle()], newTitle: 'r4');

      // Bob reaches r3 in a batch of its own: a signed point.
      await showBob(headOf(fork, 3));
      expect((await bob.group(g)).hold, Gv2Hold.withheld);
      await bob.advanceTo(g, 3);
      await bob.service.settleWithheld(g.id);
      final row = await bob.group(g);
      expect(row.hold, Gv2Hold.frozen);
      final evidence = jsonDecode(utf8.decode(row.holdEvidence!)) as Map;
      expect(evidence['kind'], 'two_heads');

      // Carol passes r3 inside a batch: no signature on her point, but her
      // signed anchor at r4 lies on the same chain.
      carol.handler.onSync = (_) async {
        world.now += 1;
        await carol.store.markSynced(g.id, world.now);
      };
      await alice.sendRaw(
        carol,
        Gv2PairwiseMessage(
          groupId: g.groupId,
          sender: alice.person.accountId,
          recipient: carol.person.accountId,
          body: Gv2HeadProofBody(headOf(fork, 3)),
        ),
      );
      await world.drainAll();
      expect((await carol.group(g)).hold, Gv2Hold.withheld);
      await carol.advanceTo(g, 4);
      expect((await carol.store.head(g.id, 3))!.headSig, isNull);
      await carol.service.settleWithheld(g.id);
      final carolRow = await carol.group(g);
      expect(carolRow.hold, Gv2Hold.frozen);
      final carolEvidence =
          jsonDecode(utf8.decode(carolRow.holdEvidence!)) as Map;
      expect(carolEvidence['kind'], 'two_heads');
      expect((carolEvidence['held'] as Map)['revision'], 3);
      expect((carolEvidence['cover'] as Map)['revision'], 4);
    });

    test('a hold whose evidence cannot be read is released', () async {
      await bob.install(g, 3);
      await bob.store.setHold(
        g.id,
        Gv2Hold.withheld,
        evidence: Uint8List.fromList(utf8.encode('not json')),
      );
      await bob.service.settleWithheld(g.id);
      expect((await bob.group(g)).hold, Gv2Hold.none);
    });

    test('giveKeys gives the current key to every confirmed member that '
        'lacks it, once', () async {
      await alice.install(g, 3);
      await bob.install(g, 3);
      await carol.install(g, 3);
      expect(await alice.service.giveKeys(g.id), 0); // no key yet
      final own = await alice.db.gv2SenderKeyStore.createOwn(
        g.id,
        alice.snowId,
      );
      expect(await alice.service.giveKeys(g.id), 2);
      expect(await alice.service.giveKeys(g.id), 0);
      expect(await alice.db.gv2SenderKeyStore.deliveredTo(g.id, own.chainId), {
        bob.snowId,
        carol.snowId,
      });
      expect(await alice.db.gv2OutboxStore.allRows(), hasLength(2));

      // A device that is not confirmed, or whose group is on hold, gives none.
      await bob.db.gv2SenderKeyStore.createOwn(g.id, bob.snowId);
      await bob.store.setHold(g.id, Gv2Hold.updateRequired);
      expect(await bob.service.giveKeys(g.id), 0);
      await bob.store.setHold(g.id, Gv2Hold.none);
      await bob.store.setMembership(g.id, Gv2Membership.awaitingConfirm);
      expect(await bob.service.giveKeys(g.id), 0);
    });
  });
}
