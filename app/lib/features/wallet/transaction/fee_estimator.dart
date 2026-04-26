/// @file        fee_estimator.dart
/// @description Combined Solana tx base-fee + priority-fee estimator.
///              Phase 6.1 §2.4. Immediately converts the result of
///              RpcClient.getFeeForMessage(int?) to BigInt to preserve the
///              BigInt-only rule.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - FeeEstimate: base + priority + total (all BigInt lamports)
///  - FeeEstimator.estimate(): combined estimate from Message + priority info
///  - FeeEstimator.estimateBaseFee(): calls getFeeForMessage + BigInt conversion
///  - FeeEstimateException

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:solana/solana.dart';

import 'compute_budget_helper.dart';
import 'priority_fee_estimator.dart';

/// Combined fee estimate result (BigInt only).
class FeeEstimate {
  const FeeEstimate({
    required this.baseLamports,
    required this.priorityLamports,
    required this.unitLimit,
    required this.microLamportsPerCu,
    required this.level,
  });

  final BigInt baseLamports;
  final BigInt priorityLamports;
  final int unitLimit;
  final BigInt microLamportsPerCu;
  final PriorityLevel level;

  BigInt get totalLamports => baseLamports + priorityLamports;
}

/// Combined base fee + priority fee estimator.
class FeeEstimator {
  FeeEstimator({
    required RpcClient rpcClient,
    required PriorityFeeEstimator priorityEstimator,
  })  : _rpc = rpcClient,
        _priority = priorityEstimator;

  final RpcClient _rpc;
  final PriorityFeeEstimator _priority;

  /// [message] original message without priority instructions
  ///   (priority fee is summed inside this method).
  /// [feePayer] first-signer public key (required for compile).
  /// [level] user-selected priority level.
  /// [writableAccounts] writable accounts to reference for priority fee estimation.
  Future<FeeEstimate> estimate({
    required Message message,
    required Ed25519HDPublicKey feePayer,
    required PriorityLevel level,
    List<String> writableAccounts = const [],
    int unitLimit = ComputeBudgetHelper.defaultUnitLimit,
  }) async {
    // 1. base fee — uses getFeeForMessage (Spike S4)
    final baseFee = await estimateBaseFee(
      message: message,
      feePayer: feePayer,
    );

    // 2. priority fee — raw JSON-RPC 75 percentile (Spike S2)
    final estimated = await _priority.estimateMicroLamportsPerCu(
      writableAccounts: writableAccounts,
    );
    final clamped = ComputeBudgetHelper.clampPriorityFee(
      microLamportsPerCu: _applyLevelMultiplier(level, estimated),
      unitLimit: unitLimit,
    );
    final priorityLamports = ComputeBudgetHelper.totalPriorityFeeLamports(
      microLamportsPerCu: clamped,
      unitLimit: unitLimit,
    );

    return FeeEstimate(
      baseLamports: baseFee,
      priorityLamports: priorityLamports,
      unitLimit: unitLimit,
      microLamportsPerCu: clamped,
      level: level,
    );
  }

  /// Convert the result of `getFeeForMessage` to BigInt immediately (CLAUDE.md BigInt rule).
  Future<BigInt> estimateBaseFee({
    required Message message,
    required Ed25519HDPublicKey feePayer,
  }) async {
    try {
      final compiled = message.compile(
        // Temporary blockhash — getFeeForMessage does not use blockhash for fee calc
        recentBlockhash: '11111111111111111111111111111111',
        feePayer: feePayer,
      );
      final encoded =
          base64Encode(Uint8List.fromList(compiled.toByteArray().toList()));
      final lamportsInt =
          await _rpc.getFeeForMessage(encoded).timeout(const Duration(seconds: 8));
      if (lamportsInt == null) {
        // RPC returning null falls back to the standard 5000
        return BigInt.from(5000);
      }
      return BigInt.from(lamportsInt);
    } catch (e) {
      debugPrint('[FeeEstimator] base fee fallback: $e');
      return BigInt.from(5000);
    }
  }

  static BigInt _applyLevelMultiplier(PriorityLevel level, BigInt estimated) {
    if (estimated < BigInt.one) estimated = BigInt.one;
    switch (level) {
      case PriorityLevel.slow:
        final v = estimated ~/ BigInt.two;
        return v < BigInt.one ? BigInt.one : v;
      case PriorityLevel.normal:
        return estimated;
      case PriorityLevel.fast:
        return estimated * BigInt.two;
    }
  }
}

class FeeEstimateException implements Exception {
  FeeEstimateException(this.message);
  final String message;
  @override
  String toString() => 'FeeEstimateException: $message';
}
