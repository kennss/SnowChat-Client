/// @file        priority_fee_estimator.dart
/// @description Solana priority-fee estimator. The solana 0.31.2+1 RpcClient
///              does not wrap `getRecentPrioritizationFees` (Spike S2), so we
///              call the raw JSON-RPC via package:http and compute the 75th
///              percentile. All fee values are microLamports per CU (BigInt).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - PriorityFeeEstimator: priority-fee estimation service
///  - estimateMicroLamportsPerCu(): return 75th-percentile microLamports/CU
///  - PriorityFeeException: failure exception

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Raw JSON-RPC priority-fee estimator.
///
/// Why: `solana ^0.31.2+1`'s `RpcClient` does not wrap the
/// `getRecentPrioritizationFees` RPC (Spike S2 finding). Instead of waiting
/// for an upstream PR, POST JSON-RPC directly via `package:http`.
///
/// Always returns BigInt microLamports per CU. Caller converts via
/// ComputeBudgetHelper.
class PriorityFeeEstimator {
  PriorityFeeEstimator({
    required String rpcUrl,
    http.Client? httpClient,
  })  : _rpcUrl = rpcUrl,
        _http = httpClient ?? http.Client();

  final String _rpcUrl;
  final http.Client _http;

  /// Returns the 75th percentile of prioritization fee stats from the last 150 slots.
  ///
  /// [writableAccounts] writable account addresses (Base58) included in
  /// the transaction. An empty array fetches the global recent fee.
  ///
  /// Returns: BigInt microLamports per CU. 0 → floored to 1.
  Future<BigInt> estimateMicroLamportsPerCu({
    List<String> writableAccounts = const [],
  }) async {
    try {
      final body = jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'getRecentPrioritizationFees',
        'params': writableAccounts.isEmpty ? [] : [writableAccounts],
      });

      final res = await _http
          .post(
            Uri.parse(_rpcUrl),
            headers: const {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw PriorityFeeException(
          'RPC HTTP ${res.statusCode}: ${res.body}',
        );
      }

      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      if (decoded.containsKey('error')) {
        throw PriorityFeeException('RPC error: ${decoded['error']}');
      }

      final result = decoded['result'];
      if (result is! List) {
        throw PriorityFeeException(
          'Unexpected result type: ${result.runtimeType}',
        );
      }

      final fees = <BigInt>[];
      for (final entry in result) {
        if (entry is! Map) continue;
        final raw = entry['prioritizationFee'];
        if (raw is num) {
          fees.add(BigInt.from(raw.toInt()));
        } else if (raw is String) {
          final parsed = BigInt.tryParse(raw);
          if (parsed != null) fees.add(parsed);
        }
      }

      if (fees.isEmpty) return BigInt.one;
      fees.sort();

      // 75 percentile (P75)
      final idx = ((fees.length - 1) * 75) ~/ 100;
      final p75 = fees[idx];
      return p75 < BigInt.one ? BigInt.one : p75;
    } catch (e) {
      debugPrint('[PriorityFeeEstimator] failed: $e');
      // Even on failure, the transfer itself should proceed → return a safe default
      return BigInt.from(1000); // 1000 microLamports/CU = very conservative
    }
  }

  void close() => _http.close();
}

class PriorityFeeException implements Exception {
  PriorityFeeException(this.message);
  final String message;

  @override
  String toString() => 'PriorityFeeException: $message';
}
