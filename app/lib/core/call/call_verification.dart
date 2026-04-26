/// @file        call_verification.dart
/// @description DTLS fingerprint Ed25519 signature + SAS 4-digit computation (Phase 8.2 §24.3)
///              Blocks SDP forgery attacks by a malicious signaling server.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - CallVerification.parseFingerprint(sdp): extract a=fingerprint:sha-256 value from SDP
///  - CallVerification.signFingerprint(fp, seed): Ed25519 signature
///  - CallVerification.verifyFingerprint(fp, sig, pubKey): Ed25519 verification
///  - CallVerification.computeSas(localFp, remoteFp): HKDF-SHA256 → 4-digit SAS
///  - CallVerificationException: verification failure exception

import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' as ed;

import '../crypto/hkdf.dart';

class CallVerificationException implements Exception {
  CallVerificationException(this.message);
  final String message;
  @override
  String toString() => 'CallVerificationException: $message';
}

class CallVerification {
  /// Find the `a=fingerprint:sha-256 AB:CD:EF:...` line in the SDP and return the hex value.
  /// If multiple media sections exist, take the first value (all identical due to BUNDLE).
  static String parseFingerprint(String sdp) {
    for (final raw in sdp.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('a=fingerprint:')) {
        final parts = line.split(' ');
        if (parts.length >= 2) {
          return parts[1].trim().toLowerCase();
        }
      }
    }
    throw CallVerificationException('SDP has no a=fingerprint line');
  }

  /// Sign the fingerprint (hex string) with the Ed25519 identity key.
  /// [signingKeySeed]: SignalProtocolService.signingKeySeed
  /// Returns: 64 byte Ed25519 signature.
  static Uint8List signFingerprint({
    required String fingerprint,
    required Uint8List signingKeySeed,
  }) {
    final signingKey = ed.SigningKey.fromSeed(signingKeySeed);
    final message = Uint8List.fromList(utf8.encode(fingerprint));
    final signedMessage = signingKey.sign(message);
    // signedMessage.signature has the raw 64-byte Ed25519 sig
    return Uint8List.fromList(signedMessage.signature);
  }

  /// Verify the remote fingerprint + signature against the remote identity Ed25519 verify key.
  /// Returns false on failure. Caller blocks the call.
  static bool verifyFingerprint({
    required String fingerprint,
    required Uint8List signature,
    required Uint8List remoteVerifyKey,
  }) {
    try {
      final verifyKey = ed.VerifyKey(remoteVerifyKey);
      final message = Uint8List.fromList(utf8.encode(fingerprint));
      // pinenacl API: verifyKey.verify(signature: Signature, message: bytes)
      return verifyKey.verify(
        signature: ed.Signature(signature),
        message: message,
      );
    } catch (_) {
      return false;
    }
  }

  /// Signal Safety Number-like SAS computation (§24.3.3).
  /// - Sort the two fingerprints lexicographically and concatenate
  /// - HKDF-SHA256(combined, salt="", info="SnowChat-Call-SAS-v1") → 32 bytes
  /// - First 4 bytes as big-endian uint32 (mask MSB to 0) % 10000 → 4-digit string
  ///
  /// Both client sides compute the same value. Users compare audibly to block MITM.
  static String computeSas({
    required String localFingerprint,
    required String remoteFingerprint,
  }) {
    final sorted = [localFingerprint, remoteFingerprint]..sort();
    final combined = utf8.encode(sorted.join('|'));

    final okm = hkdfDerive(
      ikm: Uint8List.fromList(combined),
      salt: Uint8List(0),
      info: Uint8List.fromList(utf8.encode('SnowChat-Call-SAS-v1')),
      length: 32,
    );

    final num = (okm[0] << 24 | okm[1] << 16 | okm[2] << 8 | okm[3]) &
        0x7FFFFFFF;
    return (num % 10000).toString().padLeft(4, '0');
  }
}
