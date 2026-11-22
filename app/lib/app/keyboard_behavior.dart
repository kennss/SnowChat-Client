/// @file        keyboard_behavior.dart
/// @description App-wide keyboard behavior. On iOS, Flutter keeps a text field
///              focused when a touch lands outside it (the framework unfocuses
///              on touch only on the web), and the iPhone number pad has no key
///              that closes it — so a PIN keypad could not be put away at all,
///              and after a screen change it could stay over the next screen.
///              Here: a tap outside the focused field closes the keyboard (the
///              iOS convention), and every route change drops the focus.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - DismissKeyboardOnTapOutside: overrides EditableTextTapOutsideIntent to unfocus on touch too
///  - DismissKeyboardOnRouteChange: NavigatorObserver that unfocuses on push / pop / replace / remove
///  - dismissKeyboard(): drop the primary focus (closes the keyboard)
///
/// Notes:
///  - A widget that belongs to a field (a send button beside the chat input)
///    is kept "inside" by wrapping it in TextFieldTapRegion together with the
///    field — a tap there does not close the keyboard.
library;

import 'package:flutter/material.dart';

/// Drop the primary focus, which closes the keyboard.
void dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

/// Wraps the app (MaterialApp.builder): a pointer down outside the focused
/// text field's tap region unfocuses it, on touch as well. Flutter's own
/// default does that only for mouse / stylus on mobile platforms.
class DismissKeyboardOnTapOutside extends StatelessWidget {
  const DismissKeyboardOnTapOutside({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        EditableTextTapOutsideIntent:
            CallbackAction<EditableTextTapOutsideIntent>(
          onInvoke: (intent) {
            intent.focusNode.unfocus();
            return null;
          },
        ),
      },
      child: child,
    );
  }
}

/// Drops the focus whenever the route stack changes, so a keyboard opened on
/// one screen never stays over the next one. A field the new screen focuses
/// itself (autofocus) does so after this, in its first frame.
class DismissKeyboardOnRouteChange extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      dismissKeyboard();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      dismissKeyboard();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      dismissKeyboard();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      dismissKeyboard();
}
