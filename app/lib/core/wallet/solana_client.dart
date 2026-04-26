/// @file        solana_client.dart
/// @description Solana JSON-RPC client. Queries balance, submits transactions, and queries account info via real RPC calls.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - SolanaClient: Solana JSON-RPC client class
///  - SolanaClient.getBalance(): query SOL balance (lamports BigInt)
///  - SolanaClient.getRecentBlockhash(): query recent blockhash
///  - SolanaClient.sendTransaction(): send signed transaction
///  - SolanaClient.simulateTransaction(): simulate transaction
///  - SolanaClient.confirmTransaction(): wait for transaction confirmation
///  - SolanaClient.getTokenAccountsByOwner(): query SPL token accounts
///  - SolanaClient.getAccountInfo(): query account info
///  - SolanaClient.getSignaturesForAddress(): query transaction history
///  - SolanaClient.getTransaction(): query single transaction detail
///  - SolanaClient.getMinimumBalanceForRentExemption(): query minimum balance for rent exemption
///  - SolanaClient.requestAirdrop(): request Devnet airdrop

/// Solana JSON-RPC client with real blockchain integration.
///
/// All RPC calls use dio with 10-second timeout.
/// All monetary values are [BigInt] lamports. NEVER use double for SOL.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../shared/models/wallet_models.dart';
import 'solana_config.dart';

/// Well-known Solana program IDs.
class SolanaProgramIds {
  SolanaProgramIds._();

  static const String systemProgram =
      '11111111111111111111111111111111';
  static const String tokenProgram =
      'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
  static const String tokenProgram2022 =
      'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
  static const String associatedTokenProgram =
      'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
  static const String metaplexTokenMetadata =
      'metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s';
}

/// Exception thrown on Solana RPC errors.
class SolanaRpcException implements Exception {
  SolanaRpcException(this.code, this.message, {this.data});

  final int code;
  final String message;
  final dynamic data;

  @override
  String toString() => 'SolanaRpcException($code): $message';
}

