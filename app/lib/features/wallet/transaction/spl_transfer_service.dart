/// @file        spl_transfer_service.dart
/// @description SPL token transfer service — Phase 6.1 v0 + Priority Fee +
///              Simulate + auto ATA creation. All amounts BigInt only.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-03
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - SplTransferService: SPL token transfer service
///  - transferToken(): SPL transfer (auto-create ATA if missing, v0 + priority fee)
///  - _verifySenderBalance(): sender-ATA balance pre-check (escrow / Token-2022 diagnostics)

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:solana/dto.dart' show Commitment, Encoding;
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart';

import '../core/keypair_manager.dart';
import 'compute_budget_helper.dart';
import 'fee_estimator.dart';
import 'transaction_simulator.dart';
import 'v0_send_helper.dart';

class SplTransferService {
  SplTransferService({
    required SolanaClient solanaClient,
    required KeypairManager keypairManager,
    required FeeEstimator feeEstimator,
    required TransactionSimulator simulator,
    required V0SendHelper v0Sender,
    LocalAuthentication? localAuth,
  })  : _solanaClient = solanaClient,
        _keypairManager = keypairManager,
        _feeEstimator = feeEstimator,
        _simulator = simulator,
        _v0Sender = v0Sender,
        _localAuth = localAuth ?? LocalAuthentication();

  final SolanaClient _solanaClient;
  final KeypairManager _keypairManager;
  final FeeEstimator _feeEstimator;
  final TransactionSimulator _simulator;
  final V0SendHelper _v0Sender;
  final LocalAuthentication _localAuth;

  /// SPL token transfer.
  ///
  /// [recipientAddress] recipient (Base58).
  /// [mintAddress] token mint (Base58).
  /// [amount] token smallest unit (BigInt only).
  /// [level] priority fee level.
  /// [requireBiometric] enforce biometric auth.
  Future<String> transferToken({
    required String recipientAddress,
    required String mintAddress,
    required BigInt amount,
    PriorityLevel level = PriorityLevel.normal,
    bool requireBiometric = true,
    bool forceSendOnTransientSimError = false,
  }) async {
    if (amount <= BigInt.zero) {
      throw SplTransferException('amount must be > 0');
    }

    if (requireBiometric) {
      final ok = await _authenticate();
      if (!ok) throw SplTransferException('Biometric authentication failed');
    }

    final keyPair = await _keypairManager.loadWallet();
    final recipient = Ed25519HDPublicKey.fromBase58(recipientAddress);
    final mint = Ed25519HDPublicKey.fromBase58(mintAddress);

    // Token-2022 compatibility: detect the mint's owner program
    final tokenProgram = await _detectTokenProgram(mintAddress);

    final senderAta = await findAssociatedTokenAddress(
      owner: keyPair.publicKey,
      mint: mint,
      tokenProgramType: tokenProgram,
    );
    final recipientAta = await findAssociatedTokenAddress(
      owner: recipient,
      mint: mint,
      tokenProgramType: tokenProgram,
    );

    // Pre-transfer balance check — if the ATA is empty due to escrow listing
    // / already-transferred / etc., surface an explicit error instead of an
    // RPC simulation error
    await _verifySenderBalance(senderAta.toBase58(), amount);

    final needsAta = await _needsAtaCreation(recipientAta.toBase58());

    final coreInstructions = <Instruction>[];
    if (needsAta) {
      coreInstructions.add(
        AssociatedTokenAccountInstruction.createAccount(
          funder: keyPair.publicKey,
          address: recipientAta,
          owner: recipient,
          mint: mint,
          tokenProgramId: tokenProgram.id,
        ),
      );
    }
    coreInstructions.add(
      TokenInstruction.transfer(
        source: senderAta,
        destination: recipientAta,
        owner: keyPair.publicKey,
        amount: amount.toInt(), // solana package API boundary
        tokenProgram: tokenProgram,
      ),
    );

    // priority fee estimate
    final feeEst = await _feeEstimator.estimate(
      message: Message(instructions: coreInstructions),
      feePayer: keyPair.publicKey,
      level: level,
      writableAccounts: [
        keyPair.publicKey.toBase58(),
        senderAta.toBase58(),
        recipientAta.toBase58(),
      ],
    );

    final priorityIxs = ComputeBudgetHelper.buildPriorityInstructions(
      level: level,
      estimatedMicroLamportsPerCu: feeEst.microLamportsPerCu,
      unitLimit: feeEst.unitLimit,
    );
    final message = Message(instructions: [...priorityIxs, ...coreInstructions]);

    await _runSimulation(
      message: message,
      feePayer: keyPair.publicKey,
      forceSendOnTransientSimError: forceSendOnTransientSimError,
    );

    try {
      final sig = await _v0Sender.sendV0AndConfirm(
        message: message,
        signers: [keyPair],
        commitment: Commitment.confirmed,
      );
      debugPrint('[SplTransfer] success $sig');
      return sig;
    } catch (e) {
      debugPrint('[SplTransfer] failed: $e');
      throw SplTransferException('SPL token transfer failed: $e');
    }
  }

