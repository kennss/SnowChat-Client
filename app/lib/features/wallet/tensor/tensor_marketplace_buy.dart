/// @file        tensor_marketplace_buy.dart
/// @description Dart instruction builders for the Tensor fork's buy/list
///              legacy flow. Covers:
///                - findListStatePda, findSnowchatVaultPda, findEditionPda
///                - findAssociatedTokenAddress (standard SPL ATA)
///                - buildListLegacyInstruction (owner lists an NFT)
///                - buildBuyLegacyInstruction (buyer with optional
///                  community_registration + leader_wallet for 50/50 split)
///              Mirrors codama-generated TS client account order and
///              Borsh instruction layout, except fee_vault is replaced with
///              SnowChat-owned snowchat_vault (B-1 policy, 2026-04-24).
///              BigInt lamports throughout (Wallet module CLAUDE.md §2.1).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-24
/// @lastUpdated 2026-04-24
///
/// @functions
///  - findListStatePda(mint): list_state PDA derivation
///  - findSnowchatVaultPda(): SnowChat protocol-fee vault PDA
///  - findEditionPda(mint): Metaplex master edition PDA
///  - findAssociatedTokenAddress(owner, mint): standard ATA
///  - buildListLegacyInstruction(...): list_legacy ix
///  - buildBuyLegacyInstruction(...): buy_legacy ix with optional community

import 'dart:convert';
import 'dart:typed_data';

import 'package:solana/encoder.dart';
import 'package:solana/solana.dart';

import 'tensor_marketplace_constants.dart';

final Ed25519HDPublicKey _systemProgramId =
    Ed25519HDPublicKey.fromBase58(systemProgramAddress);
final Ed25519HDPublicKey _splTokenProgramId =
    Ed25519HDPublicKey.fromBase58(splTokenProgramAddress);
final Ed25519HDPublicKey _associatedTokenProgramId =
    Ed25519HDPublicKey.fromBase58(associatedTokenProgramAddress);
final Ed25519HDPublicKey _tokenMetadataProgramId =
    Ed25519HDPublicKey.fromBase58(tokenMetadataProgramAddress);
final Ed25519HDPublicKey _authorizationRulesProgramId =
    Ed25519HDPublicKey.fromBase58(authorizationRulesProgramAddress);

/// Derives the Tensor marketplace `list_state` PDA.
/// Seeds: [b"list_state", mint].
Future<Ed25519HDPublicKey> findListStatePda({
  required Ed25519HDPublicKey mint,
  Ed25519HDPublicKey? programId,
}) async {
  return Ed25519HDPublicKey.findProgramAddress(
    seeds: <List<int>>[utf8.encode('list_state'), mint.bytes],
    programId: programId ?? tensorMarketplaceDevnetProgramId(),
  );
}

/// Derives the SnowChat vault PDA — destination for protocol fees + broker
/// fallbacks. Owned by our marketplace program (replaces Tensor's fee_vault
/// which was owned by Tensor's fees program). Seeds: [b"snowchat_vault"].
/// Single-vault design: our trade volume is orders of magnitude below the
/// PDA write-contention limit that justified Tensor's 256-shard scheme.
Future<Ed25519HDPublicKey> findSnowchatVaultPda({
  Ed25519HDPublicKey? programId,
}) async {
  return Ed25519HDPublicKey.findProgramAddress(
    seeds: <List<int>>[utf8.encode(snowchatVaultSeed)],
    programId: programId ?? tensorMarketplaceDevnetProgramId(),
  );
}

/// Derives the Metaplex master-edition PDA for a mint.
/// Seeds: ["metadata", token_metadata_program, mint, "edition"].
Future<Ed25519HDPublicKey> findEditionPda({
  required Ed25519HDPublicKey mint,
}) async {
  return Ed25519HDPublicKey.findProgramAddress(
    seeds: <List<int>>[
      utf8.encode('metadata'),
      _tokenMetadataProgramId.bytes,
      mint.bytes,
      utf8.encode('edition'),
    ],
    programId: _tokenMetadataProgramId,
  );
}

