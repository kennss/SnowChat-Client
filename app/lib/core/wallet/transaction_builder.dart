/// @file        transaction_builder.dart
/// @description [DEPRECATED — Phase 6.1] Self-serialization-based SOL/SPL transaction builder.
///              From Phase 6.1, features/wallet/transaction/sol_transfer_service.dart
///              + spl_transfer_service.dart + v0_send_helper.dart is the official path;
///              this file is kept for compatibility. Do not use in new code.
///              Removal timing is a separate PR after wallet_provider cleanup.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - BuiltTransaction: built transaction result data class
///  - TransactionBuilder: Solana transaction builder class
///  - TransactionBuilder.buildSOLTransfer(): build SOL transfer transaction
///  - TransactionBuilder.buildSPLTransfer(): build SPL token transfer transaction
///  - TransactionBuilder.buildNFTTransfer(): build NFT transfer transaction
///  - TransactionBuilder.sendSOL(): execute SOL transfer
///  - TransactionBuilder.sendSPLToken(): execute SPL token transfer
///  - _SolanaTransactionSerializer: Solana transaction binary serialization helper

/// Transaction builder for Solana SOL and SPL token transfers.
///
/// Builds real Solana transactions with proper binary serialization:
/// 1. Get recent blockhash
/// 2. Create instructions (SystemProgram for SOL, TokenProgram for SPL)
/// 3. Build compact message (header + account keys + instructions)
/// 4. Sign with Ed25519 private key
/// 5. Serialize (signatures + message) and base64 encode
///
/// All amounts are in lamports (BigInt). NEVER use double for SOL.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'solana_client.dart' show SolanaClient, SolanaProgramIds;
import 'wallet_manager.dart' show WalletManager;

/// Result of building a transaction.
@immutable
class BuiltTransaction {
  const BuiltTransaction({
    required this.serialized,
    required this.signature,
    required this.estimatedFeeLamports,
  });

  /// The signed, serialized transaction (base64).
  final String serialized;

  /// The transaction signature (base58-like hex of first 64 bytes).
  final String signature;

  /// Estimated fee in lamports.
  final BigInt estimatedFeeLamports;
}

/// Builds and signs real Solana transactions.
class TransactionBuilder {
  TransactionBuilder({
    required this.solanaClient,
    required this.walletManager,
  });

  final SolanaClient solanaClient;
  final WalletManager walletManager;

  /// Standard Solana transaction fee (5000 lamports).
  static final BigInt standardFee = BigInt.from(5000);

  // -------------------------------------------------------------------------
  // SOL Transfer
  // -------------------------------------------------------------------------

  /// Build a SOL transfer transaction using SystemProgram.transfer.
  ///
  /// [lamports] must be > 0. The sender is the wallet's active keypair.
  Future<BuiltTransaction> buildSOLTransfer({
    required String toAddress,
    required BigInt lamports,
  }) async {
    _validateAddress(toAddress);
    if (lamports <= BigInt.zero) {
      throw ArgumentError('lamports must be > 0, got $lamports');
    }

    final fromAddress = await walletManager.getPublicKey();
    if (fromAddress == null) {
      throw StateError('Wallet not initialized');
    }

    final blockhash = await solanaClient.getRecentBlockhash();

    // SystemProgram.transfer instruction
    // Program ID: 11111111111111111111111111111111
    // Instruction index 2 = Transfer
    final instructionData = _SolanaTransactionSerializer.encodeTransferInstruction(lamports);

    final accounts = [fromAddress, toAddress, SolanaProgramIds.systemProgram];

    // Build the message
    final message = _SolanaTransactionSerializer.buildMessage(
      recentBlockhash: blockhash,
      accountKeys: accounts,
      instructions: [
        _Instruction(
          programIdIndex: 2, // index of systemProgram in accounts
          accountIndices: Uint8List.fromList([0, 1]), // from, to
          data: instructionData,
        ),
      ],
      numRequiredSignatures: 1,
      numReadonlySignedAccounts: 0,
      numReadonlyUnsignedAccounts: 1, // systemProgram is readonly
    );

    // Sign the message
    final signatureBytes = await walletManager.sign(message);

    // Serialize: compact-array of signatures + message
    final serialized = _SolanaTransactionSerializer.serializeTransaction(
      signatures: [signatureBytes],
      message: message,
    );

    final base64Tx = base64Encode(serialized);
    final sigHex = signatureBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return BuiltTransaction(
      serialized: base64Tx,
      signature: sigHex,
      estimatedFeeLamports: standardFee,
    );
  }

  // -------------------------------------------------------------------------
  // SPL Token Transfer
  // -------------------------------------------------------------------------

