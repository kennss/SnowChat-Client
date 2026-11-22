/// @file        gv2_credentials_test.dart
/// @description Gv2Credentials without a server: the transport is a fake that
///              answers with values the SERVER's libsignal produced
///              (native/snowchat_zkgroup/tests/vectors/zk_vectors.json), the
///              zkgroup calls are the real native ones and the store is a
///              real in-memory database. Covers: fetching and verifying
///              credentials once and reusing them, topping them up, the
///              server keys this build trusts against stored and published
///              ones, endorsements accepted only for this device's own
///              list of members, and send tokens for subsets.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-20 (P5.3: the server keys are the build's; what the server publishes is only compared. P5.2: device clocks behind the server's)
///
/// @functions
///  - main(): the test groups below.
///  - _FakeTransport: scripted answers and call counts.
///  - _Fixture: database, store, transport, clock and the vector's group.
///
/// Notes:
///  - The clock is the vector file's `now`, so the vectors never expire.
///  - A presentation is random and can only be checked by a server; that is
///    done in test/integration/gv2_dev_server_test.dart.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_credentials.dart';
import 'package:snowchat/core/group_v2/gv2_store.dart';
import 'package:snowchat/core/group_v2/gv2_transport.dart';
import 'package:snowchat/core/group_v2/gv2_trusted_keys.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';

import 'gv2_test_support.dart';

const _vectorsPath = '../native/snowchat_zkgroup/tests/vectors/zk_vectors.json';
const _day = 86400;

class _FakeTransport extends Fake implements Gv2Transport {
  Gv2ServerKeysResponse keys;
  Object? keysError;
  Gv2IssuedCredentials? credentials;
  Gv2EndorsementsResponse? endorsementsAnswer;
  Object? credentialsError;

  int keyFetches = 0;
  int credentialFetches = 0;
  final List<Uint8List> presentationsSeen = [];

  _FakeTransport(this.keys);

  @override
  Future<Gv2ServerKeysResponse> fetchServerKeys() async {
    keyFetches++;
    if (keysError != null) throw keysError!;
    return keys;
  }

  @override
  Future<Gv2IssuedCredentials> fetchCredentials() async {
    credentialFetches++;
    if (credentialsError != null) throw credentialsError!;
    return credentials!;
  }

  @override
  Future<Gv2EndorsementsResponse> endorsements({
    required Uint8List groupId,
    required Uint8List presentation,
  }) async {
    presentationsSeen.add(presentation);
    return endorsementsAnswer!;
  }
}

class _Fixture {
  final Map<String, dynamic> v =
      jsonDecode(File(_vectorsPath).readAsStringSync()) as Map<String, dynamic>;
  final SnowDatabase db = SnowDatabase(NativeDatabase.memory());
  late final Gv2Store store = db.gv2Store;
  late int now = v['now'] as int;
  late final int today = now - now % _day;

  Uint8List b(String field, [Map<String, dynamic>? of]) =>
      base64Decode((of ?? v)[field] as String);

  late final Uint8List serverPublicParams = b('serverPublicParams');
  late final Uint8List headPublicKey = gv2TestSha('head key');
  late final Uint8List masterKey = b('masterKey');
  late final Uint8List groupId = b('groupId');
  late final String id = gv2Hex(groupId);
  late final Map<String, dynamic> cred =
      Map<String, dynamic>.from(v['credential'] as Map);
  late final Map<String, dynamic> endo =
      Map<String, dynamic>.from(v['endorsements'] as Map);
  late final List<Map<String, dynamic>> members = [
    for (final m in v['members'] as List) Map<String, dynamic>.from(m as Map),
  ];

  Uint8List accountId(int i) => b('accountId', members[i]);
  String ciphertext(int i) => gv2Hex(b('ciphertext', members[i]));
  String snowIdOf(int i) => 'snow${gv2Hex(accountId(i))}';

  late final _FakeTransport transport = _FakeTransport(Gv2ServerKeysResponse(
    serverPublicParams: serverPublicParams,
    headPublicKey: headPublicKey,
  ))
    ..credentials = Gv2IssuedCredentials(
      salt: b('salt', cred),
      responses: {cred['redemptionTime'] as int: b('response', cred)},
    )
    ..endorsementsAnswer = Gv2EndorsementsResponse(
      revision: 3,
      expiration: endo['expiration'] as int,
      response: b('response', endo),
    );

