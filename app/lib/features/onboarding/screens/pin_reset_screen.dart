/// @file        pin_reset_screen.dart
/// @description Forgotten-PIN screen, reached from the PIN lock screen. The
///              user proves the account with its recovery phrase — checked on
///              the device against the stored account key — and then sets a
///              new PIN. Nothing on the device is deleted: chats, keys and
///              groups stay as they are.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-22 (the new passcode takes a kind (Passcode options) and is stored by
///              PasscodeStore — salted Argon2id; the wrong-entry count is cleared). Earlier 2026-11-20
///
/// @functions
///  - PinResetScreen: two steps — recovery phrase, then the new PIN
///  - _parseWords(text): split the typed or pasted phrase into words
///  - _checkPhrase(): IdentityManager.matchesRecoveryPhrase(), then step two
///  - _setPin(): store the new PIN, unlock and open the chats
///
/// Notes:
///  - The phrase is only held in memory while it is checked; the text field
///    is cleared as soon as it matches. It is never logged.
///  - The phrase already gives full control of the account (it can restore
///    it on any device), so accepting it here gives an attacker nothing the
///    phrase did not already give.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/crypto/key_derivation.dart';
import '../../../core/security/passcode.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/toast.dart';
import '../widgets/passcode_input.dart';

class PinResetScreen extends ConsumerStatefulWidget {
  const PinResetScreen({super.key});

  @override
  ConsumerState<PinResetScreen> createState() => _PinResetScreenState();
}

class _PinResetScreenState extends ConsumerState<PinResetScreen> {
  final _phraseController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  List<String> _words = const [];
  bool _phraseConfirmed = false;
  bool _busy = false;
  String? _error;

  bool get _wordCountOk => _words.length == 12 || _words.length == 24;

  /// The kind of the new passcode ("Passcode options"; six digits first).
  PasscodeKind _kind = PasscodeKind.numeric6;

  bool get _pinOk {
    final pin = _pinController.text;
    return _kind.validate(pin) == null && pin == _pinConfirmController.text;
  }

  Future<void> _pickKind() async {
    final picked = await showPasscodeKindPicker(context, _kind);
    if (picked == null || picked == _kind || !mounted) return;
    setState(() {
      _kind = picked;
      _pinController.clear();
      _pinConfirmController.clear();
    });
  }

  @override
  void dispose() {
    _phraseController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  void _parseWords(String text) {
    setState(() {
      _words = text
          .trim()
          .split(RegExp(r'[\s,]+'))
          .where((w) => w.isNotEmpty)
          .map((w) => w.toLowerCase())
          .toList();
      _error = null;
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      if (mounted) {
        SnowToast.show(context, message: 'Clipboard is empty', type: ToastType.warning);
      }
      return;
    }
    _phraseController.text = text;
    _parseWords(text);
  }

  Future<void> _checkPhrase() async {
    if (!_wordCountOk || _busy) return;
    if (!KeyDerivation.isValidMnemonic(_words)) {
      setState(() => _error = 'These words are not a valid recovery phrase. Check each word.');
      return;
    }
    setState(() => _busy = true);
    final matches =
        await ref.read(identityManagerProvider).matchesRecoveryPhrase(_words);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (matches) {
        _phraseConfirmed = true;
        _phraseController.clear();
        _words = const [];
        _error = null;
      } else {
        _error = 'This recovery phrase belongs to a different account.';
      }
    });
  }

