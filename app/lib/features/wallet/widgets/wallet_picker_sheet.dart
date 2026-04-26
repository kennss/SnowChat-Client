/// @file        wallet_picker_sheet.dart
/// @description Multi-Wallet read-only wallet picker — used on Receive /
///              Send screens to choose "which wallet to receive into / which
///              wallet to send from". Unlike selector_sheet this does not
///              change the active wallet — it just returns the walletId via
///              callback (no side effects).
///              Multi-Wallet-Design-FINAL.md §4.1 Phase 4 extension.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - showWalletPickerSheet(context, selectedId, title): returns walletId
///  - WalletPickerChip: selected-wallet label + dropdown chip

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../models/wallet_account_model.dart';
import '../providers/wallet_list_provider.dart';

/// Wallet picker bottom sheet. Returns selected walletId (null on cancel).
Future<String?> showWalletPickerSheet(
  BuildContext context, {
  required String selectedId,
  String title = 'Select Wallet',
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: SnowColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => _WalletPickerSheet(
      selectedId: selectedId,
      title: title,
    ),
  );
}

class _WalletPickerSheet extends ConsumerWidget {
  const _WalletPickerSheet({
    required this.selectedId,
    required this.title,
  });

  final String selectedId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(visibleWalletEntriesProvider);
    final defaultId = ref.watch(defaultWalletIdProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SnowSizes.lg,
          SnowSizes.md,
          SnowSizes.lg,
          SnowSizes.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: SnowColors.surfaceLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                title,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: SnowSizes.sm),
                itemBuilder: (_, i) {
                  final e = entries[i];
                  return _PickerRow(
                    entry: e,
                    isSelected: e.id == selectedId,
                    isDefault: e.id == defaultId,
                    onTap: () => Navigator.of(context).pop(e.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.entry,
    required this.isSelected,
    required this.isDefault,
    required this.onTap,
  });

  final WalletEntry entry;
  final bool isSelected;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shortAddr = _shortAddress(entry.address);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: SnowColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: SnowColors.primary, width: 1.5)
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _kindColor(entry).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _kindIcon(entry),
                size: 18,
                color: _kindColor(entry),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.label,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            color: SnowColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 6),
                        const _Badge(label: 'Default', color: SnowColors.primary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    shortAddr,
                    style: const TextStyle(
                      color: SnowColors.textTertiary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: SnowColors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  IconData _kindIcon(WalletEntry e) {
    if (e.role == WalletRole.primary) return Icons.shield_rounded;
    return e.kind == WalletKind.derived
        ? Icons.account_tree_rounded
        : Icons.download_rounded;
  }

  Color _kindColor(WalletEntry e) {
    if (e.role == WalletRole.primary) return SnowColors.primary;
    return e.kind == WalletKind.derived
        ? SnowColors.primaryDim
        : SnowColors.warning;
  }

  String _shortAddress(String addr) {
    if (addr.length <= 12) return addr;
    return '${addr.substring(0, 6)}…${addr.substring(addr.length - 4)}';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Inline chip widget — used under Receive / Send screen headers.
/// Shows which wallet the user will receive/send with + opens picker sheet on tap.
class WalletPickerChip extends ConsumerWidget {
  const WalletPickerChip({
    super.key,
    required this.selectedId,
    required this.label,
    required this.onChanged,
    this.title = 'Select Wallet',
  });

  /// Currently selected wallet id.
  final String selectedId;

  /// Small label on the chip's left — "From" / "To" etc.
  final String label;

  /// Called when a new wallet is selected. Not called on cancel.
  final ValueChanged<String> onChanged;

  /// Picker sheet title.
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(walletIndexProvider).valueOrNull?.findById(
          selectedId,
        );
    if (entry == null) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final newId = await showWalletPickerSheet(
          context,
          selectedId: selectedId,
          title: title,
        );
        if (newId != null && newId != selectedId) {
          onChanged(newId);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SnowColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SnowColors.surfaceLight, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.account_balance_wallet_rounded,
              size: 14,
              color: SnowColors.textSecondary,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                entry.label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: SnowColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
