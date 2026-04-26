/// @file        prekey_bundle.dart
/// @description PreKey bundle creation and management. Generates signed prekeys and one-time prekeys for X3DH session establishment
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - PreKeyBundle: Server-upload PreKey bundle data class
///  - SignedPreKey: Signed prekey data class (keypair + signature)
///  - OneTimePreKey: One-time prekey data class
///  - PreKeyGenerator.generateSignedPreKey(): Generate signed prekey (Ed25519 signature)
///  - PreKeyGenerator.generateOneTimePreKeys(): Generate a batch of one-time prekeys
///  - PreKeyGenerator.buildBundleForUpload(): Build the server-upload bundle JSON

import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' as ed;

import 'x25519.dart';

/// A prekey bundle containing all keys needed for X3DH session establishment.
class PreKeyBundle {
  /// Bob's X25519 identity public key.
  final Uint8List identityKey;

  /// Bob's signed prekey public key (X25519).
  final Uint8List signedPreKey;

  /// Ed25519 signature over the signed prekey, made with Bob's identity key.
  final Uint8List signedPreKeySignature;

  /// ID of the signed prekey (for server tracking).
  final int signedPreKeyId;

  /// Optional one-time prekey public key (X25519).
  final Uint8List? oneTimePreKey;

  /// ID of the one-time prekey.
  final int? oneTimePreKeyId;

  /// Registration ID for the device.
  final int registrationId;

  const PreKeyBundle({
    required this.identityKey,
    required this.signedPreKey,
    required this.signedPreKeySignature,
    required this.signedPreKeyId,
    this.oneTimePreKey,
    this.oneTimePreKeyId,
    required this.registrationId,
  });

  /// Verify the signed prekey signature using the identity public key (Ed25519).
  bool verifySignature(Uint8List identityPublicKeyEd25519) {
    try {
      final verifyKey = ed.VerifyKey(identityPublicKeyEd25519);
      verifyKey.verify(
        signature: ed.Signature(signedPreKeySignature),
        message: signedPreKey,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// A signed prekey with both private and public keys.
class SignedPreKey {
  final int keyId;
  final Uint8List privateKey; // X25519 private
  final Uint8List publicKey; // X25519 public
  final Uint8List signature; // Ed25519 signature over publicKey

  const SignedPreKey({
    required this.keyId,
    required this.privateKey,
    required this.publicKey,
    required this.signature,
  });
}

/// A one-time prekey with both private and public keys.
class OneTimePreKey {
  final int keyId;
  final Uint8List privateKey; // X25519 private
  final Uint8List publicKey; // X25519 public

  const OneTimePreKey({
    required this.keyId,
    required this.privateKey,
    required this.publicKey,
  });
}

/// Generator for PreKeys used in the X3DH protocol.
class PreKeyGenerator {
  /// Generate a signed prekey pair, signed with the Ed25519 identity key.
  ///
  /// [keyId] — numeric ID for this signed prekey.
  /// [identityPrivateKeySeed] — 32-byte Ed25519 private key seed for signing.
  static SignedPreKey generateSignedPreKey(
    int keyId,
    Uint8List identityPrivateKeySeed,
  ) {
    // Generate X25519 key pair for the signed prekey
    final kp = X25519KeyPair.generate();

    // Sign the public key with Ed25519 identity key
    final signingKey = ed.SigningKey(seed: identityPrivateKeySeed);
    final signedMessage = signingKey.sign(kp.publicKey);
    final signature = Uint8List.fromList(signedMessage.signature.toList());

    return SignedPreKey(
      keyId: keyId,
      privateKey: kp.privateKey,
      publicKey: kp.publicKey,
      signature: signature,
    );
  }

  /// Generate a batch of one-time prekey pairs.
  ///
  /// [startId] — starting key ID for the batch.
  /// [count] — number of prekeys to generate.
  static List<OneTimePreKey> generateOneTimePreKeys(int startId, int count) {
    return List.generate(count, (i) {
      final kp = X25519KeyPair.generate();
      return OneTimePreKey(
        keyId: startId + i,
        privateKey: kp.privateKey,
        publicKey: kp.publicKey,
      );
    });
  }

  /// Build a prekey bundle map suitable for uploading to the server.
  ///
  /// Keys are hex-encoded for transport.
  static Map<String, dynamic> buildBundleForUpload({
    required Uint8List identityPublicKey,
    required SignedPreKey signedPreKey,
    required List<OneTimePreKey> oneTimePreKeys,
    required int registrationId,
  }) {
    return {
      'identityKey': _bytesToHex(identityPublicKey),
      'signedPreKey': {
        'keyId': signedPreKey.keyId,
        'publicKey': _bytesToHex(signedPreKey.publicKey),
        'signature': _bytesToHex(signedPreKey.signature),
      },
      'oneTimePreKeys': oneTimePreKeys
          .map((opk) => {
                'keyId': opk.keyId,
                'publicKey': _bytesToHex(opk.publicKey),
              })
          .toList(),
      'registrationId': registrationId,
    };
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Top-level Isolate-safe worker for [PreKeyGenerator.generateOneTimePreKeys].
/// 100 X25519 keypairs (~7.9s on Galaxy S25 FE) — moved off main isolate
/// via `compute()` so UI stays responsive during restore/register flows.
/// X25519KeyPair.generate() is pure Dart (pinenacl) → Isolate-safe by default.
///
/// Args: Record (startId, count).
/// Returns: List<OneTimePreKey> (serializable across isolate boundary).
List<OneTimePreKey> generateOneTimePreKeysIsolateWorker((int, int) args) {
  return PreKeyGenerator.generateOneTimePreKeys(args.$1, args.$2);
}
