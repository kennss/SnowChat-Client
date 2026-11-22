/// @file        identity_binding_review_test.dart
/// @description B-2 review follow-ups (2026-11-10):
///               H1 account-wide max epoch floor for minting
///               M1 key-change notice: only a bound peer's change
///               M3 self-check recovery by bindingRejectReason (guarded)
///               M4 non-consuming pre-admission — no OPK fetch on rejection
///                  (a forged binding, or none at all)
///               L1 malformed embedded binding → typed badFormat rejection
///               L3 non-canonical signature (S >= L) rejected
///              Uses a fake ApiClient / SocketManager / SessionStore and the
///              real Signal + identity code.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-10
/// @lastUpdated 2026-11-22 (the directory and the bundle are POST /keys/identity/fetch and POST
///              /keys/prekeys/fetch with the snowId in the body; no batch call — the route is gone).
///              Earlier 2026-11-22 (SignalSessionManager takes no socket). Earlier 2026-11-21 (legacy TOFU removed: M1 is the bound-only key-change notice; M2's held queue is gone). Earlier 2026-11-20 (bindings always mandatory: the legacy blocked-notice case is gone, and the
///              M4 legacy key change case is now an unbound directory device refused before any
///              bundle fetch. refreshPeerIdentity: a peer registered again is admitted from the directory and its old session put aside, before a group invite)
///
/// @functions
///  - FakeApiClient: records calls, answers by (method, path) handler
///  - main(): review follow-up tests
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/identity_admission.dart';
import 'package:snowchat/core/crypto/identity_binding.dart';
import 'package:snowchat/core/crypto/identity_binding_exception.dart';
import 'package:snowchat/core/crypto/identity_manager.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/crypto/session_store.dart';
import 'package:snowchat/core/crypto/signal_protocol_service.dart';
import 'package:snowchat/core/crypto/signal_session_manager.dart';
import 'package:snowchat/core/crypto/verified_identity_store.dart';
import 'package:snowchat/core/network/api_client.dart';

import 'identity_test_support.dart';

typedef FakeHandler = Object? Function(dynamic data);

class FakeApiClient extends Fake implements ApiClient {
  final Map<String, FakeHandler> handlers = {};
  final List<String> calls = [];

  Future<Response<T>> _answer<T>(String method, String path, dynamic data) async {
    calls.add('$method $path');
    final h = handlers['$method $path'];
    if (h == null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
            requestOptions: RequestOptions(path: path), statusCode: 404),
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: h(data) as T?,
    );
  }

  @override
  Future<Response<T>> get<T>(String path,
          {Map<String, dynamic>? queryParameters}) =>
      _answer<T>('GET', path, null);

  @override
  Future<Response<T>> post<T>(String path,
          {dynamic data,
          Map<String, dynamic>? queryParameters,
          Options? options}) =>
      _answer<T>('POST', path, data);

  @override
  Future<Response<T>> put<T>(String path, {dynamic data}) =>
      _answer<T>('PUT', path, data);
}


class _FakeSessionStore extends Fake implements SessionStore {}

const _devA = 'aaaaaaaa-1111-4111-8111-111111111111';
const _devB = 'bbbbbbbb-2222-4222-8222-222222222222';
const _devB2 = 'bbbbbbbb-3333-4333-8333-333333333333';

/// A logged-in local account with a real Signal identity, wired into a real
/// SignalSessionManager over [api].
Future<({SignalSessionManager mgr, IdentityManager im, InMemorySecureStorage s})>
    _localAccount(FakeApiClient api, {int seed = 21}) async {
  final s = InMemorySecureStorage();
  final seedBytes = Uint8List.fromList(List.filled(32, seed));
  final pub = Uint8List.fromList(ed.SigningKey(seed: seedBytes).verifyKey);
  s.data['identity_private_key'] = bytesToHexLower(seedBytes);
  s.data['identity_public_key'] = bytesToHexLower(pub);
  s.data['snow_chat_id'] = KeyDerivation.deriveSnowChatId(pub);
  s.data['device_id'] = _devA;
  final store = VerifiedIdentityStore(s);
  final signal = SignalProtocolService(identityStore: store);
  final im = IdentityManager(s)..setSignalService(signal);
  await im.generateSignalIdentityKey();
  final mgr = SignalSessionManager(
    signalService: signal,
    apiClient: api,
    secureStorage: s,
    identityManager: im,
    sessionStore: _FakeSessionStore(),
  );
  return (mgr: mgr, im: im, s: s);
}

