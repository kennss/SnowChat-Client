/// @file        fee_split_preview.dart
/// @description Client-side mirror of the on-chain Tensor + community fee
///              split math. Lets the UI render "you will pay X, leader will
///              receive Y" previews *before* the user signs, and lets
///              integration tests assert lamport-exact expectations.
///              Mirrors the logic in `program/src/community/fee_split.rs`
///              + Tensor `calc_fees`.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-24
/// @lastUpdated 2026-04-24
///
/// @functions
///  - computeExpectedSplit(listingPrice, {hasCommunity}): full breakdown
///  - expectedProtocolFee(listingPrice): protocol fee after broker cut
///  - expectedLeaderShare(protocolFee): community leader portion (with dust
///    redirect rule applied)

import 'tensor_marketplace_constants.dart';

/// Breakdown of how a `listingPrice` is split among Tensor, community leader,
/// brokers, and the seller. All amounts are BigInt lamports.
///
/// The values here mirror what `apply_community_share` + `calc_fees` compute
/// on-chain given the same inputs. Use this to render a fee preview before
/// signing a buy tx.
class CommunitySplitPreview {
  const CommunitySplitPreview({
    required this.listingPrice,
    required this.totalTakerFee,
    required this.brokerFeeTotal,
    required this.protocolFee,
    required this.leaderShare,
    required this.platformShare,
    required this.dustRedirected,
  });

  /// Listing amount in lamports (equals what the seller receives before
  /// royalties — royalties are computed separately by Tensor).
  final BigInt listingPrice;

  /// `listingPrice * takerFeeBps / 10_000`. Total fee the buyer pays *on top
  /// of* the listing price.
  final BigInt totalTakerFee;

  /// `totalTakerFee * brokerFeePct / 100`. Portion that flows to maker/taker
  /// brokers (or to fee_vault if no brokers provided).
  final BigInt brokerFeeTotal;

  /// `totalTakerFee - brokerFeeTotal`. Portion that normally goes to the
  /// platform vault; split 50/50 with the community leader when a
  /// registration is supplied.
  final BigInt protocolFee;

  /// Community leader portion of the protocol_fee. Zero when no community
  /// registration is supplied OR when the raw share would be below
  /// [minLeaderShareLamports] (dust redirect).
  final BigInt leaderShare;

  /// Platform vault portion. Equals `protocolFee` when no community,
  /// otherwise `protocolFee - leaderShare`. If dust redirect fires,
  /// the entire protocol_fee remains here.
  final BigInt platformShare;

  /// True when [hasCommunity] was requested but the computed leader_share
  /// fell below [minLeaderShareLamports] and was merged into the platform
  /// vault. UI can surface this explicitly so leaders understand why they
  /// did not receive a share on a tiny trade.
  final bool dustRedirected;

  /// The buyer's total outgoing lamports (listing price + taker fee,
  /// before royalty creators_fee is added).
  BigInt get buyerOutgoingBeforeRoyalty => listingPrice + totalTakerFee;

  @override
  String toString() => 'CommunitySplitPreview('
      'listing=$listingPrice, '
      'totalTakerFee=$totalTakerFee, '
      'protocolFee=$protocolFee, '
      'leaderShare=$leaderShare, '
      'platformShare=$platformShare, '
      'dust=$dustRedirected)';
}

/// Compute Tensor's `protocol_fee` portion for a given `listingPrice`.
///
/// `listingPrice * takerFeeBps / 10_000 - (total * brokerFeePct / 100)`
/// matches Tensor's on-chain `calc_fees` result for the protocol_fee
/// field (the portion that is neither broker nor creator royalty).
BigInt expectedProtocolFee(BigInt listingPrice) {
  if (listingPrice < BigInt.zero) {
    throw ArgumentError.value(
      listingPrice,
      'listingPrice',
      'must be non-negative',
    );
  }
  final totalFee =
      (listingPrice * BigInt.from(takerFeeBps)) ~/ BigInt.from(10_000);
  final brokerFee =
      (totalFee * BigInt.from(brokerFeePct)) ~/ BigInt.from(100);
  return totalFee - brokerFee;
}

/// Compute the community leader's share of [protocolFee], applying the
/// on-chain dust redirect rule. Returns a `(leaderShare, dust)` tuple: when
/// `dust` is true the [leaderShare] is zero and the caller must route the
/// full protocol_fee to the platform instead.
({BigInt leaderShare, bool dustRedirected}) expectedLeaderShare(
  BigInt protocolFee,
) {
  if (protocolFee < BigInt.zero) {
    throw ArgumentError.value(
      protocolFee,
      'protocolFee',
      'must be non-negative',
    );
  }
  final rawShare =
      (protocolFee * BigInt.from(communityLeaderShareBps)) ~/
          BigInt.from(10_000);
  if (rawShare < BigInt.from(minLeaderShareLamports)) {
    return (leaderShare: BigInt.zero, dustRedirected: true);
  }
  return (leaderShare: rawShare, dustRedirected: false);
}

/// Full fee breakdown for a listing. Pass [hasCommunity] = true when the
/// buyer will include `communityRegistration` + `leaderWallet` in their
/// buy tx.
CommunitySplitPreview computeExpectedSplit({
  required BigInt listingPrice,
  required bool hasCommunity,
}) {
  if (listingPrice < BigInt.zero) {
    throw ArgumentError.value(
      listingPrice,
      'listingPrice',
      'must be non-negative',
    );
  }
  final totalFee =
      (listingPrice * BigInt.from(takerFeeBps)) ~/ BigInt.from(10_000);
  final brokerFee =
      (totalFee * BigInt.from(brokerFeePct)) ~/ BigInt.from(100);
  final protocolFee = totalFee - brokerFee;

  if (!hasCommunity) {
    return CommunitySplitPreview(
      listingPrice: listingPrice,
      totalTakerFee: totalFee,
      brokerFeeTotal: brokerFee,
      protocolFee: protocolFee,
      leaderShare: BigInt.zero,
      platformShare: protocolFee,
      dustRedirected: false,
    );
  }

  final split = expectedLeaderShare(protocolFee);
  final leaderShare = split.leaderShare;
  final platformShare = protocolFee - leaderShare;
  return CommunitySplitPreview(
    listingPrice: listingPrice,
    totalTakerFee: totalFee,
    brokerFeeTotal: brokerFee,
    protocolFee: protocolFee,
    leaderShare: leaderShare,
    platformShare: platformShare,
    dustRedirected: split.dustRedirected,
  );
}
