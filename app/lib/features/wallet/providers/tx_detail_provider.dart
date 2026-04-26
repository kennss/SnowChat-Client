/// @file        tx_detail_provider.dart
/// @description Transaction detail Provider — returns ParsedTxResult by signature.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-09
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - txDetailProvider: FutureProvider.family(signature) → ParsedTxResult?
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../transaction/transaction_parser.dart';
import '../wallet_provider.dart' show walletProvider, transactionParserProvider;

/// Transaction detail lookup. By signature, traverses 3-tier cache (memory→drift→RPC).
final txDetailProvider = FutureProvider.autoDispose
    .family<ParsedTxResult?, String>((ref, signature) async {
  final pubKey = ref.read(walletProvider).publicKey;
  if (pubKey == null || pubKey.isEmpty) return null;
  final parser = ref.read(transactionParserProvider);
  return parser.classify(signature: signature, ownerAddress: pubKey);
});
