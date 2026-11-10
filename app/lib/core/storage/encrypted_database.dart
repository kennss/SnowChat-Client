/// @file        encrypted_database.dart
/// @description At-rest protection level 1 — opens the drift message database
///              through SQLCipher (sqlcipher_flutter_libs) with a random 256-bit
///              raw key from DatabaseKeyManager, and owns its on-disk location.
///
///              Location: `<ApplicationDocuments>/snowchat_db/snowchat.db`. The
///              dedicated directory is excluded from iOS backups as a whole, so
///              the -wal / -shm sidecars SQLite creates later are covered too
///              (Android: res/xml/data_extraction_rules.xml). The pre-encryption
///              location `<ApplicationDocuments>/snowchat.db` only ever held a
///              plaintext database and is deleted once the key is resolved.
///
///              Open sequence (main isolate, inside a retryable lazy executor):
///               1. wait for the iOS fresh-install keychain purge (caller hook)
///               2. resolve the key (DatabaseKeyManager). Storage unreadable ⇒
///                  DatabaseKeyUnavailableException, nothing deleted; the next
///                  query retries. Key absent on readable storage ⇒ delete any
///                  keyless database (+ orphaned attachments), create the key.
///               3. delete the legacy plaintext location
///               4. preflight an existing file with package:sqlite3 on this
///                  isolate: SQLCipher active? key opens it? A failure with a
///                  plaintext SQLite header ⇒ legacy plaintext ⇒ delete; a
///                  ciphertext file the key cannot open ⇒ quarantine (rename,
///                  never delete) and start fresh — see classifyOpenFailure()
///               5. NativeDatabase.createInBackground with `isolateSetup`
///                  (library override + old-Android workaround in the drift
///                  isolate) and `setup` (cipher_version check → PRAGMA key →
///                  secure_delete → key verification). SQLCipher missing is a
///                  hard StateError — never a plaintext fallback.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-11
/// @lastUpdated 2026-11-11
///
/// @functions
///  - EncryptedDatabasePaths.resolve(): directory / file / sidecar paths
///  - configureSqlCipherLibrary(): package:sqlite3 → SQLCipher (per isolate)
///  - isPlaintextSqliteHeader(bytes): "SQLite format 3\0" magic check
///  - assertSqlCipherActive(db): PRAGMA cipher_version non-empty, else StateError
///  - classifyOpenFailure(): preflight verdict for a file the key cannot open
///  - openEncryptedDatabase(): QueryExecutor for SnowDatabase
///  - deleteEncryptedDatabase(): reset / account delete — files, then key
///  - RetryableLazyDatabase: LazyDatabase whose open is retried after a
///    DatabaseKeyUnavailableException instead of failing for the process
///
/// @notes
///  - SQLCipher library: Android `libsqlcipher.so` (net.zetetic:sqlcipher-android
///    4.10), iOS `SQLCipher.framework` (pod SQLCipher 4.10, dynamic framework
///    under use_frameworks!). iOS opens the framework explicitly instead of
///    DynamicLibrary.process(): FirebaseMessaging / MLKit link the system
///    libsqlite3, and process-wide symbol lookup could bind the plaintext one.
///  - PRAGMA key uses the raw-key form `x'<64 hex>'` ⇒ no PBKDF2 at open.
///  - secure_delete=ON: freed pages are zeroed before encryption, so deleted /
///    disappearing messages do not survive inside the file even for someone
///    who later obtains the key.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:drift/backends.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'database_key_manager.dart';
import 'local_file_protection.dart';
import 'secure_storage.dart';

/// On-disk layout of the encrypted database.
class EncryptedDatabasePaths {
  static const String directoryName = 'snowchat_db';
  static const String fileName = 'snowchat.db';

  /// Suffix of a ciphertext file the stored key could not open (kept, never
  /// deleted automatically). One slot — a newer quarantine replaces it.
  static const String quarantineSuffix = '.undecryptable';

  static const List<String> sidecarSuffixes = ['', '-wal', '-shm', '-journal'];

  final String documentsPath;
  const EncryptedDatabasePaths(this.documentsPath);

  static Future<EncryptedDatabasePaths> resolve() async {
    final docs = await getApplicationDocumentsDirectory();
    return EncryptedDatabasePaths(docs.path);
  }

  String get directory => p.join(documentsPath, directoryName);
  String get database => p.join(directory, fileName);

