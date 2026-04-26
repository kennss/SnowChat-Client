/// @file        wallet_live_provider.dart
/// @description WalletLiveService Riverpod Provider — do NOT use autoDispose (P1-6).
///              Auto-recreated when walletAddressProvider/solanaNetworkProvider change.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - walletLiveServiceProvider: WalletLiveService instance (depends on wallet address)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/balance_provider.dart' show walletAddressProvider;
import '../rpc/rpc_client_provider.dart';
import 'wallet_live_service.dart';

final walletLiveServiceProvider = Provider<WalletLiveService?>((ref) {
  final addrAsync = ref.watch(walletAddressProvider);
  final addr = addrAsync.asData?.value;
  if (addr == null) return null;

  final network = ref.watch(solanaNetworkProvider);
  final svc = WalletLiveService(
    ref: ref,
    wsUri: Uri.parse(network.wsUrl),
    rpcClient: ref.watch(rpcClientProvider),
    walletPubkey: addr,
  );
  ref.onDispose(svc.dispose);
  return svc;
});
