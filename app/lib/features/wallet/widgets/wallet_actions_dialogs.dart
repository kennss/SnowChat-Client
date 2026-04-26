/// @file        wallet_actions_dialogs.dart
/// @description Multi-Wallet dialog set invoked from the selector row —
///              Set Default (A-4 biometric), Rename, Hide derived, Remove
///              (D-1 NFT check hook + D-4 typing-DELETE for imported +
///              biometric). Multi-Wallet-Design-FINAL.md §4.3 / §4.4.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - showSetDefaultDialog(context, ref, entry): biometric → setDefault
///  - showRenameDialog(context, ref, entry): label input → renameWallet
///  - showHideDerivedDialog(context, ref, entry): confirm → hideDerivedWallet
///  - showRemoveWalletDialog(context, ref, entry): kind-based confirm branch

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/widgets/toast.dart';
import '../models/wallet_account_model.dart';
import '../models/wallet_index_exceptions.dart';
import '../wallet_provider.dart';

// ---------------------------------------------------------------------------
// Set as Default — A-4 biometric gate
// ---------------------------------------------------------------------------

Future<void> showSetDefaultDialog(
  BuildContext context,
  WidgetRef ref,
  WalletEntry entry,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: SnowColors.surface,
      title: const Text(
        'Set as Default?',
        style: TextStyle(color: SnowColors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Friends sending to you will see this address:',
            style: const TextStyle(color: SnowColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SelectableText(
            entry.address,
            style: const TextStyle(
              color: SnowColors.textPrimary,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Marketplace buy/list will use ${entry.label} by default '
            '(you can change per-tx).',
            style: const TextStyle(color: SnowColors.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dctx).pop(true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  final auth = await _runBiometric(
    context,
    'Confirm to set ${entry.label} as default',
  );
  if (!auth) return;

  try {
    await ref
        .read(walletProvider.notifier)
        .setDefault(entry.id, biometricOk: true);
    if (context.mounted) {
      SnowToast.show(
        context,
        message: '${entry.label} is now your default wallet',
        type: ToastType.success,
      );
    }
  } catch (e) {
    if (context.mounted) {
      SnowToast.show(
        context,
        message: 'Failed: $e',
        type: ToastType.error,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Rename
// ---------------------------------------------------------------------------

Future<void> showRenameDialog(
  BuildContext context,
  WidgetRef ref,
  WalletEntry entry,
) async {
  final controller = TextEditingController(text: entry.label);

  final newLabel = await showDialog<String>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: SnowColors.surface,
      title: const Text(
        'Rename Wallet',
        style: TextStyle(color: SnowColors.textPrimary),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        style: const TextStyle(color: SnowColors.textPrimary),
        decoration: InputDecoration(
          labelText: 'Label',
          labelStyle: const TextStyle(color: SnowColors.textTertiary),
          filled: true,
          fillColor: SnowColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dctx).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (newLabel == null || newLabel.isEmpty) return;

  try {
    await ref
        .read(walletProvider.notifier)
        .renameWallet(entry.id, newLabel);
    if (context.mounted) {
      SnowToast.show(
        context,
        message: 'Renamed to "$newLabel"',
        type: ToastType.success,
      );
    }
  } catch (e) {
    if (context.mounted) {
      SnowToast.show(context, message: '$e', type: ToastType.error);
    }
  }
}

// ---------------------------------------------------------------------------
// Hide derived
// ---------------------------------------------------------------------------

Future<void> showHideDerivedDialog(
  BuildContext context,
  WidgetRef ref,
  WalletEntry entry,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: SnowColors.surface,
      title: const Text(
        'Hide Account?',
        style: TextStyle(color: SnowColors.textPrimary),
      ),
      content: Text(
        '${entry.label} will be hidden from the wallet list. '
        'Funds remain on chain — you can unhide later from Settings.',
        style: const TextStyle(color: SnowColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dctx).pop(true),
          child: const Text('Hide'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  try {
    await ref
        .read(walletProvider.notifier)
        .hideDerivedWallet(entry.id);
    if (context.mounted) {
      SnowToast.show(
        context,
        message: '${entry.label} hidden',
        type: ToastType.info,
      );
    }
  } catch (e) {
    if (context.mounted) {
      SnowToast.show(context, message: '$e', type: ToastType.error);
    }
  }
}

// ---------------------------------------------------------------------------
// Remove (imported = typing-DELETE + biometric / derived = simple confirm)
// ---------------------------------------------------------------------------

/// preCheck callback — Phase 5 will inject NFT/listing verification here.
/// In Phase 3 only the sendlock check happens inside WalletNotifier.removeWallet.
typedef WalletRemovePreCheck = Future<void> Function(WalletEntry entry);

Future<void> showRemoveWalletDialog(
  BuildContext context,
  WidgetRef ref,
  WalletEntry entry, {
  WalletRemovePreCheck? preCheck,
  int nftCount = 0,
}) async {
  if (entry.kind == WalletKind.imported) {
    await _showImportedRemoveDialog(context, ref, entry, preCheck, nftCount);
  } else {
    await _showDerivedRemoveDialog(context, ref, entry, preCheck, nftCount);
  }
}

Future<void> _showDerivedRemoveDialog(
  BuildContext context,
  WidgetRef ref,
  WalletEntry entry,
  WalletRemovePreCheck? preCheck,
  int nftCount,
) async {
  // Phase 6-A — D-1: derived also requires type-DELETE + recommends Hide when holding NFTs.
  if (nftCount > 0) {
    await _showDerivedRemoveWithNftDialog(
      context,
      ref,
      entry,
      preCheck,
      nftCount,
    );
    return;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: SnowColors.surface,
      title: const Text(
        'Remove Account?',
        style: TextStyle(color: SnowColors.textPrimary),
      ),
      content: Text(
        '${entry.label} will be removed from the wallet list. '
        'Because this is a derived account, the same address can be '
        're-derived later by adding a new account — your funds are safe.',
        style: const TextStyle(color: SnowColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: SnowColors.error),
          onPressed: () => Navigator.of(dctx).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  await _doRemove(context, ref, entry, preCheck);
}

/// Derived + NFT-holding case (Phase 6-A). Requires type-DELETE + recommends Hide.
Future<void> _showDerivedRemoveWithNftDialog(
  BuildContext context,
  WidgetRef ref,
  WalletEntry entry,
  WalletRemovePreCheck? preCheck,
  int nftCount,
) async {
  final controller = TextEditingController();
  bool typedMatch = false;

  final result = await showDialog<_DerivedNftAction>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          backgroundColor: SnowColors.surface,
          title: const Text(
            'Account Holds NFTs',
            style: TextStyle(color: SnowColors.warning),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${entry.label} currently holds $nftCount NFT(s). '
                'Hiding keeps your funds and NFTs safe — they will '
                'reappear when you re-add this account. Removing '
                'will only hide it from the list (the chain still '
                'shows your NFTs), but you must type the wallet '
                'label to confirm.',
                style: const TextStyle(
                  color: SnowColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Type the wallet label to confirm removal:',
                style: const TextStyle(
                  color: SnowColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(
                entry.label,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                style: const TextStyle(color: SnowColors.textPrimary),
                onChanged: (v) =>
                    setState(() => typedMatch = v.trim() == entry.label),
                decoration: InputDecoration(
                  hintText: 'Type "${entry.label}"',
                  hintStyle: TextStyle(
                    color: SnowColors.textTertiary.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: SnowColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dctx).pop(_DerivedNftAction.cancel),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SnowColors.primary,
              ),
              onPressed: () =>
                  Navigator.of(dctx).pop(_DerivedNftAction.hide),
              child: const Text('Hide instead'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SnowColors.error,
              ),
              onPressed: typedMatch
                  ? () => Navigator.of(dctx).pop(_DerivedNftAction.remove)
                  : null,
              child: const Text('Remove'),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();

  switch (result) {
    case null:
    case _DerivedNftAction.cancel:
      return;
    case _DerivedNftAction.hide:
      try {
        await ref
            .read(walletProvider.notifier)
            .hideDerivedWallet(entry.id);
        if (context.mounted) {
          SnowToast.show(
            context,
            message: '${entry.label} hidden',
            type: ToastType.info,
          );
        }
      } catch (e) {
        if (context.mounted) {
          SnowToast.show(context, message: '$e', type: ToastType.error);
        }
      }
    case _DerivedNftAction.remove:
      await _doRemove(context, ref, entry, preCheck);
  }
}

enum _DerivedNftAction { cancel, hide, remove }

Future<void> _showImportedRemoveDialog(
  BuildContext context,
  WidgetRef ref,
  WalletEntry entry,
  WalletRemovePreCheck? preCheck,
  int nftCount,
) async {
  final controller = TextEditingController();
  bool typedMatch = false;

  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          backgroundColor: SnowColors.surface,
          title: const Text(
            'Remove Imported Wallet?',
            style: TextStyle(color: SnowColors.error),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nftCount > 0
                    ? 'This is an imported wallet holding $nftCount '
                        'NFT(s) — its private key will be permanently '
                        'deleted from this device. NFTs remain on chain '
                        'but unrecoverable without external backup.'
                    : 'This is an imported wallet — its private key will '
                        'be permanently deleted from this device. If you '
                        'have no external backup, this action is '
                        'irreversible.',
                style: const TextStyle(color: SnowColors.error, height: 1.4),
              ),
              const SizedBox(height: 12),
              Text(
                'Type the wallet label below to confirm:',
                style: const TextStyle(color: SnowColors.textSecondary),
              ),
              const SizedBox(height: 6),
              SelectableText(
                entry.label,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: SnowColors.textPrimary),
                onChanged: (v) =>
                    setState(() => typedMatch = v.trim() == entry.label),
                decoration: InputDecoration(
                  hintText: 'Type "${entry.label}"',
                  hintStyle: TextStyle(
                    color: SnowColors.textTertiary.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: SnowColors.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SnowColors.error,
              ),
              onPressed:
                  typedMatch ? () => Navigator.of(dctx).pop(true) : null,
              child: const Text('Delete Forever'),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
  if (ok != true) return;

  // Imported = additional biometric (D-1)
  final auth = await _runBiometric(
    context,
    'Confirm permanent removal of ${entry.label}',
  );
  if (!auth) return;

  await _doRemove(context, ref, entry, preCheck);
}

Future<void> _doRemove(
  BuildContext context,
  WidgetRef ref,
  WalletEntry entry,
  WalletRemovePreCheck? preCheck,
) async {
  try {
    await ref
        .read(walletProvider.notifier)
        .removeWallet(entry.id, preCheck: preCheck);
    if (context.mounted) {
      SnowToast.show(
        context,
        message: '${entry.label} removed',
        type: ToastType.info,
      );
    }
  } on CannotRemovePrimaryException catch (e) {
    if (context.mounted) {
      SnowToast.show(context, message: e.message, type: ToastType.error);
    }
  } on InFlightTransactionException catch (e) {
    if (context.mounted) {
      SnowToast.show(context, message: e.message, type: ToastType.warning);
    }
  } on ActiveListingsBlockingException catch (e) {
    if (context.mounted) {
      SnowToast.show(context, message: e.message, type: ToastType.warning);
    }
  } catch (e) {
    if (context.mounted) {
      SnowToast.show(
        context,
        message: 'Remove failed: $e',
        type: ToastType.error,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Biometric
// ---------------------------------------------------------------------------

Future<bool> _runBiometric(BuildContext context, String reason) async {
  final auth = LocalAuthentication();
  try {
    final canCheck = await auth.canCheckBiometrics;
    if (!canCheck) return true;
    final ok = await auth.authenticate(
      localizedReason: reason,
      options: const AuthenticationOptions(
        biometricOnly: false,
        stickyAuth: true,
      ),
    );
    if (!ok && context.mounted) {
      SnowToast.show(
        context,
        message: 'Authentication cancelled',
        type: ToastType.warning,
      );
    }
    return ok;
  } catch (e) {
    if (context.mounted) {
      SnowToast.show(
        context,
        message: 'Biometric error: $e',
        type: ToastType.error,
      );
    }
    return false;
  }
}
