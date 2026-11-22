/// @file        channel_provider.dart
/// @description Channel state-management Provider — communities (member lists) + Phase 9.1 PERSONAL channel (friends).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-05
/// @lastUpdated 2026-11-21 (a friend request sent by nickname is remembered and vouched for once the
///              accepted friend list shows that nickname — settleNickFriendRequests, run by
///              friendListProvider and the group picker). Earlier 2026-11-21 (X1: after a ban the device block list syncs (a friend ban blocks on the server)). Earlier 2026-11-21 (a friend request sent or accepted vouches for the account (VerifiedIdentityStore.vouch); acceptFriendRequest takes the request). Earlier 2026-11-20 (v1 groups removed: no mute toggle — a community has no rooms to notify about). Earlier 2026-04-26 (header + inline English translation)
///
/// @functions
///  - myChannelsProvider: my channel list (COMMUNITY only)
///  - pendingChannelsProvider: pending-join channel list
///  - personalChannelProvider: PERSONAL channel info (friends + requests)
///  - friendListProvider: friend list (accepted members)
///  - friendRequestsProvider: received friend requests (pending)
///  - channelDiscoverProvider: public channel discovery
///  - channelSearchProvider: channel search
///  - inviteInfoProvider: invite-code lookup
///  - ChannelActions: join/leave/apply/invite/admin actions
///  - FriendActions: add/accept/remove friend actions
///  - channelCategories: category constants

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/crypto/verified_identity_store.dart'
    show VerifiedIdentityStore, VouchSource;
import '../../../core/network/api_endpoints.dart';
import '../models/channel.dart';

// ---------------------------------------------------------------------------
// My Channels (for the Channels tab)
// ---------------------------------------------------------------------------

/// My joined channels with member details — for Channels tab.
/// Filters out PERSONAL channels (Phase 9.1) — those are shown in Friends tab.
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
/// PERSONAL pending channels are shown as friend requests in Friends tab.
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
// PERSONAL Channel — Friends (Phase 9.1)
// ---------------------------------------------------------------------------

/// Raw PERSONAL channel response from server.
/// Returns { channelId, friends: [...], pendingRequests: [...] }.
final personalChannelProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    final res = await apiClient.get(ApiEndpoints.personalChannel);
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    debugPrint('[ChannelProvider] Personal channel failed: $e');
    return null;
  }
});

/// My PERSONAL channel ID.
final personalChannelIdProvider = Provider.autoDispose<String?>((ref) {
  final data = ref.watch(personalChannelProvider).valueOrNull;
  return data?['channelId'] as String?;
});

/// Friend list (accepted members of my PERSONAL channel).
final friendListProvider = FutureProvider.autoDispose<List<FriendInfo>>((ref) async {
  final data = await ref.watch(personalChannelProvider.future);
  if (data == null) return [];
  final friends = (data['friends'] as List?) ?? [];
  final list = friends
      .map((f) => FriendInfo.fromJson(Map<String, dynamic>.from(f as Map)))
      .toList();
  // A request this user sent by nickname vouches once it shows here,
  // accepted (VerifiedIdentityStore.settleNickRequests).
  await settleNickFriendRequests(ref.read(verifiedIdentityStoreProvider), list);
  return list;
});

/// Vouch for the accepted [friends] this user had asked by nickname. The
/// friend list's displayName is the nickname (unique on the server).
/// Best-effort: a storage failure leaves the requests for the next time.
Future<void> settleNickFriendRequests(
    VerifiedIdentityStore store, List<FriendInfo> friends) async {
  try {
    await store.settleNickRequests(
        friends.map((f) => (snowId: f.snowchatId, nick: f.displayName)));
  } catch (e) {
    debugPrint('[FriendActions] settle nickname requests failed: $e');
  }
}

