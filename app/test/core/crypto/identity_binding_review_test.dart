/// @file        identity_binding_review_test.dart
/// @description B-2 review follow-ups (2026-11-10):
///               H1 account-wide max epoch floor for minting
///               M1 migrated-Ed weakness + reinstall evidence on promotion
///               M2 blocked notice emitted once + held-message queue skip
///               M3 self-check recovery by bindingRejectReason (guarded)
///               M4 non-consuming pre-admission — no OPK fetch on rejection
///               L1 malformed embedded binding → typed badFormat rejection
///               L3 non-canonical signature (S >= L) rejected
///              Uses a fake ApiClient / SocketManager / SessionStore and the
///              real Signal + identity code.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-10
/// @lastUpdated 2026-11-10
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
import 'package:snowchat/core/crypto/encrypted_message_handler.dart';
import 'package:snowchat/core/crypto/identity_admission.dart';
import 'package:snowchat/core/crypto/identity_binding.dart';
import 'package:snowchat/core/crypto/identity_binding_exception.dart';
import 'package:snowchat/core/crypto/identity_key_changed_exception.dart';
import 'package:snowchat/core/crypto/identity_manager.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/crypto/session_store.dart';
import 'package:snowchat/core/crypto/signal_protocol_service.dart';
import 'package:snowchat/core/crypto/signal_session_manager.dart';
import 'package:snowchat/core/crypto/verified_identity_store.dart';
import 'package:snowchat/core/messaging/message_queue.dart';
import 'package:snowchat/core/network/api_client.dart';
import 'package:snowchat/core/network/socket_manager.dart';
import 'package:snowchat/core/network/file_service.dart';
import 'package:snowchat/core/storage/daos/attachment_dao.dart';
import 'package:snowchat/core/storage/daos/conversation_dao.dart';
import 'package:snowchat/core/storage/daos/message_dao.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/features/chat/providers/expiring_message_manager.dart';

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

class _FakeSocket extends Fake implements SocketManager {
  @override
  Stream<Map<String, dynamic>> get onSenderKeyRequestFailed =>
      const Stream.empty();
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
    socketManager: _FakeSocket(),
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
  // These suites exercise the alpha-only legacy (unbound / TOFU) policy, which
  // the default build configuration disables. Mandatory-binding behaviour is
  // covered separately in identity_binding_mandatory_test.dart.
  setUpAll(() => IdentityAdmission.debugAllowUnboundOverride = true);
  tearDownAll(() => IdentityAdmission.debugAllowUnboundOverride = null);

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

  group('M1 migrated Ed + reinstall evidence', () {
    test('ambiguous device pins migrate no Ed; single pin is legacy-sourced',
        () async {
      const snowX = 'snow0123456789abcdef0123456789abcdef';
      const snowY = 'snowfedcba9876543210fedcba9876543210';
      final s = InMemorySecureStorage()
        ..data['snow_chat_id'] = snowY
        ..data['signal_identity_pin:$snowX:$_devB'] = base64Encode(List.filled(32, 1))
        ..data['signal_identity_pin:$snowX:$_devB2'] = base64Encode(List.filled(32, 2))
        ..data['signal_identity_pin:$snowY:$_devB'] = base64Encode(List.filled(32, 3));
      final store = VerifiedIdentityStore(s);
      expect(await store.get(snowX), isNull);
      final y = await store.get(snowY);
      expect(y!.edLegacySourced, isTrue);
      expect(y.deviceId, _devB);
    });

    test('honest +304 → +305 reinstall: device notice, NOT interception',
        () async {
      final alice = await TestParty.create(seedByte: 1, deviceId: _devA);
      final bobOld = await TestParty.create(seedByte: 2, deviceId: _devB);
      final bobNew = await TestParty.create(seedByte: 2, deviceId: _devB2);
      // Pre-B-2 state: migrated Ed pin + IK seeded with its device.
      await alice.store.put(VerifiedIdentityRecord(
        snowId: bobOld.snowId,
        deviceId: _devB,
        identityKey: bobOld.identityKey,
        ed25519: bobOld.ed25519,
        edLegacySourced: true,
        updatedAt: 1,
      ));
      final events = <IdentityStoreEvent>[];
      alice.store.events.listen(events.add);
      await alice.signal.createSession(
        recipientId: bobNew.snowId,
        deviceId: _devB2,
        preKeyBundle: bobNew.bundle(
            binding: bobNew.bindingFor(epoch: 9000),
            accountPublicKey: bobNew.accountPub),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.map((e) => e.kind),
          [IdentityEventKind.deviceKeysChanged]);
    });

    test('promotionNotice rules', () {
      final ik1 = Uint8List.fromList(List.filled(32, 1));
      final ik2 = Uint8List.fromList(List.filled(32, 2));
      final ed1 = Uint8List.fromList(List.filled(32, 5));
      final ed2 = Uint8List.fromList(List.filled(32, 6));
      VerifiedIdentityRecord rec({
        String? dev,
        Uint8List? ik,
        bool legacyEd = false,
      }) =>
          VerifiedIdentityRecord(
            snowId: 'snow0123456789abcdef0123456789abcdef',
            deviceId: dev,
            identityKey: ik,
            ed25519: ed1,
            edLegacySourced: legacyEd,
            updatedAt: 1,
          );
      // Legacy-sourced Ed differs, IK same → nothing.
      expect(
          IdentityAdmission.promotionNotice(
              existing: rec(dev: _devB, ik: ik1, legacyEd: true),
              deviceId: _devB,
              identityKey: ik1,
              ed25519: ed2),
          isNull);
      // Same device, different IK → interception.
      expect(
          IdentityAdmission.promotionNotice(
              existing: rec(dev: _devB, ik: ik1),
              deviceId: _devB,
              identityKey: ik2,
              ed25519: ed1),
          IdentityEventKind.interceptionSuspected);
      // Unknown legacy device, different IK → interception.
      expect(
          IdentityAdmission.promotionNotice(
              existing: rec(ik: ik1),
              deviceId: _devB,
              identityKey: ik2,
              ed25519: ed1),
          IdentityEventKind.interceptionSuspected);
      // Different device → reinstall evidence.
      expect(
          IdentityAdmission.promotionNotice(
              existing: rec(dev: _devB, ik: ik1),
              deviceId: _devB2,
              identityKey: ik2,
              ed25519: ed1),
          IdentityEventKind.deviceKeysChanged);
    });
  });

