/// @file        enhanced_transaction.dart
/// @lastUpdated 2026-04-26 (Phase X-2: extract NFT mint + price from
///                          marketplace ix data/accounts so list/buy rows
///                          can render "Listed Nomos #7 at 1 SOL" etc.)
/// @description Helius Enhanced Transaction model. Parses the server-proxy
///              `/wallet/enhanced-history` response into rich tx types like
///              TRANSFER, SWAP, NFT_SALE. Replaces the existing
///              TransactionParser's 5-type limit (legacy kept as fallback).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - EnhancedTransaction.fromJson(): Helius JSON → model
///  - NativeTransfer.fromJson(): parse SOL transfer details
///  - TokenTransfer.fromJson(): parse SPL token transfer details
///  - EnhancedTxType: Helius type string → enum mapping
library;

import 'package:flutter/foundation.dart';
import 'package:solana/base58.dart';

import '../tensor/tensor_marketplace_constants.dart';

/// Helius Enhanced Transaction type enum.
/// Maps the main values of the `type` field returned by the Helius API.
enum EnhancedTxType {
  transfer,
  transferChecked,
  swap,
  nftSale,
  nftListing,
  nftCancelListing,
  nftMint,
  tokenMint,
  burn,
  burnChecked,
  compressed,
  compressedNftMint,
  unknown;

  /// Helius JSON `type` string → enum.
  static EnhancedTxType fromString(String? raw) {
    if (raw == null) return unknown;
    return switch (raw.toUpperCase()) {
      'TRANSFER' => transfer,
      'TRANSFER_CHECKED' => transferChecked,
      'SWAP' => swap,
      'NFT_SALE' => nftSale,
      'NFT_LISTING' => nftListing,
      'NFT_CANCEL_LISTING' => nftCancelListing,
      'NFT_MINT' => nftMint,
      'TOKEN_MINT' => tokenMint,
      'BURN' => burn,
      'BURN_CHECKED' => burnChecked,
      'COMPRESSED_NFT_MINT' => compressedNftMint,
      _ => unknown,
    };
  }

  /// Human-readable label.
  String get displayLabel => switch (this) {
    transfer || transferChecked => 'Transfer',
    swap => 'Swap',
    nftSale => 'NFT Sale',
    nftListing => 'NFT Listing',
    nftCancelListing => 'Cancelled Listing',
    nftMint || compressedNftMint => 'NFT Mint',
    tokenMint => 'Token Mint',
    burn || burnChecked => 'Burn',
    compressed => 'Compressed',
    unknown => 'Transaction',
  };
}

/// SOL (native) transfer detail.
@immutable
class NativeTransfer {
  const NativeTransfer({
    required this.fromUserAccount,
    required this.toUserAccount,
    required this.amount,
  });

  final String fromUserAccount;
  final String toUserAccount;

  /// Amount in lamports (BigInt).
  final BigInt amount;

  factory NativeTransfer.fromJson(Map<String, dynamic> json) {
    return NativeTransfer(
      fromUserAccount: json['fromUserAccount'] as String? ?? '',
      toUserAccount: json['toUserAccount'] as String? ?? '',
      amount: BigInt.from(json['amount'] as num? ?? 0),
    );
  }
}

/// SPL token transfer detail.
@immutable
class TokenTransfer {
  const TokenTransfer({
    required this.mint,
    required this.fromUserAccount,
    required this.toUserAccount,
    required this.tokenAmount,
    required this.fromTokenAccount,
    required this.toTokenAccount,
  });

  final String mint;
  final String fromUserAccount;
  final String toUserAccount;

  /// Human-readable token amount (double — display-only).
  final double tokenAmount;
  final String fromTokenAccount;
  final String toTokenAccount;

  factory TokenTransfer.fromJson(Map<String, dynamic> json) {
    return TokenTransfer(
      mint: json['mint'] as String? ?? '',
      fromUserAccount: json['fromUserAccount'] as String? ?? '',
      toUserAccount: json['toUserAccount'] as String? ?? '',
      tokenAmount: (json['tokenAmount'] as num?)?.toDouble() ?? 0.0,
      fromTokenAccount: json['fromTokenAccount'] as String? ?? '',
      toTokenAccount: json['toTokenAccount'] as String? ?? '',
    );
  }
}

/// Helius Enhanced Transaction model.
///
/// Uses the result already classified by the Helius API directly, so
/// client-side manual parsing (TransactionParser) is unnecessary.
@immutable
class EnhancedTransaction {
  const EnhancedTransaction({
    required this.signature,
    required this.type,
    required this.source,
    required this.description,
    required this.fee,
    required this.feePayer,
    required this.timestamp,
    required this.nativeTransfers,
    required this.tokenTransfers,
    this.transactionError,
    this.marketplaceNftMint,
    this.marketplaceLamports,
  });

  final String signature;
  final EnhancedTxType type;

  /// Phase X-2: extracted NFT mint (Base58) for SnowChat marketplace tx.
  /// Set only when type ∈ {nftSale, nftListing, nftCancelListing} AND the
  /// classifier matched our fork program. UI uses this to fetch DAS name
  /// and render "Listed <NFT name> at <price> SOL".
  final String? marketplaceNftMint;

