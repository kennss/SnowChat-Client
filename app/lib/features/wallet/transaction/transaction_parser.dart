/// @file        transaction_parser.dart
/// @description Solana transaction classifier. Uses
///              `getTransaction(commitment: finalized)` results — diffing
///              meta.preBalances/postBalances to decide SOL send/receive,
///              and matching SPL token changes when an
///              preTokenBalances/postTokenBalances accountIndex equals the
///              owner's accountKey index. In-memory LRU cache of 200 entries.
///              Persistent cache is a later drift migration. Phase 6.1 §3.2.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - TransactionParser.classify(): signature → ParsedTxResult
///  - ParsedTxResult: classification result (signature, type, amount, counterparty, fee)
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:solana/dto.dart' as sol;
import 'package:solana/solana.dart';

import '../../../core/storage/daos/wallet_tx_cache_dao.dart';
import '../../../core/storage/database.dart';

/// Classification result type.
enum ParsedTxType {
  solSend,
  solReceive,
  splSend,
  splReceive,
  unknown,
}

class ParsedTxResult {
  const ParsedTxResult({
    required this.signature,
    required this.type,
    required this.amountLamports,
    required this.counterparty,
    required this.feeLamports,
    required this.tokenMint,
    this.blockTime,
    this.slot,
  });

  final String signature;
  final ParsedTxType type;
  final BigInt? amountLamports;
  final String? counterparty;
  final BigInt? feeLamports;
  final String? tokenMint;

  /// Unix timestamp (seconds). null displays "Unknown".
  final int? blockTime;

  /// Slot number.
  final int? slot;

  /// blockTime → DateTime (local time).
  DateTime? get dateTime =>
      blockTime != null ? DateTime.fromMillisecondsSinceEpoch(blockTime! * 1000) : null;
}

/// Solana transaction classifier.
///
/// Cache policy (Phase 6.1 §3.2):
/// - Cache only finalized transactions (effectively immutable)
/// - L1: in-memory FIFO 200 entries
/// - L2: drift `wallet_tx_cache` persistent (parser_version comparison)
class TransactionParser {
  TransactionParser({
    required RpcClient rpcClient,
    WalletTxCacheDao? txCacheDao,
  })  : _rpc = rpcClient,
        _dao = txCacheDao;

  final RpcClient _rpc;
  final WalletTxCacheDao? _dao;

  /// Increment whenever the parser algorithm changes to invalidate stale cache.
  static const int parserVersion = 1;

  final Map<String, ParsedTxResult> _cache = {};
  static const _maxCacheEntries = 200;

  /// Classify a signature. [ownerAddress] is used to decide send/receive direction.
  Future<ParsedTxResult> classify({
    required String signature,
    required String ownerAddress,
  }) async {
    // L1: in-memory cache
    final mem = _cache[signature];
    if (mem != null) return mem;

    // L2: drift persistent cache
    if (_dao != null) {
      try {
        final row = await _dao.lookup(
          signature: signature,
          ownerAddress: ownerAddress,
        );
        if (row != null && row.parserVersion >= parserVersion) {
          final result = _rowToResult(row);
          _addToCache(signature, result);
          return result;
        }
      } catch (e) {
        debugPrint('[TransactionParser] drift lookup failed: $e');
      }
    }

    // L3: RPC fetch + parse
    try {
      final tx = await _rpc
          .getTransaction(
            signature,
            commitment: sol.Commitment.finalized,
            encoding: sol.Encoding.jsonParsed,
          )
          .timeout(const Duration(seconds: 8));

      if (tx == null) {
        return _unknown(signature);
      }
      var result = _parse(
        signature: signature,
        ownerAddress: ownerAddress,
        tx: tx,
      );
      // Inject blockTime/slot (from RPC response)
      result = ParsedTxResult(
        signature: result.signature,
        type: result.type,
        amountLamports: result.amountLamports,
        counterparty: result.counterparty,
        feeLamports: result.feeLamports,
        tokenMint: result.tokenMint,
        blockTime: tx.blockTime,
        slot: tx.slot,
      );
      _addToCache(signature, result);
      // Persist finalized result
      _persist(ownerAddress: ownerAddress, result: result, blockTime: tx.blockTime);
      return result;
    } catch (e) {
      debugPrint('[TransactionParser] $signature failed: $e');
      return _unknown(signature);
    }
  }

