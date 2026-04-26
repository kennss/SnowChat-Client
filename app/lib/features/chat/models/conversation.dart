/// @file        conversation.dart
/// @description Conversation model definition — data structure and related utilities for 1:1 and group conversations
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-19)
///
/// @functions
///  - ConversationType: conversation type enum (direct, group)
///  - Conversation: data model class holding conversation info
///  - displayName(): returns peer or group name
///  - otherParticipant(): returns peer SnowChat ID in a 1:1 conversation
///  - copyWith(): immutable copy method

enum ConversationType { direct, group }

class Conversation {
  final String id;
  final ConversationType type;
  final String? groupId; // Server group ID (for ConversationType.group)
  /// Parent channel ID (only set when this group is a channel room).
  /// `null` means this is an independent user-created group chat that
  /// should appear in the standalone "Group Chats" section, not nested
  /// under a channel.
  final String? channelId;
  final String? title;
  final List<String> participantIds;
  final String? lastMessageText;
  final DateTime? lastMessageTime;
  final String? lastMessageSenderId;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final int? disappearingTtl;
  final bool autoTranslateEnabled;
  /// Per-room translation target language (null falls back to global settings.preferredLanguage).
  final String? autoTranslateTargetLang;
  final DateTime createdAt;

  const Conversation({
    required this.id,
    this.type = ConversationType.direct,
    this.groupId,
    this.channelId,
    this.title,
    required this.participantIds,
    this.lastMessageText,
    this.lastMessageTime,
    this.lastMessageSenderId,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.disappearingTtl,
    this.autoTranslateEnabled = false,
    this.autoTranslateTargetLang,
    required this.createdAt,
  });

  /// Display name: group title or the other participant's ID.
  String displayName(String mySnowId) {
    if (title != null && title!.isNotEmpty) return title!;
    if (type == ConversationType.group) return 'Group Chat';
    final other = participantIds.where((id) => id != mySnowId);
    if (other.isNotEmpty) return _truncateId(other.first);
    return 'Unknown';
  }

  /// Get the other participant's SnowChat ID (for 1:1 chats).
  String? otherParticipant(String mySnowId) {
    final other = participantIds.where((id) => id != mySnowId);
    return other.isNotEmpty ? other.first : null;
  }

  static String _truncateId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 10)}...${id.substring(id.length - 4)}';
  }

  Conversation copyWith({
    String? groupId,
    String? channelId,
    String? title,
    String? lastMessageText,
    DateTime? lastMessageTime,
    String? lastMessageSenderId,
    int? unreadCount,
    bool? isPinned,
    bool? isMuted,
    bool? autoTranslateEnabled,
    String? autoTranslateTargetLang,
  }) {
    return Conversation(
      id: id,
      type: type,
      groupId: groupId ?? this.groupId,
      channelId: channelId ?? this.channelId,
      title: title ?? this.title,
      participantIds: participantIds,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      disappearingTtl: disappearingTtl,
      autoTranslateEnabled: autoTranslateEnabled ?? this.autoTranslateEnabled,
      autoTranslateTargetLang: autoTranslateTargetLang ?? this.autoTranslateTargetLang,
      createdAt: createdAt,
    );
  }
}