  /// Phase X-2: extracted price in lamports (BigInt). Present for
  /// list_legacy / buy_legacy. delist_legacy has no amount → null.
  final BigInt? marketplaceLamports;

  /// Transaction source: SYSTEM_PROGRAM, MAGIC_EDEN, JUPITER, etc.
  final String? source;

  /// Natural-language description generated by Helius (English).
  final String? description;

  /// Fee in lamports (BigInt).
  final BigInt fee;

  /// Fee payer address.
  final String feePayer;

  /// Unix timestamp (seconds).
  final int timestamp;

  final List<NativeTransfer> nativeTransfers;
  final List<TokenTransfer> tokenTransfers;

  /// Non-null if transaction failed on-chain.
  final String? transactionError;

  /// Unix timestamp → DateTime (local).
  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);

  /// Short signature for display.
  String get shortSignature {
    if (signature.length <= 12) return signature;
    return '${signature.substring(0, 4)}...${signature.substring(signature.length - 4)}';
  }

  /// Source label (MAGIC_EDEN → Magic Eden).
  String get sourceLabel {
    if (source == null || source!.isEmpty) return '';
    return source!
        .split('_')
        .map((w) => w.isEmpty
            ? ''
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  /// Decide send/receive direction relative to the given owner address.
  /// For TRANSFER type, decided from nativeTransfers.
  ///
  /// Phase X-3: marketplace tx (nftSale / nftListing / nftCancelListing)
  /// uses the net SOL sign instead of from-match. Buyer is the
  /// SystemProgram.transfer payer (from = buyer many times) but receives
  /// the NFT — simple from-match wrongly flips the direction.
  bool isSend(String ownerAddress) {
    if (type == EnhancedTxType.swap) return false;

    // Marketplace: net SOL sign decides (sent if net negative).
    if (type == EnhancedTxType.nftSale ||
        type == EnhancedTxType.nftListing ||
        type == EnhancedTxType.nftCancelListing) {
      var net = BigInt.zero;
      for (final nt in nativeTransfers) {
        if (nt.toUserAccount == ownerAddress) net += nt.amount;
        if (nt.fromUserAccount == ownerAddress) net -= nt.amount;
      }
      return net < BigInt.zero;
    }

    // From native transfers
    for (final nt in nativeTransfers) {
      if (nt.fromUserAccount == ownerAddress && nt.amount > BigInt.zero) {
        return true;
      }
    }
    // From token transfers
    for (final tt in tokenTransfers) {
      if (tt.fromUserAccount == ownerAddress && tt.tokenAmount > 0) {
        return true;
      }
    }
    return feePayer == ownerAddress;
  }

  /// Owner-net SOL change in lamports (positive = received).
  /// Used by detail screens to render breakdown.
  BigInt netSolForOwner(String ownerAddress) {
    var net = BigInt.zero;
    for (final nt in nativeTransfers) {
      if (nt.toUserAccount == ownerAddress) net += nt.amount;
      if (nt.fromUserAccount == ownerAddress) net -= nt.amount;
    }
    return net;
  }

  /// Extract counterparty address (by largest amount).
  String? counterparty(String ownerAddress) {
    // Find counterparty in native transfers
    for (final nt in nativeTransfers) {
      if (nt.fromUserAccount == ownerAddress) return nt.toUserAccount;
      if (nt.toUserAccount == ownerAddress) return nt.fromUserAccount;
    }
    // Find counterparty in token transfers
    for (final tt in tokenTransfers) {
      if (tt.fromUserAccount == ownerAddress) return tt.toUserAccount;
      if (tt.toUserAccount == ownerAddress) return tt.fromUserAccount;
    }
    return null;
  }

  /// Primary amount (lamports BigInt). First match in native > token order.
  BigInt? primaryAmountLamports(String ownerAddress) {
    for (final nt in nativeTransfers) {
      if (nt.fromUserAccount == ownerAddress ||
          nt.toUserAccount == ownerAddress) {
        return nt.amount;
      }
    }
    return null;
  }

  factory EnhancedTransaction.fromJson(Map<String, dynamic> json) {
    final nativeList = (json['nativeTransfers'] as List<dynamic>?)
            ?.map((e) => NativeTransfer.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final tokenList = (json['tokenTransfers'] as List<dynamic>?)
            ?.map((e) => TokenTransfer.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    // Phase X-1: Helius does not know SnowChat's Tensor fork program ID,
    // so it returns type='UNKNOWN' or generic 'TRANSFER'. Inspect raw
    // instructions for our program ID + Anchor discriminator and override
    // type so existing UI mapping (icon / label / color) just works.
    var resolvedType = EnhancedTxType.fromString(json['type'] as String?);
    var resolvedSource = json['source'] as String?;
    String? mpMint;
    BigInt? mpLamports;
    if (resolvedType == EnhancedTxType.unknown ||
        resolvedType == EnhancedTxType.transfer ||
        resolvedType == EnhancedTxType.transferChecked) {
      final classified = _classifySnowchatMarketplace(json);
      if (classified != null) {
        resolvedType = classified.type;
        mpMint = classified.mint;
        mpLamports = classified.lamports;
        // Tag source so sourceLabel renders "Snowchat Marketplace".
        resolvedSource = 'SNOWCHAT_MARKETPLACE';
      }
    }

    return EnhancedTransaction(
      signature: json['signature'] as String? ?? '',
      type: resolvedType,
      source: resolvedSource,
      description: json['description'] as String?,
      fee: BigInt.from(json['fee'] as num? ?? 0),
      feePayer: json['feePayer'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? 0,
      nativeTransfers: nativeList,
      tokenTransfers: tokenList,
      transactionError: json['transactionError'] as String?,
      marketplaceNftMint: mpMint,
      marketplaceLamports: mpLamports,
    );
  }
}

/// Result of marketplace classification — type + extracted NFT mint +
/// (optional) price in lamports. Null when no SnowChat marketplace ix
/// matched.
class _MarketplaceClassification {
  const _MarketplaceClassification({
    required this.type,
    this.mint,
    this.lamports,
  });
  final EnhancedTxType type;
  final String? mint;
  final BigInt? lamports;
}

/// Phase X-1/X-2 helper — scan top-level + inner instructions for SnowChat
/// marketplace fork program ID. Match the first 8 bytes (Anchor instruction
/// discriminator) of `data` against known buy/list/delist constants. On
/// match, also extract NFT mint (from `accounts[index]`) and price (from
/// `data[8..16]` u64 little-endian) for use in the row label.
///
/// Returns null when no SnowChat marketplace ix is found — caller keeps
/// the original type.
///
/// Account index per ix (from tensor_marketplace_buy.dart):
///   - list_legacy:    accounts[4] = mint
///   - buy_legacy:     accounts[5] = mint
///   - delist_legacy:  accounts[4] = mint (no amount)
_MarketplaceClassification? _classifySnowchatMarketplace(
    Map<String, dynamic> json) {
  final flat = <Map<String, dynamic>>[];
  final top = json['instructions'] as List<dynamic>?;
  if (top != null) {
    for (final ix in top) {
      if (ix is Map<String, dynamic>) {
        flat.add(ix);
        // innerInstructions can be a list of {instructions: [...]} groups.
        final inner = ix['innerInstructions'] as List<dynamic>?;
        if (inner != null) {
          for (final g in inner) {
            if (g is Map<String, dynamic>) {
              final innerIx = g['instructions'] as List<dynamic>?;
              if (innerIx != null) {
                for (final i in innerIx) {
                  if (i is Map<String, dynamic>) flat.add(i);
                }
              }
            } else if (g is List) {
              // Some payloads are raw lists of instructions.
              for (final i in g) {
                if (i is Map<String, dynamic>) flat.add(i);
              }
            }
          }
        }
      }
    }
  }

  for (final ix in flat) {
    final programId = ix['programId'] as String?;
    if (programId != tensorMarketplaceDevnetProgramAddress) continue;

    final dataStr = ix['data'] as String?;
    if (dataStr == null || dataStr.isEmpty) continue;

    // Helius encodes instruction `data` as base58 (Solana RPC convention).
    final List<int> bytes;
    try {
      bytes = base58decode(dataStr);
    } catch (_) {
      continue;
    }
    if (bytes.length < 8) continue;
    final disc = bytes.sublist(0, 8);
    final accounts = (ix['accounts'] as List<dynamic>?) ?? const [];

    String? mintAt(int index) {
      if (index < 0 || index >= accounts.length) return null;
      final v = accounts[index];
      return v is String ? v : null;
    }

    BigInt? readU64Le(int offset) {
      if (bytes.length < offset + 8) return null;
      var value = BigInt.zero;
      for (var i = 0; i < 8; i++) {
        value |= BigInt.from(bytes[offset + i]) << (8 * i);
      }
      return value;
    }

    if (_byteListEquals(disc, listLegacyIxDiscriminator)) {
      return _MarketplaceClassification(
        type: EnhancedTxType.nftListing,
        mint: mintAt(4),
        lamports: readU64Le(8),
      );
    }
    if (_byteListEquals(disc, buyLegacyIxDiscriminator)) {
      // buy_legacy data carries `maxAmount` (buyer's price ceiling, which
      // SnowChat sets to listing.priceLamports × 2 for royalty/fee
      // headroom — see marketplace_provider.dart:400). That overshoots
      // the actual paid price, so we deliberately omit lamports here —
      // X-3 (tx detail) will compute the real fund split from
      // nativeTransfers.
      return _MarketplaceClassification(
        type: EnhancedTxType.nftSale,
        mint: mintAt(5),
        // lamports omitted — see comment above.
      );
    }
    if (_byteListEquals(disc, delistLegacyIxDiscriminator)) {
      return _MarketplaceClassification(
        type: EnhancedTxType.nftCancelListing,
        mint: mintAt(4),
        // No price in delist — null.
      );
    }
  }
  return null;
}

bool _byteListEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
