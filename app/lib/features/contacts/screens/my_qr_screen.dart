/// @file        my_qr_screen.dart
/// @description My QR code screen — generate/display SnowChat ID QR code with qr_flutter, share/copy actions.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - MyQrScreen: ConsumerWidget that displays my QR code
///  - _shareId(): share SnowChat ID text via share_plus
///  - _copyId(): copy SnowChat ID to clipboard

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_id_display.dart';
import '../../../shared/widgets/toast.dart';
import '../../../app/providers.dart';

class MyQrScreen extends ConsumerWidget {
  const MyQrScreen({super.key});

  // Fallback when provider has no value yet
  static const _fallbackId = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentSnowIdProvider) ?? _fallbackId;

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('My QR Code'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(SnowSizes.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // QR Code generated with qr_flutter
              Container(
                width: 260,
                height: 260,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: myId,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: Colors.black,
                  ),
                ),
              ),

              const SizedBox(height: SnowSizes.xl),

              const Text(
                'Your SnowChat ID',
                style: TextStyle(
                  color: SnowColors.textSecondary,
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: SnowSizes.sm),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: SnowColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SnowIdDisplay(
                  snowId: myId,
                  compact: false,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: SnowSizes.xl),

              // Action buttons row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Copy button
                  OutlinedButton.icon(
                    onPressed: () => _copyId(context, myId),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),

                  const SizedBox(width: SnowSizes.md),

                  // Share button
                  OutlinedButton.icon(
                    onPressed: () => _shareId(myId),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Copy SnowChat ID to clipboard.
  void _copyId(BuildContext context, String id) {
    Clipboard.setData(ClipboardData(text: id));
    SnowToast.show(
      context,
      message: 'SnowChat ID copied to clipboard',
      type: ToastType.success,
    );
  }

  /// Share SnowChat ID as text via share_plus.
  void _shareId(String id) {
    Share.share('Add me on SnowChat: $id');
  }
}
