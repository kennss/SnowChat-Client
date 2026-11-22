/// @file        channel_provider.dart
/// @description Channel state-management Provider — communities (member lists). Friends are not
///              channels any more: the friend list lives on this device (features/contacts).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-05
/// @lastUpdated 2026-11-23 (no account, conversation or community id in a log line — logRef). Earlier 2026-11-22 (friend graph off the server: the PERSONAL channel is gone —
///              personalChannelProvider, friendListProvider, friendRequestsProvider, FriendActions and
///              settleNickFriendRequests are removed (the friend list is ContactStore, the actions are
///              contactProvider's); a community ban no longer touches the block list). Earlier
///              2026-11-21 (a friend request sent by nickname is remembered and vouched for once the
///              accepted friend list shows that nickname — settleNickFriendRequests, run by
///              friendListProvider and the group picker). Earlier 2026-11-21 (X1: after a ban the device block list syncs (a friend ban blocks on the server)). Earlier 2026-11-21 (a friend request sent or accepted vouches for the account (VerifiedIdentityStore.vouch); acceptFriendRequest takes the request). Earlier 2026-11-20 (v1 groups removed: no mute toggle — a community has no rooms to notify about). Earlier 2026-04-26 (header + inline English translation)
///
/// @functions
///  - myChannelsProvider: my channel list (COMMUNITY only)
///  - pendingChannelsProvider: pending-join channel list
///  - channelDiscoverProvider: public channel discovery
///  - channelSearchProvider: channel search
///  - inviteInfoProvider: invite-code lookup
///  - ChannelActions: join/leave/apply/invite/admin actions
///  - channelCategories: category constants


import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/diagnostics/log_ref.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/channel.dart';

// ---------------------------------------------------------------------------
// My Channels (for the Channels tab)
// ---------------------------------------------------------------------------

/// My joined channels with member details — for Channels tab (communities).
final myChannelsProvider = FutureProvider<List<ChannelInfo>>((ref) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    final res = await apiClient.get('/channels/my');
    final channels = (res.data['channels'] as List?) ?? [];
    return channels
        .map((c) => ChannelInfo.fromJson(Map<String, dynamic>.from(c as Map)))
        .where((c) => c.isCommunity)
        .toList();
  } catch (e) {
    debugPrint('[ChannelProvider] My channels failed: $e');
    return [];
  }
});

/// Pending channel applications — COMMUNITY channels awaiting approval.
final pendingChannelsProvider =
    FutureProvider<List<PendingChannel>>((ref) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    final res = await apiClient.get('/channels/my');
    final pending = (res.data['pendingChannels'] as List?) ?? [];
    return pending
        .map(
            (c) => PendingChannel.fromJson(Map<String, dynamic>.from(c as Map)))
        .where((c) => c.isCommunity)
        .toList();
  } catch (e) {
    debugPrint('[ChannelProvider] Pending channels failed: $e');
    return [];
  }
});

// ---------------------------------------------------------------------------
// Discovery & Search
// ---------------------------------------------------------------------------

final channelDiscoverProvider =
    FutureProvider.autoDispose.family<List<ChannelInfo>, String?>((ref, category) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    final query = category != null ? '?category=$category' : '';
    final url = '${ApiEndpoints.channelDiscover}$query';
    debugPrint('[ChannelDiscover] GET $url');
    final res = await apiClient.get(url);
    debugPrint('[ChannelDiscover] Response status=${res.statusCode} data=${res.data}');
    final list = (res.data['channels'] as List?) ?? [];
    debugPrint('[ChannelDiscover] Found ${list.length} channels');
    return list
        .map((c) => ChannelInfo.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();
  } catch (e, st) {
    debugPrint('[ChannelDiscover] FAILED: $e');
    debugPrint('[ChannelDiscover] Stack: $st');
    return [];
  }
});

final channelSearchProvider =
    FutureProvider.family<List<ChannelInfo>, String>((ref, query) async {
  if (query.trim().length < 2) return [];
  try {
    final apiClient = ref.read(apiClientProvider);
    final res = await apiClient.get('${ApiEndpoints.channelSearch}?q=$query');
    final list = (res.data['channels'] as List?) ?? [];
    return list
        .map((c) => ChannelInfo.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();
  } catch (e) {
    debugPrint('[ChannelProvider] Search failed: $e');
    return [];
  }
});

final inviteInfoProvider =
    FutureProvider.family<InviteInfo?, String>((ref, code) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    final res = await apiClient.get(ApiEndpoints.inviteInfo(code));
    return InviteInfo.fromJson(Map<String, dynamic>.from(res.data as Map));
  } catch (e) {
    debugPrint('[ChannelProvider] Invite info failed: $e');
    return null;
  }
});

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

class ChannelActions {
  final Ref _ref;
  ChannelActions(this._ref);

