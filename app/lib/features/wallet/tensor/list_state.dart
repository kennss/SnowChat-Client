/// @file        list_state.dart
/// @description Dart parser for Tensor fork `ListState` account — the
///              on-chain PDA that represents an active NFT listing. Used
///              by `marketplaceListingsProvider` to read on-chain listings
///              via `getProgramAccounts`, replacing the server escrow DB.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-24
/// @lastUpdated 2026-04-24
///
/// @functions
///  - ListState.fromBytes(bytes): parse raw account data
///  - ListState.isOwnedBySol: currency is None (SOL)

import 'dart:typed_data';

import 'package:solana/solana.dart';

/// Anchor account discriminator for `ListState`. First 8 bytes of every
/// ListState account. Used both for `getProgramAccounts` memcmp filter
/// and for defensive parsing (reject accounts that aren't ListState).
const List<int> listStateAccountDiscriminator = <int>[
  78, 242, 89, 138, 161, 221, 176, 75,
];

/// Borsh layout of `program/src/state.rs#ListState`:
/// ```
/// 0..8     discriminator
/// 8..9     version (u8)
/// 9..10    bump (u8)
/// 10..42   owner (Pubkey)
/// 42..74   asset_id (mint) (Pubkey)
/// 74..82   amount (u64 LE)
/// 82..N    currency Option<Pubkey>       (1 byte tag, then 32 if Some)
/// +8       expiry (i64 LE)
/// +N       private_taker Option<Pubkey>  (1 + 32 if Some)
/// +N       maker_broker Option<Pubkey>   (1 + 32 if Some)
/// +32      rent_payer (Pubkey)
/// +32      cosigner   (Pubkey)
/// +64      _reserved1
/// ```
class ListState {
  ListState({
    required this.version,
    required this.bump,
    required this.owner,
    required this.assetId,
    required this.amount,
    required this.currency,
    required this.expiry,
    required this.privateTaker,
    required this.makerBroker,
    required this.rentPayer,
    required this.cosigner,
  });

  final int version;
  final int bump;
  final Ed25519HDPublicKey owner;
  final Ed25519HDPublicKey assetId;
  final BigInt amount;
  final Ed25519HDPublicKey? currency;
  final int expiry;
  final Ed25519HDPublicKey? privateTaker;
  final Ed25519HDPublicKey? makerBroker;
  final Ed25519HDPublicKey rentPayer;
  final Ed25519HDPublicKey cosigner;

  bool get isSolListing => currency == null;

  /// Reject non-SOL listings — we only surface SOL-currency listings in the
  /// initial Phase C discovery feed. SPL currency listings are ignored at
  /// the parser level (caller can check via [isSolListing] before).
  bool get isExpired {
    if (expiry <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return expiry < now;
  }

  static ListState? fromBytes(Uint8List raw) {
    if (raw.length < 82) return null;
    // Discriminator check — defensive against get_program_accounts noise.
    for (var i = 0; i < 8; i++) {
      if (raw[i] != listStateAccountDiscriminator[i]) return null;
    }

    final bytes = ByteData.sublistView(raw);
    final version = raw[8];
    final bump = raw[9];
    final owner = Ed25519HDPublicKey(raw.sublist(10, 42));
    final assetId = Ed25519HDPublicKey(raw.sublist(42, 74));
    final amount = _readU64(bytes, 74);

    var cursor = 82;
    final (currency, afterCurrency) = _readOptionalPubkey(raw, cursor);
    cursor = afterCurrency;

    if (cursor + 8 > raw.length) return null;
    final expiry = bytes.getInt64(cursor, Endian.little);
    cursor += 8;

    final (privateTaker, afterPrivate) = _readOptionalPubkey(raw, cursor);
    cursor = afterPrivate;

    final (makerBroker, afterMaker) = _readOptionalPubkey(raw, cursor);
    cursor = afterMaker;

    if (cursor + 32 + 32 > raw.length) return null;
    final rentPayer = Ed25519HDPublicKey(raw.sublist(cursor, cursor + 32));
    final cosigner = Ed25519HDPublicKey(
      raw.sublist(cursor + 32, cursor + 64),
    );

    return ListState(
      version: version,
      bump: bump,
      owner: owner,
      assetId: assetId,
      amount: amount,
      currency: currency,
      expiry: expiry,
      privateTaker: privateTaker,
      makerBroker: makerBroker,
      rentPayer: rentPayer,
      cosigner: cosigner,
    );
  }

  static (Ed25519HDPublicKey?, int) _readOptionalPubkey(
    Uint8List raw,
    int offset,
  ) {
    if (offset >= raw.length) return (null, offset);
    final tag = raw[offset];
    if (tag == 0) return (null, offset + 1);
    if (offset + 1 + 32 > raw.length) return (null, raw.length);
    return (
      Ed25519HDPublicKey(raw.sublist(offset + 1, offset + 33)),
      offset + 33,
    );
  }

  static BigInt _readU64(ByteData bd, int offset) {
    final lo = bd.getUint32(offset, Endian.little);
    final hi = bd.getUint32(offset + 4, Endian.little);
    return (BigInt.from(hi) << 32) | BigInt.from(lo);
  }
}
