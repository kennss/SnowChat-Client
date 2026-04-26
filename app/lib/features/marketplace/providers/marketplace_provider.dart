/// @file        marketplace_provider.dart
/// @description NFT Marketplace Riverpod providers — refactored in Phase 2
///              to replace the server escrow backend with the Tensor fork
///              PDA (on-chain list_legacy / buy_legacy / delist_legacy).
///              UI callers are unchanged; only the notifier's tx plumbing
///              swaps. Community fee share applies automatically when the
///              listed NFT's collection is registered on-chain.
///
///              Listing discovery: `getProgramAccounts` against the
///              Tensor program ID + Anchor discriminator memcmp. Metadata
///              (name/image/collection) is enriched in parallel via
///              DAS `getAsset` (server proxy → direct fallback).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-11
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - marketplaceListingsProvider: marketplace listing list (server DB, TBD: on-chain indexer)
///  - myListingsProvider: my listings
///  - marketplaceNotifierProvider: listing create/buy/cancel actions (Tensor PDA)
///  - MarketplaceNotifier.createListing(request): list_legacy on-chain
///  - MarketplaceNotifier.buyListing(listing): buy_legacy on-chain, auto-community

library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solana/base58.dart';
import 'package:solana/dto.dart';
import 'package:solana/solana.dart';

import '../../../core/wallet/nft_service.dart';
import '../../nft/nft_provider.dart' show nftServiceProvider;
import '../../wallet/rpc/rpc_client_provider.dart';
import '../../wallet/tensor/community_registration.dart';
import '../../wallet/tensor/list_state.dart';
import '../../wallet/tensor/tensor_marketplace_constants.dart';
import '../../wallet/tensor/tensor_marketplace_service.dart';
import '../../wallet/tensor/tensor_providers.dart';
import '../../wallet/providers/wallet_list_provider.dart';
import '../../wallet/wallet_provider.dart' show walletProvider;
import '../marketplace_models.dart';

// ---------------------------------------------------------------------------
// Listings providers — on-chain `getProgramAccounts` (Phase 2 refactor).
// ---------------------------------------------------------------------------
//
// Phase 2 architecture: the Tensor fork program is the single source of
// truth for listing state. We discover listings by calling
// `getProgramAccounts` against the program ID with a memcmp filter on the
// `ListState` Anchor discriminator. No server indexer — suitable for the
// devnet MVP and low-volume mainnet launch.
//
// Scaling path (Phase C-3 follow-up, not blocking testing):
//   1. Helius webhook → snowchat-server Postgres table
//   2. Client hits server API with the same signature; on-chain fallback
//      kicks in when server is unavailable
//
// Metadata enrichment (name / image / collection) runs after listings are
// discovered — DAS `getAsset` proxy per mint, in parallel via
// `Future.wait`. Server-side proxy keeps Helius keys off the device; a
// `dasRpcUrl` direct path is used when the server is unreachable.

