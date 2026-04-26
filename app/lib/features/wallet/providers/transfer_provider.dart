/// @file        transfer_provider.dart
/// @description SOL transfer service Riverpod Provider — Phase 6.1 v0 +
///              priority-fee pipeline dependency injection.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-03
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - solTransferServiceProvider: SolTransferService instance (Phase 6.1)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rpc/rpc_client_provider.dart';
import '../transaction/fee_estimator.dart';
import '../transaction/priority_fee_estimator.dart';
import '../transaction/sol_transfer_service.dart';
import '../transaction/transaction_simulator.dart';
import '../transaction/v0_send_helper.dart';
import '../wallet_provider.dart' as wp;
import 'balance_provider.dart';

/// SolTransferService instance provider (Phase 6.1).
///
/// All dependencies reuse the canonical Providers defined in
/// [wallet_provider.dart]. To share the same object graph instead of creating
/// separate instances, this provider forwards `wp.solTransferServiceProvider`
/// as-is.
final solTransferServiceProvider = Provider<SolTransferService>((ref) {
  return ref.watch(wp.solTransferServiceProvider);
});

/// Fallback factory for cases that genuinely need a fresh instance.
/// (Tests and other special cases.)
SolTransferService createSolTransferService(Ref ref) {
  final network = ref.read(solanaNetworkProvider);
  return SolTransferService(
    keypairManager: ref.read(keypairManagerProvider),
    feeEstimator: FeeEstimator(
      rpcClient: ref.read(rpcClientProvider),
      priorityEstimator: PriorityFeeEstimator(rpcUrl: network.rpcUrl),
    ),
    simulator: TransactionSimulator(rpcClient: ref.read(rpcClientProvider)),
    v0Sender: V0SendHelper(
      solanaClient: ref.read(wp.newSolanaClientProvider),
    ),
  );
}
