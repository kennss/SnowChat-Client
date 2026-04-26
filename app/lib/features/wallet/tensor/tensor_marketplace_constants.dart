/// @file        tensor_marketplace_constants.dart
/// @description SnowChat Community Fee Share Tensor fork — devnet program
///              ID, PDA seeds, instruction discriminators. Values baked by
///              Anchor 0.29 at build time and must match the deployed `.so`.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-24
/// @lastUpdated 2026-04-24

import 'package:solana/solana.dart';

/// SnowChat Community Fee Share marketplace program on Solana devnet.
/// Upgrade authority: 55f16FJmfYYJRxbDGz9oB9ba4NgXJy6NuvPkCjezxQwq.
const String tensorMarketplaceDevnetProgramAddress =
    'BJMvy7BcwsTXyHP6Ua7ekeE7DUoN2i9KrQyEhgqVJ32z';

/// PDA seed prefix — must match `CommunityRegistration::SEED_PREFIX` in
/// program/src/community/state.rs.
const String communityRegistrationSeedPrefix = 'community_registration';

/// Anchor CommunityRegistration account schema version.
const int communityRegistrationVersion = 1;

/// SnowChat ID byte length ("snow" + 32 hex). Passed as `leaderSnowchatId`.
const int snowchatIdBytes = 36;

/// Channel ID byte length. Passed as `channelId`.
const int channelIdBytes = 32;

/// 30-day revoke cooldown in seconds.
const int revokeCooldownSeconds = 30 * 24 * 60 * 60;

/// Account data discriminators — first 8 bytes of sha256("account:<Name>").
/// Values copied from codama-generated TS client (kept in sync manually so
/// tests can spot drift between Dart + TS clients).
const List<int> communityRegistrationAccountDiscriminator = <int>[
  236, 180, 10, 39, 116, 172, 226, 118
];

/// Instruction discriminators — first 8 bytes of sha256("global:<method>").
/// Kept in sync with codama-generated TS client.
const List<int> registerCommunityCollectionIxDiscriminator = <int>[
  250, 58, 139, 204, 162, 147, 82, 44
];

/// Instruction discriminator for `revoke_community_collection`.
const List<int> revokeCommunityCollectionIxDiscriminator = <int>[
  183, 235, 152, 95, 37, 136, 110, 172
];

/// Instruction discriminator for `buy_legacy`.
const List<int> buyLegacyIxDiscriminator = <int>[
  68, 127, 43, 8, 212, 31, 249, 114
];

/// Instruction discriminator for `list_legacy`.
const List<int> listLegacyIxDiscriminator = <int>[
  6, 110, 255, 18, 16, 36, 8, 30
];

/// Instruction discriminator for `delist_legacy`.
const List<int> delistLegacyIxDiscriminator = <int>[
  88, 35, 231, 184, 110, 218, 149, 23,
];

// ---------------------------------------------------------------------------
// External program IDs (mainnet + devnet share these addresses)
// ---------------------------------------------------------------------------

/// Solana System program.
const String systemProgramAddress = '11111111111111111111111111111111';

/// SPL Token program (legacy).
const String splTokenProgramAddress =
    'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';

/// SPL Associated Token Account program.
const String associatedTokenProgramAddress =
    'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';

/// Metaplex Token Metadata program (also defined in service.dart but kept
/// here for the wider buy flow that needs it as a default/optional account).
const String tokenMetadataProgramAddress =
    'metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s';

/// Metaplex authorization-rules program (pNFT support).
const String authorizationRulesProgramAddress =
    'auth9SigNpDKz4sJJ1DfCTuZrZNSAgh9sFD3rboVmgg';

/// SnowChat vault PDA seed — replaces Tensor's fee_vault as the protocol-fee
/// destination. Single-shard PDA owned by our marketplace program (not
/// Tensor). See `external/tensor/marketplace/program/src/community/
/// snowchat_vault.rs`.
const String snowchatVaultSeed = 'snowchat_vault';

// ---------------------------------------------------------------------------
// Fee math constants — must mirror Tensor + program/src/community/fee_split.rs
// ---------------------------------------------------------------------------

/// Tensor protocol fee, in basis points of the listing amount (2.00%).
const int takerFeeBps = 200;

/// Of the total taker fee, this percentage flows to brokers (the rest is
/// the protocol_fee that may split between platform vault + community leader).
const int brokerFeePct = 50;

/// Of the protocol_fee, this is the bps share that goes to the community
/// leader when a registered collection is supplied.
const int communityLeaderShareBps = 5_000;

/// Below this absolute lamports value the leader_share is redirected to the
/// platform vault as dust (matches MIN_LEADER_SHARE_LAMPORTS in the on-chain
/// fee_split.rs).
const int minLeaderShareLamports = 1_000;

/// Tensor fork program ID as Ed25519HDPublicKey.
Ed25519HDPublicKey tensorMarketplaceDevnetProgramId() {
  return Ed25519HDPublicKey.fromBase58(tensorMarketplaceDevnetProgramAddress);
}
