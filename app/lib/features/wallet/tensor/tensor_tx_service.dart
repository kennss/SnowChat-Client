/// @file        tensor_tx_service.dart
/// @description Orchestrates Tensor fork transaction flows end-to-end:
///              biometric auth → keypair load → Message build →
///              priority fee → v0 sign + send + confirm. Exposes:
///                - sealCollectionMetadata(mint): UpdateMetadataAccountV2
///                  Option<is_mutable = false> seal (required before register)
///                - register(collectionMint, snowchatId, channelId):
///                  register_community_collection
///                - revoke(collectionMint): revoke_community_collection
///                - listNft(mint, priceLamports): list_legacy
///                - buyNft(mint, ownerAddress, maxAmountLamports,
///                  useCommunity, creators): buy_legacy optionally with
///                  community_registration + leader_wallet slotted in
///                  (fee split 50/50 + dust redirect handled on-chain)
///
///              All lamport amounts are BigInt (Wallet CLAUDE.md §2.1).
///              Every mutating call goes through local_auth + v0 send +
///              confirm (no fire-and-forget).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-24
/// @lastUpdated 2026-04-24
///
/// @functions
///  - sealCollectionMetadata(mint): one-way Metaplex seal
///  - register(collectionMint, snowchatId, channelId)
///  - revoke(collectionMint)
///  - listNft(mint, priceLamports)
///  - buyNft(mint, owner, maxAmountLamports, useCommunity, creators)

import 'dart:convert';
import 'dart:typed_data';

import 'package:local_auth/local_auth.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart';

import '../core/keypair_manager.dart';
import '../transaction/compute_budget_helper.dart';
import '../transaction/priority_fee_estimator.dart';
import '../transaction/v0_send_helper.dart';
import 'tensor_marketplace_buy.dart';
import 'tensor_marketplace_constants.dart';
import 'tensor_marketplace_service.dart';

/// Result of a tensor marketplace transaction — surface-level detail for UI.
class TensorTxResult {
  const TensorTxResult({
    required this.signature,
    required this.stepsCompleted,
  });

  /// Transaction signature (Base58).
  final String signature;

  /// Human-readable list of steps that ran for this flow (useful for the
  /// dev screen progress display).
  final List<String> stepsCompleted;
}

/// Exception thrown when a tensor tx pipeline fails. [step] identifies the
/// stage (e.g. "biometric", "seal", "register", "simulate", "send").
class TensorTxException implements Exception {
  TensorTxException(this.step, this.message);
  final String step;
  final String message;

  @override
  String toString() => 'TensorTxException($step): $message';
}

class TensorTxService {
  TensorTxService({
    required RpcClient rpcClient,
    required SolanaClient solanaClient,
    required KeypairManager keypairManager,
    required PriorityFeeEstimator priorityFeeEstimator,
    LocalAuthentication? localAuth,
    Ed25519HDPublicKey? programId,
  })  : _rpcClient = rpcClient,
        _keypairManager = keypairManager,
        _priorityFee = priorityFeeEstimator,
        _v0 = V0SendHelper(solanaClient: solanaClient),
        _localAuth = localAuth ?? LocalAuthentication(),
        _programId = programId ?? tensorMarketplaceDevnetProgramId();

  final RpcClient _rpcClient;
  final KeypairManager _keypairManager;
  final PriorityFeeEstimator _priorityFee;
  final V0SendHelper _v0;
  final LocalAuthentication _localAuth;
  final Ed25519HDPublicKey _programId;

  static final Ed25519HDPublicKey _tokenMetadataProgramId =
      Ed25519HDPublicKey.fromBase58(tokenMetadataProgramAddress);

  /// Seal a Metaplex collection metadata (`is_mutable = false`). This is a
  /// one-way change — required before `register_community_collection` due
  /// to the P1-1 audit remediation. The signer must be the metadata's
  /// `update_authority`.
  Future<TensorTxResult> sealCollectionMetadata({
    required Ed25519HDPublicKey collectionMint,
    String biometricReason = 'Seal NFT collection metadata for community fee share',
  }) async {
    final steps = <String>[];
    await _biometric(biometricReason, steps);
    final keypair = await _loadWallet(steps);

    final metadata = await _metaplexMetadataPda(collectionMint);
    final sealIx = _buildUpdateMetadataAccountV2SealIx(
      metadata: metadata,
      updateAuthority: keypair.publicKey,
    );
    steps.add('seal-ix-built');

    final priorityIxs = await _priorityIxs();
    final message = Message(instructions: [...priorityIxs, sealIx]);

    final signature = await _sendAndConfirm(message, keypair, steps);
    return TensorTxResult(signature: signature, stepsCompleted: steps);
  }