  /// Build an SPL token transfer transaction.
  ///
  /// Uses Token Program transferChecked instruction.
  /// [amount] is in the token's smallest unit (based on decimals).
  Future<BuiltTransaction> buildSPLTransfer({
    required String toAddress,
    required String tokenMint,
    required BigInt amount,
    required int decimals,
  }) async {
    _validateAddress(toAddress);
    _validateAddress(tokenMint);
    if (amount <= BigInt.zero) {
      throw ArgumentError('amount must be > 0, got $amount');
    }

    final fromAddress = await walletManager.getPublicKey();
    if (fromAddress == null) {
      throw StateError('Wallet not initialized');
    }

    final blockhash = await solanaClient.getRecentBlockhash();

    // Derive Associated Token Accounts (ATAs)
    final senderAta =
        _deriveAssociatedTokenAddress(fromAddress, tokenMint);
    final receiverAta =
        _deriveAssociatedTokenAddress(toAddress, tokenMint);

    // Check if receiver ATA exists
    final receiverAtaInfo =
        await solanaClient.getAccountInfo(receiverAta);
    final needsAtaCreation = receiverAtaInfo == null;

    final instructions = <_Instruction>[];
    final accounts = <String>[];

    if (needsAtaCreation) {
      // Create ATA instruction accounts:
      // [0] payer (signer, writable) = fromAddress
      // [1] ATA to create (writable) = receiverAta
      // [2] wallet of ATA owner = toAddress
      // [3] mint = tokenMint
      // [4] system program
      // [5] token program
      // [6] associated token program
      // [7] sender ATA (writable)
      accounts.addAll([
        fromAddress, // 0 - payer/signer
        receiverAta, // 1 - new ATA
        toAddress, // 2 - owner
        tokenMint, // 3 - mint
        SolanaProgramIds.systemProgram, // 4
        SolanaProgramIds.tokenProgram, // 5
        SolanaProgramIds.associatedTokenProgram, // 6
        senderAta, // 7 - sender ATA
      ]);

      // CreateAssociatedTokenAccount instruction (instruction index 0, no data)
      instructions.add(_Instruction(
        programIdIndex: 6, // associatedTokenProgram
        accountIndices: Uint8List.fromList([0, 1, 2, 3, 4, 5]),
        data: Uint8List(0),
      ));

      // TransferChecked instruction
      // Data: instruction 12 (transferChecked) + amount (u64 LE) + decimals (u8)
      final transferData =
          _SolanaTransactionSerializer.encodeTransferCheckedInstruction(
              amount, decimals);
      instructions.add(_Instruction(
        programIdIndex: 5, // tokenProgram
        accountIndices:
            Uint8List.fromList([7, 3, 1, 0]), // source, mint, dest, authority
        data: transferData,
      ));
    } else {
      // No ATA creation needed
      accounts.addAll([
        fromAddress, // 0 - signer/authority
        senderAta, // 1 - source ATA
        tokenMint, // 2 - mint
        receiverAta, // 3 - dest ATA
        SolanaProgramIds.tokenProgram, // 4
      ]);

      final transferData =
          _SolanaTransactionSerializer.encodeTransferCheckedInstruction(
              amount, decimals);
      instructions.add(_Instruction(
        programIdIndex: 4, // tokenProgram
        accountIndices:
            Uint8List.fromList([1, 2, 3, 0]), // source, mint, dest, authority
        data: transferData,
      ));
    }

    final numReadonlyUnsigned = needsAtaCreation ? 4 : 2;
    // systemProgram, tokenProgram, associatedTokenProgram, mint are readonly
    // Without ATA creation: tokenProgram, mint are readonly

    final message = _SolanaTransactionSerializer.buildMessage(
      recentBlockhash: blockhash,
      accountKeys: accounts,
      instructions: instructions,
      numRequiredSignatures: 1,
      numReadonlySignedAccounts: 0,
      numReadonlyUnsignedAccounts: numReadonlyUnsigned,
    );

    final signatureBytes = await walletManager.sign(message);
    final serialized = _SolanaTransactionSerializer.serializeTransaction(
      signatures: [signatureBytes],
      message: message,
    );

    final base64Tx = base64Encode(serialized);
    final sigHex = signatureBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    // SPL transfers may need ATA creation, so fee can be higher.
    final fee = needsAtaCreation
        ? standardFee + BigInt.from(2039280) // rent-exempt minimum for ATA
        : standardFee;

    return BuiltTransaction(
      serialized: base64Tx,
      signature: sigHex,
      estimatedFeeLamports: fee,
    );
  }

  // -------------------------------------------------------------------------
  // NFT Transfer
  // -------------------------------------------------------------------------