  /// Database + its SQLite sidecars.
  List<String> get databaseFiles =>
      [for (final s in sidecarSuffixes) '$database$s'];

  List<String> get quarantineFiles =>
      [for (final s in sidecarSuffixes) '$database$quarantineSuffix$s'];

  /// Pre-encryption location — only ever held a PLAINTEXT database.
  List<String> get legacyPlaintextFiles => [
        for (final s in sidecarSuffixes) p.join(documentsPath, '$fileName$s')
      ];
}

/// Point package:sqlite3 at SQLCipher on the CURRENT isolate. Must run in the
/// main isolate and in the drift background isolate before any sqlite3 use.
void configureSqlCipherLibrary() {
  open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  open.overrideFor(OperatingSystem.iOS,
      () => DynamicLibrary.open('SQLCipher.framework/SQLCipher'));
}

/// True when [header] starts with the plaintext SQLite magic
/// "SQLite format 3\0". SQLCipher files start with a random salt instead.
bool isPlaintextSqliteHeader(List<int> header) {
  const magic = [
    0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, // "SQLite f"
    0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00, // "ormat 3\0"
  ];
  if (header.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (header[i] != magic[i]) return false;
  }
  return true;
}

/// What to do with an existing database file the stored key failed to open
/// with SQLITE_NOTADB ("file is not a database").
enum DbOpenFailureAction {
  /// Plaintext SQLite file (pre-encryption build, or a downgrade wrote one):
  /// legacy data the owner chose not to migrate ⇒ delete it.
  deleteLegacyPlaintext,

  /// Ciphertext (or garbage) that the stored key cannot open: wrong key or a
  /// corrupted first page. Deleting would destroy data that might still be
  /// recoverable, keeping it in place would brick the messenger ⇒ move it
  /// aside and start a fresh database with the current key.
  quarantine,
}

/// Pure decision for a preflight NOTADB failure — only the header decides.
/// (Storage readability is already proven at this point: the key was read.)
DbOpenFailureAction classifyOpenFailure(List<int> header) =>
    isPlaintextSqliteHeader(header)
        ? DbOpenFailureAction.deleteLegacyPlaintext
        : DbOpenFailureAction.quarantine;

/// Build the database executor. [awaitBeforeKeyAccess] runs before the key is
/// read (the iOS fresh-install keychain purge — a stale key from a previous
/// install must be purged before it could ever be adopted). [allowKeyCreation]
/// is true only on the main isolate.
QueryExecutor openEncryptedDatabase({
  required SecureStorageService storage,
  required bool allowKeyCreation,
  Future<void> Function()? awaitBeforeKeyAccess,
}) {
  return RetryableLazyDatabase(() async {
    if (awaitBeforeKeyAccess != null) await awaitBeforeKeyAccess();
    return _openEncrypted(
        storage: storage, allowKeyCreation: allowKeyCreation);
  });
}

Future<QueryExecutor> _openEncrypted({
  required SecureStorageService storage,
  required bool allowKeyCreation,
}) async {
  final sw = Stopwatch()..start();
  final paths = await EncryptedDatabasePaths.resolve();
  Directory(paths.directory).createSync(recursive: true);

  // Main-isolate library setup (the preflight below uses sqlite3 here).
  configureSqlCipherLibrary();
  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();

  // Key — throws DatabaseKeyUnavailableException (retryable) when secure
  // storage cannot prove the key's absence. Nothing is deleted before this.
  final keyManager = DatabaseKeyManager(storage);
  final resolution = await keyManager.resolve(
    allowCreate: allowKeyCreation,
    onBeforeCreate: () async {
      final removed = _deleteFiles(paths.databaseFiles);
      final purged = await AttachmentStorage.purgeContents();
      if (removed > 0 || purged > 0) {
        debugPrint('[DB] 🧹 no database key on readable storage — removed '
            '$removed keyless database file(s) + $purged attachment(s)');
      }
    },
  );

  // Legacy plaintext location (pre-encryption builds). Never encrypted data.
  // Runs only after the key resolved, i.e. never while storage is unreadable.
  try {
    final legacyRemoved = _deleteFiles(paths.legacyPlaintextFiles);
    if (legacyRemoved > 0) {
      debugPrint('[DB] 🧹 legacy plaintext database removed '
          '($legacyRemoved file(s)) — local history not migrated (alpha '
          'policy)');
    }
  } catch (e) {
    debugPrint('[DB] ❌ legacy plaintext database could NOT be removed: $e');
  }

  // Backup exclusion on the directory (covers sidecars created later).
  final excluded = await LocalFileProtection.excludeFromBackup(paths.directory);
  if (!excluded) {
    debugPrint('[DB] ⚠️ database directory NOT excluded from backup '
        '(retried on next open)');
  }

  final dbFile = File(paths.database);
  final existed = dbFile.existsSync();
  if (existed) {
    _preflight(paths, resolution.hexKey);
  }

  final hexKey = resolution.hexKey;
  final token = RootIsolateToken.instance;
  final executor = NativeDatabase.createInBackground(
    dbFile,
    isolateSetup: _isolateSetup(token),
    setup: _connectionSetup(hexKey),
  );
  debugPrint('[DB] 🔐 encrypted database ready in ${sw.elapsedMilliseconds}ms '
      '(key=${resolution.created ? 'created' : 'existing'}, '
      'file=${existed && dbFile.existsSync() ? 'existing' : 'new'})');
  return executor;
}

