/// @file        change_passcode_screen.dart
/// @description Settings → Security → Change Passcode. The current passcode
///              first (checked by PasscodeStore — a wrong one counts toward
///              the wait like on the lock screen), then the new one of any
///              kind ("Passcode options") twice.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - ChangePasscodeScreen: the two steps
///  - _checkCurrent(): verify the current passcode
///  - _save(): store the new one
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/keyboard_behavior.dart';
import '../../../app/providers.dart';
import '../../../core/security/passcode.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../onboarding/widgets/passcode_input.dart';

class ChangePasscodeScreen extends ConsumerStatefulWidget {
  const ChangePasscodeScreen({super.key});

  @override
  ConsumerState<ChangePasscodeScreen> createState() =>
      _ChangePasscodeScreenState();
}

class _ChangePasscodeScreenState extends ConsumerState<ChangePasscodeScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  PasscodeKind _currentKind = PasscodeKind.numeric;
  PasscodeKind _kind = PasscodeKind.numeric6;
  bool _currentOk = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(passcodeStoreProvider).kind().then((kind) {
      if (mounted && kind != null) setState(() => _currentKind = kind);
    });
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _newOk =>
      _kind.validate(_next.text) == null && _next.text == _confirm.text;

  Future<void> _checkCurrent() async {
    if (_current.text.isEmpty || _busy) return;
    setState(() => _busy = true);
    final result = await ref.read(passcodeStoreProvider).check(_current.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _current.clear();
      switch (result) {
        case PasscodeAccepted():
          _currentOk = true;
          _error = null;
        case PasscodeRejected(:final wait, :final attemptsLeft):
          _error = wait > Duration.zero
              ? 'Too many attempts. Try again in ${_waitText(wait)}.'
              : 'Wrong passcode. $attemptsLeft '
                  '${attemptsLeft == 1 ? 'attempt' : 'attempts'} left.';
        case PasscodeLockedOut(:final wait):
          _error = 'Too many attempts. Try again in ${_waitText(wait)}.';
      }
    });
  }

  static String _waitText(Duration wait) => wait.inSeconds >= 60
      ? '${(wait.inSeconds / 60).ceil()} min'
      : '${wait.inSeconds} s';

  Future<void> _save() async {
    if (!_newOk || _busy) return;
    dismissKeyboard();
    setState(() => _busy = true);
    await ref.read(passcodeStoreProvider).set(_kind, _next.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Passcode changed')),
    );
    context.pop();
  }

  Future<void> _pickKind() async {
    final picked = await showPasscodeKindPicker(context, _kind);
    if (picked == null || picked == _kind || !mounted) return;
    setState(() {
      _kind = picked;
      _next.clear();
      _confirm.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(title: const Text('Change Passcode')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SnowSizes.lg),
          children: _currentOk ? _newStep() : _currentStep(),
        ),
      ),
    );
  }

  List<Widget> _currentStep() => [
        const Text(
          'Enter your current passcode',
          style: TextStyle(
            color: SnowColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: SnowSizes.md),
        _field(
          _current,
          'Current passcode',
          kind: _currentKind,
          onSubmitted: _checkCurrent,
        ),
        if (_error != null) ...[
          const SizedBox(height: SnowSizes.sm),
          Text(_error!, style: const TextStyle(color: SnowColors.error)),
        ],
        const SizedBox(height: SnowSizes.lg),
        ElevatedButton(
          onPressed: _busy ? null : _checkCurrent,
          child: const Text('Continue'),
        ),
      ];

  List<Widget> _newStep() => [
        const Text(
          'Choose a new passcode',
          style: TextStyle(
            color: SnowColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: SnowSizes.sm),
        Text(
          passcodeHint(_kind),
          style: const TextStyle(color: SnowColors.textTertiary, fontSize: 13),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: _pickKind,
            child: const Text(
              'Passcode options',
              style: TextStyle(color: SnowColors.primary),
            ),
          ),
        ),
        _field(_next, 'New passcode', kind: _kind),
        const SizedBox(height: SnowSizes.md),
        _field(
          _confirm,
          'Confirm new passcode',
          kind: _kind,
          error: _confirm.text.isNotEmpty && _confirm.text != _next.text
              ? 'Passcodes do not match'
              : null,
          onSubmitted: _save,
        ),
        const SizedBox(height: SnowSizes.lg),
        ElevatedButton(
          onPressed: _newOk && !_busy ? _save : null,
          child: const Text('Save'),
        ),
      ];

  Widget _field(
    TextEditingController controller,
    String hint, {
    required PasscodeKind kind,
    String? error,
    VoidCallback? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted(),
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      maxLength: kind.maxLength,
      keyboardType: passcodeKeyboard(kind),
      inputFormatters: passcodeFormatters(kind),
      style: const TextStyle(color: SnowColors.textPrimary, fontSize: 18),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: SnowColors.textTertiary),
        errorText: error,
        filled: true,
        fillColor: SnowColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
