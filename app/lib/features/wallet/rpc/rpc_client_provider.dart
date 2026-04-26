/// @file        rpc_client_provider.dart
/// @description Solana RPC client Riverpod Provider — manages the solana
///              package's RpcClient.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-03
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - solanaNetworkProvider: current Solana network state
///  - rpcClientProvider: RpcClient instance (auto-recreated on network switch)
///  - subscriptionClientProvider: WebSocket subscription client

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solana/solana.dart';

import 'rpc_config.dart';

/// Current Solana network state. Default: devnet for development.
final solanaNetworkProvider = StateProvider<SolanaNetwork>((ref) {
  return SolanaNetwork.devnet;
});

/// Solana JSON-RPC client. Recreated when network changes.
final rpcClientProvider = Provider<RpcClient>((ref) {
  final network = ref.watch(solanaNetworkProvider);
  return RpcClient(network.rpcUrl);
});

/// High-level SolanaClient (sign + send + confirm in one step).
final solanaClientProvider = Provider<SolanaClient>((ref) {
  final network = ref.watch(solanaNetworkProvider);
  return SolanaClient(
    rpcUrl: Uri.parse(network.rpcUrl),
    websocketUrl: Uri.parse(network.wsUrl),
  );
});

/// Solana WebSocket subscription client for real-time updates.
final subscriptionClientProvider = Provider<SubscriptionClient>((ref) {
  final network = ref.watch(solanaNetworkProvider);
  return SubscriptionClient(Uri.parse(network.wsUrl));
});
