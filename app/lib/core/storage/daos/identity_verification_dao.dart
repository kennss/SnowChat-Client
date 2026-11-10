/// @file        identity_verification_dao.dart
/// @description DAO for the IdentityVerifications table. Reads, writes, and
///              streams the per-peer Safety Number verification record.
///              Used by:
///                - VerifyIdentityScreen (read + manual mark/unmark)
///                - IdentityChangeHandler (TOFU mismatch latching)
///                - ChatScreen banner (watchByPeer for live UI)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-11-10 (B-2 Safety Number v2: currentVersion=2 over ACCOUNT public keys; dropPreV2Rows() invalidates every cached v1 number and resets every v1 verified=true (SC-14 made them meaningless); getCurrentByPeer()/isVerified() ignore pre-v2 rows; markKeyChange() latches a key-change event without needing a Safety Number (it does not change under v2 for same-account device-key changes); markMismatch() can force critical severity)
///
/// @functions
///  - getByPeer(snowchatId): Read the current verification row, or null.
///  - watchByPeer(snowchatId): Reactive single-row stream for UI.
///  - upsertVerification(...): Create or update a row (used by Verify
///                             screen on first load).
///  - markVerified(snowchatId): Set verified=true + verifiedAt=now.
///  - markUnverified(snowchatId): Set verified=false (clears verifiedAt).
///  - markMismatch(...): TOFU mismatch latch — wasPreviouslyVerified ←
///                       current verified, verified=false, lastChangedAt=now,
///                       update pinnedEd25519 and safetyNumber.
///  - deleteByPeer(snowchatId): Remove a peer's verification row (P2 cleanup
///                              on removeContact / blockContact / deleteChat).
///  - getCurrentByPeer(snowchatId): Row only if computed with the current algorithm
///  - isVerified(snowchatId): verified flag of a current-algorithm row
///  - dropPreV2Rows(): one-way Safety Number v2 migration (idempotent)
///  - markKeyChange(...): latch a key-change banner without a new number
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/identity_verifications_table.dart';

part 'identity_verification_dao.g.dart';

