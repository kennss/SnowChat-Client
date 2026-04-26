/// @file        token_service.dart
/// @description SPL token query service. Queries real token balances via RPC, fetches metadata/price info from the server API.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - TokenService: SPL token query service class
///  - TokenService.getTokens(): query held token list per wallet address (RPC + server API)
///  - TokenService.getTokenByMint(): single token query by mint address
///  - TokenService.getWalletBalance(): query total portfolio USD value
///  - TokenService.hasEnoughBalance(): check whether balance is sufficient for transfer

/// SPL token query service with real Solana RPC integration.
///
/// Fetches token balances from on-chain via [SolanaClient],
/// enriches with metadata and prices from the server API.
/// All monetary values are [BigInt] (lamports). NEVER use double.
library;

import 'package:dio/dio.dart';

import '../../shared/models/wallet_models.dart';
import '../network/api_client.dart';
import 'solana_client.dart';

/// Service for querying SPL token holdings, metadata, and prices.
class TokenService {
  TokenService({
    required this.solanaClient,
    this.apiClient,
  });

  final SolanaClient solanaClient;

  /// Optional server API client for metadata/price enrichment.
  final ApiClient? apiClient;

  /// Well-known token metadata cache (mint -> metadata).
  /// Populated from server or hardcoded fallbacks.
  final Map<String, _TokenMeta> _metadataCache = {};

  /// Fetch all token holdings for [walletAddress].
  ///
  /// 1. Gets native SOL balance from RPC
  /// 2. Gets SPL token accounts from RPC
  /// 3. Enriches with metadata from server API (with fallback)
  Future<List<TokenInfo>> getTokens(String walletAddress) async {
    final tokens = <TokenInfo>[];

    // 1. Native SOL balance
    final solBalance = await solanaClient.getBalance(walletAddress);
    tokens.add(TokenInfo(
      mint: 'So11111111111111111111111111111111',
      symbol: 'SOL',
      name: 'Solana',
      decimals: 9,
      balanceLamports: solBalance,
      usdValueCents: BigInt.zero, // Updated below if price available
      logoUrl:
          'https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/So11111111111111111111111111111111/logo.png',
    ));

    // 2. SPL token accounts from RPC
    try {
      final tokenAccounts =
          await solanaClient.getTokenAccountsByOwner(walletAddress);

      for (final account in tokenAccounts) {
        final mint = account['mint'] as String;
        final amountStr = account['amount'] as String;
        final decimals = account['decimals'] as int;
        final balance = BigInt.parse(amountStr);

        // Skip zero-balance token accounts
        if (balance == BigInt.zero) continue;

        // Get metadata (from cache, server, or fallback)
        final meta = await _getTokenMetadata(mint);

        tokens.add(TokenInfo(
          mint: mint,
          symbol: meta?.symbol ?? _shortenMint(mint),
          name: meta?.name ?? 'Unknown Token',
          decimals: decimals,
          balanceLamports: balance,
          usdValueCents: BigInt.zero, // Prices from server
          logoUrl: meta?.logoUrl,
        ));
      }
    } on SolanaRpcException catch (_) {
      // If token account fetch fails, still return SOL balance
    }

    // 3. Enrich with prices from server API
    await _enrichWithPrices(walletAddress, tokens);

    return tokens;
  }

  /// Fetch a single token's info by mint address.
  Future<TokenInfo?> getTokenByMint(
      String walletAddress, String mint) async {
    final tokens = await getTokens(walletAddress);
    try {
      return tokens.firstWhere((t) => t.mint == mint);
    } catch (_) {
      return null;
    }
  }

  /// Fetch the total portfolio value in USD cents.
  Future<WalletBalance> getWalletBalance(String walletAddress) async {
    final tokens = await getTokens(walletAddress);
    final totalCents = tokens.fold<BigInt>(
      BigInt.zero,
      (sum, t) => sum + t.usdValueCents,
    );

    return WalletBalance(
      totalUsdValue: totalCents,
      changePercent24h: 0, // Server should provide this
      tokens: tokens,
    );
  }

  /// Validate that [walletAddress] has enough balance for a transfer.
  Future<bool> hasEnoughBalance({
    required String walletAddress,
    required String mint,
    required BigInt amount,
  }) async {
    // For native SOL, check directly
    if (mint == 'So11111111111111111111111111111111' ||
        mint == 'SOL') {
      final balance = await solanaClient.getBalance(walletAddress);
      // Account for transaction fee (5000 lamports)
      return balance >= amount + BigInt.from(5000);
    }

    final token = await getTokenByMint(walletAddress, mint);
    if (token == null) return false;
    return token.balanceLamports >= amount;
  }