  Future<TensorTxResult> register({
    required Ed25519HDPublicKey collectionMint,
    required String snowchatId,
    required String channelId,
  }) async {
    final steps = <String>[];
    await _biometric('Register community NFT collection', steps);
    final keypair = await _loadWallet(steps);

    final leader = keypair.publicKey;
    final plan = await planRegisterCommunity(
      collectionMint: collectionMint,
      leader: leader,
      snowchatId: snowchatId,
      channelId: channelId,
      programId: _programId,
    );
    steps.add('register-ix-built (pda=${plan.registration.toBase58()})');

    final priorityIxs = await _priorityIxs();
    final message = Message(instructions: [...priorityIxs, plan.instruction]);

    final signature = await _sendAndConfirm(message, keypair, steps);
    return TensorTxResult(signature: signature, stepsCompleted: steps);
  }

  /// Combined seal + register in a single transaction — one biometric
  /// prompt, one signature, one confirm. Used by the ChannelAdminScreen
  /// community section where both steps happen back-to-back.
  Future<TensorTxResult> sealAndRegister({
    required Ed25519HDPublicKey collectionMint,
    required String snowchatId,
    required String channelId,
  }) async {
    final steps = <String>[];
    await _biometric(
      'Seal + register community NFT collection',
      steps,
    );
    final keypair = await _loadWallet(steps);
    final leader = keypair.publicKey;

    final metadata = await _metaplexMetadataPda(collectionMint);
    final sealIx = _buildUpdateMetadataAccountV2SealIx(
      metadata: metadata,
      updateAuthority: leader,
    );
    steps.add('seal-ix-built');

    final plan = await planRegisterCommunity(
      collectionMint: collectionMint,
      leader: leader,
      snowchatId: snowchatId,
      channelId: channelId,
      programId: _programId,
    );
    steps.add('register-ix-built (pda=${plan.registration.toBase58()})');

    final priorityIxs = await _priorityIxs();
    final message = Message(
      instructions: [...priorityIxs, sealIx, plan.instruction],
    );

    final signature = await _sendAndConfirm(message, keypair, steps);
    return TensorTxResult(signature: signature, stepsCompleted: steps);
  }

  Future<TensorTxResult> revoke({
    required Ed25519HDPublicKey collectionMint,
  }) async {
    final steps = <String>[];
    await _biometric('Revoke community collection registration', steps);
    final keypair = await _loadWallet(steps);

    final leader = keypair.publicKey;
    final registration = await findCommunityRegistrationPda(
      collectionMint: collectionMint,
      programId: _programId,
    );
    final ix = buildRevokeCommunityInstruction(
      registration: registration,
      leader: leader,
      programId: _programId,
    );
    steps.add('revoke-ix-built');

    final priorityIxs = await _priorityIxs();
    final message = Message(instructions: [...priorityIxs, ix]);

    final signature = await _sendAndConfirm(message, keypair, steps);
    return TensorTxResult(signature: signature, stepsCompleted: steps);
  }

  Future<TensorTxResult> delistNft({
    required Ed25519HDPublicKey mint,
  }) async {
    final steps = <String>[];
    await _biometric('Cancel NFT listing', steps);
    final keypair = await _loadWallet(steps);
    final owner = keypair.publicKey;

    final ix = await buildDelistLegacyInstruction(
      owner: owner,
      mint: mint,
      programId: _programId,
    );
    steps.add('delist-ix-built');

    final priorityIxs = await _priorityIxs();
    final message = Message(instructions: [...priorityIxs, ix]);

    final signature = await _sendAndConfirm(message, keypair, steps);
    return TensorTxResult(signature: signature, stepsCompleted: steps);
  }

  Future<TensorTxResult> listNft({
    required Ed25519HDPublicKey mint,
    required BigInt priceLamports,
  }) async {
    final steps = <String>[];
    await _biometric(
      'List NFT on SnowChat community marketplace',
      steps,
    );
    final keypair = await _loadWallet(steps);
    final owner = keypair.publicKey;

    final ix = await buildListLegacyInstruction(
      owner: owner,
      mint: mint,
      amount: priceLamports,
      programId: _programId,
    );
    steps.add('list-ix-built');

    final priorityIxs = await _priorityIxs();
    final message = Message(instructions: [...priorityIxs, ix]);

    final signature = await _sendAndConfirm(message, keypair, steps);
    return TensorTxResult(signature: signature, stepsCompleted: steps);
  }

