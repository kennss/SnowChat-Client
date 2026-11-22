/// @file        contact_store.dart
/// @description The friend list on this device and its rules (design
///              2026-11-22-friend-graph-off-server §5.1–§5.4). Each account keeps its own
///              one-sided list; the screens still show request → accept. A row says whether this
///              user added the account (inMyList) and whether the account said it added this user
///              (addedMe); the label comes from the two. Requesting and accepting are the same
///              act (add + a sealed contact_added); declining hides the row and sends nothing;
///              cancelling and unfriending remove the account from this user's list and send a
///              sealed contact_removed. Received notices only move addedMe — they open nothing.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (re-sync: a contact_added from an account already in this user's
///              list is answered once with a contact_added marked as an answer — never an answer
///              to an answer — so a lost acceptance or a peer that reinstalled without a backup
///              comes back to "friend"; resend() works for friends too. A contact_removed is
///              recorded on the row (removedMeAtMs) and, before the restore of this install ran,
///              kept as a row with neither mark, so the restore does not bring the backup's
///              addedMe back). Earlier 2026-11-22 (an account the server says does not exist: sends refused with
///              USER_NOT_FOUND are counted per row — noteRecipientNotFound / noteRecipientReached —
///              and from unavailableAfterFailures in a row the entry reads isUnavailable; the row is
///              never removed on the server's word; a notice from the account resets the count)
///
/// @functions
///  - ContactLabel / contactLabelOf(): friend, request sent, request received (§5.1 table)
///  - ContactEntry: a row with its label
///  - ContactNoticeEffect: what a received contact_added changed (for the notification)
///  - ContactStore.watch() / all() / entry(): the rows
///  - ContactStore.request() / accept(): add the account + contact_added (vouched for)
///  - ContactStore.decline(): hide a received request, nothing sent
///  - ContactStore.remove(): cancel a request or unfriend + contact_removed
///  - ContactStore.resend(): contact_added again (a sent request, or a friend the peer may not see)
///  - ContactStore.onContactAdded() / onContactRemoved(): the peer's sealed notices (an added one
///    from an account in this user's list is answered once)
///  - ContactStore.forget(): the row goes (the account was blocked)
///  - ContactStore.noteRecipientNotFound() / noteRecipientReached(): the server refused a send to
///    the account with USER_NOT_FOUND / took one (the "Account unavailable" count)
///
/// Notes:
///  - The label table: inMyList & addedMe → friend; inMyList only → request sent; addedMe only
///    → request received (hidden while hiddenAtMs is set). A row with neither is not kept.
///  - Being declined looks like "request sent" (as before — indistinguishable from a block).
///  - Vouching (VerifiedIdentityStore.vouch) happens when this user requests or accepts — never
///    for the peer's notice (what the network does is not a choice of the user).
///  - Notices are idempotent: the same notice twice leaves the same row. A hidden request that
///    comes again returns to "received" without a notification.
///  - The answer: a contact_added (not itself an answer) from an account in this user's list
///    gets one contact_added back marked `answer` (contract §12.4). The peer then knows this
///    user has it in their list, whatever it lost; an answer is never answered, so two devices
///    never send each other notices in a loop.
///  - Nothing here logs an account.
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;

import '../crypto/identity_binding.dart';
import '../crypto/verified_identity_store.dart' show VouchSource;
import '../storage/daos/contact_dao.dart';
import '../storage/database.dart';
import 'contact_notice.dart';

/// What the list shows for an account.
enum ContactLabel {
  /// Both added each other.
  friend,

  /// This user added the account; the account did not (or did not say so).
  requestSent,

  /// The account added this user; this user did not add it back.
  requestReceived,
}

/// The label of a row with [inMyList] and [addedMe]; null when it has
/// neither (such a row is not kept).
ContactLabel? contactLabelOf({required bool inMyList, required bool addedMe}) {
  if (inMyList && addedMe) return ContactLabel.friend;
  if (inMyList) return ContactLabel.requestSent;
  if (addedMe) return ContactLabel.requestReceived;
  return null;
}

/// A row of the list.
class ContactEntry {
  final String snowId;
  final bool inMyList;
  final bool addedMe;
  final int? hiddenAtMs;
  final String? nickname;
  final int? nameIssuedAtMs;
  final Uint8List? accountPub;