Map<String, dynamic> _directoryJson(TestParty p,
        {IdentityBinding? binding, String? deviceId}) =>
    {
      'accountPublicKey': bytesToHexLower(p.accountPub),
      'devices': [
        {
          'deviceId': deviceId ?? p.deviceId,
          'identityKey': base64Encode(p.identityKey),
          'identityKeyEd25519': base64Encode(p.ed25519),
          'identityBinding': binding?.toWireJson(),
        }
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('H1 account-wide max epoch', () {
    late InMemorySecureStorage s;
    late IdentityManager im;
    final ik = Uint8List.fromList(List.filled(32, 3));
    final edk = Uint8List.fromList(List.filled(32, 4));

    setUp(() {
      s = InMemorySecureStorage();
      final seed = Uint8List.fromList(List.filled(32, 9));
      final pub = Uint8List.fromList(ed.SigningKey(seed: seed).verifyKey);
      s.data['identity_private_key'] = bytesToHexLower(seed);
      s.data['identity_public_key'] = bytesToHexLower(pub);
      s.data['snow_chat_id'] = KeyDerivation.deriveSnowChatId(pub);
      im = IdentityManager(s);
    });

    test('fresh install mints strictly above the server account max', () async {
      final far = DateTime.now().millisecondsSinceEpoch + 10000000;
      await im.recordAccountMaxBindingEpoch(far.toString());
      final b = await im.currentIdentityBinding(
          deviceId: _devA, identityKey: ik, ed25519: edk);
      expect(b.epoch, far + 1);
    });

    test('max is monotonic, malformed values ignored', () async {
      await im.recordAccountMaxBindingEpoch('500');
      await im.recordAccountMaxBindingEpoch('100');
      await im.recordAccountMaxBindingEpoch(42); // not a string
      await im.recordAccountMaxBindingEpoch('9223372036854775808');
      expect(await im.accountMaxBindingEpoch(), 500);
    });

    test('a stored binding below the account max is re-minted', () async {
      final b1 = await im.currentIdentityBinding(
          deviceId: _devA, identityKey: ik, ed25519: edk);
      await im.recordAccountMaxBindingEpoch((b1.epoch + 50).toString());
      final b2 = await im.currentIdentityBinding(
          deviceId: _devA, identityKey: ik, ed25519: edk);
      expect(b2.epoch, b1.epoch + 51);
      // Equal to the max (our own) → reused.
      await im.recordAccountMaxBindingEpoch(b2.epoch.toString());
      final b3 = await im.currentIdentityBinding(
          deviceId: _devA, identityKey: ik, ed25519: edk);
      expect(b3.epoch, b2.epoch);
    });

    test('epoch space exhaustion fails closed', () async {
      await im.recordAccountMaxBindingEpoch('9223372036854775807');
      expect(
          () => im.currentIdentityBinding(
              deviceId: _devA, identityKey: ik, ed25519: edk),
          throwsStateError);
    });
  });

  group('M1 key-change notice (bound peers only)', () {
    test('keyChangeNotice: only a bound record whose device or keys differ',
        () {
      final ik1 = Uint8List.fromList(List.filled(32, 1));
      final ik2 = Uint8List.fromList(List.filled(32, 2));
      final ed1 = Uint8List.fromList(List.filled(32, 5));
      final ed2 = Uint8List.fromList(List.filled(32, 6));
      const snow = 'snow0123456789abcdef0123456789abcdef';
      final bound = VerifiedIdentityRecord(
        snowId: snow,
        accountPublicKey: Uint8List.fromList(List.filled(32, 7)),
        deviceId: _devB,
        epoch: 1,
        identityKey: ik1,
        ed25519: ed1,
        bindingSignature: Uint8List(64),
        bound: true,
        updatedAt: 1,
      );
      bool notice(VerifiedIdentityRecord r, String dev, Uint8List ik,
              Uint8List ed) =>
          IdentityAdmission.keyChangeNotice(
              existing: r, deviceId: dev, identityKey: ik, ed25519: ed);
      expect(notice(bound, _devB, ik1, ed1), isFalse, reason: 'same keys');
      expect(notice(bound, _devB2, ik1, ed1), isTrue, reason: 'other device');
      expect(notice(bound, _devB, ik2, ed1), isTrue, reason: 'other IK');
      expect(notice(bound, _devB, ik1, ed2), isTrue, reason: 'other Ed');
      // A record that only pins the account key holds no keys: first keys
      // are no change.
      final pinned = VerifiedIdentityRecord(
        snowId: snow,
        accountPublicKey: Uint8List.fromList(List.filled(32, 7)),
        updatedAt: 1,
      );
      expect(notice(pinned, _devB, ik1, ed1), isFalse);
    });

    test('a reinstall of a bound peer (same account, new device) gives the '
        'device notice; the first binding after an invite pin gives none',
        () async {
      final alice = await TestParty.create(seedByte: 1, deviceId: _devA);
      final bobOld = await TestParty.create(seedByte: 2, deviceId: _devB);
      final bobNew = await TestParty.create(seedByte: 2, deviceId: _devB2);
      final events = <IdentityStoreEvent>[];
      alice.store.events.listen(events.add);

      // The invite link pinned bob's account key; his first binding follows.
      expect(await alice.store.pinAccountKey(bobOld.snowId, bobOld.accountPub),
          isTrue);
      await alice.signal.createSession(
        recipientId: bobOld.snowId,
        deviceId: _devB,
        preKeyBundle: bobOld.bundle(
            binding: bobOld.bindingFor(epoch: 1000),
            accountPublicKey: bobOld.accountPub),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);

      // Bob reinstalls: same account, new device and keys, a newer binding.
      await alice.signal.createSession(
        recipientId: bobNew.snowId,
        deviceId: _devB2,
        preKeyBundle: bobNew.bundle(
            binding: bobNew.bindingFor(epoch: 9000),
            accountPublicKey: bobNew.accountPub),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.map((e) => e.kind), [IdentityEventKind.deviceKeysChanged]);
    });
  });

  group('M3 self-check recovery', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('b2_selfcheck');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (call) async => tmp.path);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      await tmp.delete(recursive: true);
    });

    test('epoch_regression → one re-sign with a higher epoch, then stop',
        () async {
      final api = FakeApiClient();
      final puts = <Map>[];
      api.handlers['PUT /keys/identity-binding'] = (d) {
        puts.add(d as Map);
        return {
          'bindingAccepted': false,
          'bindingRejectReason': 'epoch_regression',
        };
      };
      final a = await _localAccount(api);
      await a.mgr.selfCheckIdentityBinding(
          {'hasIdentityBinding': false, 'identityBindingEpoch': null});
      expect(puts.length, 2);
      final e1 = int.parse((puts[0]['identityBinding'] as Map)['epoch'] as String);
      final e2 = int.parse((puts[1]['identityBinding'] as Map)['epoch'] as String);
      expect(e2, greaterThan(e1));
      // Guarded: a second self-check sends one PUT and no further repair.
      await a.mgr.selfCheckIdentityBinding(
          {'hasIdentityBinding': false, 'identityBindingEpoch': null});
      expect(puts.length, 3);
      expect(api.calls.where((c) => c == 'POST /keys/prekeys'), isEmpty);
    });

    test('missing_keys → one full upload carrying IK + Ed + binding', () async {
      final api = FakeApiClient();
      Map? uploaded;
      api.handlers['PUT /keys/identity-binding'] = (_) => {
            'bindingAccepted': false,
            'bindingRejectReason': 'missing_keys',
          };
      api.handlers['POST /keys/prekeys'] = (d) {
        uploaded = d as Map;
        return {'bindingAccepted': true};
      };
      final a = await _localAccount(api);
      await a.mgr.selfCheckIdentityBinding(
          {'hasIdentityBinding': false, 'identityBindingEpoch': null});
      expect(uploaded, isNotNull);
      expect(uploaded!['identityKey'], isA<String>());
      expect(uploaded!['identityKeyEd25519'], isA<String>());
      expect((uploaded!['identityBinding'] as Map)['version'], 1);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('accepted PUT but server still has no binding → one full upload',
        () async {
      final api = FakeApiClient();
      var posts = 0;
      api.handlers['PUT /keys/identity-binding'] =
          (_) => {'bindingAccepted': true};
      api.handlers['GET /keys/prekey-count'] =
          (_) => {'count': 50, 'hasIdentityBinding': false};
      api.handlers['POST /keys/prekeys'] = (_) {
        posts++;
        return {'bindingAccepted': true};
      };
      final a = await _localAccount(api);
      await a.mgr.selfCheckIdentityBinding(
          {'hasIdentityBinding': false, 'identityBindingEpoch': null});
      await a.mgr.selfCheckIdentityBinding(
          {'hasIdentityBinding': false, 'identityBindingEpoch': null});
      expect(posts, 1);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('M4 non-consuming pre-admission', () {
    test('forged directory binding → rejected with ZERO bundle fetches, then '
        'memoized without network', () async {
      final api = FakeApiClient();
      final bob = await TestParty.create(seedByte: 2, deviceId: _devB);
      final good = bob.bindingFor(epoch: 1000);
      final forged = IdentityBinding(
          signature: Uint8List.fromList(good.signature)..[3] ^= 1,
          epoch: 1000);
      api.handlers['POST /keys/identity/fetch'] = (d) {
        expect(d, {'snowchatId': bob.snowId}, reason: 'the id travels in the body');
        return _directoryJson(bob, binding: forged);
      };
      api.handlers['POST /keys/prekeys/fetch'] = (_) => throw StateError(
          'consuming bundle endpoint must not be called');
      final a = await _localAccount(api);
      await expectLater(a.mgr.ensureSession(bob.snowId),
          throwsA(isA<IdentityBindingInvalidException>()));
      expect(api.calls, ['POST /keys/identity/fetch']);
      await expectLater(a.mgr.ensureSession(bob.snowId),
          throwsA(isA<IdentityBindingInvalidException>()));
      expect(api.calls.length, 1, reason: 'memoized — no further network');
    });

    test('a directory device without a binding → refused before any bundle '
        'fetch', () async {
      final api = FakeApiClient();
      final bob = await TestParty.create(seedByte: 5, deviceId: _devB2);
      final a = await _localAccount(api);
      api.handlers['POST /keys/identity/fetch'] =
          (_) => _directoryJson(bob);
      api.handlers['POST /keys/prekeys/fetch'] = (_) => throw StateError(
          'consuming bundle endpoint must not be called');
      await expectLater(
          a.mgr.ensureSession(bob.snowId),
          throwsA(isA<IdentityBindingInvalidException>().having(
              (e) => e.reason, 'reason', IdentityBindingFailure.bindingRequired)));
      expect(api.calls.where((c) => c == 'POST /keys/prekeys/fetch'),
          isEmpty);
    });
  });

  group('refreshPeerIdentity (before a group invite)', () {
    /// A session with [bob] made the way a first contact makes one.
    Future<void> connect(SignalSessionManager mgr, TestParty bob, int epoch) =>
        mgr.signal.createSession(
          recipientId: bob.snowId,
          deviceId: bob.deviceId,
          preKeyBundle: bob.bundle(
            binding: bob.bindingFor(epoch: epoch),
            accountPublicKey: bob.accountPub,
          ),
        );

    test('the peer registered again with its phrase (a new identity, a newer '
        'binding): the old session is put aside', () async {
      final api = FakeApiClient();
      final bob = await TestParty.create(seedByte: 2, deviceId: _devB);
      final a = await _localAccount(api);
      await connect(a.mgr, bob, 1000);
      expect(await a.mgr.signal.hasSession(bob.snowId, _devB), isTrue);

      final again = await TestParty.create(
        accountSeed: Uint8List.fromList(List.filled(32, 2)),
        deviceId: _devB2,
      );
      expect(again.snowId, bob.snowId);
      api.handlers['POST /keys/identity/fetch'] = (_) =>
          _directoryJson(again, binding: again.bindingFor(epoch: 2000));
      await a.mgr.refreshPeerIdentity(bob.snowId);
      // Looked at first: hasSession() itself puts aside what does not match
      // the bound identity, so it would hide whether the refresh did.
      expect(a.mgr.signal.getRemoteIdentityKey(bob.snowId), again.identityKey);
      expect(await a.mgr.signal.hasSession(bob.snowId, _devB), isFalse);
      // Nothing was consumed: no bundle was fetched.
      expect(api.calls.where((c) => c == 'POST /keys/prekeys/fetch'), isEmpty);
    });

    test('an unchanged peer keeps its session', () async {
      final api = FakeApiClient();
      final bob = await TestParty.create(seedByte: 2, deviceId: _devB);
      final a = await _localAccount(api);
      await connect(a.mgr, bob, 1000);
      api.handlers['POST /keys/identity/fetch'] =
          (_) => _directoryJson(bob, binding: bob.bindingFor(epoch: 1000));
      await a.mgr.refreshPeerIdentity(bob.snowId);
      expect(await a.mgr.signal.hasSession(bob.snowId, _devB), isTrue);
    });

    test('a forged directory entry is refused and the session kept', () async {
      final api = FakeApiClient();
      final bob = await TestParty.create(seedByte: 2, deviceId: _devB);
      final a = await _localAccount(api);
      await connect(a.mgr, bob, 1000);
      final other = await TestParty.create(seedByte: 9, deviceId: _devB2);
      api.handlers['POST /keys/identity/fetch'] = (_) => _directoryJson(
        other,
        binding: IdentityBinding(signature: Uint8List(64), epoch: 3000),
      );
      await expectLater(
        a.mgr.refreshPeerIdentity(bob.snowId),
        throwsA(isA<IdentityBindingInvalidException>()),
      );
      expect(await a.mgr.signal.hasSession(bob.snowId, _devB), isTrue);
    });

    test('a directory that cannot be reached throws, and nothing changes',
        () async {
      final api = FakeApiClient();
      final bob = await TestParty.create(seedByte: 2, deviceId: _devB);
      final a = await _localAccount(api);
      await connect(a.mgr, bob, 1000);
      api.handlers['POST /keys/identity/fetch'] = (_) =>
          throw DioException.connectionError(
            requestOptions: RequestOptions(path: '/keys/identity'),
            reason: 'offline',
          );
      await expectLater(
        a.mgr.refreshPeerIdentity(bob.snowId),
        throwsA(isA<SignalProtocolException>()),
      );
      expect(await a.mgr.signal.hasSession(bob.snowId, _devB), isTrue);
    });
  });

  group('L1 / L3 strict parsing + canonical signatures', () {
    test('embedded binding with non-string fields → null (no TypeError)', () {
      expect(
          EmbeddedIdentityBinding.tryParse({
            'version': 1,
            'accountPublicKey': 123,
            'deviceId': _devA,
            'epoch': '1',
            'ed25519': 'x',
            'sig': 'y',
          }),
          isNull);
      expect(
          EmbeddedIdentityBinding.tryParse({
            'version': 1,
            'accountPublicKey': 'a' * 64,
            'deviceId': _devA,
            'epoch': 1, // number, not decimal string
            'ed25519': 'b' * 64,
            'sig': base64Encode(Uint8List(64)),
          }),
          isNull);
      expect(IdentityBinding.tryParseWire(
              {'sig': base64Encode(Uint8List(64)), 'epoch': 5, 'version': 1}),
          isNull);
    });

    test('malformed embedded binding → typed badFormat rejection on receive',
        () async {
      final alice = await TestParty.create(seedByte: 1, deviceId: _devA);
      final bob = await TestParty.create(seedByte: 2, deviceId: _devB);
      alice.signal.setLocalIdentityBinding(alice.localBinding(epoch: 5000));
      await alice.signal.createSession(
        recipientId: bob.snowId,
        deviceId: _devB,
        preKeyBundle: bob.bundle(
            binding: bob.bindingFor(epoch: 1000),
            accountPublicKey: bob.accountPub),
      );
      final enc = await alice.signal.encryptMessage(
          recipientId: bob.snowId,
          deviceId: _devB,
          plaintext: Uint8List.fromList(utf8.encode('x')));
      final json = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(enc['ciphertext'] as Uint8List)) as Map);
      (json['identityBinding'] as Map)['epoch'] = 5000; // wrong type
      await expectLater(
        bob.signal.decryptMessage(
          senderId: alice.snowId,
          deviceId: _devA,
          ciphertext: Uint8List.fromList(utf8.encode(jsonEncode(json))),
          messageType: 2,
          envelopeDeviceId: _devA,
        ),
        throwsA(isA<IdentityBindingInvalidException>().having(
            (e) => e.reason, 'reason', IdentityBindingFailure.badFormat)),
      );
    });

    test('S + L (malleated, TweetNaCl-acceptable) signature is rejected', () {
      final sk = ed.SigningKey(seed: Uint8List.fromList(List.filled(32, 7)));
      final pub = Uint8List.fromList(sk.verifyKey);
      final snowId = KeyDerivation.deriveSnowChatId(pub);
      final ik = Uint8List.fromList(List.filled(32, 1));
      final edk = Uint8List.fromList(List.filled(32, 2));
      final msg = IdentityBindingV1.buildMessage(
          snowId: snowId, deviceId: _devA, epoch: 3, identityKey: ik, ed25519: edk);
      final sig = Uint8List.fromList(sk.sign(msg).signature);
      final l = (BigInt.one << 252) +
          BigInt.parse('27742317777372353535851937790883648493');
      var s = BigInt.zero;
      for (var i = 63; i >= 32; i--) {
        s = (s << 8) | BigInt.from(sig[i]);
      }
      final s2 = s + l;
      expect(s2.bitLength <= 256, isTrue);
      final mal = Uint8List.fromList(sig);
      var v = s2;
      for (var i = 32; i < 64; i++) {
        mal[i] = (v & BigInt.from(0xff)).toInt();
        v = v >> 8;
      }
      bool check(Uint8List signature) => IdentityBindingV1.verify(
          snowId: snowId,
          accountPublicKey: pub,
          deviceId: _devA,
          epoch: 3,
          identityKey: ik,
          ed25519: edk,
          signature: signature);
      expect(check(sig), isTrue);
      expect(IdentityBindingV1.isCanonicalSignatureScalar(mal), isFalse);
      expect(check(mal), isFalse);
    });
  });
}
