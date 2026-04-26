/// @file        app_config.dart
/// @description App build-time configuration — feature flags, environment variables.
///              Disable wallet module via `--dart-define=ENABLE_WALLET=false`.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - AppConfig.enableWallet: whether wallet/NFT modules are enabled
library;

abstract class AppConfig {
  /// Whether the wallet + NFT modules are enabled.
  ///
  /// Disable via `flutter build apk --dart-define=ENABLE_WALLET=false`.
  /// On Enterprise/Air-Gap builds: OFF → routes/tabs/Providers all removed.
  /// Default is true (Personal/Community builds).
  static const enableWallet = bool.fromEnvironment(
    'ENABLE_WALLET',
    defaultValue: true,
  );
}
