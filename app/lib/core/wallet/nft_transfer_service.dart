/// @file        nft_transfer_service.dart
/// @description NFT transfer service — branches between SPL transfer / Metaplex pNFT transfer based on tokenStandard.
///              Reflects Phase 7 audit P1-4: pNFTs cannot use plain SPL transfer.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-09
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - NftTransferService.transfer(): tokenStandard-branched NFT transfer
library;

import 'package:flutter/foundation.dart';

import '../../shared/models/nft_models.dart';
import '../../features/wallet/transaction/spl_transfer_service.dart';

/// NFT transfer result.
class NftTransferResult {
  const NftTransferResult({required this.signature});
  final String signature;
}

/// NFT transfer service — branches by tokenStandard.
/// Reuses SplTransferService (v0 + base64) validated in Phase 6.
class NftTransferService {
  NftTransferService({
    required this.splTransferService,
  });

  final SplTransferService splTransferService;

  /// Transfer NFT. Branches to SPL transfer or unsupported by [tokenStandard].
  ///
  /// Phase 7 supported scope:
  /// - NonFungible, NonFungibleEdition → SPL transfer(amount=1) ✅
  /// - ProgrammableNonFungible → unsupported (requires Metaplex transfer instruction)
  /// - Core NFT → unsupported (requires MPL Core transfer instruction)
  /// - cNFT (compressed) → unsupported (requires Bubblegum transfer)
  /// - Unknown → safely reject
  Future<NftTransferResult> transfer({
    required String recipientAddress,
    required String mintAddress,
    required NftTokenStandard tokenStandard,
    bool isCompressed = false,
  }) async {
    // cNFT requires Bubblegum transfer — SPL not allowed
    if (isCompressed) {
      throw UnsupportedError(
        'Compressed NFT (cNFT) transfer is not yet supported. '
        'Requires Bubblegum program transfer instruction.',
      );
    }
    // Allow only standards that can use SPL transfer
    if (tokenStandard.isSplTransferable) {
      return _transferSpl(
        recipientAddress: recipientAddress,
        mintAddress: mintAddress,
      );
    }
    // Everything else: unsupported
    final label = switch (tokenStandard) {
      NftTokenStandard.programmableNonFungible ||
      NftTokenStandard.programmableNonFungibleEdition =>
        'Programmable NFT (pNFT) requires Metaplex Token Metadata Transfer instruction.',
      NftTokenStandard.core =>
        'Core NFT requires MPL Core program Transfer instruction.',
      _ =>
        'This NFT type is not yet supported for transfer.',
    };
    throw UnsupportedError(label);
  }

  /// Standard NFT (Token Metadata legacy) — reuses Phase 6 SplTransferService.
  /// v0 transaction + base64 encoding + ATA auto-create + confirm wait + built-in biometric.
  Future<NftTransferResult> _transferSpl({
    required String recipientAddress,
    required String mintAddress,
  }) async {
    debugPrint('[NftTransfer] _transferSpl via SplTransferService');
    final sig = await splTransferService.transferToken(
      recipientAddress: recipientAddress,
      mintAddress: mintAddress,
      amount: BigInt.one, // NFT = amount 1
      requireBiometric: false, // already authenticated in nft_send_screen
    );
    debugPrint('[NftTransfer] confirmed: $sig');
    return NftTransferResult(signature: sig);
  }

  /// pNFT (Programmable NFT) — Metaplex Token Metadata `Transfer` instruction.
  /// Includes authorization rules verification.
  ///
  /// Phase 7 1st pass: on pNFT transfer, show "pNFT transfer is not yet supported" to the user.
  /// The full pNFT transfer instruction build is in Phase 7.5 with the Metaplex Rust SDK as reference.
  Future<NftTransferResult> _transferPnft({
    required String recipientAddress,
    required String mintAddress,
  }) async {
    // pNFT transfer requires complex Metaplex Token Metadata instruction:
    // - Transfer instruction with authorization rules
    // - Metadata PDA, Edition PDA, Token Record PDA derivation
    // - Owner/Destination token record accounts
    //
    // The Phase 7 1st pass throws an error to be handled at the UI layer.
    // Phase 7.5 will implement it fully via Borsh serialization.
    throw UnsupportedError(
      'Programmable NFT (pNFT) transfer is not yet supported. '
      'This NFT requires Metaplex Token Metadata Transfer instruction '
      'with authorization rules verification.',
    );
  }
}
