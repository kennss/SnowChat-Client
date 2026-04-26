/// @file        wallet_models.dart
/// @description Wallet domain models. Balance, token info, transaction record data classes
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - WalletBalance: full wallet balance data class
///  - TokenInfo: single-token holding info data class
///  - TransactionInfo: transaction record data class
///  - TransactionType: transaction type enum
///  - TransactionStatus: transaction status enum

/// Wallet domain models.
/// ALL monetary values use [BigInt] (lamports). NEVER use double for SOL.
library;

import 'package:flutter/foundation.dart';

/// Represents the overall wallet balance.
@immutable
class WalletBalance {
  const WalletBalance({
    required this.totalUsdValue,
    required this.changePercent24h,
    required this.tokens,
  });

  /// Total portfolio value in USD cents (BigInt for precision).
  final BigInt totalUsdValue;

  /// 24-hour change percentage (basis points, e.g. 230 = +2.30%).
  final int changePercent24h;

  /// List of token holdings.
  final List<TokenInfo> tokens;

  /// Formatted USD string, e.g. "\$1,234.56".
  String get formattedUsd {
    final cents = totalUsdValue.toInt();
    final dollars = cents ~/ 100;
    final remainder = (cents % 100).abs();
    final sign = cents < 0 ? '-' : '';
    return '$sign\$${_formatWithCommas(dollars)}.${remainder.toString().padLeft(2, '0')}';
  }

  /// Formatted change string, e.g. "+2.30%".
  String get formattedChange {
    final sign = changePercent24h >= 0 ? '+' : '';
    final whole = changePercent24h ~/ 100;
    final frac = (changePercent24h % 100).abs();
    return '$sign$whole.${frac.toString().padLeft(2, '0')}%';
  }

  bool get isPositiveChange => changePercent24h >= 0;

  static String _formatWithCommas(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return n < 0 ? '-${buf.toString()}' : buf.toString();
  }

  WalletBalance copyWith({
    BigInt? totalUsdValue,
    int? changePercent24h,
    List<TokenInfo>? tokens,
  }) {
    return WalletBalance(
      totalUsdValue: totalUsdValue ?? this.totalUsdValue,
      changePercent24h: changePercent24h ?? this.changePercent24h,
      tokens: tokens ?? this.tokens,
    );
  }
}

/// A single token holding.
@immutable
class TokenInfo {
  const TokenInfo({
    required this.mint,
    required this.symbol,
    required this.name,
    required this.decimals,
    required this.balanceLamports,
    required this.usdValueCents,
    this.logoUrl,
    this.changePercent24h = 0,
  });

  /// SPL token mint address (or "SOL" for native SOL).
  final String mint;

  final String symbol;
  final String name;
  final int decimals;

  /// Raw balance in smallest unit (lamports for SOL, raw amount for SPL).
  final BigInt balanceLamports;

  /// USD value in cents.
  final BigInt usdValueCents;

  /// Token logo URL.
  final String? logoUrl;

  /// 24h change in basis points.
  final int changePercent24h;

  /// Human-readable balance, e.g. "12.500000000" for SOL.
  String get formattedBalance {
    if (decimals == 0) return balanceLamports.toString();
    final whole = balanceLamports ~/ BigInt.from(10).pow(decimals);
    final frac = (balanceLamports % BigInt.from(10).pow(decimals)).abs();
    return '$whole.${frac.toString().padLeft(decimals, '0')}';
  }

  /// Short balance, e.g. "12.5" (strips trailing zeros).
  String get shortBalance {
    final full = formattedBalance;
    if (!full.contains('.')) return full;
    var trimmed = full.replaceAll(RegExp(r'0+$'), '');
    if (trimmed.endsWith('.')) trimmed = trimmed.substring(0, trimmed.length - 1);
    return trimmed;
  }

  /// Formatted USD string.
  String get formattedUsd {
    final cents = usdValueCents.toInt();
    final dollars = cents ~/ 100;
    final remainder = (cents % 100).abs();
    return '\$${dollars.toString()}.${remainder.toString().padLeft(2, '0')}';
  }

  bool get isNativeSOL => mint == 'SOL' || mint == 'So11111111111111111111111111111111111111112';
}

/// A single transaction record.
@immutable
class TransactionInfo {
  const TransactionInfo({
    required this.signature,
    required this.type,
    required this.timestamp,
    required this.status,
    this.amountLamports,
    this.tokenSymbol,
    this.tokenMint,
    this.fromAddress,
    this.toAddress,
    this.fee,
    this.nftName,
  });

  final String signature;
  final TransactionType type;
  final DateTime timestamp;
  final TransactionStatus status;

  /// Amount in smallest unit.
  final BigInt? amountLamports;
  final String? tokenSymbol;
  final String? tokenMint;

  final String? fromAddress;
  final String? toAddress;

  /// Fee in lamports.
  final BigInt? fee;

  /// NFT name (for NFT transfers).
  final String? nftName;

  /// Short signature for display.
  String get shortSignature =>
      '${signature.substring(0, 4)}...${signature.substring(signature.length - 4)}';

  /// Abbreviated address.
  static String shortenAddress(String address) {
    if (address.length <= 8) return address;
    return '${address.substring(0, 4)}...${address.substring(address.length - 4)}';
  }
}

enum TransactionType {
  send,
  receive,
  swap,
  nftSend,
  nftReceive,
  unknown,
}

enum TransactionStatus {
  pending,
  confirmed,
  failed,
}
