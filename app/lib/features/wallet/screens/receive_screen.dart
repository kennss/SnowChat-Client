/// @file        receive_screen.dart
/// @description Token receive screen — Multi-Wallet Phase 4A: user can pick
///              which wallet to receive into. Defaults to default wallet,
///              top picker chip allows switching (does not change active —
///              applies only inside the receive screen).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-05-11 (share_plus 13.x API migration — iOS 26 iPhone silent fail
///              when sharePositionOrigin missing. Previously: 2026-04-26.)
///
/// @functions
///  - ReceiveScreen: receive screen widget showing QR code and wallet address

library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/wallet_list_provider.dart';
import '../widgets/wallet_picker_sheet.dart';

abstract class _C {
  static const background = Color(0xFF000000);
  static const primary = Color(0xFF00F782);
  static const surfaceVariant = Color(0xFF1A1A1A);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
}

class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({super.key});

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  /// walletId picked by the user via picker. null = not yet init →
  /// use default.
  String? _selectedWalletId;

  @override
  Widget build(BuildContext context) {
    // Phase 4A v2 (2026-04-25 hotfix) — change prefill to active.
    // Before: prefill with default → user switches to Imported on home,
    //   enters Receive → shows "To: Main Wallet" → copies Main address →
    //   thinks they're sending Main → imported, but actually Main → Main.
    // After: prefill with active → matches the user's mental model of
    //   "receive into the wallet I'm currently viewing". The user can
    //   change via the picker (default included).
    final activeId = ref.watch(activeWalletIdProvider);
    final defaultId = ref.watch(defaultWalletIdProvider);
    final effectiveId = _selectedWalletId ?? activeId ?? defaultId;

    final entry = effectiveId == null
        ? null
        : ref.watch(walletIndexProvider).valueOrNull?.findById(effectiveId);
    final address = entry?.address ?? '---';

    return Scaffold(
      backgroundColor: _C.background,
      appBar: AppBar(
        backgroundColor: _C.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Receive',
          style: TextStyle(color: _C.textPrimary, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Phase 4A — wallet picker chip
                if (effectiveId != null) ...[
                  WalletPickerChip(
                    selectedId: effectiveId,
                    label: 'To',
                    title: 'Receive into',
                    onChanged: (id) =>
                        setState(() => _selectedWalletId = id),
                  ),
                  const SizedBox(height: 24),
                ],

                // QR Code (Polish A-1) — actual QR generation via qr_flutter.
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: address == '---'
                        ? const Icon(
                            Icons.qr_code_2,
                            size: 120,
                            color: Colors.black26,
                          )
                        : QrImageView(
                            data: address,
                            version: QrVersions.auto,
                            size: 188,
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                  ),
                ),
                const SizedBox(height: 24),

                // Address label — emphasizes the selected wallet
                Text(
                  entry == null
                      ? 'Your Solana Address'
                      : '${entry.label} address',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _C.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // Address text.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _C.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    address,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: _C.textSecondary,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Copy button.
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: address == '---'
                        ? null
                        : () => _copyAddress(context, address),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy Address'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.primary,
                      foregroundColor: const Color(0xFF000000),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Share button (Polish A-2) — share address via share_plus.
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Builder(builder: (btnContext) => OutlinedButton.icon(
                    onPressed: address == '---'
                        ? null
                        : () {
                            final subject = entry == null
                                ? 'My Solana address'
                                : '${entry.label} address';
                            final box = btnContext.findRenderObject()
                                as RenderBox?;
                            SharePlus.instance.share(ShareParams(
                              text: address,
                              subject: subject,
                              sharePositionOrigin: box != null
                                  ? box.localToGlobal(Offset.zero) & box.size
                                  : null,
                            ));
                          },
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _C.primary,
                      side: BorderSide(
                          color: _C.primary.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copyAddress(BuildContext context, String address) {
    Clipboard.setData(ClipboardData(text: address));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Address copied'),
        backgroundColor: const Color(0xFF111111),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
