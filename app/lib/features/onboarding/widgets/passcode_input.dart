/// @file        passcode_input.dart
/// @description What every screen that sets a passcode shares (sign-up, reset
///              with the recovery phrase, change in settings): the "Passcode
///              options" sheet (six digits / custom numeric / custom
///              alphanumeric, like iOS) and, per kind, the keyboard, the input
///              filter, the length cap and the hint line.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - showPasscodeKindPicker(): the options sheet; the chosen kind or null
///  - passcodeKeyboard() / passcodeFormatters() / passcodeHint(): per-kind input settings
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/security/passcode.dart';
import '../../../shared/constants/colors.dart';

/// The keyboard for a passcode of [kind].
TextInputType passcodeKeyboard(PasscodeKind kind) =>
    kind.isNumeric ? TextInputType.number : TextInputType.visiblePassword;

/// Input filters for a passcode of [kind] (digits only for the numeric ones).
List<TextInputFormatter> passcodeFormatters(PasscodeKind kind) => [
      if (kind.isNumeric) FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(kind.maxLength),
    ];

/// The line under the title that says what to enter.
String passcodeHint(PasscodeKind kind) => switch (kind) {
      PasscodeKind.numeric6 => 'Choose 6 digits.',
      PasscodeKind.numeric =>
        'Choose ${kind.minLength}–${kind.maxLength} digits.',
      PasscodeKind.alphanumeric =>
        'Choose ${kind.minLength}–${kind.maxLength} characters — letters, digits or symbols.',
    };

/// The "Passcode options" sheet. Returns the kind the user picked, or null
/// when the sheet was dismissed.
Future<PasscodeKind?> showPasscodeKindPicker(
  BuildContext context,
  PasscodeKind current,
) {
  return showModalBottomSheet<PasscodeKind>(
    context: context,
    backgroundColor: SnowColors.surface,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          for (final kind in PasscodeKind.values)
            ListTile(
              title: Text(
                kind.label,
                style: const TextStyle(color: SnowColors.textPrimary),
              ),
              subtitle: Text(
                passcodeHint(kind),
                style: const TextStyle(color: SnowColors.textTertiary),
              ),
              trailing: kind == current
                  ? const Icon(Icons.check_rounded, color: SnowColors.primary)
                  : null,
              onTap: () => Navigator.of(ctx).pop(kind),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
