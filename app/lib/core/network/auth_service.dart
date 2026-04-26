/// @file        auth_service.dart
/// @description Challenge-response authentication service. Issues and refreshes JWT based on Ed25519 signatures.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - AuthService: authentication service class
///  - AuthService.register(): register new ID with server
///  - AuthService.authenticate(): challenge-response authentication, returns JWT
///  - AuthService.refreshToken(): refresh JWT token
///  - AuthService.isRegistered(): check whether registered with the server

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'api_endpoints.dart';
import '../crypto/identity_manager.dart';
import '../storage/secure_storage.dart';

/// Challenge-response authentication service.
///
/// Flow:
/// 1. Client registers with POST /auth/register { publicKey, snowchatId, displayName }
/// 2. Client sends snowchatId to POST /auth/challenge
/// 3. Server returns a random nonce
/// 4. Client signs the nonce with Ed25519 private key
/// 5. Client sends signature (hex) to POST /auth/verify with deviceInfo
/// 6. Server verifies and returns JWT tokens
class AuthService {
  final ApiClient apiClient;
  final IdentityManager identityManager;
  final SecureStorageService secureStorage;

  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _deviceIdKey = 'device_id';

  AuthService({
    required this.apiClient,
    required this.identityManager,
    required this.secureStorage,
  });