  /// Build an NFT transfer (SPL transfer with amount = 1, decimals = 0).
  Future<BuiltTransaction> buildNFTTransfer({
    required String toAddress,
    required String nftMint,
  }) async {
    return buildSPLTransfer(
      toAddress: toAddress,
      tokenMint: nftMint,
      amount: BigInt.one,
      decimals: 0,
    );
  }

  // -------------------------------------------------------------------------
  // Send (build + simulate + submit)
  // -------------------------------------------------------------------------

  /// Build, simulate, sign, and submit a SOL transfer. Returns the signature.
  Future<String> sendSOL({
    required String toAddress,
    required BigInt lamports,
  }) async {
    final tx =
        await buildSOLTransfer(toAddress: toAddress, lamports: lamports);

    // Simulate first.
    final sim = await solanaClient.simulateTransaction(tx.serialized);
    if (sim['err'] != null) {
      throw Exception('Transaction simulation failed: ${sim['err']}');
    }

    return solanaClient.sendTransaction(tx.serialized);
  }

  /// Build, simulate, sign, and submit an SPL transfer. Returns the signature.
  Future<String> sendSPLToken({
    required String toAddress,
    required String tokenMint,
    required BigInt amount,
    required int decimals,
  }) async {
    final tx = await buildSPLTransfer(
      toAddress: toAddress,
      tokenMint: tokenMint,
      amount: amount,
      decimals: decimals,
    );

    final sim = await solanaClient.simulateTransaction(tx.serialized);
    if (sim['err'] != null) {
      throw Exception('Transaction simulation failed: ${sim['err']}');
    }

    return solanaClient.sendTransaction(tx.serialized);
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Derive the Associated Token Address for a wallet and mint.
  ///
  /// ATA = PDA([wallet, TOKEN_PROGRAM_ID, mint], ASSOCIATED_TOKEN_PROGRAM_ID)
  /// For now this returns a deterministic placeholder. In production,
  /// use the proper PDA derivation with SHA-256 + find_program_address.
  String _deriveAssociatedTokenAddress(String wallet, String mint) {
    // TODO: Implement proper PDA derivation using:
    //   seeds = [walletBytes, tokenProgramBytes, mintBytes]
    //   programId = associatedTokenProgram
    //   Use SHA-256 and off-curve check
    // For now, use a deterministic hash-based approach
    final combined = '$wallet:$mint:${SolanaProgramIds.associatedTokenProgram}';
    final bytes = utf8.encode(combined);
    // Simple deterministic derivation (replace with real PDA in production)
    final hash = _simpleHash(Uint8List.fromList(bytes));
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    final buf = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buf.write(alphabet[hash[i] % alphabet.length]);
    }
    return buf.toString();
  }

  /// Simple hash for deterministic ATA derivation placeholder.
  Uint8List _simpleHash(Uint8List input) {
    final result = Uint8List(32);
    for (var i = 0; i < input.length; i++) {
      result[i % 32] = (result[i % 32] + input[i] * 31) & 0xFF;
    }
    return result;
  }

  static void _validateAddress(String address) {
    if (address.isEmpty) {
      throw ArgumentError('Address cannot be empty');
    }
    if (address.length < 32 || address.length > 44) {
      throw ArgumentError(
          'Invalid Solana address length: ${address.length}');
    }
    final base58Regex = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
    if (!base58Regex.hasMatch(address)) {
      throw ArgumentError('Invalid base58 characters in address');
    }
  }
}

// ---------------------------------------------------------------------------
// Internal: Instruction model
// ---------------------------------------------------------------------------

class _Instruction {
  _Instruction({
    required this.programIdIndex,
    required this.accountIndices,
    required this.data,
  });

  final int programIdIndex;
  final Uint8List accountIndices;
  final Uint8List data;
}

// ---------------------------------------------------------------------------
// Internal: Solana binary serialization
// ---------------------------------------------------------------------------

/// Helper for building raw Solana transaction bytes.
///
/// Solana transaction wire format (legacy v0):
///   - Compact array of signatures (each 64 bytes)
///   - Message:
///     - Header (3 bytes): numRequiredSignatures, numReadonlySignedAccounts,
///       numReadonlyUnsignedAccounts
///     - Compact array of account public keys (each 32 bytes)
///     - Recent blockhash (32 bytes)
///     - Compact array of instructions
class _SolanaTransactionSerializer {
  _SolanaTransactionSerializer._();

