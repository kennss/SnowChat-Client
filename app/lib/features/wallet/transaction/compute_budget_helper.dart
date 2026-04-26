/// @file        compute_budget_helper.dart
/// @description ComputeBudget instruction builder — setComputeUnitLimit +
///              setComputeUnitPrice helpers for setting Solana priority fee.
///              Phase 6.1 §2.1 (Phantom parity). BigInt only.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - PriorityLevel: 3 levels — Slow / Normal / Fast
///  - ComputeBudgetHelper.buildPriorityInstructions(): build CU limit + price instruction pair
///  - ComputeBudgetHelper.MAX_PRIORITY_FEE_LAMPORTS: absolute cap on per-tx priority fee
///  - ComputeBudgetHelper.clampPriorityFee(): microLamports clamp helper
library;

import 'package:solana/encoder.dart';
import 'package:solana/solana.dart';

/// Priority levels the user can choose on the send screen.
enum PriorityLevel { slow, normal, fast }

/// ComputeBudget program instruction builder.
///
/// Solana priority fee is the combination of two instructions:
///   1. setComputeUnitLimit(units) — CU ceiling the transaction may use
///   2. setComputeUnitPrice(microLamportsPerCu) — microLamports paid per CU
///
/// Total priority fee = unitLimit × microLamportsPerCu / 1_000_000 (lamports).
///
/// **BigInt only**: every lamports/microLamports variable is BigInt. The
/// solana package's `setComputeUnitPrice` factory takes `int microLamports`,
/// so `.toInt()` is allowed only right at the call site (CLAUDE.md "package
/// API boundary exception").
class ComputeBudgetHelper {
  ComputeBudgetHelper._();

  /// Absolute cap on per-tx priority fee (Phase 6.1 §2.1).
  /// 0.001 SOL = 1_000_000 lamports.
  static final BigInt maxPriorityFeeLamports = BigInt.from(1000000);

  /// CU limit sufficient for typical SOL/SPL transfers (with safety margin).
  /// SystemProgram.transfer ~150 CU, TokenProgram.transfer ~4500 CU.
  /// Including ATA creation ~25,000 CU. Set to 200,000 CU with margin.
  static const int defaultUnitLimit = 200000;

  /// Combine the user-selected priority level with the network estimate
  /// (microLamports per CU) and produce the two ComputeBudget instructions.
  ///
  /// [estimatedMicroLamportsPerCu] is the recommended value computed by
  /// PriorityFeeEstimator (typically the 75th percentile of
  /// `getRecentPrioritizationFees`).
  ///
  /// The returned instructions must be placed before the other instructions.
  static List<Instruction> buildPriorityInstructions({
    required PriorityLevel level,
    required BigInt estimatedMicroLamportsPerCu,
    int unitLimit = defaultUnitLimit,
  }) {
    final priceMicro = _resolvePrice(level, estimatedMicroLamportsPerCu);
    final clamped = clampPriorityFee(
      microLamportsPerCu: priceMicro,
      unitLimit: unitLimit,
    );

    return <Instruction>[
      ComputeBudgetInstruction.setComputeUnitLimit(units: unitLimit),
      // solana package API boundary: BigInt → int conversion only here (CLAUDE.md)
      ComputeBudgetInstruction.setComputeUnitPrice(
        microLamports: clamped.toInt(),
      ),
    ];
  }

  /// microLamports per CU after applying the per-PriorityLevel multiplier.
  ///
  /// - slow:   estimate × 0.5 (min 1)
  /// - normal: estimate × 1
  /// - fast:   estimate × 2
  static BigInt _resolvePrice(
    PriorityLevel level,
    BigInt estimated,
  ) {
    if (estimated < BigInt.one) estimated = BigInt.one;
    switch (level) {
      case PriorityLevel.slow:
        final v = estimated ~/ BigInt.two;
        return v < BigInt.one ? BigInt.one : v;
      case PriorityLevel.normal:
        return estimated;
      case PriorityLevel.fast:
        return estimated * BigInt.two;
    }
  }

  /// microLamports per CU × unitLimit / 1_000_000 = total priority fee (lamports).
  /// Clamps the microLamports value when it exceeds the absolute cap.
  ///
  /// Returns: the microLamportsPerCu (BigInt) to apply.
  static BigInt clampPriorityFee({
    required BigInt microLamportsPerCu,
    required int unitLimit,
  }) {
    final unitLimitBig = BigInt.from(unitLimit);
    final million = BigInt.from(1000000);
    final totalLamports = (microLamportsPerCu * unitLimitBig) ~/ million;

    if (totalLamports <= maxPriorityFeeLamports) {
      return microLamportsPerCu;
    }

    // total = price * units / 1e6   →   price = max * 1e6 / units
    return (maxPriorityFeeLamports * million) ~/ unitLimitBig;
  }

  /// Compute total priority fee (lamports) from microLamports per CU + unit limit.
  static BigInt totalPriorityFeeLamports({
    required BigInt microLamportsPerCu,
    required int unitLimit,
  }) {
    return (microLamportsPerCu * BigInt.from(unitLimit)) ~/
        BigInt.from(1000000);
  }
}