/// Standard SPL associated-token-account derivation.
/// Seeds: [owner, token_program_id, mint]. Program: SPL Associated Token.
Future<Ed25519HDPublicKey> findAssociatedTokenAddress({
  required Ed25519HDPublicKey owner,
  required Ed25519HDPublicKey mint,
  Ed25519HDPublicKey? tokenProgram,
}) async {
  final tp = tokenProgram ?? _splTokenProgramId;
  return Ed25519HDPublicKey.findProgramAddress(
    seeds: <List<int>>[owner.bytes, tp.bytes, mint.bytes],
    programId: _associatedTokenProgramId,
  );
}

/// Optional-account convention: when an Anchor instruction account is
/// declared `Option<...>`, absent maps to the program ID itself (standard
/// codama/Anchor 0.29 pattern — the factory emits the program address when
/// the caller leaves the slot null).
Ed25519HDPublicKey _absentOptional(Ed25519HDPublicKey programId) => programId;

/// Encode a BigInt as 8-byte little-endian u64.
Uint8List _encodeU64Le(BigInt value) {
  if (value < BigInt.zero) {
    throw ArgumentError.value(value, 'value', 'u64 encoding requires >= 0');
  }
  if (value >= (BigInt.one << 64)) {
    throw ArgumentError.value(value, 'value', 'u64 encoding overflow');
  }
  final out = Uint8List(8);
  final bd = ByteData.sublistView(out);
  final lo = (value & BigInt.from(0xFFFFFFFF)).toInt();
  final hi = (value >> 32).toInt();
  bd.setUint32(0, lo, Endian.little);
  bd.setUint32(4, hi, Endian.little);
  return out;
}

/// Build the `list_legacy` instruction. Owner lists [mint] at [amount]
/// lamports. Currency defaults to SOL (None); SPL currencies use
/// `buy_spl` / `list_spl` flows not exposed here.
///
/// Account order (Anchor 0.29 optional convention — absent = program ID):
///   0.  owner (signer, readonly)
///   1.  owner_ta (writable)          — source ATA of the listed NFT
///   2.  list_state (writable)        — PDA, will be init'd
///   3.  list_ta (writable)           — ATA of list_state (init_if_needed)
///   4.  mint (readonly)
///   5.  payer (signer, writable)     — pays rent; defaults to owner
///   6.  token_program
///   7.  associated_token_program
///   8.  marketplace_program
///   9.  system_program
///   10. metadata (writable)
///   11. edition (readonly)
///   12. owner_token_record (optional, writable)
///   13. list_token_record (optional, writable)
///   14. authorization_rules (optional, readonly)
///   15. authorization_rules_program (optional, readonly)
///   16. token_metadata_program (optional, readonly)
///   17. sysvar_instructions (optional, readonly)
///   18. cosigner (optional, signer)
Future<Instruction> buildListLegacyInstruction({
  required Ed25519HDPublicKey owner,
  required Ed25519HDPublicKey mint,
  required BigInt amount,
  Ed25519HDPublicKey? payer,
  Ed25519HDPublicKey? programId,
}) async {
  final p = programId ?? tensorMarketplaceDevnetProgramId();
  final pay = payer ?? owner;
  final ownerTa = await findAssociatedTokenAddress(owner: owner, mint: mint);
  final listState = await findListStatePda(mint: mint, programId: p);
  final listTa =
      await findAssociatedTokenAddress(owner: listState, mint: mint);
  final metadata = await _findMetaplexMetadataPda(mint);
  final edition = await findEditionPda(mint: mint);
  final absent = _absentOptional(p);

  // Instruction data:
  //   [disc(8)] [amount(u64)] [expireInSec None(1)] [currency None(1)]
  //   [privateTaker None(1)] [makerBroker None(1)] [authorizationData None(1)]
  final data = Uint8List(8 + 8 + 5);
  data.setRange(0, 8, listLegacyIxDiscriminator);
  data.setRange(8, 16, _encodeU64Le(amount));
  // Remaining 5 bytes are Option-None (0x00) discriminators; the buffer is
  // already zero-initialised so we leave it.

  return Instruction(
    programId: p,
    accounts: <AccountMeta>[
      AccountMeta.readonly(pubKey: owner, isSigner: true),
      AccountMeta.writeable(pubKey: ownerTa, isSigner: false),
      AccountMeta.writeable(pubKey: listState, isSigner: false),
      AccountMeta.writeable(pubKey: listTa, isSigner: false),
      AccountMeta.readonly(pubKey: mint, isSigner: false),
      AccountMeta.writeable(pubKey: pay, isSigner: true),
      AccountMeta.readonly(pubKey: _splTokenProgramId, isSigner: false),
      AccountMeta.readonly(pubKey: _associatedTokenProgramId, isSigner: false),
      AccountMeta.readonly(pubKey: p, isSigner: false),
      AccountMeta.readonly(pubKey: _systemProgramId, isSigner: false),
      AccountMeta.writeable(pubKey: metadata, isSigner: false),
      AccountMeta.readonly(pubKey: edition, isSigner: false),
      // Optionals: owner_token_record, list_token_record, auth_rules,
      // auth_rules_program, token_metadata_program, sysvar_instructions,
      // cosigner — absent = program id.
      AccountMeta.writeable(pubKey: absent, isSigner: false),
      AccountMeta.writeable(pubKey: absent, isSigner: false),
      AccountMeta.readonly(pubKey: absent, isSigner: false),
      AccountMeta.readonly(pubKey: _authorizationRulesProgramId, isSigner: false),
      AccountMeta.readonly(pubKey: _tokenMetadataProgramId, isSigner: false),
      AccountMeta.readonly(pubKey: absent, isSigner: false),
      AccountMeta.readonly(pubKey: absent, isSigner: false),
    ],
    data: ByteArray(data),
  );
}

