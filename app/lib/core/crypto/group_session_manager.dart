/// @file        group_session_manager.dart
/// @description High-level manager for group E2EE. Sender Key creation/distribution, member change handling, group message encrypt/decrypt
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; Phase 6.9: stateless myId — caller passes per-call)
///
/// @functions
///  - GroupSessionManager: Group E2EE session management class
///  - GroupSessionManager.initializeGroup(): Create and distribute Sender Key on group creation
///  - GroupSessionManager.handleMemberAdded(): Send existing Sender Key to a new member
///  - GroupSessionManager.handleMemberRemoved(): Rotate the entire Sender Key on member removal
///  - GroupSessionManager.sendGroupMessage(): Encrypt a group message
///  - GroupSessionManager.decryptGroupMessage(): Decrypt a group message
///  - GroupSessionManager.handleSenderKeyMessage(): Handle a received Sender Key distribution message
///  - GroupSessionManager.toJson(): Serialize state
///  - GroupSessionManager.fromJson(): Deserialize state

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../network/socket_manager.dart';
import 'sender_key.dart';
import 'signal_session_manager.dart';

/// Higher-level manager for group E2EE using Sender Keys.
///
/// Coordinates between [SenderKeyManager] (cryptographic operations)
/// and [SignalSessionManager] (1:1 E2EE channels for key distribution).
///
/// Sender Key distribution always happens via existing 1:1 E2EE channels
/// to ensure the server never sees the sender keys.
///
/// **Phase 6.9 invariant**: this class never holds a captured `myId`. The
/// caller (chat_provider) MUST pass the current SnowChat ID into every
/// outbound operation. This eliminates the structural bug where a stale
/// or empty `_myId` would silently key the sender-key map at the wrong
/// slot, causing SKDM/encryption divergence and 100% verification
/// failure on receivers.
///
/// **Phase 6.9 invariant**: this class never holds a captured
/// `SenderKeyManager` reference. `senderKeyManager` always resolves through
/// `_sessionManager.signal.senderKeyManager` so that calls survive
/// `clearAllSessions()` and `loadSessionStore()` (both of which REPLACE
/// the underlying instance, not mutate it).
class GroupSessionManager {
  final SignalSessionManager _sessionManager;
  final SocketManager? _socketManager;

  /// Track group membership for key distribution.
  /// Key: groupId, Value: set of member SnowChat IDs (excluding self).
  final Map<String, Set<String>> _groupMembers;

  GroupSessionManager({
    required SignalSessionManager sessionManager,
    SocketManager? socketManager,
    Map<String, Set<String>>? groupMembers,
  })  : _sessionManager = sessionManager,
        _socketManager = socketManager,
        _groupMembers = groupMembers ?? {};

  /// Access the underlying SenderKeyManager (for persistence). Always reads
  /// the live instance from SignalProtocolService so that
  /// `clearAllSessions()` / `loadSessionStore()` reassignments are observed.
  SenderKeyManager get senderKeyManager =>
      _sessionManager.signal.senderKeyManager;

  // Internal alias used by all method bodies; resolves on every call.
  SenderKeyManager get _senderKeyManager =>
      _sessionManager.signal.senderKeyManager;

  // ---------------------------------------------------------------------------
  // Group Initialization
  // ---------------------------------------------------------------------------

