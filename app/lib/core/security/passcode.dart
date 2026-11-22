/// @file        passcode.dart
/// @description The app passcode (what unlocks the app). Three kinds — six
///              digits (the default), digits of a free length, letters and
///              digits — stored as a salted Argon2id record, never as the
///              passcode or a fast hash of it. Checking runs the KDF off the
///              UI isolate. A record in the old format (unsalted SHA-256 of a
///              4–6 digit PIN, builds ≤ 1000) is replaced by the new one the
///              first time it unlocks. Wrong guesses are counted on disk with
///              growing waits, so killing the app does not reset them.
///              Design: Documentation/TO-DO/2026-11-22-passcode-redesign-design.md.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (a [Perf] line with the KDF time — time and parameters only — to tune
///              the parameters on phones)
///
/// @functions
///  - PasscodeKind / PasscodeKindRules: the kinds and what each accepts
///  - PasscodeRecord: the stored record (JSON, `passcode_v2`)
///  - PasscodeStore.has() / kind(): whether a passcode is set, and its kind
///  - PasscodeStore.set(): store a new passcode (any kind)
///  - PasscodeStore.check(): verify an entry (with the wait policy)
///  - PasscodeStore.lockedFor(): how long entries are refused now
///  - PasscodeStore.clearForReset(): forget the passcode (recovery-phrase reset)
///  - passcodeVerifier(): HMAC of the derived key — what the record keeps
///  - waitAfterFailures(): the wait policy
///
/// Notes:
///  - verifier = HMAC-SHA256(K, "snowchat-passcode-verify"), K =
///    Argon2id(passcode, salt). K itself is never stored; at-rest level 2 will
///    derive its DB key-encryption key from the same K (another HKDF label),
///    so this record format is what level 2 builds on.
///  - KDF parameters live in the record: raising them later needs no format
///    change (the next unlock re-derives).
///  - Nothing here logs the passcode, the salt, K or the verifier.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';

import '../crypto/hkdf.dart' show hmacSha256, sha256;
import '../storage/secure_storage.dart';

/// The kinds of passcode. The lock screen shows the input that fits the kind;
/// only the kind is stored, never the length.
enum PasscodeKind {
  /// Exactly six digits; the lock screen submits on the sixth.
  numeric6,

  /// 4–16 digits; submitted with a button.
  numeric,

  /// 6–64 characters (letters, digits, symbols); a normal keyboard.
  alphanumeric,
}

/// What each kind accepts.
extension PasscodeKindRules on PasscodeKind {
  int get minLength => switch (this) {
        PasscodeKind.numeric6 => 6,
        PasscodeKind.numeric => 4,
        PasscodeKind.alphanumeric => 6,
      };

  int get maxLength => switch (this) {
        PasscodeKind.numeric6 => 6,
        PasscodeKind.numeric => 16,
        PasscodeKind.alphanumeric => 64,
      };

  bool get isNumeric => this != PasscodeKind.alphanumeric;

  /// Why [value] is not a passcode of this kind, or null when it is.
  String? validate(String value) {
    if (isNumeric && !RegExp(r'^[0-9]*$').hasMatch(value)) {
      return 'Digits only';
    }
    if (value.length < minLength || value.length > maxLength) {
      return minLength == maxLength
          ? 'Use exactly $minLength digits'
          : isNumeric
              ? 'Use $minLength–$maxLength digits'
              : 'Use $minLength–$maxLength characters';
    }
    return null;
  }

  /// Short name for the options sheet.
  String get label => switch (this) {
        PasscodeKind.numeric6 => '6-digit numeric code',
        PasscodeKind.numeric => 'Custom numeric code',
        PasscodeKind.alphanumeric => 'Custom alphanumeric code',
      };
}

/// Argon2id parameters of new records (64 MiB, 3 passes, 1 lane). Measured
/// on the development Mac (Apple Silicon, `flutter test`, including the
/// isolate start): ~0.5 s per derivation. To be confirmed on the slowest
/// supported phones before release (design §3.3: aim 0.3–0.5 s there); old
/// records keep their parameters until the next unlock re-derives, so a later
/// change needs no migration step.
const int kPasscodeKdfMemoryKiB = 65536;
const int kPasscodeKdfIterations = 3;
const int kPasscodeKdfParallelism = 1;

/// Salt length of new records (RFC 9106's recommendation).
const int kPasscodeSaltLength = 16;

