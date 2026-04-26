/// @file        sha512.dart
/// @description SHA-512 thin wrapper used by Safety Number iterated-hash
///              fingerprint algorithm. Delegates to `package:crypto` (FIPS
///              180-4) so we don't ship a hand-rolled SHA-512 implementation
///              alongside the Signal-compatible 5200-iteration loop in
///              [SafetyNumber.compute]. Kept as a separate file so the
///              callsite is obvious in security review (no hidden hash
///              imports inside Safety Number) and so we can swap the
///              backing implementation in one place if needed.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-18
///
/// @functions
///  - sha512Bytes(input): Returns the 64-byte SHA-512 digest of [input]
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as pkg_crypto;

/// Computes SHA-512 over [input] and returns the raw 64-byte digest.
///
/// This is the only hash primitive used by [SafetyNumber.compute].
/// The Signal Safety Number algorithm iterates this function 5200 times
/// per side, so the wrapper avoids any per-call allocation beyond what
/// `package:crypto` itself does.
Uint8List sha512Bytes(List<int> input) {
  final digest = pkg_crypto.sha512.convert(input);
  return Uint8List.fromList(digest.bytes);
}
