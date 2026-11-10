/// @file        auth_service.dart
/// @description Challenge-response authentication service. Issues JWT pair
///              based on Ed25519 signatures and hands the result off as a
///              `TokenSnapshot` so the caller can store it via TokenManager.
///              Phase 11 (2026-05-03): refresh logic moved to TokenManager.
///              This service ONLY handles register, authenticate, isRegistered,
///              and logout (best-effort push-token unregister).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-10 (B-2: the login nonce is signed via IdentityManager.signAuthChallenge (strict format — signing-oracle fix); deviceInfo carries identityKeyEd25519 + identityBinding so a freshly registered device row is bound from the start; records accountMaxIdentityBindingEpoch from the verify response (H1); on the 403 "deviceId is registered to another account" regenerates device_id and retries the full challenge once (L5); retries the 503 registration-conflict race with a short backoff without touching device_id). Earlier 2026-05-03 (Phase 11 — refreshToken/restoreToken removed; authenticate returns TokenSnapshot)
///
/// @functions
///  - AuthService: authentication service class
///  - AuthService.register(): register new ID with server
///  - AuthService.authenticate(): challenge-response (signAuthChallenge), returns TokenSnapshot
///  - AuthService._buildDeviceInfo(): device payload incl. Ed25519 key + identity binding (B-2)
///  - AuthService._isDeviceIdOwnedByAnotherAccount(): detect the 403 deviceId-conflict (L5)
///  - AuthService._authenticateWithConflictRetry(): 503 registration-race backoff
///  - AuthService.isRegistered(): check whether registered with the server
///  - AuthService.logout(): best-effort push-token unregister (token wipe is TokenManager.clear())

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'api_endpoints.dart';
import 'token_manager.dart';
import '../crypto/identity_binding.dart';
import '../crypto/identity_manager.dart';
import '../storage/secure_storage.dart';
import '../../utils/version.dart';

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

  /// Perform challenge-response auth and return a [TokenSnapshot].
  ///
  /// Phase 11: The caller is responsible for handing the returned snapshot to
  /// `tokenManager.setFromLogin(snapshot)` so the SSoT picks it up. This
  /// service no longer touches secure_storage for token persistence — that's
  /// TokenManager's job (single key `auth_tokens_v2`).
  ///
  /// Steps:
  /// 1. POST /auth/challenge { snowchatId } -> { nonce, expiresAt }
  /// 2. Sign nonce with Ed25519 private key -> hex signature
  /// 3. POST /auth/verify { snowchatId, nonce, signature, deviceInfo }
  /// 4. Decode JWT exp claim and return TokenSnapshot
  Future<TokenSnapshot> authenticate() async {
    try {
      return await _authenticateWithConflictRetry();
    } on DioException catch (e) {
      if (!_isDeviceIdOwnedByAnotherAccount(e)) rethrow;
      // B-2 L5: our stored device_id belongs to another account on the
      // server (e.g. a Keychain item that survived an account switch). The
      // server refuses to rebind it — mint a fresh deviceId and retry ONCE
      // with a brand-new challenge (the old nonce may already be consumed).
      // This is the ONLY error that regenerates the deviceId.
      debugPrint('[AuthService] deviceId owned by another account — '
          'regenerating deviceId and retrying once');
      await secureStorage.write(_deviceIdKey, const Uuid().v4());
      return _authenticateWithConflictRetry();
    }
  }

  /// Backoff for the server's transient 503 "Device registration conflict.
  /// Please retry." (concurrent-registration race on /auth/verify).
  static const List<Duration> _conflictRetryDelays = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
  ];

  /// Full challenge/verify, retried with a short backoff ONLY on the 503
  /// registration-conflict race. Never regenerates the deviceId and never
  /// surfaces as an auth failure while retries remain (no forced logout).
  Future<TokenSnapshot> _authenticateWithConflictRetry() async {
    for (var attempt = 0;; attempt++) {
      try {
        return await _authenticateOnce();
      } on DioException catch (e) {
        final retryable = e.response?.statusCode == 503;
        if (!retryable || attempt >= _conflictRetryDelays.length) rethrow;
        debugPrint('[AuthService] device registration conflict (503) — '
            'retry ${attempt + 1}/${_conflictRetryDelays.length}');
        await Future<void>.delayed(_conflictRetryDelays[attempt]);
      }
    }
  }

  /// True for the server's 403 "deviceId is registered to another account".
  static bool _isDeviceIdOwnedByAnotherAccount(DioException e) {
    if (e.response?.statusCode != 403) return false;
    final body = e.response?.data;
    return body != null &&
        body.toString().contains('deviceId is registered to another account');
  }

  Future<TokenSnapshot> _authenticateOnce() async {
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

    // Step 2: Sign nonce with Ed25519 private key (hex-encoded signature).
    // B-2 §3.1: signAuthChallenge refuses (FormatException → login aborted)
    // any nonce that is not the server's `uuidv4-base36(ms)` shape, so the
    // login challenge cannot be abused as a general account-key oracle.
    final signatureHex = await identityManager.signAuthChallenge(nonce);

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

    // B-2 H1: remember the account-wide max binding epoch so every later
    // mint lands above it (a restore / fresh install has no local history).
    // A soft-rejected login binding is repaired by the prekey-count
    // self-check right after initialize().
    try {
      await identityManager.recordAccountMaxBindingEpoch(
          verifyData['accountMaxIdentityBindingEpoch']);
      if (verifyData['bindingAccepted'] == false) {
        debugPrint('[AuthService] login binding soft-rejected '
            '(${verifyData['bindingRejectReason']}) — self-check will repair');
      }
    } catch (e) {
      debugPrint('[AuthService] account max epoch not recorded: '
          '${e.runtimeType}');
    }

    debugPrint('[AuthService] Authenticated successfully');
    return TokenSnapshot.fromTokens(
      access: token,
      refresh: refreshToken,
      version: 1,
    );
  }

  /// Best-effort push-token unregister. Phase 11: token wipe is now driven by
  /// `TokenManager.clear()` — this method only sends the side-effect API call.
  ///
  /// Callers (settings_screen reset path) typically:
  ///   1. tokenManager.clear()  — wipes envelope + emits logout event
  ///   2. authService.logout()  — best-effort server-side push unregister
  ///
  /// Calling order is not strict because the API itself uses the bearer JWT;
  /// if the JWT is already wiped, the push unregister silently fails (network
  /// 401) and we don't surface that to the user.
  Future<void> logout() async {
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

    // Phase 8.2 Path B v4 (C2) — report client buildNumber so server can
    // gate Path B always-push behind PATHB_MIN_CLIENT_VERSION (Plan §2.5).
    // Field is omitted when version lookup fails so legacy server (no C0)
    // ignores unknown key and so newer server doesn't blank existing value.
    final appVersion = await getAppVersionForServer();

    // B-2 Identity Binding v1: ship the Signal Ed25519 key and the account-
    // signed binding with the device registration so the server row is bound
    // from the first request (no unbound window). Omitted only when the Ed
    // key does not exist yet; the prekey upload / self-check covers that.
    Map<String, dynamic>? bindingFields;
    final ed25519 = await identityManager.getSignalVerifyKey();
    if (ed25519 != null &&
        ed25519.length == 32 &&
        realPublicKey.length == 32 &&
        IdentityBindingV1.isValidDeviceId(deviceId)) {
      try {
        final binding = await identityManager.currentIdentityBinding(
          deviceId: deviceId,
          identityKey: realPublicKey,
          ed25519: ed25519,
        );
        bindingFields = {
          'identityKeyEd25519': base64Encode(ed25519),
          'identityBinding': binding.wire.toWireJson(),
        };
      } catch (e) {
        // Never block login on the binding: the prekey upload and the
        // prekey-count self-check (PUT /keys/identity-binding) repair it.
        debugPrint('[AuthService] identity binding unavailable at login: '
            '${e.runtimeType}');
      }
    }

    return {
      'deviceId': deviceId,
      'identityKey': base64Encode(realPublicKey),
      ...?bindingFields,
      'signedPreKey': signedPreKey,
      'signedPreKeySig': signedPreKeySig,
      'signedPreKeyId': 0,
      'registrationId': 0,
      'deviceName': _getDeviceName(),
      'osType': Platform.isIOS ? 'ios' : 'android',
      if (appVersion != null) 'appVersion': appVersion,
    };
  }

  /// Get a human-readable device name.
  static String _getDeviceName() {
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isAndroid) return 'Android';
    return 'Unknown';
  }
}