  group('M2 held messages', () {
    test('blocked notice fires once across repeated attempts', () async {
      final alice = await TestParty.create(seedByte: 1, deviceId: _devA);
      final old = await TestParty.create(seedByte: 5, deviceId: _devB);
      final re = await TestParty.create(seedByte: 5, deviceId: _devB2);
      alice.store.verifiedLookup = (_) async => true;
      await alice.signal.createSession(
          recipientId: old.snowId, deviceId: _devB, preKeyBundle: old.bundle());
      final events = <IdentityStoreEvent>[];
      alice.store.events.listen(events.add);
      for (var i = 0; i < 3; i++) {
        await expectLater(
          alice.signal.createSession(
              recipientId: old.snowId,
              deviceId: _devB2,
              preKeyBundle: re.bundle(opkIndex: i)),
          throwsA(isA<IdentityKeyChangedException>()),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(events.length, 1);
      expect(events.single.kind, IdentityEventKind.legacyKeyChangeBlocked);
    });

    test('a held envelope is skipped on redelivery until released', () {
      final q = MessageQueue(
        sessionManager: _FakeMgr(),
        e2eeHandler: _FakeHandler(),
        messageDao: _FakeMessageDao(),
        conversationDao: _FakeConversationDao(),
        attachmentDao: _FakeAttachmentDao(),
        fileService: _FakeFileService(),
        expiringManager: _FakeExpiring(),
        database: _FakeDb(),
        apiClient: FakeApiClient(),
        socketManager: _FakeSocket(),
        myIdResolver: () => 'snow0123456789abcdef0123456789abcdef',
      );
      q.holdForReverifyForTesting('m1', 'snowpeer');
      expect(q.heldForReverifyCount, 1);
      q.enqueue({'id': 'm1', 'type': 'e2ee_text'});
      expect(q.depth, 0, reason: 'held id must not be decrypted again');
      q.releaseHeldForPeer('snowpeer');
      expect(q.heldForReverifyCount, 0);
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
      api.handlers['GET /keys/identity/${bob.snowId}'] =
          (_) => _directoryJson(bob, binding: forged);
      api.handlers['GET /keys/prekeys/${bob.snowId}'] = (_) => throw StateError(
          'consuming bundle endpoint must not be called');
      final a = await _localAccount(api);
      await expectLater(a.mgr.ensureSession(bob.snowId),
          throwsA(isA<IdentityBindingInvalidException>()));
      expect(api.calls, ['GET /keys/identity/${bob.snowId}']);
      await expectLater(a.mgr.ensureSession(bob.snowId),
          throwsA(isA<IdentityBindingInvalidException>()));
      expect(api.calls.length, 1, reason: 'memoized — no further network');
    });

    test('verified legacy key change → blocked before any bundle fetch',
        () async {
      final api = FakeApiClient();
      final re = await TestParty.create(seedByte: 5, deviceId: _devB2);
      final a = await _localAccount(api);
      final store = a.mgr.signal.identityStore!;
      store.verifiedLookup = (_) async => true;
      await store.put(VerifiedIdentityRecord(
        snowId: re.snowId,
        deviceId: _devB,
        identityKey: Uint8List.fromList(List.filled(32, 7)),
        updatedAt: 1,
      ));
      api.handlers['GET /keys/identity/${re.snowId}'] =
          (_) => _directoryJson(re);
      await expectLater(a.mgr.ensureSession(re.snowId),
          throwsA(isA<IdentityKeyChangedException>()));
      expect(api.calls.where((c) => c.startsWith('GET /keys/prekeys/')),
          isEmpty);
    });

    test('batch: a rejected member is dropped before the consuming batch call',
        () async {
      final api = FakeApiClient();
      final bob = await TestParty.create(seedByte: 2, deviceId: _devB);
      final forged = IdentityBinding(signature: Uint8List(64), epoch: 1);
      api.handlers['GET /keys/identity/${bob.snowId}'] =
          (_) => _directoryJson(bob, binding: forged);
      final a = await _localAccount(api);
      await a.mgr.ensureSessionBatch([bob.snowId]);
      expect(api.calls.where((c) => c.contains('/batch')), isEmpty);
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

// --- Inert fakes for MessageQueue construction (never invoked) -------------
class _FakeMgr extends Fake implements SignalSessionManager {}

class _FakeHandler extends Fake implements EncryptedMessageHandler {}

class _FakeMessageDao extends Fake implements MessageDao {}

class _FakeConversationDao extends Fake implements ConversationDao {}

class _FakeAttachmentDao extends Fake implements AttachmentDao {}

class _FakeFileService extends Fake implements FileService {}

class _FakeExpiring extends Fake implements ExpiringMessageManager {}

class _FakeDb extends Fake implements SnowDatabase {}

