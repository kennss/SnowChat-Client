/// @file        name_certificate.dart
/// @description Name certificates (design 2026-11-22-friend-graph-off-server §5.6, contract
///              §12.3): the server signs (snowId, display name, issue time) for an account, the
///              account carries its own certificate inside its sealed messages, and a receiver
///              checks it offline against the Sealed Sender server keys pinned in the build.
///              No receiver asks the server "who just sent me this" any more.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (verifyOrigin(): signature and subject only — the check of this
///              account's own certificate, which must not depend on this device's clock)
///
/// @functions
///  - NameCertificate: a parsed certificate (issue time, snowId, name, signature, bytes)
///  - NameCertificate.parse(): the bytes as the contract lays them out, or a FormatException
///  - NameCertificate.signedMessage(): what the server's signature covers
///  - NameCertificate.verify(): signature with a pinned key, subject, age window
///  - NameCertificate.verifyOrigin(): signature with a pinned key and subject (no clock)
///  - NameCertRejected: why a received certificate is not believed
///
/// Notes:
///  - Layout (big-endian integers): version 0x01 (1) ‖ issuedAtMs (8) ‖ snowId length (1) ‖
///    snowId ASCII ‖ name length (2) ‖ name UTF-8 (0 bytes: no name) ‖ Ed25519 signature (64)
///    over "SnowChat-NameCert-v1" ‖ 0x00 ‖ every byte before the signature.
///  - Accepted only when issued at most [nameCertMaxAge] ago (the nickname cooldown: a name
///    given up cannot be taken by another account within it, so an older certificate cannot
///    lend a name another account holds now) and not more than [nameCertFutureSkew] ahead.
///  - The signature is checked strictly (canonical scalar, non-small-order key), like every
///    other signature that decides what this device shows.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../crypto/ed25519_strict.dart';
import '../crypto/identity_binding.dart';

/// First byte of a name certificate.
const int nameCertVersion = 0x01;

/// The domain label in front of the signed bytes.
const String nameCertDomainLabel = 'SnowChat-NameCert-v1';

/// A certificate older than this is not believed (the nickname cooldown).
const Duration nameCertMaxAge = Duration(days: 30);

/// How far in the future an issue time may be (clock skew).
const Duration nameCertFutureSkew = Duration(minutes: 5);

/// A sender refreshes its own certificate when it is older than this.
const Duration nameCertRefreshAfter = Duration(days: 7);

const int _signatureLength = 64;

/// Why a received certificate is not believed.
enum NameCertRejected {
  /// Not laid out as the contract says.
  malformed,

  /// No pinned key signed it.
  signature,

  /// It names another account than the authenticated sender.
  wrongSubject,

  /// Issued more than [nameCertMaxAge] ago.
  expired,

  /// Issued more than [nameCertFutureSkew] ahead of this device's clock.
  future,
}

/// Thrown by [NameCertificate.verify].
class NameCertException implements Exception {
  final NameCertRejected reason;
  const NameCertException(this.reason);

  @override
  String toString() => 'NameCertException(${reason.name})';
}

class NameCertificate {
  /// The server's issue time (Unix ms).
  final int issuedAtMs;

  /// The account the certificate names.
  final String snowId;

  /// The account's display name, or null when it has none.
  final String? name;

  /// The server's Ed25519 signature (64 bytes).
  final Uint8List signature;

  /// The certificate as received (what travels inside messages).
  final Uint8List bytes;

  NameCertificate._({
    required this.issuedAtMs,
    required this.snowId,
    required this.name,
    required this.signature,
    required this.bytes,
  });

  /// The certificate as base64, for the inner JSON's `nameCert` field.
  String get base64 => base64Encode(bytes);

