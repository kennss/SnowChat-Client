/// @file        nft_models.dart
/// @description NFT domain models. NFT asset, attribute, collection data classes.
///              Marketplace listing models live in `features/marketplace/marketplace_models.dart`.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-24)
///
/// @functions
///  - NftTokenStandard: NFT standard enum (NonFungible, ProgrammableNonFungible, Core, etc.)
///  - NFTAsset: single NFT asset data class
///  - NFTAttribute: NFT attribute/trait data class
///  - NFTCollection: NFT collection data class

/// NFT domain models.
library;

import 'package:flutter/foundation.dart';

/// NFT token standard — maps to the DAS API `token_standard` field.
/// Branching on this is required for transfers (pNFT cannot use plain SPL transfer).
enum NftTokenStandard {
  /// Token Metadata legacy NFT
  nonFungible,
  /// Token Metadata edition
  nonFungibleEdition,
  /// Programmable NFT — transfers require the Metaplex transfer instruction
  programmableNonFungible,
  /// Programmable edition
  programmableNonFungibleEdition,
  /// Fungible Asset (semi-fungible)
  fungibleAsset,
  /// Metaplex Core NFT (single-account model)
  core,
  /// Unknown (fallback)
  unknown;

  /// Convert the DAS API response's `token_standard` string into the enum.
  /// Pass [dasInterface] too so we can correctly classify Core NFTs etc.
  static NftTokenStandard fromDas(String? value, {String? dasInterface}) {
    // Core NFTs have no token_standard; their interface is 'MplCoreAsset'
    if (dasInterface == 'MplCoreAsset' || dasInterface == 'MplCoreCollection') {
      return core;
    }
    return switch (value) {
      'NonFungible' => nonFungible,
      'NonFungibleEdition' => nonFungibleEdition,
      'ProgrammableNonFungible' => programmableNonFungible,
      'ProgrammableNonFungibleEdition' => programmableNonFungibleEdition,
      'FungibleAsset' => fungibleAsset,
      _ => unknown,
    };
  }

  /// Whether this is a pNFT-family (transfers need the Metaplex transfer instruction)
  bool get isProgrammable =>
      this == programmableNonFungible ||
      this == programmableNonFungibleEdition;

  /// Whether this standard supports SPL token transfer
  bool get isSplTransferable =>
      this == nonFungible || this == nonFungibleEdition;

  /// Whether this standard is currently unsupported for transfer in Phase 7
  bool get isTransferUnsupported =>
      isProgrammable ||
      this == core ||
      this == unknown;
}

/// A single NFT asset.
@immutable
class NFTAsset {
  const NFTAsset({
    required this.mint,
    required this.name,
    required this.imageUrl,
    this.tokenStandard = NftTokenStandard.unknown,
    this.collectionName,
    this.collectionMint,
    this.description,
    this.attributes = const [],
    this.externalUrl,
    this.animationUrl,
    this.listingPriceLamports,
    this.isListed = false,
    this.isCompressed = false,
    this.creatorAddresses = const <String>[],
  });

  /// Mint address of the NFT.
  final String mint;

  final String name;

  /// Image URL (IPFS, Arweave, or HTTP).
  final String imageUrl;

  /// Token standard (NonFungible, ProgrammableNonFungible, Core, etc.)
  final NftTokenStandard tokenStandard;

  /// Name of the collection this NFT belongs to.
  final String? collectionName;

  /// Mint address of the collection.
  final String? collectionMint;

  final String? description;

  /// NFT attributes / traits.
  final List<NFTAttribute> attributes;

  final String? externalUrl;

  /// Animation / video / 3D URL (rendering to be added later).
  final String? animationUrl;

  /// If listed on marketplace, the price in lamports.
  final BigInt? listingPriceLamports;

  final bool isListed;

  /// Whether this is a compressed NFT (cNFT / Bubblegum).
  final bool isCompressed;

  /// Ordered list of creator addresses from Metaplex metadata. Required
  /// for Tensor `transfer_creators_fee` which checks each passed
  /// remaining_account address matches metadata.creators[].address in order.
  final List<String> creatorAddresses;

  /// Formatted listing price in SOL.
  String? get formattedListingPrice {
    if (listingPriceLamports == null) return null;
    final sol = listingPriceLamports! ~/ BigInt.from(1000000000);
    final frac = (listingPriceLamports! % BigInt.from(1000000000)).abs();
    var fracStr = frac.toString().padLeft(9, '0');
    // Trim trailing zeros but keep at least 2 decimals.
    fracStr = fracStr.replaceAll(RegExp(r'0+$'), '');
    if (fracStr.isEmpty) fracStr = '0';
    return '$sol.$fracStr SOL';
  }

  NFTAsset copyWith({
    String? mint,
    String? name,
    String? imageUrl,
    NftTokenStandard? tokenStandard,
    String? collectionName,
    String? collectionMint,
    String? description,
    List<NFTAttribute>? attributes,
    String? externalUrl,
    String? animationUrl,
    BigInt? listingPriceLamports,
    bool? isListed,
    bool? isCompressed,
  }) {
    return NFTAsset(
      mint: mint ?? this.mint,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      tokenStandard: tokenStandard ?? this.tokenStandard,
      collectionName: collectionName ?? this.collectionName,
      collectionMint: collectionMint ?? this.collectionMint,
      description: description ?? this.description,
      attributes: attributes ?? this.attributes,
      externalUrl: externalUrl ?? this.externalUrl,
      animationUrl: animationUrl ?? this.animationUrl,
      listingPriceLamports: listingPriceLamports ?? this.listingPriceLamports,
      isListed: isListed ?? this.isListed,
      isCompressed: isCompressed ?? this.isCompressed,
    );
  }
}

/// A single trait / attribute on an NFT.
@immutable
class NFTAttribute {
  const NFTAttribute({
    required this.traitType,
    required this.value,
  });

  final String traitType;
  final String value;
}

/// A collection of NFTs grouped together.
@immutable
class NFTCollection {
  const NFTCollection({
    required this.name,
    required this.mint,
    required this.nfts,
    this.imageUrl,
    this.floorPriceLamports,
  });

  final String name;

  /// Collection mint address.
  final String mint;

  final List<NFTAsset> nfts;

  final String? imageUrl;

  /// Floor price in lamports.
  final BigInt? floorPriceLamports;

  int get count => nfts.length;
}

