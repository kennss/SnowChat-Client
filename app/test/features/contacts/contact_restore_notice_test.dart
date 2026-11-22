/// @file        contact_restore_notice_test.dart
/// @description The one-time notice after a fresh-install restore (design
///              2026-11-22-friend-graph-off-server §5.10): a backup found — "Friends restored from a
///              backup of (today / yesterday / N days ago)"; none — "No backup found — your friends
///              and blocked accounts could not be restored."; the dialog shows the text and closes
///              on OK. A backup that did not open has its own notice — nothing restored, nothing
///              written over it — with Later / Try again (the dialog says which).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (the notice of a backup that did not open)
///
/// @functions
///  - main(): the cases above
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/contacts/contact_backup.dart' show ContactRestoreReport;
import 'package:snowchat/features/contacts/widgets/contact_restore_notice.dart';

void main() {
  final now = DateTime(2026, 11, 22, 9).millisecondsSinceEpoch;
  int daysAgo(int days, {int hour = 23}) =>
      DateTime(2026, 11, 22 - days, hour).millisecondsSinceEpoch;

  test('the backup\'s age, by calendar day', () {
    expect(contactBackupAge(daysAgo(0, hour: 1), now), 'today');
    expect(contactBackupAge(daysAgo(1), now), 'yesterday');
    expect(contactBackupAge(daysAgo(3), now), '3 days ago');
    // Another device's clock ahead of this one.
    expect(contactBackupAge(now + 3600000, now), 'today');
  });

  test('a backup found: restored, with its age', () {
    final report = ContactRestoreReport(found: true, savedAtMs: daysAgo(3));
    expect(contactRestoreNoticeTitle(report), 'Friends restored');
    expect(contactRestoreNoticeText(report, now),
        startsWith('Friends restored from a backup of 3 days ago.'));
  });

  test('no backup found: friends and blocked accounts not restored', () {
    const report = ContactRestoreReport(found: false);
    expect(contactRestoreNoticeTitle(report), 'No backup found');
    expect(contactRestoreNoticeText(report, now),
        'No backup found — your friends and blocked accounts could not be '
        'restored.');
  });

  testWidgets('the dialog shows the text and closes on OK', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    var closed = false;
    showContactRestoreNotice(ctx, const ContactRestoreReport(found: false))
        .then((_) => closed = true);
    await tester.pumpAndSettle();
    expect(find.text('No backup found'), findsOneWidget);
    expect(find.textContaining('could not be restored'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(find.text('No backup found'), findsNothing);
  });

  test('a backup that did not open: its own notice', () {
    const report = ContactRestoreReport(found: false, unreadable: true);
    expect(contactRestoreNoticeTitle(report), 'Backup could not be opened');
    expect(contactRestoreNoticeText(report, now), contains('could not be opened'));
    expect(contactRestoreNoticeText(report, now), contains('nothing is written'));
  });

  testWidgets('the unreadable notice: Try again answers true, Later false',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    const report = ContactRestoreReport(found: false, unreadable: true);
    bool? answer;
    showContactRestoreNotice(ctx, report).then((v) => answer = v);
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
    showContactRestoreNotice(ctx, report).then((v) => answer = v);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
