/// @file        wallet_live_mode.dart
/// @description WalletLiveService state-machine enum
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header English translation)
library;

enum WalletLiveMode {
  initial,
  connecting,
  reconnecting,
  websocket,
  polling,
  offline,
  disposed,
}
