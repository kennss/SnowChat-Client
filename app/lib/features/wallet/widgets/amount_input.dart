/// @file        amount_input.dart
/// @description Amount input widget with a custom numeric keypad (includes
///              USD conversion display).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - AmountInput: StatefulWidget with large amount display + numeric keypad
///  - AmountInputState: state management for AmountInput (exposes amount)

/// Phantom-style amount input with a custom numeric keypad.
library;

import 'package:flutter/material.dart';

abstract class _C {
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF5C5C5C);
}

/// Large amount display with a custom numeric keypad underneath.
class AmountInput extends StatefulWidget {
  const AmountInput({
    super.key,
    required this.symbol,
    this.usdRate,
    this.onAmountChanged,
    this.maxDecimals = 9,
  });

  /// Token symbol to show below the number (e.g. "SOL").
  final String symbol;

  /// USD per unit, for live conversion display. Null hides the USD line.
  final double? usdRate;

  /// Called whenever the amount string changes.
  final ValueChanged<String>? onAmountChanged;

  /// Maximum decimal places allowed.
  final int maxDecimals;

  @override
  State<AmountInput> createState() => AmountInputState();
}

class AmountInputState extends State<AmountInput> {
  String _amount = '0';

  /// Current amount string.
  String get amount => _amount;

  /// Programmatically set the amount (e.g., from Solana Pay URI prefill).
  void setAmount(String value) {
    setState(() {
      _amount = value.isEmpty ? '0' : value;
      widget.onAmountChanged?.call(_amount);
    });
  }

  void _onKey(String key) {
    setState(() {
      if (key == 'backspace') {
        if (_amount.length <= 1) {
          _amount = '0';
        } else {
          _amount = _amount.substring(0, _amount.length - 1);
        }
      } else if (key == '.') {
        if (!_amount.contains('.')) {
          _amount = '$_amount.';
        }
      } else {
        // Digit.
        if (_amount == '0' && key != '0') {
          _amount = key;
        } else if (_amount == '0' && key == '0') {
          // Don't add leading zeros.
        } else {
          // Enforce max decimals.
          if (_amount.contains('.')) {
            final fracLen = _amount.split('.')[1].length;
            if (fracLen >= widget.maxDecimals) return;
          }
          _amount += key;
        }
      }
      widget.onAmountChanged?.call(_amount);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Amount display.
        _buildAmountDisplay(),
        const SizedBox(height: 8),
        // Token symbol.
        Text(
          widget.symbol,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: _C.textSecondary,
          ),
        ),
        // USD conversion.
        if (widget.usdRate != null) ...[
          const SizedBox(height: 4),
          Text(
            _usdString(),
            style: const TextStyle(fontSize: 14, color: _C.textTertiary),
          ),
        ],
        const SizedBox(height: 24),
        // Keypad.
        _buildKeypad(),
      ],
    );
  }

  Widget _buildAmountDisplay() {
    // Auto-size the text to fit the screen width.
    final fontSize = _amount.length > 8 ? 36.0 : 48.0;
    return Text(
      _amount,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: _C.textPrimary,
        letterSpacing: -1,
      ),
      maxLines: 1,
    );
  }

  String _usdString() {
    final parsed = double.tryParse(_amount) ?? 0;
    final usd = parsed * (widget.usdRate ?? 0);
    return '~\$${usd.toStringAsFixed(2)}';
  }

  Widget _buildKeypad() {
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', 'backspace'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: keys.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((k) => _keyButton(k)).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _keyButton(String key) {
    final isBackspace = key == 'backspace';
    return Expanded(
      child: GestureDetector(
        onTap: () => _onKey(key),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          child: isBackspace
              ? const Icon(Icons.backspace_outlined, color: _C.textPrimary, size: 22)
              : Text(
                  key,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                    color: _C.textPrimary,
                  ),
                ),
        ),
      ),
    );
  }
}
