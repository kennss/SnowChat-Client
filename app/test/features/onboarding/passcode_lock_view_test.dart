/// @file        passcode_lock_view_test.dart
/// @description PasscodeLockView: the input follows the stored kind (a six-digit
///              code submits on the sixth digit; a custom numeric code waits
///              for OK; a letters code uses a text field), the entry is checked
///              exactly once per submit, a wrong entry says how many attempts
///              are left, and biometric unlock (when on) opens without an entry.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - _Store: a PasscodeStore that records each check (no KDF)
///  - _Storage: in-memory storage with the settings the screen reads
///  - main(): the cases

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/core/security/passcode.dart';
import 'package:snowchat/features/onboarding/screens/pin_login_screen.dart';

import '../../core/crypto/identity_test_support.dart';

class _Storage extends InMemorySecureStorage {
  _Storage({this.biometric = false});
  final bool biometric;

  @override
  Future<String?> getPreferredLanguage() async => null;
  @override
  Future<bool> getCallAlwaysRelay() async => false;
  @override
  Future<bool> getCallRequirePin() async => false;
  @override
  Future<bool> getBiometricLock() async => biometric;
  @override
  Future<int?> getAutoLockSeconds() async => null;
  @override
  Future<String?> getDisplayName() async => 'x1alice';
}

class _Store extends PasscodeStore {
  _Store(this._kind, this._right) : super(InMemorySecureStorage());
  final PasscodeKind _kind;
  final String _right;
  final checked = <String>[];
  int _wrong = 0;

  @override
  Future<PasscodeKind?> kind() async => _kind;

  @override
  Future<Duration> lockedFor() async => Duration.zero;

  @override
  Future<PasscodeCheck> check(String entry) async {
    checked.add(entry);
    if (entry == _right) return const PasscodeAccepted();
    _wrong++;
    return PasscodeRejected(wait: Duration.zero, attemptsLeft: 5 - _wrong);
  }
}

void main() {
  Future<({_Store store, List<String> events})> pump(
    WidgetTester tester,
    PasscodeKind kind,
    String right, {
    bool biometric = false,
    Future<bool> Function()? biometrics,
  }) async {
    final store = _Store(kind, right);
    final events = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(_Storage(biometric: biometric)),
          passcodeStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          home: PasscodeLockView(
            onUnlocked: () => events.add('unlocked'),
            onForgot: () => events.add('forgot'),
            biometrics: biometrics,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (store: store, events: events);
  }

  Future<void> digits(WidgetTester tester, String value) async {
    for (final d in value.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
  }

  testWidgets('six digits: submitted once, on the sixth', (tester) async {
    final r = await pump(tester, PasscodeKind.numeric6, '123456');
    await digits(tester, '12345');
    expect(r.store.checked, isEmpty, reason: 'no check before the sixth digit');
    await digits(tester, '6');
    await tester.pumpAndSettle();
    expect(r.store.checked, ['123456']);
    expect(r.events, ['unlocked']);
  });

  testWidgets('custom numeric: waits for OK, then checks once', (tester) async {
    final r = await pump(tester, PasscodeKind.numeric, '12345678');
    await digits(tester, '12345678');
    expect(r.store.checked, isEmpty);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(r.store.checked, ['12345678']);
    expect(r.events, ['unlocked']);
  });

  testWidgets('letters: a text field, checked once on submit', (tester) async {
    final r = await pump(tester, PasscodeKind.alphanumeric, 'Snow-chat9');
    expect(find.text('1'), findsNothing, reason: 'no keypad for letters');
    await tester.enterText(find.byKey(const Key('passcode-text')), 'Snow-chat9');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(r.store.checked, ['Snow-chat9']);
    expect(r.events, ['unlocked']);
  });

  testWidgets('a wrong entry says how many attempts are left', (tester) async {
    final r = await pump(tester, PasscodeKind.numeric6, '123456');
    await digits(tester, '000000');
    await tester.pumpAndSettle();
    expect(r.store.checked, ['000000']);
    expect(r.events, isEmpty);
    expect(find.text('Wrong passcode. 4 attempts left.'), findsOneWidget);
  });

  testWidgets('biometric unlock opens without an entry', (tester) async {
    final r = await pump(
      tester,
      PasscodeKind.numeric6,
      '123456',
      biometric: true,
      biometrics: () async => true,
    );
    expect(r.store.checked, isEmpty);
    expect(r.events, ['unlocked']);
  });

  testWidgets('biometrics off: no biometric prompt', (tester) async {
    var asked = false;
    final r = await pump(
      tester,
      PasscodeKind.numeric6,
      '123456',
      biometrics: () async => asked = true,
    );
    expect(asked, isFalse);
    expect(r.events, isEmpty);
  });
}
