/// @file        app_config.dart
/// @description App build-time configuration — feature flags, environment variables.
///              The wallet module is off unless a build asks for it with
///              `--dart-define=ENABLE_WALLET=true`.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-11-21 (enableWallet defaults to false: only the release scripts passed
///              ENABLE_WALLET=false, so every other build — by hand, from Xcode, the device
///              test builds — shipped the wallet. A build that wants it opts in). Earlier
///              2026-11-20 (enableGroupsV2 removed — group protocol v2 always runs where this
///              build pins the server keys, gv2_trusted_keys.dart; allowUnboundIdentity removed —
///              identity bindings are always required, IdentityAdmission.refuseUnbound). Earlier 2026-11-13
///              (enableGroupsV2 flag). Earlier 2026-11-11 (allowUnboundIdentity — identity bindings are
///              mandatory unless a pre-beta build opts out). Earlier 2026-04-26 (header
///              English translation)
///
/// @functions
///  - AppConfig.enableWallet: whether wallet/NFT modules are enabled
library;

abstract class AppConfig {
  /// Whether the wallet + NFT modules are enabled. OFF → their routes, tabs
  /// and providers are all removed.
  ///
  /// Off by default: a build that should have them passes
  /// `--dart-define=ENABLE_WALLET=true` (the release scripts take
  /// `ENABLE_WALLET=true ./scripts/build_release.sh`). The default used to be
  /// true with the release scripts passing false, so any other build — by
  /// hand, from Xcode — came out with the wallet on.
  static const enableWallet = bool.fromEnvironment(
    'ENABLE_WALLET',
    defaultValue: false,
  );
}
