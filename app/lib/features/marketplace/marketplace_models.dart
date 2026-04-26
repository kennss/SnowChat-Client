/// @file        marketplace_models.dart
/// @description NFT Marketplace domain models — listing and filter data classes.
///              Phase 2 refactor: dropped server-escrow-era CreateListingRequest +
///              escrowSignature/purchaseSignature/buyerAddress/soldAt/
///              cancelledAt/expiresAt fields entirely. The on-chain ListState
///              PDA is the single source of truth.
///              priceLamports is BigInt-only (Float/double forbidden).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-11
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - MarketplaceListing: marketplace-listing data class (ListState PDA parse result)
///  - MarketplaceFilter: listing-query filter (collection / seller)

library;

import 'package:flutter/foundation.dart';

/// A single marketplace listing backed by an on-chain Tensor ListState PDA.
@immutable
class MarketplaceListing {
  const MarketplaceListing({
    required this.id,
    required this.nftMintAddress,
    this.nftName,
    this.nftImageUrl,
    this.collectionName,
    this.collectionMint,
    required this.priceLamports,
    required this.sellerAddress,
    required this.status,
    required this.listedAt,
    this.feeBps = 200,
    this.royaltyBps = 0,
    this.creatorAddresses = const <String>[],
  });

  /// ListState PDA address — stable identifier.
  final String id;
  final String nftMintAddress;
  final String? nftName;
  final String? nftImageUrl;
  final String? collectionName;
  final String? collectionMint;

  /// Price in lamports (BigInt). Never use double for this field.
  final BigInt priceLamports;
  final String sellerAddress;

  /// ACTIVE | EXPIRED (ListState expiry crossed but not yet delisted).
  final String status;
  final DateTime listedAt;

  /// Marketplace fee in basis points (200 = 2%). Derived from program
  /// constant TAKER_FEE_BPS; surfaced for UI fee preview.
  final int feeBps;

  /// Creator royalty in basis points. On-chain metadata-driven; kept for
  /// UI display of the expected royalty cut.
  final int royaltyBps;

  /// Ordered list of creator Base58 addresses from Metaplex metadata.
  /// Must be passed as remaining_accounts in the buy ix for Tensor's
  /// `transfer_creators_fee` check — order AND addresses must match
  /// metadata.creators[] exactly or the tx aborts with CreatorMismatch.
  final List<String> creatorAddresses;

  /// Formatted price in SOL for display.
  String get formattedPrice {
    final sol = priceLamports ~/ BigInt.from(1000000000);
    final frac = (priceLamports % BigInt.from(1000000000)).abs();
    var fracStr = frac.toString().padLeft(9, '0');
    fracStr = fracStr.replaceAll(RegExp(r'0+$'), '');
    if (fracStr.isEmpty) return '$sol SOL';
    return '$sol.$fracStr SOL';
  }

  /// Shortened seller address for display (e.g. "DzQF...n7ZK").
  String get shortSellerAddress {
    if (sellerAddress.length <= 8) return sellerAddress;
    return '${sellerAddress.substring(0, 4)}...${sellerAddress.substring(sellerAddress.length - 4)}';
  }

  /// Shortened mint address for display (e.g. "DzQF...n7ZK").
  String get shortMintAddress {
    if (nftMintAddress.length <= 8) return nftMintAddress;
    return '${nftMintAddress.substring(0, 4)}...${nftMintAddress.substring(nftMintAddress.length - 4)}';
  }

  /// Human-readable time since listed (e.g. "2h ago", "3d ago").
  String get timeAgo {
    final diff = DateTime.now().difference(listedAt);
    if (diff.inDays > 365) return '${diff.inDays ~/ 365}y ago';
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  /// Fee amount in lamports (BigInt arithmetic only).
  BigInt get feeLamports =>
      priceLamports * BigInt.from(feeBps) ~/ BigInt.from(10000);

  /// Formatted fee in SOL for display.
  String get formattedFee {
    final fee = feeLamports;
    final sol = fee ~/ BigInt.from(1000000000);
    final frac = (fee % BigInt.from(1000000000)).abs();
    var fracStr = frac.toString().padLeft(9, '0');
    fracStr = fracStr.replaceAll(RegExp(r'0+$'), '');
    if (fracStr.isEmpty) return '$sol SOL';
    return '$sol.$fracStr SOL';
  }
}

/// Filter parameters for marketplace listing queries.
@immutable
class MarketplaceFilter {
  const MarketplaceFilter({
    this.page = 1,
    this.limit = 20,
    this.status = 'ACTIVE',
    this.sort = 'newest',
    this.query,
    this.collectionMint,
    this.sellerAddress,
  });

  final int page;
  final int limit;

  /// ACTIVE | SOLD | ALL
  final String status;

  /// newest | oldest | price_asc | price_desc
  final String sort;

  /// Search query (collection name).
  final String? query;
  final String? collectionMint;

  /// If set, filter by seller (for "My Listings" tab).
  final String? sellerAddress;

  MarketplaceFilter copyWith({
    int? page,
    int? limit,
    String? status,
    String? sort,
    String? query,
    String? collectionMint,
    String? sellerAddress,
  }) {
    return MarketplaceFilter(
      page: page ?? this.page,
      limit: limit ?? this.limit,
      status: status ?? this.status,
      sort: sort ?? this.sort,
      query: query ?? this.query,
      collectionMint: collectionMint ?? this.collectionMint,
      sellerAddress: sellerAddress ?? this.sellerAddress,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarketplaceFilter &&
          page == other.page &&
          limit == other.limit &&
          status == other.status &&
          sort == other.sort &&
          query == other.query &&
          collectionMint == other.collectionMint &&
          sellerAddress == other.sellerAddress;

  @override
  int get hashCode => Object.hash(
        page,
        limit,
        status,
        sort,
        query,
        collectionMint,
        sellerAddress,
      );
}
