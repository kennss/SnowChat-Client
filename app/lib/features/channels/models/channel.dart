/// @file        channel.dart
/// @description Channel data models — discover/search results, channel info, invite info (communities).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-05
/// @lastUpdated 2026-11-22 (friend graph off the server: no PERSONAL channel — FriendInfo,
///              FriendRequest, the request creator fields of PendingChannel, ChannelType.personal and
///              isPersonal are gone; friends live on this device, features/contacts). Earlier
///              2026-11-20 (v1 groups removed: a community has no rooms — no ChannelRoom, no rooms / defaultRoom / systemRoom / userRooms — and no mute flag; InviteInfo names the community by channelId / channelName). Earlier 2026-04-26 (header English translation)
///
/// @functions
///  - ChannelType: channel type enum (community — the only kind the server keeps)
///  - ChannelInfo: channel discover/search result model
///  - PendingChannel: channel awaiting join approval
///  - InviteInfo: invite-link info model (the community it joins)
///  - JoinPolicy: join policy enum

/// Channel type. The server keeps communities only (friends are not
/// channels any more); a type this build does not know is a community.
enum ChannelType { community }

ChannelType parseChannelType(String? value) => ChannelType.community;

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

class ChannelInfo {
  final String id;
  final String? name;
  final ChannelType type;
  final String? avatarUrl;
  final String? category;
  final int memberCount;
  final JoinPolicy joinPolicy;
  /// Whether regular members may create invites. The owner toggles it in
  /// the community settings. Forced false for INVITE_ONLY (enforced on the
  /// server — race defense).
  final bool allowMemberInvite;
  final String? role;

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
  });

  factory ChannelInfo.fromJson(Map<String, dynamic> json) {
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
    );
  }

  bool get isCommunity => type == ChannelType.community;

  bool get isOwner => role == 'OWNER';
  bool get isAdmin => role == 'ADMIN' || role == 'OWNER';

  /// Whether this account can create an invite link: an admin, or a member
  /// when allowMemberInvite is on and the community is not INVITE_ONLY.
  /// Same as the server's permission check.
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

  const PendingChannel({
    required this.id,
    this.name,
    this.type = ChannelType.community,
    this.avatarUrl,
    this.category,
    this.appliedAt = '',
  });

  factory PendingChannel.fromJson(Map<String, dynamic> json) {
    return PendingChannel(
      id: json['id'] as String,
      name: json['name'] as String?,
      type: parseChannelType(json['type'] as String?),
      avatarUrl: json['avatarUrl'] as String?,
      category: json['category'] as String?,
      appliedAt: json['appliedAt'] as String? ?? '',
    );
  }

  bool get isCommunity => type == ChannelType.community;
}

class InviteInfo {
  final String channelId;
  final String? channelName;
  final String? avatarUrl;
  final String? category;
  final int memberCount;
  final JoinPolicy joinPolicy;

  const InviteInfo({
    required this.channelId,
    this.channelName,
    this.avatarUrl,
    this.category,
    this.memberCount = 0,
    this.joinPolicy = JoinPolicy.open,
  });

  factory InviteInfo.fromJson(Map<String, dynamic> json) {
    // Matches the server's ChannelService.getInviteInfo.
    return InviteInfo(
      channelId: json['channelId'] as String,
      channelName: json['channelName'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      category: json['category'] as String?,
      memberCount: json['memberCount'] as int? ?? 0,
      joinPolicy: parseJoinPolicy(json['joinPolicy'] as String?),
    );
  }
}
