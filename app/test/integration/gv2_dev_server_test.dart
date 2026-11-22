/// @file        gv2_dev_server_test.dart
/// @description Group protocol v2 client against a RUNNING development
///              server: real accounts, real zkgroup, real HTTP. Two devices
///              (each with its own database, store, transport and
///              credentials) create a group, read it as an invitee, accept,
///              follow the log (by hand, then with Gv2Sync), check the
///              members, fetch endorsements and send — and the server is
///              asked the things it must refuse. Everything the offline
///              tests cannot show is shown here: that the server accepts this
///              client's presentations, entries and tokens, and that this
///              client accepts the server's head signatures and endorsements.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-22 (SC-18: sends carry no noPush). Earlier 2026-11-20 (the credentials take the dev server keys this build trusts)
///
/// @functions
///  - main(): one ordered scenario.
///  - _Device: an account with its own client stack.
///
/// Notes:
///  - Skipped unless SNOWCHAT_DEV_SERVER is set:
///      SNOWCHAT_DEV_SERVER=http://localhost:3100 \
///        flutter test test/integration/gv2_dev_server_test.dart
///    Never point it at production: it registers and deletes accounts.
///  - The accounts are throwaway (random keys) and are deleted at the end
///    with a signed deletion proof — which is itself the client/server check
///    of that proof. The test group is ended by its owner; the server keeps
///    the ended group's id by design.
///  - The envelope sent is filler: the server never reads envelopes.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/ed25519_strict.dart';
import 'package:snowchat/core/crypto/identity_binding.dart';
import 'package:snowchat/core/crypto/identity_manager.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_credentials.dart';
import 'package:snowchat/core/group_v2/gv2_keys.dart';
import 'package:snowchat/core/group_v2/gv2_member_check.dart';
import 'package:snowchat/core/group_v2/gv2_payloads.dart';
import 'package:snowchat/core/group_v2/gv2_state_machine.dart';
import 'package:snowchat/core/group_v2/gv2_store.dart';
import 'package:snowchat/core/group_v2/gv2_sync.dart';
import 'package:snowchat/core/group_v2/gv2_transport.dart';
import 'package:snowchat/core/group_v2/gv2_trusted_keys.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';

import '../core/crypto/identity_test_support.dart';

final String? _server = Platform.environment['SNOWCHAT_DEV_SERVER'];

