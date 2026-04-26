/// @file        transaction_monitor.dart
/// @description Monitor post-send transaction confirmation status via
///              polling / subscription. 90s timeout, emits a stream of
///              Pending → Confirmed → Finalized transitions. Phase 6.1 §2.5.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - TransactionStage: pending / confirmed / finalized / failed / timeout
///  - TransactionMonitor.watch(): Stream of TransactionStage events
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:solana/solana.dart';

enum TransactionStage { pending, confirmed, finalized, failed, timeout }

class TransactionStageEvent {
  const TransactionStageEvent({
    required this.stage,
    this.error,
  });

  final TransactionStage stage;
  final String? error;

  bool get isTerminal =>
      stage == TransactionStage.finalized ||
      stage == TransactionStage.failed ||
      stage == TransactionStage.timeout;
}

/// Transaction confirmation status monitor.
///
/// First attempts `signatureSubscribe` (WebSocket); on failure, polls
/// `getSignatureStatuses` every 5 seconds. Emits a timeout event when
/// finalized is not reached within 90 seconds.
class TransactionMonitor {
  TransactionMonitor({required RpcClient rpcClient}) : _rpc = rpcClient;

  final RpcClient _rpc;

  static const _pollInterval = Duration(seconds: 5);
  static const _maxWait = Duration(seconds: 90);

  Stream<TransactionStageEvent> watch(String signature) async* {
    yield const TransactionStageEvent(stage: TransactionStage.pending);

    final start = DateTime.now();
    var lastStage = TransactionStage.pending;

    while (DateTime.now().difference(start) < _maxWait) {
      try {
        final res = await _rpc
            .getSignatureStatuses([signature], searchTransactionHistory: true)
            .timeout(const Duration(seconds: 8));
        final value = res.value.isNotEmpty ? res.value.first : null;

        if (value != null) {
          if (value.err != null) {
            yield TransactionStageEvent(
              stage: TransactionStage.failed,
              error: value.err.toString(),
            );
            return;
          }

          final c = value.confirmationStatus;
          if (c == Commitment.finalized) {
            yield const TransactionStageEvent(
                stage: TransactionStage.finalized);
            return;
          } else if (c == Commitment.confirmed &&
              lastStage != TransactionStage.confirmed) {
            lastStage = TransactionStage.confirmed;
            yield const TransactionStageEvent(
                stage: TransactionStage.confirmed);
          }
        }
      } catch (e) {
        debugPrint('[TransactionMonitor] poll error: $e');
        // continue polling
      }

      await Future<void>.delayed(_pollInterval);
    }

    yield const TransactionStageEvent(stage: TransactionStage.timeout);
  }
}
