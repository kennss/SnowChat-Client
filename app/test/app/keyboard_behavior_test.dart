/// @file        keyboard_behavior_test.dart
/// @description keyboard_behavior.dart on iOS: a touch outside the focused text field closes
///              the keyboard (Flutter alone keeps the focus there on touch), a tap on a widget
///              in the field's TextFieldTapRegion keeps it, and a route change drops it.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - main(): the cases

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/app/keyboard_behavior.dart';

void main() {
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  Widget app(FocusNode node, {List<NavigatorObserver> observers = const []}) {
    return MaterialApp(
      navigatorObservers: observers,
      builder: (context, child) => DismissKeyboardOnTapOutside(child: child!),
      home: Scaffold(
        body: Column(
          children: [
            TextFieldTapRegion(
              child: Row(
                children: [
                  Expanded(child: TextField(focusNode: node)),
                  IconButton(
                    key: const Key('send'),
                    icon: const Icon(Icons.send),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(key: Key('outside'), height: 200, width: 200),
          ],
        ),
      ),
    );
  }

  testWidgets('a touch outside the field closes the keyboard', (tester) async {
    final node = FocusNode();
    await tester.pumpWidget(app(node));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(node.hasFocus, isTrue);
    await tester.tap(find.byKey(const Key('outside')));
    await tester.pump();
    expect(node.hasFocus, isFalse);
  }, variant: ios);

  testWidgets('a button in the field\'s tap region keeps it', (tester) async {
    final node = FocusNode();
    await tester.pumpWidget(app(node));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.byKey(const Key('send')));
    await tester.pump();
    expect(node.hasFocus, isTrue);
  }, variant: ios);

  testWidgets('a route change drops the focus', (tester) async {
    final node = FocusNode();
    await tester.pumpWidget(app(node, observers: [DismissKeyboardOnRouteChange()]));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(node.hasFocus, isTrue);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isFalse);
  }, variant: ios);
}
