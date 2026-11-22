/// @file        gv2_runtime_test.dart
/// @description Group protocol v2 runtime and the backup of the group keys:
///              a pump asks for the backup first while this install has not
///              looked at it, takes the groups in, tries to bring them into
///              use and writes the backup; a backup that cannot be had
///              holds nothing else up.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-21 (no autoAccept). Earlier 2026-11-20 (the runtime takes the server keys this build trusts)
///
/// @functions
///  - main(): restore through a pump, a backup route that fails, leaving
///    the groups before the account is deleted.
///
/// Notes:
///  - The runtime is the real one on an in-memory database. Its group
///    transport points at a port nothing listens on: every call to the
///    group server fails like "no network", which is all these tests need
///    of it (the group flows themselves are tested with a stand-in server
///    in gv2_groups_test.dart).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/group_v2/gv2_backup.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_content.dart';
import 'package:snowchat/core/group_v2/gv2_envelope.dart';
import 'package:snowchat/core/group_v2/gv2_inbox.dart';
import 'package:snowchat/core/group_v2/gv2_keys.dart';
import 'package:snowchat/core/group_v2/gv2_messaging.dart';
import 'package:snowchat/core/group_v2/gv2_pairwise_crypto.dart';
import 'package:snowchat/core/group_v2/gv2_runtime.dart';
import 'package:snowchat/core/group_v2/gv2_trusted_keys.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';

import 'gv2_test_support.dart';

class _Crypto extends Fake implements Gv2PairwiseCrypto {
  int opens = 0;

  @override
  Future<Gv2PairwiseOpened> open(Uint8List envelope) async {
    opens++;
    throw const Gv2PairwiseOpenException(Gv2PairwiseOpenFailure.unsealed);
  }
}

class _Sink implements Gv2MessageSink {
  @override
  Future<void> message(Gv2IncomingMessage message) async {}

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
  void groupChanged(String groupId, List<Gv2Entry> applied) {}
}

class _Api implements Gv2BackupApi {
  Uint8List? blob;
  Object? failWith;
  int fetches = 0;
  int stores = 0;

  static String _tag(Uint8List b) => base64Encode(hash.sha256.convert(b).bytes);

  @override
  Future<Gv2BackupBlob> fetch() async {
    fetches++;
    if (failWith != null) throw failWith!;
    final held = blob;
    return held == null
        ? const Gv2BackupBlob(null, null)
        : Gv2BackupBlob(held, _tag(held));
  }

