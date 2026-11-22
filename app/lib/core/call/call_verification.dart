/// @file        call_verification.dart
/// @description DTLS fingerprint Ed25519 signature + SAS 4-digit computation (Phase 8.2 §24.3)
///              Blocks SDP forgery attacks by a malicious signaling server.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-11-22 (SC-10: the signature binds the call — "SnowChat-Call-DTLS-v1|callId|
///              fingerprint" — so it cannot be carried over to another call; signatureField /
///              checkRemote are what CallService signs its own SDP and checks the peer's with). Earlier 2026-04-26 (header + inline English translation)
///
/// @functions
///  - CallVerification.parseFingerprint(sdp): extract a=fingerprint:sha-256 value from SDP
///  - CallVerification.signedMessage(callId, fp): the bytes a fingerprint signature covers
///  - CallVerification.signFingerprint(callId, fp, seed): Ed25519 signature
///  - CallVerification.verifyFingerprint(callId, fp, sig, pubKey): Ed25519 verification
///  - CallVerification.signatureField(callId, sdp, seed): the fpSig field of an SDP this device sends
///  - CallVerification.checkRemote(fpSig, callId, sdp, peerKey): unsigned / verified / refused for a received SDP
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

/// The result of checking a received SDP's fingerprint signature (SC-10).
enum RemoteFingerprintCheck {
  /// No signature: a peer on build 1000, which does not sign (accepted).
  unsigned,

  /// The signature verifies under the peer's key, for this call.
  verified,

  /// A signature that does not verify, or cannot be checked — end the call.
  refused,
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

  /// Domain label of a DTLS fingerprint signature (version 1).
  static const String signatureLabel = 'SnowChat-Call-DTLS-v1';

  /// What a fingerprint signature covers: the label, the call and the
  /// fingerprint — a signature of one call is worth nothing in another.
  static Uint8List signedMessage({
    required String callId,
    required String fingerprint,
  }) =>
      Uint8List.fromList(
        utf8.encode('$signatureLabel|$callId|${fingerprint.toLowerCase()}'),
      );

  /// Sign the fingerprint (hex string) of [callId] with the Signal-layer
  /// Ed25519 identity key.
  /// [signingKeySeed]: SignalProtocolService.signingKeySeed
  /// Returns: 64 byte Ed25519 signature.
  static Uint8List signFingerprint({
    required String callId,
    required String fingerprint,
    required Uint8List signingKeySeed,
  }) {
    final signingKey = ed.SigningKey.fromSeed(signingKeySeed);
    final message = signedMessage(callId: callId, fingerprint: fingerprint);
    final signed = signingKey.sign(message);
    // .signature has the raw 64-byte Ed25519 sig
    return Uint8List.fromList(signed.signature);
  }

  /// Verify the remote fingerprint + signature against the remote identity Ed25519 verify key.
  /// Returns false on failure. Caller blocks the call.
  static bool verifyFingerprint({
    required String callId,
    required String fingerprint,
    required Uint8List signature,
    required Uint8List remoteVerifyKey,
  }) {
    try {
      final verifyKey = ed.VerifyKey(remoteVerifyKey);
      final message = signedMessage(callId: callId, fingerprint: fingerprint);
      // pinenacl API: verifyKey.verify(signature: Signature, message: bytes)
      return verifyKey.verify(
        signature: ed.Signature(signature),
        message: message,
      );
    } catch (_) {
      return false;
    }
  }

  /// The `fpSig` field of an SDP this device sends for [callId]: its DTLS
  /// fingerprint signed with [signingKeySeed] (base64). Empty when there is
  /// nothing to sign with, no call id, or no fingerprint in [sdp].
  static Map<String, String> signatureField({
    required String? callId,
    required String? sdp,
    required Uint8List? signingKeySeed,
  }) {
    if (callId == null || sdp == null || signingKeySeed == null) return const {};
    final String fingerprint;
    try {
      fingerprint = parseFingerprint(sdp);
    } on CallVerificationException {
      return const {};
    }
    final signature = signFingerprint(
      callId: callId,
      fingerprint: fingerprint,
      signingKeySeed: signingKeySeed,
    );
    return {'fpSig': base64Encode(signature)};
  }

  /// Check the `fpSig` ([fpSig]) a peer sent with [sdp] for [callId].
  ///
  /// - None: [RemoteFingerprintCheck.unsigned] — a build-1000 peer. The
  ///   signaling is sealed and Double-Ratchet encrypted, so the server can
  ///   neither strip a signature nor change the SDP; the SAS stays.
  /// - Present: it must verify under the peer's account-bound Ed25519 key
  ///   ([peerKey]) for this call and this fingerprint — anything else (no
  ///   key, malformed, wrong) is [RemoteFingerprintCheck.refused].
  static Future<RemoteFingerprintCheck> checkRemote({
    required Object? fpSig,
    required Object? callId,
    required String sdp,
    required Future<Uint8List?> Function() peerKey,
  }) async {
    if (fpSig == null) return RemoteFingerprintCheck.unsigned;
    if (fpSig is! String || callId is! String) return RemoteFingerprintCheck.refused;
    final String fingerprint;
    final Uint8List signature;
    try {
      fingerprint = parseFingerprint(sdp);
      signature = base64Decode(fpSig);
    } on CallVerificationException {
      return RemoteFingerprintCheck.refused;
    } on FormatException {
      return RemoteFingerprintCheck.refused;
    }
    Uint8List? key;
    try {
      key = await peerKey();
    } catch (_) {
      key = null;
    }
    if (key == null) return RemoteFingerprintCheck.refused;
    return verifyFingerprint(
      callId: callId,
      fingerprint: fingerprint,
      signature: signature,
      remoteVerifyKey: key,
    )
        ? RemoteFingerprintCheck.verified
        : RemoteFingerprintCheck.refused;
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
