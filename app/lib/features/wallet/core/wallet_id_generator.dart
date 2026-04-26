/// @file        wallet_id_generator.dart
/// @description CSPRNG-based wallet UUID generation. Format:
///              `wal_<base58 12 chars>`. Uses `Random.secure()` (audit A-8
///              mandated) — never use the default `dart:math.Random`
///              constructor.
///
///              12 base58 chars ≈ 70 bits entropy. With max wallets per user
///              of 16 (Primary 1 + derived 5 + imported 10), collision
///              probability is negligible (~1 in 2^60).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - WalletIdGenerator.generate(): "wal_<12 base58 chars>"

library;

import 'dart:math';

const _base58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

abstract class WalletIdGenerator {
  /// Build a 12-char base58 suffix via CSPRNG and join with the `wal_` prefix.
  /// `dart:math.Random.secure()` is the backing entropy source — OS-level
  /// (Android `/dev/urandom`, iOS `SecRandomCopyBytes`).
  static String generate() {
    final r = Random.secure();
    final chars = StringBuffer('wal_');
    for (int i = 0; i < 12; i++) {
      chars.writeCharCode(_base58Alphabet.codeUnitAt(r.nextInt(58)));
    }
    return chars.toString();
  }
}