/// Incoming friend requests — PERSONAL channels where I have pending membership.
/// These come from GET /channels/my → pendingChannels where type == PERSONAL.
final friendRequestsProvider =
    FutureProvider.autoDispose<List<PendingChannel>>((ref) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    final res = await apiClient.get('/channels/my');
    final pending = (res.data['pendingChannels'] as List?) ?? [];
    return pending
        .map((c) =>
            PendingChannel.fromJson(Map<String, dynamic>.from(c as Map)))
        .where((c) => c.isPersonal)
        .toList();
  } catch (e) {
    debugPrint('[ChannelProvider] Friend requests failed: $e');
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
      // Banning from the PERSONAL channel (a friend) blocks the account on
      // the server: this device's block list takes it in now (X1).
      unawaited(_ref.read(blockListProvider).sync());
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
      debugPrint('[ChannelActions] POST transfer-ownership: channelId=$channelId newOwnerId=$newOwnerId');
      final apiClient = _ref.read(apiClientProvider);
      final url = ApiEndpoints.channelTransferOwnership(channelId);
      debugPrint('[ChannelActions] URL: $url');
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

// ---------------------------------------------------------------------------
// Friend Actions (Phase 9.1)
// ---------------------------------------------------------------------------

class FriendActions {
  final Ref _ref;
  FriendActions(this._ref);

  /// Send a friend request by snowchatId. The user chose this account: it is
  /// vouched for (VouchSource.friendRequest) once the server took the
  /// request.
  /// Returns status string: 'pending', 'already_friend', 'already_pending', or 'error'.
  Future<String> addFriend(String snowchatId) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      final res = await apiClient.post(
        ApiEndpoints.personalChannelAdd,
        data: {'snowchatId': snowchatId},
      );
      await _ref
          .read(verifiedIdentityStoreProvider)
          .vouch(snowchatId, VouchSource.friendRequest);
      return (res.data['status'] as String?) ?? 'pending';
    } catch (e) {
      debugPrint('[FriendActions] Add friend failed: $e');
      return 'error';
    }
  }

  /// Nick first-contact lookup (design B). Exact-match; returns whether a user
  /// holds the nick + a one-time OPAQUE inviteToken (NOT the target's id/avatar)
  /// + whether the nick was recently reassigned (impersonation hint). Rate-
  /// limited server-side → [rateLimited] distinguishes a 429 from a genuine miss.
  Future<({bool exists, String? inviteToken, bool recentlyReassigned, bool rateLimited})>
      lookupByNick(String nick) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      final res = await apiClient
          .post(ApiEndpoints.lookupByNick, data: {'nick': nick.trim()});
      final d = Map<String, dynamic>.from(res.data as Map);
      return (
        exists: d['exists'] == true,
        inviteToken: d['inviteToken'] as String?,
        recentlyReassigned: d['recentlyReassigned'] == true,
        rateLimited: false,
      );
    } catch (e) {
      final limited = e is DioException && e.response?.statusCode == 429;
      if (!limited) debugPrint('[FriendActions] lookupByNick failed: $e');
      return (exists: false, inviteToken: null, recentlyReassigned: false, rateLimited: limited);
    }
  }

  /// Send a friend request by redeeming a nick-invite opaque token. Returns the
  /// same status strings as [addFriend], plus 'expired' when the token is gone.
  ///
  /// [nick] is the nickname the token was looked up for: the request is
  /// remembered under it and vouched for once the accepted friend list shows
  /// it (this path never names the account — settleNickFriendRequests).
  Future<String> addFriendByToken(String inviteToken, {required String nick}) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      final res = await apiClient.post(
        ApiEndpoints.personalChannelAddByToken,
        data: {'inviteToken': inviteToken},
      );
      await _ref.read(verifiedIdentityStoreProvider).rememberNickRequest(nick);
      return (res.data['status'] as String?) ?? 'pending';
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 410) return 'expired';
      debugPrint('[FriendActions] addFriendByToken failed: $e');
      return 'error';
    }
  }

  /// Accept a friend request (bidirectional). The user chose its sender: it
  /// is vouched for (VouchSource.friendAccepted).
  Future<bool> acceptFriendRequest(PendingChannel request) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post(ApiEndpoints.personalChannelAccept(request.id));
      final requester = request.creatorSnowchatId;
      if (requester != null) {
        await _ref
            .read(verifiedIdentityStoreProvider)
            .vouch(requester, VouchSource.friendAccepted);
      }
      return true;
    } catch (e) {
      debugPrint('[FriendActions] Accept friend failed: $e');
      return false;
    }
  }

  /// Remove a friend (kick from PERSONAL channel — server handles bidirectional).
  Future<bool> removeFriend(String channelId, String userId) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post(ApiEndpoints.channelKick(channelId, userId));
      return true;
    } catch (e) {
      debugPrint('[FriendActions] Remove friend failed: $e');
      return false;
    }
  }
}

final friendActionsProvider = Provider<FriendActions>((ref) {
  return FriendActions(ref);
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
