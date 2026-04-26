/// @file        tensor_marketplace_buy_test.dart
/// @description Unit tests for Phase C-1 Dart binding extensions — fee
///              split preview, list/fee_vault PDA derivation, and the
///              25-account `buy_legacy` instruction builder. Devnet v3
///              run artifacts are used as byte-exact PDA fixtures to catch
///              Rust/Dart drift early.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-24
/// @lastUpdated 2026-04-24

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solana/solana.dart';
import 'package:snowchat/features/wallet/tensor/fee_split_preview.dart';
import 'package:snowchat/features/wallet/tensor/tensor_marketplace_buy.dart';
import 'package:snowchat/features/wallet/tensor/tensor_marketplace_constants.dart';

void main() {
  group('computeExpectedSplit', () {
    test('0.1 SOL listing with community: 500k leader share', () {
      final preview = computeExpectedSplit(
        listingPrice: BigInt.from(100_000_000),
        hasCommunity: true,
      );
      // totalTakerFee = 100_000_000 * 200/10_000 = 2_000_000
      // brokerFee    = 2_000_000 * 50/100 = 1_000_000
      // protocolFee  = 1_000_000
      // leaderShare  = 1_000_000 * 5000/10_000 = 500_000
      // platform     = 500_000
      expect(preview.totalTakerFee, BigInt.from(2_000_000));
      expect(preview.brokerFeeTotal, BigInt.from(1_000_000));
      expect(preview.protocolFee, BigInt.from(1_000_000));
      expect(preview.leaderShare, BigInt.from(500_000));
      expect(preview.platformShare, BigInt.from(500_000));
      expect(preview.dustRedirected, false);
    });

    test('0.1 SOL listing without community: all protocol to platform', () {
      final preview = computeExpectedSplit(
        listingPrice: BigInt.from(100_000_000),
        hasCommunity: false,
      );
      expect(preview.leaderShare, BigInt.zero);
      expect(preview.platformShare, BigInt.from(1_000_000));
      expect(preview.dustRedirected, false);
    });

    test('0.0001 SOL listing with community: dust redirect to platform', () {
      // 100_000 * 200/10_000 = 2_000 total taker fee
      // broker = 1_000, protocol = 1_000
      // leader raw = 1_000 * 5000/10_000 = 500 < MIN(1000) → dust merged.
      final preview = computeExpectedSplit(
        listingPrice: BigInt.from(100_000),
        hasCommunity: true,
      );
      expect(preview.leaderShare, BigInt.zero);
      expect(preview.platformShare, BigInt.from(1_000));
      expect(preview.dustRedirected, true);
    });

    test('edge: zero listing price returns all-zero split', () {
      final preview = computeExpectedSplit(
        listingPrice: BigInt.zero,
        hasCommunity: true,
      );
      expect(preview.totalTakerFee, BigInt.zero);
      expect(preview.protocolFee, BigInt.zero);
      expect(preview.leaderShare, BigInt.zero);
      expect(preview.dustRedirected, true);
    });

    test('negative listing price throws', () {
      expect(
        () => computeExpectedSplit(
          listingPrice: BigInt.from(-1),
          hasCommunity: false,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('PDA derivation — matches devnet v3 artifacts', () {
    // Fixture: clients/js/scripts/devnet-buy-split.ts run on v3 program
    // BJMvy7BcwsTXyHP6Ua7ekeE7DUoN2i9KrQyEhgqVJ32z:
    //   child mint  = BHtM2GapgeNhf1SeaEt4oKXC1crfdBsDQaLwev9HF1rF
    //   listState   = 3qfjeeGVf6hwKxMcLHYjJX3m67jZTLreTGgjnvmmYzce
    //   feeVault    = CZ1SdSJqsqkksrxnoq4MSrPgiN1vSGzaERwUrSCw2jjD

    test('findListStatePda matches devnet buy-split fixture', () async {
      final mint = Ed25519HDPublicKey.fromBase58(
        'BHtM2GapgeNhf1SeaEt4oKXC1crfdBsDQaLwev9HF1rF',
      );
      final pda = await findListStatePda(mint: mint);
      expect(pda.toBase58(), '3qfjeeGVf6hwKxMcLHYjJX3m67jZTLreTGgjnvmmYzce');
    });

    test('findFeeVaultPda matches devnet buy-split fixture', () async {
      final listState = Ed25519HDPublicKey.fromBase58(
        '3qfjeeGVf6hwKxMcLHYjJX3m67jZTLreTGgjnvmmYzce',
      );
      final pda = await findFeeVaultPda(stateAddress: listState);
      expect(pda.toBase58(), 'CZ1SdSJqsqkksrxnoq4MSrPgiN1vSGzaERwUrSCw2jjD');
    });

    test('findEditionPda is deterministic', () async {
      final mint = Ed25519HDPublicKey.fromBase58(
        'BHtM2GapgeNhf1SeaEt4oKXC1crfdBsDQaLwev9HF1rF',
      );
      final a = await findEditionPda(mint: mint);
      final b = await findEditionPda(mint: mint);
      expect(a.toBase58(), b.toBase58());
    });
  });

  group('buildBuyLegacyInstruction', () {
    final owner = Ed25519HDPublicKey.fromBase58(
      '55f16FJmfYYJRxbDGz9oB9ba4NgXJy6NuvPkCjezxQwq',
    );
    final payer = Ed25519HDPublicKey.fromBase58(
      '2FsYou1i36PDfZQcfktmQNEZ88pLhvUbFiP3c3kUipm6',
    );
    final mint = Ed25519HDPublicKey.fromBase58(
      'BHtM2GapgeNhf1SeaEt4oKXC1crfdBsDQaLwev9HF1rF',
    );

    test('baseline (no community): 26 fixed accounts + creators', () async {
      final ix = await buildBuyLegacyInstruction(
        mint: mint,
        owner: owner,
        payer: payer,
        maxAmount: BigInt.from(200_000_000),
        creators: <Ed25519HDPublicKey>[owner],
      );
      expect(ix.accounts.length, 26 + 1); // 26 fixed + 1 creator
      expect(ix.accounts[7].isSigner, true); // payer is signer
      expect(ix.accounts[7].isWriteable, true);
    });

    test('with community: community_registration + leaderWallet slotted', () async {
      final community = Ed25519HDPublicKey.fromBase58(
        'BefjhpqCSsVFn4drFVpupdA5HKQ9su5uf5SJQ1hycK7i',
      );
      final ix = await buildBuyLegacyInstruction(
        mint: mint,
        owner: owner,
        payer: payer,
        maxAmount: BigInt.from(200_000_000),
        creators: <Ed25519HDPublicKey>[owner],
        communityRegistration: community,
        leaderWallet: owner,
      );
      // accounts[24] = community_registration, accounts[25] = leader_wallet
      expect(ix.accounts[24].pubKey.toBase58(), community.toBase58());
      expect(ix.accounts[25].pubKey.toBase58(), owner.toBase58());
      expect(ix.accounts[24].isWriteable, true);
      expect(ix.accounts[25].isWriteable, true);
    });

    test('rejects community_registration without leader_wallet', () async {
      final community = Ed25519HDPublicKey.fromBase58(
        'BefjhpqCSsVFn4drFVpupdA5HKQ9su5uf5SJQ1hycK7i',
      );
      expect(
        () => buildBuyLegacyInstruction(
          mint: mint,
          owner: owner,
          payer: payer,
          maxAmount: BigInt.from(100),
          communityRegistration: community,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('data layout: discriminator + u64 maxAmount + two Option-None', () async {
      final ix = await buildBuyLegacyInstruction(
        mint: mint,
        owner: owner,
        payer: payer,
        maxAmount: BigInt.from(100_000_000),
      );
      final data = ix.data.toList(growable: false);
      expect(data.length, 8 + 8 + 1 + 1);
      expect(data.sublist(0, 8), buyLegacyIxDiscriminator);
      // u64 little-endian of 100_000_000 = 0x05F5E100
      final bd = ByteData.sublistView(Uint8List.fromList(data.sublist(8, 16)));
      final lo = bd.getUint32(0, Endian.little);
      final hi = bd.getUint32(4, Endian.little);
      expect(lo, 100_000_000);
      expect(hi, 0);
      expect(data[16], 0); // optionalRoyaltyPct = None
      expect(data[17], 0); // authorizationData = None
    });
  });

  group('buildListLegacyInstruction', () {
    test('account count + discriminator + amount encoding', () async {
      final owner = Ed25519HDPublicKey.fromBase58(
        '55f16FJmfYYJRxbDGz9oB9ba4NgXJy6NuvPkCjezxQwq',
      );
      final mint = Ed25519HDPublicKey.fromBase58(
        'BHtM2GapgeNhf1SeaEt4oKXC1crfdBsDQaLwev9HF1rF',
      );
      final ix = await buildListLegacyInstruction(
        owner: owner,
        mint: mint,
        amount: BigInt.from(500_000_000),
      );
      expect(ix.accounts.length, 19);
      expect(ix.accounts[0].isSigner, true); // owner is signer
      expect(ix.accounts[5].isSigner, true); // payer is signer
      final data = ix.data.toList(growable: false);
      expect(data.length, 8 + 8 + 5);
      expect(data.sublist(0, 8), listLegacyIxDiscriminator);
      final bd = ByteData.sublistView(Uint8List.fromList(data.sublist(8, 16)));
      expect(bd.getUint32(0, Endian.little), 500_000_000);
    });
  });
}
