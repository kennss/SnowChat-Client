/// @file        identity_change_banner.dart
/// @description Inline chat-screen banner shown after an identity binding of
///              the peer was rejected or missing (latched by the identity-
///              change handler in IdentityVerificationDao) and until the user
///              verifies again. Always critical (red): someone may be trying
///              to impersonate the contact.
///
///              Actions:
///                - Verify  → /safety/:peerSnowId
///                - Dismiss → in-memory dismissal for this screen instance
///                            (the latch stays until the user marks verified)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-11-21 (one meaning left — a rejected or missing identity binding: no amber "safety number changed" variant, which only the removed legacy TOFU policy produced)
///
/// @functions
///  - IdentityChangeBanner: identity-rejection chat banner widget
library;

import 'package:flutter/material.dart';

import '../../../shared/constants/colors.dart';

class IdentityChangeBanner extends StatelessWidget {
  final String peerDisplayName;

  /// "Verify" tap → push the verify screen.
  final VoidCallback onVerify;

  /// "Dismiss" tap → hide the banner for this screen instance.
  final VoidCallback onDismiss;

  const IdentityChangeBanner({
    super.key,
    required this.peerDisplayName,
    required this.onVerify,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    const accent = SnowColors.error;
    final bg = SnowColors.error.withValues(alpha: 0.14);
    final title = "Couldn't verify $peerDisplayName's identity — check the "
        'safety number';
    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
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
                icon: const Icon(Icons.close_rounded, color: accent),
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
