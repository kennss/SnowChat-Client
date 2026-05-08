/// @file        channel.dart
/// @description Channel data models — discover/search results, channel info, invite info, friend info.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-05
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - ChannelType: channel type enum (community, personal)
///  - ChannelInfo: channel discover/search result model
///  - PendingChannel: channel awaiting join approval
///  - InviteInfo: invite-link info model
///  - JoinPolicy: join policy enum
///  - FriendInfo: PERSONAL channel friend info model
///  - FriendRequest: PERSONAL channel friend request model

/// Channel type: COMMUNITY (default) or PERSONAL (friend channel).
enum ChannelType { community, personal }

ChannelType parseChannelType(String? value) {
  switch (value) {
    case 'PERSONAL':
      return ChannelType.personal;
    default:
      return ChannelType.community;
  }
}

enum JoinPolicy { open, approval, inviteOnly }

JoinPolicy parseJoinPolicy(String? value) {
  switch (value) {
    case 'APPROVAL':
      return JoinPolicy.approval;
    case 'INVITE_ONLY':
      return JoinPolicy.inviteOnly;
    default:
      return JoinPolicy.open;
  }
}

class ChannelRoom {
  final String id;
  final String name;
  final bool isDefaultRoom;
  final bool isSystemRoom;
  final int memberCount;

  const ChannelRoom({
    required this.id,
    required this.name,
    this.isDefaultRoom = false,
    this.isSystemRoom = false,
    this.memberCount = 0,
  });

  factory ChannelRoom.fromJson(Map<String, dynamic> json) {
    return ChannelRoom(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Room',
      isDefaultRoom: json['isDefaultRoom'] as bool? ?? false,
      isSystemRoom: json['isSystemRoom'] as bool? ?? false,
      memberCount: json['memberCount'] as int? ?? 0,
    );
  }
}

class ChannelInfo {
  final String id;
  final String? name;
  final ChannelType type;
  final String? avatarUrl;
  final String? category;
  final int memberCount;
  final JoinPolicy joinPolicy;
  /// 일반 멤버 invite 허용 여부. owner 가 channel settings 에서 토글.
  /// INVITE_ONLY 채널엔 강제 false (서버에서 enforce — race 방어).
  final bool allowMemberInvite;
  final String? role;
  final bool isMuted;
  final List<ChannelRoom> rooms;

  const ChannelInfo({
    required this.id,
    this.name,
    this.type = ChannelType.community,
    this.avatarUrl,
    this.category,
    this.memberCount = 0,
    this.joinPolicy = JoinPolicy.open,
    this.allowMemberInvite = false,
    this.role,
    this.isMuted = false,
    this.rooms = const [],
  });

  factory ChannelInfo.fromJson(Map<String, dynamic> json) {
    final roomsList = (json['rooms'] as List?)
            ?.map((r) => ChannelRoom.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList() ??
        [];
    return ChannelInfo(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['groupName'] as String?,
      type: parseChannelType(json['type'] as String?),
      avatarUrl: json['avatarUrl'] as String?,
      category: json['category'] as String?,
      memberCount: json['memberCount'] as int? ?? 0,
      joinPolicy: parseJoinPolicy(json['joinPolicy'] as String?),
      allowMemberInvite: json['allowMemberInvite'] as bool? ?? false,
      role: json['role'] as String?,
      isMuted: json['isMuted'] as bool? ?? false,
      rooms: roomsList,
    );
  }

  bool get isPersonal => type == ChannelType.personal;
  bool get isCommunity => type == ChannelType.community;

  /// Get default room (General).
  ChannelRoom? get defaultRoom =>
      rooms.where((r) => r.isDefaultRoom).firstOrNull;

  /// Get system room.
  ChannelRoom? get systemRoom =>
      rooms.where((r) => r.isSystemRoom).firstOrNull;

  /// Get user-created rooms (not default, not system).
  List<ChannelRoom> get userRooms =>
      rooms.where((r) => !r.isDefaultRoom && !r.isSystemRoom).toList();

  bool get isOwner => role == 'OWNER';
  bool get isAdmin => role == 'ADMIN' || role == 'OWNER';

  /// 사용자가 invite link 를 생성할 수 있는지. admin 이거나 (멤버 +
  /// allowMemberInvite=true + INVITE_ONLY 아님). 서버 권한 체크와 동일.
  bool get canCreateInvite =>
      isAdmin ||
      (allowMemberInvite && joinPolicy != JoinPolicy.inviteOnly);
}

class PendingChannel {
  final String id;
  final String? name;
  final ChannelType type;
  final String? avatarUrl;
  final String? category;
  final String appliedAt;
  // Phase 9.1: creator info for PERSONAL channels (friend request display)
  final String? creatorSnowchatId;
  final String? creatorDisplayName;

