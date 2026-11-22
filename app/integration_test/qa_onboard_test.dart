/// @file        qa_onboard_test.dart
/// @description QA helper: gives a fresh install an account through the
///              app's own onboarding screens — Welcome → "Create New
///              Identity" → nickname and PIN → the identity is made and
///              registered → "Skip for now" → Chats. For a test device
///              that has none (the account is a dev-server test account).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-20
///
/// @functions
///  - main(): one test
///
/// Notes:
///  - `--dart-define=QA_NICKNAME=<2..20 characters>` and
///    `--dart-define=QA_PIN=<4..6 digits>`.
///  - An install that already has an account is left as it is: the test
///    stops with a message and changes nothing.
///  - The recovery phrase is never printed. By default it is not shown or
///    copied either ("Skip for now"). With `--dart-define=QA_BACKUP=true`
///    the user's own backup flow is taken instead: reveal the phrase, "Copy
///    All Words" (the device's clipboard — on a simulator it outlives the
///    app, so a reinstall test can paste it back), "I've Written It Down",
///    and the three words the app asks for are typed from the clipboard.
///  - It prints the steps and the new account's snowId only.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:snowchat/app/app.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/main.dart' as app;

const _nickname = String.fromEnvironment('QA_NICKNAME');
const _pin = String.fromEnvironment('QA_PIN');
const _backup = bool.fromEnvironment('QA_BACKUP');
const _step = Duration(milliseconds: 400);

void _say(String line) {
  // The test's own progress lines (read from the device log).
  // ignore: avoid_print
  print('QAONBOARD $line');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboard a fresh install', (tester) async {
    expect(_nickname.length, inInclusiveRange(2, 20), reason: 'QA_NICKNAME');
    expect(RegExp(r'^\d{4,6}$').hasMatch(_pin), isTrue, reason: 'QA_PIN');

    app.main();
    await tester.pump(const Duration(seconds: 2));

    Future<T> until<T>(
      String what,
      FutureOr<T?> Function() done, {
      Duration within = const Duration(minutes: 3),
    }) async {
      final deadline = DateTime.now().add(within);
      while (DateTime.now().isBefore(deadline)) {
        final value = await done();
        if (value != null) {
          _say('ok: $what');
          return value;
        }
        await tester.pump(_step);
        await Future<void>.delayed(_step);
      }
      fail('timed out waiting for: $what');
    }

    bool shown(Finder f) => f.hitTestable().evaluate().isNotEmpty;
    Future<void> tap(String what, Finder f) async {
      await until('$what is on screen', () => shown(f) ? true : null);
      await tester.tap(f.hitTestable().first);
      await tester.pump(_step);
      _say('tapped: $what');
    }

    final container = await until('the app is up', () {
      final found = find.byType(SnowChatApp);
      if (found.evaluate().isEmpty) return null;
      return ProviderScope.containerOf(tester.element(found));
    });

    final where = await until('the first screen', () {
      if (shown(find.text('Create New Identity'))) return 'welcome';
      if (container.read(currentSnowIdProvider) != null) return 'account';
      return null;
    });
    if (where == 'account') {
      _say('this install already has an account — nothing done');
      return;
    }

    await tap('Create New Identity', find.text('Create New Identity'));
    final fields = find.byType(TextField);
    await until('the profile form', () => fields.evaluate().length >= 3 ? true : null);
    await tester.enterText(fields.at(0), _nickname);
    await tester.pump(_step);
    await tester.enterText(fields.at(1), _pin);
    await tester.pump(_step);
    await tester.enterText(fields.at(2), _pin);
    await tester.pump(_step);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(_step);
    await tap('Continue', find.text('Continue'));

    await until(
      'the identity is made and registered',
      () => shown(find.text('Skip for now')) ? true : null,
    );
    if (!_backup) {
      await tap('Skip for now', find.text('Skip for now'));
    } else {
      await tap(
        'Back Up Recovery Phrase',
        find.text('Back Up Recovery Phrase'),
      );
      await tap(
        'reveal',
        find.text('Tap to reveal your recovery phrase'),
      );
      await tap('Copy All Words', find.text('Copy All Words'));
      final words = (await Clipboard.getData(Clipboard.kTextPlain))
              ?.text
              ?.trim()
              .split(RegExp(r'\s+')) ??
          const <String>[];
      expect(words.length == 12 || words.length == 24, isTrue,
          reason: 'the phrase is on the clipboard');
      await tap("I've Written It Down", find.text("I've Written It Down"));
      // The screen asks for three of the words, by their place.
      final asked = await until('the words asked for', () {
        final fields = find.byType(TextField).evaluate().toList();
        return fields.length >= 3 ? fields.length : null;
      });
      for (var i = 0; i < asked; i++) {
        final field = find.byType(TextField).at(i);
        final hint = (tester.widget<TextField>(field).decoration?.hintText) ?? '';
        final n = int.parse(RegExp(r'(\d+)').firstMatch(hint)!.group(1)!);
        await tester.enterText(field, words[n - 1]);
        await tester.pump(_step);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(_step);
      await tap('Complete Setup', find.text('Complete Setup'));
    }
    final me = await until(
      'an account is signed in',
      () => container.read(currentSnowIdProvider),
    );
    _say('snowId=$me');
    _say('PASS');
  });
}
