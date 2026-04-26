/// @file        identity_change_banner.dart
/// @description Inline chat-screen banner shown when the local TOFU pin
///              store has caught a new Ed25519 identity key for the peer.
///              Two severity levels:
///                - Critical (red): the user had previously marked the
///                  prior key as verified — possible MITM, must re-verify.
///                - Warning (amber): a re-pin without prior verification —
///                  e.g. the contact reinstalled the app — re-verification
///                  recommended but not urgent.
///
///              Actions:
///                - Verify  → /safety/:peerSnowId
///                - Dismiss → in-memory dismissal for this screen instance
///                            (the underlying DAO row stays mismatched
///                            until the user explicitly marks verified)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-18
///
/// @functions
///  - IdentityChangeBanner: critical/warning chat banner widget
library;

import 'package:flutter/material.dart';

import '../../../shared/constants/colors.dart';

class IdentityChangeBanner extends StatelessWidget {
  final String peerDisplayName;

  /// True when the user had previously verified the (now-replaced) key.
  /// Drives the red severity styling.
  final bool wasPreviouslyVerified;

  /// "Verify" tap → push the verify screen.
  final VoidCallback onVerify;

  /// "Dismiss" tap → hide the banner for this screen instance.
  final VoidCallback onDismiss;

  const IdentityChangeBanner({
    super.key,
    required this.peerDisplayName,
    required this.wasPreviouslyVerified,
    required this.onVerify,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final critical = wasPreviouslyVerified;
    final accent = critical ? SnowColors.error : Colors.amber.shade800;
    final bg = (critical ? SnowColors.error : Colors.amber)
        .withValues(alpha: 0.14);
    final title = critical
        ? 'Safety number with $peerDisplayName changed — re-verify'
        : 'Safety number with $peerDisplayName changed';
    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                critical
                    ? Icons.warning_amber_rounded
                    : Icons.shield_outlined,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: onVerify,
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Verify'),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: Icon(Icons.close_rounded, color: accent),
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