  String? account;

  /// The keys the build trusts: by default the ones the vectors' server
  /// used.
  late Gv2TrustedServerKeys trusted = Gv2TrustedServerKeys(
    serverPublicParams: serverPublicParams,
    headPublicKey: headPublicKey,
  );

  Gv2Credentials credentials({int isolateThreshold = 256}) => Gv2Credentials(
        store: store,
        transport: transport,
        snowId: () async => account,
        trustedKeys: trusted,
        nowSeconds: () => now,
        isolateThreshold: isolateThreshold,
      );

  _Fixture() {
    account = snowIdOf(0);
  }

  /// Store the vector's group at revision 3 with members [indexes] (this
  /// device is member 0). The store does not verify signatures, so the member
  /// keys and payloads are placeholders.
  Future<void> storeGroup({
    List<int> indexes = const [0, 1, 2, 3, 4, 5],
    Map<int, Uint8List> replaceCiphertext = const {},
  }) async {
    final state = Gv2GroupState(
      version: gv2ProtocolVersion,
      groupId: groupId,
      revision: 3,
      chain: gv2TestSha('chain 3'),
      deleted: false,
      members: SplayTreeMap.of({
        for (final i in indexes)
          (replaceCiphertext[i] == null
              ? ciphertext(i)
              : gv2Hex(replaceCiphertext[i]!)): Gv2MemberState(
            role: i == 0 ? gv2RoleOwner : gv2RoleMember,
            memberPub: gv2TestSha('member key $i'),
            joinedRevision: i == 0 ? 0 : 1,
            memberPayload: gv2TestBytes('payload $i', 146),
          ),
      }),
      titlePayload: gv2TestBytes('title', 332),
    );
    await store.insertAnchored(
      groupId: groupId,
      masterKey: masterKey,
      myCiphertext: gv2Unhex(ciphertext(0)),
      protocolVersion: gv2ProtocolVersion,
      revision: 3,
      chain: state.chain,
      stateHash: gv2StateHash(state),
      membership: Gv2Membership.awaitingConfirm,
    );
    await store.installState(state: state);
  }
}