Future<List<MarketplaceListing>> _fetchOnChainListings({
  required RpcClient rpc,
  required NFTService nftService,
  String? sellerAddress,
  String? collectionMint,
}) async {
  final filters = <ProgramDataFilter>[
    ProgramDataFilter.memcmp(
      offset: 0,
      bytes: listStateAccountDiscriminator,
    ),
    // Owner (seller) pubkey sits at byte 10 in ListState.
    if (sellerAddress != null && sellerAddress.isNotEmpty)
      ProgramDataFilter.memcmp(
        offset: 10,
        bytes: base58decode(sellerAddress),
      ),
  ];

  final accounts = await rpc.getProgramAccounts(
    tensorMarketplaceDevnetProgramAddress,
    encoding: Encoding.base64,
    filters: filters,
    commitment: Commitment.confirmed,
  );

  final rawListings = <MarketplaceListing>[];
  for (final acc in accounts) {
    final data = acc.account.data;
    if (data is! BinaryAccountData) continue;
    final raw = Uint8List.fromList(data.data);
    final parsed = ListState.fromBytes(raw);
    if (parsed == null) continue;
    if (parsed.isExpired) continue;
    if (!parsed.isSolListing) continue; // SPL currency listings skipped in MVP

    final sellerBase58 = parsed.owner.toBase58();
    final mintBase58 = parsed.assetId.toBase58();

    rawListings.add(MarketplaceListing(
      id: acc.pubkey, // ListState PDA address as stable listing id
      nftMintAddress: mintBase58,
      priceLamports: parsed.amount,
      sellerAddress: sellerBase58,
      status: 'ACTIVE',
      listedAt: DateTime.now(), // unknown from ListState alone
      feeBps: 200, // TAKER_FEE_BPS
      royaltyBps: 0,
    ));
  }

  if (rawListings.isEmpty) return rawListings;

  // Parallel metadata fetch — one DAS getAsset per mint. Individual
  // failures are non-fatal: the card falls back to "Unnamed" / placeholder.
  final metadataFutures = rawListings
      .map((l) => nftService.fetchAssetByMint(l.nftMintAddress).catchError(
            (Object e) {
              debugPrint(
                '[Marketplace] metadata fetch failed for ${l.nftMintAddress}: $e',
              );
              return null;
            },
          ))
      .toList();
  final metadata = await Future.wait(metadataFutures);

  final enriched = <MarketplaceListing>[];
  for (var i = 0; i < rawListings.length; i++) {
    final base = rawListings[i];
    final asset = metadata[i];

    // Optional collection-filter — applied post-enrichment because
    // ListState doesn't carry collection info.
    if (collectionMint != null && collectionMint.isNotEmpty) {
      if (asset == null || asset.collectionMint != collectionMint) {
        continue;
      }
    }

    enriched.add(MarketplaceListing(
      id: base.id,
      nftMintAddress: base.nftMintAddress,
      nftName: asset?.name,
      nftImageUrl: asset?.imageUrl,
      collectionName: asset?.collectionName,
      collectionMint: asset?.collectionMint,
      priceLamports: base.priceLamports,
      sellerAddress: base.sellerAddress,
      status: base.status,
      listedAt: base.listedAt,
      feeBps: base.feeBps,
      royaltyBps: base.royaltyBps,
      creatorAddresses: asset?.creatorAddresses ?? const <String>[],
    ));
  }
  return enriched;
}

/// Multi-Wallet Phase 5-5 — D-2: lookup used by removeWallet preCheck.
/// Fetches only active listings for a specific wallet address (skips
/// metadata enrichment — fast path). If caller (selector_sheet) sees
/// result length > 0, blocks remove and shows user a notice.
///
/// Policy: throw on RPC fail (fail-closed) — caller catches and shows
/// "Cannot verify, try again" then blocks remove.
Future<List<String>> fetchActiveListingMintsForOwner({
  required RpcClient rpc,
  required String ownerAddress,
}) async {
  final filters = <ProgramDataFilter>[
    ProgramDataFilter.memcmp(
      offset: 0,
      bytes: listStateAccountDiscriminator,
    ),
    ProgramDataFilter.memcmp(
      offset: 10,
      bytes: base58decode(ownerAddress),
    ),
  ];
  final accounts = await rpc.getProgramAccounts(
    tensorMarketplaceDevnetProgramAddress,
    encoding: Encoding.base64,
    filters: filters,
    commitment: Commitment.confirmed,
  );
  final mints = <String>[];
  for (final acc in accounts) {
    final data = acc.account.data;
    if (data is! BinaryAccountData) continue;
    final parsed = ListState.fromBytes(Uint8List.fromList(data.data));
    if (parsed == null || parsed.isExpired || !parsed.isSolListing) continue;
    mints.add(parsed.assetId.toBase58());
  }
  return mints;
}

/// Marketplace listings — all active on-chain listings for the Tensor
/// fork program. Filter is accepted for API stability; the returned list
/// is already filtered by on-chain state (expired / SPL-currency skipped).
final marketplaceListingsProvider = FutureProvider.autoDispose
    .family<List<MarketplaceListing>, MarketplaceFilter>(
  (ref, filter) async {
    final rpc = ref.watch(rpcClientProvider);
    final nftService = ref.watch(nftServiceProvider);
    try {
      return await _fetchOnChainListings(
        rpc: rpc,
        nftService: nftService,
        sellerAddress: filter.sellerAddress,
        collectionMint: filter.collectionMint,
      );
    } catch (e) {
      debugPrint('[Marketplace] on-chain listings fetch failed: $e');
      rethrow;
    }
  },
);