  /// Create a new channel.
  Future<Map<String, dynamic>?> createChannel({
    required String name,
    String? description,
    bool isPublic = false,
    String joinPolicy = 'OPEN',
    String? category,
    String? avatarUrl,
    String? rules,
  }) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      final res = await apiClient.post(ApiEndpoints.channels, data: {
        'name': name,
        if (description != null) 'description': description,
        'isPublic': isPublic,
        'joinPolicy': joinPolicy,
        if (category != null) 'category': category,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (rules != null) 'rules': rules,
      });
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      debugPrint('[ChannelActions] Create failed: $e');
      return null;
    }
  }

  /// Join a public channel (OPEN policy).
  Future<bool> joinPublicChannel(String channelId) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post(ApiEndpoints.channelJoin(channelId));
      return true;
    } catch (e) {
      debugPrint('[ChannelActions] Join failed: $e');
      return false;
    }
  }

  /// Leave a channel.
  Future<bool> leaveChannel(String channelId) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post(ApiEndpoints.channelLeave(channelId));
      return true;
    } catch (e) {
      debugPrint('[ChannelActions] Leave failed: $e');
      return false;
    }
  }

  /// Apply to join an APPROVAL channel.
  Future<String> applyToChannel(String channelId) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      final res = await apiClient.post(ApiEndpoints.channelApply(channelId));
      return (res.data['status'] as String?) ?? 'pending';
    } catch (e) {
      debugPrint('[ChannelActions] Apply failed: $e');
      return 'error';
    }
  }

  /// Join via invite code.
  Future<bool> joinViaInvite(String code) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post(ApiEndpoints.inviteJoin(code));
      return true;
    } catch (e) {
      debugPrint('[ChannelActions] Invite join failed: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Admin Actions
  // ---------------------------------------------------------------------------

  /// Approve a pending member.
  Future<bool> approveApplication(String channelId, String userId) async {
    try {
      final url = ApiEndpoints.channelApprove(channelId, userId);
      debugPrint('[ChannelActions] Approve POST $url');
      final apiClient = _ref.read(apiClientProvider);
      final res = await apiClient.post(url);
      debugPrint('[ChannelActions] Approve success: ${res.data}');
      return true;
    } catch (e, st) {
      debugPrint('[ChannelActions] Approve FAILED: $e');
      debugPrint('[ChannelActions] Stack: $st');
      return false;
    }
  }

  /// Reject a pending member.
  Future<bool> rejectApplication(String channelId, String userId) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post(ApiEndpoints.channelReject(channelId, userId));
      return true;
    } catch (e) {
      debugPrint('[ChannelActions] Reject failed: $e');
      return false;
    }
  }

  /// Kick member from channel.
  Future<bool> kickMember(String channelId, String userId) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post(ApiEndpoints.channelKick(channelId, userId));
      return true;
    } catch (e) {
      debugPrint('[ChannelActions] Kick failed: $e');
      return false;
    }
  }

  /// Ban member from channel.
  Future<bool> banMember(String channelId, String userId) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post(ApiEndpoints.channelBan(channelId, userId));
      return true;
    } catch (e) {
      debugPrint('[ChannelActions] Ban failed: $e');
      return false;
    }
  }

  /// Change member role (ADMIN/MEMBER).
  Future<bool> setRole(String channelId, String userId, String role) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.put(
        ApiEndpoints.channelRole(channelId, userId),
        data: {'role': role},
      );
      return true;
    } catch (e) {
      debugPrint('[ChannelActions] SetRole failed: $e');
      return false;
    }
  }

  /// Update channel settings.
  Future<bool> updateSettings(String channelId, Map<String, dynamic> data) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.put(ApiEndpoints.channelSettings(channelId), data: data);
      return true;
    } catch (e) {
      debugPrint('[ChannelActions] UpdateSettings failed: $e');
      return false;
    }
  }

  /// Delete channel (owner only).
  Future<bool> deleteChannel(String channelId) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.delete(ApiEndpoints.channelDelete(channelId));
      return true;
    } catch (e) {
      debugPrint('[ChannelActions] Delete failed: $e');
      return false;
    }
  }

  /// Transfer channel ownership to another member (owner only).
  Future<bool> transferOwnership(String channelId, String newOwnerId) async {
    try {
      debugPrint('[ChannelActions] POST transfer-ownership: '
          'channel=${logRef(channelId)} newOwner=${logRef(newOwnerId)}');
      final apiClient = _ref.read(apiClientProvider);
      final url = ApiEndpoints.channelTransferOwnership(channelId);
      await apiClient.post(url, data: {'newOwnerId': newOwnerId});
      debugPrint('[ChannelActions] TransferOwnership success');
      return true;
    } catch (e, st) {
      debugPrint('[ChannelActions] TransferOwnership FAILED: $e\n$st');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Invite Links
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> createInviteLink(
    String channelId, {
    int? expiresInHours,
    int? maxUses,
  }) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      final res = await apiClient.post(
        ApiEndpoints.channelInviteLink(channelId),
        data: {
          if (expiresInHours != null) 'expiresInHours': expiresInHours,
          if (maxUses != null) 'maxUses': maxUses,
        },
      );
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      debugPrint('[ChannelActions] Create invite failed: $e');
      return null;
    }
  }

  Future<bool> deactivateInviteLink(String channelId) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.delete(ApiEndpoints.channelInviteLink(channelId));
      return true;
    } catch (e) {
      debugPrint('[ChannelActions] Deactivate invite failed: $e');
      return false;
    }
  }
}

final channelActionsProvider = Provider<ChannelActions>((ref) {
  return ChannelActions(ref);
});

/// Available channel categories.
const channelCategories = [
  'Gaming',
  'NFT & Crypto',
  'Business',
  'Technology',
  'Art & Design',
  'Education',
  'Finance',
  'Health',
  'Entertainment',
  'Social',
  'Sports',
  'Food & Drink',
  'Travel',
  'Music',
  'Other',
];
