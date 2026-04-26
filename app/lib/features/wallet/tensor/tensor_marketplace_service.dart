/// @file        tensor_marketplace_service.dart
/// @description Dart binding for SnowChat Community Fee Share — Tensor fork.
///              Provides PDA derivation + instruction builders for the
///              `register_community_collection` and `revoke_community_collection`
///              entry points. `buy_legacy` + `take_bid_legacy` wrappers with
///              community accounts are deferred until the marketplace UI
///              flow is defined (Phase C).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-24
/// @lastUpdated 2026-04-24
///
/// @functions
///  - findCommunityRegistrationPda(collectionMint): derive the registration PDA.
///  - buildRegisterCommunityInstruction(...): Anchor instruction.
///  - buildRevokeCommunityInstruction(...): Anchor instruction.
///  - fetchCommunityRegistration(rpc, pda): RPC + deserialize.

import 'dart:convert';
import 'dart:typed_data';

import 'package:solana/dto.dart' hide Instruction;
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart';

import 'community_registration.dart';
import 'tensor_marketplace_constants.dart';

/// System Program address (always present for `init` accounts).
final Ed25519HDPublicKey _systemProgramId =
    Ed25519HDPublicKey.fromBase58('11111111111111111111111111111111');

/// Metaplex Token Metadata program ID (same on mainnet + devnet).
final Ed25519HDPublicKey _tokenMetadataProgramId =
    Ed25519HDPublicKey.fromBase58('metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s');