  /// Sends to the account the server refused in a row with USER_NOT_FOUND.
  final int notFoundCount;
  final int createdAtMs;
  final int updatedAtMs;

  const ContactEntry({
    required this.snowId,
    required this.inMyList,
    required this.addedMe,
    required this.hiddenAtMs,
    required this.nickname,
    required this.nameIssuedAtMs,
    required this.accountPub,
    this.notFoundCount = 0,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory ContactEntry.fromRow(ContactRow r) => ContactEntry(
        snowId: r.snowId,
        inMyList: r.inMyList,
        addedMe: r.addedMe,
        hiddenAtMs: r.hiddenAtMs,
        nickname: r.nickname,
        nameIssuedAtMs: r.nameIssuedAtMs,
        accountPub: r.accountPub,
        notFoundCount: r.notFoundCount,
        createdAtMs: r.createdAtMs,
        updatedAtMs: r.updatedAtMs,
      );

  /// The label; null for a row that has neither mark.
  ContactLabel? get label =>
      contactLabelOf(inMyList: inMyList, addedMe: addedMe);

  /// A received request this user declined (or an unfriended account's
  /// leftover mark): not shown until the account sends contact_added again.
  bool get isHidden => !inMyList && hiddenAtMs != null;

  /// Whether the list shows the row.
  bool get isVisible => label != null && !isHidden;

  /// The server refused sends to the account as not existing, again and
  /// again (deleted, or deactivated): shown as "Account unavailable".
  bool get isUnavailable =>
      notFoundCount >= ContactStore.unavailableAfterFailures;
}

/// What a received contact_added changed.
enum ContactNoticeEffect {
  /// Nothing new (a repeat), or a hidden request that came back (no
  /// notification by design).
  none,

  /// A new request: the account added this user, who has not added it.
  requestReceived,

  /// This user's request was accepted: both are friends now.
  requestAccepted,
}

/// Sends a contact notice to a peer (the 1:1 outbox).
typedef ContactNoticeSender = Future<void> Function(
    String peer, ContactNotice notice);

/// Marks an account this user chose (VerifiedIdentityStore.vouch).
typedef ContactVoucher = Future<void> Function(String snowId, VouchSource source);

class ContactStore {
  /// Sends refused with USER_NOT_FOUND in a row after which the account
  /// shows as unavailable (one refusal can be a server hiccup or a race with
  /// a re-registration; three in a row are not).
  static const int unavailableAfterFailures = 3;

  final ContactDao _dao;
  final ContactNoticeSender _send;
  final ContactVoucher _vouch;
  final int Function() _nowMs;

  ContactStore({
    required ContactDao dao,
    required ContactNoticeSender send,
    required ContactVoucher vouch,
    int Function()? nowMs,
  })  : _dao = dao,
        _send = send,
        _vouch = vouch,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Every row (hidden ones included — see ContactEntry.isVisible), each
  /// time one changes.
  Stream<List<ContactEntry>> watch() => _dao
      .watchAll()
      .map((rows) => [for (final r in rows) ContactEntry.fromRow(r)]);

  Future<List<ContactEntry>> all() async =>
      [for (final r in await _dao.allRows()) ContactEntry.fromRow(r)];

  Future<ContactEntry?> entry(String snowId) async {
    final row = await _dao.row(snowId);
    return row == null ? null : ContactEntry.fromRow(row);
  }

  /// This user adds [snowId] (a friend request — or, when the account added
  /// this user already, the acceptance). [accountPub] (checked to derive
  /// the snowId) and [nickname] are what the lookup found. Vouched for, and
  /// a contact_added goes out (through the outbox). Throws ArgumentError for
  /// what is not an account.
  Future<void> request(
    String snowId, {
    Uint8List? accountPub,
    String? nickname,
  }) async {
    final wasAddedMe = await _add(snowId, accountPub: accountPub, nickname: nickname);
    await _vouch(
      snowId,
      wasAddedMe ? VouchSource.friendAccepted : VouchSource.friendRequest,
    );
    await _send(snowId, ContactNotice.added);
  }

  /// This user accepts [snowId]'s request: the same act as [request] (add +
  /// contact_added), vouched for as an acceptance.
  Future<void> accept(String snowId) async {
    await _add(snowId);
    await _vouch(snowId, VouchSource.friendAccepted);
    await _send(snowId, ContactNotice.added);
  }

  /// Add [snowId] to this user's list (shown again if hidden). Returns
  /// whether the account had added this user.
  Future<bool> _add(
    String snowId, {
    Uint8List? accountPub,
    String? nickname,
  }) {
    _checkAccount(snowId);
    final pub = IdentityBindingV1.accountKeyMatchesSnowId(accountPub, snowId)
        ? accountPub
        : null;
    return _dao.transaction(() async {
      final now = _nowMs();
      final row = await _dao.row(snowId);
      final learned = row == null ? await _dao.peerName(snowId) : null;
      await _dao.putRow(ContactRow(
        snowId: snowId,
        inMyList: true,
        addedMe: row?.addedMe ?? false,
        hiddenAtMs: null,
        // A name from a certificate is kept; a lookup's name only fills a gap.
        nickname: row?.nickname ?? learned?.name ?? nickname,
        nameIssuedAtMs: row?.nameIssuedAtMs ?? learned?.issuedAtMs,
        accountPub: row?.accountPub ?? pub,
        notFoundCount: row?.notFoundCount ?? 0,
        removedMeAtMs: row?.removedMeAtMs,
        createdAtMs: row?.createdAtMs ?? now,
        updatedAtMs: now,
      ));
      return row?.addedMe ?? false;
    });
  }

  /// This user declines [snowId]'s request: the row is hidden; nothing is
  /// sent (the requester keeps seeing "request sent").
  Future<void> decline(String snowId) => _dao.transaction(() async {
        final row = await _dao.row(snowId);
        if (row == null || row.inMyList) return;
        final now = _nowMs();
        await _dao.putRow(row.copyWith(hiddenAtMs: Value(now), updatedAtMs: now));
      });

  /// This user cancels a request to [snowId] or removes the friend: the
  /// account leaves this user's list and a contact_removed goes out. When
  /// the account had added this user, its mark stays, hidden (it is not
  /// shown as a request until it sends contact_added again).
  Future<void> remove(String snowId) async {
    _checkAccount(snowId);
    final wasInList = await _dao.transaction(() async {
      final row = await _dao.row(snowId);
      if (row == null || !row.inMyList) return false;
      final now = _nowMs();
      if (row.addedMe) {
        await _dao.putRow(row.copyWith(
          inMyList: false,
          hiddenAtMs: Value(now),
          updatedAtMs: now,
        ));
      } else {
        await _dao.deleteRow(snowId);
      }
      return true;
    });
    if (wasInList) await _send(snowId, ContactNotice.removed);
  }

  /// Send contact_added to [snowId] again: a request whose answer never
  /// came, an acceptance the peer may not have received, or a friend that
  /// may not show this user as one (it reinstalled without a backup). The
  /// peer answers it when this user is in its list. Only for an account in
  /// this user's list.
  Future<void> resend(String snowId) async {
    final row = await _dao.row(snowId);
    if (row == null || !row.inMyList) return;
    await _send(snowId, ContactNotice.added);
  }

  /// [sender] (the authenticated sender of a sealed envelope) says it added
  /// this user; [isAnswer] — the notice answered one of this user's. Idempotent
  /// for the row. A hidden request becomes visible again without a
  /// notification. When [sender] is in this user's list and the notice is not
  /// an answer, one contact_added marked as an answer goes back (the peer may
  /// have lost this user's acceptance, or everything — it learns it is in
  /// this user's list).
  Future<ContactNoticeEffect> onContactAdded(
    String sender, {
    bool isAnswer = false,
  }) async {
    _checkAccount(sender);
    final (effect, inMyList) = await _dao.transaction(() async {
      final now = _nowMs();
      final row = await _dao.row(sender);
      if (row == null) {
        // A name this device already learned from the sender's certificate.
        final learned = await _dao.peerName(sender);
        await _dao.putRow(ContactRow(
          snowId: sender,
          inMyList: false,
          addedMe: true,
          hiddenAtMs: null,
          nickname: learned?.name,
          nameIssuedAtMs: learned?.issuedAtMs,
          accountPub: null,
          notFoundCount: 0,
          removedMeAtMs: null,
          createdAtMs: now,
          updatedAtMs: now,
        ));
        return (ContactNoticeEffect.requestReceived, false);
      }
      // The account sent this: it exists (an "unavailable" mark goes), and
      // its newest word is that it added this user.
      if (row.addedMe && row.hiddenAtMs == null) {
        if (row.notFoundCount != 0 || row.removedMeAtMs != null) {
          await _dao.putRow(row.copyWith(
            notFoundCount: 0,
            removedMeAtMs: const Value(null),
            updatedAtMs: now,
          ));
        }
        return (ContactNoticeEffect.none, row.inMyList);
      }
      final wasHidden = row.hiddenAtMs != null;
      final wasAddedMe = row.addedMe;
      await _dao.putRow(row.copyWith(
        addedMe: true,
        hiddenAtMs: const Value(null),
        notFoundCount: 0,
        removedMeAtMs: const Value(null),
        updatedAtMs: now,
      ));
      if (wasAddedMe || (wasHidden && !row.inMyList)) {
        return (ContactNoticeEffect.none, row.inMyList);
      }
      return (
        row.inMyList
            ? ContactNoticeEffect.requestAccepted
            : ContactNoticeEffect.requestReceived,
        row.inMyList,
      );
    });
    if (inMyList && !isAnswer) await _send(sender, ContactNotice.answer);
    return effect;
  }

  /// [sender] says it removed this user: only its mark goes (this user's
  /// own list is this user's), and the row records when — the peer's word on
  /// this install, newer than any backup. A row left with neither mark is
  /// removed, except before the restore of this install ran: then it stays
  /// (with neither mark — not shown) so the restore does not bring the
  /// backup's addedMe back; the restore drops it. Idempotent; no
  /// notification.
  Future<void> onContactRemoved(String sender) {
    _checkAccount(sender);
    return _dao.transaction(() async {
      final now = _nowMs();
      final row = await _dao.row(sender);
      final restoreDone = (await _dao.syncState())?.restored ?? false;
      if (row == null) {
        if (restoreDone) return;
        await _dao.putRow(ContactRow(
          snowId: sender,
          inMyList: false,
          addedMe: false,
          hiddenAtMs: null,
          nickname: null,
          nameIssuedAtMs: null,
          accountPub: null,
          notFoundCount: 0,
          removedMeAtMs: now,
          createdAtMs: now,
          updatedAtMs: now,
        ));
        return;
      }
      if (!row.inMyList && restoreDone) {
        await _dao.deleteRow(sender);
        return;
      }
      await _dao.putRow(row.copyWith(
        addedMe: false,
        removedMeAtMs: Value(now),
        updatedAtMs: now,
      ));
    });
  }

  /// [snowId] was blocked: its row goes (unblocking does not bring it back).
  /// Nothing is sent.
  Future<void> forget(String snowId) => _dao.deleteRow(snowId);

  /// The server refused a send to [snowId] with USER_NOT_FOUND: one more in
  /// the row's count (no row: nothing — only accounts of the list are
  /// marked). The row stays: the server's word alone removes nothing.
  Future<void> noteRecipientNotFound(String snowId) =>
      _dao.transaction(() async {
        final row = await _dao.row(snowId);
        if (row == null) return;
        await _dao.putRow(row.copyWith(
          notFoundCount: row.notFoundCount + 1,
          updatedAtMs: _nowMs(),
        ));
      });

  /// The server took a send to [snowId]: the account exists — its count goes
  /// back to zero. Writes only when there was a count.
  Future<void> noteRecipientReached(String snowId) =>
      _dao.transaction(() async {
        final row = await _dao.row(snowId);
        if (row == null || row.notFoundCount == 0) return;
        await _dao.putRow(row.copyWith(notFoundCount: 0, updatedAtMs: _nowMs()));
      });

  static void _checkAccount(String snowId) {
    if (!IdentityBindingV1.isValidSnowId(snowId)) {
      throw ArgumentError('contact list: not an account');
    }
  }
}
