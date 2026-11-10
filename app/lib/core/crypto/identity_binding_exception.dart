/// @file        identity_binding_exception.dart
/// @description Hard-failure exception for Identity Binding v1 (B-2 §5.7).
///              Raised when a peer's key bundle / PreKey message carries a
///              forged or inconsistent identity binding, when a peer that has
///              proven a binding before shows up without one (downgrade), or
///              when an epoch is replayed. Unlike the transient Signal errors
///              this is NEVER retried: every caller must surface it (the
///              VerifiedIdentityStore emits a user-visible event) and stop.
///
///              The message text deliberately avoids the substrings the
///              message queue uses for string-based error classification
///              ("404", "No devices", "could decrypt the message", "forged",
///              "malformed", "shared secret", "Signed prekey") so this
///              exception can never be mis-routed into a retry / reset path.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-10
/// @lastUpdated 2026-11-10
///
/// @functions
///  - IdentityBindingFailure: reason taxonomy
///  - IdentityBindingInvalidException: typed hard failure (no retry)
library;

import 'signal_protocol_service.dart';

/// Why a binding was rejected. Names are wire/log-safe (no key material).
enum IdentityBindingFailure {
  /// Binding present but structurally unusable (bad lengths, bad encoding).
  badFormat,

  /// Ed25519 signature over the binding message did not verify, or the
  /// account key does not derive the peer's snowId.
  signatureInvalid,

  /// Account key differs from one we already pinned (invite link / record).
  accountKeyMismatch,

  /// Epoch lower than the highest epoch we have accepted (replay), or the
  /// same epoch re-used for different keys.
  epochRegression,

  /// Peer proved a binding before (latched) but now presents none.
  downgrade,

  /// Binding's deviceId differs from the device the envelope/certificate names.
  deviceMismatch,

  /// Binding's X25519 identity key differs from the key actually used in X3DH.
  identityKeyMismatch,
}

class IdentityBindingInvalidException extends SignalProtocolException {
  /// Peer whose binding failed.
  final String peerSnowchatId;

  /// Rejection reason.
  final IdentityBindingFailure reason;

  IdentityBindingInvalidException({
    required this.peerSnowchatId,
    required this.reason,
  }) : super(
          'Identity binding rejected for peer (${reason.name}); '
          'refusing session — not retryable',
          code: 'identity_binding_invalid',
        );
}
