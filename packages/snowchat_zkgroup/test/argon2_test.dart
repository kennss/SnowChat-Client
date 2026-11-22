/// @file        argon2_test.dart
/// @description Host test of Argon2id.derive through the C ABI: the reference
///              implementation's Argon2id v1.3 vector (the same one the Rust
///              tests check), refusals, and a call from another isolate.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';
import 'package:test/test.dart';

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

const _reference =
    '09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7';

Uint8List _derive() => Argon2id.derive(
  password: _bytes('password'),
  salt: _bytes('somesalt'),
  memoryKiB: 1 << 16,
  iterations: 2,
  parallelism: 1,
);

void main() {
  test('reference vector (phc-winner-argon2 test.c, Argon2id v1.3)', () {
    expect(_hex(_derive()), _reference);
  });

  test('refuses a short salt and impossible parameters', () {
    Matcher refused = throwsA(
      isA<ZkGroupException>().having(
        (e) => e.error,
        'error',
        ZkGroupError.invalidInput,
      ),
    );
    expect(
      () => Argon2id.derive(
        password: _bytes('pw'),
        salt: _bytes('short'),
        memoryKiB: 1024,
        iterations: 1,
        parallelism: 1,
      ),
      refused,
    );
    expect(
      () => Argon2id.derive(
        password: _bytes('pw'),
        salt: _bytes('somesalt'),
        memoryKiB: 1024,
        iterations: 0,
        parallelism: 1,
      ),
      refused,
    );
  });

  test('runs in another isolate with no setup', () async {
    expect(_hex(await Isolate.run(_derive)), _reference);
  });
}
