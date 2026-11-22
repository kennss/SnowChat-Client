/// @file        pick_candidates.dart
/// @description The accounts a group picker offers (new group from the
///              friend list and chosen 1:1 peers, or from a community
///              roster; add members), each marked known or not. A roster is
///              the server's word (it can hold an account the server made
///              up), every name is, and an invite gives an account the
///              group's master key for good (whether or not it joins, even
///              after it is removed). So "known" means this
///              user chose the account by an action of their own on this
///              device — VerifiedIdentityStore.isVouched (a friend request
///              sent or accepted, a message written in a 1:1, a safety
///              number marked verified). A session or a key proves nothing
///              here: the identity latch is raised by any 1:1 session,
///              whoever starts it.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-22 (description: the contact candidates are no server list — only a roster
///              and the names are the server's word). Earlier 2026-11-22 (friend graph off the server —
///              design §5.6: the contact candidates are
///              this user's list (friends and sent requests) and the 1:1 peers this user vouched
///              for; no server contact list, no nickname-request settling (a request names its
///              account when it is made)). Earlier 2026-11-21 (requests sent by nickname and since accepted are vouched for before the
///              known / not-known split — settleNickFriendRequests). Earlier 2026-11-21 (X1: the contact candidates leave out this device's blocked accounts). Earlier 2026-11-21 (from roster_candidates.dart: known = vouched, not the identity latch; the
///              contacts of the pickers too)
///
/// @functions
///  - PickCandidate: one account (snowId, name, known)
///  - rosterCandidates(): the roster of a community detail answer, without
///    this account, blocked accounts, duplicates and what is not a snowId
///  - contactCandidates(): the contacts, without this account, blocked
///    accounts, [exclude] (e.g. members already in the group), duplicates
///    and what is not a snowId
///  - contactPickCandidatesProvider: contactCandidates() of this user's list and the vouched
///    1:1 peers, marked by VerifiedIdentityStore.isVouched
///  - PickSelection: the picked accounts, at most a given number
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/crypto/identity_binding.dart';
import '../../chat/models/conversation.dart';
import '../../chat/providers/conversation_list_provider.dart';
import '../../contacts/contact_provider.dart';

/// One account a picker offers.
class PickCandidate {
  final String snowId;

  /// The display name the server gave (its word only); null when blank.
  final String? name;

  /// This user chose the account by an action of their own (see the file
  /// notes).
  final bool known;

  const PickCandidate({
    required this.snowId,
    required this.name,
    required this.known,
  });
}

/// [accounts] (snowId, name) without [mySnowId], [exclude], duplicates and
/// what is not a snowId, each marked by [isKnown]: known first, then by
/// name (unnamed last), then by snowId.
Future<List<PickCandidate>> _candidates(
  Iterable<(Object?, Object?)> accounts, {
  required String? mySnowId,
  required Set<String> exclude,
  required Future<bool> Function(String snowId) isKnown,
}) async {
  final seen = <String>{};
  final picked = <(String, String?)>[];
  for (final (snowId, name) in accounts) {
    if (snowId is! String ||
        !IdentityBindingV1.isValidSnowId(snowId) ||
        snowId == mySnowId ||
        exclude.contains(snowId) ||
        !seen.add(snowId)) {
      continue;
    }
    picked.add((
      snowId,
      name is String && name.trim().isNotEmpty ? name.trim() : null,
    ));
  }
  final known = await Future.wait([for (final p in picked) isKnown(p.$1)]);
  final out = [
    for (var i = 0; i < picked.length; i++)
      PickCandidate(snowId: picked[i].$1, name: picked[i].$2, known: known[i]),
  ];
  out.sort((a, b) {
    if (a.known != b.known) return a.known ? -1 : 1;
    final an = a.name?.toLowerCase();
    final bn = b.name?.toLowerCase();
    if (an != bn) {
      if (an == null) return 1;
      if (bn == null) return -1;
      return an.compareTo(bn);
    }
    return a.snowId.compareTo(b.snowId);
  });
  return out;
}

