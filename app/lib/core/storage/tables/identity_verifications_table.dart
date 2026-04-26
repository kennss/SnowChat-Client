/// @file        identity_verifications_table.dart
/// @description Drift table that records the verification state of every
///              peer SnowChat ID we have a Signal session with. Tracks the
///              currently pinned Ed25519 identity key, the Signal-compatible
///              60-digit Safety Number derived from it, whether the local
///              user has manually marked it verified, and — critically for
///              the "key changed" warning UX — whether the prior pinning
///              was already verified at the time of a TOFU mismatch.
///
///              Schema rationale:
///                - peerSnowchatId is the primary key; one row per peer.
///                - pinnedEd25519 is the Ed25519 raw public key (32 bytes)
///                  stored base64 so the column stays a TEXT column with
///                  human-inspectable contents in development.
///                - safetyNumber is the 60-digit display value (no spaces),
///                  cached to avoid recomputing 5200 SHA-512 rounds per UI
///                  build.
///                - verified / verifiedAt: result of explicit user action
///                  ("Mark as Verified" toggle) — not a TOFU pin.
///                - lastChangedAt + wasPreviouslyVerified: latched on a
///                  detected mismatch so the UI can show the appropriate
///                  banner severity (red if previously verified, amber if
///                  unverified TOFU re-pin).
///                - algorithmVersion mirrors the version used by
///                  [SafetyNumber.compute]; future migrations can
///                  recompute on read if the value advances.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-18
///
/// @functions
///  - IdentityVerifications: per-peer Safety Number verification record
library;

import 'package:drift/drift.dart';

class IdentityVerifications extends Table {
  /// Peer SnowChat ID (snow + 32 hex). One row per peer.
  TextColumn get peerSnowchatId => text()();

  /// Currently pinned Ed25519 identity key, base64-encoded raw bytes.
  TextColumn get pinnedEd25519 => text()();

  /// Cached 60-digit Safety Number (no spaces).
  TextColumn get safetyNumber => text()();

  /// True iff the user has explicitly marked the current Safety Number as
  /// verified (e.g. compared in person / over a video call).
  BoolColumn get verified => boolean().withDefault(const Constant(false))();

  /// Wall-clock ms-epoch of the last "Mark as Verified" action.
  IntColumn get verifiedAt => integer().nullable()();

  /// Wall-clock ms-epoch of the last detected key-mismatch event.
  IntColumn get lastChangedAt => integer().nullable()();

  /// Snapshot of [verified] at the moment of a detected mismatch. Drives the
  /// "previously verified" red banner vs. plain TOFU re-pin amber banner.
  BoolColumn get wasPreviouslyVerified =>
      boolean().withDefault(const Constant(false))();

  /// Safety Number algorithm version used to compute [safetyNumber].
  /// Defaults to 1 (Signal v1 5200-round SHA-512).
  IntColumn get algorithmVersion =>
      integer().withDefault(const Constant(1))();

  /// ms-epoch of row creation.
  IntColumn get createdAt => integer()();

  /// ms-epoch of last write.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {peerSnowchatId};
}
