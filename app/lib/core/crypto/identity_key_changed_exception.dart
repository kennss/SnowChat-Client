/// @file        identity_key_changed_exception.dart
/// @description Specialized SignalProtocolException raised when our TOFU
///              pin store detects that the remote Ed25519 identity key for
///              a peer has changed since the last successful X3DH. The
///              exception carries the peer SnowChat ID, the device ID, and
///              both the previously pinned key and the freshly received
///              key so that higher-level callers (MessageQueue,
///              EncryptedMessageHandler) can hand off to
///              [IdentityChangeHandler] for Safety Number recomputation,
///              banner emission, and system-message insertion — instead of
///              silently failing as if the message bounced for any other
///              ratchet reason.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-18
///
/// @functions
///  - IdentityKeyChangedException: typed exception with peer + key fields
library;

import 'dart:typed_data';

import 'signal_protocol_service.dart';

class IdentityKeyChangedException extends SignalProtocolException {
  /// Peer SnowChat ID whose key changed.
  final String peerSnowchatId;

  /// Optional device ID (sub-key in our session map). Single-device today,
  /// but kept here so multi-device-aware UI can disambiguate later.
  final String? deviceId;

  /// Previously pinned Ed25519 raw public key (32 bytes).
  final Uint8List expectedKey;

  /// Newly received Ed25519 raw public key (32 bytes) that triggered the
  /// mismatch.
  final Uint8List actualKey;

  IdentityKeyChangedException({
    required this.peerSnowchatId,
    required this.expectedKey,
    required this.actualKey,
    this.deviceId,
  }) : super(
          'Identity key changed for $peerSnowchatId'
          '${deviceId == null ? '' : ':$deviceId'} — possible MITM. '
          'User must re-verify before continuing.',
          code: 'identity_key_changed',
        );
}
