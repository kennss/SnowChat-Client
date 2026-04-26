/// @file        add_wallet_sheet.dart
/// @description Multi-Wallet "Add Wallet" bottom sheet — 3-option entry:
///                1. Add Account (derived sub, [WalletNotifier.addDerivedWallet])
///                2. Import Recovery Phrase (mnemonic, C-1 self-reject)
///                3. Import Private Key (32-byte seed, I-2/I-8 + biometric)
///              Multi-Wallet-Design-FINAL.md §4.2.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - showAddWalletSheet(context): bottom sheet entry
///  - AddWalletSheet: ConsumerWidget — option-selection screen
///  - showAddDerivedFlow / showImportMnemonicFlow / showImportPrivateKeyFlow

library;

import 'dart:convert' show base64Decode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/toast.dart';
import '../models/wallet_index_exceptions.dart';
import '../wallet_provider.dart';

Future<void> showAddWalletSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: SnowColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const AddWalletSheet(),
  );
}

class AddWalletSheet extends ConsumerWidget {
  const AddWalletSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 16),
              child: Text(
                'Add Wallet',
                style: TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _OptionTile(
              icon: Icons.account_tree_rounded,
              iconColor: SnowColors.primaryDim,
              title: 'Add Account',
              subtitle:
                  'Create a new sub-wallet from your recovery phrase '
                  '(BIP44 next index)',
              onTap: () async {
                // Phase 3 fix: ref disposes after sheet pop, so capture
                // notifier first (Bad state: Cannot use ref after disposed).
                final notifier = ref.read(walletProvider.notifier);
                Navigator.of(context).pop();
                await _runAddDerivedFlow(context, notifier);
              },
            ),
            const SizedBox(height: SnowSizes.sm),
            _OptionTile(
              icon: Icons.text_snippet_rounded,
              iconColor: SnowColors.warning,
              title: 'Import Recovery Phrase',
              subtitle:
                  'Add an existing wallet using its 12 or 24-word phrase',
              onTap: () async {
                final notifier = ref.read(walletProvider.notifier);
                Navigator.of(context).pop();
                await _showImportMnemonicSheet(context, notifier);
              },
            ),
            const SizedBox(height: SnowSizes.sm),
            _OptionTile(
              icon: Icons.key_rounded,
              iconColor: SnowColors.warning,
              title: 'Import Private Key',
              subtitle:
                  'Solana private key only (32-byte Ed25519 seed). '
                  'Other chains may cause fund loss.',
              onTap: () async {
                final notifier = ref.read(walletProvider.notifier);
                Navigator.of(context).pop();
                await _showImportPrivateKeySheet(context, notifier);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SnowColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: SnowColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: SnowColors.textTertiary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: SnowColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Derived (no input — confirm dialog only)
// ---------------------------------------------------------------------------

Future<void> _runAddDerivedFlow(
  BuildContext context,
  WalletNotifier notifier,
) async {
  // Just a short confirm — derived re-derives on the fly from mnemonic, no extra input
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: SnowColors.surface,
      title: const Text(
        'Add new account?',
        style: TextStyle(color: SnowColors.textPrimary),
      ),
      content: const Text(
        'A new sub-wallet will be created from your recovery phrase '
        '(next available account index). You can hide it later, but '
        'the same address can always be re-derived.',
        style: TextStyle(color: SnowColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  try {
    final id = await notifier.addDerivedWallet();
    if (context.mounted) {
      SnowToast.show(
        context,
        message: 'New account added',
        type: ToastType.success,
      );
    }
    // ignore: unused_local_variable
    final _ = id;
  } on DerivedLimitExceededException catch (e) {
    if (context.mounted) {
      SnowToast.show(context, message: e.message, type: ToastType.warning);
    }
  } on IdentityMnemonicMissingException catch (e) {
    if (context.mounted) {
      SnowToast.show(context, message: e.message, type: ToastType.error);
    }
  } catch (e) {
    if (context.mounted) {
      SnowToast.show(
        context,
        message: 'Failed to add account: $e',
        type: ToastType.error,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Import Mnemonic
// ---------------------------------------------------------------------------

Future<void> _showImportMnemonicSheet(
  BuildContext context,
  WalletNotifier notifier,
) async {
  final controller = TextEditingController();
  final labelController = TextEditingController();
  String? error;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: SnowColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return Padding(
            padding: EdgeInsets.only(
              left: SnowSizes.lg,
              right: SnowSizes.lg,
              top: SnowSizes.md,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + SnowSizes.lg,
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
                const Text(
                  'Import Recovery Phrase',
                  style: TextStyle(
                    color: SnowColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Paste 12 or 24 words separated by spaces. account 0 will '
                  'be derived.',
                  style: TextStyle(
                    color: SnowColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: SnowSizes.md),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  style: const TextStyle(
                    color: SnowColors.textPrimary,
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'word1 word2 word3 …',
                    hintStyle: TextStyle(
                      color: SnowColors.textTertiary.withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: SnowColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: SnowSizes.md),
                TextField(
                  controller: labelController,
                  style: const TextStyle(color: SnowColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Label (optional)',
                    labelStyle: const TextStyle(
                      color: SnowColors.textTertiary,
                    ),
                    hintText: 'Trading',
                    hintStyle: TextStyle(
                      color: SnowColors.textTertiary.withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: SnowColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: SnowSizes.sm),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: SnowColors.error,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: SnowSizes.lg),
                FilledButton(
                  onPressed: () async {
                    final mnemonic = controller.text.trim();
                    if (mnemonic.isEmpty) {
                      setState(() => error = 'Please paste a recovery phrase.');
                      return;
                    }
                    final ok =
                        await _runBiometric(ctx, 'Import wallet from phrase');
                    if (!ok) return;

                    try {
                      await notifier.importWalletFromMnemonic(
                        mnemonic,
                        label: labelController.text.trim().isEmpty
                            ? null
                            : labelController.text.trim(),
                      );
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (context.mounted) {
                        SnowToast.show(
                          context,
                          message: 'Wallet imported',
                          type: ToastType.success,
                        );
                      }
                    } on SelfImportRejectedException catch (e) {
                      setState(() => error = e.message);
                    } on DuplicateWalletException catch (e) {
                      setState(() => error = e.message);
                    } on ImportLimitExceededException catch (e) {
                      setState(() => error = e.message);
                    } catch (e) {
                      setState(() => error = 'Import failed: $e');
                    }
                  },
                  child: const Text('Import'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  controller.dispose();
  labelController.dispose();
}

// ---------------------------------------------------------------------------
// Import Private Key
// ---------------------------------------------------------------------------

Future<void> _showImportPrivateKeySheet(
  BuildContext context,
  WalletNotifier notifier,
) async {
  final controller = TextEditingController();
  final labelController = TextEditingController();
  bool confirmed = false;
  String? error;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: SnowColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return Padding(
            padding: EdgeInsets.only(
              left: SnowSizes.lg,
              right: SnowSizes.lg,
              top: SnowSizes.md,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + SnowSizes.lg,
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
                const Text(
                  'Import Private Key',
                  style: TextStyle(
                    color: SnowColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: SnowSizes.sm),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SnowColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_rounded,
                        color: SnowColors.error,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Solana private key only (32-byte Ed25519 seed). '
                          'Importing keys from other chains (BTC, ETH) may '
                          'cause permanent fund loss.',
                          style: TextStyle(
                            color: SnowColors.error,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SnowSizes.md),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: confirmed,
                  onChanged: (v) => setState(() => confirmed = v ?? false),
                  activeColor: SnowColors.primary,
                  title: const Text(
                    'I confirm this is a Solana private key',
                    style: TextStyle(
                      color: SnowColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: SnowSizes.sm),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  style: const TextStyle(
                    color: SnowColors.textPrimary,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Base58 (86-88 chars) or Base64 (44 chars) Ed25519 '
                        'seed',
                    hintStyle: TextStyle(
                      color: SnowColors.textTertiary.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                    filled: true,
                    fillColor: SnowColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: SnowSizes.md),
                TextField(
                  controller: labelController,
                  style: const TextStyle(color: SnowColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Label (optional)',
                    labelStyle: const TextStyle(
                      color: SnowColors.textTertiary,
                    ),
                    hintText: 'Trading',
                    hintStyle: TextStyle(
                      color: SnowColors.textTertiary.withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: SnowColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: SnowSizes.sm),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: SnowColors.error,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: SnowSizes.lg),
                FilledButton(
                  onPressed: !confirmed
                      ? null
                      : () async {
                          final raw = controller.text.trim();
                          if (raw.isEmpty) {
                            setState(() => error = 'Paste your private key.');
                            return;
                          }
                          Uint8List? secret;
                          try {
                            secret = _decodePrivateKey(raw);
                          } catch (e) {
                            setState(
                                () => error = 'Invalid key encoding: $e');
                            return;
                          }
                          if (secret.length != 32) {
                            setState(() => error =
                                'Private key must be 32 bytes (got ${secret!.length}).');
                            return;
                          }

                          final ok = await _runBiometric(
                              ctx, 'Import wallet from private key');
                          if (!ok) return;

                          try {
                            await notifier.importWalletFromPrivateKey(
                              secret,
                              label: labelController.text.trim().isEmpty
                                  ? null
                                  : labelController.text.trim(),
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (context.mounted) {
                              SnowToast.show(
                                context,
                                message: 'Wallet imported',
                                type: ToastType.success,
                              );
                            }
                            // I-8: clear clipboard (safety after the user paste)
                            await Clipboard.setData(
                                const ClipboardData(text: ''));
                          } on SelfImportRejectedException catch (e) {
                            setState(() => error = e.message);
                          } on DuplicateWalletException catch (e) {
                            setState(() => error = e.message);
                          } on InvalidPrivateKeyException catch (e) {
                            setState(() => error = e.message);
                          } on ImportLimitExceededException catch (e) {
                            setState(() => error = e.message);
                          } catch (e) {
                            setState(() => error = 'Import failed: $e');
                          }
                        },
                  child: const Text('Import'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
  controller.dispose();
  labelController.dispose();
}

/// Parse a 32-byte or 64-byte (Phantom-style: secret + public concat)
/// private key. For 64-byte input, use only the first 32 bytes (seed).
Uint8List _decodePrivateKey(String raw) {
  // Try Base58 (Solana standard serialization — 86-88 chars for 64-byte, 44 for 32)
  try {
    final bytes = _decodeBase58(raw);
    return bytes.length == 64
        ? Uint8List.fromList(bytes.sublist(0, 32))
        : Uint8List.fromList(bytes);
  } catch (_) {
    // Base64 fallback
    final bytes = base64Decode(raw);
    return bytes.length == 64
        ? Uint8List.fromList(bytes.sublist(0, 32))
        : Uint8List.fromList(bytes);
  }
}

/// Standard Base58 (Bitcoin alphabet) decoder — Solana keypair JSON.
Uint8List _decodeBase58(String s) {
  const alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  final indexes = <int, int>{
    for (var i = 0; i < alphabet.length; i++) alphabet.codeUnitAt(i): i,
  };
  if (s.isEmpty) return Uint8List(0);

  // Count leading '1's (=> leading zero bytes)
  var zeros = 0;
  while (zeros < s.length && s.codeUnitAt(zeros) == 0x31) {
    zeros++;
  }

  final input58 = List<int>.filled(s.length, 0);
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final idx = indexes[c];
    if (idx == null) {
      throw FormatException('Invalid base58 character: ${s[i]}');
    }
    input58[i] = idx;
  }

  final decoded = List<int>.filled(s.length, 0);
  var outputStart = decoded.length;

  for (var inputStart = zeros; inputStart < s.length;) {
    decoded[--outputStart] = _divmod(input58, inputStart, 58, 256);
    if (input58[inputStart] == 0) inputStart++;
  }

  while (outputStart < decoded.length && decoded[outputStart] == 0) {
    outputStart++;
  }

  final result = List<int>.filled(zeros + (decoded.length - outputStart), 0);
  for (var i = 0; i < decoded.length - outputStart; i++) {
    result[zeros + i] = decoded[outputStart + i];
  }
  return Uint8List.fromList(result);
}

int _divmod(List<int> number, int firstDigit, int base, int divisor) {
  var remainder = 0;
  for (var i = firstDigit; i < number.length; i++) {
    final digit = number[i] & 0xFF;
    final temp = remainder * base + digit;
    number[i] = temp ~/ divisor;
    remainder = temp % divisor;
  }
  return remainder;
}

// ---------------------------------------------------------------------------
// Biometric (A-4)
// ---------------------------------------------------------------------------

Future<bool> _runBiometric(BuildContext context, String reason) async {
  final auth = LocalAuthentication();
  try {
    final canCheck = await auth.canCheckBiometrics;
    if (!canCheck) return true; // Pass if device doesn't support it (UX fallback)
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

