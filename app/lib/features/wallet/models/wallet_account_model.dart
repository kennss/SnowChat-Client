/// @file        wallet_account_model.dart
/// @description Multi-Wallet (Phase 1, Foundation) — `WalletEntry` and helper
///              enum/label classes. Core data types for the Primary + Sub +
///              Default model. The serialization (toJson/fromJson) is stored
///              directly as the `wallet_index_v1` value in
///              flutter_secure_storage. Reflects Multi-Wallet-Design-FINAL.md
///              §1 + §2 + Open Decisions (all recommended values adopted).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - WalletKind: derived (mnemonic) | imported (external key)
///  - WalletRole: primary (permanent) | sub (user-added)
///  - WalletEntry: per-wallet metadata (no secret)
///  - WalletEntry.fromJson / toJson: serialization
///  - WalletEntry.copyWith: immutable update
///  - WalletLabels: const / i18n-friendly label helper

library;

import 'package:flutter/foundation.dart';

/// How the wallet's private key was generated.
///
/// - [derived] : Derived from a BIP44 account index of the SnowChat
///               identity_mnemonic. Reproducible any time from mnemonic.
///               Safe to delete.
/// - [imported] : Externally provided secret material. Deletion = permanent
///                key loss (recoverable only if an external backup exists).
enum WalletKind { derived, imported }

/// Role within the wallet list.
///
/// - [primary] : First wallet auto-created at onboarding. Derived from
///               account index 0 of the same mnemonic as SnowChat ID.
///               **Cannot be deleted / replaced.** Exactly one entry holds
///               this role.
/// - [sub]     : Wallet manually added by the user (derived or imported).
///               Multiple may exist. Can be hidden / removed.
enum WalletRole { primary, sub }

/// Single-wallet metadata in the Multi-Wallet model — no secret material.
///
/// This is the entry serialized as JSON under the `wallet_index_v1` key of
/// `flutter_secure_storage`. The actual private key is obtained either from
/// a separate key (`wallet_secret/<id>` for [WalletKind.imported]) or
/// derived on the fly from the mnemonic (for [WalletKind.derived]) —
/// therefore secrets are never serialized in this class.
@immutable
class WalletEntry {
  const WalletEntry({
    required this.id,
    required this.address,
    required this.kind,
    required this.role,
    required this.label,
    required this.createdAtMs,
    this.derivationAccountIndex,
    this.hidden = false,
  })  : assert(
          kind != WalletKind.derived || derivationAccountIndex != null,
          'derived wallet must have derivationAccountIndex',
        ),
        assert(
          kind != WalletKind.imported || derivationAccountIndex == null,
          'imported wallet must NOT have derivationAccountIndex',
        ),
        assert(
          // F-4 mismatch branch case: a primary may be imported.
          // Only derived primary is forced to account 0. Imported primary has null index.
          !(role == WalletRole.primary && kind == WalletKind.derived) ||
              derivationAccountIndex == 0,
          'derived primary wallet must be at account index 0',
        );

  /// `wal_<base58 12 chars>` format. Generated via CSPRNG (Random.secure()).
  /// Stable identifier for the wallet — preserved even when the label changes.
  final String id;

  /// Solana Base58 public key. For derived wallets, always reproducible from
  /// mnemonic + index. For imported, derived from the secret.
  final String address;

  final WalletKind kind;
  final WalletRole role;

  /// User-facing label. Editable directly. Default comes from [WalletLabels].
  final String label;

  final int createdAtMs;

  /// BIP44 account index of a derived wallet. `m/44'/501'/{index}'/0'`.
  /// Always null for imported.
  final int? derivationAccountIndex;

  /// Soft-delete flag for "removed" derived wallets.
  /// derived entries with hidden=true are hidden from the wallet selector,
  /// but still count toward the next-available calculation so the same
  /// index is never re-derived (C-2 fix).
  /// imported wallets are not hidden — they are permanently deleted (the
  /// entry itself is removed).
  final bool hidden;

  WalletEntry copyWith({
    String? id,
    String? address,
    WalletKind? kind,
    WalletRole? role,
    String? label,
    int? createdAtMs,
    int? derivationAccountIndex,
    bool? hidden,
  }) {
    return WalletEntry(
      id: id ?? this.id,
      address: address ?? this.address,
      kind: kind ?? this.kind,
      role: role ?? this.role,
      label: label ?? this.label,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      derivationAccountIndex:
          derivationAccountIndex ?? this.derivationAccountIndex,
      hidden: hidden ?? this.hidden,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'address': address,
        'kind': kind.name,
        'role': role.name,
        'label': label,
        'createdAtMs': createdAtMs,
        if (derivationAccountIndex != null)
          'derivationAccountIndex': derivationAccountIndex,
        if (hidden) 'hidden': true,
      };

  factory WalletEntry.fromJson(Map<String, dynamic> json) {
    return WalletEntry(
      id: json['id'] as String,
      address: json['address'] as String,
      kind: WalletKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => throw FormatException(
          'Unknown WalletKind: ${json['kind']}',
        ),
      ),
      role: WalletRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => throw FormatException(
          'Unknown WalletRole: ${json['role']}',
        ),
      ),
      label: json['label'] as String,
      createdAtMs: json['createdAtMs'] as int,
      derivationAccountIndex: json['derivationAccountIndex'] as int?,
      hidden: (json['hidden'] as bool?) ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WalletEntry &&
          id == other.id &&
          address == other.address &&
          kind == other.kind &&
          role == other.role &&
          label == other.label &&
          createdAtMs == other.createdAtMs &&
          derivationAccountIndex == other.derivationAccountIndex &&
          hidden == other.hidden;

  @override
  int get hashCode => Object.hash(
        id,
        address,
        kind,
        role,
        label,
        createdAtMs,
        derivationAccountIndex,
        hidden,
      );

  @override
  String toString() =>
      'WalletEntry(id=$id, address=${address.substring(0, 6)}…, '
      'kind=$kind, role=$role, label="$label", '
      'idx=$derivationAccountIndex, hidden=$hidden)';
}

/// const/i18n-friendly label helper.
/// Compromise between CLAUDE.md "unify UI in English" and "no hardcoding" —
/// gather fixed strings in one place. Map to i18n keys later from this single
/// site.
abstract class WalletLabels {
  /// Default label for the primary entry.
  static const String primary = 'Main Wallet';

  /// Default label pattern for derived sub-wallets — mirrors Phantom's
  /// "Account N" pattern.
  /// e.g. account index 1 → "Account 2" (1-based index user sees).
  /// `n` is the Phantom-compatible derivation account index (0-based).
  /// Display is +1.
  static String derivedAccount(int derivationAccountIndex) {
    return 'Account ${derivationAccountIndex + 1}';
  }

  /// Default label for imported wallets. Users are encouraged to rename
  /// immediately.
  static const String importedDefault = 'Imported Wallet';

  /// Distinct label (F-4 fix) for an imported entry registered as Primary in
  /// the migration mismatch branch — differentiated from the regular imported
  /// label.
  static const String legacyPrimary = 'Main Wallet (Legacy)';
}
