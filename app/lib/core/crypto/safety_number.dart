/// @file        safety_number.dart
/// @description Signal v1 algorithm-based 60-digit fingerprint
///              ("safety number" / "security number"). Two SnowChat peers
///              that have successfully agreed on each other's Ed25519
///              identity keys must see byte-identical 60-digit numbers;
///              mismatch ⇒ MITM.
///
///              **Interop note (intentional divergence from upstream Signal):**
///              this implementation feeds the **raw 32-byte Ed25519 public
///              key** into the iterated hash. Upstream Signal's
///              NumericFingerprintGenerator v1 uses the **33-byte serialized
///              IdentityKey form** (1-byte type prefix || 32-byte key), so a
///              Signal client and a SnowChat client computing a fingerprint
///              over the same Ed25519 key bytes will produce **different**
///              60-digit numbers. The two outputs are NOT interchangeable.
///
///              Uses Signal v1's iteration count (5200), digest (SHA-512),
///              truncation length (30 bytes), and decimal encoder
///              (uint40 BE mod 100000). Two intentional divergences from
///              upstream Signal:
///                1. **First-round input layout**: libsignal feeds
///                   `(version || key || id) || key` into the FIRST SHA-512
///                   call (key appears twice in round 1). SnowChat feeds
///                   `(version || key || id)` once into round 1, then
///                   `(prev || key)` for rounds 2..5200. Both call SHA-512
///                   exactly 5200 times; only the round-1 payload differs.
///                2. **Identity key serialization**: Signal uses 33-byte
///                   `type-prefix(1) || key(32)` ("DJB type" 0x05 prefix).
///                   SnowChat uses raw 32-byte Ed25519 with no prefix.
///              Cross-SnowChat consistency is preserved (every SnowChat
///              client uses the same algorithm), which is what the
///              verify-identity UI displays. Signal client cross-interop
///              is **not** supported by design.
///
///              Algorithm (Signal v1, raw-key variant):
///                1. Sort the two (snowchatId, ed25519Key) tuples by
///                   snowchatId so both peers iterate in the same order.
///                2. For each side compute fingerprint =
///                     iteratedHash(version, idKey, snowId, idKey)
///                   where iteratedHash starts with
///                     hash[0] = u16BE(version) || idKey || utf8(snowId)
///                   and runs
///                     hash[i+1] = SHA512(hash[i] || originalIdKey)
///                   for 5200 iterations, taking the first 30 bytes of
///                   the final digest.
///                3. Encode each 30-byte fingerprint as 6 chunks of 5
///                   bytes; each chunk is read as a 40-bit big-endian
///                   unsigned int and rendered as a 5-digit decimal
///                   (mod 100000). Concatenating both sides yields a
///                   60-digit number.
///
///              References:
///                - libsignal-protocol-java
///                  org.signal.libsignal.protocol.fingerprint
///                  NumericFingerprintGenerator.java
///                - Signal-Android FingerprintLogic / Verify Identity
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-18 (P0-2 Stage 4-2: clarified SnowChat ↔ Signal interop boundary — raw 32B vs 33B serialized)
///
/// @functions
///  - SafetyNumber.compute(...): Compute the 60-digit number from two
///                               (snowId, Ed25519 key) pairs.
///  - SafetyNumber.formatForDisplay(digits60): Layout the 60 digits as
///                               "12345 67890" pairs, 6 lines × 2 chunks.
///  - SafetyNumber._iteratedHash(...): 5200-round SHA-512 fingerprint.
///  - SafetyNumber._encodeChunks(fp): 30-byte → 30-digit decimal encoding.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'sha512.dart';

class SafetyNumber {
  SafetyNumber._();

  /// Number of SHA-512 iterations per side. Matches Signal v1.
  static const int _iterations = 5200;

  /// Bytes of the iterated digest used for display (Signal v1: 30 bytes →
  /// 6 chunks of 5 bytes → 30 decimal digits per side → 60 digits total).
  static const int _fingerprintBytes = 30;