/// Build the `buy_legacy` instruction, optionally including the community
/// accounts so the 50/50 split applies. [maxAmount] is the buyer's price
/// ceiling in lamports (listing amount + accepted royalty overhead).
///
/// Supplying [communityRegistration] + [leaderWallet] together enables the
/// community share; omitting both preserves upstream Tensor behavior.
///
/// Account order (mirrors codama generated buyLegacy.ts, with fee_vault
/// swapped for snowchat_vault — SnowChat-owned PDA, see
/// community/snowchat_vault.rs in the Anchor program):
///   0.  snowchat_vault (writable)
///   1.  buyer (readonly)                     — asset recipient; defaults to payer
///   2.  buyer_ta (writable)                  — ATA of buyer
///   3.  list_ta (writable)                   — ATA of list_state
///   4.  list_state (writable)
///   5.  mint (readonly)
///   6.  owner (writable)                     — seller
///   7.  payer (writable signer)              — lamport payer
///   8.  taker_broker (optional, writable)
///   9.  maker_broker (optional, writable)
///   10. rent_destination (writable)          — defaults to owner
///   11. token_program
///   12. associated_token_program
///   13. marketplace_program
///   14. system_program
///   15. metadata (writable)
///   16. edition (readonly)
///   17. buyer_token_record (optional)
///   18. list_token_record (optional)
///   19. authorization_rules (optional)
///   20. authorization_rules_program
///   21. token_metadata_program
///   22. sysvar_instructions (optional)
///   23. cosigner (optional signer)
///   24. community_registration (optional, writable)
///   25. leader_wallet (optional, writable)
/// + creators as remaining_accounts (1..N)
Future<Instruction> buildBuyLegacyInstruction({
  required Ed25519HDPublicKey mint,
  required Ed25519HDPublicKey owner,
  required Ed25519HDPublicKey payer,
  required BigInt maxAmount,
  Ed25519HDPublicKey? buyer,
  Ed25519HDPublicKey? rentDestination,
  Ed25519HDPublicKey? communityRegistration,
  Ed25519HDPublicKey? leaderWallet,
  Ed25519HDPublicKey? takerBroker,
  Ed25519HDPublicKey? makerBroker,
  Ed25519HDPublicKey? cosigner,
  List<Ed25519HDPublicKey> creators = const <Ed25519HDPublicKey>[],
  Ed25519HDPublicKey? programId,
}) async {
  final p = programId ?? tensorMarketplaceDevnetProgramId();
  final buy = buyer ?? payer;
  final rentTo = rentDestination ?? owner;
  final listState = await findListStatePda(mint: mint, programId: p);
  final snowchatVault = await findSnowchatVaultPda(programId: p);
  final buyerTa = await findAssociatedTokenAddress(owner: buy, mint: mint);
  final listTa =
      await findAssociatedTokenAddress(owner: listState, mint: mint);
  final metadata = await _findMetaplexMetadataPda(mint);
  final edition = await findEditionPda(mint: mint);
  final absent = _absentOptional(p);

  if ((communityRegistration == null) != (leaderWallet == null)) {
    throw ArgumentError(
      'communityRegistration and leaderWallet must both be provided or both absent',
    );
  }

  // data: [disc(8)] [maxAmount(u64)] [optionalRoyaltyPct None(1)]
  //       [authorizationData None(1)]
  final data = Uint8List(8 + 8 + 1 + 1);
  data.setRange(0, 8, buyLegacyIxDiscriminator);
  data.setRange(8, 16, _encodeU64Le(maxAmount));
  // bytes 16 and 17 stay 0 (Option<None>).

  final accounts = <AccountMeta>[
    AccountMeta.writeable(pubKey: snowchatVault, isSigner: false),
    AccountMeta.readonly(pubKey: buy, isSigner: false),
    AccountMeta.writeable(pubKey: buyerTa, isSigner: false),
    AccountMeta.writeable(pubKey: listTa, isSigner: false),
    AccountMeta.writeable(pubKey: listState, isSigner: false),
    AccountMeta.readonly(pubKey: mint, isSigner: false),
    AccountMeta.writeable(pubKey: owner, isSigner: false),
    AccountMeta.writeable(pubKey: payer, isSigner: true),
    AccountMeta.writeable(pubKey: takerBroker ?? absent, isSigner: false),
    AccountMeta.writeable(pubKey: makerBroker ?? absent, isSigner: false),
    AccountMeta.writeable(pubKey: rentTo, isSigner: false),
    AccountMeta.readonly(pubKey: _splTokenProgramId, isSigner: false),
    AccountMeta.readonly(pubKey: _associatedTokenProgramId, isSigner: false),
    AccountMeta.readonly(pubKey: p, isSigner: false),
    AccountMeta.readonly(pubKey: _systemProgramId, isSigner: false),
    AccountMeta.writeable(pubKey: metadata, isSigner: false),
    AccountMeta.readonly(pubKey: edition, isSigner: false),
    // buyer_token_record, list_token_record (optional, writable — pNFT only)
    AccountMeta.writeable(pubKey: absent, isSigner: false),
    AccountMeta.writeable(pubKey: absent, isSigner: false),
    // authorization_rules (optional readonly — pNFT only)
    AccountMeta.readonly(pubKey: absent, isSigner: false),
    // authorization_rules_program + token_metadata_program — fixed
    AccountMeta.readonly(pubKey: _authorizationRulesProgramId, isSigner: false),
    AccountMeta.readonly(pubKey: _tokenMetadataProgramId, isSigner: false),
    // sysvar_instructions (optional — pNFT)
    AccountMeta.readonly(pubKey: absent, isSigner: false),
    // cosigner (optional signer)
    cosigner != null
        ? AccountMeta.readonly(pubKey: cosigner, isSigner: true)
        : AccountMeta.readonly(pubKey: absent, isSigner: false),
    // community_registration + leader_wallet (both optional, writable)
    AccountMeta.writeable(
      pubKey: communityRegistration ?? absent,
      isSigner: false,
    ),
    AccountMeta.writeable(
      pubKey: leaderWallet ?? absent,
      isSigner: false,
    ),
    // creators[] as remaining accounts (writable so they can receive royalties)
    for (final c in creators)
      AccountMeta.writeable(pubKey: c, isSigner: false),
  ];

  return Instruction(
    programId: p,
    accounts: accounts,
    data: ByteArray(data),
  );
}

