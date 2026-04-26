/// @file        solana_config.dart
/// @description Solana network configuration management. Provides Devnet/Mainnet toggle, RPC URL, and Explorer URL.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - SolanaNetwork: Devnet/Mainnet network enum
///  - SolanaConfig: network configuration singleton class
///  - SolanaConfig.rpcUrl: RPC URL for the current network
///  - SolanaConfig.wsUrl: WebSocket URL for the current network
///  - SolanaConfig.explorerBaseUrl: Explorer URL for the current network
///  - SolanaConfig.isDevnet: check if Devnet
///  - SolanaConfig.switchNetwork(): switch and persist network
///  - SolanaConfig.loadSaved(): load saved network configuration

/// Solana network configuration with Devnet/Mainnet toggle.
///
/// Persists the selected network via [SecureStorageService].
/// Default network is Devnet for safe development.
library;

import '../storage/secure_storage.dart';

/// Available Solana networks.
enum SolanaNetwork {
  devnet,
  mainnet,
}

/// Global Solana network configuration.
///
/// Provides RPC URLs, WebSocket URLs, and Explorer URLs
/// based on the currently selected network.
class SolanaConfig {
  SolanaConfig._();

  static SolanaNetwork currentNetwork = SolanaNetwork.devnet;

  static const String _storageKey = 'solana_network';

  /// JSON-RPC endpoint for the current network.
  static String get rpcUrl => currentNetwork == SolanaNetwork.devnet
      ? 'https://api.devnet.solana.com'
      : 'https://api.mainnet-beta.solana.com';

  /// WebSocket endpoint for the current network.
  static String get wsUrl => currentNetwork == SolanaNetwork.devnet
      ? 'wss://api.devnet.solana.com'
      : 'wss://api.mainnet-beta.solana.com';

  /// Solana Explorer base URL for the current network.
  static String get explorerBaseUrl => currentNetwork == SolanaNetwork.devnet
      ? 'https://explorer.solana.com/?cluster=devnet'
      : 'https://explorer.solana.com';

  /// Explorer URL for a specific transaction signature.
  static String explorerTxUrl(String signature) {
    final cluster =
        currentNetwork == SolanaNetwork.devnet ? '?cluster=devnet' : '';
    return 'https://explorer.solana.com/tx/$signature$cluster';
  }

  /// Explorer URL for a specific account address.
  static String explorerAccountUrl(String address) {
    final cluster =
        currentNetwork == SolanaNetwork.devnet ? '?cluster=devnet' : '';
    return 'https://explorer.solana.com/address/$address$cluster';
  }

  /// Whether the current network is Devnet.
  static bool get isDevnet => currentNetwork == SolanaNetwork.devnet;

  /// Switch to a different network and persist the choice.
  static Future<void> switchNetwork(
    SolanaNetwork network,
    SecureStorageService storage,
  ) async {
    currentNetwork = network;
    await storage.write(_storageKey, network.name);
  }

  /// Load the saved network preference from secure storage.
  /// Defaults to Devnet if no preference is saved.
  static Future<void> loadSaved(SecureStorageService storage) async {
    final saved = await storage.read(_storageKey);
    currentNetwork =
        saved == 'mainnet' ? SolanaNetwork.mainnet : SolanaNetwork.devnet;
  }
}