/// My active listings — Multi-Wallet Phase 5-1: fetches listings for all
/// visible wallets in parallel and merges. UI matches listing.sellerAddress
/// to a wallet entry → "Listed by: <label>" badge (Phase 5-2).
///
/// Single-wallet (legacy) users: visibleEntries is [primary] (length 1) so
/// behavior is identical to before.
///
/// If a per-wallet RPC partially fails, only that wallet's listings are
/// excluded (no impact on other wallets — debugPrint then fallback to
/// empty list).
final myListingsProvider =
    FutureProvider.autoDispose<List<MarketplaceListing>>((ref) async {
  final entries = ref.watch(visibleWalletEntriesProvider);
  if (entries.isEmpty) {
    // If walletIndex is not ready, fallback to legacy active (short window
    // right after bootstrap).
    final walletState = ref.watch(walletProvider);
    final address = walletState.publicKey;
    if (address == null || address.isEmpty) return [];
    final rpc = ref.watch(rpcClientProvider);
    final nftService = ref.watch(nftServiceProvider);
    try {
      return await _fetchOnChainListings(
        rpc: rpc,
        nftService: nftService,
        sellerAddress: address,
      );
    } catch (e) {
      debugPrint('[Marketplace] on-chain my listings fetch failed: $e');
      rethrow;
    }
  }

  final rpc = ref.watch(rpcClientProvider);
  final nftService = ref.watch(nftServiceProvider);

  final futures = entries.map((e) {
    return _fetchOnChainListings(
      rpc: rpc,
      nftService: nftService,
      sellerAddress: e.address,
    ).catchError((Object err) {
      debugPrint(
        '[Marketplace] my listings fetch failed for ${e.address} '
        '(${e.label}): $err',
      );
      return <MarketplaceListing>[];
    });
  });

  final perWallet = await Future.wait(futures);
  // Simple concat — UI sorts by priceLamports/listedAt.
  return perWallet.expand((l) => l).toList();
});

// ---------------------------------------------------------------------------
// Marketplace action notifier
// ---------------------------------------------------------------------------

/// Notifier for marketplace write actions (create listing, buy, cancel).
// autoDispose removed — prevents post-dispose access during screen transitions
final marketplaceNotifierProvider =
    StateNotifierProvider<MarketplaceNotifier, MarketplaceState>(
  (ref) => MarketplaceNotifier(ref),
);

/// State for marketplace operations.
@immutable
class MarketplaceState {
  const MarketplaceState({
    this.isLoading = false,
    this.error,
  });

  final bool isLoading;
  final String? error;

