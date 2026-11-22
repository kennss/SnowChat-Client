/// @file        api_endpoints.dart
/// @description SnowChat server API endpoint constant definitions. Includes auth, keys, messages, contacts, files, devices, prekeys, communities and group protocol v2 paths.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-22 (no deleteMessage — the server's unsend route is gone; a 1:1 unsend is
///              the sealed control; no push-token clear — a device whose session ended loses its
///              tokens on the server). Earlier 2026-11-22 (fetchFile POST /files/fetch { fileId } replaces downloadFile GET
///              /files/:fileId).
///              Earlier 2026-11-22 (friend graph off the server — contract §12.1: no id in a URL path for
///              accounts, devices or conversations: preKeysFetch / identityFetch POST
///              /keys/{prekeys,identity}/fetch, devicePushToken / deviceVoipToken PUT
///              /devices/{push,voip}-token, deviceRemove POST /devices/remove, conversationDelete /
///              conversationClear POST /conversations/{delete,clear}, resolveUser POST /users/resolve,
///              unblockUser POST /users/unblock, blocksReplace POST /users/blocks/replace, nameCert POST
///              /users/name-cert, contactsBackup GET/PUT /contacts-backup; gone: GET /users/:id, GET
///              /users/blocked, the PERSONAL channel routes, find-or-create, the per-id key, device and
///              conversation paths). Earlier 2026-11-21 (blockUser POST /users/block, unblockUser DELETE /users/block/:snowchatId — BlockList). Earlier 2026-11-21 (blockedUsers GET /users/blocked). Earlier 2026-11-20 (DEV_SERVER_URL: a dev build on a physical device names the dev server — e.g. `http://<mac LAN ip>:3100` — instead of localhost; ignored by a production build. v1 groups removed: no /groups endpoints. Earlier same day: group protocol v2: gv2Backup GET/PUT /gv2-account/backup, gv2Retention GET/PUT /gv2-account/retention, deleteAccountWithProof POST /users/me/delete). Earlier 2026-11-10 (B-2: identityForUser() non-consuming GET /keys/identity/:snowId + identityBinding PUT /keys/identity-binding). Earlier 2026-04-26 (header + inline English translation; dart-define environment switching support: SERVER_ENV=dev|prod)
///
/// @functions
///  - ApiEndpoints: API endpoint constants class
///  - ApiEndpoints.getBaseUrl(): return platform-specific base URL
///  - ApiEndpoints.getSocketUrl(): return platform-specific socket URL
///  - ApiEndpoints.preKeysFetch / identityFetch: a peer's prekey bundle / identity (POST, id in the body)
///  - ApiEndpoints.resolveUser / lookupByNick: find an account by snowId / by nickname (POST)
///  - ApiEndpoints.nameCert: this account's name certificate (POST)
///  - ApiEndpoints.blockUser / unblockUser / blocksReplace: block tags on the server (POST)
///  - ApiEndpoints.contactsBackup: the sealed contact backup (GET / PUT)
///  - ApiEndpoints.conversationDelete / conversationClear: a 1:1 on the server (POST)
///  - ApiEndpoints.devicePushToken / deviceVoipToken / deviceRemove: this account's devices
///  - ApiEndpoints.uploadFile / fetchFile: file upload / fetch (POST, fileId in the body)
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
///   - dev (default): localhost:3100 (Android emulator uses 10.0.2.2:3100);
///                    a physical device names the dev server with
///                    `--dart-define=DEV_SERVER_URL=http://<host>:3100`
///   - prod:          https://snowchat.calidalab.ai (DEV_SERVER_URL ignored)
abstract class ApiEndpoints {
  static const String _env =
      String.fromEnvironment('SERVER_ENV', defaultValue: 'dev');
  static final bool isProduction = _env == 'prod';

  // Base URLs
  static const String _prodHost = 'snowchat.calidalab.ai';
  static const String _prodBase = 'https://$_prodHost';
  static const String _devBase = 'http://localhost:3100';
  static const String _devBaseAndroid = 'http://10.0.2.2:3100';

