/// @file        call_permission_helper.dart
/// @description Android USE_FULL_SCREEN_INTENT permission handling for incoming
///              calls. On Android 14+ (API 34) the full-screen-intent permission
///              is NOT auto-granted to non-default-dialer apps, so a locked-screen
///              incoming call is downgraded from the full-screen call UI to a
///              heads-up notification the user must tap (and can swipe away with
///              no way to answer). This helper checks the grant state and, once,
///              prompts the user to enable it (the request opens the system
///              Settings toggle — there is no way to grant it programmatically).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-08-07
/// @lastUpdated 2026-08-07
///
/// @functions
///  - hasFullScreenIntent(): whether the full-screen-intent permission is granted (true on iOS / Android < 14)
///  - openFullScreenIntentSettings(): open the system settings toggle for the permission (Android 14+)
///  - maybePromptOnLaunch(): one-shot launch-time prompt (skips if granted or previously dismissed)
///  - promptFromSettings(): always-available entry point (Settings tile) to enable it

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../../shared/constants/colors.dart';
import '../storage/secure_storage.dart';

class CallPermissionHelper {
  CallPermissionHelper._();

  /// Secure-storage flag: the user explicitly dismissed the launch prompt with
  /// "Later" — don't auto-prompt again (the Settings tile still lets them enable
  /// it). "Allow" does NOT set this, so a gentle re-prompt happens next launch
  /// until the permission is actually granted (canUseFullScreenIntent → true).
  static const _dismissedKey = 'voip_fsi_prompt_dismissed';

  /// True when incoming calls can show the full-screen UI over the lock screen.
  /// iOS uses CallKit (unaffected) and Android < 14 auto-grants the declared
  /// permission, so both return true; only Android 14+ can return false.
  static Future<bool> hasFullScreenIntent() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await FlutterCallkitIncoming.canUseFullScreenIntent();
      // Plugin returns a dynamic bool; default to true if the channel is absent
      // (older plugin / non-14 device) so we never nag unnecessarily.
      return result is bool ? result : true;
    } catch (_) {
      return true;
    }
  }

  /// Open the system Settings toggle for the full-screen-intent permission.
  /// No-op on iOS / Android < 14 (the plugin guards internally).
  static Future<void> openFullScreenIntentSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {
      // best-effort — the settings deep-link can be missing on some OEMs
    }
  }

  /// One-shot, launch-time prompt. Shows the explanation dialog only when the
  /// permission is genuinely missing (Android 14+, not granted) AND the user
  /// hasn't dismissed it before. Safe to call on every home-screen mount — it
  /// self-guards and returns immediately in the common (granted) case.
  static Future<void> maybePromptOnLaunch(
    BuildContext context,
    SecureStorageService storage,
  ) async {
    if (!Platform.isAndroid) return;
    if (await hasFullScreenIntent()) return; // already grantable/granted
    final dismissed = await storage.read(_dismissedKey);
    if (dismissed == 'true') return;
    if (!context.mounted) return;
    await _showDialog(context, storage: storage, allowLater: true);
  }

  /// Always-available entry point (Settings tile). If already granted, shows a
  /// short confirmation; otherwise opens the enable dialog (no "Later" gate).
  static Future<void> promptFromSettings(BuildContext context) async {
    if (!Platform.isAndroid) return;
    if (await hasFullScreenIntent()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Lock-screen calls are already enabled.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (!context.mounted) return;
    await _showDialog(context, storage: null, allowLater: false);
  }

  static Future<void> _showDialog(
    BuildContext context, {
    required SecureStorageService? storage,
    required bool allowLater,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Show calls on the lock screen',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: const Text(
          'Android needs your permission to show incoming SnowChat calls '
          'full-screen while your phone is locked. Without it, a locked-screen '
          'call only appears as a small notification that’s easy to miss.\n\n'
          'Tap Enable, then turn on the switch on the next screen.',
          style: TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          if (allowLater)
            TextButton(
              onPressed: () async {
                await storage?.write(_dismissedKey, 'true');
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Later'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openFullScreenIntentSettings();
            },
            child: const Text(
              'Enable',
              style: TextStyle(color: SnowColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
