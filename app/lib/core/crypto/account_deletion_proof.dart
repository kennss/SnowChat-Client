/// @file        account_deletion_proof.dart
/// @description Account deletion proof v1 — the statement, signed by the
///              account key itself, that an account was deleted at a given
///              time. The account signs it when it deletes itself; the server
///              stores it and hands it to group members who still address
///              that account (group protocol v2 design §9.7). A member is
///              dropped on the account's own signature, never on the server's
///              word that "this account does not exist".
///
///              Signed message (fixed length, 71 bytes):
///                0xFF                             1B  (never produced by
///                                                      utf8.encode, so the
///                                                      login challenge cannot
///                                                      be used as an oracle)
///                "SnowChat_AccountDeleted_v1"    26B  ASCII
///                snowId                          36B  ASCII lowercase
///                deletedAtMs                      8B  u64 big-endian
///              signature = Ed25519_detached(accountPrivateKey, message)
///
///              The server implements the same format
///              (server/src/utils/accountDeletionProof.ts); both sides are
///              tested against test/fixtures/account_deleted_v1.json.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-13
///
/// @functions
///  - AccountDeletionProofV1.buildMessage(): encode the 71-byte message
///  - AccountDeletionProofV1.verify(): fail-closed check against an account key
///  - AccountDeletionProof: wire form `{deletedAtMs: decimal string, sig: base64}`
///  - AccountDeletionProof.tryParseWire(): strict parser, null when malformed
///
/// Notes:
///  - deletedAtMs is Unix time in MILLISECONDS: a decimal string in JSON, an
///    int here. Values of 2^63 and above are refused (the server only stores
///    a proof whose time is within ten minutes of its own clock).
///  - The ten-minute window is the SERVER's rule, applied once when the
///    account is deleted. A client verifying a stored proof later has no
///    clock rule: it compares deletedAtMs with the member certificate's
///    issuedAtMs instead (gv2_member_check.dart).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'ed25519_strict.dart';
import 'identity_binding.dart';

class AccountDeletionProofV1 {
  AccountDeletionProofV1._();

  /// First byte of the signed message.
  static const int domainPrefix = 0xFF;

  /// ASCII domain label (26 bytes).
  static const String label = 'SnowChat_AccountDeleted_v1';

  /// Total message length: 1 + 26 + 36 + 8.
  static const int messageLength = 71;

  /// Encode the 71-byte message. Throws [ArgumentError] on a malformed snowId
  /// or a negative time (callers handling untrusted input use [verify], which
  /// never throws).
  static Uint8List buildMessage({
    required String snowId,
    required int deletedAtMs,
  }) {
    if (!IdentityBindingV1.isValidSnowId(snowId)) {
      throw ArgumentError('deletion proof: snowId format');
    }
    if (deletedAtMs < 0) {
      throw ArgumentError('deletion proof: deletedAtMs must be >= 0');
    }
    final time = ByteData(8)..setUint64(0, deletedAtMs, Endian.big);
    final b = BytesBuilder(copy: false)
      ..addByte(domainPrefix)
      ..add(ascii.encode(label))
      ..add(ascii.encode(snowId))
      ..add(time.buffer.asUint8List());
    final out = b.takeBytes();
    assert(out.length == messageLength);
    return out;
  }

  /// True only when [accountPublicKey] is an acceptable account key that
  /// derives [snowId] and [proof] carries its strict Ed25519 signature over
  /// (snowId, deletedAtMs). Never throws.
  static bool verify({
    required String snowId,
    required Uint8List accountPublicKey,
    required AccountDeletionProof proof,
  }) {
    try {
      if (!IdentityBindingV1.accountKeyMatchesSnowId(accountPublicKey, snowId)) {
        return false;
      }
      if (proof.deletedAtMs < 0) return false;
      final message =
          buildMessage(snowId: snowId, deletedAtMs: proof.deletedAtMs);
      return verifyEd25519Strict(accountPublicKey, message, proof.signature);
    } catch (_) {
      return false;
    }
  }
}

/// A deletion proof as it travels: `{deletedAtMs: "<u63 decimal>", sig: "<base64, 64 bytes>"}`.
class AccountDeletionProof {
  /// Unix time in milliseconds the account says it was deleted at.
  final int deletedAtMs;

  /// 64-byte Ed25519 signature by the account key.
  final Uint8List signature;

  const AccountDeletionProof({
    required this.deletedAtMs,
    required this.signature,
  });

  static final RegExp _sigRe = RegExp(r'^[A-Za-z0-9+/]{86}==$');

  Map<String, dynamic> toWireJson() => {
        'deletedAtMs': deletedAtMs.toString(),
        'sig': base64Encode(signature),
      };

  /// Strict parser: null for anything that is not exactly the wire form (a
  /// number instead of a string, a sign character, base64 that is not the
  /// canonical encoding of 64 bytes).
  static AccountDeletionProof? tryParseWire(Object? raw) {
    if (raw is! Map) return null;
    final timeRaw = raw['deletedAtMs'];
    final sigRaw = raw['sig'];
    if (timeRaw is! String || sigRaw is! String) return null;
    final time = IdentityBindingV1.parseEpoch(timeRaw);
    if (time == null) return null;
    if (!_sigRe.hasMatch(sigRaw)) return null;
    final Uint8List sig;
    try {
      sig = base64Decode(sigRaw);
    } catch (_) {
      return null;
    }
    if (sig.length != 64 || base64Encode(sig) != sigRaw) return null;
    return AccountDeletionProof(deletedAtMs: time, signature: sig);
  }
}
