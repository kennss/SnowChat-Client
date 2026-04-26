/// @file        group_detail_provider.dart
/// @description Group detail and member-management provider. Handles group fetch, member add/remove, admin toggle, leave, and rename via server API.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-31
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - GroupMember: group-member data model
///  - GroupDetail: group-detail data model
///  - GroupDetailNotifier: StateNotifier managing group-detail state
///  - GroupDetailNotifier.loadGroup(): load group info from server
///  - GroupDetailNotifier.removeMember(): remove member
///  - GroupDetailNotifier.toggleAdmin(): toggle admin role
///  - GroupDetailNotifier.leaveGroup(): leave the group
///  - GroupDetailNotifier.updateName(): change group name
///  - groupDetailProvider: family StateNotifierProvider keyed by group ID

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/crypto/group_metadata_crypto.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../app/providers.dart';

/// A single member within a group.
class GroupMember {
  final String userId;
  final String snowchatId;
  final String? displayName;
  final bool isAdmin;
  final String status;
  final String joinedAt;

  const GroupMember({
    required this.userId,
    required this.snowchatId,
    this.displayName,
    this.isAdmin = false,
    this.status = 'active',
    this.joinedAt = '',
  });

  GroupMember copyWith({
    String? displayName,
    bool? isAdmin,
    String? status,
  }) {
    return GroupMember(
      userId: userId,
      snowchatId: snowchatId,
      displayName: displayName ?? this.displayName,
      isAdmin: isAdmin ?? this.isAdmin,
      status: status ?? this.status,
      joinedAt: joinedAt,
    );
  }
}

/// Full detail of a group including its member list.
class GroupDetail {
  final String id;
  final String? name;
  final String? description;
  final String creatorId;
  final int senderKeyEpoch;
  final List<GroupMember> members;
  final bool isLoading;
  final String? error;

  const GroupDetail({
    required this.id,
    this.name,
    this.description,
    this.creatorId = '',
    this.senderKeyEpoch = 0,
    this.members = const [],
    this.isLoading = false,
    this.error,
  });

