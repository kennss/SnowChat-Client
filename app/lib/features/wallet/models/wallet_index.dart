/// @file        wallet_index.dart
/// @description Multi-Wallet single-source-of-truth collection.
///              Serialized as JSON and stored under the `wallet_index_v1`
///              key in `flutter_secure_storage`. WalletIndexNotifier reads/
///              writes this value and enforces immutable invariants.
///
///              Core invariants (all checked at fromJson / mutator entry):
///                I1. primaryId must match some entry.id in entries
///                I2. defaultId must match some entry.id in entries
///                I3. exactly one entry with role==primary
///                I4. no duplicate id / address
///                I5. metadata.legacyKeysPendingCleanup stays true until
///                    step 8 deferred (Open Decision: v2.0.0 → v2.1.0)
///
///              On violation: throws [WalletIndexCorruptedException].
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - WalletIndex: immutable collection
///  - WalletIndex.empty(): empty index (do not use — primary required at bootstrap)
///  - WalletIndex.fromJson / toJson
///  - WalletIndex.copyWith / withEntry / withoutEntry / withDefault
///  - WalletIndex.primaryEntry / defaultEntry / activeEntry
///  - WalletIndex.derivedEntries / importedEntries / visibleEntries
///  - WalletIndex.nextDerivationAccountIndex(): C-2 monotonic
///  - WalletIndex.canAddDerived / canAddImported (Open Decisions)

library;

import 'package:flutter/foundation.dart';

import 'wallet_account_model.dart';
import 'wallet_index_exceptions.dart';

/// Multi-Wallet model constants. Open Decisions §11 recommended values (all approved).
abstract class WalletIndexLimits {
  /// Max derived sub-wallets (hidden included). Conservative choice within
  /// Phantom's pattern (5-10). Open Decision §11.1.
  static const int maxDerived = 5;

  /// Max imported wallets. dust-attack surface + UX limit (A-9).
  /// Open Decision (NEW).
  static const int maxImported = 10;
}

@immutable
class WalletIndex {
  WalletIndex({
    required this.entries,
    required this.primaryId,
    required this.defaultId,
    this.metadata = const WalletIndexMetadata(),
  }) {
    _enforceInvariants();
  }

  /// All wallet entries — Primary included.
  /// Order is the user-visible order (selector display order). Primary is
  /// always the first entry.
  final List<WalletEntry> entries;

  /// I1: id of the primary entry. immutable — this value must not change.
  /// However at storage-serialization time, potential corruption may exist
  /// alongside entries. `_enforceInvariants` checks every time.
  final String primaryId;

  /// I2: id of the current default entry. Changed via setDefault.
  final String defaultId;

  /// Auxiliary metadata (deferred cleanup flag, etc.).
  final WalletIndexMetadata metadata;

  // ---------------------------------------------------------------------------
  // Lookups
  // ---------------------------------------------------------------------------

  WalletEntry get primaryEntry =>
      entries.firstWhere((e) => e.id == primaryId);

  WalletEntry get defaultEntry =>
      entries.firstWhere((e) => e.id == defaultId);

  /// Entries shown to the user in the selector — excludes hidden.
  List<WalletEntry> get visibleEntries =>
      entries.where((e) => !e.hidden).toList();

  /// derived entries — hidden included (for next-index calculation).
  List<WalletEntry> get derivedEntries =>
      entries.where((e) => e.kind == WalletKind.derived).toList();

  /// imported entries — never hidden (imported uses permanent delete instead of hide).
  List<WalletEntry> get importedEntries =>
      entries.where((e) => e.kind == WalletKind.imported).toList();

