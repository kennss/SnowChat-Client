/// @file        wallet_index_exceptions.dart
/// @description Multi-Wallet domain-specific exception types. Thrown by
///              WalletIndexNotifier / WalletNotifier / SecureWalletStorage
///              and caught by the UI layer to convert into user-friendly
///              messages. All exceptions share the same base class — a
///              single try-catch can handle them polymorphically.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - WalletException: base
///  - CannotRemovePrimaryException
///  - DuplicateWalletException
///  - SelfImportRejectedException
///  - ImportLimitExceededException
///  - DerivedLimitExceededException
///  - InFlightTransactionException
///  - ActiveListingsBlockingException
///  - WalletNotFoundException
///  - IdentityMnemonicMissingException
///  - WalletSecretMissingException
///  - InvalidPrivateKeyException
///  - WalletIndexCorruptedException
///  - PrimaryIntegrityViolationException

library;

/// Base for all Multi-Wallet domain exceptions.
sealed class WalletException implements Exception {
  const WalletException(this.message);
  final String message;

  @override
  String toString() => '${runtimeType.toString()}: $message';
}

// ---------------------------------------------------------------------------
// Removal / mutation guards
// ---------------------------------------------------------------------------

/// Attempt to remove the Primary wallet. Throws when either the ID matches
/// or role==primary (P0 C-3 hardening).
class CannotRemovePrimaryException extends WalletException {
  const CannotRemovePrimaryException()
      : super('Main Wallet cannot be removed.');
}

/// A wallet with the same address is already registered (derived re-add OR imported duplicate).
class DuplicateWalletException extends WalletException {
  const DuplicateWalletException(this.address)
      : super('A wallet with this address is already added.');
  final String address;
}

/// User tried to import their own SnowChat identity_mnemonic (C-1).
class SelfImportRejectedException extends WalletException {
  const SelfImportRejectedException()
      : super(
          'This phrase is your SnowChat identity recovery phrase. '
          'Your Main Wallet is already derived from it.',
        );
}

/// Imported wallet count limit reached (Open Decision: 10).
class ImportLimitExceededException extends WalletException {
  const ImportLimitExceededException(this.maxImported)
      : super(
          'Imported wallet limit reached. '
          'Remove one before importing another.',
        );
  final int maxImported;
}

/// Derived sub-wallet count limit reached (Open Decision: 5, hidden included).
class DerivedLimitExceededException extends WalletException {
  const DerivedLimitExceededException(this.maxDerived)
      : super(
          'Account limit reached. '
          'You can have up to $maxDerived sub accounts.',
        );
  final int maxDerived;
}

/// Attempt to delete / evict keys of a wallet with an in-flight transfer or marketplace tx (A-5).
class InFlightTransactionException extends WalletException {
  const InFlightTransactionException()
      : super(
          'A transaction is in progress on this wallet. '
          'Wait for it to complete before removing.',
        );
}

/// Attempt to delete a wallet with active marketplace listings (D-2). Fail-closed on RPC failure.
class ActiveListingsBlockingException extends WalletException {
  const ActiveListingsBlockingException(this.reason)
      : super(
          'Cannot remove wallet: $reason. '
          'Cancel listings on this wallet first.',
        );

  /// "$N active listing(s) found" or "RPC unavailable, cannot verify"
  final String reason;
}

// ---------------------------------------------------------------------------
// Lookup failures
// ---------------------------------------------------------------------------

class WalletNotFoundException extends WalletException {
  const WalletNotFoundException(this.identifier)
      : super('Wallet not found.');

  /// Identifier used by the caller (id or address etc.) — for debugging.
  final String identifier;
}

/// `identity_mnemonic` missing from secure_storage — thrown by mnemonic-dependent
/// operations like addDerivedWallet (I-3).
class IdentityMnemonicMissingException extends WalletException {
  const IdentityMnemonicMissingException()
      : super(
          'Recovery phrase is required. '
          'Restore from your backup phrase in Settings.',
        );
}

/// imported wallet secret missing from keystore / unwrap failed (I-5).
class WalletSecretMissingException extends WalletException {
  const WalletSecretMissingException(this.walletId, this.label)
      : super('Wallet "$label" is unavailable. Re-import the private key.');
  final String walletId;
  final String label;
}

// ---------------------------------------------------------------------------
// Input validation
// ---------------------------------------------------------------------------

/// On import: key length / encoding / Solana key validation failure.
class InvalidPrivateKeyException extends WalletException {
  const InvalidPrivateKeyException(super.message);
}

// ---------------------------------------------------------------------------
// Storage integrity
// ---------------------------------------------------------------------------

/// `wallet_index_v1` JSON parse failure or invariant violation (primary count
/// 0 or 2, defaultId not in entries, etc.).
class WalletIndexCorruptedException extends WalletException {
  const WalletIndexCorruptedException(super.message);
}

/// At bootstrap, primary entry address does not match the derived address
/// from identity_mnemonic (C-4). UI shows a banner and guides the user.
class PrimaryIntegrityViolationException extends WalletException {
  const PrimaryIntegrityViolationException({
    required this.expectedAddress,
    required this.actualAddress,
  }) : super(
          'Main Wallet integrity check failed. '
          'Restore your recovery phrase to repair.',
        );
  final String expectedAddress;
  final String actualAddress;
}