/// The candidates of [detail] (the answer of GET /channels/:id; its
/// `members` are the accepted members) without [mySnowId] and the
/// [blocked] accounts, each marked by [isKnown]. Throws [FormatException]
/// when [detail] holds no member list.
Future<List<PickCandidate>> rosterCandidates({
  required Object? detail,
  required String? mySnowId,
  required Set<String> blocked,
  required Future<bool> Function(String snowId) isKnown,
}) {
  final members = detail is Map ? detail['members'] : null;
  if (members is! List) throw const FormatException('no member list');
  return _candidates(
    [
      for (final m in members)
        if (m is Map && m['user'] is Map)
          (
            (m['user'] as Map)['snowchatId'],
            (m['user'] as Map)['displayName'],
          ),
    ],
    mySnowId: mySnowId,
    exclude: blocked,
    isKnown: isKnown,
  );
}

/// The [contacts] that are not blocked, without [mySnowId] and [exclude],
/// each marked by [isKnown].
Future<List<PickCandidate>> contactCandidates({
  required List<Contact> contacts,
  required String? mySnowId,
  Set<String> exclude = const {},
  required Future<bool> Function(String snowId) isKnown,
}) =>
    _candidates(
      [
        for (final c in contacts)
          if (!c.isBlocked) (c.snowChatId, c.displayName),
      ],
      mySnowId: mySnowId,
      exclude: exclude,
      isKnown: isKnown,
    );

/// The picker candidates of the contacts (recomputed when they change):
/// this user's list (friends and sent requests) and the 1:1 peers this user
/// vouched for (design §5.6). A received request alone is not a candidate.
final contactPickCandidatesProvider =
    FutureProvider.autoDispose<List<PickCandidate>>((ref) async {
  final contacts =
      ref.watch(contactProvider).where((c) => c.inMyList).toList();
  // The accounts this user blocked (this device's list) are left out too.
  final blocked = await ref.watch(blockedAccountsProvider.future);
  final store = ref.read(verifiedIdentityStoreProvider);
  final listed = {for (final c in contacts) c.snowChatId};
  for (final conv in ref.watch(conversationListProvider)) {
    // A 1:1 room's id is the peer's snowId.
    if (conv.type != ConversationType.direct || listed.contains(conv.id)) {
      continue;
    }
    if (!await store.isVouched(conv.id)) continue;
    contacts.add(Contact(
      snowChatId: conv.id,
      displayName: (conv.title != null && conv.title != conv.id) ? conv.title : null,
      addedAt: conv.createdAt,
    ));
    listed.add(conv.id);
  }
  return contactCandidates(
    contacts: contacts,
    mySnowId: ref.read(currentSnowIdProvider),
    exclude: blocked,
    isKnown: store.isVouched,
  );
});

/// The accounts picked in a picker: at most [max].
class PickSelection {
  final int max;
  final Set<String> ids = {};

  PickSelection(this.max);

  /// Pick or unpick [snowId]. False when it could not be picked: full.
  bool toggle(String snowId) {
    if (ids.remove(snowId)) return true;
    if (ids.length >= max) return false;
    ids.add(snowId);
    return true;
  }

  /// Every known account of [candidates] is picked — or as many as fit.
  bool allKnownTaken(List<PickCandidate> candidates) {
    final known = [for (final c in candidates) if (c.known) c.snowId];
    if (known.isEmpty) return false;
    if (known.every(ids.contains)) return true;
    return ids.length >= max && known.any(ids.contains);
  }

  /// Pick every known account of [candidates] (as many as fit), or unpick
  /// them all when [allKnownTaken]. True when some did not fit.
  bool selectAllKnown(List<PickCandidate> candidates) {
    final known = [for (final c in candidates) if (c.known) c.snowId];
    if (allKnownTaken(candidates)) {
      ids.removeAll(known);
      return false;
    }
    for (final id in known) {
      if (ids.contains(id)) continue;
      if (ids.length >= max) return true;
      ids.add(id);
    }
    return false;
  }
}