  const PendingChannel({
    required this.id,
    this.name,
    this.type = ChannelType.community,
    this.avatarUrl,
    this.category,
    this.appliedAt = '',
    this.creatorSnowchatId,
    this.creatorDisplayName,
  });

  factory PendingChannel.fromJson(Map<String, dynamic> json) {
    return PendingChannel(
      id: json['id'] as String,
      name: json['name'] as String?,
      type: parseChannelType(json['type'] as String?),
      avatarUrl: json['avatarUrl'] as String?,
      category: json['category'] as String?,
      appliedAt: json['appliedAt'] as String? ?? '',
      creatorSnowchatId: json['creatorSnowchatId'] as String?,
      creatorDisplayName: json['creatorDisplayName'] as String?,
    );
  }

  bool get isPersonal => type == ChannelType.personal;
  bool get isCommunity => type == ChannelType.community;
}

class InviteInfo {
  final String groupId;
  final String? groupName;
  final String? avatarUrl;
  final String? category;
  final int memberCount;
  final JoinPolicy joinPolicy;

  const InviteInfo({
    required this.groupId,
    this.groupName,
    this.avatarUrl,
    this.category,
    this.memberCount = 0,
    this.joinPolicy = JoinPolicy.open,
  });

  factory InviteInfo.fromJson(Map<String, dynamic> json) {
    // 서버 (channelService.getInviteInfo) 는 channelId 키로 반환. 과거
    // group/channel 분리 전 코드 잔재로 클라이언트는 groupId 만 기대했음
    // → null cast 실패 → "Invalid or expired invite link" 표면화.
    // 양쪽 키 모두 받아 자연스러운 마이그레이션.
    return InviteInfo(
      groupId: (json['channelId'] ?? json['groupId']) as String,
      groupName: json['groupName'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      category: json['category'] as String?,
      memberCount: json['memberCount'] as int? ?? 0,
      joinPolicy: parseJoinPolicy(json['joinPolicy'] as String?),
    );
  }
}

/// Friend info from PERSONAL channel accepted member list.
/// Matches server `GET /channels/personal` → friends[] response.
class FriendInfo {
  final String userId;
  final String snowchatId;
  final String? displayName;
  final DateTime? lastSeenAt;

  const FriendInfo({
    required this.userId,
    required this.snowchatId,
    this.displayName,
    this.lastSeenAt,
  });

  factory FriendInfo.fromJson(Map<String, dynamic> json) {
    return FriendInfo(
      userId: json['userId'] as String,
      snowchatId: json['snowchatId'] as String,
      displayName: json['displayName'] as String?,
      lastSeenAt: json['lastSeenAt'] != null
          ? DateTime.tryParse(json['lastSeenAt'] as String)
          : null,
    );
  }
}

/// Pending friend request from PERSONAL channel.
/// Matches server `GET /channels/personal` → pendingRequests[] response.
class FriendRequest {
  final String userId;
  final String snowchatId;
  final String? displayName;
  final DateTime? requestedAt;

  const FriendRequest({
    required this.userId,
    required this.snowchatId,
    this.displayName,
    this.requestedAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      userId: json['userId'] as String,
      snowchatId: json['snowchatId'] as String,
      displayName: json['displayName'] as String?,
      requestedAt: json['requestedAt'] != null
          ? DateTime.tryParse(json['requestedAt'] as String)
          : null,
    );
  }
}
