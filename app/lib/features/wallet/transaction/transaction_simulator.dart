/// @file        transaction_simulator.dart
/// @description Pre-flight Solana transaction simulation — calls
///              `simulateTransaction` and classifies the result as
///              deterministic_error / transient_error / success to decide
///              whether to block the send. Phase 6.1 §2.3.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - SimulationOutcome: success / deterministic-error / transient-error classification
///  - TransactionSimulator.simulate(): base64 tx simulation + classification

import 'package:flutter/foundation.dart';
import 'package:solana/dto.dart' show Commitment, Encoding;
import 'package:solana/solana.dart';

/// Simulation classification result (see Phase 6.1 §2.3 table).
enum SimulationCategory {
  /// Simulation itself succeeded (err == null).
  success,

  /// Insufficient funds / bad instruction etc. — sending will surely fail.
  /// Block the send + show reason to user.
  deterministicError,

  /// Transient error such as RPC timeout / stale blockhash.
  /// Warn the user + allow a "send anyway" option.
  transientError,
}

class SimulationOutcome {
  const SimulationOutcome({
    required this.category,
    required this.err,
    required this.unitsConsumed,
    required this.logs,
    required this.rawMessage,
  });

  final SimulationCategory category;
  final dynamic err;
  final int? unitsConsumed;
  final List<String>? logs;
  final String rawMessage;

  bool get shouldBlockSend => category == SimulationCategory.deterministicError;
  bool get isSuccess => category == SimulationCategory.success;
}

/// Calls `simulateTransaction` and classifies the result.
class TransactionSimulator {
  TransactionSimulator({required RpcClient rpcClient}) : _rpc = rpcClient;

  final RpcClient _rpc;

  /// [encodedTx] base64-encoded signed transaction (or unsigned + replaceRecentBlockhash).
  ///
  /// Always uses `replaceRecentBlockhash: true` (Spike S3 finding) to block
  /// false-positives caused by stale blockhash.
  Future<SimulationOutcome> simulate(String encodedTx) async {
    try {
      final result = await _rpc
          .simulateTransaction(
            encodedTx,
            sigVerify: false,
            replaceRecentBlockhash: true,
            encoding: Encoding.base64,
            commitment: Commitment.confirmed,
          )
          .timeout(const Duration(seconds: 10));

      final status = result.value;
      if (status.err == null) {
        return SimulationOutcome(
          category: SimulationCategory.success,
          err: null,
          unitsConsumed: status.unitsConsumed,
          logs: status.logs,
          rawMessage: 'OK',
        );
      }

      final classification = _classifyErr(status.err);
      return SimulationOutcome(
        category: classification,
        err: status.err,
        unitsConsumed: status.unitsConsumed,
        logs: status.logs,
        rawMessage: status.err.toString(),
      );
    } catch (e) {
      debugPrint('[TransactionSimulator] RPC error: $e');
      return SimulationOutcome(
        category: SimulationCategory.transientError,
        err: e,
        unitsConsumed: null,
        logs: null,
        rawMessage: e.toString(),
      );
    }
  }

  /// Classify the `err` object. Solana RPC returns err as Map or String.
  ///
  /// Deterministic error keywords:
  ///  - InsufficientFunds, InsufficientFundsForRent
  ///  - AccountNotFound (recipient ATA is auto-created, so usually deterministic)
  ///  - InstructionError (mostly deterministic, with a custom code)
  ///  - InvalidAccountData
  ///
  /// Transient error keywords:
  ///  - BlockhashNotFound (still appears even with replaceRecentBlockhash=true)
  ///  - NodeUnhealthy
  static SimulationCategory _classifyErr(dynamic err) {
    final s = err.toString();
    final transientKeywords = [
      'BlockhashNotFound',
      'NodeUnhealthy',
      'TransactionExpired',
    ];
    for (final k in transientKeywords) {
      if (s.contains(k)) return SimulationCategory.transientError;
    }
    return SimulationCategory.deterministicError;
  }
}