  GroupDetail copyWith({
    String? name,
    String? description,
    String? creatorId,
    int? senderKeyEpoch,
    List<GroupMember>? members,
    bool? isLoading,
    String? error,
  }) {
    return GroupDetail(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      creatorId: creatorId ?? this.creatorId,
      senderKeyEpoch: senderKeyEpoch ?? this.senderKeyEpoch,
      members: members ?? this.members,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  /// Find a member by userId or snowchatId.
  GroupMember? findMember(String id) {
    return members
        .where((m) => m.userId == id || m.snowchatId == id)
        .firstOrNull;
  }

  /// Check if a user is the group creator (superadmin).
  bool isSuperAdmin(String id) => creatorId == id;

  /// Check if a user is an admin (either superadmin or assigned admin).
  bool isAdmin(String id) {
    if (isSuperAdmin(id)) return true;
    final member = findMember(id);
    return member?.isAdmin ?? false;
  }
}

class GroupDetailNotifier extends StateNotifier<GroupDetail> {
  final ApiClient _apiClient;
  final String _groupId;
  final Ref _ref;

  GroupDetailNotifier({
    required ApiClient apiClient,
    required String groupId,
    required Ref ref,
  })  : _apiClient = apiClient,
        _groupId = groupId,
        _ref = ref,
        super(GroupDetail(id: groupId, isLoading: true)) {
    loadGroup();
  }

  /// Load group info and members from the server.
  Future<void> loadGroup() async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _apiClient.get(ApiEndpoints.group(_groupId));
      if (!mounted) return;
      final data = Map<String, dynamic>.from(response.data as Map);

      final membersRaw = data['members'] as List<dynamic>? ?? [];
      final members = membersRaw.map((m) {
        final map = Map<String, dynamic>.from(m as Map);
        return GroupMember(
          userId: (map['userId'] ?? map['id'] ?? '') as String,
          snowchatId: (map['snowchatId'] ?? '') as String,
          displayName: map['displayName'] as String?,
          isAdmin: (map['isAdmin'] ?? false) as bool,
          status: (map['status'] ?? 'active') as String,
          joinedAt: (map['joinedAt'] ?? '') as String,
        );
      }).toList();

      // Phase 8.8: Decrypt group name with locally stored GMK
      String? groupName;
      final encName = data['encryptedName'] as String?;
      if (encName != null) {
        final (gmk, _) = await GroupMetadataCrypto.loadGMK(_groupId);
        if (gmk != null) {
          groupName = GroupMetadataCrypto.decryptGroupName(gmk, encName);
        } else {
          // GMK missing — auto-request
          debugPrint('[GroupDetail] GMK missing for $_groupId — requesting');
          _ref.read(socketManagerProvider).requestGmk(_groupId);
        }
      }
      groupName ??= data['name'] as String?;

      if (!mounted) return;
      state = state.copyWith(
        name: groupName,
        creatorId: (data['creatorId'] ?? '') as String,
        senderKeyEpoch: (data['senderKeyEpoch'] ?? 0) as int,
        members: members,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('[GroupDetail] Failed to load group: $e');
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Remove a member from the group.
  Future<bool> removeMember(String targetUserId) async {
    try {
      await _apiClient.delete(
        ApiEndpoints.groupMember(_groupId, targetUserId),
      );
      state = state.copyWith(
        members: state.members.where((m) => m.userId != targetUserId).toList(),
      );
      return true;
    } catch (e) {
      debugPrint('[GroupDetail] Failed to remove member: $e');
      return false;
    }
  }

  /// Toggle admin status for a member.
  Future<bool> toggleAdmin(String targetUserId) async {
    final member = state.members.where((m) => m.userId == targetUserId).firstOrNull;
    if (member == null) return false;

    final newIsAdmin = !member.isAdmin;
    try {
      await _apiClient.patch(
        ApiEndpoints.groupMember(_groupId, targetUserId),
        data: {'isAdmin': newIsAdmin},
      );
      state = state.copyWith(
        members: state.members.map((m) {
          if (m.userId == targetUserId) {
            return m.copyWith(isAdmin: newIsAdmin);
          }
          return m;
        }).toList(),
      );
      return true;
    } catch (e) {
      debugPrint('[GroupDetail] Failed to toggle admin: $e');
      return false;
    }
  }

  /// Leave the group.
  Future<bool> leaveGroup() async {
    try {
      await _apiClient.post(ApiEndpoints.groupLeave(_groupId));
      return true;
    } catch (e) {
      debugPrint('[GroupDetail] Failed to leave group: $e');
      return false;
    }
  }

  /// Update the group name with GMK rotation (Phase 8.8).
  Future<bool> updateName(String newName) async {
    try {
      // Load current GMK epoch
      final (_, currentEpoch) = await GroupMetadataCrypto.loadGMK(_groupId);
      final newEpoch = currentEpoch + 1;

      // Generate new GMK (rotation on every name change — audit #9)
      final newGmk = GroupMetadataCrypto.generateGMK();
      final encryptedName = GroupMetadataCrypto.encryptGroupName(newGmk, newName);

      await _apiClient.put(
        ApiEndpoints.groupName(_groupId),
        data: {
          'encryptedName': encryptedName,
          'gmkEpoch': newEpoch,
        },
      );

      // Store new GMK locally
      await GroupMetadataCrypto.storeGMK(_groupId, newGmk, newEpoch);

      state = state.copyWith(name: newName);
      debugPrint('[GroupDetail] Name updated with GMK rotation epoch=$newEpoch');

      // Distribute new GMK to all members via 1:1 E2EE
      final sessionManager = _ref.read(signalSessionManagerProvider);
      final mySnowId = _ref.read(currentSnowIdProvider) ?? '';
      final signingKeySeed = sessionManager.signal.signingKeySeed;
      final signature = signingKeySeed != null
          ? GroupMetadataCrypto.signGMK(
              signingKeySeed: signingKeySeed,
              groupId: _groupId,
              gmk: newGmk,
              epoch: newEpoch,
            )
          : null;

      for (final member in state.members) {
        if (member.snowchatId == mySnowId) continue;
        if (member.status != 'accepted') continue;
        try {
          await sessionManager.ensureSession(member.snowchatId);
          final deviceId = await sessionManager.getDeviceIdForRecipient(member.snowchatId);
          final payload = utf8.encode(jsonEncode({
            'type': 'group_metadata_key',
            'groupId': _groupId,
            'gmk': base64Encode(newGmk),
            'epoch': newEpoch,
            if (signature != null) 'signature': base64Encode(signature),
            'coordinatorSnowId': mySnowId,
          }));
          final encrypted = await sessionManager.encrypt(
            member.snowchatId, deviceId, Uint8List.fromList(payload),
          );
          _ref.read(socketManagerProvider).sendPrivateMessage({
            'recipientId': member.snowchatId,
            'encryptedContent': {
              'ciphertext': base64Encode(encrypted['ciphertext'] as Uint8List),
            },
            'messageType': encrypted['messageType'],
            'type': 'group_metadata_key',
          });
        } catch (e) {
          debugPrint('[GroupDetail] GMK distribute to ${member.snowchatId} failed: $e');
        }
      }

      return true;
    } catch (e) {
      debugPrint('[GroupDetail] Failed to update name: $e');
      return false;
    }
  }
}

final groupDetailProvider =
    StateNotifierProvider.family<GroupDetailNotifier, GroupDetail, String>(
  (ref, groupId) {
    final apiClient = ref.read(apiClientProvider);
    return GroupDetailNotifier(
      apiClient: apiClient,
      groupId: groupId,
      ref: ref,
    );
  },
);