  /// Initialize E2EE for a group by creating our sender key and distributing
  /// it to all members via their 1:1 E2EE channels.
  ///
  /// [myId] is the current user's SnowChat ID — must be non-empty. The
  /// caller (chat_provider) is responsible for ensuring identity has been
  /// fully resolved before calling this method.
  /// [memberSnowchatIds] should include all members except ourselves.
  Future<void> initializeGroup(
    String groupId,
    String myId,
    List<String> memberSnowchatIds,
  ) async {
    if (myId.isEmpty) {
      throw ArgumentError(
          'initializeGroup: myId must not be empty (group $groupId)');
    }
    if (memberSnowchatIds.length > maxGroupSize) {
      throw ArgumentError(
        'Group size ${memberSnowchatIds.length} exceeds maximum $maxGroupSize',
      );
    }

    // Track membership
    _groupMembers[groupId] = Set<String>.from(memberSnowchatIds);

    // Create our sender key only if one doesn't already exist (e.g. restored
    // from session store). Unconditional creation would overwrite a restored
    // key, invalidating all previously distributed SKDMs.
    if (!_senderKeyManager.hasSenderKey(groupId, myId)) {
      _senderKeyManager.createSenderKey(groupId, myId);
      debugPrint(
        '[GroupSessionManager] Initialized group $groupId myId=$myId with '
        '${memberSnowchatIds.length} members (new Sender Key created)',
      );
    } else {
      debugPrint(
        '[GroupSessionManager] Initialized group $groupId myId=$myId with '
        '${memberSnowchatIds.length} members (existing Sender Key reused)',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Member Changes
  // ---------------------------------------------------------------------------

  /// Handle a new member being added to the group.
  ///
  /// Sends our existing sender key to the new member via 1:1 E2EE.
  /// [myId] must be non-empty.
  Future<void> handleMemberAdded(
    String groupId,
    String myId,
    String newMemberSnowchatId,
  ) async {
    if (myId.isEmpty) {
      throw ArgumentError(
          'handleMemberAdded: myId must not be empty (group $groupId)');
    }
    final members = _groupMembers[groupId];
    if (members == null) {
      debugPrint(
        '[GroupSessionManager] Cannot add member: group $groupId not initialized',
      );
      return;
    }

    if (members.length >= maxGroupSize) {
      throw StateError(
        'Cannot add member: group $groupId has reached maximum size $maxGroupSize',
      );
    }

    members.add(newMemberSnowchatId);

    // Send our existing sender key to the new member (BUG-1 fix: getExistingSKDM, not createSenderKey)
    if (_senderKeyManager.hasSenderKey(groupId, myId)) {
      final distribution = _senderKeyManager.getExistingSKDM(groupId, myId);
      final distributionBytes = distribution.serialize();
      await _distributeSenderKey(newMemberSnowchatId, distributionBytes);
    }

    debugPrint(
      '[GroupSessionManager] Added member $newMemberSnowchatId to group $groupId',
    );
  }

  /// Handle a member being removed from the group.
  ///
  /// ALL remaining members must rotate their sender keys to ensure
  /// the removed member cannot decrypt future messages.
  /// [myId] must be non-empty.
  Future<void> handleMemberRemoved(String groupId, String myId) async {
    if (myId.isEmpty) {
      throw ArgumentError(
          'handleMemberRemoved: myId must not be empty (group $groupId)');
    }
    final members = _groupMembers[groupId];
    if (members == null) {
      debugPrint(
        '[GroupSessionManager] Cannot handle removal: '
        'group $groupId not initialized',
      );
      return;
    }

    // Rotate our sender key
    final distribution = _senderKeyManager.rotateSenderKey(groupId, myId);
    final distributionBytes = distribution.serialize();

    // Invalidate Tracker so next message re-distributes SKDM to all members
    _sessionManager.signal.skdmTracker.invalidateGroup(groupId);

    // Distribute new sender key to all remaining members
    for (final memberId in members) {
      await _distributeSenderKey(memberId, distributionBytes);
    }

    debugPrint(
      '[GroupSessionManager] Rotated sender key for group $groupId '
      '(${members.length} members)',
    );
  }

  /// Remove a specific member from our local tracking.
  void removeMemberFromGroup(String groupId, String memberId) {
    _groupMembers[groupId]?.remove(memberId);
  }

  // ---------------------------------------------------------------------------
  // Message Encryption / Decryption
  // ---------------------------------------------------------------------------

  /// Encrypt a message for the group using our sender key.
  ///
  /// Returns the ciphertext (O(1) encryption regardless of group size).
  /// [myId] must be non-empty — caller (chat_provider) is responsible for
  /// passing the resolved SnowChat ID.
  Uint8List sendGroupMessage(String groupId, String myId, Uint8List plaintext) {
    if (myId.isEmpty) {
      throw ArgumentError(
          'sendGroupMessage: myId must not be empty (group $groupId)');
    }
    return _senderKeyManager.encryptGroupMessage(groupId, myId, plaintext);
  }

  /// Decrypt a group message from a specific sender.
  Uint8List decryptGroupMessage(
    String groupId,
    String senderId,
    Uint8List ciphertext,
  ) {
    return _senderKeyManager.decryptGroupMessage(groupId, senderId, ciphertext);
  }

  // ---------------------------------------------------------------------------
  // Sender Key Distribution Handling
  // ---------------------------------------------------------------------------

  /// Process an incoming sender key distribution message from another member.
  ///
  /// Called when we receive a 1:1 E2EE message containing a sender key
  /// distribution payload.
  void handleSenderKeyMessage(
    String groupId,
    String senderId,
    Uint8List messageBytes,
  ) {
    final distribution =
        SenderKeyDistributionMessage.deserialize(messageBytes);

    // Verify the message matches the expected group and sender
    if (distribution.groupId != groupId || distribution.senderId != senderId) {
      debugPrint(
        '[GroupSessionManager] Sender key distribution mismatch: '
        'expected $groupId:$senderId, got '
        '${distribution.groupId}:${distribution.senderId}',
      );
      return;
    }

    _senderKeyManager.processSenderKey(distribution);

    debugPrint(
      '[GroupSessionManager] Processed sender key from $senderId '
      'for group $groupId (iteration: ${distribution.iteration})',
    );
  }

  /// Check if we have a sender key for a specific member.
  bool hasSenderKey(String groupId, String senderId) {
    return _senderKeyManager.hasSenderKey(groupId, senderId);
  }

  /// Persist current group session state to disk via SignalSessionManager.
  /// Must be called after SKDM processing and message encrypt/decrypt.
  Future<void> persistState() async {
    await _sessionManager.saveGroupState();
  }

  /// Leave a group, cleaning up all sender key state.
  void leaveGroup(String groupId) {
    _senderKeyManager.removeGroup(groupId);
    _groupMembers.remove(groupId);
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Serialize all group session state to JSON.
  Map<String, dynamic> toJson() {
    final membersJson = <String, dynamic>{};
    for (final entry in _groupMembers.entries) {
      membersJson[entry.key] = entry.value.toList();
    }
    return {
      'senderKeys': _senderKeyManager.toJson(),
      'groupMembers': membersJson,
    };
  }

  /// Create a GroupSessionManager from serialized JSON state.
  ///
  /// **Phase 6.9**: Sender keys are NOT loaded here — they are owned by
  /// SignalProtocolService and loaded via `loadSessionStore()`. This factory
  /// only restores group membership tracking. The `senderKeys` field in the
  /// legacy JSON shape is ignored if present.
  factory GroupSessionManager.fromJson(
    Map<String, dynamic> json, {
    required SignalSessionManager sessionManager,
    SocketManager? socketManager,
  }) {
    final membersJson = json['groupMembers'] as Map<String, dynamic>? ?? {};
    final groupMembers = <String, Set<String>>{};
    for (final entry in membersJson.entries) {
      groupMembers[entry.key] =
          Set<String>.from((entry.value as List).cast<String>());
    }

    return GroupSessionManager(
      sessionManager: sessionManager,
      socketManager: socketManager,
      groupMembers: groupMembers,
    );
  }

  // ---------------------------------------------------------------------------
  // Private Helpers
  // ---------------------------------------------------------------------------

  /// Distribute a sender key to a member via their 1:1 E2EE channel.
  Future<void> _distributeSenderKey(
    String memberId,
    Uint8List distributionBytes,
  ) async {
    try {
      // Ensure we have a 1:1 session with this member (X3DH if needed)
      await _sessionManager.ensureSession(memberId);

      // Wrap distribution bytes in standard E2EE payload format
      // so decryptIncomingMessage() can parse it normally.
      // The distribution bytes are base64-encoded in the 'text' field.
      final payload = {
        'text': base64Encode(distributionBytes),
        'type': 'sender_key_distribution',
        'timestamp': DateTime.now().toIso8601String(),
      };
      final payloadBytes =
          Uint8List.fromList(utf8.encode(jsonEncode(payload)));

      // Encrypt with Double Ratchet (standard 1:1 E2EE)
      final deviceId = await _sessionManager.getDeviceIdForRecipient(memberId);
      final encrypted = await _sessionManager.encrypt(
        memberId,
        deviceId,
        payloadBytes,
      );

      // Send the encrypted sender key via 1:1 private message (Zero-Knowledge)
      if (_socketManager != null) {
        _socketManager!.sendPrivateMessage({
          'recipientId': memberId,
          'encryptedContent': base64Encode(
              encrypted['ciphertext'] as Uint8List),
          'type': 'sender_key_distribution',
          'messageType': encrypted['messageType'] as int,
        });
      }

      debugPrint(
        '[GroupSessionManager] Distributed sender key to $memberId '
        '(type: ${encrypted['messageType']})',
      );
    } catch (e) {
      debugPrint(
        '[GroupSessionManager] Failed to distribute sender key '
        'to $memberId: $e',
      );
      // Non-fatal: the member won't be able to decrypt our messages
      // until they receive our sender key via another path.
    }
  }
}
