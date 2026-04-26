/// @file        rpc_config.dart
/// @description Solana network config — manages Devnet/Mainnet RPC /
///              WebSocket / DAS URLs.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-03
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - SolanaNetwork: Devnet/Mainnet enum (RPC URL, WS URL, DAS URL, Explorer URL)

/// Helius API key (build-time injection).
/// `flutter run --dart-define=HELIUS_API_KEY=xxx`
const _heliusKey = String.fromEnvironment('HELIUS_API_KEY', defaultValue: '');

/// Available Solana networks with their endpoint URLs.
enum SolanaNetwork {
  devnet(
    rpcUrl: 'https://api.devnet.solana.com',
    wsUrl: 'wss://api.devnet.solana.com',
    explorerBaseUrl: 'https://explorer.solana.com/?cluster=devnet',
  ),
  mainnet(
    rpcUrl: 'https://api.mainnet-beta.solana.com',
    wsUrl: 'wss://api.mainnet-beta.solana.com',
    explorerBaseUrl: 'https://explorer.solana.com',
  );

  const SolanaNetwork({
    required this.rpcUrl,
    required this.wsUrl,
    required this.explorerBaseUrl,
  });

  final String rpcUrl;
  final String wsUrl;
  final String explorerBaseUrl;

  /// DAS API URL (Helius). null when Helius key is missing → skip DAS.
  String? get dasRpcUrl {
    if (_heliusKey.isEmpty) return null;
    return switch (this) {
      devnet => 'https://devnet.helius-rpc.com/?api-key=$_heliusKey',
      mainnet => 'https://mainnet.helius-rpc.com/?api-key=$_heliusKey',
    };
  }

  /// Explorer URL for a specific transaction signature.
  String explorerTxUrl(String signature) {
    final cluster = this == devnet ? '?cluster=devnet' : '';
    return 'https://explorer.solana.com/tx/$signature$cluster';
  }

  /// Explorer URL for a specific account address.
  String explorerAccountUrl(String address) {
    final cluster = this == devnet ? '?cluster=devnet' : '';
    return 'https://explorer.solana.com/address/$address$cluster';
  }
}
