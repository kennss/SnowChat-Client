/// @file        contact_provider.dart
/// @description The friend list for the screens (design 2026-11-22-friend-graph-off-server §5).
///              The list lives on this device (ContactStore, core/contacts) — nothing is read from
///              the server: no GET /users, no PERSONAL channel. This file maps the rows to what the
///              screens show and is the one place their actions go through: request / accept /
///              decline / remove / resend, block / unblock (the row goes, the identity record is
///              purged, the block list and its backup follow), and the names of accounts.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-22 (blockContact: its queued notices and messages leave the outbox, the
///              block list takes the account — what it sends is refused from then on — and only then
///              does its row go, so an in-flight notice cannot bring the row back; canBlock() / blockLimitText — the 5,000-account cap). Earlier 2026-11-22 (Contact.isUnavailable — sends the server refused again and again as
///              not existing; nameTakenBy also looks at the 1:1 chats' names). Earlier 2026-11-22
///              (friend graph off the server: the contact list is this device's
///              ContactStore — contactProvider maps its visible rows (friends, sent and received
///              requests) and carries the actions; friendsProvider / sentRequestsProvider /
///              receivedRequestsProvider; blockedContactsProvider names blocked accounts from this
///              device's rows (no GET /users/blocked); no profile_updated listener).
///              Earlier 2026-11-21 (X1: block / unblock go through BlockList). Earlier 2026-11-10
///              (B-2: identity purge uses VerifiedIdentityStore.remove). Earlier 2026-08-03 (privacy:
///              no user_registered blind-add). Earlier 2026-04-26 (header + inline English translation)
///
/// @functions
///  - Contact: what the screens show for a row (or for a blocked account)
///  - contactEntriesProvider: every row of the list, hidden ones included (ContactEntry)
///  - contactProvider: StateNotifierProvider — the visible rows as Contact, plus the actions
///  - ContactNotifier.request() / requestFound() / accept() / decline() / remove() / resend()
///  - ContactNotifier.blockContact() / unblockContact(): block / unblock an account
///  - ContactNotifier.canBlock(): whether one more account can be blocked (the cap)
///  - blockLimitText: what the screens say when the cap is reached
///  - ContactNotifier.nameTakenBy(): another account in the list or the 1:1 chats with the same
///    name
///  - friendsProvider / sentRequestsProvider / receivedRequestsProvider: the rows by label
///  - blockedContactsProvider: this device's blocked accounts with their kept names
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/blocking/block_list.dart' show BlockLimitReached;
import '../../core/contacts/contact_lookup.dart' show FoundAccount;
import '../../core/contacts/contact_store.dart';
import '../../core/crypto/identity_binding.dart';

/// What the screens say when this user blocked [BlockList.maxBlocked]
/// accounts already (BlockLimitReached).
const String blockLimitText =
    'You have blocked 5,000 accounts, the most there can be. Unblock one first.';

/// What the screens show for an account of the list (or a blocked one).
class Contact {
  final String snowChatId;

  /// The name from the account's name certificate (or the lookup), or null.
  final String? displayName;

  /// friend / request sent / request received; null for a blocked account.
  final ContactLabel? label;

  final bool isBlocked;

  /// The server refused sends to the account as not existing, again and
  /// again (ContactEntry.isUnavailable): "Account unavailable".
  final bool isUnavailable;

  /// When the row was made on this device.
  final DateTime addedAt;

  const Contact({
    required this.snowChatId,
    this.displayName,
    this.label,
    this.isBlocked = false,
    this.isUnavailable = false,
    required this.addedAt,
  });

  factory Contact.fromEntry(ContactEntry e) => Contact(
        snowChatId: e.snowId,
        displayName: e.nickname,
        label: e.label,
        isUnavailable: e.isUnavailable,
        addedAt: DateTime.fromMillisecondsSinceEpoch(e.createdAtMs),
      );

  /// Both added each other.
  bool get isFriend => label == ContactLabel.friend;

  /// This user added the account (a friend or a sent request).
  bool get inMyList =>
      label == ContactLabel.friend || label == ContactLabel.requestSent;
}

/// Every row of the list, hidden ones included, as it changes.
final contactEntriesProvider = StreamProvider<List<ContactEntry>>(
  (ref) => ref.watch(contactStoreProvider).watch(),
);

final contactProvider =
    StateNotifierProvider<ContactNotifier, List<Contact>>((ref) {
  return ContactNotifier(ref);
});

/// The visible rows of the list (friends, sent requests, received requests
/// that were not declined) and the actions on them.
class ContactNotifier extends StateNotifier<List<Contact>> {
  final Ref _ref;
  StreamSubscription<List<ContactEntry>>? _rows;

  ContactNotifier(this._ref) : super(const []) {
    _rows = _ref.read(contactStoreProvider).watch().listen((rows) {
      state = [
        for (final r in rows)
          if (r.isVisible) Contact.fromEntry(r),
      ];
    });
  }

  @override
  void dispose() {
    _rows?.cancel();
    super.dispose();
  }

  ContactStore get _store => _ref.read(contactStoreProvider);

