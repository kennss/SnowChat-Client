/// @file        restart_widget.dart
/// @description In-app full restart primitive. Wraps the root [ProviderScope]
///              in a keyed subtree; swapping the key tears down and rebuilds the
///              entire widget tree AND the ProviderScope, disposing every
///              provider (socket, timers, drift handle, all identity-scoped
///              in-memory state) and re-running app startup from scratch — the
///              same clean slate as a cold launch, without killing the process.
///              Used by "Reset App" / "Delete Account": clearing secure storage
///              and the drift file is not enough on its own because identity-
///              scoped providers (conversation list, contacts, channels, display
///              name) keep the previous account's data in memory until the next
///              cold start; restarting guarantees a freshly created identity
///              never sees the prior account's state in the same session.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-08-04
/// @lastUpdated 2026-08-04
///
/// @functions
///  - RestartWidget.restartApp(context): rebuild the whole app from the nearest RestartWidget ancestor
///  - _RestartWidgetState.restart(): swap the subtree key to force a full rebuild
import 'package:flutter/widgets.dart';

class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});

  final Widget child;

  /// Rebuild the entire app subtree (including the root ProviderScope) from the
  /// nearest [RestartWidget] ancestor of [context]. No-op if none is found.
  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restart();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  void restart() {
    setState(() => _key = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
