/// @file        local_file_protection.dart
/// @description At-rest protection level 1 — on-disk policy for local files
///              outside the encrypted database.
///
///              iOS (MethodChannel `snowchat/file_protection`, AppDelegate.swift):
///               - Directories holding the database and decrypted attachments
///                 are excluded from iCloud / Finder backups
///                 (NSURLIsExcludedFromBackupKey on the directory covers files
///                 created inside it later, incl. SQLite -wal / -shm).
///               - The attachments directory gets the default data-protection
///                 class NSFileProtectionCompleteUnlessOpen: files created while
///                 the device is locked (background receipt) stay writable while
///                 open, but once closed they cannot be read until the user
///                 unlocks. Existing files are converted once per process.
///                 NEVER applied to the database — it must open in the
///                 background while locked-after-first-unlock.
///              Android: backups / device transfers are excluded declaratively
///              (res/xml/data_extraction_rules.xml); file-based encryption
///              already covers at-rest, so every call here is a no-op.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-11
/// @lastUpdated 2026-11-11
///
/// @functions
///  - LocalFileProtection.excludeFromBackup(path): iOS backup exclusion
///  - LocalFileProtection.protectAttachmentDirectory(path): iOS dir policy + sweep
///  - LocalFileProtection.protectAttachmentFile(path): iOS per-file class
///  - AttachmentStorage.directoryName: 'snowchat_attachments' (relative root)
///  - AttachmentStorage.ensureDirectory(): create + protect the attachments dir
///  - AttachmentStorage.protectFile(path): enforce the class on a copied file
///  - AttachmentStorage.purgeContents(): delete every file in the dir (fresh DB)
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalFileProtection {
  static const MethodChannel _channel =
      MethodChannel('snowchat/file_protection');

  /// Exclude [path] (file or directory) from device backups. iOS only.
  /// Returns false when the attribute could not be set.
  static Future<bool> excludeFromBackup(String path) async {
    if (!Platform.isIOS) return true;
    try {
      final ok = await _channel
          .invokeMethod<bool>('excludeFromBackup', {'path': path});
      return ok ?? false;
    } catch (e) {
      debugPrint('[FileProtection] ❌ excludeFromBackup failed '
          '(${p.basename(path)}): $e');
      return false;
    }
  }

  /// iOS: exclude the attachments directory from backups, make
  /// CompleteUnlessOpen its default class for new files and convert the files
  /// already inside it. Returns the number of files that could NOT be
  /// converted (e.g. device locked right now), or -1 on channel failure.
  static Future<int> protectAttachmentDirectory(String path) async {
    if (!Platform.isIOS) return 0;
    try {
      final failed = await _channel
          .invokeMethod<int>('protectAttachmentDirectory', {'path': path});
      return failed ?? -1;
    } catch (e) {
      debugPrint('[FileProtection] ❌ protectAttachmentDirectory failed: $e');
      return -1;
    }
  }

  /// iOS: set CompleteUnlessOpen on one file. Used after File.copy, whose
  /// metadata copy must not leave a weaker class on the destination.
  static Future<bool> protectAttachmentFile(String path) async {
    if (!Platform.isIOS) return true;
    try {
      final ok = await _channel
          .invokeMethod<bool>('protectAttachmentFile', {'path': path});
      return ok ?? false;
    } catch (e) {
      debugPrint('[FileProtection] ❌ protectAttachmentFile failed '
          '(${p.basename(path)}): $e');
      return false;
    }
  }
}

/// Single owner of the decrypted-attachments directory
/// (`<ApplicationDocuments>/snowchat_attachments/`). Every writer obtains the
/// directory through [ensureDirectory] so it is never created without the
/// protection policy.
class AttachmentStorage {
  /// Relative root stored in drift (`snowchat_attachments/{fileId}.{ext}`).
  static const String directoryName = 'snowchat_attachments';

  /// Once per process: the policy (incl. the sweep of existing files) has
  /// been applied successfully. Reset on failure so a later call retries.
  static Future<void>? _protected;

  /// Create the attachments directory if needed and make sure the protection
  /// policy was applied in this process. Never throws for policy failures —
  /// those are logged loudly and retried on the next call.
  static Future<Directory> ensureDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, directoryName));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final pending = _protected ??= _applyPolicy(dir.path);
    await pending;
    return dir;
  }

  static Future<void> _applyPolicy(String path) async {
    final failed = await LocalFileProtection.protectAttachmentDirectory(path);
    if (failed == 0) {
      debugPrint('[FileProtection] 🔒 attachments dir protected '
          '(backup-excluded, CompleteUnlessOpen)');
      return;
    }
    debugPrint('[FileProtection] ⚠️ attachments protection incomplete '
        '(failed=$failed) — will retry');
    _protected = null;
  }

  /// Enforce the protection class on a file just written into the directory.
  static Future<void> protectFile(String absolutePath) async {
    await LocalFileProtection.protectAttachmentFile(absolutePath);
  }

  /// Delete every file in the attachments directory (keeps the directory and
  /// its policy). Used when a fresh database is created: attachments of the
  /// discarded database have no rows left and would linger as plaintext.
  static Future<int> purgeContents() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, directoryName));
    if (!dir.existsSync()) return 0;
    var removed = 0;
    for (final entity in dir.listSync(followLinks: false)) {
      try {
        entity.deleteSync(recursive: true);
        removed++;
      } catch (e) {
        debugPrint('[FileProtection] ❌ failed to purge attachment '
            '${p.basename(entity.path)}: $e');
      }
    }
    return removed;
  }
}