  WalletEntry? findById(String id) {
    for (final e in entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  WalletEntry? findByAddress(String address) {
    for (final e in entries) {
      if (e.address == address) return e;
    }
    return null;
  }

  /// C-2 fix: next-available derivation account index is
  /// max(visible + hidden derived indexes) + 1. monotonic increasing.
  /// Index 0 must never be reused (Primary protection).
  int nextDerivationAccountIndex() {
    final indexes = derivedEntries
        .map((e) => e.derivationAccountIndex!)
        .toList();
    if (indexes.isEmpty) return 1; // primary occupies 0, so sub starts at 1+
    final maxIndex = indexes.reduce((a, b) => a > b ? a : b);
    return maxIndex + 1;
  }

  /// Whether a derived wallet can be added — checks max including hidden.
  bool get canAddDerived =>
      derivedEntries.length < WalletIndexLimits.maxDerived;

  /// Whether an imported wallet can be added.
  bool get canAddImported =>
      importedEntries.length < WalletIndexLimits.maxImported;

  // ---------------------------------------------------------------------------
  // Mutators (immutable copy with new state)
  // ---------------------------------------------------------------------------

  WalletIndex copyWith({
    List<WalletEntry>? entries,
    String? primaryId,
    String? defaultId,
    WalletIndexMetadata? metadata,
  }) {
    return WalletIndex(
      entries: entries ?? this.entries,
      primaryId: primaryId ?? this.primaryId,
      defaultId: defaultId ?? this.defaultId,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Add a new entry. Throws on duplicate id / address.
  /// Adding a Primary is forbidden (already one exists — invariant violation).
  WalletIndex withEntry(WalletEntry entry) {
    if (entry.role == WalletRole.primary) {
      throw const WalletIndexCorruptedException(
        'Cannot add a second primary entry.',
      );
    }
    if (findById(entry.id) != null) {
      throw const WalletIndexCorruptedException(
        'Duplicate wallet id.',
      );
    }
    if (findByAddress(entry.address) != null) {
      throw DuplicateWalletException(entry.address);
    }
    return copyWith(entries: [...entries, entry]);
  }

  /// Replace an entry (hide / rename / relabel etc.).
  WalletIndex updateEntry(String id, WalletEntry Function(WalletEntry) update) {
    final next = entries.map((e) => e.id == id ? update(e) : e).toList();
    return copyWith(entries: next);
  }

  /// Permanent delete of an imported wallet — removes the entry itself.
  /// derived entries are marked with hidden=true (separate method).
  WalletIndex withoutEntry(String id) {
    final entry = findById(id);
    if (entry == null) {
      throw WalletNotFoundException(id);
    }
    if (entry.role == WalletRole.primary || id == primaryId) {
      throw const CannotRemovePrimaryException();
    }
    final nextEntries = entries.where((e) => e.id != id).toList();
    // If Default is the one being deleted, fall back to Primary.
    final nextDefault = (id == defaultId) ? primaryId : defaultId;
    return copyWith(entries: nextEntries, defaultId: nextDefault);
  }

  /// Change Default. Validates invariant I2.
  WalletIndex withDefault(String newDefaultId) {
    if (findById(newDefaultId) == null) {
      throw WalletNotFoundException(newDefaultId);
    }
    return copyWith(defaultId: newDefaultId);
  }

  /// Set metadata.legacyKeysPendingCleanup to false.
  /// Called when v2.1.0 orphan-prune completes (final step of the F-6 deferred).
  WalletIndex markLegacyKeysCleaned() {
    return copyWith(
      metadata: metadata.copyWith(legacyKeysPendingCleanup: false),
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'version': 1,
        'entries': entries.map((e) => e.toJson()).toList(),
        'primaryId': primaryId,
        'defaultId': defaultId,
        'metadata': metadata.toJson(),
      };

  factory WalletIndex.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int?;
    if (version != 1) {
      throw WalletIndexCorruptedException(
        'Unsupported wallet_index version: $version',
      );
    }
    final entriesList = (json['entries'] as List?)
            ?.map((e) => WalletEntry.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <WalletEntry>[];
    final primaryId = json['primaryId'] as String?;
    final defaultId = json['defaultId'] as String?;
    if (primaryId == null || defaultId == null) {
      throw const WalletIndexCorruptedException(
        'wallet_index missing primaryId / defaultId',
      );
    }
    final metadataJson = json['metadata'] as Map<String, dynamic>?;
    final metadata = metadataJson != null
        ? WalletIndexMetadata.fromJson(metadataJson)
        : const WalletIndexMetadata();

    return WalletIndex(
      entries: entriesList,
      primaryId: primaryId,
      defaultId: defaultId,
      metadata: metadata,
    );
  }

  // ---------------------------------------------------------------------------
  // Invariants
  // ---------------------------------------------------------------------------

  void _enforceInvariants() {
    // I1
    final primaryMatch = entries.where((e) => e.id == primaryId).toList();
    if (primaryMatch.length != 1) {
      throw WalletIndexCorruptedException(
        'I1: primaryId "$primaryId" must match exactly one entry '
        '(matched ${primaryMatch.length}).',
      );
    }
    if (primaryMatch.single.role != WalletRole.primary) {
      throw const WalletIndexCorruptedException(
        'I1: primaryId entry has role != primary.',
      );
    }

    // I2
    if (entries.where((e) => e.id == defaultId).isEmpty) {
      throw WalletIndexCorruptedException(
        'I2: defaultId "$defaultId" not found in entries.',
      );
    }

    // I3
    final primaries =
        entries.where((e) => e.role == WalletRole.primary).toList();
    if (primaries.length != 1) {
      throw WalletIndexCorruptedException(
        'I3: must have exactly 1 primary entry (got ${primaries.length}).',
      );
    }

    // I4 — duplicate id
    final idsSeen = <String>{};
    for (final e in entries) {
      if (!idsSeen.add(e.id)) {
        throw WalletIndexCorruptedException(
          'I4: duplicate wallet id "${e.id}".',
        );
      }
    }
    // I4 — duplicate address
    final addressesSeen = <String>{};
    for (final e in entries) {
      if (!addressesSeen.add(e.address)) {
        throw WalletIndexCorruptedException(
          'I4: duplicate wallet address "${e.address}".',
        );
      }
    }
  }
}

/// Auxiliary metadata.
@immutable
class WalletIndexMetadata {
  const WalletIndexMetadata({
    this.legacyKeysPendingCleanup = false,
    this.migratedAtMs,
    this.schemaCreatedAtMs,
  });

  /// F-6 deferred: true right after v2.0.0 migration. false after v2.1.0
  /// boot completes orphan-prune.
  final bool legacyKeysPendingCleanup;

  final int? migratedAtMs;
  final int? schemaCreatedAtMs;

  WalletIndexMetadata copyWith({
    bool? legacyKeysPendingCleanup,
    int? migratedAtMs,
    int? schemaCreatedAtMs,
  }) {
    return WalletIndexMetadata(
      legacyKeysPendingCleanup:
          legacyKeysPendingCleanup ?? this.legacyKeysPendingCleanup,
      migratedAtMs: migratedAtMs ?? this.migratedAtMs,
      schemaCreatedAtMs: schemaCreatedAtMs ?? this.schemaCreatedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        if (legacyKeysPendingCleanup) 'legacyKeysPendingCleanup': true,
        if (migratedAtMs != null) 'migratedAtMs': migratedAtMs,
        if (schemaCreatedAtMs != null) 'schemaCreatedAtMs': schemaCreatedAtMs,
      };

  factory WalletIndexMetadata.fromJson(Map<String, dynamic> json) {
    return WalletIndexMetadata(
      legacyKeysPendingCleanup:
          (json['legacyKeysPendingCleanup'] as bool?) ?? false,
      migratedAtMs: json['migratedAtMs'] as int?,
      schemaCreatedAtMs: json['schemaCreatedAtMs'] as int?,
    );
  }
}
