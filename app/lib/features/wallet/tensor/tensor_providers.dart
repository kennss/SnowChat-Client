/// @file        tensor_providers.dart
/// @description Riverpod providers for the SnowChat Community Fee Share
///              Tensor fork. Network gating (devnet-only on mainnet UI),
///              tensor tx service factory, and PDA fetch providers.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-24
/// @lastUpdated 2026-04-24
///
/// @functions
///  - communityFeaturesEnabledProvider: true on devnet, false on mainnet.
///    UI MUST hide community register/list/buy entry points when false.
///    Legal gate per Agent B audit (§18.5 Regulatory).
///  - tensorTxServiceProvider: single service instance wired against the
///    current network's RpcClient + keypair manager + priority estimator.
///  - communityRegistrationFetchProvider(collectionMint): FutureProvider
///    that returns the CommunityRegistration PDA state (null if unregistered).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solana/solana.dart';

import '../providers/balance_provider.dart';
import '../rpc/rpc_client_provider.dart';
import '../rpc/rpc_config.dart';
import '../transaction/priority_fee_estimator.dart';
import 'community_registration.dart';
import 'tensor_marketplace_buy.dart'
    show findSnowchatVaultPda, findListStatePda;
import 'tensor_tx_service.dart';

/// True when the current wallet network is devnet (or any non-mainnet
/// tagged network). Production UI must watch this provider and **hide**
/// all community register/list/buy affordances on mainnet until Phase 0
/// (haedoe entity + KYC) completes — see Agent B P0 legal section.
final communityFeaturesEnabledProvider = Provider<bool>((ref) {
  final network = ref.watch(solanaNetworkProvider);
  return network == SolanaNetwork.devnet;
});

/// Shared Tensor tx service. Rebuilt when the network changes so the
/// underlying RpcClient / SolanaClient match.
final tensorTxServiceProvider = Provider<TensorTxService>((ref) {
  final rpc = ref.watch(rpcClientProvider);
  final solanaClient = ref.watch(solanaClientProvider);
  final network = ref.watch(solanaNetworkProvider);
  final priority = PriorityFeeEstimator(rpcUrl: network.rpcUrl);
  return TensorTxService(
    rpcClient: rpc,
    solanaClient: solanaClient,
    keypairManager: ref.watch(keypairManagerProvider),
    priorityFeeEstimator: priority,
  );
});

/// Fetches the CommunityRegistration PDA state for a given [collectionMint].
/// Returns null if the PDA does not exist on-chain.
final communityRegistrationFetchProvider =
    FutureProvider.family<CommunityRegistration?, String>(
  (ref, collectionMintBase58) async {
    final service = ref.watch(tensorTxServiceProvider);
    final mint = Ed25519HDPublicKey.fromBase58(collectionMintBase58);
    return await service.fetchRegistration(mint) as CommunityRegistration?;
  },
);

/// Phase X-3: SnowChat marketplace fee vault PDA (Base58 address).
/// Single PDA per program — derive once and keep forever.
final snowchatVaultAddressProvider = FutureProvider<String>((ref) async {
  final pda = await findSnowchatVaultPda();
  return pda.toBase58();
});

/// Phase X-3: list_state PDA (Base58) for a given NFT mint. PDA is
/// per-mint so we use a family. Caller passes mint Base58. keepAlive (no
/// autoDispose) so revisiting the same tx detail does not re-derive.
final listStateAddressProvider =
    FutureProvider.family<String, String>((ref, mintBase58) async {
  final mint = Ed25519HDPublicKey.fromBase58(mintBase58);
  final pda = await findListStatePda(mint: mint);
  return pda.toBase58();
});
