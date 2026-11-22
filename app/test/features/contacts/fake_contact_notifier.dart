/// @file        fake_contact_notifier.dart
/// @description A ContactNotifier for widget tests: its rows are given by the test and every
///              action is recorded (method name and account) instead of touching a store, the
///              outbox or the server — the screens' tests check that each button calls the right
///              action.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (canBlock; atBlockLimit — blockContact throws BlockLimitReached)
///
/// @functions
///  - FakeContactNotifier: the recorded actions (calls), nameTakenBy's answer (takenBy), the
///    block cap (atBlockLimit)
///  - contactOf(): a Contact row for a test
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snowchat/core/blocking/block_list.dart' show BlockLimitReached;
import 'package:snowchat/core/contacts/contact_lookup.dart' show FoundAccount;
import 'package:snowchat/core/contacts/contact_store.dart';
import 'package:snowchat/features/contacts/contact_provider.dart';

/// A Contact row for a test.
Contact contactOf(
  String snowId, {
  String? name,
  ContactLabel? label,
  bool unavailable = false,
}) =>
    Contact(
      snowChatId: snowId,
      displayName: name,
      label: label,
      isUnavailable: unavailable,
      addedAt: DateTime(2026, 11, 22),
    );

class FakeContactNotifier extends StateNotifier<List<Contact>>
    implements ContactNotifier {
  FakeContactNotifier(super.state);

  /// Every action, as (method, account).
  final List<(String, String)> calls = [];

  /// What nameTakenBy answers.
  String? takenBy;

  /// The block list is full: canBlock says no, blockContact throws.
  bool atBlockLimit = false;

  @override
  Future<void> request(String snowId, {String? displayName}) async =>
      calls.add(('request', snowId));

  @override
  Future<void> requestFound(FoundAccount account) async =>
      calls.add(('requestFound', account.snowId));

  @override
  Future<void> accept(String snowId) async => calls.add(('accept', snowId));

  @override
  Future<void> decline(String snowId) async => calls.add(('decline', snowId));

  @override
  Future<void> remove(String snowId) async => calls.add(('remove', snowId));

  @override
  Future<void> resend(String snowId) async => calls.add(('resend', snowId));

  @override
  Future<String?> nameTakenBy(String name, String snowId) async => takenBy;

  @override
  Future<void> blockContact(String snowId) async {
    if (atBlockLimit) throw const BlockLimitReached();
    calls.add(('blockContact', snowId));
  }

  @override
  Future<bool> canBlock(String snowId) async => !atBlockLimit;

  @override
  Future<void> unblockContact(String snowId) async =>
      calls.add(('unblockContact', snowId));
}
