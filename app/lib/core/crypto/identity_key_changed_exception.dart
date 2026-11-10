/// @file        identity_key_changed_exception.dart
/// @description Raised under the B-2 legacy-peer policy (§5.5, Signal
///              style) when a peer WITHOUT an identity binding presents new
///              Signal keys while the user had marked them verified. The new
///              keys are parked as "pending" in VerifiedIdentityStore and the
///              peer stays blocked (send + new inbound sessions) until the user
///              re-verifies on the verify screen. Unverified peers never raise
///              this — their keys are updated with a notice. Carries the peer
///              SnowChat ID, device ID, and the old/new key for diagnostics
///              (never logged).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-11-10 (B-2: semantics narrowed to the verified-legacy-peer block; the TOFU pin store it was built for is gone)
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
