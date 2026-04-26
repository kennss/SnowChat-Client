/// @file        token_list_service.dart
/// @description Jupiter Token List integration — SPL token symbol, name,
///              logo, decimals mapping.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-03
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - TokenListService: Jupiter Token List fetch + cache
///  - getTokenInfo(): look up token metadata by mint
///  - tokenListServiceProvider: Riverpod Provider
///  - TokenMetadata: token metadata data class

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Token metadata from Jupiter Token List.
class TokenMetadata {
  final String mint;
  final String symbol;
  final String name;
  final int decimals;
  final String? logoUrl;

  const TokenMetadata({
    required this.mint,
    required this.symbol,
    required this.name,
    required this.decimals,
    this.logoUrl,
  });
}

/// Well-known token mints (hardcoded for offline fallback).
const _wellKnownTokens = <String, TokenMetadata>{
  'So11111111111111111111111111111111': TokenMetadata(
    mint: 'So11111111111111111111111111111111',
    symbol: 'SOL',
    name: 'Solana',
    decimals: 9,
    logoUrl: 'https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/So11111111111111111111111111111111/logo.png',
  ),
  'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v': TokenMetadata(
    mint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
    symbol: 'USDC',
    name: 'USD Coin',
    decimals: 6,
    logoUrl: 'https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/logo.png',
  ),
  'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB': TokenMetadata(
    mint: 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB',
    symbol: 'USDT',
    name: 'Tether USD',
    decimals: 6,
  ),
};

/// Jupiter Token List service.
///
/// Fetches token metadata (symbol, name, logo) from Jupiter's strict token list.
/// Caches results in memory for the session.
class TokenListService {
  TokenListService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Cache: mint → metadata. Populated on first fetch.
  Map<String, TokenMetadata>? _tokenMap;
  bool _loading = false;

  /// Get token metadata by mint address.
  /// Returns null if token is not found in the list.
  Future<TokenMetadata?> getTokenInfo(String mint) async {
    // Check well-known first
    final wellKnown = _wellKnownTokens[mint];
    if (wellKnown != null) return wellKnown;

    // Load full list if not cached
    if (_tokenMap == null && !_loading) {
      await _loadTokenList();
    }

    return _tokenMap?[mint];
  }

  /// Get metadata for multiple mints at once.
  Future<Map<String, TokenMetadata>> getTokenInfoBatch(
      List<String> mints) async {
    if (_tokenMap == null && !_loading) {
      await _loadTokenList();
    }

    final result = <String, TokenMetadata>{};
    for (final mint in mints) {
      final info =
          _wellKnownTokens[mint] ?? _tokenMap?[mint];
      if (info != null) result[mint] = info;
    }
    return result;
  }

  /// Load Jupiter strict token list.
  Future<void> _loadTokenList() async {
    _loading = true;
    try {
      final response = await _http
          .get(Uri.parse('https://token.jup.ag/strict'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        final map = <String, TokenMetadata>{};

        for (final item in list) {
          final token = item as Map<String, dynamic>;
          final address = token['address'] as String?;
          if (address == null) continue;

          map[address] = TokenMetadata(
            mint: address,
            symbol: token['symbol'] as String? ?? '',
            name: token['name'] as String? ?? '',
            decimals: token['decimals'] as int? ?? 0,
            logoUrl: token['logoURI'] as String?,
          );
        }

        _tokenMap = map;
        debugPrint('[TokenList] Loaded ${map.length} tokens from Jupiter');
      }
    } catch (e) {
      debugPrint('[TokenList] Failed to load Jupiter token list: $e');
      _tokenMap = {};
    } finally {
      _loading = false;
    }
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

final tokenListServiceProvider = Provider<TokenListService>((ref) {
  return TokenListService();
});