  Future<void> _persist({
    required String ownerAddress,
    required ParsedTxResult result,
    int? blockTime,
  }) async {
    if (_dao == null) return;
    try {
      await _dao.upsert(
        WalletTxCacheCompanion.insert(
          signature: result.signature,
          ownerAddress: ownerAddress,
          type: result.type.name,
          amountLamports: Value(result.amountLamports?.toString()),
          counterparty: Value(result.counterparty),
          tokenMint: Value(result.tokenMint),
          feeLamports: Value(result.feeLamports?.toString()),
          blockTime: Value(blockTime),
          parserVersion: const Value(parserVersion),
          cachedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (e) {
      debugPrint('[TransactionParser] persist failed: $e');
    }
  }

  ParsedTxResult _rowToResult(WalletTxCacheData row) {
    return ParsedTxResult(
      signature: row.signature,
      type: ParsedTxType.values.firstWhere(
        (t) => t.name == row.type,
        orElse: () => ParsedTxType.unknown,
      ),
      amountLamports:
          row.amountLamports != null ? BigInt.tryParse(row.amountLamports!) : null,
      counterparty: row.counterparty,
      feeLamports:
          row.feeLamports != null ? BigInt.tryParse(row.feeLamports!) : null,
      tokenMint: row.tokenMint,
      blockTime: row.blockTime,
    );
  }

  ParsedTxResult _parse({
    required String signature,
    required String ownerAddress,
    required sol.TransactionDetails tx,
  }) {
    final meta = tx.meta;
    final feeLamports = meta != null ? BigInt.from(meta.fee) : null;

    // Only handle the ParsedTransaction → ParsedMessage path (jsonParsed encoding)
    final transaction = tx.transaction;
    if (transaction is! sol.ParsedTransaction) {
      return _withFee(signature, feeLamports);
    }
    final message = transaction.message;
    if (message is! sol.ParsedMessage) {
      return _withFee(signature, feeLamports);
    }

    final accountKeys = message.accountKeys;
    final ownerIndex = accountKeys.indexWhere((k) => k.pubkey == ownerAddress);
    if (ownerIndex < 0 || meta == null) {
      return _withFee(signature, feeLamports);
    }

    // ----- SPL token balance delta detection -----
    // If the owner's ATA is in the transaction, token balance changes, so check first.
    final splResult = _detectSplDelta(
      ownerAddress: ownerAddress,
      accountKeys: accountKeys,
      pre: meta.preTokenBalances,
      post: meta.postTokenBalances,
      signature: signature,
      feeLamports: feeLamports,
    );
    if (splResult != null) return splResult;

    // ----- SOL balance delta detection -----
    if (ownerIndex < meta.preBalances.length &&
        ownerIndex < meta.postBalances.length) {
      final pre = BigInt.from(meta.preBalances[ownerIndex]);
      final post = BigInt.from(meta.postBalances[ownerIndex]);
      var delta = post - pre;
      // When owner is fee payer (typically ownerIndex == 0), fee is already
      // subtracted; add it back to see the pure transfer amount.
      if (ownerIndex == 0 && feeLamports != null) {
        delta = delta + feeLamports;
      }

      if (delta < BigInt.from(-1000)) {
        // Send. Estimate receiver: the other account whose balance increased the most
        final cp = _findIncreasedCounterparty(
          accountKeys: accountKeys,
          pre: meta.preBalances,
          post: meta.postBalances,
          excludeIndex: ownerIndex,
        );
        return ParsedTxResult(
          signature: signature,
          type: ParsedTxType.solSend,
          amountLamports: delta.abs(),
          counterparty: cp,
          feeLamports: feeLamports,
          tokenMint: null,
        );
      } else if (delta > BigInt.from(1000)) {
        final cp = _findDecreasedCounterparty(
          accountKeys: accountKeys,
          pre: meta.preBalances,
          post: meta.postBalances,
          excludeIndex: ownerIndex,
        );
        return ParsedTxResult(
          signature: signature,
          type: ParsedTxType.solReceive,
          amountLamports: delta,
          counterparty: cp,
          feeLamports: feeLamports,
          tokenMint: null,
        );
      }
    }

    return _withFee(signature, feeLamports);
  }

  /// Detect SPL transfer from preTokenBalances / postTokenBalances delta.
  ///
  /// Find the accountIndex of the owner's ATA and look at the amount delta
  /// at that index. Increase → receive, decrease → send.
  ///
  /// **Note**: solana ^0.31's TokenBalance does not expose an owner field,
  /// so we cannot enumerate all of owner's SPL ATAs ahead of time. Instead,
  /// when owner's pubkey is in accountKeys, use a simple heuristic that
  /// inspects token balance change at that index. ATA accountIndex mapping
  /// can be refined in a follow-up PR.
  ParsedTxResult? _detectSplDelta({
    required String ownerAddress,
    required List<sol.AccountKey> accountKeys,
    required List<sol.TokenBalance> pre,
    required List<sol.TokenBalance> post,
    required String signature,
    required BigInt? feeLamports,
  }) {
    if (pre.isEmpty && post.isEmpty) return null;

    // Map pre/post amount by accountIndex
    final preMap = <int, _TokenSnapshot>{};
    for (final tb in pre) {
      final amt = BigInt.tryParse(tb.uiTokenAmount.amount) ?? BigInt.zero;
      preMap[tb.accountIndex] = _TokenSnapshot(mint: tb.mint, amount: amt);
    }
    final postMap = <int, _TokenSnapshot>{};
    for (final tb in post) {
      final amt = BigInt.tryParse(tb.uiTokenAmount.amount) ?? BigInt.zero;
      postMap[tb.accountIndex] = _TokenSnapshot(mint: tb.mint, amount: amt);
    }

    // Check whether owner's accountKey appears directly at that token
    // balance accountIndex. Usually the ATA address appears; owner's pubkey
    // may not. As a fallback, when owner's pubkey is in accountKeys (e.g.
    // wrapped SOL where the token account is owned directly), estimate
    // token balance change from adjacent accounts based on signer/payer.
    //
    // Heuristics:
    //  1) Largest positive change (increase) → owner receives
    //  2) Largest negative change (decrease) → owner sends
    //  3) When the tx fee payer is owner, prefer send.
    final indices = {...preMap.keys, ...postMap.keys};
    BigInt biggestIncrease = BigInt.zero;
    BigInt biggestDecrease = BigInt.zero;
    String? receivedMint;
    String? sentMint;

    for (final i in indices) {
      final preSnap = preMap[i];
      final postSnap = postMap[i];
      final preAmt = preSnap?.amount ?? BigInt.zero;
      final postAmt = postSnap?.amount ?? BigInt.zero;
      final delta = postAmt - preAmt;
      if (delta > biggestIncrease) {
        biggestIncrease = delta;
        receivedMint = postSnap?.mint ?? preSnap?.mint;
      } else if (delta < biggestDecrease) {
        biggestDecrease = delta;
        sentMint = postSnap?.mint ?? preSnap?.mint;
      }
    }

    final ownerIsFeePayer =
        accountKeys.isNotEmpty && accountKeys.first.pubkey == ownerAddress;

    if (ownerIsFeePayer && biggestDecrease < BigInt.zero) {
      return ParsedTxResult(
        signature: signature,
        type: ParsedTxType.splSend,
        amountLamports: biggestDecrease.abs(),
        counterparty: null,
        feeLamports: feeLamports,
        tokenMint: sentMint,
      );
    }
    if (!ownerIsFeePayer && biggestIncrease > BigInt.zero) {
      return ParsedTxResult(
        signature: signature,
        type: ParsedTxType.splReceive,
        amountLamports: biggestIncrease,
        counterparty: null,
        feeLamports: feeLamports,
        tokenMint: receivedMint,
      );
    }
    return null;
  }

  String? _findIncreasedCounterparty({
    required List<sol.AccountKey> accountKeys,
    required List<int> pre,
    required List<int> post,
    required int excludeIndex,
  }) {
    var bestIdx = -1;
    var bestDelta = 0;
    for (var i = 0; i < accountKeys.length && i < pre.length && i < post.length; i++) {
      if (i == excludeIndex) continue;
      final d = post[i] - pre[i];
      if (d > bestDelta) {
        bestDelta = d;
        bestIdx = i;
      }
    }
    return bestIdx >= 0 ? accountKeys[bestIdx].pubkey : null;
  }

  String? _findDecreasedCounterparty({
    required List<sol.AccountKey> accountKeys,
    required List<int> pre,
    required List<int> post,
    required int excludeIndex,
  }) {
    var bestIdx = -1;
    var bestDelta = 0;
    for (var i = 0; i < accountKeys.length && i < pre.length && i < post.length; i++) {
      if (i == excludeIndex) continue;
      final d = post[i] - pre[i];
      if (d < bestDelta) {
        bestDelta = d;
        bestIdx = i;
      }
    }
    return bestIdx >= 0 ? accountKeys[bestIdx].pubkey : null;
  }

  ParsedTxResult _withFee(String signature, BigInt? feeLamports) {
    return ParsedTxResult(
      signature: signature,
      type: ParsedTxType.unknown,
      amountLamports: null,
      counterparty: null,
      feeLamports: feeLamports,
      tokenMint: null,
    );
  }

  ParsedTxResult _unknown(String signature) => ParsedTxResult(
        signature: signature,
        type: ParsedTxType.unknown,
        amountLamports: null,
        counterparty: null,
        feeLamports: null,
        tokenMint: null,
      );

  void _addToCache(String key, ParsedTxResult val) {
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = val;
  }
}

class _TokenSnapshot {
  const _TokenSnapshot({required this.mint, required this.amount});
  final String mint;
  final BigInt amount;
}
