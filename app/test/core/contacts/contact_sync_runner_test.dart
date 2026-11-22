/// @file        contact_sync_runner_test.dart
/// @description ContactSyncRunner (review fix 13): one sync at a time — calls during a run make
///              exactly one more run after it, never two at once; one timer, armed for the next
///              due write (never sooner than the shortest wait) and replaced, not added to, on
///              every run; a connect and a write made due sooner (ContactBackup.onWriteDueChanged)
///              run a sync; after dispose no timer fires and nothing runs.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - _Backup: a ContactBackup whose sync the test holds open and counts
///  - main(): the cases above
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/contacts/contact_backup.dart';
import 'package:snowchat/core/contacts/contact_sync_runner.dart';

class _Backup extends Fake implements ContactBackup {
  int syncs = 0;
  int running = 0;
  int maxRunning = 0;

  /// When set, a sync waits for it.
  Completer<void>? gate;

  /// The next due write (ms, the fake clock).
  int dueAtMs = 0;

  @override
  void Function()? onWriteDueChanged;

  @override
  Future<bool> sync() async {
    syncs++;
    running++;
    if (running > maxRunning) maxRunning = running;
    await gate?.future;
    running--;
    return true;
  }

  @override
  Future<int> nextWriteAtMs() async => dueAtMs;
}

void main() {
  test('calls during a run make exactly one more run after it, never two at '
      'once', () {
    fakeAsync((async) {
      final backup = _Backup()..gate = Completer<void>();
      final connection = StreamController<bool>.broadcast();
      final runner = ContactSyncRunner(
        backup: backup,
        connectionChanges: connection.stream,
        nowMs: () => async.elapsed.inMilliseconds,
      )..start();
      async.flushMicrotasks();
      expect(backup.syncs, 1);
      // A connect and two due changes while the first sync runs.
      connection.add(true);
      backup.onWriteDueChanged!();
      unawaited(runner.run());
      async.flushMicrotasks();
      expect(backup.syncs, 1);
      backup.gate!.complete();
      backup.gate = null;
      async.flushMicrotasks();
      expect(backup.syncs, 2, reason: 'one more run for all of them');
      expect(backup.maxRunning, 1);
      runner.dispose();
      unawaited(connection.close());
    });
  });

  test('one timer for the next due write, never sooner than the shortest '
      'wait; each run replaces it', () {
    fakeAsync((async) {
      final backup = _Backup()..dueAtMs = const Duration(hours: 2).inMilliseconds;
      final runner = ContactSyncRunner(
        backup: backup,
        connectionChanges: const Stream<bool>.empty(),
        nowMs: () => async.elapsed.inMilliseconds,
      )..start();
      async.flushMicrotasks();
      expect(backup.syncs, 1);
      expect(async.pendingTimers, hasLength(1));
      // Three more runs: still one timer.
      for (var i = 0; i < 3; i++) {
        unawaited(runner.run());
        async.flushMicrotasks();
      }
      expect(backup.syncs, 4);
      expect(async.pendingTimers, hasLength(1));
      async.elapse(const Duration(hours: 2));
      expect(backup.syncs, 5, reason: 'the timer ran the due write');
      // A due time already past: the shortest wait, not a loop.
      backup.dueAtMs = 0;
      unawaited(runner.run());
      async.flushMicrotasks();
      final before = backup.syncs;
      async.elapse(const Duration(seconds: 59));
      expect(backup.syncs, before);
      async.elapse(const Duration(seconds: 1));
      expect(backup.syncs, before + 1);
      runner.dispose();
    });
  });

  test('after dispose: no timer fires, nothing runs, the backup hook is '
      'released', () {
    fakeAsync((async) {
      final backup = _Backup()..dueAtMs = const Duration(minutes: 5).inMilliseconds;
      final connection = StreamController<bool>.broadcast();
      final runner = ContactSyncRunner(
        backup: backup,
        connectionChanges: connection.stream,
        nowMs: () => async.elapsed.inMilliseconds,
      )..start();
      async.flushMicrotasks();
      runner.dispose();
      expect(backup.onWriteDueChanged, isNull);
      expect(async.pendingTimers, isEmpty);
      connection.add(true);
      unawaited(runner.run());
      async.elapse(const Duration(hours: 1));
      expect(backup.syncs, 1);
      unawaited(connection.close());
    });
  });
}
