/// @file        passcode_test.dart
/// @description PasscodeStore: the kinds' rules, the stored record (no
///              passcode in it), checking, the wait policy kept on disk, the
///              old SHA-256 PIN replaced on its first unlock, the reset; and
///              the KDF time at the record's parameters (printed).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - main(): the cases

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/crypto/hkdf.dart' show sha256;
import 'package:snowchat/core/security/passcode.dart';

import '../crypto/identity_test_support.dart';

String _legacyHash(String pin) => sha256(Uint8List.fromList(utf8.encode(pin)))
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

void main() {
  group('kinds', () {
    test('numeric6 takes exactly six digits', () {
      expect(PasscodeKind.numeric6.validate('123456'), isNull);
      expect(PasscodeKind.numeric6.validate('12345'), isNotNull);
      expect(PasscodeKind.numeric6.validate('12345a'), isNotNull);
    });
    test('numeric takes 4–16 digits', () {
      expect(PasscodeKind.numeric.validate('1234'), isNull);
      expect(PasscodeKind.numeric.validate('1' * 16), isNull);
      expect(PasscodeKind.numeric.validate('123'), isNotNull);
      expect(PasscodeKind.numeric.validate('1' * 17), isNotNull);
    });
    test('alphanumeric takes 6–64 characters of any kind', () {
      expect(PasscodeKind.alphanumeric.validate('abc12!'), isNull);
      expect(PasscodeKind.alphanumeric.validate('abc12'), isNotNull);
      expect(PasscodeKind.alphanumeric.validate('x' * 65), isNotNull);
    });
  });

  test('wait policy: five free, then 30 s, 1 min, 5 min, 15 min, 1 h', () {
    expect(waitAfterFailures(4), Duration.zero);
    expect(waitAfterFailures(5), const Duration(seconds: 30));
    expect(waitAfterFailures(6), const Duration(minutes: 1));
    expect(waitAfterFailures(7), const Duration(minutes: 5));
    expect(waitAfterFailures(8), const Duration(minutes: 15));
    expect(waitAfterFailures(9), const Duration(hours: 1));
    expect(waitAfterFailures(20), const Duration(hours: 1));
  });

  test('set + check; the record holds no passcode; KDF time', () async {
    final storage = InMemorySecureStorage();
    final store = PasscodeStore(storage);
    expect(await store.has(), isFalse);

    final sw = Stopwatch()..start();
    await store.set(PasscodeKind.alphanumeric, 'Snow-chat9');
    // ignore: avoid_print
    print('[passcode] Argon2id m=$kPasscodeKdfMemoryKiB KiB t=$kPasscodeKdfIterations '
        'p=$kPasscodeKdfParallelism: ${sw.elapsedMilliseconds} ms (host, incl. isolate)');

    expect(await store.has(), isTrue);
    expect(await store.kind(), PasscodeKind.alphanumeric);
    final raw = (await storage.read(PasscodeStore.recordKey))!;
    expect(raw.contains('Snow-chat9'), isFalse);
    final record = PasscodeRecord.tryParse(raw)!;
    expect(record.salt.length, kPasscodeSaltLength);
    expect(record.verifier.length, 32);

    expect(await store.check('Snow-chat9'), isA<PasscodeAccepted>());
    expect(await store.check('snow-chat9'), isA<PasscodeRejected>());
  });

  test('two records of the same passcode differ (salted)', () async {
    final a = InMemorySecureStorage();
    final b = InMemorySecureStorage();
    await PasscodeStore(a).set(PasscodeKind.numeric6, '123456');
    await PasscodeStore(b).set(PasscodeKind.numeric6, '123456');
    final ra = PasscodeRecord.tryParse((await a.read(PasscodeStore.recordKey))!)!;
    final rb = PasscodeRecord.tryParse((await b.read(PasscodeStore.recordKey))!)!;
    expect(ra.salt, isNot(rb.salt));
    expect(ra.verifier, isNot(rb.verifier));
  });

  test('wrong entries wait on disk; a new store keeps the count', () async {
    var now = DateTime.utc(2026, 11, 22, 12);
    final storage = InMemorySecureStorage();
    final store = PasscodeStore(storage, now: () => now);
    await store.set(PasscodeKind.numeric6, '123456');

    for (var i = 1; i <= 4; i++) {
      final r = await store.check('000000') as PasscodeRejected;
      expect(r.wait, Duration.zero);
      expect(r.attemptsLeft, 5 - i);
    }
    final fifth = await store.check('000000') as PasscodeRejected;
    expect(fifth.wait, const Duration(seconds: 30));

    // Killing the app does not reset it: a fresh store reads the same disk.
    final again = PasscodeStore(storage, now: () => now);
    final refused = await again.check('123456');
    expect(refused, isA<PasscodeLockedOut>());

    now = now.add(const Duration(seconds: 31));
    expect(await again.check('123456'), isA<PasscodeAccepted>());
    // The count is cleared by the right entry.
    final r = await again.check('000000') as PasscodeRejected;
    expect(r.wait, Duration.zero);
    expect(r.attemptsLeft, 4);
  });

  test('an old SHA-256 PIN unlocks once and is replaced', () async {
    final storage = InMemorySecureStorage();
    await storage.write(PasscodeStore.legacyKey, _legacyHash('123456'));
    final store = PasscodeStore(storage);
    expect(await store.has(), isTrue);
    expect(await store.kind(), PasscodeKind.numeric);

    expect(await store.check('654321'), isA<PasscodeRejected>());
    expect(await store.check('123456'), isA<PasscodeAccepted>());
    expect(await storage.containsKey(PasscodeStore.legacyKey), isFalse);
    expect(await store.kind(), PasscodeKind.numeric6);
    expect(await store.check('123456'), isA<PasscodeAccepted>());
  });

  test('an old 4-digit PIN becomes a custom numeric code', () async {
    final storage = InMemorySecureStorage();
    await storage.write(PasscodeStore.legacyKey, _legacyHash('1234'));
    final store = PasscodeStore(storage);
    expect(await store.check('1234'), isA<PasscodeAccepted>());
    expect(await store.kind(), PasscodeKind.numeric);
  });

  test('set refuses an invalid passcode; reset forgets it', () async {
    final storage = InMemorySecureStorage();
    final store = PasscodeStore(storage);
    expect(() => store.set(PasscodeKind.numeric6, '12ab56'), throwsArgumentError);
    await store.set(PasscodeKind.numeric, '1234');
    await store.check('0000');
    await store.clearForReset();
    expect(await store.has(), isFalse);
    expect(await storage.containsKey(PasscodeStore.failuresKey), isFalse);
  });
}