/// Open an existing file on this isolate with the key. Handles NOTADB per
/// [classifyOpenFailure]; any other failure is rethrown (loud).
void _preflight(EncryptedDatabasePaths paths, String hexKey) {
  sql.Database? db;
  try {
    db = sql.sqlite3.open(paths.database, mode: sql.OpenMode.readWrite);
    final version = assertSqlCipherActive(db);
    _applyKey(db, hexKey);
    db.select('SELECT count(*) FROM sqlite_master;');
    debugPrint('[DB] 🔐 SQLCipher $version — existing database decrypted OK');
  } on sql.SqliteException catch (e) {
    if (e.resultCode != sql.SqlError.SQLITE_NOTADB) rethrow;
    db?.dispose();
    db = null;
    final header = _readHeader(paths.database);
    switch (classifyOpenFailure(header)) {
      case DbOpenFailureAction.deleteLegacyPlaintext:
        final n = _deleteFiles(paths.databaseFiles);
        debugPrint('[DB] 🧹 plaintext database found next to a key — deleted '
            '($n file(s)); starting a fresh encrypted database');
      case DbOpenFailureAction.quarantine:
        _quarantine(paths);
        debugPrint('[DB] ❌❌ DATABASE UNDECRYPTABLE with the stored key '
            '(wrong key or corrupted page 1). Moved aside to '
            '${EncryptedDatabasePaths.fileName}'
            '${EncryptedDatabasePaths.quarantineSuffix} (NOT deleted); '
            'starting a fresh encrypted database.');
    }
  } finally {
    db?.dispose();
  }
}

/// Returns the SQLCipher version or throws — a stock sqlite3 silently ignores
/// PRAGMA key and would write plaintext.
String assertSqlCipherActive(sql.Database db) {
  final rows = db.select('PRAGMA cipher_version;');
  final version =
      rows.isEmpty ? null : rows.first.values.first?.toString().trim();
  if (version == null || version.isEmpty) {
    throw StateError('[DB] SQLCipher is NOT the active sqlite3 library '
        '(PRAGMA cipher_version empty) — refusing to open the database '
        'unencrypted');
  }
  return version;
}

void _applyKey(sql.Database db, String hexKey) {
  if (!DatabaseKeyManager.isValidHexKey(hexKey)) {
    throw StateError('[DB] invalid database key format');
  }
  db.execute("PRAGMA key = \"x'$hexKey'\";");
}

/// drift `isolateSetup` — runs in the drift background isolate before sqlite3
/// is touched there. Built by a top-level function so the closure captures
/// only the (sendable) root isolate token.
IsolateSetup _isolateSetup(RootIsolateToken? token) {
  return () async {
    configureSqlCipherLibrary();
    if (Platform.isAndroid) {
      // The workaround may fall back to a platform channel; background
      // isolates need the root token for that.
      if (token != null) {
        BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      }
      await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
    }
  };
}

/// drift `setup` — runs on the connection right after sqlite3_open, before
/// migrations / beforeOpen (WAL, synchronous). Captures only the hex key.
DatabaseSetup _connectionSetup(String hexKey) {
  return (sql.Database db) {
    final version = assertSqlCipherActive(db);
    _applyKey(db, hexKey);
    db.execute('PRAGMA secure_delete = ON;');
    // Fails with "file is not a database" here if the key does not match.
    db.select('SELECT count(*) FROM sqlite_master;');
    debugPrint('[DB] 🔐 SQLCipher $version active on the drift connection '
        '(keyed, secure_delete=ON)');
  };
}

