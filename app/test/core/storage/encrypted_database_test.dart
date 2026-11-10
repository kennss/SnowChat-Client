/// @file        encrypted_database_test.dart
/// @description At-rest protection level 1 — host-testable parts of the
///              encrypted database opener: legacy / undecryptable file
///              classification, the "never run on a stock sqlite3" guard,
///              the on-disk layout and the retry-after-locked-keychain
///              lazy executor.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-11
/// @lastUpdated 2026-11-11
///
/// @functions
///  - _TestDb: minimal drift database for the executor tests
///  - main(): test cases
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/storage/database_key_manager.dart';
import 'package:snowchat/core/storage/encrypted_database.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

class _TestDb extends GeneratedDatabase {
  _TestDb(super.executor);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}

void main() {
  group('legacy detection', () {
    final plainHeader = [...ascii.encode('SQLite format 3'), 0];

    test('plaintext SQLite header is recognised', () {
      expect(isPlaintextSqliteHeader(plainHeader), isTrue);
      expect(isPlaintextSqliteHeader([...plainHeader, 1, 2, 3]), isTrue);
    });

    test('random salt / short / empty header is not plaintext', () {
      expect(isPlaintextSqliteHeader(List<int>.generate(16, (i) => i * 7)),
          isFalse);
      expect(isPlaintextSqliteHeader(plainHeader.sublist(0, 10)), isFalse);
      expect(isPlaintextSqliteHeader(const []), isFalse);
    });

    test('NOTADB on a plaintext file → delete as legacy', () {
      expect(classifyOpenFailure(plainHeader),
          DbOpenFailureAction.deleteLegacyPlaintext);
    });

    test('NOTADB on ciphertext → quarantine (never delete)', () {
      expect(classifyOpenFailure(List<int>.generate(16, (i) => 255 - i)),
          DbOpenFailureAction.quarantine);
      expect(classifyOpenFailure(const []), DbOpenFailureAction.quarantine);
    });

    test('a real plaintext sqlite3 file is classified as legacy', () {
      final dir = Directory.systemTemp.createTempSync('enc_db_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/legacy.db';
      final db = sql.sqlite3.open(path);
      db.execute('CREATE TABLE t (x TEXT); INSERT INTO t VALUES (\'hello\');');
      db.dispose();
      final header = File(path).readAsBytesSync().sublist(0, 16);
      expect(classifyOpenFailure(header),
          DbOpenFailureAction.deleteLegacyPlaintext);
    });
  });

  test('stock sqlite3 (no SQLCipher) is refused loudly', () {
    final db = sql.sqlite3.openInMemory();
    addTearDown(db.dispose);
    expect(() => assertSqlCipherActive(db), throwsStateError);
  });

  test('layout: database lives in its own backup-excluded directory', () {
    const paths = EncryptedDatabasePaths('/docs');
    expect(paths.directory, '/docs/snowchat_db');
    expect(paths.database, '/docs/snowchat_db/snowchat.db');
    expect(paths.databaseFiles, contains('/docs/snowchat_db/snowchat.db-wal'));
    expect(paths.databaseFiles, contains('/docs/snowchat_db/snowchat.db-shm'));
    expect(paths.legacyPlaintextFiles, contains('/docs/snowchat.db'));
    expect(paths.legacyPlaintextFiles, isNot(contains(paths.database)));
    expect(paths.quarantineFiles.first,
        '/docs/snowchat_db/snowchat.db.undecryptable');
  });

  group('RetryableLazyDatabase', () {
    test('locked keychain: first query fails, a later one opens', () async {
      var attempts = 0;
      final db = _TestDb(RetryableLazyDatabase(() async {
        attempts++;
        if (attempts == 1) {
          throw const DatabaseKeyUnavailableException('locked');
        }
        return NativeDatabase.memory();
      }));
      addTearDown(db.close);

      await expectLater(db.customSelect('SELECT 1 AS v').get(),
          throwsA(isA<DatabaseKeyUnavailableException>()));
      final rows = await db.customSelect('SELECT 1 AS v').get();
      expect(rows.single.read<int>('v'), 1);
      expect(attempts, 2);
    });

    test('non-retryable failure stays sticky (no silent re-open)', () async {
      var attempts = 0;
      final db = _TestDb(RetryableLazyDatabase(() async {
        attempts++;
        throw StateError('SQLCipher missing');
      }));
      addTearDown(db.close);

      await expectLater(
          db.customSelect('SELECT 1').get(), throwsA(isA<StateError>()));
      await expectLater(
          db.customSelect('SELECT 1').get(), throwsA(isA<StateError>()));
      expect(attempts, 1);
    });

    test('concurrent first queries share one open', () async {
      var attempts = 0;
      final db = _TestDb(RetryableLazyDatabase(() async {
        attempts++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return NativeDatabase.memory();
      }));
      addTearDown(db.close);
      await Future.wait([
        for (var i = 0; i < 4; i++) db.customSelect('SELECT 1').get(),
      ]);
      expect(attempts, 1);
    });
  });
}
