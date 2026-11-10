/// @file        verified_identity_store_test.dart
/// @description B-2 VerifiedIdentityStore — lazy legacy-pin migration behind
///              the single `ready` gate (bare / `:device` / both / corrupt /
///              interrupted / locked keychain), latch persistence across
///              remove(), invite-link pinning, and one-time IK seeding.
///              Uses the in-memory SecureStorageService fake.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-10
/// @lastUpdated 2026-11-10
///
/// @functions
///  - main(): migration + latch + seeding tests
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/crypto/identity_admission.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/crypto/verified_identity_store.dart';

import 'identity_test_support.dart';

const _snowA = 'snow0123456789abcdef0123456789abcdef';
const _snowB = 'snowfedcba9876543210fedcba9876543210';
const _dev = '3f2a9c1e-5b7d-4e8a-9c21-7d4e5f6a8b90';

Uint8List _key(int b) => Uint8List.fromList(List.filled(32, b));
String _b64(int b) => base64Encode(_key(b));

InMemorySecureStorage _unlocked() =>
    InMemorySecureStorage()..data['snow_chat_id'] = _snowB;

void main() {
  // These suites exercise the alpha-only legacy (unbound / TOFU) policy, which
  // the default build configuration disables. Mandatory-binding behaviour is
  // covered separately in identity_binding_mandatory_test.dart.
  setUpAll(() => IdentityAdmission.debugAllowUnboundOverride = true);
  tearDownAll(() => IdentityAdmission.debugAllowUnboundOverride = null);

  group('legacy pin migration', () {
    test('bare pin → record, marker written, legacy deleted', () async {
      final s = _unlocked()..data['signal_identity_pin:$_snowA'] = _b64(1);
      final store = VerifiedIdentityStore(s);
      final rec = await store.get(_snowA);
      expect(rec, isNotNull);
      expect(rec!.ed25519, _key(1));
      expect(rec.bound, isFalse);
      expect(rec.deviceId, isNull);
      expect(s.data[VerifiedIdentityStore.versionMarkerKey], '1');
      expect(s.data.containsKey('signal_identity_pin:$_snowA'), isFalse);
      expect(s.data.containsKey('verified_identity_v1:$_snowA'), isTrue);
    });

    test(':device pin → record with deviceId', () async {
      final s = _unlocked()..data['signal_identity_pin:$_snowA:$_dev'] = _b64(2);
      final rec = await VerifiedIdentityStore(s).get(_snowA);
      expect(rec!.ed25519, _key(2));
      expect(rec.deviceId, _dev);
      expect(s.data.keys.where((k) => k.startsWith('signal_identity_pin:')),
          isEmpty);
    });

    test('both bare and :device → the X3DH (:device) key wins', () async {
      final s = _unlocked()
        ..data['signal_identity_pin:$_snowA'] = _b64(3)
        ..data['signal_identity_pin:$_snowA:$_dev'] = _b64(4);
      final rec = await VerifiedIdentityStore(s).get(_snowA);
      expect(rec!.ed25519, _key(4));
      expect(rec.deviceId, _dev);
    });

    test('corrupt legacy entry is skipped; others still migrate', () async {
      final s = _unlocked()
        ..data['signal_identity_pin:$_snowA'] = 'not-base64!!'
        ..data['signal_identity_pin:$_snowB'] = _b64(5);
      final store = VerifiedIdentityStore(s);
      expect(await store.get(_snowA), isNull);
      expect((await store.get(_snowB))!.ed25519, _key(5));
      expect(s.data[VerifiedIdentityStore.versionMarkerKey], '1');
    });

    test('interrupted (readAll throws): no marker, per-peer fallback works, '
        'next launch completes', () async {
      final s = _unlocked()
        ..data['signal_identity_pin:$_snowA:$_dev'] = _b64(6)
        ..failReadAll = true;
      final store = VerifiedIdentityStore(s);
      // Without the device hint the :device slot is unreachable.
      expect(await store.get(_snowA), isNull);
      store.clearCache();
      final rec = await store.get(_snowA, legacyDeviceIdHint: _dev);
      expect(rec!.ed25519, _key(6));
      expect(s.data[VerifiedIdentityStore.versionMarkerKey], isNull);
      // New record was written before any marker / delete.
      expect(s.data.containsKey('verified_identity_v1:$_snowA'), isTrue);

      // "Next launch": enumeration works → marker + cleanup, record intact.
      s.failReadAll = false;
      final store2 = VerifiedIdentityStore(s);
      final rec2 = await store2.get(_snowA);
      expect(rec2!.ed25519, _key(6));
      expect(s.data[VerifiedIdentityStore.versionMarkerKey], '1');
      expect(s.data.containsKey('signal_identity_pin:$_snowA:$_dev'), isFalse);
    });

    test('locked keychain (probe unreadable): enumeration skipped, bare '
        'fallback still answers', () async {
      final s = InMemorySecureStorage()
        ..data['signal_identity_pin:$_snowA'] = _b64(7)
        ..failReadsFor.add('snow_chat_id');
      final store = VerifiedIdentityStore(s);
      final rec = await store.get(_snowA);
      expect(rec!.ed25519, _key(7));
      expect(s.data[VerifiedIdentityStore.versionMarkerKey], isNull);
    });

    test('migration never overwrites a record written by the new code', () async {
      final s = _unlocked()..data['signal_identity_pin:$_snowA'] = _b64(8);
      final newRec = VerifiedIdentityRecord(
        snowId: _snowA,
        identityKey: _key(9),
        ed25519: _key(10),
        updatedAt: 1,
      );
      s.data['verified_identity_v1:$_snowA'] = jsonEncode(newRec.toJson());
      final rec = await VerifiedIdentityStore(s).get(_snowA);
      expect(rec!.ed25519, _key(10));
    });

    test('corrupt new record is treated as absent but the latch still holds',
        () async {
      final s = _unlocked()
        ..data[VerifiedIdentityStore.versionMarkerKey] = '1'
        ..data['verified_identity_v1:$_snowA'] = '{not json'
        ..data['identity_bound_latch:$_snowA'] = '123';
      final store = VerifiedIdentityStore(s);
      expect(await store.get(_snowA), isNull);
      expect(await store.latchedEpoch(_snowA), 123);
    });
  });

  group('latch + pins', () {
    test('remove() drops the record but keeps the latch', () async {
      final s = _unlocked()..data[VerifiedIdentityStore.versionMarkerKey] = '1';
      final store = VerifiedIdentityStore(s);
      await store.put(VerifiedIdentityRecord(
          snowId: _snowA, identityKey: _key(1), updatedAt: 1));
      await store.raiseLatch(_snowA, 50);
      await store.raiseLatch(_snowA, 10); // never lowers
      await store.remove(_snowA);
      expect(await store.get(_snowA), isNull);
      expect(await VerifiedIdentityStore(s).latchedEpoch(_snowA), 50);
    });

    test('invite-link pin requires a key that derives the snowId and latches',
        () async {
      final sk = ed.SigningKey(seed: _key(33));
      final pub = Uint8List.fromList(sk.verifyKey.toList());
      final snow = KeyDerivation.deriveSnowChatId(pub);
      final s = _unlocked()..data[VerifiedIdentityStore.versionMarkerKey] = '1';
      final store = VerifiedIdentityStore(s);
      expect(await store.pinFromInviteLink(_snowA, pub), isFalse);
      expect(await store.pinFromInviteLink(snow, pub), isTrue);
      expect((await store.get(snow))!.accountPublicKey, pub);
      expect(await store.latchedEpoch(snow), 0);
    });

    test('IK seeding fills unbound records once and is not repeated', () async {
      final s = _unlocked()..data[VerifiedIdentityStore.versionMarkerKey] = '1';
      final store = VerifiedIdentityStore(s);
      await store.put(VerifiedIdentityRecord(
          snowId: _snowA, ed25519: _key(1), updatedAt: 1));
      await store.seedLegacyIdentityKeys({_snowA: _key(2), _snowB: _key(3)});
      expect((await store.get(_snowA))!.identityKey, _key(2));
      expect((await store.get(_snowB))!.identityKey, _key(3));

      await store.remove(_snowB);
      await store.seedLegacyIdentityKeys({_snowB: _key(3)});
      expect(await store.get(_snowB), isNull);
    });
  });
}
