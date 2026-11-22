/// @file        screen_driver.dart
/// @description What the on-device screen tests share: start the real app,
///              wait for what the screen shows, tap and type like a user,
///              and the few reads of the app's own state the tests check
///              against (the account, the database, the router).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-21 (pickAccount(): pick an account in a group picker — through the warning
///              when this user has not vouched for it). Earlier same day (write(): types into the input on screen — a text field of a route or
///              tab underneath is not it)
///
/// @functions
///  - ScreenDriver.start(): start the app and wait until it is signed in,
///    group protocol v2 runs, the socket is up and the Chats tab shows
///  - until() / see() / gone(): wait for a condition, or for something to
///    appear on screen or leave it
///  - tap() / scrollTo() / write(): act like a user
///  - pickAccount(): pick an account in a group picker (new group, add
///    members), showing the accounts not verified first when it is one
///  - sent(): wait until a message this account wrote reads "sent"
///  - groupTitled(): the v2 group with a name
///
/// Notes:
///  - "Shown" means on screen and on top: a widget of a route underneath,
///    or scrolled out of view, does not count.
///  - The PIN screen is a lock in front of a session that is already there;
///    the driver opens the Chats tab through the router instead of typing a
///    PIN (it holds none). Unlocking rebuilds the router, so it is read anew
///    at each use ([router]).
///  - Progress lines go to the device log through [say] — steps only, never
///    keys or group ids.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:snowchat/app/app.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/app/router.dart';
import 'package:snowchat/core/group_v2/gv2_store.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/features/group/widgets/account_picker_list.dart';
import 'package:snowchat/main.dart' as app;

class ScreenDriver {
  final WidgetTester tester;
  final void Function(String line) say;

  /// Time between two frames while waiting.
  static const Duration step = Duration(milliseconds: 400);

  late final ProviderContainer container;
  late final String me;

  ScreenDriver(this.tester, this.say);

  SnowDatabase get db => container.read(snowDatabaseProvider);
  Gv2Store get store => db.gv2Store;
  GoRouter router() => container.read(routerProvider);

  /// Start the app and wait until this install is signed in, group protocol
  /// v2 runs and the socket is up; then open the Chats tab.
  Future<void> start() async {
    app.main();
    await tester.pump(const Duration(seconds: 2));
    container = await until('the app is up', () {
      final found = find.byType(SnowChatApp);
      if (found.evaluate().isEmpty) return null;
      return ProviderScope.containerOf(tester.element(found));
    });
    me = await until(
      'an account is signed in',
      () => container.read(currentSnowIdProvider),
      within: const Duration(minutes: 2),
    );
    await until(
      'group protocol v2 is running',
      () => container.read(gv2RuntimeProvider),
    );
    await until(
      'the socket is connected',
      () => container.read(socketManagerProvider).isConnected ? true : null,
    );
    container.read(isLockedProvider.notifier).state = false;
    await tester.pump(step);
    router().go('/chat');
    await see('the Chats tab', find.text('SnowChat'));
  }

  /// Keep the app's frames going until [done] gives a value.
  Future<T> until<T>(
    String what,
    FutureOr<T?> Function() done, {
    Duration within = const Duration(minutes: 4),
  }) async {
    final deadline = DateTime.now().add(within);
    while (DateTime.now().isBefore(deadline)) {
      final value = await done();
      if (value != null) {
        say('ok: $what');
        return value;
      }
      await tester.pump(step);
      await Future<void>.delayed(step);
    }
    fail('timed out waiting for: $what');
  }

  bool shown(Finder finder) => finder.hitTestable().evaluate().isNotEmpty;

  Future<void> see(String what, Finder finder, {Duration? within}) => until(
    what,
    () => shown(finder) ? true : null,
    within: within ?? const Duration(minutes: 4),
  );

  Future<void> gone(String what, Finder finder, {Duration? within}) => until(
    what,
    () => shown(finder) ? null : true,
    within: within ?? const Duration(minutes: 4),
  );

  Future<void> tap(String what, Finder finder) async {
    await see('$what is on screen', finder, within: const Duration(minutes: 1));
    await tester.tap(finder.hitTestable().first);
    await tester.pump(step);
    say('tapped: $what');
  }

  /// Scroll the screen's list up until [target] is in view.
  Future<void> scrollTo(String what, Finder target) async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (var i = 0; i < 40 && !shown(target); i++) {
      await tester.dragFrom(
        Offset(size.width / 2, size.height * 0.6),
        Offset(0, -size.height * 0.3),
      );
      await tester.pump(step);
    }
    expect(shown(target), isTrue, reason: 'scrolled to: $what');
  }

  /// In a group picker: pick [snowId]. An account this user has not
  /// vouched for is listed only after the warning: those are shown first.
  Future<void> pickAccount(String what, String snowId) async {
    await see('the picker list', find.byType(AccountPickerList));
    final vouched = await container
        .read(verifiedIdentityStoreProvider)
        .isVouched(snowId);
    if (!vouched) {
      say('$what is not verified on this device');
      final reveal = find.textContaining("haven't verified");
      await scrollTo('the accounts not verified', reveal);
      await tap('show the accounts not verified', reveal);
      await tap('Show them', find.text('Show them'));
    }
    final row = find.text(accountShortId(snowId));
    await scrollTo(what, row);
    await tap(what, row);
  }

  /// Type [text] into the chat's input and send it.
  Future<void> write(String text) async {
    // The input on screen: a tab kept alive underneath (the Communities
    // tab's search field, an earlier chat) has text fields too.
    final input = find.byType(TextField);
    await see('the message input', input, within: const Duration(minutes: 1));
    say('text fields: ${input.hitTestable().evaluate().length} on screen, '
        '${input.evaluate().length} in all');
    await tester.enterText(input.hitTestable().first, text);
    await tester.pump(step);
    await tap('send', find.byIcon(Icons.send_rounded));
    await see('"$text" in the chat', find.text(text));
  }

  /// Wait until the row of the message [text] this account wrote in
  /// [groupId] reads "sent".
  Future<void> sent(String groupId, String text) => until<bool>(
    '"$text" was taken by the server',
    () async {
      final rows = await db.messageDao.getMessagesForConversation(groupId);
      return rows.any(
            (m) =>
                m.plaintext == text &&
                m.senderSnowchatId == me &&
                m.outgoingStatus == 'sent',
          )
          ? true
          : null;
    },
  );

  /// The v2 group named [name] on this device, or null.
  Future<Gv2GroupRow?> groupTitled(String name) async {
    for (final g in await store.groups()) {
      if (g.title == name) return g;
    }
    return null;
  }

  /// The texts of the messages stored for [groupId].
  Future<Set<String>> texts(String groupId) async => {
    for (final m in await db.messageDao.getMessagesForConversation(groupId))
      m.plaintext,
  };
}