Uint8List _random(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

String _uuid() {
  final b = _random(16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = gv2Hex(b);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// One account on one device.
class _Device {
  final String name;
  final String baseUrl;
  final Uint8List accountSeed = _random(32);
  late final Uint8List accountPub = Uint8List.fromList(
      ed.SigningKey(seed: accountSeed).verifyKey.asTypedList);
  late final String snowId = KeyDerivation.deriveSnowChatId(accountPub);
  late final Uint8List accountId = Uint8List.fromList(accountPub.sublist(0, 16));
  late final String displayName = 'gv2t-$name-${gv2Hex(_random(4))}';

  late final IdentityManager identity = IdentityManager(InMemorySecureStorage()
    ..data['identity_private_key'] = bytesToHexLower(accountSeed)
    ..data['identity_public_key'] = bytesToHexLower(accountPub)
    ..data['snow_chat_id'] = snowId);

  final SnowDatabase db = SnowDatabase(NativeDatabase.memory());
  late final Gv2Store store = db.gv2Store;
  late final Dio _login = Dio(BaseOptions(baseUrl: baseUrl));
  String? _bearer;
  int credentialFetches = 0;

  late final Gv2Transport transport = Gv2Transport(
    baseUrl: baseUrl,
    authenticatedPost: (path) async {
      credentialFetches++;
      final response = await _login.post<Object?>(path,
          options: Options(headers: {'Authorization': 'Bearer $_bearer'}));
      return response.data;
    },
  );
  late final Gv2Credentials credentials = Gv2Credentials(
    store: store,
    transport: transport,
    snowId: () async => snowId,
    trustedKeys: gv2TrustedServerKeysFor('dev')!,
  );

  late final Gv2Sync sync = Gv2Sync(
    store: store,
    transport: transport,
    credentials: credentials,
    pinnedAccountKey: (_) async => null,
  );

  _Device(this.name, String server) : baseUrl = '$server/api/v2';

  /// Register and log in the way the app does.
  Future<void> register() async {
    await _login.post<Object?>('/auth/register', data: {
      'publicKey': bytesToHexLower(accountPub),
      'snowchatId': snowId,
      'displayName': displayName,
    });
    final challenge = await _login
        .post<Map<String, dynamic>>('/auth/challenge', data: {'snowchatId': snowId});
    final nonce = challenge.data!['nonce'] as String;
    final verified = await _login.post<Map<String, dynamic>>('/auth/verify', data: {
      'snowchatId': snowId,
      'nonce': nonce,
      'signature': await identity.signAuthChallenge(nonce),
      'deviceInfo': {
        'deviceId': _uuid(),
        'identityKey': base64Encode(_random(32)),
        'signedPreKey': base64Encode(_random(32)),
        'signedPreKeySig': base64Encode(_random(64)),
        'signedPreKeyId': 1,
        'registrationId': 1,
        'deviceName': 'gv2 client test',
        'osType': 'test',
      },
    });
    _bearer = verified.data!['token'] as String;
  }

  /// Delete the account with its signed deletion proof.
  Future<int?> deleteAccount({int clockErrorMs = 0}) async {
    final proof = await identity.signAccountDeleted(
        DateTime.now().millisecondsSinceEpoch + clockErrorMs);
    final response = await _login.post<Object?>(
      '/users/me/delete',
      data: {'deletionProof': proof.toWireJson()},
      options: Options(
        headers: {'Authorization': 'Bearer $_bearer'},
        validateStatus: (_) => true,
      ),
    );
    return response.statusCode;
  }

  Uint8List ciphertextIn(Uint8List masterKey) =>
      ZkGroup.encryptMember(masterKey: masterKey, accountId: accountId);

  /// The sealed member payload this account joins a group with.
  Future<Uint8List> memberPayload(Uint8List masterKey, Uint8List groupId) async {
    final issuedAtMs = DateTime.now().millisecondsSinceEpoch;
    return gv2SealMemberPayload(
      gv2DeriveStateKey(masterKey, groupId),
      Gv2MemberPayload(
        accountPublicKey: accountPub,
        issuedAtMs: issuedAtMs,
        certSignature: await identity.signGroupMemberCert(
            groupId: groupId, issuedAtMs: issuedAtMs),
      ),
    );
  }

  Future<void> dispose() async {
    transport.close();
    _login.close(force: true);
    await db.close();
  }
}

void main() {
  final skip = _server == null
      ? 'set SNOWCHAT_DEV_SERVER (for example http://localhost:3100)'
      : null;

  late _Device alice;
  late _Device bob;
  late _Device mallory;
  var registered = <_Device>[];

  late Uint8List masterKey;
  late Uint8List groupId;
  late String id;
  late Uint8List headKey;
  late Gv2GroupState stateAtCreation;

  setUpAll(() async {
    if (_server == null) return;
    // One in-memory database per device, on purpose.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    alice = _Device('alice', _server!);
    bob = _Device('bob', _server!);
    mallory = _Device('mallory', _server!);
    for (final device in [alice, bob, mallory]) {
      await device.register();
      registered.add(device);
    }
  });

  tearDownAll(() async {
    for (final device in registered) {
      await device.deleteAccount();
      await device.dispose();
    }
  });

  bool headVerifies(Gv2Head head) => verifyEd25519Strict(
      headKey, gv2HeadMessage(groupId, head.revision, head.chain), head.headSig);

  test('server keys are fetched without a login and stored', () async {
    final keys = await alice.credentials.serverKeys();
    headKey = keys.headPublicKey;
    expect(keys.serverPublicParams, isNotEmpty);
    expect(headKey.length, 32);
    // Both devices see the same server.
    final bobKeys = await bob.credentials.serverKeys();
    expect(bobKeys.serverPublicParams, keys.serverPublicParams);
    expect(bobKeys.headPublicKey, headKey);
  }, skip: skip);

  test('alice creates a group; the server signs its head', () async {
    masterKey = gv2NewMasterKey();
    final params = ZkGroup.groupParams(masterKey);
    groupId = params.groupId;
    id = gv2Hex(groupId);
    final stateKey = gv2DeriveStateKey(masterKey, groupId);
    final keys = await alice.credentials.serverKeys();

    final memberKey = await alice.identity.deriveGroupMemberKey(groupId);
    final bobInvite = Gv2SigningKey.generate();
    final signed = gv2SignEntry(
      state: null,
      groupId: groupId,
      draft: Gv2EntryDraft(
        version: gv2ProtocolVersion,
        revision: 0,
        prevChain: gv2GenesisPrevChain(),
        actor: alice.ciphertextIn(masterKey),
        actions: [
          Gv2Create(memberKey.publicKey),
          Gv2Invite(bob.ciphertextIn(masterKey), bobInvite.publicKey),
        ],
        memberPayload: await alice.memberPayload(masterKey, groupId),
        titlePayload: gv2SealTitlePayload(
          stateKey,
          Gv2TitlePayload(
            name: 'Dev server round trip',
            serverKeyHash: gv2ServerKeyHash(
              serverPublicParams: keys.serverPublicParams,
              headPublicKey: keys.headPublicKey,
            ),
          ),
        ),
      ),
      key: memberKey,
    );

    final head = await alice.transport.create(
      groupId: groupId,
      publicParams: params.publicParams,
      presentation: await alice.credentials.presentation(masterKey),
      entry: gv2EncodeEntry(signed.entry),
    );
    expect(alice.credentialFetches, 1);
    stateAtCreation = signed.next;
    expect(head.revision, 0);
    expect(head.chain, signed.next.chain, reason: 'server and client chain');
    expect(headVerifies(head), isTrue);

    await alice.store.insertCreated(
      masterKey: masterKey,
      myCiphertext: alice.ciphertextIn(masterKey),
      state: signed.next,
      headSig: head.headSig,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    expect((await alice.store.group(id))!.title, 'Dev server round trip');

    // What the 1:1 invite message would carry to bob.
    expect(
      await bob.store.insertAnchored(
        groupId: groupId,
        masterKey: masterKey,
        myCiphertext: bob.ciphertextIn(masterKey),
        protocolVersion: gv2ProtocolVersion,
        revision: 0,
        chain: signed.next.chain,
        stateHash: signed.entry.stateHashAfter,
        membership: Gv2Membership.invited,
        inviteSeed: bobInvite.seed,
        invitedBySnowId: alice.snowId,
      ),
      isTrue,
    );
  }, skip: skip);

  test('creating the same group again is refused', () async {
    final again = gv2SignEntry(
      state: null,
      groupId: groupId,
      draft: Gv2EntryDraft(
        version: gv2ProtocolVersion,
        revision: 0,
        prevChain: gv2GenesisPrevChain(),
        actor: alice.ciphertextIn(masterKey),
        actions: [
          Gv2Create((await alice.identity.deriveGroupMemberKey(groupId)).publicKey),
        ],
        memberPayload: await alice.memberPayload(masterKey, groupId),
        titlePayload: gv2SealTitlePayload(
            gv2DeriveStateKey(masterKey, groupId),
            Gv2TitlePayload(name: 'again', serverKeyHash: Uint8List(32))),
      ),
      key: await alice.identity.deriveGroupMemberKey(groupId),
    );
    await expectLater(
      alice.transport.create(
        groupId: groupId,
        publicParams: ZkGroup.groupParams(masterKey).publicParams,
        presentation: await alice.credentials.presentation(masterKey),
        entry: gv2EncodeEntry(again.entry),
      ),
      throwsA(isA<Gv2ApiException>()
          .having((e) => e.status, 'status', 409)
          .having((e) => e.code, 'code', 'group_exists')),
    );
  }, skip: skip);

  test('bob, invited, reads the state and it matches the anchor', () async {
    final snapshot = await bob.transport.snapshot(
      groupId: groupId,
      presentation: await bob.credentials.presentation(masterKey),
      at: 0,
    );
    // installState accepts it only if it hashes to the invite's state hash.
    await bob.store.installState(state: snapshot.state, headSig: snapshot.headSig);
    final row = (await bob.store.group(id))!;
    expect(row.title, 'Dev server round trip');
    expect(
        verifyEd25519Strict(headKey, gv2HeadMessage(groupId, 0, row.chain),
            row.headSig!),
        isTrue);

    // Bob confirms who the owner is from the member payload.
    final state = (await bob.store.loadState(id))!;
    final owner = state.members.entries.single;
    final check = gv2CheckMember(
      stateKey: gv2DeriveStateKey(masterKey, groupId),
      groupId: groupId,
      accountId: ZkGroup.decryptMember(
          masterKey: masterKey, ciphertext: gv2Unhex(owner.key)),
      member: owner.value,
    );
    expect(check.confirmed, isTrue);
    expect(check.member!.snowId, alice.snowId);
  }, skip: skip);

  test('someone who is not in the group reads nothing, even with the master key',
      () async {
    final presentation = await mallory.credentials.presentation(masterKey);
    for (final call in <Future<Object?> Function()>[
      () => mallory.transport
          .snapshot(groupId: groupId, presentation: presentation, at: 0),
      () => mallory.transport
          .log(groupId: groupId, presentation: presentation, from: 0),
      () => mallory.transport
          .endorsements(groupId: groupId, presentation: presentation),
    ]) {
      await expectLater(
        call(),
        throwsA(isA<Gv2ApiException>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.code, 'code', 'not_a_member')),
      );
    }
    // And a request without a valid presentation is not even identified.
    await expectLater(
      mallory.transport
          .log(groupId: groupId, presentation: _random(200), from: 0),
      throwsA(isA<Gv2ApiException>().having((e) => e.status, 'status', 401)),
    );
  }, skip: skip);

  test('bob accepts with the invite key; alice follows the log', () async {
    final before = (await bob.store.loadState(id))!;
    final row = (await bob.store.group(id))!;
    final memberKey = await bob.identity.deriveGroupMemberKey(groupId);
    final signed = gv2SignEntry(
      state: before,
      groupId: groupId,
      draft: Gv2EntryDraft(
        version: gv2ProtocolVersion,
        revision: 1,
        prevChain: before.chain,
        actor: bob.ciphertextIn(masterKey),
        actions: [
          Gv2Accept(
            memberKey.publicKey,
            gv2SignInviteAccept(
              inviteKey: Gv2SigningKey.fromSeed(row.inviteSeed!),
              groupId: groupId,
              ciphertext: bob.ciphertextIn(masterKey),
              memberPub: memberKey.publicKey,
            ),
          ),
        ],
        memberPayload: await bob.memberPayload(masterKey, groupId),
        titlePayload: Uint8List(0),
      ),
      key: memberKey,
    );
    final head = await bob.transport.change(
      groupId: groupId,
      presentation: await bob.credentials.presentation(masterKey),
      entry: gv2EncodeEntry(signed.entry),
    );
    expect(head.revision, 1);
    expect(head.chain, signed.next.chain);
    expect(headVerifies(head), isTrue);
    await bob.store.advance(
      from: before,
      to: signed.next,
      headSig: head.headSig,
      membership: Gv2Membership.awaitingConfirm,
    );

    // Alice learns of it from the log and verifies the entry herself.
    final aliceBefore = (await alice.store.loadState(id))!;
    final page = await alice.transport.log(
      groupId: groupId,
      presentation: await alice.credentials.presentation(masterKey),
      from: aliceBefore.revision + 1,
    );
    expect(page.removed, isFalse);
    expect(page.more, isFalse);
    expect(page.entries.single.revision, 1);
    expect(page.head!.revision, 1);
    final next = gv2ApplyEntry(
        aliceBefore, groupId, gv2DecodeEntry(page.entries.single.entry));
    expect(next.chain, page.head!.chain);
    expect(headVerifies(page.head!), isTrue);
    await alice.store.advance(
        from: aliceBefore, to: next, headSig: page.head!.headSig);
    expect((await alice.store.memberRows(id)).length, 2);
    expect(await alice.store.pendingInvites(id), isEmpty);
  }, skip: skip);

  test('a change from a stale revision comes back with the current head',
      () async {
    final current = (await alice.store.loadState(id))!;
    final memberKey = await alice.identity.deriveGroupMemberKey(groupId);
    // A valid entry on top of revision 0 — but revision 1 is already taken.
    final old = gv2SignEntry(
      state: stateAtCreation,
      groupId: groupId,
      draft: Gv2EntryDraft(
        version: gv2ProtocolVersion,
        revision: 1,
        prevChain: stateAtCreation.chain,
        actor: alice.ciphertextIn(masterKey),
        actions: const [Gv2SetTitle()],
        memberPayload: Uint8List(0),
        titlePayload: gv2SealTitlePayload(gv2DeriveStateKey(masterKey, groupId),
            Gv2TitlePayload(name: 'late', serverKeyHash: Uint8List(32))),
      ),
      key: memberKey,
    );
    Gv2ApiException? error;
    try {
      await alice.transport.change(
        groupId: groupId,
        presentation: await alice.credentials.presentation(masterKey),
        entry: gv2EncodeEntry(old.entry),
      );
    } on Gv2ApiException catch (e) {
      error = e;
    }
    expect(error?.status, 409);
    expect(error?.code, 'revision_conflict');
    expect(error?.head?.revision, 1);
    expect(error?.head?.chain, current.chain);
    expect(headVerifies(error!.head!), isTrue);
  }, skip: skip);

  test('an entry the rules forbid is rejected with the same code the client gives',
      () async {
    // Bob (a plain member) signs a removal of the owner. The client refuses
    // to sign it, so the entry is assembled by hand.
    final state = (await bob.store.loadState(id))!;
    final memberKey = await bob.identity.deriveGroupMemberKey(groupId);
    final draft = Gv2EntryDraft(
      version: gv2ProtocolVersion,
      revision: 2,
      prevChain: state.chain,
      actor: bob.ciphertextIn(masterKey),
      actions: [Gv2Remove(alice.ciphertextIn(masterKey))],
      memberPayload: Uint8List(0),
      titlePayload: Uint8List(0),
    );
    Gv2RejectCode? local;
    try {
      gv2PreviewEntry(state, groupId, draft);
    } on Gv2Reject catch (e) {
      local = e.code;
    }
    expect(local, Gv2RejectCode.permission);

    final fakeHash = _random(32);
    final entry = Gv2Entry.complete(draft,
        stateHashAfter: fakeHash,
        sig: memberKey.sign(gv2SignedBytes(groupId, draft, fakeHash)));
    await expectLater(
      bob.transport.change(
        groupId: groupId,
        presentation: await bob.credentials.presentation(masterKey),
        entry: gv2EncodeEntry(entry),
      ),
      throwsA(isA<Gv2ApiException>()
          .having((e) => e.status, 'status', 422)
          .having((e) => e.code, 'code', 'entry_rejected')
          .having((e) => e.reason, 'reason', local!.wire)),
    );
  }, skip: skip);

  test('endorsements verify for the members alice holds; a token sends',
      () async {
    expect(await alice.credentials.refreshEndorsements(id),
        Gv2EndorsementOutcome.stored);
    final everyone = [
      gv2Hex(alice.ciphertextIn(masterKey)),
      gv2Hex(bob.ciphertextIn(masterKey)),
    ];
    final token = (await alice.credentials.sendToken(id, everyone))!;

    final results = await alice.transport.send(
      [
        Gv2SendEntry(
          token: token.token,
          recipients: [alice.accountId, bob.accountId],
          envelope: _random(256),
        ),
      ],
    );
    expect(results.single.ok, isTrue);
    expect(results.single.delivered, 2);
    expect(results.single.unknownRecipients, isEmpty);
    expect(results.single.deleted, isEmpty);

    // The same token names the two accounts and nobody else.
    final names = await alice.transport.names(
        token: token.token, recipients: [alice.accountId, bob.accountId]);
    expect(names[gv2Hex(alice.accountId)], alice.displayName);
    expect(names[gv2Hex(bob.accountId)], bob.displayName);

    // A token for bob alone does not open a send to both.
    final bobOnly = (await alice.credentials
        .sendToken(id, [gv2Hex(bob.ciphertextIn(masterKey))]))!;
    final refused = await alice.transport.send([
      Gv2SendEntry(
        token: bobOnly.token,
        recipients: [alice.accountId, bob.accountId],
        envelope: _random(64),
      ),
    ]);
    expect(refused.single.ok, isFalse);
    expect(refused.single.error, 'invalid_token');
    expect(refused.single.delivered, 0);
  }, skip: skip);

  test('bob verifies the same endorsements against his own member list',
      () async {
    expect(await bob.credentials.refreshEndorsements(id),
        Gv2EndorsementOutcome.stored);
    final mine = {
      for (final e in await bob.store.endorsements(id)) e.ciphertext: e.endorsement,
    };
    final hers = {
      for (final e in await alice.store.endorsements(id))
        e.ciphertext: e.endorsement,
    };
    // The response is the same whoever asks.
    expect(mine, hers);
  }, skip: skip);

  test('a device that is behind is told so instead of trusting the server list',
      () async {
    // Mallory-free variant of "the server's members differ from mine": a
    // third store that still holds revision 0 asks for endorsements.
    final behind = _Device('behind', _server ?? '');
    addTearDown(behind.dispose);
    // Same account as alice (her keys), but an older view of the group.
    final stale = Gv2Credentials(
      store: behind.store,
      transport: alice.transport,
      snowId: () async => alice.snowId,
      trustedKeys: gv2TrustedServerKeysFor('dev')!,
    );
    final keys = await alice.credentials.serverKeys();
    await behind.store.saveServerKeys(
        serverPublicParams: keys.serverPublicParams,
        headPublicKey: keys.headPublicKey);
    final snapshot = await alice.transport.snapshot(
      groupId: groupId,
      presentation: await alice.credentials.presentation(masterKey),
      at: 0,
    );
    await behind.store.insertAnchored(
      groupId: groupId,
      masterKey: masterKey,
      myCiphertext: alice.ciphertextIn(masterKey),
      protocolVersion: gv2ProtocolVersion,
      revision: 0,
      chain: snapshot.state.chain,
      stateHash: gv2StateHash(snapshot.state),
      membership: Gv2Membership.awaitingConfirm,
    );
    await behind.store.installState(state: snapshot.state);
    expect(await stale.refreshEndorsements(id),
        Gv2EndorsementOutcome.revisionDiffers);
    expect(await behind.store.endorsements(id), isEmpty);
  }, skip: skip);

  test('Gv2Sync: alice invites mallory; every device follows the real log',
      () async {
    // Alice submits the invite and advances her own store.
    final before = (await alice.store.loadState(id))!;
    final malloryInvite = Gv2SigningKey.generate();
    final signed = gv2SignEntry(
      state: before,
      groupId: groupId,
      draft: Gv2EntryDraft(
        version: gv2ProtocolVersion,
        revision: before.revision + 1,
        prevChain: before.chain,
        actor: alice.ciphertextIn(masterKey),
        actions: [
          Gv2Invite(mallory.ciphertextIn(masterKey), malloryInvite.publicKey),
        ],
        memberPayload: Uint8List(0),
        titlePayload: Uint8List(0),
      ),
      key: await alice.identity.deriveGroupMemberKey(groupId),
    );
    final head = await alice.transport.change(
      groupId: groupId,
      presentation: await alice.credentials.presentation(masterKey),
      entry: gv2EncodeEntry(signed.entry),
    );
    await alice.store.advance(from: before, to: signed.next, headSig: head.headSig);

    // Alice has nothing to fetch; her group's title commits to this server.
    final own = await alice.sync.sync(id);
    expect(own.status, Gv2SyncStatus.upToDate);
    expect(await alice.sync.titleMatchesServerKeys(id), isTrue);

    // Bob is one entry behind and verifies it himself.
    final bobs = await bob.sync.sync(id);
    expect(bobs.status, Gv2SyncStatus.advanced);
    expect(bobs.applied.single.revision, signed.next.revision);
    expect(bobs.membership, Gv2Membership.awaitingConfirm);
    expect((await bob.store.group(id))!.chain, signed.next.chain);

    // Mallory holds only what the 1:1 invite carries.
    await mallory.store.insertAnchored(
      groupId: groupId,
      masterKey: masterKey,
      myCiphertext: mallory.ciphertextIn(masterKey),
      protocolVersion: gv2ProtocolVersion,
      revision: signed.next.revision,
      chain: signed.next.chain,
      stateHash: signed.entry.stateHashAfter,
      membership: Gv2Membership.invited,
      inviteSeed: malloryInvite.seed,
      invitedBySnowId: alice.snowId,
    );
    final hers = await mallory.sync.sync(id);
    expect(hers.status, Gv2SyncStatus.upToDate);
    expect(hers.membership, Gv2Membership.invited);
    final row = (await mallory.store.group(id))!;
    expect(row.stateLoaded, isTrue);
    expect(row.title, 'Dev server round trip');
    expect(headVerifies(Gv2Head(
        revision: row.revision, chain: row.chain, headSig: row.headSig!)), isTrue);
  }, skip: skip);

  test('Gv2Sync: member checks confirm the real accounts behind the members',
      () async {
    final summary = await mallory.sync.checkMembers(id);
    expect(summary.confirmed, 2);
    expect(summary.unconfirmed, 0);
    final confirmed = await mallory.store.confirmedMembers(id);
    expect(confirmed.map((m) => m.snowId).toSet(), {alice.snowId, bob.snowId});
    expect(
        confirmed.singleWhere((m) => m.snowId == alice.snowId).accountPublicKey,
        alice.accountPub);
    // The pending invite is her own.
    expect((await mallory.store.pendingInvites(id)).single.snowId, mallory.snowId);
  }, skip: skip);

  test('Gv2Sync: a device told an anchor the server cannot back stores nothing',
      () async {
    final lied = _Device('lied', _server ?? '');
    addTearDown(lied.dispose);
    final keys = await alice.credentials.serverKeys();
    await lied.store.saveServerKeys(
        serverPublicParams: keys.serverPublicParams,
        headPublicKey: keys.headPublicKey);
    final row = (await mallory.store.group(id))!;
    // Mallory's account, but an "invite" whose state hash is made up.
    await lied.store.insertAnchored(
      groupId: groupId,
      masterKey: masterKey,
      myCiphertext: mallory.ciphertextIn(masterKey),
      protocolVersion: gv2ProtocolVersion,
      revision: row.revision,
      chain: row.chain,
      stateHash: _random(32),
      membership: Gv2Membership.invited,
      inviteSeed: _random(32),
    );
    final sync = Gv2Sync(
      store: lied.store,
      transport: mallory.transport,
      credentials: mallory.credentials,
      pinnedAccountKey: (_) async => null,
    );
    expect((await sync.sync(id)).status, Gv2SyncStatus.snapshotMismatch);
    expect((await lied.store.group(id))!.stateLoaded, isFalse);
    expect(await lied.store.memberRows(id), isEmpty);
  }, skip: skip);

  test('a deletion proof with a wrong clock is refused; the account survives',
      () async {
    expect(await mallory.deleteAccount(clockErrorMs: 3600 * 1000), 400);
    // Still able to fetch credentials: the account exists.
    await mallory.credentials.renew();
  }, skip: skip);

  test('the owner ends the group', () async {
    final state = (await alice.store.loadState(id))!;
    final signed = gv2SignEntry(
      state: state,
      groupId: groupId,
      draft: Gv2EntryDraft(
        version: gv2ProtocolVersion,
        revision: state.revision + 1,
        prevChain: state.chain,
        actor: alice.ciphertextIn(masterKey),
        actions: const [Gv2DeleteGroup()],
        memberPayload: Uint8List(0),
        titlePayload: Uint8List(0),
      ),
      key: await alice.identity.deriveGroupMemberKey(groupId),
    );
    final head = await alice.transport.change(
      groupId: groupId,
      presentation: await alice.credentials.presentation(masterKey),
      entry: gv2EncodeEntry(signed.entry),
    );
    expect(headVerifies(head), isTrue);
    await alice.store.advance(
      from: state,
      to: signed.next,
      headSig: head.headSig,
      membership: Gv2Membership.ended,
    );
    // An ended group issues no endorsements.
    await expectLater(
      alice.transport.endorsements(
          groupId: groupId,
          presentation: await alice.credentials.presentation(masterKey)),
      throwsA(isA<Gv2ApiException>().having((e) => e.status, 'status', 403)),
    );
  }, skip: skip);

  test('accounts are deleted with their own signed proof', () async {
    for (final device in List.of(registered)) {
      expect(await device.deleteAccount(), 200, reason: device.name);
      registered.remove(device);
      await device.dispose();
    }
  }, skip: skip);
}
