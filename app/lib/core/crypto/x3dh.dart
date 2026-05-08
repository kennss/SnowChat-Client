/// @file        x3dh.dart
/// @description X3DH (Extended Triple Diffie-Hellman) key agreement protocol. Used for asynchronous session establishment
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-05-05 (P3 defense: domain-separate HKDF info — SnowChat_X3DH_4DH vs _5DH; BREAKING CHANGE for new sessions with v248- peers)
///
/// @functions
///  - X3DHResult: X3DH session establishment result (shared secret + ephemeral public key)
///  - X3DH.initiateSession(): Alice initiates a session using Bob's PreKey bundle
///  - X3DH.receiveSession(): Bob establishes a session from Alice's initial message

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'x25519.dart';
import 'hkdf.dart';

/// Result of the X3DH key agreement (initiator side).
class X3DHResult {
  /// 32-byte shared secret derived from X3DH.
  final Uint8List sharedSecret;

  /// Alice's ephemeral public key, to be sent to Bob in the initial message.
  final Uint8List ephemeralPublicKey;

  const X3DHResult({
    required this.sharedSecret,
    required this.ephemeralPublicKey,
  });
}

/// X3DH info strings used in HKDF for domain separation.
///
/// P3 defense-in-depth (2026-05-05): split the unified info string into
/// 4DH/5DH variants so that a silent fall from the OPK path to the no-OPK
/// path produces an *immediate* AEAD verify failure on the very first
/// message, instead of silently deriving a different shared secret and
/// passing all of X3DH while making every Double Ratchet message
/// undecryptable forever. After P0 client fail-loud at
/// signal_protocol_service.dart:707 this fall is supposed to be impossible,
/// but the cost of the guard is zero and the cost of being wrong is the
/// "long-idle first-call decrypt fails permanently" UX we just fixed.
///
/// BREAKING CHANGE: this info string change makes new clients incompatible
/// with peers running v248 or earlier when establishing a *new* X3DH
/// session. Existing Double Ratchet sessions (already-derived shared
/// secrets) keep working because the ratchet does not re-run HKDF with
/// this info. Roll out to all paired devices in one batch.
final Uint8List _x3dhInfo4DH =
    Uint8List.fromList(utf8.encode('SnowChat_X3DH_4DH'));
final Uint8List _x3dhInfo5DH =
    Uint8List.fromList(utf8.encode('SnowChat_X3DH_5DH'));

/// 32 zero bytes prepended to DH outputs per the Signal spec
/// (used as a padding prefix before concatenation).
final Uint8List _x3dhPad = Uint8List(32)..fillRange(0, 32, 0xFF);

/// Extended Triple Diffie-Hellman key agreement protocol.
///
/// Implements the Signal Protocol X3DH specification for asynchronous
/// session establishment between two parties.
///
/// DH calculations:
/// - DH1 = DH(IK_A, SPK_B)  — Alice's identity key + Bob's signed prekey
/// - DH2 = DH(EK_A, IK_B)   — Alice's ephemeral + Bob's identity key
/// - DH3 = DH(EK_A, SPK_B)  — Alice's ephemeral + Bob's signed prekey
/// - DH4 = DH(EK_A, OPK_B)  — Alice's ephemeral + Bob's one-time prekey (optional)
/// - SK  = HKDF(0xFF*32 || DH1 || DH2 || DH3 [|| DH4])
class X3DH {
  /// Alice initiates a session using Bob's prekey bundle.
  ///
  /// All keys must be X25519 format (not Ed25519).
  ///
  /// Returns [X3DHResult] containing the shared secret and the ephemeral
  /// public key that must be sent to Bob.
  static X3DHResult initiateSession({
    required Uint8List identityKeyPrivate,
    required Uint8List remoteIdentityKey,
    required Uint8List remoteSignedPreKey,
    Uint8List? remoteOneTimePreKey,
  }) {
    // Generate ephemeral key pair
    final ephemeral = X25519KeyPair.generate();

    // Compute DH values
    final dh1 = x25519Dh(identityKeyPrivate, remoteSignedPreKey);
    final dh2 = x25519Dh(ephemeral.privateKey, remoteIdentityKey);
    final dh3 = x25519Dh(ephemeral.privateKey, remoteSignedPreKey);

    // Security: never log private keys, DH outputs, or shared secrets

    // Concatenate: 0xFF*32 || DH1 || DH2 || DH3 [|| DH4]
    final hasOpk = remoteOneTimePreKey != null;
    final dhLen = 32 + 32 + 32 + 32 + (hasOpk ? 32 : 0);
    final dhConcat = Uint8List(dhLen);
    var offset = 0;

    dhConcat.setAll(offset, _x3dhPad);
    offset += 32;
    dhConcat.setAll(offset, dh1);
    offset += 32;
    dhConcat.setAll(offset, dh2);
    offset += 32;
    dhConcat.setAll(offset, dh3);
    offset += 32;

    if (hasOpk) {
      final dh4 = x25519Dh(ephemeral.privateKey, remoteOneTimePreKey!);
      dhConcat.setAll(offset, dh4);
    }

    // Derive shared secret using HKDF
    final sharedSecret = hkdfDerive(
      ikm: dhConcat,
      salt: Uint8List(32), // zero salt per Signal spec
      info: hasOpk ? _x3dhInfo5DH : _x3dhInfo4DH,
      length: 32,
    );

    return X3DHResult(
      sharedSecret: sharedSecret,
      ephemeralPublicKey: ephemeral.publicKey,
    );
  }

  /// Bob receives Alice's initial message and derives the same shared secret.
  ///
  /// All keys must be X25519 format.
  static Uint8List receiveSession({
    required Uint8List identityKeyPrivate,
    required Uint8List signedPreKeyPrivate,
    Uint8List? oneTimePreKeyPrivate,
    required Uint8List remoteIdentityKey,
    required Uint8List remoteEphemeralKey,
  }) {
    // Mirror DH calculations from Alice's perspective
    final dh1 = x25519Dh(signedPreKeyPrivate, remoteIdentityKey);
    final dh2 = x25519Dh(identityKeyPrivate, remoteEphemeralKey);
    final dh3 = x25519Dh(signedPreKeyPrivate, remoteEphemeralKey);

    // Security: never log private keys, DH outputs, or shared secrets

    final hasOpk = oneTimePreKeyPrivate != null;
    final dhLen = 32 + 32 + 32 + 32 + (hasOpk ? 32 : 0);
    final dhConcat = Uint8List(dhLen);
    var offset = 0;

    dhConcat.setAll(offset, _x3dhPad);
    offset += 32;
    dhConcat.setAll(offset, dh1);
    offset += 32;
    dhConcat.setAll(offset, dh2);
    offset += 32;
    dhConcat.setAll(offset, dh3);
    offset += 32;

    if (hasOpk) {
      final dh4 = x25519Dh(oneTimePreKeyPrivate!, remoteEphemeralKey);
      dhConcat.setAll(offset, dh4);
    }

    final sk = hkdfDerive(
      ikm: dhConcat,
      salt: Uint8List(32),
      info: hasOpk ? _x3dhInfo5DH : _x3dhInfo4DH,
      length: 32,
    );
    return sk;
  }
}