  /// Compute the Signal-compatible 60-digit Safety Number.
  ///
  /// Inputs:
  ///   - [mySnowId]          this user's SnowChat ID (e.g. "snow…")
  ///   - [myEd25519]         this user's 32-byte raw Ed25519 identity key
  ///   - [theirSnowId]       peer SnowChat ID
  ///   - [theirEd25519]      peer 32-byte raw Ed25519 identity key
  ///   - [version]           algorithm version (default 1)
  ///
  /// Returns a 60-character ASCII string of decimal digits.
  ///
  /// Throws [ArgumentError] if any input is empty or if either key is not
  /// exactly 32 bytes (Ed25519 raw public-key length).
  static String compute({
    required String mySnowId,
    required Uint8List myEd25519,
    required String theirSnowId,
    required Uint8List theirEd25519,
    int version = 1,
  }) {
    if (mySnowId.isEmpty || theirSnowId.isEmpty) {
      throw ArgumentError('SafetyNumber: snow IDs must not be empty');
    }
    if (myEd25519.length != 32 || theirEd25519.length != 32) {
      throw ArgumentError(
          'SafetyNumber: Ed25519 keys must be exactly 32 bytes');
    }

    // Canonical ordering — both peers must hash in the same sequence.
    // Lexicographic on the SnowChat ID gives a stable, simple total order.
    final firstIsMe = mySnowId.compareTo(theirSnowId) < 0;
    final firstId = firstIsMe ? mySnowId : theirSnowId;
    final firstKey = firstIsMe ? myEd25519 : theirEd25519;
    final secondId = firstIsMe ? theirSnowId : mySnowId;
    final secondKey = firstIsMe ? theirEd25519 : myEd25519;

    final firstFp = _iteratedHash(version, firstKey, firstId);
    final secondFp = _iteratedHash(version, secondKey, secondId);

    final buf = StringBuffer();
    _encodeChunks(firstFp, buf);
    _encodeChunks(secondFp, buf);
    return buf.toString();
  }

  /// Layout the 60 digits into a Signal-style display:
  ///   "12345 67890\n12345 67890\n…"
  /// 6 lines × 2 chunks of 5 digits each. Returns the raw layout — the
  /// caller wraps it in a TextStyle (monospace, large font).
  static String formatForDisplay(String digits60) {
    if (digits60.length != 60) {
      throw ArgumentError(
          'formatForDisplay expects exactly 60 digits, got '
          '${digits60.length}');
    }
    final lines = <String>[];
    for (var line = 0; line < 6; line++) {
      final start = line * 10;
      final left = digits60.substring(start, start + 5);
      final right = digits60.substring(start + 5, start + 10);
      lines.add('$left $right');
    }
    return lines.join('\n');
  }

  // -------------------------------------------------------------------------
  // Internal — Signal v1 iterated hash + decimal encoder.
  // -------------------------------------------------------------------------

  /// 5200-round SHA-512 fingerprint per Signal v1. Returns the first
  /// [_fingerprintBytes] bytes of the final digest.
  static Uint8List _iteratedHash(
    int version,
    Uint8List idKey,
    String snowId,
  ) {
    // Input layout for round 0:
    //   u16BE(version) || idKey || utf8(snowId)
    final snowBytes = utf8.encode(snowId);
    final initial = BytesBuilder(copy: false)
      ..addByte((version >> 8) & 0xff)
      ..addByte(version & 0xff)
      ..add(idKey)
      ..add(snowBytes);

    var hash = sha512Bytes(initial.takeBytes());

    // Round i+1: SHA512(hash[i] || originalIdKey)
    final next = BytesBuilder(copy: false);
    for (var i = 1; i < _iterations; i++) {
      next
        ..add(hash)
        ..add(idKey);
      hash = sha512Bytes(next.takeBytes());
    }

    return Uint8List.sublistView(hash, 0, _fingerprintBytes);
  }

  /// Encode a 30-byte fingerprint as 6×5-digit decimal chunks. Each chunk
  /// reads 5 bytes as a 40-bit big-endian unsigned int, then renders the
  /// value mod 100000 as a 5-digit zero-padded decimal.
  ///
  /// 5 bytes → range [0, 2^40) → mod 1e5 keeps every digit reachable.
  /// Signal uses the same `% 100000` reduction so the displayable space is
  /// 1e5 per chunk × 12 chunks = ~1e60 — far beyond any feasible MITM
  /// attempt to spoof a matching number for both peers simultaneously.
  static void _encodeChunks(Uint8List fp, StringBuffer out) {
    assert(fp.length == _fingerprintBytes);
    for (var i = 0; i < _fingerprintBytes; i += 5) {
      // Build a 40-bit BE value into an int. Dart int is 64-bit on native
      // and 53-bit safe on web, so 40 bits fits without precision loss.
      final v = (fp[i] << 32) |
          (fp[i + 1] << 24) |
          (fp[i + 2] << 16) |
          (fp[i + 3] << 8) |
          fp[i + 4];
      final chunk = (v % 100000).toString().padLeft(5, '0');
      out.write(chunk);
    }
  }
}