/// Wrong entries allowed before the first wait.
const int kPasscodeFreeAttempts = 5;

/// The stored record (`passcode_v2`).
class PasscodeRecord {
  PasscodeRecord({
    required this.kind,
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.salt,
    required this.verifier,
  });

  final PasscodeKind kind;
  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final Uint8List salt;
  final Uint8List verifier;

  String toJson() => jsonEncode({
        'v': 2,
        'kind': kind.name,
        'kdf': {
          'alg': 'argon2id',
          'm': memoryKiB,
          't': iterations,
          'p': parallelism,
        },
        'salt': base64Encode(salt),
        'verifier': base64Encode(verifier),
      });

  /// Null when [raw] is not a record this build reads.
  static PasscodeRecord? tryParse(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['v'] != 2) return null;
      final kdf = map['kdf'] as Map<String, dynamic>;
      if (kdf['alg'] != 'argon2id') return null;
      final kind = PasscodeKind.values.asNameMap()[map['kind']];
      if (kind == null) return null;
      return PasscodeRecord(
        kind: kind,
        memoryKiB: kdf['m'] as int,
        iterations: kdf['t'] as int,
        parallelism: kdf['p'] as int,
        salt: base64Decode(map['salt'] as String),
        verifier: base64Decode(map['verifier'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// HMAC-SHA256(K, "snowchat-passcode-verify") with K = Argon2id(passcode,
/// salt). Runs the KDF in a short-lived isolate; K is cleared before return.
Future<Uint8List> passcodeVerifier(
  String passcode, {
  required Uint8List salt,
  required int memoryKiB,
  required int iterations,
  required int parallelism,
}) {
  final password = Uint8List.fromList(utf8.encode(passcode));
  final sw = Stopwatch()..start();
  return Isolate.run(() {
    final key = Argon2id.derive(
      password: password,
      salt: salt,
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
    );
    try {
      return hmacSha256(
          key, Uint8List.fromList(utf8.encode('snowchat-passcode-verify')));
    } finally {
      key.fillRange(0, key.length, 0);
      password.fillRange(0, password.length, 0);
    }
  }).whenComplete(() {
    // Time only (no passcode, salt or output): the parameters are tuned
    // against what the slowest phones take (design §3.3).
    debugPrint('[Perf] passcode KDF ${sw.elapsedMilliseconds}ms '
        '(m=${memoryKiB}KiB t=$iterations p=$parallelism)');
  });
}

/// The wait after [failures] wrong entries in a row: none for the first
/// [kPasscodeFreeAttempts], then 30 s, 1 min, 5 min, 15 min, and 1 h from
/// then on.
Duration waitAfterFailures(int failures) {
  final over = failures - kPasscodeFreeAttempts;
  if (over < 0) return Duration.zero;
  const steps = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];
  return over < steps.length ? steps[over] : const Duration(hours: 1);
}

/// The result of one entry.
sealed class PasscodeCheck {
  const PasscodeCheck();
}

/// Right: the app may unlock.
class PasscodeAccepted extends PasscodeCheck {
  const PasscodeAccepted();
}

/// Wrong. [wait] is how long the next entry is refused (zero while free
/// attempts remain); [attemptsLeft] the free attempts left before waits.
class PasscodeRejected extends PasscodeCheck {
  const PasscodeRejected({required this.wait, required this.attemptsLeft});
  final Duration wait;
  final int attemptsLeft;
}

/// Not checked: entries are refused for [wait] more.
class PasscodeLockedOut extends PasscodeCheck {
  const PasscodeLockedOut(this.wait);
  final Duration wait;
}

/// The app passcode, in secure storage.
class PasscodeStore {
  PasscodeStore(this._storage, {DateTime Function()? now, Random? random})
      : _now = now ?? DateTime.now,
        _random = random ?? Random.secure();

  final SecureStorageService _storage;
  final DateTime Function() _now;
  final Random _random;

  static const String recordKey = 'passcode_v2';

  /// The pre-2026-11-22 record: unsalted SHA-256 hex of a 4–6 digit PIN.
  static const String legacyKey = 'pin_hash';

  static const String failuresKey = 'passcode_failures';
  static const String lockedUntilKey = 'passcode_locked_until';

  /// Whether a passcode is set (either format).
  Future<bool> has() async =>
      await _storage.containsKey(recordKey) ||
      await _storage.containsKey(legacyKey);

  /// The kind the lock screen should ask for. An old-format PIN (4–6 digits,
  /// length not recorded) is asked for as [PasscodeKind.numeric].
  Future<PasscodeKind?> kind() async {
    final raw = await _storage.read(recordKey);
    if (raw != null) return PasscodeRecord.tryParse(raw)?.kind;
    if (await _storage.containsKey(legacyKey)) return PasscodeKind.numeric;
    return null;
  }

  /// Store [passcode] of [kind] as the app passcode (replacing any, in either
  /// format) and clear the wrong-entry count. Throws [ArgumentError] when
  /// it is not a valid passcode of that kind.
  Future<void> set(PasscodeKind kind, String passcode) async {
    final problem = kind.validate(passcode);
    if (problem != null) throw ArgumentError(problem);
    final salt = Uint8List.fromList(
        List<int>.generate(kPasscodeSaltLength, (_) => _random.nextInt(256)));
    final verifier = await passcodeVerifier(
      passcode,
      salt: salt,
      memoryKiB: kPasscodeKdfMemoryKiB,
      iterations: kPasscodeKdfIterations,
      parallelism: kPasscodeKdfParallelism,
    );
    final record = PasscodeRecord(
      kind: kind,
      memoryKiB: kPasscodeKdfMemoryKiB,
      iterations: kPasscodeKdfIterations,
      parallelism: kPasscodeKdfParallelism,
      salt: salt,
      verifier: verifier,
    );
    await _storage.write(recordKey, record.toJson());
    await _storage.delete(legacyKey);
    await _clearFailures();
  }

  /// How long entries are refused from now (zero when they are not).
  Future<Duration> lockedFor() async {
    final until = int.tryParse(await _storage.read(lockedUntilKey) ?? '');
    if (until == null) return Duration.zero;
    final left = until - _now().millisecondsSinceEpoch;
    return left > 0 ? Duration(milliseconds: left) : Duration.zero;
  }

  /// Check [entry]. While a wait is running nothing is checked. A right
  /// entry clears the count; an old-format record that matches is replaced
  /// by a new-format one in place.
  Future<PasscodeCheck> check(String entry) async {
    final wait = await lockedFor();
    if (wait > Duration.zero) return PasscodeLockedOut(wait);

    final bool right;
    final raw = await _storage.read(recordKey);
    if (raw != null) {
      final record = PasscodeRecord.tryParse(raw);
      right = record != null && await _matches(record, entry);
    } else {
      right = await _matchesLegacy(entry);
      if (right) {
        // Old format: re-store in the new one under the kind its length
        // implies (old PINs were 4–6 digits).
        await set(
          entry.length == 6 ? PasscodeKind.numeric6 : PasscodeKind.numeric,
          entry,
        );
      }
    }

    if (right) {
      await _clearFailures();
      return const PasscodeAccepted();
    }
    final failures =
        (int.tryParse(await _storage.read(failuresKey) ?? '') ?? 0) + 1;
    await _storage.write(failuresKey, '$failures');
    final next = waitAfterFailures(failures);
    if (next > Duration.zero) {
      await _storage.write(lockedUntilKey,
          '${_now().add(next).millisecondsSinceEpoch}');
    }
    return PasscodeRejected(
      wait: next,
      attemptsLeft: max(0, kPasscodeFreeAttempts - failures),
    );
  }

  /// Forget the passcode and the wrong-entry count (the user proved the
  /// account with its recovery phrase and sets a new one next).
  Future<void> clearForReset() async {
    await _storage.delete(recordKey);
    await _storage.delete(legacyKey);
    await _clearFailures();
  }

  Future<bool> _matches(PasscodeRecord record, String entry) async {
    final verifier = await passcodeVerifier(
      entry,
      salt: record.salt,
      memoryKiB: record.memoryKiB,
      iterations: record.iterations,
      parallelism: record.parallelism,
    );
    return _equal(verifier, record.verifier);
  }

  Future<bool> _matchesLegacy(String entry) async {
    final stored = await _storage.read(legacyKey);
    if (stored == null) return false;
    final hash = sha256(Uint8List.fromList(utf8.encode(entry)));
    final hex = hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _equal(
      Uint8List.fromList(utf8.encode(hex)),
      Uint8List.fromList(utf8.encode(stored)),
    );
  }

  Future<void> _clearFailures() async {
    await _storage.delete(failuresKey);
    await _storage.delete(lockedUntilKey);
  }

  /// Constant-time comparison (time depends on the length only).
  static bool _equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
