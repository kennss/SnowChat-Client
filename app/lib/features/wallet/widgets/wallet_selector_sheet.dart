/// @file        wallet_selector_sheet.dart
/// @description Multi-Wallet selector bottom sheet — list of visible entries
///              + active/default badge + Copy icon (E-5) + Add Wallet entry.
///              On row tap calls [WalletNotifier.switchActive] + pops sheet.
///              Multi-Wallet-Design-FINAL.md §4.1.
///
///              Phase 3B scope: read + switch + copy only. Add Wallet sheet
///              and ⋯ overflow menu (Set Default / Rename / Hide / Remove)
///              come in Phase 3C/3D/3E.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - showWalletSelectorSheet(context): show the WalletSelectorSheet
///  - WalletSelectorSheet: ConsumerWidget — sheet body
///  - _WalletRow: single row

library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/toast.dart';
import '../../marketplace/providers/marketplace_provider.dart'
    show fetchActiveListingMintsForOwner;
import '../../nft/nft_provider.dart' show nftServiceProvider;
import '../models/wallet_account_model.dart';
import '../models/wallet_index_exceptions.dart';
import '../providers/wallet_list_provider.dart';
import '../rpc/rpc_client_provider.dart';
import '../wallet_provider.dart';
import 'add_wallet_sheet.dart';
import 'wallet_actions_dialogs.dart';

Future<void> showWalletSelectorSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: SnowColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const WalletSelectorSheet(),
  );
}

class WalletSelectorSheet extends ConsumerWidget {
  const WalletSelectorSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(visibleWalletEntriesProvider);
    final activeId = ref.watch(activeWalletIdProvider);
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
            // grab handle
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

            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                'Wallets',
                style: TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Entries — flexible scroll if many
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: SnowSizes.sm),
                itemBuilder: (_, i) => _WalletRow(
                  entry: entries[i],
                  isActive: entries[i].id == activeId,
                  isDefault: entries[i].id == defaultId,
                ),
              ),
            ),

            const SizedBox(height: SnowSizes.lg),

            // Add Wallet — entry to the Phase 3C add sheet.
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await showAddWalletSheet(context);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Wallet'),
              style: OutlinedButton.styleFrom(
                foregroundColor: SnowColors.primary,
                side: BorderSide(
                  color: SnowColors.primary.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletRow extends ConsumerWidget {
  const _WalletRow({
    required this.entry,
    required this.isActive,
    required this.isDefault,
  });

  final WalletEntry entry;
  final bool isActive;
  final bool isDefault;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortAddr = _shortAddress(entry.address);

    return Container(
      decoration: BoxDecoration(
        color: SnowColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: isActive
            ? Border.all(color: SnowColors.primary, width: 1.5)
            : Border.all(color: Colors.transparent),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // tap area — switch active
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: isActive
                    ? null
                    : () async {
                        try {
                          await ref
                              .read(walletProvider.notifier)
                              .switchActive(entry.id);
                          if (context.mounted) Navigator.of(context).pop();
                        } catch (e) {
                          if (context.mounted) {
                            SnowToast.show(
                              context,
                              message: 'Failed to switch: $e',
                              type: ToastType.error,
                            );
                          }
                        }
                      },
                child: Row(
                  children: [
                    // wallet icon — color per kind
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
                                _Badge(
                                  label: 'Default',
                                  color: SnowColors.primary,
                                ),
                              ],
                              if (entry.role == WalletRole.primary) ...[
                                const SizedBox(width: 6),
                                _Badge(
                                  label: 'Main',
                                  color: SnowColors.textSecondary,
                                ),
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
                  ],
                ),
              ),
            ),

            // E-5 quick copy — separate button apart from the overflow ⋯
            IconButton(
              tooltip: 'Copy address',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.copy_rounded,
                size: 18,
                color: SnowColors.textSecondary,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: entry.address));
                SnowToast.show(
                  context,
                  message: 'Address copied',
                  type: ToastType.info,
                );
              },
            ),
            // ⋯ overflow menu — Set Default / Rename / Hide / Remove
            PopupMenuButton<_RowAction>(
              tooltip: 'More',
              icon: const Icon(
                Icons.more_vert_rounded,
                size: 18,
                color: SnowColors.textSecondary,
              ),
              color: SnowColors.surfaceVariant,
              onSelected: (action) =>
                  _handleAction(context, ref, entry, action),
              itemBuilder: (_) => _menuItems(entry, isDefault),
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<_RowAction>> _menuItems(
    WalletEntry entry,
    bool isDefault,
  ) {
    final items = <PopupMenuEntry<_RowAction>>[];
    if (!isDefault) {
      items.add(
        const PopupMenuItem(
          value: _RowAction.setDefault,
          child: _MenuRow(
            icon: Icons.star_rounded,
            label: 'Set as Default',
            color: SnowColors.primary,
          ),
        ),
      );
    }
    items.add(
      const PopupMenuItem(
        value: _RowAction.rename,
        child: _MenuRow(
          icon: Icons.edit_rounded,
          label: 'Rename',
          color: SnowColors.textPrimary,
        ),
      ),
    );
    // Primary cannot be hidden / removed
    if (entry.role == WalletRole.primary) return items;

    if (entry.kind == WalletKind.derived) {
      items.add(
        const PopupMenuItem(
          value: _RowAction.hide,
          child: _MenuRow(
            icon: Icons.visibility_off_rounded,
            label: 'Hide Account',
            color: SnowColors.textSecondary,
          ),
        ),
      );
    }
    items.add(
      const PopupMenuItem(
        value: _RowAction.remove,
        child: _MenuRow(
          icon: Icons.delete_forever_rounded,
          label: 'Remove',
          color: SnowColors.error,
        ),
      ),
    );
    return items;
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    WalletEntry entry,
    _RowAction action,
  ) async {
    switch (action) {
      case _RowAction.setDefault:
        await showSetDefaultDialog(context, ref, entry);
      case _RowAction.rename:
        await showRenameDialog(context, ref, entry);
      case _RowAction.hide:
        await showHideDerivedDialog(context, ref, entry);
        if (context.mounted) Navigator.of(context).pop();
      case _RowAction.remove:
        // Phase 5-5 + 6-A: listing interlock + NFT count prefetch.
        // listing is a hard block (preCheck throws); NFT count drives the
        // dialog branch (derived → require type-DELETE, imported → show NFT
        // count). NFT lookup failure is fail-open (the listing check is
        // more critical).
        int nftCount = 0;
        try {
          nftCount = await ref
              .read(nftServiceProvider)
              .getNFTCount(entry.address);
        } catch (err) {
          // Proceed — derived gets simple confirm; imported gets only type-DELETE.
          // ignore: avoid_print
          // (debug only — noop in release builds)
        }

        await showRemoveWalletDialog(
          context,
          ref,
          entry,
          nftCount: nftCount,
          preCheck: (e) async {
            final rpc = ref.read(rpcClientProvider);
            List<String> mints;
            try {
              mints = await fetchActiveListingMintsForOwner(
                rpc: rpc,
                ownerAddress: e.address,
              );
            } catch (err) {
              throw const ActiveListingsBlockingException(
                'cannot verify marketplace listings (network error)',
              );
            }
            if (mints.isNotEmpty) {
              throw ActiveListingsBlockingException(
                '${mints.length} active marketplace listing(s) on this '
                'wallet',
              );
            }
          },
        );
        if (context.mounted) Navigator.of(context).pop();
    }
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

enum _RowAction { setDefault, rename, hide, remove }

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}