List<int> _readHeader(String path) {
  RandomAccessFile? raf;
  try {
    raf = File(path).openSync();
    return raf.readSync(16);
  } catch (_) {
    return const [];
  } finally {
    raf?.closeSync();
  }
}

void _quarantine(EncryptedDatabasePaths paths) {
  _deleteFiles(paths.quarantineFiles);
  final from = paths.databaseFiles;
  final to = paths.quarantineFiles;
  for (var i = 0; i < from.length; i++) {
    final f = File(from[i]);
    if (!f.existsSync()) continue;
    // Rename within the same directory — atomic, keeps the backup exclusion.
    f.renameSync(to[i]);
  }
}

/// Delete [files] that exist. Returns how many were removed; a failure to
/// remove one is rethrown so a fresh database never lands on top of an old
/// file (that would mix two databases).
int _deleteFiles(List<String> files) {
  var removed = 0;
  for (final path in files) {
    final f = File(path);
    if (!f.existsSync()) continue;
    f.deleteSync();
    removed++;
  }
  return removed;
}

/// App reset / account delete. The SnowDatabase must be close()d first.
/// Order: database files (incl. quarantine + legacy) FIRST, key LAST — the key
/// is never removed while a populated database it belongs to still exists.
/// If a file cannot be deleted the key is still removed: without it the
/// remaining ciphertext is unreadable (crypto-erasure), and the next open
/// treats it as keyless and deletes it before creating a new key.
Future<void> deleteEncryptedDatabase(SecureStorageService storage) async {
  final paths = await EncryptedDatabasePaths.resolve();
  for (final path in [
    ...paths.databaseFiles,
    ...paths.quarantineFiles,
    ...paths.legacyPlaintextFiles,
  ]) {
    final f = File(path);
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (e) {
      debugPrint('[Reset] failed to delete ${p.basename(path)}: $e');
    }
  }
  try {
    await DatabaseKeyManager(storage).deleteKey();
  } catch (e) {
    debugPrint('[Reset] failed to delete database key: ${e.runtimeType}');
  }
}

/// drift's LazyDatabase caches a failed open for the life of the instance.
/// This variant forgets the failure when [isRetryable] says so (a locked
/// keychain), so the next query re-attempts the open once storage is readable.
/// All other failures (SQLCipher missing, I/O) stay sticky and loud.
class RetryableLazyDatabase extends QueryExecutor {
  final Future<QueryExecutor> Function() _opener;
  final bool Function(Object error) _isRetryable;

  QueryExecutor? _delegate;
  Completer<void>? _opening;

  RetryableLazyDatabase(
    this._opener, {
    bool Function(Object error)? isRetryable,
  }) : _isRetryable =
            isRetryable ?? ((e) => e is DatabaseKeyUnavailableException);

  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  Future<void> _awaitOpened() {
    if (_delegate != null) return Future.value();
    final pending = _opening;
    if (pending != null) return pending.future;
    final completer = _opening = Completer<void>();
    Future.sync(_opener).then((executor) {
      _delegate = executor;
      completer.complete();
    }, onError: (Object e, StackTrace st) {
      if (_isRetryable(e)) {
        debugPrint('[DB] ⏳ database open deferred: $e');
        if (identical(_opening, completer)) _opening = null;
      } else {
        debugPrint('[DB] ❌ database open failed: $e');
      }
      completer.completeError(e, st);
    });
    return completer.future;
  }

  QueryExecutor get _open {
    final d = _delegate;
    if (d == null) throw StateError('database used before ensureOpen');
    return d;
  }

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) =>
      _awaitOpened().then((_) => _open.ensureOpen(user));

  @override
  QueryExecutor beginExclusive() => _open.beginExclusive();

  @override
  TransactionExecutor beginTransaction() => _open.beginTransaction();

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _open.runBatched(statements);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _open.runCustom(statement, args);

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _open.runDelete(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _open.runInsert(statement, args);

  @override
  Future<List<Map<String, Object?>>> runSelect(
          String statement, List<Object?> args) =>
      _open.runSelect(statement, args);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _open.runUpdate(statement, args);

  @override
  Future<void> close() async {
    final d = _delegate;
    if (d != null) return d.close();
    final pending = _opening;
    if (pending == null) return;
    try {
      await pending.future;
    } catch (_) {
      return; // never opened — nothing to close
    }
    await _delegate?.close();
  }
}