  /// Parse [bytes]. Throws [FormatException] for anything not laid out as
  /// the contract says (wrong version, lengths, trailing bytes, a snowId that
  /// is not one, a name that is not UTF-8).
  factory NameCertificate.parse(Uint8List bytes) {
    var at = 0;
    void need(int n) {
      if (at + n > bytes.length) {
        throw const FormatException('name certificate: truncated');
      }
    }

    need(1);
    if (bytes[at] != nameCertVersion) {
      throw const FormatException('name certificate: version');
    }
    at += 1;
    need(8);
    final view = ByteData.sublistView(bytes);
    final issuedAtMs = view.getInt64(at, Endian.big);
    at += 8;
    need(1);
    final snowLength = bytes[at];
    at += 1;
    need(snowLength);
    final String snowId;
    try {
      snowId = ascii.decode(bytes.sublist(at, at + snowLength));
    } on FormatException {
      throw const FormatException('name certificate: snowId');
    }
    if (!IdentityBindingV1.isValidSnowId(snowId)) {
      throw const FormatException('name certificate: snowId');
    }
    at += snowLength;
    need(2);
    final nameLength = view.getUint16(at, Endian.big);
    at += 2;
    need(nameLength);
    final String? name;
    try {
      name = nameLength == 0
          ? null
          : utf8.decode(bytes.sublist(at, at + nameLength));
    } on FormatException {
      throw const FormatException('name certificate: name');
    }
    at += nameLength;
    need(_signatureLength);
    final signature = Uint8List.fromList(
      bytes.sublist(at, at + _signatureLength),
    );
    at += _signatureLength;
    if (at != bytes.length) {
      throw const FormatException('name certificate: trailing bytes');
    }
    return NameCertificate._(
      issuedAtMs: issuedAtMs,
      snowId: snowId,
      name: name,
      signature: signature,
      bytes: Uint8List.fromList(bytes),
    );
  }

  /// Parse the base64 of a certificate; null when it is not one.
  static NameCertificate? tryParseBase64(Object? encoded) {
    if (encoded is! String || encoded.isEmpty) return null;
    try {
      return NameCertificate.parse(base64Decode(encoded));
    } on FormatException {
      return null;
    }
  }

  /// What the server signs: the domain label, 0x00, then [body] (every byte
  /// of the certificate before the signature).
  static Uint8List signedMessage(Uint8List body) {
    final label = utf8.encode(nameCertDomainLabel);
    return Uint8List.fromList([...label, 0x00, ...body]);
  }

  /// Check that a key of [trustedKeys] signed this certificate, that it
  /// names [expectedSnowId] (the sealed envelope's authenticated sender —
  /// or this account, for its own), and that it was issued within
  /// [nameCertMaxAge] before [nowMs] and not more than [nameCertFutureSkew]
  /// after. Throws [NameCertException].
  void verify({
    required List<Uint8List> trustedKeys,
    required String expectedSnowId,
    required int nowMs,
  }) {
    verifyOrigin(trustedKeys: trustedKeys, expectedSnowId: expectedSnowId);
    if (issuedAtMs > nowMs + nameCertFutureSkew.inMilliseconds) {
      throw const NameCertException(NameCertRejected.future);
    }
    if (nowMs - issuedAtMs > nameCertMaxAge.inMilliseconds) {
      throw const NameCertException(NameCertRejected.expired);
    }
  }

  /// Check that a key of [trustedKeys] signed this certificate and that it
  /// names [expectedSnowId] — not its age. For this account's own
  /// certificate, just fetched from the server: a phone whose clock is off
  /// must still send it (the receivers judge its age by their own clocks).
  /// Throws [NameCertException].
  void verifyOrigin({
    required List<Uint8List> trustedKeys,
    required String expectedSnowId,
  }) {
    final body = Uint8List.sublistView(
      bytes,
      0,
      bytes.length - _signatureLength,
    );
    final message = signedMessage(body);
    final signed = trustedKeys.any(
      (key) => verifyEd25519Strict(key, message, signature),
    );
    if (!signed) throw const NameCertException(NameCertRejected.signature);
    if (snowId != expectedSnowId) {
      throw const NameCertException(NameCertRejected.wrongSubject);
    }
  }
}
