/// @file        wallet_v2_migration.dart
/// @description Multi-Wallet v1 → v2 schema migration logic.
///              Bootstrap entry — idempotent + crash-safe + verified-write.
///              Reflects every hardening from Multi-Wallet-Design-FINAL.md §5:
///                F-1: routing barrier (caller's responsibility — wait while Future pending)
///                F-2: orphan cleanup
///                F-3: concurrent-call mutex (Future caching)
///                F-4: mismatch branch label "Main Wallet (Legacy)"
///                F-5: per-delete try-catch
///                F-6: step 8 (legacy-key deletion) deferred to v2.1.0
///                C-4: primary integrity check even on the idempotent path
///
///              Usage:
///                final mig = WalletV2Migration(storage, identityReader);
///                await mig.bootstrap();   // performs work on first call only
///                await mig.bootstrap();   // subsequent calls return cached future
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - WalletV2Migration: bootstrap orchestrator
///  - WalletV2Migration.bootstrap(): main entry, idempotent
///  - BootstrapOutcome: enum result (used by caller for UI / banner)

library;

import 'dart:async';
import 'dart:convert';

import '../models/wallet_account_model.dart';
import '../models/wallet_index.dart';
import 'derivation_service.dart';
import 'secure_wallet_storage.dart';
import 'wallet_id_generator.dart';

/// Result of `bootstrap()` — UI uses it to decide banner / state.
enum BootstrapOutcome {
  /// v2 schema already present (idempotent path). primary integrity OK.
  alreadyMigrated,

  /// First boot. No legacy either (fresh install). User onboarding needed.
  freshInstall,

  /// v1 → v2 migration succeeded.
  migratedFromV1,

  /// v2 schema present but the primary entry's address mismatches the
  /// identity_mnemonic derive result (C-4). UI shows a banner + restore guide.
  primaryIntegrityViolated,
}

/// Function signature for reading `identity_mnemonic`. Injected so the
/// migration does not depend on IdentityManager — fake-able in tests.
typedef IdentityMnemonicReader = Future<String?> Function();

class WalletV2Migration {
  WalletV2Migration({
    required SecureWalletStorage storage,
    required IdentityMnemonicReader identityReader,
    DateTime Function()? nowProvider,
  })  : _storage = storage,
        _readIdentityMnemonic = identityReader,
        _now = nowProvider ?? DateTime.now;

  final SecureWalletStorage _storage;
  final IdentityMnemonicReader _readIdentityMnemonic;
  final DateTime Function() _now;

  /// F-3 mutex: under concurrent calls, all callers await the first call's future.
  Future<BootstrapOutcome>? _bootstrapFuture;

  /// Last bootstrap result — reused by callers for subsequent queries.
  BootstrapOutcome? lastOutcome;

  /// Multi-wallet bootstrap main entry. Called once at app start.
  /// If already in progress, returns the same future (idempotent + race-safe).
  Future<BootstrapOutcome> bootstrap() {
    return _bootstrapFuture ??= _bootstrapInner();
  }

  Future<BootstrapOutcome> _bootstrapInner() async {
    // ===========================================================
    // Step 1: Check whether v2 schema exists
    // ===========================================================
    final indexJson = await _storage.readWalletIndexJson();
    if (indexJson != null) {
      // Idempotent path. C-4 integrity check.
      final outcome = await _verifyExistingIndex(indexJson);
      lastOutcome = outcome;
      return outcome;
    }

    // ===========================================================
    // Step 2: Check whether legacy keys exist
    // ===========================================================
    final hasLegacy = await _storage.hasLegacyKeys();
    if (!hasLegacy) {
      // Fresh install — onboarding will create a new wallet.
      lastOutcome = BootstrapOutcome.freshInstall;
      return BootstrapOutcome.freshInstall;
    }

    // ===========================================================
    // Step 3-7: Migration
    // ===========================================================
    final outcome = await _migrate();
    lastOutcome = outcome;
    return outcome;
  }

  /// When v2 schema already exists — verify the primary entry's address
  /// matches the identity_mnemonic derive result (C-4).
  Future<BootstrapOutcome> _verifyExistingIndex(String indexJson) async {
    final index = WalletIndex.fromJson(
      jsonDecode(indexJson) as Map<String, dynamic>,
    );
    final primary = index.primaryEntry;

    // For an imported primary (mismatch branch), skip verification — by
    // definition its address differs from derive (F-4 case).
    if (primary.kind != WalletKind.derived) {
      return BootstrapOutcome.alreadyMigrated;
    }

    final mnemonic = await _readIdentityMnemonic();
    if (mnemonic == null || mnemonic.isEmpty) {
      // No identity_mnemonic but a derived primary — abnormal but fail-soft.
      // Pass as alreadyMigrated so the user can recover via restore flow.
      return BootstrapOutcome.alreadyMigrated;
    }

    final expected = await DerivationService.deriveWalletAddressAt(
      mnemonic,
      primary.derivationAccountIndex!, // derived is always non-null (assert)
    );
    if (expected != primary.address) {
      // C-4 integrity violation. UI shows a banner.
      return BootstrapOutcome.primaryIntegrityViolated;
    }

    return BootstrapOutcome.alreadyMigrated;
  }

