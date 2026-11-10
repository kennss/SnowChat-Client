/// @file        app_config.dart
/// @description App build-time configuration — feature flags, environment variables.
///              Disable wallet module via `--dart-define=ENABLE_WALLET=false`.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-11-11 (allowUnboundIdentity — identity bindings are mandatory unless a
///              pre-beta build opts out). Earlier 2026-04-26 (header English translation)
///
/// @functions
///  - AppConfig.enableWallet: whether wallet/NFT modules are enabled
///  - AppConfig.allowUnboundIdentity: whether peers without an identity binding are accepted
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

  /// Whether a peer whose Signal identity keys carry NO account-key binding
  /// (B-2 Identity Binding v1) may still be accepted under the legacy
  /// Signal-style TOFU policy.
  ///
  /// Default is false: every peer must present a valid binding, otherwise the
  /// session is refused (IdentityBindingFailure.bindingRequired). This is the
  /// only setting that closes the downgrade path where a compromised server
  /// strips the binding of a peer we have never seen bound — the absence of
  /// old clients alone does not.
  ///
  /// Only the internal alpha (build numbers below 1000) sets this to true, so
  /// that +305 alpha testers can keep talking to peers still on +304. The
  /// release scripts derive it from the pubspec build number; beta starts at
  /// build 1000 on a reset server where no unbound client exists. A plain
  /// `flutter run` without the define gets the safe default (mandatory), so
  /// dev interop with a pre-305 build needs
  /// `--dart-define=ALLOW_UNBOUND_IDENTITY=true`.
  static const allowUnboundIdentity = bool.fromEnvironment(
    'ALLOW_UNBOUND_IDENTITY',
    defaultValue: false,
  );
}
