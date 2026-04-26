/// @file        sol_transfer_service.dart
/// @description SOL transfer service — Phase 6.1 v0 + Priority Fee +
///              Simulate pipeline.
///              biometric auth → load key → ComputeBudget +
///              SystemInstruction.transfer → v0 compile/sign → simulate →
///              sendTransaction → wait for confirm.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-03
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - SolTransferService: SOL transfer service class
///  - transferSol(): SOL transfer (BigInt lamports only, v0 + priority fee)
///  - estimateFee(): combined fee estimate (delegates to FeeEstimator)

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:solana/solana.dart';

import '../core/keypair_manager.dart';
import 'compute_budget_helper.dart';
import 'fee_estimator.dart';
import 'transaction_simulator.dart';
import 'v0_send_helper.dart';

/// Phase 6.1 SOL transfer service.
///
/// All amounts are BigInt lamports. Float/double NEVER used.
/// Pipeline:
///   1. biometric auth
///   2. load keypair
///   3. estimate priority fee
///   4. build instructions: [computeBudget x2, transfer]
///   5. simulate (replaceRecentBlockhash=true)
///   6. v0 send + confirm
class SolTransferService {
  SolTransferService({
    required KeypairManager keypairManager,
    required FeeEstimator feeEstimator,
    required TransactionSimulator simulator,
    required V0SendHelper v0Sender,
    LocalAuthentication? localAuth,
  })  : _keypairManager = keypairManager,
        _feeEstimator = feeEstimator,
        _simulator = simulator,
        _v0Sender = v0Sender,
        _localAuth = localAuth ?? LocalAuthentication();

  final KeypairManager _keypairManager;
  final FeeEstimator _feeEstimator;
  final TransactionSimulator _simulator;
  final V0SendHelper _v0Sender;
  final LocalAuthentication _localAuth;

  /// SOL transfer.
  ///
  /// [recipientAddress] Solana address (Base58).
  /// [lamports] transfer amount (BigInt only).
  /// [level] priority fee level (slow/normal/fast).
  /// [requireBiometric] whether biometric auth is required before sending.
  /// [forceSendOnTransientSimError] whether to push through when simulate returns a transient error.
  ///
  /// Returns: transaction signature (Base58).
  Future<String> transferSol({
    required String recipientAddress,
    required BigInt lamports,
    PriorityLevel level = PriorityLevel.normal,
    bool requireBiometric = true,
    bool forceSendOnTransientSimError = false,
  }) async {
    if (lamports <= BigInt.zero) {
      throw TransferException('lamports must be > 0');
    }

    // 1. Biometric auth
    if (requireBiometric) {
      final ok = await _authenticate();
      if (!ok) throw TransferException('Biometric authentication failed');
    }

    // 2. Load keypair
    final keyPair = await _keypairManager.loadWallet();
    final recipient = Ed25519HDPublicKey.fromBase58(recipientAddress);

    // 3. Build core transfer instruction
    final transferIx = SystemInstruction.transfer(
      fundingAccount: keyPair.publicKey,
      recipientAccount: recipient,
      lamports: lamports.toInt(), // solana package API boundary (CLAUDE.md)
    );

    // 4. Estimate priority fee
    final feeEst = await _feeEstimator.estimate(
      message: Message(instructions: [transferIx]),
      feePayer: keyPair.publicKey,
      level: level,
      writableAccounts: [
        keyPair.publicKey.toBase58(),
        recipient.toBase58(),
      ],
    );

    // 5. ComputeBudget + transfer instructions
    final priorityIxs = ComputeBudgetHelper.buildPriorityInstructions(
      level: level,
      estimatedMicroLamportsPerCu: feeEst.microLamportsPerCu,
      unitLimit: feeEst.unitLimit,
    );
    final message = Message(instructions: [...priorityIxs, transferIx]);

    // 6. Simulate (replaceRecentBlockhash=true)
    await _runSimulation(
      message: message,
      feePayer: keyPair.publicKey,
      forceSendOnTransientSimError: forceSendOnTransientSimError,
    );

    // 7. v0 send + confirm
    try {
      final sig = await _v0Sender.sendV0AndConfirm(
        message: message,
        signers: [keyPair],
        commitment: Commitment.confirmed,
      );
      debugPrint('[SolTransfer] success $sig');
      return sig;
    } catch (e) {
      debugPrint('[SolTransfer] failed: $e');
      throw TransferException('SOL transfer failed: $e');
    }
  }

  /// Fee estimate (called from UI preview).
  Future<FeeEstimate> estimateFee({
    required String recipientAddress,
    required BigInt lamports,
    PriorityLevel level = PriorityLevel.normal,
  }) async {
    final keyPair = await _keypairManager.loadWallet();
    final transferIx = SystemInstruction.transfer(
      fundingAccount: keyPair.publicKey,
      recipientAccount: Ed25519HDPublicKey.fromBase58(recipientAddress),
      lamports: lamports.toInt(),
    );
    return _feeEstimator.estimate(
      message: Message(instructions: [transferIx]),
      feePayer: keyPair.publicKey,
      level: level,
      writableAccounts: [
        keyPair.publicKey.toBase58(),
        recipientAddress,
      ],
    );
  }

  Future<void> _runSimulation({
    required Message message,
    required Ed25519HDPublicKey feePayer,
    required bool forceSendOnTransientSimError,
  }) async {
    try {
      final compiled = message.compile(
        recentBlockhash: '11111111111111111111111111111111',
        feePayer: feePayer,
      );
      final encoded =
          base64Encode(Uint8List.fromList(compiled.toByteArray().toList()));
      final outcome = await _simulator.simulate(encoded);

      if (outcome.shouldBlockSend) {
        throw TransferException(
          'Pre-flight simulation failed: ${outcome.rawMessage}',
        );
      }
      if (outcome.category == SimulationCategory.transientError &&
          !forceSendOnTransientSimError) {
        debugPrint(
          '[SolTransfer] transient sim error, proceeding (warning only): '
          '${outcome.rawMessage}',
        );
      }
    } on TransferException {
      rethrow;
    } catch (e) {
      // The simulation call itself failed → warn only; proceed with send
      debugPrint('[SolTransfer] simulation exception (warn only): $e');
    }
  }

  Future<bool> _authenticate() async {
    try {
      final canAuth = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!canAuth) return true;
      return _localAuth.authenticate(
        localizedReason: 'Authenticate to send SOL',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      debugPrint('[SolTransfer] biometric auth error: $e');
      return false;
    }
  }
}

class TransferException implements Exception {
  TransferException(this.message);
  final String message;
  @override
  String toString() => 'TransferException: $message';
}
