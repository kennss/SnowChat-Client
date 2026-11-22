/// @file        contact_sync_runner.dart
/// @description Runs the contact backup while an account is signed in (design
///              2026-11-22-friend-graph-off-server §5.10): ContactBackup.sync() at start, on every
///              connect, when the next write comes due, and when a block / unblock made it due
///              sooner. One run at a time — a call during a run makes one more run after it — and
///              one timer, cancelled when the runner is disposed.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - ContactSyncRunner.start(): follow the connection and run once
///  - ContactSyncRunner.run(): one sync now (or right after the running one), then wait for the
///    next due write
///  - ContactSyncRunner.dispose(): stop — no timer, no subscription, no further run
///
/// Notes:
///  - The wait is never shorter than [ContactSyncRunner.minDelay], so a sync the server keeps
///    refusing is not tried in a loop.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'contact_backup.dart';

class ContactSyncRunner {
  final ContactBackup _backup;
  final Stream<bool> _connectionChanges;
  final int Function() _nowMs;

  /// The shortest wait before the timer runs a sync.
  final Duration minDelay;

  ContactSyncRunner({
    required ContactBackup backup,
    required Stream<bool> connectionChanges,
    int Function()? nowMs,
    this.minDelay = const Duration(minutes: 1),
  })  : _backup = backup,
        _connectionChanges = connectionChanges,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  StreamSubscription<bool>? _connection;
  Timer? _timer;
  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;

  /// Follow the connection (a connect runs a sync), let a block or an
  /// unblock that moved the next write closer run one, and run one now.
  void start() {
    if (_disposed || _connection != null) return;
    _connection = _connectionChanges.listen((connected) {
      if (connected) unawaited(run());
    });
    _backup.onWriteDueChanged = () => unawaited(run());
    unawaited(run());
  }

  /// One sync, then the timer for the next due write. A call while a sync
  /// runs makes exactly one more after it (and returns the running one).
  Future<void> run() {
    if (_disposed) return Future<void>.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final done = _runOnce().whenComplete(() {
      _running = null;
      if (_again && !_disposed) {
        _again = false;
        unawaited(run());
      }
    });
    _running = done;
    return done;
  }

  Future<void> _runOnce() async {
    _timer?.cancel();
    _timer = null;
    var delay = minDelay;
    try {
      await _backup.sync();
      if (_disposed) return;
      final dueAt = await _backup.nextWriteAtMs();
      final untilDue = Duration(milliseconds: dueAt - _nowMs());
      if (untilDue > delay) delay = untilDue;
    } catch (e) {
      // The database could not be read: tried again after the shortest wait.
      debugPrint('[ContactSync] run failed: ${e.runtimeType}');
    }
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(run()));
  }

  /// Stop: the timer and the subscription go, and no run starts after.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_connection?.cancel());
    _connection = null;
    _backup.onWriteDueChanged = null;
  }
}