/// Derives the Metaplex metadata PDA for a given mint.
Future<Ed25519HDPublicKey> findMetaplexMetadataPda(
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

/// Derives the `CommunityRegistration` PDA for a given collection mint.
///
/// Seeds: [b"community_registration", collection_mint].
/// Program: tensorMarketplaceDevnetProgramAddress.
Future<Ed25519HDPublicKey> findCommunityRegistrationPda({
  required Ed25519HDPublicKey collectionMint,
  Ed25519HDPublicKey? programId,
}) async {
  return Ed25519HDPublicKey.findProgramAddress(
    seeds: <List<int>>[
      utf8.encode(communityRegistrationSeedPrefix),
      collectionMint.bytes,
    ],
    programId: programId ?? tensorMarketplaceDevnetProgramId(),
  );
}

/// Builds the `register_community_collection` instruction.
///
/// Account order (must match
/// program/src/community/register.rs#RegisterCommunityCollection):
///   0. registration          (writable, PDA)
///   1. collection_mint       (readonly)
///   2. metadata              (readonly, Metaplex metadata PDA for collection)
///   3. leader                (writable signer — pays rent + must be update_authority
///                             + verified creator on the collection metadata)
///   4. system_program        (readonly)
///
/// Args (Borsh):
///   leader_snowchat_id: [u8; 36]
///   channel_id:         [u8; 32]
Future<Instruction> buildRegisterCommunityInstruction({
  required Ed25519HDPublicKey registration,
  required Ed25519HDPublicKey collectionMint,
  required Ed25519HDPublicKey collectionMetadata,
  required Ed25519HDPublicKey leader,
  required Uint8List leaderSnowchatId,
  required Uint8List channelId,
  Ed25519HDPublicKey? programId,
}) async {
  _requireLength('leaderSnowchatId', leaderSnowchatId, snowchatIdBytes);
  _requireLength('channelId', channelId, channelIdBytes);

  final args = Uint8List(snowchatIdBytes + channelIdBytes);
  args.setRange(0, snowchatIdBytes, leaderSnowchatId);
  args.setRange(snowchatIdBytes, snowchatIdBytes + channelIdBytes, channelId);

  final data = Uint8List(8 + args.length);
  data.setRange(0, 8, registerCommunityCollectionIxDiscriminator);
  data.setRange(8, 8 + args.length, args);

  return Instruction(
    programId: programId ?? tensorMarketplaceDevnetProgramId(),
    accounts: <AccountMeta>[
      AccountMeta.writeable(pubKey: registration, isSigner: false),
      AccountMeta.readonly(pubKey: collectionMint, isSigner: false),
      AccountMeta.readonly(pubKey: collectionMetadata, isSigner: false),
      AccountMeta.writeable(pubKey: leader, isSigner: true),
      AccountMeta.readonly(pubKey: _systemProgramId, isSigner: false),
    ],
    data: ByteArray(data),
  );
}

/// Builds the `revoke_community_collection` instruction.
///
/// Account order (must match
/// program/src/community/revoke.rs#RevokeCommunityCollection):
///   0. registration          (writable, PDA — seeds-validated against its
///                             stored collection_mint on-chain)
///   1. leader                (readonly signer — must match registration.leader_wallet)
///
/// On-chain cooldown: `elapsed >= 30d` since `registered_at`. Early revoke
/// returns CommunityCooldownActive.
Instruction buildRevokeCommunityInstruction({
  required Ed25519HDPublicKey registration,
  required Ed25519HDPublicKey leader,
  Ed25519HDPublicKey? programId,
}) {
  final data =
      Uint8List.fromList(revokeCommunityCollectionIxDiscriminator);

  return Instruction(
    programId: programId ?? tensorMarketplaceDevnetProgramId(),
    accounts: <AccountMeta>[
      AccountMeta.writeable(pubKey: registration, isSigner: false),
      AccountMeta.readonly(pubKey: leader, isSigner: true),
    ],
    data: ByteArray(data),
  );
}

/// Fetches a `CommunityRegistration` PDA and deserializes its raw bytes.
/// Returns null if the PDA does not exist on-chain.
Future<CommunityRegistration?> fetchCommunityRegistration({
  required RpcClient rpc,
  required Ed25519HDPublicKey pda,
}) async {
  final response = await rpc.getAccountInfo(
    pda.toBase58(),
    encoding: Encoding.base64,
  );
  final account = response.value;
  if (account == null) return null;
  final accountData = account.data;
  if (accountData is! BinaryAccountData) {
    throw FormatException(
      'Unexpected account data type for CommunityRegistration: '
      '${accountData.runtimeType}',
    );
  }
  return CommunityRegistration.fromBytes(
    Uint8List.fromList(accountData.data),
  );
}

/// ---------- Internal helpers ----------

void _requireLength(String name, Uint8List bytes, int expected) {
  if (bytes.length != expected) {
    throw ArgumentError.value(
      bytes.length,
      name,
      'must be exactly $expected bytes, got ${bytes.length}',
    );
  }
}

/// Helper for consumer code — convert "snow" + 32 hex ASCII into a 36-byte
/// fixed buffer suitable for [buildRegisterCommunityInstruction].
Uint8List snowchatIdToBytes(String snowchatId) {
  _requireLength(
    'snowchatId',
    Uint8List.fromList(ascii.encode(snowchatId)),
    snowchatIdBytes,
  );
  return Uint8List.fromList(ascii.encode(snowchatId));
}

/// Helper for consumer code — left-pad or truncate to [channelIdBytes] (32).
Uint8List channelIdToBytes(String channelId) {
  final source = utf8.encode(channelId);
  if (source.length > channelIdBytes) {
    throw ArgumentError.value(
      source.length,
      'channelId',
      'must be at most $channelIdBytes bytes when UTF-8 encoded',
    );
  }
  final padded = Uint8List(channelIdBytes);
  padded.setRange(0, source.length, source);
  return padded;
}

/// Convenience bundle — what callers typically need to submit a register tx.
class RegisterCommunityPlan {
  const RegisterCommunityPlan({
    required this.registration,
    required this.collectionMetadata,
    required this.instruction,
  });

  final Ed25519HDPublicKey registration;
  final Ed25519HDPublicKey collectionMetadata;
  final Instruction instruction;
}

/// Derives the registration PDA + metaplex metadata PDA + builds the
/// register instruction in a single call. Keeps UI code concise.
Future<RegisterCommunityPlan> planRegisterCommunity({
  required Ed25519HDPublicKey collectionMint,
  required Ed25519HDPublicKey leader,
  required String snowchatId,
  required String channelId,
  Ed25519HDPublicKey? programId,
}) async {
  final pda = await findCommunityRegistrationPda(
    collectionMint: collectionMint,
    programId: programId,
  );
  final metadata = await findMetaplexMetadataPda(collectionMint);
  final ix = await buildRegisterCommunityInstruction(
    registration: pda,
    collectionMint: collectionMint,
    collectionMetadata: metadata,
    leader: leader,
    leaderSnowchatId: snowchatIdToBytes(snowchatId),
    channelId: channelIdToBytes(channelId),
    programId: programId,
  );
  return RegisterCommunityPlan(
    registration: pda,
    collectionMetadata: metadata,
    instruction: ix,
  );
}
