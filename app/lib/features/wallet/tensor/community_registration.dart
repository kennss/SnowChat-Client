/// @file        community_registration.dart
/// @description Dart model + deserializer for the `CommunityRegistration`
///              PDA that tracks a community-leader registration against a
///              Metaplex collection. Layout mirrors the Anchor struct in
///              program/src/community/state.rs (207 bytes payload + 8-byte
///              Anchor discriminator = 215 bytes total).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-24
/// @lastUpdated 2026-04-24
///
/// @functions
///  - CommunityRegistration.fromBytes(bytes): parse raw account data.
///  - CommunityRegistration.isActive: true if never revoked.
///  - CommunityRegistration.toDebugString(): compact human-readable dump.

import 'dart:convert';
import 'dart:typed_data';

import 'package:solana/solana.dart';

import 'tensor_marketplace_constants.dart';

/// Account data for the CommunityRegistration PDA.
///
/// Byte layout (little-endian, matches Anchor Borsh):
/// ```
///   0..8    account discriminator  ([236,180,10,39,116,172,226,118])
///   8..9    version                (u8)
///   9..10   bump                   (u8)
///  10..42   collection_mint        (Pubkey)
///  42..74   leader_wallet          (Pubkey)
///  74..110  leader_snowchat_id     (36 bytes fixed array)
///  110..142 channel_id             (32 bytes)
///  142..174 metadata_hash          (32 bytes — currently unused at runtime)
///  174..182 registered_at          (i64 unix seconds)
///  182..183 Option<i64> discriminator for revoked_at (0=None, 1=Some)
///  183..191 revoked_at value       (i64, only if discriminator == 1)
///  191..192 revoked_reason         (u8)
///  192..200 cumulative_share_lamports (u64)
///  200..208 trade_count            (u64)
///  208..272 _reserved              (64 bytes)
/// ```
class CommunityRegistration {
  CommunityRegistration({
    required this.version,
    required this.bump,
    required this.collectionMint,
    required this.leaderWallet,
    required this.leaderSnowchatId,
    required this.channelId,
    required this.metadataHash,
    required this.registeredAt,
    required this.revokedAt,
    required this.revokedReason,
    required this.cumulativeShareLamports,
    required this.tradeCount,
  });

  final int version;
  final int bump;
  final Ed25519HDPublicKey collectionMint;
  final Ed25519HDPublicKey leaderWallet;
  final Uint8List leaderSnowchatId;
  final Uint8List channelId;
  final Uint8List metadataHash;
  final int registeredAt;
  final int? revokedAt;
  final int revokedReason;
  final BigInt cumulativeShareLamports;
  final BigInt tradeCount;

  bool get isActive => revokedAt == null;

  /// SnowChat ID as ASCII string ("snow" + 32 hex).
  String get leaderSnowchatIdString => ascii.decode(leaderSnowchatId);

  /// Channel ID as UTF-8 string (implementation-defined encoding).
  String get channelIdString => utf8.decode(channelId, allowMalformed: true);

  static CommunityRegistration fromBytes(Uint8List raw) {
    if (raw.length < 208) {
      throw FormatException(
        'CommunityRegistration: expected >= 208 bytes, got ${raw.length}',
      );
    }

    // Discriminator.
    for (var i = 0; i < 8; i++) {
      if (raw[i] != communityRegistrationAccountDiscriminator[i]) {
        throw FormatException(
          'CommunityRegistration: discriminator mismatch at byte $i',
        );
      }
    }

    final bytes = ByteData.sublistView(raw);
    final version = raw[8];
    final bump = raw[9];

    final collectionMint = Ed25519HDPublicKey(raw.sublist(10, 42));
    final leaderWallet = Ed25519HDPublicKey(raw.sublist(42, 74));
    final leaderSnowchatId = Uint8List.fromList(raw.sublist(74, 110));
    final channelId = Uint8List.fromList(raw.sublist(110, 142));
    final metadataHash = Uint8List.fromList(raw.sublist(142, 174));

    final registeredAt = bytes.getInt64(174, Endian.little);

    final revokedAtDiscriminator = raw[182];
    int? revokedAt;
    int cursorAfterOption = 183;
    if (revokedAtDiscriminator == 1) {
      revokedAt = bytes.getInt64(183, Endian.little);
      cursorAfterOption = 191;
    } else {
      cursorAfterOption = 183;
    }

    final revokedReason = raw[cursorAfterOption];
    final cumulativeShareLamports = _readU64(bytes, cursorAfterOption + 1);
    final tradeCount = _readU64(bytes, cursorAfterOption + 9);

    return CommunityRegistration(
      version: version,
      bump: bump,
      collectionMint: collectionMint,
      leaderWallet: leaderWallet,
      leaderSnowchatId: leaderSnowchatId,
      channelId: channelId,
      metadataHash: metadataHash,
      registeredAt: registeredAt,
      revokedAt: revokedAt,
      revokedReason: revokedReason,
      cumulativeShareLamports: cumulativeShareLamports,
      tradeCount: tradeCount,
    );
  }

  static BigInt _readU64(ByteData bytes, int offset) {
    final lo = bytes.getUint32(offset, Endian.little);
    final hi = bytes.getUint32(offset + 4, Endian.little);
    return (BigInt.from(hi) << 32) | BigInt.from(lo);
  }

  String toDebugString() {
    return 'CommunityRegistration('
        'version=$version, '
        'bump=$bump, '
        'collectionMint=${collectionMint.toBase58()}, '
        'leaderWallet=${leaderWallet.toBase58()}, '
        'snowchatId=$leaderSnowchatIdString, '
        'registeredAt=$registeredAt, '
        'revokedAt=$revokedAt, '
        'cumulativeShareLamports=$cumulativeShareLamports, '
        'tradeCount=$tradeCount)';
  }
}