  /// Buys a listed NFT. When [useCommunityRegistration] is non-null, the
  /// buy instruction slots the registration PDA + leader wallet so the
  /// 50/50 fee split applies.
  Future<TensorTxResult> buyNft({
    required Ed25519HDPublicKey mint,
    required Ed25519HDPublicKey owner,
    required BigInt maxAmountLamports,
    required List<Ed25519HDPublicKey> creators,
    Ed25519HDPublicKey? communityRegistration,
    Ed25519HDPublicKey? leaderWallet,
  }) async {
    final steps = <String>[];
    await _biometric('Buy NFT (community split applies if registered)', steps);
    final keypair = await _loadWallet(steps);
    final payer = keypair.publicKey;

    final ix = await buildBuyLegacyInstruction(
      mint: mint,
      owner: owner,
      payer: payer,
      maxAmount: maxAmountLamports,
      creators: creators,
      communityRegistration: communityRegistration,
      leaderWallet: leaderWallet,
      programId: _programId,
    );
    steps.add('buy-ix-built');

    final priorityIxs = await _priorityIxs();
    final message = Message(instructions: [...priorityIxs, ix]);

    final signature = await _sendAndConfirm(message, keypair, steps);
    return TensorTxResult(signature: signature, stepsCompleted: steps);
  }

  /// Fetch the current CommunityRegistration PDA state.
  Future<dynamic> fetchRegistration(
    Ed25519HDPublicKey collectionMint,
  ) async {
    final pda = await findCommunityRegistrationPda(
      collectionMint: collectionMint,
      programId: _programId,
    );
    return fetchCommunityRegistration(rpc: _rpcClient, pda: pda);
  }

  // --- Internals ------------------------------------------------------

  Future<void> _biometric(String reason, List<String> steps) async {
    // NOTE — Samsung devices hang on the fingerprint BiometricPrompt when
    // `biometricOnly: true` + `stickyAuth: true` are both set (observed on
    // Galaxy 25 FE: fingerprint prompt spins forever; cancelling and
    // retrying with face unlock succeeds). Matches the pattern used by
    // sol_transfer_service / spl_transfer_service / create_listing_screen
    // elsewhere in the app — allow device-credential fallback (PIN /
    // pattern / any enrolled biometric) and let the OS pick.
    final ok = await _localAuth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(biometricOnly: false),
    );
    if (!ok) {
      throw TensorTxException('biometric', 'Authentication denied');
    }
    steps.add('biometric-ok');
  }

  Future<Ed25519HDKeyPair> _loadWallet(List<String> steps) async {
    final kp = await _keypairManager.loadWallet();
    steps.add('keypair-loaded');
    return kp;
  }

  Future<List<Instruction>> _priorityIxs() async {
    final estimated = await _priorityFee.estimateMicroLamportsPerCu();
    return ComputeBudgetHelper.buildPriorityInstructions(
      level: PriorityLevel.normal,
      estimatedMicroLamportsPerCu: estimated,
      unitLimit: 400_000,
    );
  }

  Future<String> _sendAndConfirm(
    Message message,
    Ed25519HDKeyPair keypair,
    List<String> steps,
  ) async {
    try {
      final sig = await _v0.sendV0AndConfirm(
        message: message,
        signers: [keypair],
      );
      steps.add('confirmed: $sig');
      return sig;
    } catch (e) {
      steps.add('send-failed: $e');
      throw TensorTxException('send', e.toString());
    }
  }

  Future<Ed25519HDPublicKey> _metaplexMetadataPda(
    Ed25519HDPublicKey mint,
  ) async {
    return Ed25519HDPublicKey.findProgramAddress(
      seeds: <List<int>>[
        utf8.encode('metadata'),
        _tokenMetadataProgramId.bytes,
        mint.bytes,
      ],
      programId: _tokenMetadataProgramId,
    );
  }

  /// Hand-build Metaplex `UpdateMetadataAccountV2` instruction with only
  /// `is_mutable = Some(false)`. Borsh layout:
  ///   disc(u8=15) | Option<DataV2> (0=None) | Option<Pubkey> (0=None)
  ///   | Option<bool primary_sale> (0=None) | Option<bool is_mutable> (1=Some)
  ///   | bool value (0=false)
  /// = 6 bytes total.
  /// Accounts:
  ///   0. metadata (writable)
  ///   1. update_authority (signer, readonly)
  Instruction _buildUpdateMetadataAccountV2SealIx({
    required Ed25519HDPublicKey metadata,
    required Ed25519HDPublicKey updateAuthority,
  }) {
    final data = Uint8List.fromList(<int>[
      15, // discriminator
      0, // Option<DataV2> None
      0, // Option<Pubkey> None
      0, // Option<bool primary_sale> None
      1, // Option<bool is_mutable> Some
      0, // false
    ]);
    return Instruction(
      programId: _tokenMetadataProgramId,
      accounts: <AccountMeta>[
        AccountMeta.writeable(pubKey: metadata, isSigner: false),
        AccountMeta.readonly(pubKey: updateAuthority, isSigner: true),
      ],
      data: ByteArray(data),
    );
  }
}
