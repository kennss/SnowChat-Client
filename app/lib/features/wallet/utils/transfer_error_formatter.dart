/// @file        transfer_error_formatter.dart
/// @description Convert Solana RPC errors into user-friendly messages.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-15
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - TransferErrorFormatter.format(): RPC error → user-friendly message

class TransferErrorFormatter {
  TransferErrorFormatter._();

  /// Convert an RPC error string into a user-friendly message.
  /// Returns the original string when no pattern matches.
  static String format(String raw) {
    final lower = raw.toLowerCase();

    // Insufficient balance
    if (lower.contains('insufficient lamports')) {
      final match = RegExp(r'insufficient lamports (\d+), need (\d+)')
          .firstMatch(lower);
      if (match != null) {
        final have = _lamportsToSol(match.group(1)!);
        final need = _lamportsToSol(match.group(2)!);
        return 'Insufficient balance — you have $have SOL but need $need SOL (including fees).';
      }
      return 'Insufficient SOL balance for this transaction.';
    }

    // Insufficient token balance (SPL Token custom error 0x1)
    if (lower.contains('custom program error: 0x1') &&
        lower.contains('tokenkeg')) {
      return 'Token account has insufficient balance. '
          'The token may be listed on marketplace or already transferred.';
    }

    // Marketplace (Tensor program) 0x1 — typically insufficient balance on
    // buy/list, or listing state mismatch (NFT already sold or cancelled).
    if (lower.contains('custom program error: 0x1') &&
        (lower.contains('buylegacy') ||
            lower.contains('listlegacy') ||
            lower.contains('delistlegacy'))) {
      return 'Marketplace transaction failed. '
          'Likely insufficient SOL in this wallet — '
          'you need the listing price plus about 0.005 SOL for fees. '
          'If you have enough, the listing may have just been bought or '
          'cancelled by someone else.';
    }

    // Blockhash expired
    if (lower.contains('blockhash not found') ||
        lower.contains('block height exceeded')) {
      return 'Transaction expired. Please try again.';
    }

    // Network error
    if (lower.contains('failed to send') ||
        lower.contains('connection refused') ||
        lower.contains('timeout')) {
      return 'Network error — please check your connection and try again.';
    }

    // Simulation failure (generic)
    if (lower.contains('simulation failed')) {
      return 'Transaction simulation failed. Please check your balance and try again.';
    }

    // Biometric auth failure
    if (lower.contains('biometric')) {
      return 'Authentication failed. Please try again.';
    }

    // Default: return original (truncated if too long)
    if (raw.length > 200) {
      return '${raw.substring(0, 200)}…';
    }
    return raw;
  }

  static String _lamportsToSol(String lamportsStr) {
    final lamports = BigInt.tryParse(lamportsStr) ?? BigInt.zero;
    final sol = lamports ~/ BigInt.from(1000000000);
    final frac = (lamports % BigInt.from(1000000000)).abs();
    final fracStr = frac.toString().padLeft(9, '0').substring(0, 4);
    return '$sol.$fracStr';
  }
}