  Future<void> _setPin() async {
    if (!_pinOk || _busy) return;
    setState(() => _busy = true);
    // The account was proved with the recovery phrase: the wrong-entry count
    // goes with the old passcode.
    final store = ref.read(passcodeStoreProvider);
    await store.clearForReset();
    await store.set(_kind, _pinController.text);
    if (!mounted) return;
    ref.read(isLockedProvider.notifier).state = false;
    context.go('/chat');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/pin-login'),
        ),
        title: const Text('Reset passcode'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SnowSizes.lg),
                child: _phraseConfirmed ? _pinStep() : _phraseStep(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(SnowSizes.lg),
              child: SizedBox(
                width: double.infinity,
                child: _phraseConfirmed
                    ? _button('Set passcode', _pinOk && !_busy ? _setPin : null)
                    : _button('Continue', _wordCountOk && !_busy ? _checkPhrase : null),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phraseStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Enter your recovery phrase'),
        const SizedBox(height: SnowSizes.sm),
        _note(
          'Type or paste the 12 or 24 words of this account. They are checked '
          'on this device only. Your chats stay on this device.',
        ),
        const SizedBox(height: SnowSizes.lg),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _paste,
            icon: const Icon(Icons.paste_rounded, size: 20),
            label: const Text('Paste from Clipboard'),
            style: OutlinedButton.styleFrom(
              foregroundColor: SnowColors.primary,
              side: BorderSide(color: SnowColors.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: SnowSizes.lg),
        TextField(
          controller: _phraseController,
          onChanged: _parseWords,
          maxLines: 6,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(
            color: SnowColors.textPrimary,
            fontSize: 16,
            height: 1.8,
            fontFamily: 'monospace',
          ),
          decoration: _decoration(hint: 'word1 word2 word3 ...'),
        ),
        const SizedBox(height: SnowSizes.md),
        Text(
          '${_words.length} words${_wordCountOk ? '' : ' (12 or 24)'}',
          style: TextStyle(
            color: _wordCountOk ? SnowColors.primary : SnowColors.textTertiary,
            fontSize: 13,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: SnowSizes.md),
          Text(_error!, style: const TextStyle(color: SnowColors.error, fontSize: 13)),
        ],
      ],
    );
  }

  Widget _pinStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Choose a new passcode'),
        const SizedBox(height: SnowSizes.sm),
        _note('${passcodeHint(_kind)} It replaces the old passcode on this device.'),
        TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: _pickKind,
          child: const Text(
            'Passcode options',
            style: TextStyle(color: SnowColors.primary),
          ),
        ),
        const SizedBox(height: SnowSizes.sm),
        _pinField(_pinController, 'New passcode'),
        const SizedBox(height: SnowSizes.md),
        _pinField(
          _pinConfirmController,
          'Confirm new passcode',
          error: _pinConfirmController.text.isNotEmpty &&
                  _pinConfirmController.text != _pinController.text
              ? 'Passcodes do not match'
              : null,
        ),
      ],
    );
  }

  Widget _pinField(TextEditingController controller, String hint, {String? error}) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      obscureText: true,
      maxLength: _kind.maxLength,
      keyboardType: passcodeKeyboard(_kind),
      inputFormatters: passcodeFormatters(_kind),
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(color: SnowColors.textPrimary, fontSize: 20, letterSpacing: 8),
      decoration: _decoration(hint: hint, error: error),
    );
  }

  InputDecoration _decoration({required String hint, String? error}) {
    OutlineInputBorder border(Color? color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: color == null ? BorderSide.none : BorderSide(color: color, width: 1.5),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: SnowColors.textTertiary, letterSpacing: 0, fontSize: 14),
      counterStyle: const TextStyle(color: SnowColors.textTertiary, fontSize: 11),
      errorText: error,
      filled: true,
      fillColor: SnowColors.surfaceVariant,
      border: border(null),
      focusedBorder: border(SnowColors.primary),
      errorBorder: border(SnowColors.error),
      focusedErrorBorder: border(SnowColors.error),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _title(String text) => Text(
        text,
        style: const TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _note(String text) => Text(
        text,
        style: const TextStyle(color: SnowColors.textTertiary, fontSize: 14, height: 1.4),
      );

  Widget _button(String label, VoidCallback? onPressed) {
    final enabled = onPressed != null;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? SnowColors.primary : SnowColors.surfaceLight,
        foregroundColor: enabled ? SnowColors.background : SnowColors.textTertiary,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }
}