void main() {
  late _Fixture f;
  setUp(() => f = _Fixture());
  tearDown(() => f.db.close());

  group('credentials', () {
    test('are fetched once, verified, stored and reused', () async {
      final credentials = f.credentials();
      final first = await credentials.presentation(f.masterKey);
      expect(first, isNotEmpty);
      expect(f.transport.keyFetches, 1);
      expect(f.transport.credentialFetches, 1);

      // What is stored is exactly what the server-side client received.
      final row = (await f.store.authCredential(f.account!, f.today))!;
      expect(row.credential, f.b('received', f.cred));
      final keys = (await f.store.serverKeys())!;
      expect(keys.serverPublicParams, f.serverPublicParams);
      expect(keys.headPublicKey, f.headPublicKey);

      // A new object (an app restart) uses the stored credential and keys;
      // it looks once at what the server publishes.
      final restarted = f.credentials();
      f.transport.credentialsError = const Gv2NetworkException();
      final second = await restarted.presentation(f.masterKey);
      expect(f.transport.keyFetches, 2);
      // Presentations are randomized: two for the same group differ.
      expect(second, isNot(first));
    });

    test('are topped up when the stock runs low, at most once an hour',
        () async {
      final credentials = f.credentials();
      await credentials.presentation(f.masterKey);
      expect(f.transport.credentialFetches, 1);
      // Only today is stored (the vector has one day): a top-up is tried.
      await credentials.presentation(f.masterKey);
      expect(f.transport.credentialFetches, 2);
      await credentials.presentation(f.masterKey);
      expect(f.transport.credentialFetches, 2, reason: 'not again so soon');
      f.now += 3600;
      await credentials.presentation(f.masterKey);
      expect(f.transport.credentialFetches, 3);
    });

    test('a failed top-up does not fail the request', () async {
      final credentials = f.credentials();
      await credentials.presentation(f.masterKey);
      for (final error in [
        const Gv2NetworkException(),
        const Gv2ApiException(429, 'rate_limited'),
      ]) {
        f.now += 3600;
        f.transport.credentialsError = error;
        expect(await credentials.presentation(f.masterKey), isNotEmpty);
      }
    });

    test('with a full week in store nothing is fetched', () async {
      final credential = f.b('received', f.cred);
      await f.store.saveServerKeys(
          serverPublicParams: f.serverPublicParams, headPublicKey: f.headPublicKey);
      await f.store.saveAuthCredentials(
        f.account!,
        {for (var d = 0; d < 7; d++) f.today + d * _day: credential},
        pruneBefore: f.today,
      );
      final credentials = f.credentials();
      await credentials.presentation(f.masterKey);
      await credentials.presentation(f.masterKey);
      expect(f.transport.credentialFetches, 0);
      expect(f.transport.keyFetches, 1, reason: 'the one look per run');
    });

    test('concurrent first uses share one fetch', () async {
      final credentials = f.credentials();
      await Future.wait([
        for (var i = 0; i < 5; i++) credentials.presentation(f.masterKey),
      ]);
      expect(f.transport.credentialFetches, 1);
      expect(f.transport.keyFetches, 1);
    });

    test('a response for another account is refused and nothing is stored',
        () async {
      f.account = f.snowIdOf(1);
      await expectLater(f.credentials().presentation(f.masterKey),
          throwsA(isA<Gv2CredentialException>()));
      expect(await f.store.authCredential(f.account!, f.today), isNull);
      // What the server publishes was looked at once (the same keys).
      expect(f.transport.keyFetches, 1);
      expect(f.transport.credentialFetches, 1);
    });

    test('a clock a little behind the server (before its midnight): the '
        'server issues from its own today, and that credential is presented',
        () async {
      f.now = f.today - 2 * 3600; // the device still shows yesterday
      final presentation = await f.credentials().presentation(f.masterKey);
      expect(presentation, isNotEmpty);
      expect(f.transport.credentialFetches, 1);
      // Asked again soon: not fetched for every request.
      final again = f.credentials();
      f.now += 60;
      expect(await again.presentation(f.masterKey), isNotEmpty);
      expect(await again.presentation(f.masterKey), isNotEmpty);
      expect(f.transport.credentialFetches, 2);
      // The clock is set right: today's credential is the one held.
      f.now = f.today + 3600;
      expect(await f.credentials().presentation(f.masterKey), isNotEmpty);
    });

    test('a clock days behind has nothing the server would take: refused, '
        'until it is set right', () async {
      f.now = f.today - 3 * _day;
      await expectLater(f.credentials().presentation(f.masterKey),
          throwsA(isA<Gv2CredentialException>()));
      f.now = f.today + 60;
      expect(await f.credentials().presentation(f.masterKey), isNotEmpty);
    });

    test('a response that only covers past days is refused', () async {
      f.now += 2 * _day;
      await expectLater(f.credentials().presentation(f.masterKey),
          throwsA(isA<Gv2CredentialException>()));
    });

    test('server errors and a missing identity surface as they are', () async {
      f.transport.credentialsError = const Gv2ApiException(401, 'unauthorized');
      await expectLater(f.credentials().presentation(f.masterKey),
          throwsA(isA<Gv2ApiException>()));
      f.account = null;
      await expectLater(
          f.credentials().presentation(f.masterKey), throwsStateError);
    });

    test('stored keys other than the ones this build trusts (a release that '
        'changed them) are replaced, and what was issued under them erased',
        () async {
      // This device holds keys an earlier build trusted, with a credential
      // and endorsements issued under them.
      await f.storeGroup();
      await f.store.saveServerKeys(
          serverPublicParams: gv2TestBytes('old params', 673),
          headPublicKey: gv2TestSha('old head key'));
      await f.store.saveAuthCredentials(
          f.account!, {f.today + _day: gv2TestBytes('old credential', 265)},
          pruneBefore: f.today);
      await f.store.replaceEndorsements(
        groupId: f.id,
        revision: 3,
        expiration: f.today + 2 * _day,
        byCiphertext: {
          for (var i = 0; i < 6; i++) f.ciphertext(i): gv2TestBytes('old $i', 33),
        },
      );

      final presentation = await f.credentials().presentation(f.masterKey);
      expect(presentation, isNotEmpty);
      expect(f.transport.keyFetches, 1);
      expect((await f.store.serverKeys())!.serverPublicParams, f.serverPublicParams);
      expect((await f.store.authCredential(f.account!, f.today))!.credential,
          f.b('received', f.cred));
      expect(await f.store.authCredential(f.account!, f.today + _day), isNull,
          reason: 'issued under the old keys');
      expect(await f.store.endorsements(f.id), isEmpty);
    });

    test('stored keys that differ in one of the two keys alone are replaced '
        'as well', () async {
      for (final (params, head) in [
        (gv2TestBytes('old params', 673), f.headPublicKey),
        (f.serverPublicParams, gv2TestSha('old head key')),
      ]) {
        await f.store.saveServerKeys(serverPublicParams: params, headPublicKey: head);
        await f.store.saveAuthCredentials(
            f.account!, {f.today: gv2TestBytes('old credential', 265)},
            pruneBefore: f.today);
        final keys = await f.credentials().serverKeys();
        expect(keys.serverPublicParams, f.serverPublicParams);
        expect(keys.headPublicKey, f.headPublicKey);
        expect(await f.store.authCredential(f.account!, f.today), isNull);
      }
    });

    test('a server that publishes other keys than this build trusts: '
        'serverKeysDiffer, and its keys are not taken', () async {
      f.transport.keys = Gv2ServerKeysResponse(
        serverPublicParams: gv2TestBytes('other params', 673),
        headPublicKey: gv2TestSha('other head key'),
      );
      final credentials = f.credentials();
      final changes = <bool>[];
      credentials.serverKeysDifferChanges.listen(changes.add);
      expect(credentials.serverKeysDiffer, isFalse);

      // Issued under the trusted keys, so they verify all the same.
      expect(await credentials.presentation(f.masterKey), isNotEmpty);
      await pumpEventQueue();
      expect(credentials.serverKeysDiffer, isTrue);
      expect(changes, [true]);
      final stored = (await f.store.serverKeys())!;
      expect(stored.serverPublicParams, f.serverPublicParams);
      expect(stored.headPublicKey, f.headPublicKey);
      credentials.dispose();
    });

    test('credentials not issued under the trusted keys are refused, and the '
        'stored keys stay the trusted ones', () async {
      f.trusted = Gv2TrustedServerKeys(
        serverPublicParams: gv2TestBytes('other params', 673),
        headPublicKey: gv2TestSha('other head key'),
      );
      final credentials = f.credentials();
      await expectLater(credentials.presentation(f.masterKey),
          throwsA(isA<Gv2CredentialException>()));
      expect(await f.store.authCredential(f.account!, f.today), isNull);
      expect((await f.store.serverKeys())!.serverPublicParams,
          f.trusted.serverPublicParams);
      // The look tells why: the server publishes the vectors' keys.
      expect(f.transport.keyFetches, 1);
      expect(credentials.serverKeysDiffer, isTrue);
    });

    test('while the keys differ the server is looked at again hourly, and a '
        'fixed server clears it', () async {
      f.transport.keys = Gv2ServerKeysResponse(
        serverPublicParams: gv2TestBytes('other params', 673),
        headPublicKey: f.headPublicKey,
      );
      final credentials = f.credentials();
      final changes = <bool>[];
      credentials.serverKeysDifferChanges.listen(changes.add);
      await credentials.serverKeys();
      await pumpEventQueue();
      expect(credentials.serverKeysDiffer, isTrue);

      f.transport.keys = Gv2ServerKeysResponse(
        serverPublicParams: f.serverPublicParams,
        headPublicKey: f.headPublicKey,
      );
      f.now += 1800;
      await credentials.serverKeys();
      await pumpEventQueue();
      expect(credentials.serverKeysDiffer, isTrue, reason: 'not due yet');
      expect(f.transport.keyFetches, 1);

      f.now += 1800;
      await credentials.serverKeys();
      await pumpEventQueue();
      expect(credentials.serverKeysDiffer, isFalse);
      expect(changes, [true, false]);
      expect(f.transport.keyFetches, 2);

      // Agreeing keys are not looked at again in this run.
      f.now += 7 * 3600;
      await credentials.serverKeys();
      await pumpEventQueue();
      expect(f.transport.keyFetches, 2);
    });

    test('a look that gets no answer is tried again after a minute, not on '
        'every call; the trusted keys are used meanwhile', () async {
      f.transport.keysError = const Gv2NetworkException();
      final credentials = f.credentials();
      expect(await credentials.presentation(f.masterKey), isNotEmpty);
      for (var i = 0; i < 3; i++) {
        await credentials.serverKeys();
      }
      await pumpEventQueue();
      expect(f.transport.keyFetches, 1);
      expect(credentials.serverKeysDiffer, isFalse);

      f.transport.keysError = null;
      f.now += 60;
      await credentials.serverKeys();
      await pumpEventQueue();
      expect(f.transport.keyFetches, 2);
      expect(credentials.serverKeysDiffer, isFalse);
    });

    test('renew fetches again on demand', () async {
      final credentials = f.credentials();
      await credentials.presentation(f.masterKey);
      await credentials.renew();
      expect(f.transport.credentialFetches, 2);
    });
  });

  group('endorsements', () {
    Future<Map<String, Uint8List>> stored() async => {
          for (final e in await f.store.endorsements(f.id))
            e.ciphertext: e.endorsement,
        };

    test('are verified against the stored members and kept per member',
        () async {
      await f.storeGroup();
      expect(await f.credentials().refreshEndorsements(f.id),
          Gv2EndorsementOutcome.stored);
      final rows = await stored();
      final expected = f.endo['received'] as List;
      expect(rows.length, 6);
      for (var i = 0; i < 6; i++) {
        expect(rows[f.ciphertext(i)], base64Decode(expected[i] as String),
            reason: 'member $i');
      }
      expect((await f.store.endorsements(f.id)).first.expiration,
          f.endo['expiration']);
      // The request was made with a presentation for this group.
      expect(f.transport.presentationsSeen.single, isNotEmpty);
    });

    test('verify the same way in a worker isolate', () async {
      await f.storeGroup();
      expect(
          await f.credentials(isolateThreshold: 1).refreshEndorsements(f.id),
          Gv2EndorsementOutcome.stored);
      final rows = await stored();
      final expected = f.endo['received'] as List;
      for (var i = 0; i < 6; i++) {
        expect(rows[f.ciphertext(i)], base64Decode(expected[i] as String));
      }
    });

    test('account ids this device already worked out are used as they are',
        () async {
      await f.storeGroup();
      await f.store.saveMemberChecks(f.id, [
        for (var i = 0; i < 6; i++)
          Gv2MemberCheckResult(
            ciphertext: f.ciphertext(i),
            joinedRevision: i == 0 ? 0 : 1,
            state: Gv2MemberCheckState.certificate,
            snowId: f.snowIdOf(i),
          ),
      ]);
      expect(await f.credentials().refreshEndorsements(f.id),
          Gv2EndorsementOutcome.stored);

      // A recorded account that is not the one behind the ciphertext makes
      // the verification fail: the recorded value really is what is used.
      await f.store.saveMemberChecks(f.id, [
        Gv2MemberCheckResult(
          ciphertext: f.ciphertext(2),
          joinedRevision: 1,
          state: Gv2MemberCheckState.certificate,
          snowId: 'snow${'ab' * 16}',
        ),
      ]);
      expect(await f.credentials().refreshEndorsements(f.id),
          Gv2EndorsementOutcome.rosterMismatch);
    });

    test('for another revision are not even examined', () async {
      await f.storeGroup();
      f.transport.endorsementsAnswer = Gv2EndorsementsResponse(
        revision: 4,
        expiration: f.endo['expiration'] as int,
        response: f.b('response', f.endo),
      );
      expect(await f.credentials().refreshEndorsements(f.id),
          Gv2EndorsementOutcome.revisionDiffers);
      expect(await stored(), isEmpty);
    });

    test('for a list of members this device does not hold are refused',
        () async {
      // The server issued for six members; this device knows five.
      await f.storeGroup(indexes: [0, 1, 2, 3, 4]);
      expect(await f.credentials().refreshEndorsements(f.id),
          Gv2EndorsementOutcome.rosterMismatch);
      expect(await stored(), isEmpty);
    });

    test('a member whose ciphertext names no account makes the list unusable',
        () async {
      await f.storeGroup(
          replaceCiphertext: {5: gv2TestBytes('not a ciphertext', 65)});
      expect(await f.credentials().refreshEndorsements(f.id),
          Gv2EndorsementOutcome.rosterUnusable);
      expect(await stored(), isEmpty);
    });

    test('that expired are refused', () async {
      await f.storeGroup();
      f.now = (f.endo['expiration'] as int) + 1;
      // Today's credential for that later day is not what this test is about.
      await f.store.saveServerKeys(
          serverPublicParams: f.serverPublicParams, headPublicKey: f.headPublicKey);
      await f.store.saveAuthCredentials(
        f.account!,
        {
          for (var d = 0; d < 7; d++)
            f.now - f.now % _day + d * _day: f.b('received', f.cred),
        },
        pruneBefore: f.now - f.now % _day,
      );
      expect(await f.credentials().refreshEndorsements(f.id),
          Gv2EndorsementOutcome.rosterMismatch);
    });

    test('need a group whose state is loaded', () async {
      await expectLater(
          f.credentials().refreshEndorsements(f.id), throwsStateError);
    });
  });

  group('send tokens', () {
    late Gv2Credentials credentials;
    setUp(() async {
      await f.storeGroup();
      credentials = f.credentials();
      await credentials.refreshEndorsements(f.id);
    });

    test('equal the ones the server-side client builds for the same subset',
        () async {
      for (final t in f.v['tokens'] as List) {
        final indexes = [for (final i in (t as Map)['members'] as List) i as int];
        final token = (await credentials
            .sendToken(f.id, [for (final i in indexes) f.ciphertext(i)]))!;
        expect(token.token, base64Decode(t['token'] as String),
            reason: 'members $indexes');
        expect(token.expiration, f.endo['expiration']);
      }
    });

    test('do not depend on the order of the recipients', () async {
      final a = await credentials
          .sendToken(f.id, [f.ciphertext(1), f.ciphertext(4), f.ciphertext(2)]);
      final b = await credentials
          .sendToken(f.id, [f.ciphertext(4), f.ciphertext(2), f.ciphertext(1)]);
      expect(a!.token, b!.token);
    });

    test('are not built for someone without an endorsement', () async {
      expect(
          await credentials.sendToken(
              f.id, [f.ciphertext(0), gv2Hex(gv2TestBytes('stranger', 65))]),
          isNull);
    });

    test('are not built from endorsements about to expire', () async {
      f.now = (f.endo['expiration'] as int) - 601;
      expect(await credentials.sendToken(f.id, [f.ciphertext(0)]), isNotNull);
      f.now = (f.endo['expiration'] as int) - 599;
      expect(await credentials.sendToken(f.id, [f.ciphertext(0)]), isNull);
    });

    test('need distinct recipients and a known group', () async {
      expect(() => credentials.sendToken(f.id, const []), throwsArgumentError);
      expect(
          () => credentials.sendToken(f.id, [f.ciphertext(1), f.ciphertext(1)]),
          throwsArgumentError);
      expect(() => credentials.sendToken('ef' * 32, [f.ciphertext(1)]),
          throwsStateError);
    });

    test('a removed member can no longer be addressed', () async {
      final from = (await f.store.loadState(f.id))!;
      final to = from.copy()
        ..revision = 4
        ..chain = gv2TestSha('chain 4')
        ..members.remove(f.ciphertext(5));
      await f.store.advance(
          from: from, to: to, headSig: gv2TestBytes('head 4', 64));
      expect(await credentials.sendToken(f.id, [f.ciphertext(0), f.ciphertext(5)]),
          isNull);
      // The others still can, without asking the server again.
      expect(
          await credentials.sendToken(
              f.id, [for (var i = 0; i < 5; i++) f.ciphertext(i)]),
          isNotNull);
      expect((await f.store.endorsements(f.id)).length, 5);
    });
  });

  test('gv2AccountIdOfSnowId is the 16 bytes behind a snowId', () {
    expect(gv2AccountIdOfSnowId(f.snowIdOf(3)), f.accountId(3));
    expect(() => gv2AccountIdOfSnowId('snowXYZ'), throwsArgumentError);
    expect(() => gv2AccountIdOfSnowId('SNOW${'0' * 32}'), throwsArgumentError);
  });
}
