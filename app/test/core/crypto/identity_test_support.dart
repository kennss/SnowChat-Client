/// @file        identity_test_support.dart
/// @description Shared helpers for the B-2 Identity Binding v1 tests: an
///              in-memory SecureStorageService fake (no platform channels)
///              and a "party" builder that owns a real account key, a real
///              SignalProtocolService (X3DH / Double Ratchet) and a
///              VerifiedIdentityStore — no mocks of the crypto under test.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-10
/// @lastUpdated 2026-11-10
///
/// @functions
///  - InMemorySecureStorage: SecureStorageService fake with failure injection
///  - TestParty.create(): account key + Signal identity + store for one user
///  - TestParty.bindingFor(): sign an Identity Binding v1 with the account key
///  - TestParty.bundle(): a decoded prekey bundle (as SignalSessionManager builds)
///  - TestParty.localBinding(): LocalIdentityBinding for type-2 embedding
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/identity_binding.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/crypto/signal_protocol_service.dart';
import 'package:snowchat/core/crypto/verified_identity_store.dart';
import 'package:snowchat/core/storage/secure_storage.dart';

/// In-memory SecureStorageService. [failReadAll] simulates an Android
/// EncryptedSharedPreferences corrupt entry / iOS enumeration failure;
/// [failReadsFor] makes individual reads throw (BFU-style).
class InMemorySecureStorage extends Fake implements SecureStorageService {
  final Map<String, String> data = {};
  bool failReadAll = false;
  final Set<String> failReadsFor = {};

  @override
  Future<String?> read(String key) async {
    if (failReadsFor.contains(key)) {
      throw StateError('keychain locked');
    }
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => data.containsKey(key);

  @override
  Future<Map<String, String>> readAll() async {
    if (failReadAll) throw StateError('corrupt entry');
    return Map<String, String>.from(data);
  }
}

/// One user: account key (snowId root) + Signal identity + identity store.
class TestParty {
  final ed.SigningKey accountKey;
  final Uint8List accountPub;
  final String snowId;
  final String deviceId;
  final SignalProtocolService signal;
  final VerifiedIdentityStore store;
  final InMemorySecureStorage storage;
  final List<Map<String, dynamic>> oneTimePreKeys;
  final Map<String, dynamic> preKeyBundle;

  TestParty._({
    required this.accountKey,
    required this.accountPub,
    required this.snowId,
    required this.deviceId,
    required this.signal,
    required this.store,
    required this.storage,
    required this.oneTimePreKeys,
    required this.preKeyBundle,
  });

  /// [seedByte] makes the account deterministic per party.
  static Future<TestParty> create({
    required int seedByte,
    required String deviceId,
    int opkCount = 3,
  }) async {
    final accountKey =
        ed.SigningKey(seed: Uint8List.fromList(List.filled(32, seedByte)));
    final accountPub = Uint8List.fromList(accountKey.verifyKey.toList());
    final snowId = KeyDerivation.deriveSnowChatId(accountPub);
    final storage = InMemorySecureStorage();
    final store = VerifiedIdentityStore(storage);
    final signal = SignalProtocolService(identityStore: store);
    await signal.generateIdentityKeyPair();
    await signal.generateSignedPreKey(1);
    final opks = await signal.generateOneTimePreKeys(1, opkCount);
    final bundle = await signal.getPreKeyBundle();
    return TestParty._(
      accountKey: accountKey,
      accountPub: accountPub,
      snowId: snowId,
      deviceId: deviceId,
      signal: signal,
      store: store,
      storage: storage,
      oneTimePreKeys: opks,
      preKeyBundle: bundle,
    );
  }

  Uint8List get identityKey => preKeyBundle['identityKey'] as Uint8List;
  Uint8List get ed25519 => preKeyBundle['identityKeyEd25519'] as Uint8List;

  /// Binding over this party's CURRENT keys (or overrides).
  IdentityBinding bindingFor({
    required int epoch,
    String? deviceIdOverride,
    String? snowIdOverride,
    Uint8List? ikOverride,
    Uint8List? edOverride,
  }) {
    final msg = IdentityBindingV1.buildMessage(
      snowId: snowIdOverride ?? snowId,
      deviceId: deviceIdOverride ?? deviceId,
      epoch: epoch,
      identityKey: ikOverride ?? identityKey,
      ed25519: edOverride ?? ed25519,
    );
    final sig = Uint8List.fromList(accountKey.sign(msg).signature.toList());
    return IdentityBinding(signature: sig, epoch: epoch);
  }

  LocalIdentityBinding localBinding({required int epoch}) {
    final b = bindingFor(epoch: epoch);
    return LocalIdentityBinding(
      snowId: snowId,
      accountPublicKey: accountPub,
      deviceId: deviceId,
      epoch: epoch,
      identityKey: identityKey,
      ed25519: ed25519,
      signature: b.signature,
    );
  }

  /// Decoded bundle as SignalSessionManager hands it to createSession.
  /// [opkIndex] selects a one-time prekey (null → none).
  Map<String, dynamic> bundle({
    IdentityBinding? binding,
    Uint8List? accountPublicKey,
    int? opkIndex = 0,
  }) {
    final spk = preKeyBundle['signedPreKey'] as Map<String, dynamic>;
    return {
      'identityKey': identityKey,
      'identityKeyEd25519': ed25519,
      'signedPreKey': {
        'keyId': spk['keyId'],
        'publicKey': spk['publicKey'],
        'signature': spk['signature'],
      },
      if (opkIndex != null)
        'oneTimePreKey': {
          'keyId': oneTimePreKeys[opkIndex]['keyId'],
          'publicKey': oneTimePreKeys[opkIndex]['publicKey'],
        },
      'registrationId': preKeyBundle['registrationId'],
      'identityBinding': ?binding,
      'accountPublicKey': ?accountPublicKey,
    };
  }
}
