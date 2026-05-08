/// @file        api_endpoints.dart
/// @description SnowChat server API endpoint constant definitions. Includes auth, keys, messages, contacts, files, devices, prekeys, and group invite paths.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; dart-define environment switching support: SERVER_ENV=dev|prod)
///  - ApiEndpoints.groupLeave(): group leave endpoint
///  - ApiEndpoints.group(): specific group endpoint
///  - ApiEndpoints.groupMembers(): group members endpoint
///  - ApiEndpoints.groupMember(): specific group member endpoint
///  - ApiEndpoints.groupName(): group name change endpoint
///  - ApiEndpoints.groupMessages(): group messages list endpoint
///  - ApiEndpoints.groupInviteAccept(): group invite accept endpoint
///  - ApiEndpoints.groupInviteReject(): group invite reject endpoint
///  - ApiEndpoints.pendingGroupInvites: pending group invites list endpoint
///
/// @functions
///  - ApiEndpoints: API endpoint constants class
///  - ApiEndpoints.getBaseUrl(): return platform-specific base URL
///  - ApiEndpoints.getSocketUrl(): return platform-specific socket URL
///  - ApiEndpoints.preKeysForUser(): prekey endpoint for a specific user
///  - ApiEndpoints.messagesForConversation(): messages endpoint for a specific conversation
///  - ApiEndpoints.conversation(): specific conversation endpoint
///  - ApiEndpoints.contact(): specific contact endpoint
///  - ApiEndpoints.downloadFile(): file download endpoint
///  - ApiEndpoints.device(): specific device endpoint
///  - ApiEndpoints.userLookup(): user search by SnowChat ID
///  - ApiEndpoints.walletRegister: wallet registration endpoint
///  - ApiEndpoints.walletTokens(): per-wallet token list endpoint
///  - ApiEndpoints.walletPrices: token price endpoint
///  - ApiEndpoints.walletTokenMetadata(): token metadata endpoint
///  - ApiEndpoints.walletEnhancedHistory: Helius Enhanced Transactions proxy endpoint
///  - ApiEndpoints.nftCollection: NFT collection endpoint
///  - ApiEndpoints.nftDetail(): NFT detail endpoint

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// API endpoint constants for the SnowChat server.
///
/// Environment switching: flutter run --dart-define=SERVER_ENV=prod
///   - dev (default): localhost:3100 (Android emulator uses 10.0.2.2:3100)
///   - prod:          https://snowchat.calidalab.ai
abstract class ApiEndpoints {
  static const String _env =
      String.fromEnvironment('SERVER_ENV', defaultValue: 'dev');
  static final bool isProduction = _env == 'prod';

  // Base URLs
  static const String _prodHost = 'snowchat.calidalab.ai';
  static const String _prodBase = 'https://$_prodHost';
  static const String _devBase = 'http://localhost:3100';
  static const String _devBaseAndroid = 'http://10.0.2.2:3100';

  /// Cached resolved IP for production server.
  /// Set by [resolveProductionDns] at app startup to work around
  /// Dart VM DNS resolver failures on some Android devices.
  static String? _resolvedProdIp;

  /// Pre-resolve production domain at app startup.
  /// Tries InternetAddress.lookup (IPv4 only), falls back to original hostname.
  static Future<void> resolveProductionDns() async {
    if (!isProduction) return;
    try {
      final addresses = await InternetAddress.lookup(_prodHost)
          .timeout(const Duration(seconds: 5));
      final ipv4 = addresses.where((a) => a.type == InternetAddressType.IPv4);
      if (ipv4.isNotEmpty) {
        _resolvedProdIp = ipv4.first.address;
        debugPrint('[ApiEndpoints] DNS resolved: $_prodHost → $_resolvedProdIp');
      }
    } catch (e) {
      debugPrint('[ApiEndpoints] DNS pre-resolve failed: $e — using hostname');
    }
  }

  /// Get resolved IP (null if not resolved or dev mode).
  static String? get resolvedIp => _resolvedProdIp;

  /// Get the base URL (always uses hostname — SSL/SNI requires it).
  static String getBaseUrl() {
    if (isProduction) return '$_prodBase/api/v2';
    if (Platform.isAndroid) return '$_devBaseAndroid/api/v2';
    return '$_devBase/api/v2';
  }

  /// Get the Socket.IO URL (always uses hostname).
  static String getSocketUrl() {
    if (isProduction) return _prodBase;
    if (Platform.isAndroid) return _devBaseAndroid;
    return _devBase;
  }

  /// Original production hostname (for Host header when using IP).
  static String get prodHost => _prodHost;

  // Auth
  static const String authRegister = '/auth/register';
  static const String authChallenge = '/auth/challenge';
  static const String authVerify = '/auth/verify';
  static const String authRefresh = '/auth/refresh';

  // Identity / Registration (legacy, kept for backward compat)
  static const String register = '/identity/register';
  static const String identityLookup = '/identity/lookup';