  /// Core of the first v2 boot — convert legacy keys into v2 schema.
  Future<BootstrapOutcome> _migrate() async {
    // ===========================================================
    // Step 3: Decide migration case
    //   3a. derived match  : derive(identity_mnemonic, account 0) == legacyAddress
    //   3b. mismatch       : derive result != legacy, or identity_mnemonic missing
    //
    //   The previous approach (mnemonic-string equality) caused false-mismatch
    //   whenever the wallet_mnemonic key differed from the identity_mnemonic
    //   key. Address-derive comparison is the real correctness check
    //   (Phase 3 fix).
    // ===========================================================
    final identityMnemonic = await _readIdentityMnemonic();
    final legacyAddress = await _storage.readSolanaAddress();
    final legacyPrivKey = await _storage.readPrivateKey();

    if (legacyAddress == null || legacyAddress.isEmpty) {
      // Only legacy mnemonic / private key present, no address — partial state.
      // Since address is required, treat as fresh install.
      lastOutcome = BootstrapOutcome.freshInstall;
      return BootstrapOutcome.freshInstall;
    }

    final WalletKind primaryKind;
    final String primaryLabel;

    String? derivedAddress;
    if (identityMnemonic != null && identityMnemonic.isNotEmpty) {
      try {
        derivedAddress = await DerivationService.deriveWalletAddressAt(
          identityMnemonic,
          0,
        );
      } catch (_) {
        derivedAddress = null;
      }
    }

    if (derivedAddress != null && derivedAddress == legacyAddress) {
      // Step 3a — standard case. Primary is derived (account 0).
      primaryKind = WalletKind.derived;
      primaryLabel = WalletLabels.primary;
    } else {
      // Step 3b — mismatch or identity missing. Primary is imported (legacy).
      // F-4: label shows "Legacy".
      primaryKind = WalletKind.imported;
      primaryLabel = WalletLabels.legacyPrimary;
    }

    // ===========================================================
    // Step 4: Build WalletEntry
    // ===========================================================
    final primaryId = WalletIdGenerator.generate();
    final nowMs = _now().millisecondsSinceEpoch;

    final WalletEntry primaryEntry;
    if (primaryKind == WalletKind.derived) {
      primaryEntry = WalletEntry(
        id: primaryId,
        address: legacyAddress,
        kind: WalletKind.derived,
        role: WalletRole.primary,
        label: primaryLabel,
        createdAtMs: nowMs,
        derivationAccountIndex: 0,
      );
    } else {
      primaryEntry = WalletEntry(
        id: primaryId,
        address: legacyAddress,
        kind: WalletKind.imported,
        role: WalletRole.primary,
        label: primaryLabel,
        createdAtMs: nowMs,
        // imported has null derivationAccountIndex (assert)
      );
    }

    // ===========================================================
    // Step 5: Save the imported primary's secret to wallet_secret/<id>
    // ===========================================================
    if (primaryKind == WalletKind.imported &&
        legacyPrivKey != null &&
        legacyPrivKey.length == 32) {
      try {
        await _storage.writeImportedSecret(primaryId, legacyPrivKey);
      } catch (e) {
        // Possible secret-save failure — to retry on next boot, do not
        // write index and fall back to fresh install.
        // User funds safety: legacy keys are kept (F-6 deferred).
        return BootstrapOutcome.freshInstall;
      }
    }

    // ===========================================================
    // Step 6: Write WalletIndex (legacyKeysPendingCleanup=true)
    // ===========================================================
    final index = WalletIndex(
      entries: [primaryEntry],
      primaryId: primaryId,
      defaultId: primaryId,
      metadata: WalletIndexMetadata(
        legacyKeysPendingCleanup: true, // F-6 deferred
        migratedAtMs: nowMs,
        schemaCreatedAtMs: nowMs,
      ),
    );

    final json = jsonEncode(index.toJson());
    await _storage.writeWalletIndexJson(json);

    // ===========================================================
    // Step 7: Verified write — read-compare round-trip (F-2)
    // ===========================================================
    final readback = await _storage.readWalletIndexJson();
    if (readback != json) {
      // Verification failed. Keep legacy keys — retry on next boot.
      // step 6's write succeeded but read returned a different result —
      // keystore corruption suspected. The right way would be to guide
      // the user to fresh install, but at the bootstrap stage we return
      // freshInstall as fail-soft.
      // On next boot, step 1 sees indexJson != null and takes the idempotent path.
      return BootstrapOutcome.freshInstall;
    }

    // ===========================================================
    // Step 8: F-6 deferred — DO NOT delete legacy keys in v2.0.0
    // ===========================================================
    // Legacy-key deletion is performed by v2.1.0's orphan-prune.
    // At this point migration finishes with metadata.legacyKeysPendingCleanup
    // = true. On a v1 downgrade, legacy keys are still present so v1 code
    // works correctly (rollback safety).

    return BootstrapOutcome.migratedFromV1;
  }
}