  /// Send a friend request to [snowId] (typed, scanned or from a link). The
  /// account is added to this user's list at once ("request sent" — or
  /// "friend" when it had added this user) and vouched for; a sealed
  /// contact_added goes out through the outbox.
  Future<void> request(String snowId, {String? displayName}) async {
    await _store.request(snowId, nickname: displayName);
    await _ref.read(nameCertServiceProvider).nameOf(snowId);
  }

  /// Send a friend request to an account a lookup found (its account key
  /// was checked to derive its snowId; it is kept with the row).
  Future<void> requestFound(FoundAccount account) async {
    await _store.request(
      account.snowId,
      accountPub: account.accountPub,
      nickname: account.displayName,
    );
    await _ref.read(nameCertServiceProvider).nameOf(account.snowId);
  }

  /// Accept [snowId]'s request (= add it too).
  Future<void> accept(String snowId) => _store.accept(snowId);

  /// Decline [snowId]'s request: hidden here, nothing sent.
  Future<void> decline(String snowId) => _store.decline(snowId);

  /// Cancel a request to [snowId], or remove the friend.
  Future<void> remove(String snowId) => _store.remove(snowId);

  /// Send the request (or the acceptance) to [snowId] again.
  Future<void> resend(String snowId) => _store.resend(snowId);

  /// Another account than [snowId] that the list or a chat knows under
  /// [name], or null — the add screen warns about it (a server can answer
  /// a nickname with another account, §5.1). Looks at the list's names, the
  /// names from certificates and the 1:1 chats' names (a 1:1 room's id is
  /// the peer's snowId).
  Future<String?> nameTakenBy(String name, String snowId) async {
    final others = await _ref.read(contactDaoProvider).accountsNamed(name);
    final known = others.where((id) => id != snowId).firstOrNull;
    if (known != null) return known;
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return null;
    for (final c in await _ref.read(conversationDaoProvider).getAllConversations()) {
      if (c.id != snowId &&
          IdentityBindingV1.isValidSnowId(c.id) &&
          c.title?.trim().toLowerCase() == lower) {
        return c.id;
      }
    }
    return null;
  }

  /// Block [snowId]. Whatever this device still had queued for it leaves
  /// the outbox first (nothing more is sent to it); then the block list
  /// takes it (this device at once — what it sends is refused from then on
  /// — then the server's tag; the backup follows); only then does its row go
  /// from the list and its identity record get purged, so a notice of it
  /// already on its way cannot bring the row back. Throws BlockLimitReached
  /// at the cap ([blockLimitText]) — nothing changed then.
  Future<void> blockContact(String snowId) async {
    final blocks = _ref.read(blockListProvider);
    if (!await blocks.canBlock(snowId)) throw const BlockLimitReached();
    final name = await _ref.read(nameCertServiceProvider).resolveName(snowId);
    await _ref.read(directOutboxProvider).dropPeer(snowId);
    await blocks.block(snowId, nickname: name);
    await _store.forget(snowId);
    _purgeIdentityState(snowId);
  }

  /// Whether one more account can be blocked (or [snowId] is blocked
  /// already).
  Future<bool> canBlock(String snowId) =>
      _ref.read(blockListProvider).canBlock(snowId);

  /// Unblock [snowId] (what it sent meanwhile does not come back; its row
  /// does not come back either).
  Future<void> unblockContact(String snowId) =>
      _ref.read(blockListProvider).unblock(snowId);

  /// P2: clean up the identity record + Safety Number verification row, so
  /// a later contact with the account starts as a clean first encounter.
  void _purgeIdentityState(String snowChatId) {
    if (snowChatId.isEmpty) return;
    Future.microtask(() async {
      try {
        // B-2: drop the identity record (the bound latch is kept).
        await _ref.read(verifiedIdentityStoreProvider).remove(snowChatId);
        await _ref.read(identityVerificationDaoProvider).deleteByPeer(snowChatId);
      } catch (e) {
        debugPrint('[ContactNotifier] _purgeIdentityState failed: ${e.runtimeType}');
      }
    });
  }
}

/// Friends (both added each other).
final friendsProvider = Provider<List<Contact>>((ref) =>
    ref.watch(contactProvider).where((c) => c.isFriend).toList());

/// Requests this user sent that were not answered (or were declined —
/// indistinguishable by design).
final sentRequestsProvider = Provider<List<Contact>>((ref) => ref
    .watch(contactProvider)
    .where((c) => c.label == ContactLabel.requestSent)
    .toList());

/// Requests this user received and did not decline.
final receivedRequestsProvider = Provider<List<Contact>>((ref) => ref
    .watch(contactProvider)
    .where((c) => c.label == ContactLabel.requestReceived)
    .toList());

/// The accounts this user blocked — this device's list (BlockList) with the
/// names kept with each block. Recomputed when the list changes.
final blockedContactsProvider =
    FutureProvider.autoDispose<List<Contact>>((ref) async {
  ref.watch(blockedAccountsProvider);
  final named = await ref.read(blockListProvider).blockedWithNames();
  return [
    for (final e in named.entries)
      Contact(
        snowChatId: e.key,
        displayName: e.value,
        isBlocked: true,
        addedAt: DateTime.now(),
      ),
  ]..sort((a, b) => a.snowChatId.compareTo(b.snowChatId));
});
