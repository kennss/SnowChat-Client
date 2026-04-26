/// @file        amount_converter.dart
/// @description BigInt amount conversion utilities — handles SOL/SPL token
///              amounts as BigInt. Float/double strictly forbidden. String
///              parsing → BigInt arithmetic → String output.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-03
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - solToLamports(): SOL string → BigInt lamports
///  - lamportsToSol(): BigInt lamports → SOL string
///  - tokenToSmallestUnit(): token display amount → BigInt smallest unit
///  - smallestUnitToDisplay(): BigInt smallest unit → display string
///  - formatUsd(): BigInt lamports + SOL price → USD display string

/// BigInt-only amount conversion utilities.
///
/// RULES:
///   - Float/double NEVER used for amount arithmetic
///   - String parsing → BigInt → String display
///   - solana package API boundary: toInt() allowed ONLY at call site
library;

/// SOL → lamports (BigInt). "1.5" → BigInt(1500000000)
BigInt solToLamports(String solAmount) {
  final trimmed = solAmount.trim();
  if (trimmed.isEmpty) return BigInt.zero;

  final parts = trimmed.split('.');
  if (parts.length > 2) {
    throw FormatException('Invalid SOL amount: $solAmount');
  }

  final wholePart = parts[0].isEmpty ? BigInt.zero : BigInt.parse(parts[0]);
  final whole = wholePart * BigInt.from(1000000000);

  if (parts.length == 1) return whole;

  var fracStr = parts[1];
  if (fracStr.length > 9) {
    fracStr = fracStr.substring(0, 9);
  } else {
    fracStr = fracStr.padRight(9, '0');
  }

  return whole + BigInt.parse(fracStr);
}

/// lamports → SOL display string (BigInt). BigInt(1500000000) → "1.5"
String lamportsToSol(BigInt lamports) {
  final isNegative = lamports < BigInt.zero;
  final abs = lamports.abs();
  final whole = abs ~/ BigInt.from(1000000000);
  final frac = abs % BigInt.from(1000000000);

  if (frac == BigInt.zero) {
    return '${isNegative ? '-' : ''}$whole';
  }

  var fracStr = frac.toString().padLeft(9, '0');
  fracStr = fracStr.replaceAll(RegExp(r'0+$'), '');
  return '${isNegative ? '-' : ''}$whole.$fracStr';
}

/// Token display amount → smallest unit (BigInt).
/// "100.5" with 6 decimals → BigInt(100500000)
BigInt tokenToSmallestUnit(String displayAmount, int decimals) {
  final parts = displayAmount.split('.');
  final integerPart = BigInt.parse(parts[0]) * BigInt.from(10).pow(decimals);
  if (parts.length == 1) return integerPart;

  final decimalStr = parts[1].padRight(decimals, '0').substring(0, decimals);
  return integerPart + BigInt.parse(decimalStr);
}

/// Smallest unit (BigInt) → token display string.
/// BigInt(100500000) with 6 decimals → "100.5"
String smallestUnitToDisplay(BigInt amount, int decimals) {
  final divisor = BigInt.from(10).pow(decimals);
  final integerPart = amount ~/ divisor;
  final remainder = amount % divisor;
  final decimalStr = remainder.toString().padLeft(decimals, '0');
  final trimmed = decimalStr.replaceAll(RegExp(r'0+$'), '');
  if (trimmed.isEmpty) return integerPart.toString();
  return '$integerPart.$trimmed';
}

/// Format lamports as USD string for display.
/// Uses double ONLY for UI display — NEVER for amount arithmetic.
String formatUsd(BigInt lamports, double solPriceUsd) {
  if (solPriceUsd <= 0) return '\$0.00';
  final solStr = lamportsToSol(lamports);
  // Parse SOL string to double ONLY for display calculation
  final solValue = double.tryParse(solStr) ?? 0.0;
  final usdValue = solValue * solPriceUsd;
  return '\$${usdValue.toStringAsFixed(2)}';
}