/// Build the `delist_legacy` instruction. Seller cancels their listing —
/// the NFT returns from `list_state` ATA back to the owner's ATA; the
/// `list_state` PDA is closed and rent is refunded to the rent_destination
/// (defaults to owner).
///
/// Account order (codama delistLegacy.ts):
///   0.  owner (signer, writable)
///   1.  owner_ta (writable) — destination ATA for the NFT
///   2.  list_state (writable) — PDA being closed
///   3.  list_ta (writable) — source ATA (owned by list_state)
///   4.  mint (readonly)
///   5.  rent_destination (writable) — defaults to owner
///   6.  payer (signer, writable)
///   7.  token_program
///   8.  associated_token_program
///   9.  marketplace_program
///   10. system_program
///   11. metadata (writable)
///   12. edition (readonly)
///   13. owner_token_record (optional, writable)
///   14. list_token_record (optional, writable)
///   15. authorization_rules (optional)
///   16. authorization_rules_program
///   17. token_metadata_program
///   18. sysvar_instructions (optional)
Future<Instruction> buildDelistLegacyInstruction({
  required Ed25519HDPublicKey owner,
  required Ed25519HDPublicKey mint,
  Ed25519HDPublicKey? rentDestination,
  Ed25519HDPublicKey? programId,
}) async {
  final p = programId ?? tensorMarketplaceDevnetProgramId();
  final ownerTa = await findAssociatedTokenAddress(owner: owner, mint: mint);
  final listState = await findListStatePda(mint: mint, programId: p);
  final listTa =
      await findAssociatedTokenAddress(owner: listState, mint: mint);
  final metadata = await _findMetaplexMetadataPda(mint);
  final edition = await findEditionPda(mint: mint);
  final rentTo = rentDestination ?? owner;
  final absent = _absentOptional(p);

  // Data: [disc(8)] [authorizationData Option<None>=(1 byte, 0x00)]
  final data = Uint8List(8 + 1);
  data.setRange(0, 8, delistLegacyIxDiscriminator);
  // byte 8 stays 0 (None).

  return Instruction(
    programId: p,
    accounts: <AccountMeta>[
      AccountMeta.writeable(pubKey: owner, isSigner: true),
      AccountMeta.writeable(pubKey: ownerTa, isSigner: false),
      AccountMeta.writeable(pubKey: listState, isSigner: false),
      AccountMeta.writeable(pubKey: listTa, isSigner: false),
      AccountMeta.readonly(pubKey: mint, isSigner: false),
      AccountMeta.writeable(pubKey: rentTo, isSigner: false),
      AccountMeta.writeable(pubKey: owner, isSigner: true), // payer = owner
      AccountMeta.readonly(pubKey: _splTokenProgramId, isSigner: false),
      AccountMeta.readonly(pubKey: _associatedTokenProgramId, isSigner: false),
      AccountMeta.readonly(pubKey: p, isSigner: false),
      AccountMeta.readonly(pubKey: _systemProgramId, isSigner: false),
      AccountMeta.writeable(pubKey: metadata, isSigner: false),
      AccountMeta.readonly(pubKey: edition, isSigner: false),
      // owner_token_record / list_token_record optional (pNFT only)
      AccountMeta.writeable(pubKey: absent, isSigner: false),
      AccountMeta.writeable(pubKey: absent, isSigner: false),
      // authorization_rules optional
      AccountMeta.readonly(pubKey: absent, isSigner: false),
      AccountMeta.readonly(pubKey: _authorizationRulesProgramId, isSigner: false),
      AccountMeta.readonly(pubKey: _tokenMetadataProgramId, isSigner: false),
      // sysvar_instructions optional
      AccountMeta.readonly(pubKey: absent, isSigner: false),
    ],
    data: ByteArray(data),
  );
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

Future<Ed25519HDPublicKey> _findMetaplexMetadataPda(
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