  @override
  Future<String?> store(Uint8List blob, String? ifMatch) async {
    stores++;
    if (failWith != null) throw failWith!;
    final held = this.blob;
    if ((held == null ? null : _tag(held)) != ifMatch) return null;
    this.blob = blob;
    return _tag(blob);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final seed = gv2TestSha('gv2 runtime test — account seed');
  final accountPub = Uint8List.fromList(
    ed.SigningKey(seed: seed).verifyKey.asTypedList,
  );
  final me = KeyDerivation.deriveSnowChatId(accountPub);
  final key = gv2DeriveBackupKey(seed);

  late SnowDatabase db;
  late _Api api;
  late _Crypto crypto;
  late Gv2Runtime runtime;
  late List<String> acked;

  Gv2BackupEntry entry(String label) {
    final masterKey = gv2TestSha('gv2 runtime test — master key $label');
    return Gv2BackupEntry(
      groupId: ZkGroup.groupParams(masterKey).groupId,
      masterKey: masterKey,
      revision: 4,
      chain: gv2TestSha('chain $label'),
      stateHash: gv2TestSha('state $label'),
    );
  }

  /// A row of the group queue holding a sealed-sender-shaped envelope that
  /// opens for nobody.
  Map<String, Object?> row(int n) => {
    'id': '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}',
    'seq': '$n',
    'envelope': base64Encode([0x01, ...gv2TestBytes('row $n', 80)]),
  };

  setUp(() {
    db = SnowDatabase(NativeDatabase.memory());
    api = _Api();
    crypto = _Crypto();
    acked = [];
    runtime = Gv2Runtime(
      db: db,
      mySnowId: me,
      authenticatedPost: (_) async => throw StateError('no server'),
      pinnedAccountKey: (_) async => null,
      crypto: crypto,
      myDeviceId: () async => '11111111-1111-4111-8111-111111111111',
      memberKey: (groupId) async =>
          Gv2SigningKey.fromSeed(gv2DeriveMemberSeed(seed, groupId)),
      memberCert: (_, _) async => Uint8List(64),
      accountPublicKey: () async => accountPub,
      ack: (ids) async => acked.addAll(ids),
      sink: _Sink(),
      sendInvite: (_, _) async => false,
      backupApi: api,
      backupKey: () async => key,
      trustedKeys: gv2TrustedServerKeysFor('dev')!,
      isBlocked: (_) async => false,
      backupWriteDelay: () => Duration.zero,
      // Nothing listens here: the group server is "not reachable".
      baseUrl: 'http://127.0.0.1:9',
    );
  });
  tearDown(() async {
    runtime.dispose();
    await db.close();
  });

  test('a pump on a new install takes the groups from the backup, tries to '
      'bring them into use, and writes the backup', () async {
    final a = entry('a');
    final b = entry('b');
    api.blob = gv2SealBackup(key, [a, b]);

    await runtime.pump();
    final groups = await db.gv2Store.groups();
    expect(
      {for (final g in groups) g.groupId},
      {gv2Hex(a.groupId), gv2Hex(b.groupId)},
    );
    for (final g in groups) {
      expect(g.membership, Gv2Membership.awaitingConfirm);
      // The group server was not reached: still to be followed.
      expect(g.resetPending, isTrue);
      expect(g.stateLoaded, isFalse);
    }
    expect((await db.gv2Store.backupState())!.restored, isTrue);
    expect(api.fetches, 1);
    expect(api.stores, 1);
    expect(gv2OpenBackup(key, api.blob!), hasLength(2));

    // Later pumps neither ask for the backup nor write it again.
    await runtime.pump();
    await runtime.pump();
    expect(api.fetches, 1);
    expect(api.stores, 1);
    expect(await db.gv2OutboxStore.allRows(), isEmpty);
  });

  test('the backup follows the groups: at the end of a pump, and when '
      'something this account queued was sent', () async {
    await runtime.pump();
    expect(api.stores, 1);
    expect(gv2OpenBackup(key, api.blob!), isEmpty);

    Future<String> join(String label) async {
      final e = entry(label);
      await db.gv2Store.insertAnchored(
        groupId: e.groupId,
        masterKey: e.masterKey,
        myCiphertext: ZkGroup.encryptMember(
          masterKey: e.masterKey,
          accountId: Uint8List.fromList(accountPub.sublist(0, 16)),
        ),
        protocolVersion: gv2ProtocolVersion,
        revision: e.revision,
        chain: e.chain,
        stateHash: e.stateHash,
        membership: Gv2Membership.awaitingConfirm,
      );
      return gv2Hex(e.groupId);
    }

    List<String> listed() => [
      for (final e in gv2OpenBackup(key, api.blob!)!) gv2Hex(e.groupId),
    ];

    // A group more, then a pump.
    final a = await join('a');
    await runtime.pump();
    expect(api.stores, 2);
    expect(listed(), [a]);

    // A group more, then only a message queued for it (no pump).
    final b = await join('b');
    await runtime.messaging.send(b, Gv2MessageContent(Uint8List(3)));
    for (var i = 0; i < 200 && api.stores < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(api.stores, 3);
    expect(listed().toSet(), {a, b});
  });

  test('a backup that cannot be had holds nothing else up', () async {
    for (final failure in <Object>[
      const Gv2BackupUnreachable(),
      StateError('500'),
    ]) {
      api.failWith = failure;
      final opens = crypto.opens;
      expect(await runtime.receive([row(crypto.opens + 1)]), isTrue);
      await runtime.pump();
      // The row was stored, acknowledged and handled (it opens for nobody
      // and is gone).
      expect(crypto.opens, opens + 1, reason: '$failure');
      expect(await db.gv2InboxStore.allRows(), isEmpty);
      expect(await db.gv2Store.backupState(), isNull);
    }
    expect(acked, hasLength(2));

    // The route answers again, but this device does not ask yet.
    api.failWith = null;
    api.blob = gv2SealBackup(key, [entry('a')]);
    // (The refusal just before is remembered for ten minutes.)
    await runtime.pump();
    expect(await db.gv2Store.groups(), isEmpty);
  });

  test('a refusal of the backup route is not repeated with every pump; "no '
      'network" is asked again', () async {
    api.failWith = const Gv2BackupUnreachable();
    await runtime.pump();
    await runtime.pump();
    expect(api.fetches, 2);

    api.failWith = StateError('429');
    await runtime.pump();
    await runtime.pump();
    await runtime.pump();
    expect(api.fetches, 3);
  });

  test('leaving every group before the account is deleted never throws',
      () async {
    api.blob = gv2SealBackup(key, [entry('a')]);
    await runtime.leaveAllGroups();
    // The group could not be followed (no group server): it is still
    // there, and nothing was thrown.
    expect(await db.gv2Store.groups(), hasLength(1));

    api.failWith = StateError('down');
    await runtime.leaveAllGroups();
    runtime.dispose();
    await runtime.leaveAllGroups();
  });

  test('a push of the group queue opens the chat of the row\'s group — at '
      'once, without waiting for the group server; an unknown or pairwise '
      'row opens none', () async {
    final a = entry('a');
    api.blob = gv2SealBackup(key, [a]);
    await runtime.pump();
    final groupId = gv2Hex(a.groupId);
    // The group from the backup is not followed yet (the group server is not
    // reachable): what arrives for it waits in its lane.
    final notice = gv2SealChangeNoticeEnvelope(
      keys: Gv2EnvelopeKeys.derive(a.masterKey, a.groupId),
      stamp: Gv2EnvelopeStamp(
        senderAccountId: Uint8List(16),
        senderDeviceId: '22222222-2222-4222-8222-222222222222',
        messageId: gv2NewMessageId(),
        revision: 5,
        chain: Uint8List(32),
        timestampMs: 1,
      ),
    );
    const rowId = '00000000-0000-4000-8000-0000000000aa';
    // Stored only — as when a tap fetched the row a moment ago.
    final stored = await runtime.inbox.receive([
      Gv2QueueRow.tryParse({
        'id': rowId,
        'seq': '170',
        'envelope': base64Encode(notice),
      })!,
      Gv2QueueRow.tryParse(row(171))!,
    ]);
    expect(stored.acknowledged, isTrue);
    final clock = Stopwatch()..start();
    expect(await runtime.conversationOfPush(rowId), groupId);
    expect(await runtime.conversationOfPush(row(171)['id']! as String), isNull);
    expect(
      await runtime.conversationOfPush('00000000-0000-4000-8000-0000000000ff'),
      isNull,
    );
    // Nothing of this waited for the group server (a sync waits seconds).
    expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    runtime.dispose();
    expect(await runtime.conversationOfPush(rowId), isNull);
  });
}