/// Low-level Solana JSON-RPC client using dio.
class SolanaClient {
  SolanaClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'Content-Type': 'application/json'},
            ));

  final Dio _dio;

  /// Auto-incrementing request ID for JSON-RPC.
  int _requestId = 0;

  /// The commitment level to use for queries.
  String commitment = 'confirmed';

  // -------------------------------------------------------------------------
  // RPC Methods
  // -------------------------------------------------------------------------

  /// Get SOL balance for [address] in lamports.
  Future<BigInt> getBalance(String address) async {
    final result = await _rpcCall('getBalance', [
      address,
      {'commitment': commitment},
    ]);
    return BigInt.from(result['value'] as num);
  }

  /// Get the latest blockhash for transaction building.
  Future<String> getRecentBlockhash() async {
    final result = await _rpcCall('getLatestBlockhash', [
      {'commitment': commitment},
    ]);
    return result['value']['blockhash'] as String;
  }

  /// Get the latest blockhash with its last valid block height.
  Future<({String blockhash, int lastValidBlockHeight})>
      getLatestBlockhashWithHeight() async {
    final result = await _rpcCall('getLatestBlockhash', [
      {'commitment': commitment},
    ]);
    return (
      blockhash: result['value']['blockhash'] as String,
      lastValidBlockHeight:
          result['value']['lastValidBlockHeight'] as int,
    );
  }

  /// Send a signed transaction (base64-encoded) and return the signature.
  Future<String> sendTransaction(String signedTxBase64) async {
    final result = await _rpcCall('sendTransaction', [
      signedTxBase64,
      {
        'encoding': 'base64',
        'skipPreflight': false,
        'preflightCommitment': commitment,
      },
    ]);
    return result as String;
  }

  /// Simulate a transaction before sending (pre-flight check).
  Future<Map<String, dynamic>> simulateTransaction(
      String signedTxBase64) async {
    final result = await _rpcCall('simulateTransaction', [
      signedTxBase64,
      {
        'encoding': 'base64',
        'commitment': commitment,
      },
    ]);
    final value = result['value'] as Map<String, dynamic>;
    return {
      'err': value['err'],
      'logs': value['logs'] ?? <String>[],
      'unitsConsumed': value['unitsConsumed'] ?? 0,
    };
  }

  /// Confirm a transaction by polling its status.
  ///
  /// Polls up to [maxRetries] times with [pollInterval] delay.
  Future<TransactionStatus> confirmTransaction(
    String signature, {
    int maxRetries = 30,
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    for (var i = 0; i < maxRetries; i++) {
      try {
        final result = await _rpcCall('getSignatureStatuses', [
          [signature],
        ]);
        final statuses = result['value'] as List;
        if (statuses.isNotEmpty && statuses[0] != null) {
          final status = statuses[0] as Map<String, dynamic>;
          if (status['err'] != null) {
            return TransactionStatus.failed;
          }
          final confirmationStatus =
              status['confirmationStatus'] as String?;
          if (confirmationStatus == 'confirmed' ||
              confirmationStatus == 'finalized') {
            return TransactionStatus.confirmed;
          }
        }
      } catch (_) {
        // Ignore transient errors during polling.
      }
      await Future<void>.delayed(pollInterval);
    }
    return TransactionStatus.pending;
  }

  /// Get all SPL token accounts owned by [address].
  ///
  /// Returns parsed token account data including mint, amount, decimals.
  Future<List<Map<String, dynamic>>> getTokenAccountsByOwner(
      String address) async {
    final result = await _rpcCall('getTokenAccountsByOwner', [
      address,
      {'programId': SolanaProgramIds.tokenProgram},
      {'encoding': 'jsonParsed'},
    ]);
    final accounts = result['value'] as List;
    return accounts.map<Map<String, dynamic>>((account) {
      final parsed = account['account']['data']['parsed']['info']
          as Map<String, dynamic>;
      return {
        'pubkey': account['pubkey'] as String,
        'mint': parsed['mint'] as String,
        'amount': parsed['tokenAmount']['amount'] as String,
        'decimals': parsed['tokenAmount']['decimals'] as int,
        'uiAmount': parsed['tokenAmount']['uiAmountString'] as String?,
      };
    }).toList();
  }

  /// Get account info for [address].
  Future<Map<String, dynamic>?> getAccountInfo(String address) async {
    final result = await _rpcCall('getAccountInfo', [
      address,
      {'encoding': 'jsonParsed'},
    ]);
    final value = result['value'];
    if (value == null) return null;
    return value as Map<String, dynamic>;
  }

  /// Get transaction history for [address].
  Future<List<Map<String, dynamic>>> getSignaturesForAddress(
    String address, {
    int limit = 20,
    String? before,
    String? until,
  }) async {
    final params = <String, dynamic>{
      'limit': limit,
      'commitment': commitment,
    };
    if (before != null) params['before'] = before;
    if (until != null) params['until'] = until;

    final result = await _rpcCall('getSignaturesForAddress', [
      address,
      params,
    ]);
    return (result as List).cast<Map<String, dynamic>>();
  }

  /// Get a single transaction by signature with parsed detail.
  Future<Map<String, dynamic>?> getTransaction(String signature) async {
    final result = await _rpcCall('getTransaction', [
      signature,
      {
        'encoding': 'jsonParsed',
        'commitment': commitment,
        'maxSupportedTransactionVersion': 0,
      },
    ]);
    if (result == null) return null;
    return result as Map<String, dynamic>;
  }

  /// Get minimum balance for rent exemption for [dataLength] bytes.
  Future<BigInt> getMinimumBalanceForRentExemption(int dataLength) async {
    final result =
        await _rpcCall('getMinimumBalanceForRentExemption', [dataLength]);
    return BigInt.from(result as num);
  }

  /// Request an airdrop on Devnet.
  ///
  /// [lamports] is the amount to airdrop in lamports.
  /// Throws if not on Devnet.
  Future<String> requestAirdrop(String address, BigInt lamports) async {
    if (!SolanaConfig.isDevnet) {
      throw StateError('Airdrop is only available on Devnet');
    }
    final result = await _rpcCall('requestAirdrop', [
      address,
      lamports.toInt(),
    ]);
    return result as String;
  }

  /// Request an airdrop in SOL amount (convenience).
  ///
  /// [solAmount] is the SOL amount as a string, e.g. "1" or "2".
  /// Maximum 2 SOL per request on Devnet.
  Future<String> requestAirdropSol(String address, String solAmount) async {
    final parts = solAmount.split('.');
    var lamports = BigInt.parse(parts[0]) * BigInt.from(1000000000);
    if (parts.length > 1) {
      var fracStr = parts[1];
      if (fracStr.length > 9) {
        fracStr = fracStr.substring(0, 9);
      } else {
        fracStr = fracStr.padRight(9, '0');
      }
      lamports += BigInt.parse(fracStr);
    }
    return requestAirdrop(address, lamports);
  }

  // -------------------------------------------------------------------------
  // JSON-RPC internals
  // -------------------------------------------------------------------------

  /// Make a JSON-RPC call and return the result field.
  Future<dynamic> _rpcCall(String method, List<dynamic> params) async {
    _requestId++;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': _requestId,
      'method': method,
      'params': params,
    });

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        SolanaConfig.rpcUrl,
        data: body,
      );

      final data = response.data;
      if (data == null) {
        throw SolanaRpcException(-1, 'Empty response from RPC');
      }

      if (data.containsKey('error')) {
        final error = data['error'] as Map<String, dynamic>;
        throw SolanaRpcException(
          error['code'] as int? ?? -1,
          error['message'] as String? ?? 'Unknown RPC error',
          data: error['data'],
        );
      }

      return data['result'];
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 429) {
        throw SolanaRpcException(
          429,
          'Rate limited. Please wait a moment and try again.',
          data: e.response?.data,
        );
      }
      throw SolanaRpcException(
        statusCode ?? -1,
        'Network error: ${e.message ?? e.type.name}',
        data: e.response?.data,
      );
    }
  }
}
