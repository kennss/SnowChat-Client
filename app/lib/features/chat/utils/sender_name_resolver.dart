/// @file        sender_name_resolver.dart
/// @description Resolves a message sender's snowchatId to a human display name
///              from the best available local source, so a message from a
///              sealed / receive-first sender (whose server envelope carries no
///              senderDisplayName) renders a real name instead of a raw snow-id.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-08-03
/// @lastUpdated 2026-11-22 (resolvePeerName(): the name of a 1:1 peer for the chat header and the
///              Chats list — the friend list, then the chat's own name, then a certificate's, then
///              the short snowId). Earlier 2026-11-22 (friend graph off the server — the name order of design §5.6: the friend
///              list on this device, then the name from a verified name certificate, then the group
///              roster; no server friend list). Earlier 2026-11-20 (comment: a group's name comes from its change log, no GMK or channel room). Earlier 2026-08-03
///
/// @functions
///  - resolveSenderName(ref, snowId, {roomId, envelopeName}): best-effort name
///    via envelope → contacts → name certificate → group roster → truncated snow-id.
///  - resolvePeerName(ref, snowId, {conversationTitle}): a 1:1 peer's name via
///    the friend list → the chat's title → name certificate → truncated snow-id.
///  - groupDisplayNameFallback(ref, roomId, {mySnowId}): roster-derived group
///    title ("Dave, Carol") when the group's name isn't known yet.
///  - truncateSnowId(snowId): short "snow1234...cdef" form (last-resort label).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart' show nameCertServiceProvider;
import '../../contacts/contact_provider.dart';
import '../../group/providers/group_detail_provider.dart';

/// Resolve [snowId] to a display name.
///
/// Order: [envelopeName] (a name stored with the message) → the friend list
/// on this device → the name from the sender's verified name certificate →
/// group roster member (when [roomId] is a group) → truncated snow-id. Uses
/// `ref.watch` for the list and the roster, so the label fills in reactively.
/// Never returns empty.
String resolveSenderName(
  WidgetRef ref,
  String snowId, {
  String? roomId,
  String? envelopeName,
}) {
  if (envelopeName != null && envelopeName.isNotEmpty) return envelopeName;

  // 1. The friend list on this device.
  for (final c in ref.watch(contactProvider)) {
    if (c.snowChatId == snowId && (c.displayName?.isNotEmpty ?? false)) {
      return c.displayName!;
    }
  }

  // 2. The sender's verified name certificate (a 1:1 peer's name).
  final certified = ref.read(nameCertServiceProvider).cachedName(snowId);
  if (certified != null && certified.isNotEmpty) return certified;

  // 3. Group roster member.
  if (roomId != null && roomId.isNotEmpty) {
    final detail = ref.watch(groupDetailProvider(roomId));
    for (final m in detail.members) {
      if (m.snowchatId == snowId && (m.displayName?.isNotEmpty ?? false)) {
        return m.displayName!;
      }
    }
  }

  // 4. Last resort — a short, non-identifying snow-id form.
  return truncateSnowId(snowId);
}

/// The name of the 1:1 peer [snowId] (design §5.6, the order for a 1:1):
/// the friend list on this device → [conversationTitle] (the 1:1 room's
/// name, kept in step with the peer's verified name certificate) → a name
/// certificate's → a short snowId. Watches the friend list. Never asks the
/// server; never returns empty.
String resolvePeerName(
  WidgetRef ref,
  String snowId, {
  String? conversationTitle,
}) {
  for (final c in ref.watch(contactProvider)) {
    if (c.snowChatId == snowId && (c.displayName?.isNotEmpty ?? false)) {
      return c.displayName!;
    }
  }
  final title = conversationTitle?.trim();
  if (title != null && title.isNotEmpty && title != snowId) return title;
  final certified = ref.read(nameCertServiceProvider).cachedName(snowId);
  if (certified != null && certified.isNotEmpty) return certified;
  return truncateSnowId(snowId);
}

/// Fallback title for a group when its name is not known on this device yet,
/// which would leave a bare "Group". The roster is always available, so derive a name from
/// the other members ("Dave, Carol" / "Dave, Carol +2"), the standard messenger
/// treatment for an unnamed group. Returns null only when no other member is
/// known yet (caller keeps its own last-resort label).
String? groupDisplayNameFallback(
  WidgetRef ref,
  String roomId, {
  String? mySnowId,
}) {
  final detail = ref.watch(groupDetailProvider(roomId));
  final names = <String>[];
  for (final m in detail.members) {
    if (mySnowId != null && mySnowId.isNotEmpty && m.snowchatId == mySnowId) {
      continue;
    }
    names.add((m.displayName?.isNotEmpty ?? false)
        ? m.displayName!
        : truncateSnowId(m.snowchatId));
  }
  if (names.isEmpty) return null;
  if (names.length <= 3) return names.join(', ');
  return '${names.take(2).join(', ')} +${names.length - 2}';
}

/// Short display form of a snowchatId: "snow1234...cdef" (mirrors the legacy
/// chat_screen _truncateSnowId format).
String truncateSnowId(String snowId) {
  if (snowId.length > 12) {
    return '${snowId.substring(0, 8)}...${snowId.substring(snowId.length - 4)}';
  }
  return snowId;
}