  /// Register a new identity with the server.
  /// Returns the server response { userId, snowchatId }.
  Future<Map<String, dynamic>> register({String? displayName}) async {
    final snowId = await identityManager.getSnowChatId();
    final publicKeyHex = await identityManager.getPublicKeyHex();

    if (snowId == null || publicKeyHex == null) {
      throw StateError('No identity found. Create identity first.');
    }

    final response = await apiClient.post(
      ApiEndpoints.authRegister,
      data: {
        'publicKey': publicKeyHex,
        'snowchatId': snowId,
        if (displayName != null) 'displayName': displayName,
      },
    );

    debugPrint('[AuthService] Registered: ${response.data}');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Check if the current identity is already registered on the server.
  /// Attempts a challenge -- if user not found, returns false.
  Future<bool> isRegistered() async {
    final snowId = await identityManager.getSnowChatId();
    if (snowId == null) return false;

    try {
      await apiClient.post(
        ApiEndpoints.authChallenge,
        data: {'snowchatId': snowId},
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Perform challenge-response auth and return JWT token.
  ///
  /// Steps:
  /// 1. POST /auth/challenge { snowchatId } -> { nonce, expiresAt }
  /// 2. Sign nonce with Ed25519 private key -> hex signature
  /// 3. POST /auth/verify { snowchatId, nonce, signature, deviceInfo }
  /// 4. Store JWT + refresh token in secure storage
  Future<String> authenticate() async {
    final snowId = await identityManager.getSnowChatId();
    if (snowId == null) {
      throw StateError('No identity found. Create or restore identity first.');
    }

    // Step 1: Request challenge nonce
    final challengeResponse = await apiClient.post(
      ApiEndpoints.authChallenge,
      data: {'snowchatId': snowId},
    );

    final challengeData = Map<String, dynamic>.from(
      challengeResponse.data as Map,
    );
    final nonce = challengeData['nonce'] as String;

    // Step 2: Sign nonce with Ed25519 private key (hex-encoded signature)
    final signatureHex = await identityManager.signString(nonce);

    // Step 3: Build device info and verify
    final deviceId = await _getOrCreateDeviceId();
    final deviceInfo = await _buildDeviceInfo(deviceId);

    final verifyResponse = await apiClient.post(
      ApiEndpoints.authVerify,
      data: {
        'snowchatId': snowId,
        'nonce': nonce,
        'signature': signatureHex,
        'deviceInfo': deviceInfo,
      },
    );

    final verifyData = Map<String, dynamic>.from(
      verifyResponse.data as Map,
    );
    final token = verifyData['token'] as String;
    final refreshToken = verifyData['refreshToken'] as String;

    // Step 4: Store tokens and set auth header
    await secureStorage.write(_tokenKey, token);
    await secureStorage.write(_refreshTokenKey, refreshToken);
    apiClient.setAuthToken(token);

    debugPrint('[AuthService] Authenticated successfully');
    return token;
  }

  /// Refresh the JWT token using the stored refresh token.
  Future<String> refreshToken() async {
    final currentRefreshToken = await secureStorage.read(_refreshTokenKey);
    if (currentRefreshToken == null) {
      throw StateError('No refresh token available');
    }

    final response = await apiClient.post(
      ApiEndpoints.authRefresh,
      data: {'refreshToken': currentRefreshToken},
    );

    final data = Map<String, dynamic>.from(response.data as Map);
    final newToken = data['token'] as String;
    final newRefreshToken = data['refreshToken'] as String;

    await secureStorage.write(_tokenKey, newToken);
    await secureStorage.write(_refreshTokenKey, newRefreshToken);
    apiClient.setAuthToken(newToken);

    return newToken;
  }

  /// Try to restore a previously stored auth token.
  /// Returns the token if found and sets it on the API client.
  Future<String?> restoreToken() async {
    final token = await secureStorage.read(_tokenKey);
    if (token != null) {
      apiClient.setAuthToken(token);
    }
    return token;
  }

  /// Clear all stored auth data (logout).
  /// Unregisters push token from server before clearing credentials.
  Future<void> logout() async {
    // Unregister push token (server) — best-effort
    try {
      final deviceId = await secureStorage.read(_deviceIdKey);
      if (deviceId != null) {
        await apiClient.put(
          ApiEndpoints.devicePushToken(deviceId),
          data: {'pushToken': null, 'platform': null},
        );
      }
    } catch (_) {
      // Network failure on logout is OK — token will expire
    }

    await secureStorage.delete(_tokenKey);
    await secureStorage.delete(_refreshTokenKey);
    apiClient.clearAuthToken();
  }

  /// Get stored device ID or create a new one.
  Future<String> _getOrCreateDeviceId() async {
    var deviceId = await secureStorage.read(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await secureStorage.write(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  /// Build device info payload for the verify request.
  /// Includes Signal Protocol keys from the SignalProtocolService.
  Future<Map<String, dynamic>> _buildDeviceInfo(String deviceId) async {
    // Phase 8.7 round 4 — Layer C1: never let a fresh-install device send
    // an all-zero placeholder identityKey. The previous fallback caused
    // the server's CREATE path to register the device with an invisible
    // identity key — fetchPreKeyBundle then 404'd for every other sender
    // and the user could not receive group messages until the (slow)
    // follow-up POST /keys/prekeys finally updated the row.
    //
    // Idempotent: only generate when the secure-storage slot is empty
    // AND hasSignalIdentity() reports false (the latter accounts for the
    // race where another caller writes the slot between checks). Generating
    // unconditionally on every authenticate() would rotate the X25519 key
    // and invalidate every existing X3DH session — that is the regression
    // both the audit and the simulation agent flagged as critical.
    var realPublicKey = await identityManager.getSignalPublicKey();
    if (realPublicKey == null) {
      final hasIdentity = await identityManager.hasSignalIdentity();
      if (!hasIdentity) {
        debugPrint('[AuthService] _buildDeviceInfo: generating fresh '
            'Signal identity (first device registration)');
        await identityManager.generateSignalIdentityKey();
        realPublicKey = await identityManager.getSignalPublicKey();
      }
    }
    if (realPublicKey == null) {
      // Should never happen — fail loud rather than send a placeholder.
      throw StateError(
        '_buildDeviceInfo: Signal identity key still null after generate. '
        'Aborting registration to prevent placeholder pollution.',
      );
    }

    // Signed prekey / sig are uploaded properly via POST /keys/prekeys
    // after auth — send placeholders here unless we have real ones.
    // (Server's CREATE path stores them as placeholders until uploadPreKeys
    //  arrives. fetchPreKeyBundle does NOT placeholder-check signedPreKey,
    //  so this does not break group E2EE — but a separate cleanup PR
    //  should send a real signed prekey here too for full correctness.)
    final signedPreKey = base64Encode(List<int>.filled(32, 0));
    final signedPreKeySig = base64Encode(List<int>.filled(64, 0));

    return {
      'deviceId': deviceId,
      'identityKey': base64Encode(realPublicKey),
      'signedPreKey': signedPreKey,
      'signedPreKeySig': signedPreKeySig,
      'signedPreKeyId': 0,
      'registrationId': 0,
      'deviceName': _getDeviceName(),
      'osType': Platform.isIOS ? 'ios' : 'android',
    };
  }

  /// Get a human-readable device name.
  static String _getDeviceName() {
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isAndroid) return 'Android';
    return 'Unknown';
  }
}