  /// The dev server as a physical device reaches it (no trailing slash), or
  /// empty: the simulator / emulator defaults above. Never used by a
  /// production build.
  static const String _devServerUrl =
      String.fromEnvironment('DEV_SERVER_URL');

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
    if (_devServerUrl.isNotEmpty) return '$_devServerUrl/api/v2';
    if (Platform.isAndroid) return '$_devBaseAndroid/api/v2';
    return '$_devBase/api/v2';
  }

  /// Get the Socket.IO URL (always uses hostname).
  static String getSocketUrl() {
    if (isProduction) return _prodBase;
    if (_devServerUrl.isNotEmpty) return _devServerUrl;
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
  /// POST { snowchatId } — a peer's prekey bundle (consumes a one-time prekey).
  static const String preKeysFetch = '/keys/prekeys/fetch';
  static const String preKeyCount = '/keys/prekey-count';
  static const String signedPreKey = '/keys/signed-prekey';

  // B-2 Identity Binding v1
  /// POST { snowchatId } — non-consuming identity lookup (does NOT pop a
  /// one-time prekey).
  static const String identityFetch = '/keys/identity/fetch';

  /// Register / refresh our binding without uploading prekeys (PUT).
  static const String identityBinding = '/keys/identity-binding';

  // Messages — Phase 6 queue model
  static const String sendMessage = '/messages/send';
  /// GET — Fetch pending+delivered messages from the per-user queue.
  static const String fetchMessages = '/messages';
  /// POST — Batch ACK after client processes messages: { messageIds: [...] }
  static const String ackMessages = '/messages/ack';

  // Conversations (a 1:1 is keyed by the peer's snowId, in the body)
  /// POST { peerSnowchatId } — delete the 1:1 on the server.
  static const String conversationDelete = '/conversations/delete';
  /// POST { peerSnowchatId } — clear the 1:1's queued rows on the server.
  static const String conversationClear = '/conversations/clear';

  // Users
  /// POST { snowchatId } → { snowchatId, displayName, publicKey, avatarHash };
  /// 404 USER_NOT_FOUND.
  static const String resolveUser = '/users/resolve';
  /// POST { nick } → { exists:false } or { exists:true, snowchatId,
  /// publicKey, recentlyReassigned }.
  static const String lookupByNick = '/users/lookup-by-nick';
  /// POST {} → { cert } (base64): this account's name certificate.
  static const String nameCert = '/users/name-cert';
  static const String userProfile = '/users/profile'; // PUT — update displayName / avatar
  /// POST { snowchatId } — block an account (idempotent; the server keeps a tag).
  static const String blockUser = '/users/block';
  /// POST { snowchatId } — unblock (idempotent).
  static const String unblockUser = '/users/unblock';
  /// POST { snowchatIds } → { count }: the server's tags become exactly this list.
  static const String blocksReplace = '/users/blocks/replace';
  /// POST — delete this account; the body carries the deletion proof the
  /// account key signed: { deletionProof: { deletedAtMs, sig } }.
  static const String deleteAccountWithProof = '/users/me/delete';

  // Group protocol v2 — per-account data (login required)
  /// GET → { blob, etag } (both null when none); PUT { blob, ifMatch } →
  /// { etag }, 409 BACKUP_CONFLICT when the stored blob is another one.
  static const String gv2Backup = '/gv2-account/backup';

  /// GET → { days }; PUT { days: 1 | 7 | 30 } → { days }. How long the
  /// server keeps group messages for this account while it is offline.
  static const String gv2Retention = '/gv2-account/retention';

  /// GET → { blob, etag } (both null when none); PUT { blob, ifMatch } →
  /// { etag }, 409 BACKUP_CONFLICT { etag } when the stored blob is another.
  static const String contactsBackup = '/contacts-backup';

  // Channels: communities (member lists)
  static const String channels = '/channels';
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
  /// POST raw body + x-content-hash header → { fileId, size }.
  static const String uploadFile = '/files/upload';
  /// POST { fileId } → the blob. The fileId is in the body: a path would put
  /// it in access logs next to every downloader's address.
  static const String fetchFile = '/files/fetch';

  // Devices
  static const String devices = '/devices';
  /// PUT { deviceId, pushToken, platform, appVersion } — this device's push token.
  static const String devicePushToken = '/devices/push-token';
  /// PUT { deviceId, voipPushToken } — this device's VoIP push token.
  static const String deviceVoipToken = '/devices/voip-token';
  /// POST { deviceId } — remove one of this account's devices.
  static const String deviceRemove = '/devices/remove';

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
