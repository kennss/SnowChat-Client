/// @file        sender_name_resolver.dart
/// @description Resolves a message sender's snowchatId to a human display name
///              from the best available local source, so a message from a
///              sealed / receive-first sender (whose server envelope carries no
///              senderDisplayName) renders a real name instead of a raw snow-id.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-08-03
/// @lastUpdated 2026-08-03
///
/// @functions
///  - resolveSenderName(ref, snowId, {roomId, envelopeName}): best-effort name
///    via envelope → group roster → contacts → friends → truncated snow-id.
///  - groupDisplayNameFallback(ref, roomId, {mySnowId}): roster-derived group
///    title ("Dave, Carol") when the real GMK/channel name isn't available.
///  - truncateSnowId(snowId): short "snow1234...cdef" form (last-resort label).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contacts/contact_provider.dart';
import '../../channels/providers/channel_provider.dart';
import '../../group/providers/group_detail_provider.dart';

/// Resolve [snowId] to a display name.
///
/// Order: [envelopeName] (server-supplied, non-sealed) → group roster member
/// (when [roomId] is a group) → reachable contacts → friends → truncated
/// snow-id. Uses `ref.watch`, so the label fills in reactively once a source
/// loads (e.g. the roster arrives, or contacts refresh). Never returns empty.
String resolveSenderName(
  WidgetRef ref,
  String snowId, {
  String? roomId,
  String? envelopeName,
}) {
  if (envelopeName != null && envelopeName.isNotEmpty) return envelopeName;

  // 1. Group roster — authoritative for group members.
  if (roomId != null && roomId.isNotEmpty) {
    final detail = ref.watch(groupDetailProvider(roomId));
    for (final m in detail.members) {
      if (m.snowchatId == snowId && (m.displayName?.isNotEmpty ?? false)) {
        return m.displayName!;
      }
    }
  }

  // 2. Contacts (already scoped to the reachable set server-side).
  for (final c in ref.watch(contactProvider)) {
    if (c.snowChatId == snowId && (c.displayName?.isNotEmpty ?? false)) {
      return c.displayName!;
    }
  }

  // 3. Friends.
  final friends = ref.watch(friendListProvider).valueOrNull ?? const [];
  for (final f in friends) {
    if (f.snowchatId == snowId && (f.displayName?.isNotEmpty ?? false)) {
      return f.displayName!;
    }
  }

  // 4. Last resort — a short, non-identifying snow-id form.
  return truncateSnowId(snowId);
}

/// Fallback title for a group / channel room when the real name is unavailable
/// — the E2EE group name needs the GMK (which may not have been delivered yet)
/// and a channel room's name needs the channel loaded; either can be missing,
/// leaving a bare "Group". The roster is always available, so derive a name from
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