  /// Detect the mint's owner program — for Token-2022 ATA/transfer compatibility.
  /// Returns tokenProgram for the standard Token program, token2022Program for Token-2022.
  Future<TokenProgramType> _detectTokenProgram(String mintAddress) async {
    try {
      final info = await _solanaClient.rpcClient.getAccountInfo(
        mintAddress,
        encoding: Encoding.jsonParsed,
      );
      final owner = info.value?.owner;
      if (owner == 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb') {
        debugPrint('[SplTransfer] Token-2022 mint detected: $mintAddress');
        return TokenProgramType.token2022Program;
      }
    } catch (e) {
      debugPrint('[SplTransfer] Token program detection failed, defaulting to standard: $e');
    }
    return TokenProgramType.tokenProgram;
  }

  /// Pre-check sender ATA balance — surface an explicit error when the
  /// balance is insufficient (market listing/escrow transfer, already
  /// transferred, Token-2022 ATA mismatch, etc.).
  Future<void> _verifySenderBalance(String ataAddress, BigInt required) async {
    try {
      final result = await _solanaClient.rpcClient.getTokenAccountBalance(
        ataAddress,
      );
      final balance = BigInt.tryParse(result.value.amount) ?? BigInt.zero;
      if (balance < required) {
        throw SplTransferException(
          'Token account balance insufficient ($balance < $required). '
          'The token may be listed on marketplace, already transferred, '
          'or held by a different token program (Token-2022).',
        );
      }
    } on SplTransferException {
      rethrow;
    } catch (e) {
      // ATA missing or RPC error → likely not held / listed
      throw SplTransferException(
        'Token account not found or inaccessible. '
        'The token may be locked in an active marketplace listing.',
      );
    }
  }

  Future<bool> _needsAtaCreation(String ataAddress) async {
    try {
      final info = await _solanaClient.rpcClient.getAccountInfo(
        ataAddress,
        encoding: Encoding.jsonParsed,
      );
      return info.value == null;
    } catch (_) {
      return true;
    }
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
        throw SplTransferException(
          'Pre-flight simulation failed: ${outcome.rawMessage}',
        );
      }
      if (outcome.category == SimulationCategory.transientError &&
          !forceSendOnTransientSimError) {
        debugPrint(
          '[SplTransfer] transient sim error (warn only): ${outcome.rawMessage}',
        );
      }
    } on SplTransferException {
      rethrow;
    } catch (e) {
      debugPrint('[SplTransfer] simulation exception (warn only): $e');
    }
  }

  Future<bool> _authenticate() async {
    try {
      final canAuth = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!canAuth) return true;
      return _localAuth.authenticate(
        localizedReason: 'Authenticate to send tokens',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      debugPrint('[SplTransfer] biometric auth error: $e');
      return false;
    }
  }
}

class SplTransferException implements Exception {
  SplTransferException(this.message);
  final String message;
  @override
  String toString() => 'SplTransferException: $message';
}
