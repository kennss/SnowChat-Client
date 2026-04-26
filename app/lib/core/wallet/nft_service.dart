/// @file        nft_service.dart
/// @description NFT collection query service. 3-tier fallback: DAS API (1st) → server API (2nd) → RPC (3rd).
///              Reflects Phase 7 audit: DAS API first, supports all of Core NFT/pNFT/cNFT standards.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - NFTService: NFT query service class
///  - NFTService.getCollections(): DAS API first, fallback to server API/RPC
///  - NFTService.getAllNFTs(): query all NFTs as a flat list
///  - NFTService.getNFTByMint(): single NFT detail via DAS API (owner path)
///  - NFTService.fetchAssetByMint(): single DAS getAsset query (for marketplace listing enrichment)
///  - NFTService.getNFTCount(): query total NFT count

/// NFT collection query service with DAS API, server API, and RPC fallback.
///
/// Priority: DAS API (Helius/QuickNode) → Server API (indexed) → On-chain RPC.
/// DAS API returns Token Metadata, Core NFT, and cNFT all unified.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../shared/models/nft_models.dart';
import '../network/api_client.dart';
import 'nft_image_utils.dart';
import 'solana_client.dart';

/// Service for querying NFT holdings, details, and marketplace.
class NFTService {
  NFTService({
    required this.solanaClient,
    this.apiClient,
    this.dasRpcUrl,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// DAS call timeout.
  static const _dasTimeout = Duration(seconds: 15);

  /// Pagination max pages (safety guard — prevents infinite loop).
  static const _maxPages = 50;

  final SolanaClient solanaClient;

  /// Optional server API client for indexed NFT data.
  final ApiClient? apiClient;

  /// DAS API RPC URL (e.g. Helius). If null, DAS is skipped.
  final String? dasRpcUrl;

  final http.Client _http;

  /// Fetch all NFTs owned by [walletAddress], grouped by collection.
  ///
  /// Priority: DAS API → Server API → RPC.
  Future<List<NFTCollection>> getCollections(String walletAddress) async {
    // 1st: server DAS proxy (/api/v2/nft/assets) — Helius key lives on the server only
    debugPrint('[NFT] getCollections($walletAddress) apiClient=${apiClient != null}, dasRpcUrl=$dasRpcUrl');
    if (apiClient != null) {
      try {
        debugPrint('[NFT] Trying server DAS proxy...');
        final assets = await _fetchFromServerDasProxy(walletAddress);
        debugPrint('[NFT] Server DAS proxy returned ${assets.length} assets');
        if (assets.isNotEmpty) {
          return _groupByCollection(assets);
        }
      } catch (e) {
        debugPrint('[NFT] Server DAS proxy failed: $e');
      }
    }

    // 1.5th: dev/test direct DAS call (if dasRpcUrl is set)
    if (dasRpcUrl != null && dasRpcUrl!.isNotEmpty) {
      try {
        final assets = await _fetchFromDas(walletAddress);
        if (assets.isNotEmpty) {
          return _groupByCollection(assets);
        }
      } catch (e) {
        debugPrint('[NFT] DAS direct API failed: $e');
      }
    }

    // 2nd: Server API (legacy on-chain)
    if (apiClient != null) {
      try {
        final response = await apiClient!.get(
          '/nft/collection',
          queryParameters: {'walletAddress': walletAddress},
        );
        if (response.statusCode == 200 && response.data != null) {
          return _parseCollectionsFromServer(response.data);
        }
      } on DioException catch (_) {
        // Server unavailable, fall through
      }
    }

    // 3rd: RPC fallback
    return _fetchCollectionsFromRpc(walletAddress);
  }

  /// Fetch all NFTs as a flat list.
  Future<List<NFTAsset>> getAllNFTs(String walletAddress) async {
    final collections = await getCollections(walletAddress);
    return collections.expand((c) => c.nfts).toList();
  }

  /// Fetch a single NFT by mint address.
  ///
  /// Tries server API first (`GET /nft/:mintAddress`), falls back to
  /// searching all owned NFTs.
  Future<NFTAsset?> getNFTByMint(
    String mintAddress, {
    String? walletAddress,
  }) async {
    // Try server API first
    if (apiClient != null) {
      try {
        final response = await apiClient!.get('/nft/$mintAddress');
        if (response.statusCode == 200 && response.data != null) {
          return _parseNFTAssetFromServer(response.data);
        }
      } on DioException catch (_) {
        // Server unavailable, fall through
      }
    }

    // Fallback: search in owned NFTs if walletAddress provided
    if (walletAddress != null) {
      final allNFTs = await getAllNFTs(walletAddress);
      try {
        return allNFTs.firstWhere((n) => n.mint == mintAddress);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  /// Fetch a single asset's DAS metadata (name / image / collection) for
  /// a given mint. Marketplace listing enrichment uses this — the seller
  /// no longer owns the token while it sits in a ListState PDA, so the
  /// owner-based DAS `getAssetsByOwner` path does NOT return it.
  ///
  /// Priority: server DAS proxy (`GET /nft/asset/:id`) → direct DAS
  /// `getAsset` JSON-RPC with `dasRpcUrl`. Returns null when both
  /// channels are unavailable or the asset is missing.
  Future<NFTAsset?> fetchAssetByMint(String mintAddress) async {
    if (mintAddress.isEmpty) return null;
    // 1st: server DAS proxy (Helius key lives on the server only)
    if (apiClient != null) {
      try {
        final response = await apiClient!.get('/nft/asset/$mintAddress');
        if (response.statusCode == 200 && response.data != null) {
          final item = response.data as Map<String, dynamic>;
          return _parseDasAsset(item);
        }
      } on DioException catch (e) {
        debugPrint('[NFT] server DAS proxy asset/$mintAddress failed: $e');
      }
    }
    // 2nd: direct DAS (only if the Helius key is injected into the app)
    if (dasRpcUrl != null && dasRpcUrl!.isNotEmpty) {
      try {
        final body = jsonEncode({
          'jsonrpc': '2.0',
          'id': 'snowchat-asset-$mintAddress',
          'method': 'getAsset',
          'params': {'id': mintAddress},
        });
        final response = await _http
            .post(
              Uri.parse(dasRpcUrl!),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(_dasTimeout);
        if (response.statusCode != 200) return null;
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final result = json['result'];
        if (result is Map<String, dynamic>) {
          return _parseDasAsset(result);
        }
      } catch (e) {
        debugPrint('[NFT] direct DAS getAsset($mintAddress) failed: $e');
      }
    }
    return null;
  }

  /// Get total NFT count for [walletAddress].
  Future<int> getNFTCount(String walletAddress) async {
    final collections = await getCollections(walletAddress);
    return collections.fold<int>(0, (sum, c) => sum + c.count);
  }

  // ---------------------------------------------------------------------------
  // Private: Server response parsing
  // ---------------------------------------------------------------------------

  List<NFTCollection> _parseCollectionsFromServer(dynamic data) {
    if (data is! List) return [];
    return data.map<NFTCollection>((collection) {
      final c = collection as Map<String, dynamic>;
      final nftsData = c['nfts'] as List? ?? [];
      return NFTCollection(
        name: c['name'] as String? ?? 'Unknown Collection',
        mint: c['mint'] as String? ?? '',
        imageUrl: c['imageUrl'] as String?,
        floorPriceLamports: c['floorPriceLamports'] != null
            ? BigInt.from(c['floorPriceLamports'] as num)
            : null,
        nfts: nftsData
            .map<NFTAsset>(
                (n) => _parseNFTAssetFromServer(n as Map<String, dynamic>))
            .toList(),
      );
    }).toList();
  }

  NFTAsset _parseNFTAssetFromServer(dynamic data) {
    final n = data as Map<String, dynamic>;
    final attributesData = n['attributes'] as List? ?? [];
    return NFTAsset(
      mint: n['mint'] as String? ?? '',
      name: n['name'] as String? ?? 'Unknown NFT',
      imageUrl: n['imageUrl'] as String? ?? '',
      collectionName: n['collectionName'] as String?,
      collectionMint: n['collectionMint'] as String?,
      description: n['description'] as String?,
      externalUrl: n['externalUrl'] as String?,
      isListed: n['isListed'] as bool? ?? false,
      listingPriceLamports: n['listingPriceLamports'] != null
          ? BigInt.from(n['listingPriceLamports'] as num)
          : null,
      attributes: attributesData
          .map<NFTAttribute>((a) {
            final attr = a as Map<String, dynamic>;
            return NFTAttribute(
              traitType: attr['trait_type'] as String? ?? '',
              value: attr['value']?.toString() ?? '',
            );
          })
          .toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Private: Server DAS Proxy (/api/v2/nft/assets)
  // ---------------------------------------------------------------------------

  /// Query NFTs via the server DAS proxy.
  /// The server proxies the Helius DAS API call and forwards the result as-is.
  Future<List<NFTAsset>> _fetchFromServerDasProxy(String walletAddress) async {
    final allAssets = <NFTAsset>[];
    int page = 1;

    while (page <= _maxPages) {
      final response = await apiClient!.get(
        '/nft/assets',
        queryParameters: {
          'owner': walletAddress,
          'page': page,
          'limit': 100,
        },
      );

      if (response.statusCode == 501) {
        // DAS not configured → fall through to the next fallback
        debugPrint('[NFT] Server DAS not configured (501)');
        return [];
      }

      if (response.statusCode != 200 || response.data == null) break;

      final data = response.data as Map<String, dynamic>;
      final items = data['items'] as List? ?? [];
      for (final item in items) {
        final asset = await _parseDasAsset(item as Map<String, dynamic>);
        if (asset != null) allAssets.add(asset);
      }

      final total = data['total'] as int? ?? 0;
      if (allAssets.length >= total || items.length < 100) break;
      page++;
    }

    debugPrint('[NFT] Server DAS proxy returned ${allAssets.length} assets');
    return allAssets;
  }

  // ---------------------------------------------------------------------------
  // Private: DAS API direct (dev/test only)
  // ---------------------------------------------------------------------------

  /// DAS `getAssetsByOwner` — returns Token Metadata, Core, and cNFT all unified.
  Future<List<NFTAsset>> _fetchFromDas(String walletAddress) async {
    final allAssets = <NFTAsset>[];
    int page = 1;
    const limit = 100;
    bool hasMore = true;

    while (hasMore && page <= _maxPages) {
      final body = jsonEncode({
        'jsonrpc': '2.0',
        'id': 'snowchat-nft-$page',
        'method': 'getAssetsByOwner',
        'params': {
          'ownerAddress': walletAddress,
          'page': page,
          'limit': limit,
          'displayOptions': {
            'showCollectionMetadata': true,
            'showUnverifiedCollections': false,
          },
        },
      });

      final response = await _http
          .post(
            Uri.parse(dasRpcUrl!),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_dasTimeout);

      if (response.statusCode != 200) {
        throw Exception('DAS API ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) break;

      final items = result['items'] as List? ?? [];
      for (final item in items) {
        final asset = await _parseDasAsset(item as Map<String, dynamic>);
        if (asset != null) allAssets.add(asset);
      }

      final total = result['total'] as int? ?? 0;
      hasMore = allAssets.length < total && items.length == limit;
      page++;
    }

    debugPrint('[NFT] DAS returned ${allAssets.length} assets');
    return allAssets;
  }

  /// Parse one DAS response item → NFTAsset.
  Future<NFTAsset?> _parseDasAsset(Map<String, dynamic> item) async {
    final id = item['id'] as String? ?? '';
    if (id.isEmpty) return null;

    // interface check — "V1_NFT", "V2_NFT", "ProgrammableNFT", "V1_PRINT", etc.
    final iface = item['interface'] as String? ?? '';
    // Exclude fungible tokens
    if (iface == 'FungibleToken' || iface == 'FungibleAsset') return null;

    final content = item['content'] as Map<String, dynamic>? ?? {};
    final metadata = content['metadata'] as Map<String, dynamic>? ?? {};
    final links = content['links'] as Map<String, dynamic>? ?? {};
    final files = content['files'] as List? ?? [];

    // Image URL: links.image > files[0].uri > json_uri fetch > ''
    String imageUrl = (links['image'] as String?) ?? '';
    if (imageUrl.isEmpty && files.isNotEmpty) {
      final first = files.first;
      if (first is Map) imageUrl = (first['uri'] as String?) ?? '';
    }
    // When DAS returns only json_uri without links/files → fetch off-chain metadata
    if (imageUrl.isEmpty) {
      final jsonUri = content['json_uri'] as String?;
      if (jsonUri != null && jsonUri.isNotEmpty) {
        try {
          final metaResp = await _http
              .get(Uri.parse(jsonUri))
              .timeout(const Duration(seconds: 10));
          if (metaResp.statusCode == 200) {
            final offchain = jsonDecode(metaResp.body) as Map<String, dynamic>;
            imageUrl = (offchain['image'] as String?) ?? '';
          }
        } catch (_) {
          // Off-chain fetch failed — proceed without an image
        }
      }
    }
    imageUrl = normalizeImageUrl(imageUrl);

    // Token standard (also pass interface — for Core NFT classification)
    final tokenStandard = NftTokenStandard.fromDas(
      metadata['token_standard'] as String?,
      dasInterface: iface,
    );

    // Collection
    final grouping = item['grouping'] as List? ?? [];
    String? collectionMint;
    String? collectionName;
    for (final g in grouping) {
      if (g is Map && g['group_key'] == 'collection') {
        collectionMint = g['group_value'] as String?;
        final cMeta = g['collection_metadata'] as Map<String, dynamic>?;
        collectionName = cMeta?['name'] as String?;
        break;
      }
    }

    // Fallback: when DAS doesn't return collection_metadata.name,
    // infer collection name from the NFT name pattern (e.g. "Nomos#5", "SnowNFT #4")
    if (collectionName == null) {
      final nftName = (metadata['name'] as String?) ?? '';
      final match = RegExp(r'^(.+?)\s*#\d+$').firstMatch(nftName);
      if (match != null) {
        collectionName = match.group(1)!.trim();
      }
    }

    // Attributes
    final rawAttrs = metadata['attributes'] as List? ?? [];
    final attributes = rawAttrs.map<NFTAttribute>((a) {
      if (a is Map) {
        return NFTAttribute(
          traitType: (a['trait_type'] ?? a['traitType'] ?? '') as String,
          value: (a['value'] ?? '').toString(),
        );
      }
      return const NFTAttribute(traitType: '', value: '');
    }).where((a) => a.traitType.isNotEmpty).toList();

    // Compressed flag
    final compression = item['compression'] as Map<String, dynamic>?;
    final isCompressed = compression?['compressed'] as bool? ?? false;

    // Extract creator addresses in order — buy_legacy `transfer_creators_fee`
    // requires remaining_accounts in the same order as metadata.creators[].
    // The DAS response exposes them as the top-level `creators` field next to
    // royalty.primary_sale_happened.
    final creatorList = item['creators'] as List? ?? [];
    final creatorAddresses = <String>[];
    for (final c in creatorList) {
      if (c is Map) {
        final addr = c['address'] as String?;
        if (addr != null && addr.isNotEmpty) creatorAddresses.add(addr);
      }
    }

    debugPrint('[NFT] parsed: name=${metadata['name']}, imageUrl=$imageUrl, iface=$iface, creators=${creatorAddresses.length}');
    return NFTAsset(
      mint: id,
      name: (metadata['name'] as String?) ?? 'Unknown NFT',
      imageUrl: imageUrl,
      tokenStandard: tokenStandard,
      collectionName: collectionName,
      collectionMint: collectionMint,
      description: metadata['description'] as String?,
      externalUrl: (links['external_url'] as String?) ??
          (metadata['external_url'] as String?),
      animationUrl: (links['animation_url'] as String?) ??
          content['animation_url'] as String?,
      attributes: attributes,
      isCompressed: isCompressed,
      creatorAddresses: creatorAddresses,
    );
  }

  /// Group an NFTAsset list by collection.
  List<NFTCollection> _groupByCollection(List<NFTAsset> assets) {
    final groups = <String, List<NFTAsset>>{};
    final collectionNames = <String, String>{};

    for (final asset in assets) {
      final key = asset.collectionMint ?? '_uncategorized';
      groups.putIfAbsent(key, () => []).add(asset);
      if (asset.collectionName != null && !collectionNames.containsKey(key)) {
        collectionNames[key] = asset.collectionName!;
      }
    }

    return groups.entries.map((e) {
      final mint = e.key == '_uncategorized' ? '' : e.key;
      final name = collectionNames[e.key] ?? 'Uncategorized';
      final nfts = e.value;
      // Collection cover image = first NFT's image
      final imageUrl = nfts.isNotEmpty ? nfts.first.imageUrl : null;
      return NFTCollection(
        name: name,
        mint: mint,
        nfts: nfts,
        imageUrl: imageUrl,
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  // ---------------------------------------------------------------------------
  // Private: RPC fallback for NFT discovery
  // ---------------------------------------------------------------------------

  /// Fetch NFTs from on-chain by looking at token accounts with amount=1, decimals=0.
  Future<List<NFTCollection>> _fetchCollectionsFromRpc(
      String walletAddress) async {
    try {
      final tokenAccounts =
          await solanaClient.getTokenAccountsByOwner(walletAddress);

      // Filter for NFTs: decimals=0 and amount="1"
      final nftAccounts = tokenAccounts.where((account) {
        return account['decimals'] == 0 && account['amount'] == '1';
      }).toList();

      if (nftAccounts.isEmpty) return [];

      // Group into a single "Uncategorized" collection
      // (proper collection grouping requires Metaplex metadata which
      //  needs the server indexer)
      final nfts = nftAccounts.map<NFTAsset>((account) {
        final mint = account['mint'] as String;
        return NFTAsset(
          mint: mint,
          name: 'NFT ${_shortenAddress(mint)}',
          imageUrl: '', // Requires metadata fetch
          description: 'Mint: $mint',
        );
      }).toList();

      return [
        NFTCollection(
          name: 'Uncategorized',
          mint: '',
          nfts: nfts,
        ),
      ];
    } on SolanaRpcException catch (_) {
      return [];
    }
  }

  static String _shortenAddress(String address) {
    if (address.length <= 8) return address;
    return '${address.substring(0, 4)}...${address.substring(address.length - 4)}';
  }
}