  // ---------------------------------------------------------------------------
  // Private: Metadata & Price enrichment
  // ---------------------------------------------------------------------------

  /// Get token metadata from cache, server API, or fallback.
  Future<_TokenMeta?> _getTokenMetadata(String mint) async {
    // Check cache first
    if (_metadataCache.containsKey(mint)) {
      return _metadataCache[mint];
    }

    // Check well-known tokens
    final wellKnown = _wellKnownTokens[mint];
    if (wellKnown != null) {
      _metadataCache[mint] = wellKnown;
      return wellKnown;
    }

    // Try server API
    if (apiClient != null) {
      try {
        final response =
            await apiClient!.get('/wallet/token-metadata/$mint');
        if (response.statusCode == 200 && response.data != null) {
          final data = response.data as Map<String, dynamic>;
          final meta = _TokenMeta(
            symbol: data['symbol'] as String? ?? _shortenMint(mint),
            name: data['name'] as String? ?? 'Unknown Token',
            logoUrl: data['logoUrl'] as String?,
          );
          _metadataCache[mint] = meta;
          return meta;
        }
      } on DioException catch (_) {
        // Server unavailable, use fallback
      }
    }

    return null;
  }

  /// Enrich token list with USD prices from server API.
  Future<void> _enrichWithPrices(
      String walletAddress, List<TokenInfo> tokens) async {
    if (apiClient == null) return;

    try {
      final response = await apiClient!.get(
        '/wallet/prices',
        queryParameters: {
          'mints':
              tokens.map((t) => t.mint).join(','),
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        final prices = response.data as Map<String, dynamic>;
        for (var i = 0; i < tokens.length; i++) {
          final priceData = prices[tokens[i].mint];
          if (priceData != null) {
            final priceCents = priceData['usdValueCents'];
            final change = priceData['changePercent24h'];
            if (priceCents != null) {
              // Replace token with price-enriched version
              tokens[i] = TokenInfo(
                mint: tokens[i].mint,
                symbol: tokens[i].symbol,
                name: tokens[i].name,
                decimals: tokens[i].decimals,
                balanceLamports: tokens[i].balanceLamports,
                usdValueCents: BigInt.from(priceCents as num),
                logoUrl: tokens[i].logoUrl,
                changePercent24h: change as int? ?? 0,
              );
            }
          }
        }
      }
    } on DioException catch (_) {
      // Price enrichment is best-effort; tokens still returned without prices
    }
  }

  /// Shorten a mint address for display when no symbol is known.
  static String _shortenMint(String mint) {
    if (mint.length <= 8) return mint;
    return '${mint.substring(0, 4)}..${mint.substring(mint.length - 4)}';
  }
}

// ---------------------------------------------------------------------------
// Internal: Token metadata model
// ---------------------------------------------------------------------------

class _TokenMeta {
  _TokenMeta({
    required this.symbol,
    required this.name,
    this.logoUrl,
  });

  final String symbol;
  final String name;
  final String? logoUrl;
}

// ---------------------------------------------------------------------------
// Well-known token registry (fallback when server is unavailable)
// ---------------------------------------------------------------------------

final _wellKnownTokens = <String, _TokenMeta>{
  'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v': _TokenMeta(
    symbol: 'USDC',
    name: 'USD Coin',
    logoUrl:
        'https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/logo.png',
  ),
  'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB': _TokenMeta(
    symbol: 'USDT',
    name: 'USDT',
    logoUrl:
        'https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB/logo.png',
  ),
  'DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263': _TokenMeta(
    symbol: 'BONK',
    name: 'Bonk',
    logoUrl:
        'https://arweave.net/hQiPZOsRZXGXBJd_82PhVdlM_hACsT_q6wqwf5cSY7I',
  ),
  'JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN': _TokenMeta(
    symbol: 'JUP',
    name: 'Jupiter',
    logoUrl: null,
  ),
  'SNOWkNTSi8yoSmFRRa5B6KNjGBRb6LYaHCfghtxLMJf': _TokenMeta(
    symbol: 'SNOW',
    name: 'SnowChat Token',
    logoUrl: null,
  ),
};