@DriftAccessor(tables: [IdentityVerifications])
class IdentityVerificationDao extends DatabaseAccessor<SnowDatabase>
    with _$IdentityVerificationDaoMixin {
  IdentityVerificationDao(super.db);

  /// B-2 Safety Number algorithm version (account-key fingerprint).
  static const int currentVersion = 2;

  /// Row for [snowchatId] only if it was computed with [currentVersion].
  Future<IdentityVerification?> getCurrentByPeer(String snowchatId) async {
    final row = await getByPeer(snowchatId);
    if (row == null || row.algorithmVersion < currentVersion) return null;
    return row;
  }

  /// True iff the user verified [snowchatId] under the current algorithm.
  Future<bool> isVerified(String snowchatId) async {
    final row = await getCurrentByPeer(snowchatId);
    return row?.verified ?? false;
  }

  /// One-way v1 → v2 migration: v1 numbers mixed the local ACCOUNT key with
  /// the peer's SIGNAL key (SC-14), so they never matched between honest
  /// peers — every cached number and every "verified" mark is meaningless.
  /// Deleting the rows invalidates both at once. Idempotent; safe to run on
  /// every start.
  Future<int> dropPreV2Rows() {
    return (delete(identityVerifications)
          ..where((v) => v.algorithmVersion.isSmallerThanValue(currentVersion)))
        .go();
  }

  /// Latch a key-change event for [snowchatId] (banner + severity) without a
  /// new Safety Number. [critical] forces the red "previously verified"
  /// severity (used for suspected interception). Creates a placeholder row
  /// (empty key / number — recomputed by the verify screen) when absent.
  Future<void> markKeyChange({
    required String snowchatId,
    bool critical = false,
  }) async {
    if (snowchatId.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final existing = await getCurrentByPeer(snowchatId);
    if (existing == null) {
      await deleteByPeer(snowchatId); // drop any stale pre-v2 row
      await into(identityVerifications).insert(
        IdentityVerificationsCompanion.insert(
          peerSnowchatId: snowchatId,
          pinnedEd25519: '',
          safetyNumber: '',
          verified: const Value(false),
          lastChangedAt: Value(nowMs),
          wasPreviouslyVerified: Value(critical),
          algorithmVersion: const Value(currentVersion),
          createdAt: nowMs,
          updatedAt: nowMs,
        ),
      );
      return;
    }
    await (update(identityVerifications)
          ..where((v) => v.peerSnowchatId.equals(snowchatId)))
        .write(IdentityVerificationsCompanion(
      verified: const Value(false),
      verifiedAt: const Value(null),
      lastChangedAt: Value(nowMs),
      wasPreviouslyVerified: Value(critical || existing.verified),
      updatedAt: Value(nowMs),
    ));
  }

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  /// Single-row lookup. Returns null if no verification row exists yet.
  Future<IdentityVerification?> getByPeer(String snowchatId) {
    if (snowchatId.isEmpty) return Future.value(null);
    return (select(identityVerifications)
          ..where((v) => v.peerSnowchatId.equals(snowchatId)))
        .getSingleOrNull();
  }

  /// Reactive single-row stream — drift fires on any write to the table
  /// affecting this peer. Drives the chat-screen banner and verify screen.
  Stream<IdentityVerification?> watchByPeer(String snowchatId) {
    if (snowchatId.isEmpty) return const Stream.empty();
    return (select(identityVerifications)
          ..where((v) => v.peerSnowchatId.equals(snowchatId)))
        .watchSingleOrNull();
  }

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  /// Insert or update the row for [snowchatId]. Used by the Verify screen
  /// on first open (caches the freshly computed Safety Number) and after
  /// any code path that needs to refresh the cached display value without
  /// raising a mismatch.
  ///
  /// Does NOT clear [wasPreviouslyVerified] / [lastChangedAt] — those are
  /// owned by [markMismatch] and never silently reset by this method.
  Future<void> upsertVerification({
    required String snowchatId,
    required Uint8List ed25519Key,
    required String safetyNumber,
    int algorithmVersion = currentVersion,
  }) async {
    if (snowchatId.isEmpty) {
      throw ArgumentError('upsertVerification: snowchatId must not be empty');
    }
    if (ed25519Key.length != 32) {
      throw ArgumentError(
          'upsertVerification: Ed25519 key must be 32 bytes');
    }
    if (safetyNumber.length != 60) {
      throw ArgumentError(
          'upsertVerification: safetyNumber must be 60 digits');
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final keyB64 = base64Encode(ed25519Key);

    final existing = await getByPeer(snowchatId);
    if (existing == null) {
      await into(identityVerifications).insert(
        IdentityVerificationsCompanion.insert(
          peerSnowchatId: snowchatId,
          pinnedEd25519: keyB64,
          safetyNumber: safetyNumber,
          algorithmVersion: Value(algorithmVersion),
          createdAt: nowMs,
          updatedAt: nowMs,
        ),
      );
      return;
    }

    await (update(identityVerifications)
          ..where((v) => v.peerSnowchatId.equals(snowchatId)))
        .write(IdentityVerificationsCompanion(
      pinnedEd25519: Value(keyB64),
      safetyNumber: Value(safetyNumber),
      algorithmVersion: Value(algorithmVersion),
      updatedAt: Value(nowMs),
    ));
  }

  /// User confirmed the displayed Safety Number matches the peer's screen.
  /// Idempotent.
  Future<void> markVerified(String snowchatId) async {
    if (snowchatId.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await (update(identityVerifications)
          ..where((v) => v.peerSnowchatId.equals(snowchatId)))
        .write(IdentityVerificationsCompanion(
      verified: const Value(true),
      verifiedAt: Value(nowMs),
      updatedAt: Value(nowMs),
    ));
  }

  /// User toggled verification off (without a mismatch event).
  Future<void> markUnverified(String snowchatId) async {
    if (snowchatId.isEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await (update(identityVerifications)
          ..where((v) => v.peerSnowchatId.equals(snowchatId)))
        .write(IdentityVerificationsCompanion(
      verified: const Value(false),
      verifiedAt: const Value(null),
      updatedAt: Value(nowMs),
    ));
  }

  /// P2: Delete the verification row for [snowchatId]. Used by removeContact /
  /// blockContact / deleteChat (1:1) flows so stale rows do not accumulate.
  /// Idempotent — no-op if row absent.
  Future<void> deleteByPeer(String snowchatId) async {
    if (snowchatId.isEmpty) return;
    await (delete(identityVerifications)
          ..where((v) => v.peerSnowchatId.equals(snowchatId)))
        .go();
  }

  /// Latch a TOFU mismatch:
  ///   - wasPreviouslyVerified ← current verified value (snapshot)
  ///   - verified ← false
  ///   - lastChangedAt ← now
  ///   - pinnedEd25519 ← base64(newKey)
  ///   - safetyNumber  ← newSafetyNumber
  ///
  /// If no prior row exists, create one with verified=false. This is the
  /// only entry point that should ever flip wasPreviouslyVerified to true,
  /// so the banner severity decision (red vs amber) stays correct.
  Future<void> markMismatch({
    required String snowchatId,
    required Uint8List newKey,
    required String newSafetyNumber,
    int algorithmVersion = currentVersion,
  }) async {
    if (snowchatId.isEmpty) {
      throw ArgumentError('markMismatch: snowchatId must not be empty');
    }
    if (newKey.length != 32) {
      throw ArgumentError('markMismatch: Ed25519 key must be 32 bytes');
    }
    if (newSafetyNumber.length != 60) {
      throw ArgumentError(
          'markMismatch: safetyNumber must be 60 digits');
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final keyB64 = base64Encode(newKey);
    final existing = await getByPeer(snowchatId);

    if (existing == null) {
      // First sighting that already failed TOFU — wasPreviouslyVerified=false
      // because we've never had a verified pin to compare against.
      await into(identityVerifications).insert(
        IdentityVerificationsCompanion.insert(
          peerSnowchatId: snowchatId,
          pinnedEd25519: keyB64,
          safetyNumber: newSafetyNumber,
          verified: const Value(false),
          lastChangedAt: Value(nowMs),
          wasPreviouslyVerified: const Value(false),
          algorithmVersion: Value(algorithmVersion),
          createdAt: nowMs,
          updatedAt: nowMs,
        ),
      );
      return;
    }

    await (update(identityVerifications)
          ..where((v) => v.peerSnowchatId.equals(snowchatId)))
        .write(IdentityVerificationsCompanion(
      pinnedEd25519: Value(keyB64),
      safetyNumber: Value(newSafetyNumber),
      verified: const Value(false),
      verifiedAt: const Value(null),
      lastChangedAt: Value(nowMs),
      // Snapshot what the user's verification stance was at the moment of
      // the mismatch so the UI can color-code the banner correctly.
      wasPreviouslyVerified: Value(existing.verified),
      algorithmVersion: Value(algorithmVersion),
      updatedAt: Value(nowMs),
    ));
  }
}
