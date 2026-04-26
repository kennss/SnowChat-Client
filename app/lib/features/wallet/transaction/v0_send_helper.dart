/// @file        v0_send_helper.dart
/// @description Versioned Transaction (v0) send pipeline.
///              solana 0.31.2+1's SolanaClient.sendAndConfirmTransaction only
///              calls legacy `signTransaction` (Spike S1), so a dedicated
///              helper is required for v0 sending. Encapsulates the
///              signV0Transaction → sendTransaction → waitForSignatureStatus
///              flow.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - V0SendHelper.sendV0AndConfirm(): integrated v0 build / sign / send / confirm
///  - V0SendException: per-stage failure exception
library;

import 'package:flutter/foundation.dart';
import 'package:solana/dto.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart';

/// Send helper for v0 (Versioned Transaction) only.
///
/// `SolanaClient.sendAndConfirmTransaction` internally uses the legacy
/// `signTransaction`, so sending a v0 transaction requires assembling these
/// steps manually:
///
/// 1. `rpcClient.getLatestBlockhash()` — recent blockhash
/// 2. `signV0Transaction(blockhash, message, signers)` — v0 compile + sign
/// 3. `rpcClient.sendTransaction(encoded)` — RPC send
/// 4. `solanaClient.waitForSignatureStatus(sig, ...)` — confirm wait
///
/// This helper encapsulates those 4 steps. Caller passes `Message` and
/// `signers` only. priority fee instructions must be pre-included in
/// `Message` (prepend ComputeBudgetHelper output to instructions).
class V0SendHelper {
  V0SendHelper({required SolanaClient solanaClient})
      : _solanaClient = solanaClient;

  final SolanaClient _solanaClient;

  /// Build/sign/send a v0 transaction and wait for confirmation.
  ///
  /// [message] — `Message` with instructions only (priority fee included).
  /// [signers] — signer list. First signer is fee payer.
  /// [lookupTables] — when using Address Lookup Tables (optional).
  /// [commitment] — confirmation level (default confirmed).
  ///
  /// Returns: transaction signature (Base58).
  Future<String> sendV0AndConfirm({
    required Message message,
    required List<Ed25519HDKeyPair> signers,
    List<AddressLookupTableAccount> lookupTables = const [],
    Commitment commitment = Commitment.confirmed,
  }) async {
    if (signers.isEmpty) {
      throw V0SendException('At least one signer required');
    }

    // Step 1: latest blockhash
    final LatestBlockhash bh;
    try {
      final result =
          await _solanaClient.rpcClient.getLatestBlockhash(commitment: commitment);
      bh = result.value;
    } catch (e) {
      throw V0SendException('getLatestBlockhash failed: $e');
    }

    // Step 2: v0 compile + sign
    // signV0Transaction takes RecentBlockhash; we adapt LatestBlockhash by
    // wrapping it with a default FeeCalculator (5000 lamports/sig).
    final SignedTx signed;
    try {
      signed = await signV0Transaction(
        RecentBlockhash(
          blockhash: bh.blockhash,
          feeCalculator: const FeeCalculator(lamportsPerSignature: 5000),
        ),
        message,
        signers,
        addressLookupTableAccounts: lookupTables,
      );
    } catch (e) {
      throw V0SendException('signV0Transaction failed: $e');
    }

    // Step 3: send raw transaction
    final String signature;
    try {
      signature = await _solanaClient.rpcClient.sendTransaction(
        signed.encode(),
        preflightCommitment: commitment,
      );
    } catch (e) {
      throw V0SendException('sendTransaction failed: $e');
    }

    debugPrint('[V0SendHelper] sent: $signature');

    // Step 4: wait for confirmation (ConfirmationStatus is a typedef for Commitment)
    try {
      await _solanaClient.waitForSignatureStatus(
        signature,
        status: commitment,
      );
    } catch (e) {
      // Confirm-wait timeout — re-check actual on-chain status.
      // sendTransaction succeeded, so the transaction may already be confirmed.
      debugPrint('[V0SendHelper] confirm wait failed, re-checking on-chain: $e');
      try {
        final statuses = await _solanaClient.rpcClient.getSignatureStatuses(
          [signature],
        );
        final status = statuses.value.firstOrNull;
        if (status != null && status.err == null) {
          // Confirmed on-chain — guard against false negatives
          debugPrint('[V0SendHelper] on-chain re-check: CONFIRMED (was false negative)');
        } else if (status != null && status.err != null) {
          throw V0SendException(
            'Transaction failed on-chain (sig=$signature): ${status.err}',
          );
        } else {
          throw V0SendException(
            'Transaction status unknown after timeout (sig=$signature). '
            'Check explorer: the transaction may still confirm.',
          );
        }
      } catch (recheckErr) {
        if (recheckErr is V0SendException) rethrow;
        throw V0SendException(
          'Confirm timeout + re-check failed (sig=$signature): $e',
        );
      }
    }

    debugPrint('[V0SendHelper] confirmed: $signature');
    return signature;
  }
}

class V0SendException implements Exception {
  V0SendException(this.message);
  final String message;

  @override
  String toString() => 'V0SendException: $message';
}