  MarketplaceState copyWith({
    bool? isLoading,
    String? error,
  }) {
    return MarketplaceState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class MarketplaceNotifier extends StateNotifier<MarketplaceState> {
  MarketplaceNotifier(this._ref) : super(const MarketplaceState());

  final Ref _ref;

  /// Purchase a listing via the Tensor fork `buy_legacy` instruction.
  ///
  /// When the listed NFT's collection has a `CommunityRegistration` PDA
  /// on-chain, the registration + leader wallet are slotted into the
  /// instruction so the 50/50 fee split applies automatically.
  ///
  /// [listing] — full listing row; [creators] is the creators[] array to
  /// pass as `remaining_accounts`. When empty, we fall back to the seller
  /// (matches the single-creator collections produced by our devnet
  /// fixtures).
  Future<bool> buyListing({
    required MarketplaceListing listing,
    List<String> creators = const <String>[],
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final walletState = _ref.read(walletProvider);
      final buyerAddress = walletState.publicKey;
      if (buyerAddress == null || buyerAddress.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'Wallet address unavailable',
        );
        return false;
      }

      // Auto-detect community registration — buy tx applies 50/50 split
      // when the collection is registered. Falls back silently when not.
      Ed25519HDPublicKey? communityRegistration;
      Ed25519HDPublicKey? leaderWallet;
      final collectionMintStr = listing.collectionMint;
      if (collectionMintStr != null && collectionMintStr.isNotEmpty) {
        try {
          final collectionMint =
              Ed25519HDPublicKey.fromBase58(collectionMintStr);
          final reg = await _ref
              .read(tensorTxServiceProvider)
              .fetchRegistration(collectionMint);
          if (reg is CommunityRegistration && reg.isActive) {
            communityRegistration = await findCommunityRegistrationPda(
              collectionMint: collectionMint,
            );
            leaderWallet = reg.leaderWallet;
          }
        } catch (e) {
          debugPrint(
            '[Marketplace] Community fetch failed (continuing without split): $e',
          );
        }
      }

      // Creator order MUST match metadata.creators[] exactly or
      // `transfer_creators_fee` fails with TensorError::CreatorMismatch
      // (0x3a9b). Priority:
      //   1. Explicit caller override
      //   2. Listing-embedded creatorAddresses (populated via DAS enrichment)
      //   3. Fallback: re-fetch metadata via DAS getAsset
      //   4. Last resort: seller (only works for single-creator/self-minted NFTs)
      List<String> creatorSource;
      if (creators.isNotEmpty) {
        creatorSource = creators;
      } else if (listing.creatorAddresses.isNotEmpty) {
        creatorSource = listing.creatorAddresses;
      } else {
        try {
          final asset = await _ref
              .read(nftServiceProvider)
              .fetchAssetByMint(listing.nftMintAddress);
          creatorSource = asset?.creatorAddresses ?? <String>[];
        } catch (e) {
          debugPrint('[Marketplace] creator fetch failed: $e');
          creatorSource = const <String>[];
        }
        if (creatorSource.isEmpty) {
          creatorSource = <String>[listing.sellerAddress];
        }
      }
      final creatorsKeys =
          creatorSource.map(Ed25519HDPublicKey.fromBase58).toList();

      // Max amount — add 2x buffer on top of listing price to absorb the
      // royalty creator_fee Tensor enforces separately.
      final maxAmount = listing.priceLamports * BigInt.two;

      final result = await _ref.read(tensorTxServiceProvider).buyNft(
            mint: Ed25519HDPublicKey.fromBase58(listing.nftMintAddress),
            owner: Ed25519HDPublicKey.fromBase58(listing.sellerAddress),
            maxAmountLamports: maxAmount,
            creators: creatorsKeys,
            communityRegistration: communityRegistration,
            leaderWallet: leaderWallet,
          );
      debugPrint('[Marketplace] buy_legacy OK: ${result.signature}');
      state = state.copyWith(isLoading: false);
      _ref.invalidate(myListingsProvider);
      _ref.invalidate(marketplaceListingsProvider);
      return true;
    } catch (e) {
      debugPrint('[Marketplace] buy_legacy failed: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }


  /// Cancel a listing (seller only). Calls `delist_legacy` on-chain; the
  /// NFT returns from the listState PDA ATA back to the seller's ATA and
  /// the listState account closes (rent refunded to rent_payer).
  ///
  /// [listing] — full listing object so we can extract the mint. (Legacy
  /// server-delete endpoint is retired.)
  ///
  /// Multi-Wallet Phase 5-3: if listing.sellerAddress differs from the
  /// active wallet, auto switchActive to that wallet. Must sign with
  /// seller's keypair for PDA delist to succeed.
  Future<bool> cancelListing(MarketplaceListing listing) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Phase 5-3 — auto-switch to seller wallet
      final activeAddr = _ref.read(walletProvider).publicKey;
      if (activeAddr != listing.sellerAddress) {
        final idx = _ref.read(walletIndexProvider).valueOrNull;
        final sellerEntry = idx?.findByAddress(listing.sellerAddress);
        if (sellerEntry == null) {
          state = state.copyWith(
            isLoading: false,
            error: 'This listing belongs to a wallet not in your account.',
          );
          return false;
        }
        await _ref.read(walletProvider.notifier).switchActive(sellerEntry.id);
      }

      final result = await _ref.read(tensorTxServiceProvider).delistNft(
            mint: Ed25519HDPublicKey.fromBase58(listing.nftMintAddress),
          );
      debugPrint('[Marketplace] delist_legacy OK: ${result.signature}');
      state = state.copyWith(isLoading: false);
      _ref.invalidate(myListingsProvider);
      _ref.invalidate(marketplaceListingsProvider);
      return true;
    } catch (e) {
      debugPrint('[Marketplace] delist_legacy failed: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }
}
