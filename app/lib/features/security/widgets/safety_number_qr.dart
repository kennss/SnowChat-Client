/// @file        safety_number_qr.dart
/// @description QR-code modal for the 60-digit Safety Number. Encodes the
///              payload as `snowchat-fingerprint:v1:{theirSnowId}:{digits60}`
///              so a future QR-scanner verification flow (out of scope for
///              this PR) can recognize the data shape, validate the snow ID,
///              and reject mismatched scans before showing any UI.
///
///              Today the QR is purely a display aid — peers compare visual
///              digits or scan + manual confirm. The version prefix gives
///              us room to migrate to a binary 30-byte fingerprint payload
///              later without breaking older readers.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-18
///
/// @functions
///  - SafetyNumberQrSheet: bottom-sheet QR display widget
///  - showSafetyNumberQr(...): convenience launcher
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';

/// Build the canonical QR payload for a Safety Number.
String buildSafetyNumberQrPayload({
  required String peerSnowId,
  required String digits60,
}) {
  return 'snowchat-fingerprint:v1:$peerSnowId:$digits60';
}

/// Convenience launcher that mirrors the in-codebase `showModalBottomSheet`
/// patterns used elsewhere (e.g. `_showMemberOptions`). Centralized here so
/// the chat & verify screens both reach the QR via a single call site.
Future<void> showSafetyNumberQr(
  BuildContext context, {
  required String peerSnowId,
  required String peerDisplayName,
  required String digits60,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: SnowColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(SnowSizes.radiusMd)),
    ),
    builder: (_) => _SafetyNumberQrSheet(
      peerSnowId: peerSnowId,
      peerDisplayName: peerDisplayName,
      digits60: digits60,
    ),
  );
}

class _SafetyNumberQrSheet extends StatelessWidget {
  final String peerSnowId;
  final String peerDisplayName;
  final String digits60;

  const _SafetyNumberQrSheet({
    required this.peerSnowId,
    required this.peerDisplayName,
    required this.digits60,
  });

  @override
  Widget build(BuildContext context) {
    final payload = buildSafetyNumberQrPayload(
      peerSnowId: peerSnowId,
      digits60: digits60,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(SnowSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Safety number with $peerDisplayName',
              style: const TextStyle(
                color: SnowColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SnowSizes.md),
            Container(
              width: 240,
              height: 240,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 216,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: SnowSizes.md),
            const Text(
              'Have your contact scan this code (or compare the digits) to '
              'verify that no one is intercepting your messages.',
              style: TextStyle(
                color: SnowColors.textSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SnowSizes.md),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: payload));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Safety number payload copied'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded,
                  size: 18, color: SnowColors.primary),
              label: const Text('Copy payload',
                  style: TextStyle(color: SnowColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}
