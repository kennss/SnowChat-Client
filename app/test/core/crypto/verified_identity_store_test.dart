/// @file        verified_identity_store_test.dart
/// @description B-2 VerifiedIdentityStore — a corrupt record reads as absent
///              while the latch holds, latch persistence across remove(),
///              invite-link pinning, remembering a derive-checked account key
///              only for a peer with no record, the record codec, and the
///              vouched mark (first source kept, kept by remove(), a second
///              instance reads it, a session's latch is no vouch).
///              Uses the in-memory SecureStorageService fake.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-10
/// @lastUpdated 2026-11-22 (no nickname requests — a request names its account when it is made;
///              VouchSource.restored). Earlier 2026-11-21 (nickname requests: vouched once accepted, matched only on the accepted
///              friend list, forgotten after the TTL). Earlier 2026-11-21 (vouch / isVouched). Earlier same day (legacy TOFU removed: no legacy pin migration, IK seeding or readiness gate to test; rememberAccountKey and the record codec instead). Earlier 2026-11-20 (no unbound-admission override). Earlier 2026-11-10
///
/// @functions
///  - main(): record + latch + pin tests
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/crypto/verified_identity_store.dart';

import 'identity_test_support.dart';

const _snowA = 'snow0123456789abcdef0123456789abcdef';
const _dev = '3f2a9c1e-5b7d-4e8a-9c21-7d4e5f6a8b90';

Uint8List _key(int b) => Uint8List.fromList(List.filled(32, b));
String _b64(int b) => base64Encode(_key(b));

void main() {
  group('records', () {
    test('corrupt new record is treated as absent but the latch still holds',
        () async {
      final s = InMemorySecureStorage()
        ..data['verified_identity_v1:$_snowA'] = '{not json'
        ..data['identity_bound_latch:$_snowA'] = '123';
      final store = VerifiedIdentityStore(s);
      expect(await store.get(_snowA), isNull);
      expect(await store.latchedEpoch(_snowA), 123);
    });
  });

  group('latch + pins', () {
    test('remove() drops the record but keeps the latch', () async {
      final s = InMemorySecureStorage();
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
      final store = VerifiedIdentityStore(InMemorySecureStorage());
      expect(await store.pinAccountKey(_snowA, pub), isFalse);
      expect(await store.pinAccountKey(snow, pub), isTrue);
      expect((await store.get(snow))!.accountPublicKey, pub);
      expect(await store.latchedEpoch(snow), 0);
    });

    test('an account key is remembered only when it derives the snowId and '
        'the peer has no record yet', () async {
      final sk = ed.SigningKey(seed: _key(44));
      final pub = Uint8List.fromList(sk.verifyKey.toList());
      final snow = KeyDerivation.deriveSnowChatId(pub);
      final store = VerifiedIdentityStore(InMemorySecureStorage());
      await store.rememberAccountKey(_snowA, pub); // does not derive _snowA
      expect(await store.get(_snowA), isNull);
      await store.rememberAccountKey(snow, pub);
      final rec = await store.get(snow);
      expect(rec!.accountPublicKey, pub);
      expect(rec.bound, isFalse);
      expect(rec.identityKey, isNull);
      expect(rec.ed25519, isNull);

      // An existing record is left as it is.
      final other = KeyDerivation.deriveSnowChatId(_key(9));
      await store.put(VerifiedIdentityRecord(
          snowId: other, deviceId: _dev, updatedAt: 1));
      await store.rememberAccountKey(other, _key(9));
      expect((await store.get(other))!.accountPublicKey, isNull);
    });

    test('the record codec round-trips a bound record and drops unknown keys',
        () {
      final bound = VerifiedIdentityRecord(
        snowId: _snowA,
        accountPublicKey: _key(7),
        deviceId: _dev,
        epoch: 12,
        identityKey: _key(1),
        ed25519: _key(2),
        bindingSignature: Uint8List.fromList(List.filled(64, 3)),
        bound: true,
        updatedAt: 5,
      );
      final json = bound.toJson()..['pendingIk'] = _b64(9);
      final back = VerifiedIdentityRecord.fromJson(json);
      expect(back.bound, isTrue);
      expect(back.epoch, 12);
      expect(back.identityKey, _key(1));
      expect(back.toJson().containsKey('pendingIk'), isFalse);
    });
  });

  group('vouching', () {
    test('a vouch is kept: first source, through remove(), for a second '
        'instance; a latch alone is none', () async {
      final storage = InMemorySecureStorage();
      final store = VerifiedIdentityStore(storage);
      expect(await store.isVouched(_snowA), isFalse);

      // A session proved the key (latch) — the user chose nothing.
      await store.raiseLatch(_snowA, 7);
      expect(await store.isVouched(_snowA), isFalse);

      await store.vouch(_snowA, VouchSource.message);
      await store.vouch(_snowA, VouchSource.safetyNumber);
      expect(storage.data['${VerifiedIdentityStore.vouchedPrefix}$_snowA'],
          'message');
      await store.remove(_snowA);
      expect(await store.isVouched(_snowA), isTrue);
      expect(await VerifiedIdentityStore(storage).isVouched(_snowA), isTrue);
    });

    test('an account restored from the contact backup is vouched for',
        () async {
      final storage = InMemorySecureStorage();
      final store = VerifiedIdentityStore(storage);
      await store.vouch(_snowA, VouchSource.restored);
      expect(await store.isVouched(_snowA), isTrue);
      expect(storage.data['${VerifiedIdentityStore.vouchedPrefix}$_snowA'],
          'restored');
    });

    test('what is not a snowId is never vouched for', () async {
      final storage = InMemorySecureStorage();
      final store = VerifiedIdentityStore(storage);
      await store.vouch('snowXYZ', VouchSource.friendRequest);
      await store.vouch('', VouchSource.friendRequest);
      expect(storage.data.keys.where(
          (k) => k.startsWith(VerifiedIdentityStore.vouchedPrefix)), isEmpty);
      expect(await store.isVouched('snowXYZ'), isFalse);
    });
  });
}
