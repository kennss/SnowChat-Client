/// @file        tensor_marketplace_test.dart
/// @description Unit tests for Phase B-6 Dart binding of the SnowChat
///              Community Fee Share Tensor fork. Verifies PDA derivation
///              matches the actual devnet artifacts produced by
///              devnet-buy-split.ts and that instruction discriminators
///              + account account orders align with the Anchor IDL.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-24
/// @lastUpdated 2026-04-24

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:solana/solana.dart';
import 'package:snowchat/features/wallet/tensor/community_registration.dart';
import 'package:snowchat/features/wallet/tensor/tensor_marketplace_constants.dart';
import 'package:snowchat/features/wallet/tensor/tensor_marketplace_service.dart';

void main() {
  group('findCommunityRegistrationPda', () {
    test('matches the devnet buy-split test result (v3)', () async {
      // Fixture captured from a real devnet run on program v3
      // BJMvy7BcwsTXyHP6Ua7ekeE7DUoN2i9KrQyEhgqVJ32z:
      // - tx 3Jr5fTBvCXxysCK4z9vH6CzkujHZtHdHvJTPiB9na7z1T3n72MFESVRpoAChniazkhsLcHpj3GPh7vQs2pc57d3q
      // - collection mint 7bxwUP76a6TYyRXsekKeN6e7FAZwHCDHFhdHuMg67u1f
      // - expected registration PDA BefjhpqCSsVFn4drFVpupdA5HKQ9su5uf5SJQ1hycK7i
      final collectionMint = Ed25519HDPublicKey.fromBase58(
        '7bxwUP76a6TYyRXsekKeN6e7FAZwHCDHFhdHuMg67u1f',
      );
      final pda = await findCommunityRegistrationPda(
        collectionMint: collectionMint,
      );
      expect(
        pda.toBase58(),
        'BefjhpqCSsVFn4drFVpupdA5HKQ9su5uf5SJQ1hycK7i',
      );
    });

    test('is deterministic for the same collection mint', () async {
      final mint = Ed25519HDPublicKey.fromBase58(
        'Ggpw7WErtJGs81VVkNyXmyFSiU4UANj1NmXfeMzEoBXy',
      );
      final a = await findCommunityRegistrationPda(collectionMint: mint);
      final b = await findCommunityRegistrationPda(collectionMint: mint);
      expect(a.toBase58(), b.toBase58());
    });
  });

  group('buildRegisterCommunityInstruction', () {
    test('serialises 8-byte discriminator + 36 + 32 args with correct prefix',
        () async {
      final program = tensorMarketplaceDevnetProgramId();
      final mint = Ed25519HDPublicKey.fromBase58(
        'ADM3TFKp34Hq7Psf2aZShuJx8qQoYCoxWK8uVB5ZubVC',
      );
      final metadata = await findMetaplexMetadataPda(mint);
      final pda = await findCommunityRegistrationPda(collectionMint: mint);

      final snowchatId = Uint8List.fromList(
        List<int>.generate(snowchatIdBytes, (i) => i),
      );
      final channelId = Uint8List.fromList(
        List<int>.generate(channelIdBytes, (i) => 100 + i),
      );

      final ix = await buildRegisterCommunityInstruction(
        registration: pda,
        collectionMint: mint,
        collectionMetadata: metadata,
        leader: Ed25519HDPublicKey.fromBase58(
          '55f16FJmfYYJRxbDGz9oB9ba4NgXJy6NuvPkCjezxQwq',
        ),
        leaderSnowchatId: snowchatId,
        channelId: channelId,
      );

      // Program id + accounts.
      expect(ix.programId.toBase58(), program.toBase58());
      expect(ix.accounts.length, 5);
      expect(ix.accounts[0].pubKey.toBase58(), pda.toBase58());
      expect(ix.accounts[0].isWriteable, true);
      expect(ix.accounts[0].isSigner, false);
      expect(ix.accounts[3].isSigner, true); // leader

      // Data: [discriminator(8), snowchatId(36), channelId(32)].
      final data = ix.data.toList(growable: false);
      expect(data.length, 8 + 36 + 32);
      expect(
        data.sublist(0, 8),
        registerCommunityCollectionIxDiscriminator,
      );
      expect(data.sublist(8, 44), snowchatId);
      expect(data.sublist(44, 76), channelId);
    });

    test('rejects wrong snowchatId length', () async {
      final mint = Ed25519HDPublicKey.fromBase58(
        'ADM3TFKp34Hq7Psf2aZShuJx8qQoYCoxWK8uVB5ZubVC',
      );
      final metadata = await findMetaplexMetadataPda(mint);
      final pda = await findCommunityRegistrationPda(collectionMint: mint);

      expect(
        () => buildRegisterCommunityInstruction(
          registration: pda,
          collectionMint: mint,
          collectionMetadata: metadata,
          leader: Ed25519HDPublicKey.fromBase58(
            '55f16FJmfYYJRxbDGz9oB9ba4NgXJy6NuvPkCjezxQwq',
          ),
          leaderSnowchatId: Uint8List(10), // too short
          channelId: Uint8List(channelIdBytes),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('buildRevokeCommunityInstruction', () {
    test('2 accounts + 8-byte discriminator only (no args)', () async {
      final mint = Ed25519HDPublicKey.fromBase58(
        'ADM3TFKp34Hq7Psf2aZShuJx8qQoYCoxWK8uVB5ZubVC',
      );
      final pda = await findCommunityRegistrationPda(collectionMint: mint);
      final leader = Ed25519HDPublicKey.fromBase58(
        '55f16FJmfYYJRxbDGz9oB9ba4NgXJy6NuvPkCjezxQwq',
      );

      final ix = buildRevokeCommunityInstruction(
        registration: pda,
        leader: leader,
      );

      expect(ix.accounts.length, 2);
      expect(ix.accounts[0].isWriteable, true);
      expect(ix.accounts[1].isSigner, true);
      final data = ix.data.toList(growable: false);
      expect(data.length, 8);
      expect(data, revokeCommunityCollectionIxDiscriminator);
    });
  });

  group('CommunityRegistration.fromBytes', () {
    test('rejects account data with wrong discriminator', () {
      final bad = Uint8List(210); // all zeros — wrong discriminator
      expect(
        () => CommunityRegistration.fromBytes(bad),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses a round-trip synthetic payload (revoked_at = None)', () {
      final raw = Uint8List(272);
      // discriminator
      raw.setRange(0, 8, communityRegistrationAccountDiscriminator);
      raw[8] = 1; // version
      raw[9] = 255; // bump
      // collection_mint = 32 bytes all 0x11
      raw.fillRange(10, 42, 0x11);
      // leader_wallet = 32 bytes all 0x22
      raw.fillRange(42, 74, 0x22);
      // leader_snowchat_id = ASCII "snow" + 32 zeros
      raw.setRange(74, 78, 'snow'.codeUnits);
      // channel_id stays zero
      // metadata_hash stays zero
      // registered_at = 0x0000000061234567 (little-endian)
      final registeredAtBytes = ByteData(8)
        ..setInt64(0, 0x61234567, Endian.little);
      raw.setRange(174, 182, registeredAtBytes.buffer.asUint8List());
      // revoked_at option discriminator = None
      raw[182] = 0;
      // revoked_reason
      raw[183] = 1;
      // cumulative_share_lamports = 500000
      final cum = ByteData(8)..setUint64(0, 500000, Endian.little);
      raw.setRange(184, 192, cum.buffer.asUint8List());
      // trade_count = 1
      final tc = ByteData(8)..setUint64(0, 1, Endian.little);
      raw.setRange(192, 200, tc.buffer.asUint8List());

      final reg = CommunityRegistration.fromBytes(raw);
      expect(reg.version, 1);
      expect(reg.bump, 255);
      expect(reg.registeredAt, 0x61234567);
      expect(reg.revokedAt, null);
      expect(reg.isActive, true);
      expect(reg.cumulativeShareLamports, BigInt.from(500000));
      expect(reg.tradeCount, BigInt.one);
      expect(reg.leaderSnowchatIdString.startsWith('snow'), true);
    });
  });
}
