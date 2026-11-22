/// @file        pin_reset_test.dart
/// @description A forgotten PIN is replaced after the account's recovery
///              phrase is proven on the device: IdentityManager
///              .matchesRecoveryPhrase() and the PinResetScreen flow — a
///              wrong or foreign phrase never reaches the new-PIN step and
///              never changes the PIN; the right one sets it and unlocks.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-22 (the new passcode goes through PasscodeStore (kind + passcode; six digits
///              by default); wording "passcode")
///
/// @functions
///  - main(): the cases above
///  - _Store: a PasscodeStore that records the passcodes set
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/core/crypto/identity_manager.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/security/passcode.dart';
import 'package:snowchat/features/onboarding/screens/pin_reset_screen.dart';

import '../../core/crypto/identity_test_support.dart';

/// Records the passcodes set (the real store keeps a salted Argon2id record).
class _Store extends PasscodeStore {
  _Store() : super(InMemorySecureStorage());
  final List<String> storedPins = [];
  int resets = 0;

  @override
  Future<void> set(PasscodeKind kind, String passcode) async =>
      storedPins.add('${kind.name}:$passcode');

  @override
  Future<void> clearForReset() async => resets++;
}

void main() {
  group('IdentityManager.matchesRecoveryPhrase', () {
    late InMemorySecureStorage storage;
    late IdentityManager identity;
    late List<String> phrase;

    setUp(() async {
      storage = InMemorySecureStorage();
      identity = IdentityManager(storage);
      phrase = await identity.createIdentity();
    });

    test('the account\'s own phrase matches', () async {
      expect(await identity.matchesRecoveryPhrase(phrase), isTrue);
    });

    test('a valid phrase of another account does not', () async {
      final other = KeyDerivation.generateMnemonic();
      expect(KeyDerivation.isValidMnemonic(other), isTrue);
      expect(await identity.matchesRecoveryPhrase(other), isFalse);
    });

    test('a phrase with one word changed, or the wrong length, does not',
        () async {
      final changed = [...phrase]..[0] = phrase[0] == 'abandon' ? 'ability' : 'abandon';
      expect(await identity.matchesRecoveryPhrase(changed), isFalse);
      expect(await identity.matchesRecoveryPhrase(phrase.sublist(0, 23)), isFalse);
      expect(await identity.matchesRecoveryPhrase(const []), isFalse);
    });

    test('a device without an account key matches nothing', () async {
      final empty = IdentityManager(InMemorySecureStorage());
      expect(await empty.matchesRecoveryPhrase(phrase), isFalse);
    });

    test('checking stores nothing', () async {
      final before = Map.of(storage.data);
      await identity.matchesRecoveryPhrase(phrase);
      await identity.matchesRecoveryPhrase(KeyDerivation.generateMnemonic());
      expect(storage.data, before);
    });
  });

  group('PinResetScreen', () {
    late _Store store;
    late InMemorySecureStorage storage;
    late IdentityManager identity;
    late List<String> phrase;

    setUp(() async {
      store = _Store();
      storage = InMemorySecureStorage();
      identity = IdentityManager(storage);
      phrase = await identity.createIdentity();
    });

    Future<ProviderContainer> open(WidgetTester tester) async {
      final container = ProviderContainer(overrides: [
        secureStorageProvider.overrideWithValue(storage),
        identityManagerProvider.overrideWithValue(identity),
        passcodeStoreProvider.overrideWithValue(store),
      ]);
      container.read(isLockedProvider.notifier).state = true;
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/pin-reset',
        routes: [
          GoRoute(path: '/pin-reset', builder: (_, _) => const PinResetScreen()),
          GoRoute(path: '/pin-login', builder: (_, _) => const Text('LOCK SCREEN')),
          GoRoute(path: '/chat', builder: (_, _) => const Text('CHATS')),
        ],
      );
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      return container;
    }

    Future<void> enterPhrase(WidgetTester tester, List<String> words) async {
      await tester.enterText(find.byType(TextField), words.join(' '));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Continue'));
        // The check derives the key (PBKDF2 + SLIP-0010) for real.
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('a phrase of another account is refused and the PIN is kept',
        (tester) async {
      final container = await open(tester);
      await enterPhrase(tester, KeyDerivation.generateMnemonic());
      expect(find.text('This recovery phrase belongs to a different account.'),
          findsOneWidget);
      expect(find.text('Choose a new passcode'), findsNothing);
      expect(store.storedPins, isEmpty);
      expect(container.read(isLockedProvider), isTrue);
    });

    testWidgets('words that are not a recovery phrase are refused',
        (tester) async {
      await open(tester);
      final wrong = List.filled(12, 'snow');
      await enterPhrase(tester, wrong);
      expect(find.textContaining('not a valid recovery phrase'), findsOneWidget);
      expect(store.storedPins, isEmpty);
    });

    testWidgets('the right phrase leads to a new PIN, which unlocks the app',
        (tester) async {
      final container = await open(tester);
      await enterPhrase(tester, phrase);
      expect(find.text('Choose a new passcode'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '246810');
      await tester.enterText(fields.at(1), '246800');
      await tester.pump();
      expect(find.text('Passcodes do not match'), findsOneWidget);
      await tester.tap(find.text('Set passcode'));
      await tester.pump();
      expect(store.storedPins, isEmpty);

      // Four digits are not a six-digit code.
      await tester.enterText(fields.at(0), '2468');
      await tester.enterText(fields.at(1), '2468');
      await tester.pump();
      await tester.tap(find.text('Set passcode'));
      await tester.pump();
      expect(store.storedPins, isEmpty);

      await tester.enterText(fields.at(0), '246810');
      await tester.enterText(fields.at(1), '246810');
      await tester.pump();
      await tester.tap(find.text('Set passcode'));
      await tester.pumpAndSettle();
      expect(store.storedPins, ['numeric6:246810']);
      expect(store.resets, 1);
      expect(container.read(isLockedProvider), isFalse);
      expect(find.text('CHATS'), findsOneWidget);
    });

    testWidgets('back returns to the lock screen without changing anything',
        (tester) async {
      final container = await open(tester);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('LOCK SCREEN'), findsOneWidget);
      expect(store.storedPins, isEmpty);
      expect(container.read(isLockedProvider), isTrue);
    });
  });
}
