/// @file        contact_restore_notice.dart
/// @description The one-time notice after the contact restore of a new install (design
///              2026-11-22-friend-graph-off-server §5.10): a backup was found — "Friends restored
///              from a backup of (N days ago)" (the server may hand out an older backup, so its date
///              is shown) — or none — the friend list and the block list could not be restored. The
///              main shell shows it once; ContactBackup.dismissRestoreNotice() ends it.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (a backup that did not open has its own notice — nothing was restored or
///              overwritten — with "Try again"; showContactRestoreNotice() says whether to)
///
/// @functions
///  - contactBackupAge(): "today" / "yesterday" / "N days ago" for a backup's time
///  - contactRestoreNoticeTitle() / contactRestoreNoticeText(): what the notice says
///  - showContactRestoreNotice(): the notice as a dialog; true when the user asked to try again
library;

import 'package:flutter/material.dart';

import '../../../core/contacts/contact_backup.dart' show ContactRestoreReport;
import '../../../shared/constants/colors.dart';

/// How old a backup written at [savedAtMs] is at [nowMs], in whole days by
/// the calendar: "today", "yesterday", "N days ago". A time in the future
/// (another device's clock) reads "today".
String contactBackupAge(int savedAtMs, int nowMs) {
  final saved = DateTime.fromMillisecondsSinceEpoch(savedAtMs);
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(saved.year, saved.month, saved.day))
      .inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}

String contactRestoreNoticeTitle(ContactRestoreReport report) {
  if (report.unreadable) return 'Backup could not be opened';
  return report.found ? 'Friends restored' : 'No backup found';
}

/// What the notice says for [report] at [nowMs].
String contactRestoreNoticeText(ContactRestoreReport report, int nowMs) {
  if (report.unreadable) {
    return 'Your backup could not be opened, so your friends and blocked '
        'accounts were not restored. It is kept as it is — nothing is written '
        'over it — and tried again each time the app connects.';
  }
  final savedAtMs = report.savedAtMs;
  if (!report.found || savedAtMs == null) {
    return 'No backup found — your friends and blocked accounts could not be '
        'restored.';
  }
  return 'Friends restored from a backup of ${contactBackupAge(savedAtMs, nowMs)}. '
      'Changes made after that backup are not included.';
}

/// Show the notice for [report]; completes when the user closed it, with
/// true when they asked to try an unreadable backup again.
Future<bool> showContactRestoreNotice(
  BuildContext context,
  ContactRestoreReport report,
) async {
  final retry = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SnowColors.surface,
      title: Text(
        contactRestoreNoticeTitle(report),
        style: const TextStyle(color: SnowColors.textPrimary),
      ),
      content: Text(
        contactRestoreNoticeText(report, DateTime.now().millisecondsSinceEpoch),
        style: const TextStyle(color: SnowColors.textSecondary, height: 1.4),
      ),
      actions: [
        if (report.unreadable) ...[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Later',
                style: TextStyle(color: SnowColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Try again',
                style: TextStyle(color: SnowColors.primary)),
          ),
        ] else
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('OK', style: TextStyle(color: SnowColors.primary)),
          ),
      ],
    ),
  );
  return retry ?? false;
}