  // Keys (E2EE PreKey management)
  static const String preKeys = '/keys/prekeys';
  static String preKeysForUser(String snowId) => '/keys/prekeys/$snowId';
  static const String preKeyCount = '/keys/prekey-count';
  static const String signedPreKey = '/keys/signed-prekey';

  // Messages — Phase 6 queue model
  static const String sendMessage = '/messages/send';
  /// GET — Fetch pending+delivered messages from the per-user queue.
  static const String fetchMessages = '/messages';
  /// POST — Batch ACK after client processes messages: { messageIds: [...] }
  static const String ackMessages = '/messages/ack';
  /// DELETE — Delete a logical message by messageGuid (sender, within 5 min)
  static String deleteMessage(String messageGuid) => '/messages/$messageGuid';
  /// @deprecated Phase 6 — use fetchMessages (queue) instead
  static String messagesForConversation(String convId) =>
      '/conversations/$convId/messages';

  // Conversations
  static const String conversations = '/conversations';
  static const String conversationFindOrCreate = '/conversations/find-or-create';
  static String conversation(String id) => '/conversations/$id';

  // Contacts
  static const String contacts = '/contacts';
  static String contact(String snowId) => '/contacts/$snowId';

  // Users
  static String userLookup(String snowchatId) => '/users/$snowchatId';

  // Groups
  static const String groups = '/groups';
  static String group(String groupId) => '/groups/$groupId';
  static String groupMembers(String groupId) => '/groups/$groupId/members';
  static String groupMember(String groupId, String userId) =>
      '/groups/$groupId/members/$userId';
  static String groupName(String groupId) => '/groups/$groupId/name';
  static String groupLeave(String groupId) => '/groups/$groupId/leave';
  static String groupMessages(String groupId) => '/groups/$groupId/messages';
  static String groupInviteAccept(String groupId) =>
      '/groups/$groupId/invites/accept';
  static String groupInviteReject(String groupId) =>
      '/groups/$groupId/invites/reject';
  static const String pendingGroupInvites = '/groups/pending';

  // Channels (Phase 7 — Channel ≠ GroupChat) + Phase 9.1 PERSONAL Channel
  static const String channels = '/channels';
  static const String personalChannel = '/channels/personal';
  static const String personalChannelAdd = '/channels/personal/add';
  static String personalChannelAccept(String channelId) =>
      '/channels/personal/accept/$channelId';
  static const String channelDiscover = '/channels/discover';
  static const String channelSearch = '/channels/search';
  static String channelDetail(String channelId) => '/channels/$channelId';
  static String channelSettings(String channelId) => '/channels/$channelId/settings';
  static String channelJoin(String channelId) => '/channels/$channelId/join';
  static String channelLeave(String channelId) => '/channels/$channelId/leave';
  static String channelApply(String channelId) => '/channels/$channelId/apply';
  static String channelApprove(String channelId, String userId) =>
      '/channels/$channelId/approve/$userId';
  static String channelReject(String channelId, String userId) =>
      '/channels/$channelId/reject/$userId';
  static String channelKick(String channelId, String userId) =>
      '/channels/$channelId/kick/$userId';
  static String channelBan(String channelId, String userId) =>
      '/channels/$channelId/ban/$userId';
  static String channelRole(String channelId, String userId) =>
      '/channels/$channelId/role/$userId';
  static String channelInviteLink(String channelId) =>
      '/channels/$channelId/invite-link';
  static String channelDelete(String channelId) => '/channels/$channelId';
  static String channelTransferOwnership(String channelId) =>
      '/channels/$channelId/transfer-ownership';
  // 서버 mount 위치: app.use('/api/v2/channels', channelsRoutes) 안에
  // router.get('/invite/:code') → 풀 경로 /api/v2/channels/invite/<code>.
  // 따라서 client base (/api/v2) + endpoint = /channels/invite/<code>.
  static String inviteInfo(String code) => '/channels/invite/$code';
  static String inviteJoin(String code) => '/channels/invite/$code/join';

  // Files / Attachments
  static const String uploadFile = '/files/upload';
  static String downloadFile(String fileId) => '/files/$fileId';

  // Devices
  static const String devices = '/devices';
  static String device(String deviceId) => '/devices/$deviceId';
  static String devicePushToken(String deviceId) =>
      '/devices/$deviceId/push-token';
  static String deviceVoipToken(String deviceId) =>
      '/devices/$deviceId/voip-token';

  // Wallet
  static const String walletRegister = '/wallet';
  static String walletTokens(String walletId) => '/wallet/$walletId/tokens';
  static const String walletPrices = '/wallet/prices';
  static String walletTokenMetadata(String mint) =>
      '/wallet/token-metadata/$mint';
  static const String walletEnhancedHistory = '/wallet/enhanced-history';

  // NFT
  static const String nftCollection = '/nft/collection';
  static String nftDetail(String mintAddress) => '/nft/$mintAddress';

}
