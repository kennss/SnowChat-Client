/// @file        nft_provider.dart
/// @description Riverpod Providers for NFT state management.
///              3-tier fallback: DAS API first -> server API -> RPC.
///              Phase 2: removed all server-escrow market Providers (PDA migration).
///              Market Providers live in `features/marketplace/providers/`.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - nftServiceProvider: provide NFTService instance (incl. DAS URL)
///  - nftCollectionsProvider: fetch NFT collection list with DAS API priority
///  - allNFTsProvider: provide flat list of all NFTs
///  - nftCountProvider: provide total NFT count
///  - selectedNFTProvider: StateProvider managing selected NFT

/// Riverpod providers for NFT state management.
/// DAS API (Helius) → Server API → RPC fallback.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/wallet/nft_service.dart';
import '../../core/wallet/nft_transfer_service.dart';
import '../../shared/models/nft_models.dart';
import '../wallet/wallet_provider.dart'
    show walletProvider, solanaClientProvider, splTransferServiceProvider;
import '../wallet/rpc/rpc_client_provider.dart'
    show solanaNetworkProvider;
import '../../app/providers.dart' show apiClientProvider;

// ---------------------------------------------------------------------------
// Service provider
// ---------------------------------------------------------------------------

final nftServiceProvider = Provider<NFTService>((ref) {
  final network = ref.watch(solanaNetworkProvider);
  return NFTService(
    solanaClient: ref.read(solanaClientProvider),
    dasRpcUrl: network.dasRpcUrl,
    apiClient: ref.read(apiClientProvider),
  );
});

// ---------------------------------------------------------------------------
// Collection / gallery providers
// ---------------------------------------------------------------------------

/// All NFT collections for the current wallet.
/// NFTService internally handles a 3-tier DAS → Server → RPC fallback.
///
/// Tensor PDA listings are auto-excluded — once list_legacy runs, the
/// token is moved to the ListState PDA ATA, so it drops out of the DAS
/// `getAssetsByOwner(user)` response. No separate server filtering needed
/// (the Phase 1 escrow-era `_fetchMyListedMints` has been removed).
final nftCollectionsProvider = FutureProvider<List<NFTCollection>>((ref) async {
  final walletState = ref.watch(walletProvider);
  final address = walletState.publicKey ?? '';
  if (address.isEmpty) return [];
  return ref.read(nftServiceProvider).getCollections(address);
});

/// Flat list of all NFTs.
final allNFTsProvider = FutureProvider<List<NFTAsset>>((ref) async {
  final collections = await ref.watch(nftCollectionsProvider.future);
  return collections.expand((c) => c.nfts).toList();
});

/// Total NFT count.
final nftCountProvider = FutureProvider<int>((ref) async {
  final nfts = await ref.watch(allNFTsProvider.future);
  return nfts.length;
});

/// Phase X-2: NFT asset by mint — keepAlive cache (no autoDispose) so
/// scrolling Activity list does not refire DAS lookups. Used by
/// enhanced_tx_list_tile to render "Listed Nomos #7 at 1 SOL".
/// Returns null on lookup failure (UI falls back to short mint).
final nftAssetByMintProvider =
    FutureProvider.family<NFTAsset?, String>((ref, mint) async {
  if (mint.isEmpty) return null;
  return ref.read(nftServiceProvider).fetchAssetByMint(mint);
});

// ---------------------------------------------------------------------------
// NFT transfer service
// ---------------------------------------------------------------------------

final nftTransferServiceProvider = Provider<NftTransferService>((ref) {
  return NftTransferService(
    splTransferService: ref.read(splTransferServiceProvider),
  );
});

// ---------------------------------------------------------------------------
// Selected NFT (for detail / send screens)
// ---------------------------------------------------------------------------

final selectedNFTProvider = StateProvider<NFTAsset?>((ref) => null);