  /// Encode a SystemProgram.Transfer instruction.
  ///
  /// Layout: u32 instruction_index (2 = Transfer) + u64 lamports (LE).
  static Uint8List encodeTransferInstruction(BigInt lamports) {
    final data = Uint8List(12);
    final view = ByteData.view(data.buffer);
    // Instruction index 2 = Transfer
    view.setUint32(0, 2, Endian.little);
    // Lamports as u64 little-endian
    _writeUint64LE(view, 4, lamports);
    return data;
  }

  /// Encode a Token Program TransferChecked instruction.
  ///
  /// Layout: u8 instruction (12 = TransferChecked) + u64 amount (LE) + u8 decimals.
  static Uint8List encodeTransferCheckedInstruction(
      BigInt amount, int decimals) {
    final data = Uint8List(10);
    final view = ByteData.view(data.buffer);
    // Instruction index 12 = TransferChecked
    data[0] = 12;
    // Amount as u64 little-endian
    _writeUint64LE(view, 1, amount);
    // Decimals
    data[9] = decimals;
    return data;
  }

  /// Build a Solana message (legacy format).
  static Uint8List buildMessage({
    required String recentBlockhash,
    required List<String> accountKeys,
    required List<_Instruction> instructions,
    required int numRequiredSignatures,
    required int numReadonlySignedAccounts,
    required int numReadonlyUnsignedAccounts,
  }) {
    final buffer = BytesBuilder();

    // Header (3 bytes)
    buffer.addByte(numRequiredSignatures);
    buffer.addByte(numReadonlySignedAccounts);
    buffer.addByte(numReadonlyUnsignedAccounts);

    // Compact array of account keys
    _writeCompactU16(buffer, accountKeys.length);
    for (final key in accountKeys) {
      buffer.add(_base58Decode(key));
    }

    // Recent blockhash (32 bytes)
    buffer.add(_base58Decode(recentBlockhash));

    // Compact array of instructions
    _writeCompactU16(buffer, instructions.length);
    for (final ix in instructions) {
      buffer.addByte(ix.programIdIndex);

      // Compact array of account indices
      _writeCompactU16(buffer, ix.accountIndices.length);
      buffer.add(ix.accountIndices);

      // Compact array of data bytes
      _writeCompactU16(buffer, ix.data.length);
      buffer.add(ix.data);
    }

    return buffer.toBytes();
  }

  /// Serialize a complete transaction: signatures + message.
  static Uint8List serializeTransaction({
    required List<Uint8List> signatures,
    required Uint8List message,
  }) {
    final buffer = BytesBuilder();

    // Compact array of signatures
    _writeCompactU16(buffer, signatures.length);
    for (final sig in signatures) {
      buffer.add(sig);
    }

    // Message bytes
    buffer.add(message);

    return buffer.toBytes();
  }

  // --- Encoding helpers ---

  /// Write a compact u16 (Solana's variable-length encoding).
  static void _writeCompactU16(BytesBuilder buffer, int value) {
    if (value < 0x80) {
      buffer.addByte(value);
    } else if (value < 0x4000) {
      buffer.addByte((value & 0x7F) | 0x80);
      buffer.addByte(value >> 7);
    } else {
      buffer.addByte((value & 0x7F) | 0x80);
      buffer.addByte(((value >> 7) & 0x7F) | 0x80);
      buffer.addByte(value >> 14);
    }
  }

  /// Write a u64 in little-endian format.
  static void _writeUint64LE(ByteData view, int offset, BigInt value) {
    final low = (value & BigInt.from(0xFFFFFFFF)).toInt();
    final high = ((value >> 32) & BigInt.from(0xFFFFFFFF)).toInt();
    view.setUint32(offset, low, Endian.little);
    view.setUint32(offset + 4, high, Endian.little);
  }

  /// Base58 decode a Solana address/blockhash to 32 bytes.
  ///
  /// Uses the Bitcoin base58 alphabet.
  static Uint8List _base58Decode(String input) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var result = BigInt.zero;
    for (var i = 0; i < input.length; i++) {
      final charIndex = alphabet.indexOf(input[i]);
      if (charIndex < 0) {
        throw FormatException('Invalid base58 character: ${input[i]}');
      }
      result = result * BigInt.from(58) + BigInt.from(charIndex);
    }

    // Convert BigInt to bytes
    final bytes = <int>[];
    while (result > BigInt.zero) {
      bytes.insert(0, (result % BigInt.from(256)).toInt());
      result = result ~/ BigInt.from(256);
    }

    // Add leading zeros for leading '1's in base58
    for (var i = 0; i < input.length && input[i] == '1'; i++) {
      bytes.insert(0, 0);
    }

    // Pad to 32 bytes
    while (bytes.length < 32) {
      bytes.insert(0, 0);
    }

    return Uint8List.fromList(bytes.sublist(bytes.length - 32));
  }
}
