/// @file        ed25519_strict.dart
/// @description Strict Ed25519 verification for every signature that decides
///              shared state: group protocol v2 change-log entries, invite
///              acceptances, server log heads, member certificates and
///              account deletion proofs. TweetNaCl alone accepts a signature
///              whose scalar is not reduced (S >= L) and a public key of
///              small order; the server refuses both
///              (server/src/utils/identityBinding.ts verifyEd25519Strict), and
///              a signature one side accepts and the other refuses would
///              split their views of a group. The rules here are the ones
///              Identity Binding v1 already applies, exposed for any message.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-13
///
/// @functions
///  - verifyEd25519Strict(): canonical non-small-order key + S < L + verify
library;

import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' as ed;

import 'identity_binding.dart';

/// True only when [publicKey] is a 32-byte canonical encoding that is not a
/// small-order point, [signature] is 64 bytes with a canonical scalar
/// (S < L), and the signature verifies for [message]. Never throws.
bool verifyEd25519Strict(
  Uint8List publicKey,
  Uint8List message,
  Uint8List signature,
) {
  try {
    if (signature.length != 64) return false;
    if (!IdentityBindingV1.isAcceptableAccountKey(publicKey)) return false;
    if (!IdentityBindingV1.isCanonicalSignatureScalar(signature)) return false;
    // pinenacl throws on a bad signature or a key that is not on the curve.
    return ed.VerifyKey(Uint8List.fromList(publicKey)).verify(
      signature: ed.Signature(Uint8List.fromList(signature)),
      message: message,
    );
  } catch (_) {
    return false;
  }
}
