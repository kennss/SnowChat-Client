/// @file        signal_session_manager.dart
/// @description High-level manager for Signal Protocol sessions. PreKey upload, session establishment, encrypt/decrypt orchestration
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; Wallet V2 Phase F: getPeerEd25519PublicKey public helper — for TransferService walletAddressSig verification)
///
/// @functions
///  - SignalSessionManager: Signal session management class
///  - SignalSessionManager.initialize(): Restore session store and replenish prekeys
///  - SignalSessionManager.getDeviceId(): Get/create local device ID
///  - SignalSessionManager.uploadPreKeys(): Upload identity key, signed prekey, one-time prekeys to the server
///  - SignalSessionManager.handlePreKeysLow(): Replenish when prekeys are low
///  - SignalSessionManager.checkPreKeyCount(): Query remaining prekey count on server and replenish
///  - SignalSessionManager.ensureSession(): Ensure a session exists with the recipient (X3DH)
///  - SignalSessionManager.encrypt(): Encrypt a message
///  - SignalSessionManager.decrypt(): Decrypt a message
///  - SignalSessionManager.getPeerEd25519PublicKey(): Look up peer's Ed25519 verify key (TOFU cache -> server prekey bundle fallback) — Wallet V2 Phase F
///  - SignalSessionManager.createGroupSenderKey(): Create group Sender Key
///  - SignalSessionManager.processGroupSenderKey(): Process incoming group Sender Key
///  - SignalSessionManager.encryptGroup(): Encrypt group message
///  - SignalSessionManager.decryptGroup(): Decrypt group message
///  - SignalSessionManager.archiveAndResetSession(): Archive session, then re-establish X3DH + notify peer (Phase 10 Mechanism 0 + P1-A)
///  - SignalSessionManager.resetSession(): Backward-compat wrapper for archiveAndResetSession
///  - SignalSessionManager.resetSessionData(): Reset all E2EE session data (on app reset/onboarding)
///  - SignalSessionManager.dispose(): Persist session state and release resources

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../network/socket_manager.dart';
import '../storage/secure_storage.dart';
import 'hkdf.dart' show hkdfDerive;
import 'identity_manager.dart';
import 'identity_pin_store.dart';
import 'session_store.dart';
import 'signal_protocol_service.dart';

/// Higher-level session manager that coordinates between [SignalProtocolService],
/// the SnowChat API server, and local secure storage.
///
/// Responsibilities:
/// - Initialize / restore session store on app start
/// - Upload pre-keys to the server and replenish when low
/// - Establish sessions on-demand by fetching pre-key bundles
/// - Encrypt / decrypt messages (delegates to [SignalProtocolService])
class SignalSessionManager {
  final SignalProtocolService _signal;

  /// Public access to the underlying protocol service (for Tracker access).
  SignalProtocolService get signal => _signal;
  final ApiClient _apiClient;
  final SecureStorageService _secureStorage;
  final IdentityManager _identityManager;
  final SessionStore _sessionStore;
  final SocketManager _socketManager;

  /// Wallet V2 Phase F: TOFU pin store. Reused for `getPeerEd25519PublicKey`
  /// — leverages that the peer's Ed25519 verify key is pinned on the first
  /// X3DH (cache hit). On cache miss, falls back to fetching the prekey
  /// bundle from the server. Optional — null always fetches from the server
  /// (test environment compat).
  final IdentityPinStore? _identityPinStore;

  /// Number of one-time pre-keys to generate per batch.
  static const int preKeyBatchSize = 100;

  /// Threshold at which we proactively generate more pre-keys.
  static const int preKeyLowThreshold = 20;

  /// Secure-storage key for the next pre-key ID counter.
  static const _nextPreKeyIdKey = 'signal_next_prekey_id';

  /// Secure-storage key for the next signed pre-key ID counter.
  static const _nextSignedPreKeyIdKey = 'signal_next_signed_prekey_id';

  /// Secure-storage key for the local device ID.
  /// Reuses AuthService's device_id (UUID) to match server UserDevice record.
  static const _deviceIdKey = 'device_id';

  /// Secure-storage flag: set to 'true' once session store has been encrypted.
  /// Once set, plaintext fallback is permanently disabled (tamper protection).
  static const _storeEncryptedFlagKey = 'signal_store_encrypted';

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Cache of recipient snowchatId → actual device ID (from server prekey bundle).
  final Map<String, String> _recipientDeviceIds = {};

  /// Phase 10 Mechanism 0: Rate limit for session resets.
  /// Maps peer snowchatId → timestamp of last reset.
  /// Prevents rapid-fire resets for the same peer (5 min cooldown).
  final Map<String, DateTime> _lastResetTimestamps = {};

  /// Minimum interval between session resets for the same peer.
  static const Duration _resetCooldown = Duration(minutes: 5);

  // ---------------------------------------------------------------------------
  // Phase 8.2 VoIP — debounced session-store snapshot (2026-04-19)
  //
  // `_signal.saveSessionStore(path)` dumps every peer's session into the file
  // wholesale + SecretBox-encrypts it (measured 100~350ms, per ratchet step).
  // Call signaling bursts encrypt + decrypt within a short window — the main
  // thread gets blocked 100~350ms × N times each, inducing ANR.
  //
  // Per-peer ratchet state is saved immediately by
  // `_sessionStore.saveSessionState()` (10~30ms), so ratchet integrity is
  // preserved. The whole-store snapshot is safe to **debounce**: even if the
  // process is killed within 200ms, the next ensureSession auto-recovers the
  // archived session. Graceful shutdown (`dispose()`) forces an immediate
  // flush.
  //
  // Scope: encrypt / decrypt (high-frequency only). Startup, prekey upload,
  // session reset, group SKDM, dispose, etc. keep immediate save — a
  // conservative start.
  Timer? _saveStoreDebouncer;
  static const Duration _saveStoreDebounceWindow = Duration(milliseconds: 200);

  void _scheduleSaveSessionStore() {
    _saveStoreDebouncer?.cancel();
    _saveStoreDebouncer = Timer(_saveStoreDebounceWindow, () {
      _saveStoreDebouncer = null;
      _saveSessionStore().catchError((Object e) {
        debugPrint('[SignalSessionManager] debounced save failed: $e');
      });
    });
  }

  Future<void> _flushSaveSessionStore() async {
    if (_saveStoreDebouncer != null) {
      _saveStoreDebouncer!.cancel();
      _saveStoreDebouncer = null;
      await _saveSessionStore();
    }
  }

  SignalSessionManager({
    required SignalProtocolService signalService,
    required ApiClient apiClient,
    required SecureStorageService secureStorage,
    required IdentityManager identityManager,
    required SessionStore sessionStore,
    required SocketManager socketManager,
    IdentityPinStore? identityPinStore,
  })  : _signal = signalService,
        _apiClient = apiClient,
        _secureStorage = secureStorage,
        _identityManager = identityManager,
        _sessionStore = sessionStore,
        _socketManager = socketManager,
        _identityPinStore = identityPinStore;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Initialize the session manager.
  /// - Loads persisted session store from disk
  /// - Restores session states from local DB
  /// - Checks remaining pre-keys on the server
  /// - Uploads new pre-keys if needed
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Derive store encryption key from identity private key in secure storage
      // This ensures the session store file is encrypted at rest
      await _setupStoreEncryptionKey();

      // Restore session store from secure storage path
      final storePath = await _sessionStorePath();
      await _signal.loadSessionStore(storePath);

      // Load persisted session states from local DB
      await _sessionStore.initialize();

      // Check if identity key in session store matches secure storage.
      // If different (key was regenerated), sessions are stale → clear them.
      final storedPubKey = await _identityManager.getSignalPublicKey();
      if (storedPubKey != null && _signal.hasIdentityKey) {
        final sessionPubKey = _signal.identityPublicKey;
        if (sessionPubKey != null && !_bytesEqual(storedPubKey, sessionPubKey)) {
          debugPrint('[SignalSessionManager] Identity key changed — clearing stale sessions');
          _signal.clearAllSessions();
          _recipientDeviceIds.clear();
          await _deleteSessionStore();
        }
      }

      // Ensure local identity key exists in both secure storage AND signal service.
      // Also check that Ed25519 signing seed is stored (added in Phase 5).
      final hasIdentity = await _identityManager.hasSignalIdentity();
      final hasSigningSeed = await _identityManager.getSignalSigningSeed() != null;
      if (!hasIdentity || !hasSigningSeed) {
        // Fresh install OR upgrade from pre-Phase5 build → full key generation + upload.
        // Clear ALL existing sessions — they used old keys and are now invalid.
        _signal.clearAllSessions();
        _recipientDeviceIds.clear();
        // Also delete session store file to prevent loadSessionStore from restoring
        await _deleteSessionStore();
        debugPrint('[SignalSessionManager] Missing identity or signing seed '
            '— cleared sessions + store file, generating and uploading pre-keys');
        try {
          await uploadPreKeys();
        } catch (e) {
          debugPrint('[SignalSessionManager] PreKey upload failed (will retry): $e');
        }
      } else {
        // Restore all identity keys from secure storage into SignalProtocolService
        if (!_signal.hasIdentityKey) {
          await _restoreIdentityKeyToSignal();
        }
        try {
          await checkPreKeyCount();
        } catch (e) {
          debugPrint('[SignalSessionManager] PreKey count check failed: $e');
        }

        // Identity key sync is handled by _buildDeviceInfo() in auth_service.dart
        // which sends the real identity key during authenticate().
        // No separate sync needed here — _syncIdentityKeyToServer() was removed
        // because it rotated the signed prekey on every restart, causing
        // X3DH handshake failures for new sessions.
      }

      // Mark initialized if we have local identity (server sync can happen later)
      if (_signal.hasIdentityKey && _signal.signingKeySeed != null) {
        _initialized = true;
        debugPrint('[SignalSessionManager] Initialized successfully');
      } else {
        debugPrint('[SignalSessionManager] Initialization incomplete: '
            'hasIdentity=${_signal.hasIdentityKey}, hasSeed=${_signal.signingKeySeed != null}');
      }
    } catch (e) {
      debugPrint('[SignalSessionManager] Initialization FAILED: $e');
    }
  }

  /// Get the local device ID (shared with AuthService).
  /// Must be called after authentication (AuthService creates the device_id).
  Future<String> getDeviceId() async {
    final deviceId = await _secureStorage.read(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      throw StateError('Device ID not found. Authenticate first.');
    }
    return deviceId;
  }

  // ---------------------------------------------------------------------------
  // Pre-key Management
  // ---------------------------------------------------------------------------

  /// Concurrent-upload guard. Restore + socket-connect race both call upload
  /// paths near-simultaneously; without this, we generate 100 X25519 pairs
  /// twice (~15s wasted). In-flight uploads merge into the same Future so
  /// late callers just await the first upload's result.
  Future<void>? _uploadPreKeysInFlight;

  /// Generate identity key pair, signed pre-key, and one-time pre-keys,
  /// then upload them to the server.
  ///
  /// Called during initial registration and when pre-keys run low.
  /// Server endpoint: POST /api/v2/keys/prekeys
  /// Server expects: { signedPreKey: { keyId, publicKey(b64), signature(b64) },
  ///                   oneTimePreKeys: [{ keyId, publicKey(b64) }] }
  Future<void> uploadPreKeys() async {
    // Merge concurrent calls: if an upload is already running, just await it.
    final inFlight = _uploadPreKeysInFlight;
    if (inFlight != null) {
      debugPrint('[SignalSessionManager] uploadPreKeys merged with in-flight upload');
      return inFlight;
    }
    final future = _doUploadPreKeys();
    _uploadPreKeysInFlight = future;
    try {
      await future;
    } finally {
      _uploadPreKeysInFlight = null;
    }
  }

  Future<void> _doUploadPreKeys() async {
    final _sw = Stopwatch()..start();

    // P1-4 (2026-04-18): defensively ensure the session store encryption key
    // is set BEFORE any _saveSessionStore() call. Without this, a restore-flow
    // path (onboarding `restoreIdentity` → background `_uploadPreKeysWithRetry`
    // → `uploadPreKeys()`) reaches the `await _saveSessionStore()` line below
    // before `initialize()` has run — and would persist PLAINTEXT session
    // material to disk on first install (signal_protocol_service.dart L1081
    // falls back to `writeAsString(jsonEncode(store))` when the key is null).
    //
    // Below we call `_setupStoreEncryptionKey()` first; if it still cannot
    // derive a key (no identity private key in secure storage yet) we
    // skip the save inside _saveSessionStore via the new
    // `_signal.hasStoreEncryptionKey` precondition we add immediately
    // before each save in this method.
    if (!_signal.hasStoreEncryptionKey) {
      await _setupStoreEncryptionKey();
      debugPrint('[Perf]   _setupStoreEncryptionKey (ensure pre-save): '
          '${_sw.elapsedMilliseconds}ms');
      _sw.reset();
    }

    // Ensure Signal identity key + Ed25519 signing seed exist in both
    // secure storage AND signal service. If ANY piece is missing, regenerate all.
    final hasSignalKey = await _identityManager.hasSignalIdentity();
    debugPrint('[Perf]   hasSignalIdentity (read): ${_sw.elapsedMilliseconds}ms');
    _sw.reset();

    if (!hasSignalKey) {
      await _identityManager.generateSignalIdentityKey();
      debugPrint('[Perf]   generateSignalIdentityKey (keygen + 5 writes): ${_sw.elapsedMilliseconds}ms');
      _sw.reset();
    } else if (!_signal.hasIdentityKey) {
      await _restoreIdentityKeyToSignal();
      if (!_signal.hasIdentityKey) {
        await _identityManager.generateSignalIdentityKey();
      }
      debugPrint('[Perf]   restore/regenerate SignalIdentityKey: ${_sw.elapsedMilliseconds}ms');
      _sw.reset();
    }

    // Ed25519 signing seed is required for signed prekey generation.
    // If missing (e.g. upgraded from pre-Phase5 build), generate ONLY the
    // signing seed — do NOT regenerate the X25519 identity key (which would
    // invalidate existing sessions and server-stored keys).
    if (_signal.signingKeySeed == null) {
      debugPrint('[SignalSessionManager] Signing seed missing — generating Ed25519 only');
      _signal.generateSigningKeyIfMissing();
      // Persist the new signing seed to secure storage
      if (_signal.signingKeySeed != null) {
        await _identityManager.saveSigningSeed(
          _signal.signingKeySeed!,
          _signal.verifyKey!,
        );
      }
      debugPrint('[Perf]   signingSeed gen + 2 writes: ${_sw.elapsedMilliseconds}ms');
      _sw.reset();
    }

    final signedPreKeyId = await _nextSignedPreKeyId();
    debugPrint('[Perf]   nextSignedPreKeyId (read): ${_sw.elapsedMilliseconds}ms');
    _sw.reset();

    final signedPreKey = await _signal.generateSignedPreKey(signedPreKeyId);
    debugPrint('[Perf]   generateSignedPreKey: ${_sw.elapsedMilliseconds}ms');
    _sw.reset();

    final preKeyStartId = await _nextPreKeyId();
    debugPrint('[Perf]   nextPreKeyId (read): ${_sw.elapsedMilliseconds}ms');
    _sw.reset();

    final oneTimePreKeys = await _signal.generateOneTimePreKeys(
      preKeyStartId,
      preKeyBatchSize,
    );
    debugPrint('[Perf]   generateOneTimePreKeys ($preKeyBatchSize x X25519): ${_sw.elapsedMilliseconds}ms');
    _sw.reset();

    // Persist the next IDs
    await _secureStorage.write(
      _nextSignedPreKeyIdKey,
      (signedPreKeyId + 1).toString(),
    );
    await _secureStorage.write(
      _nextPreKeyIdKey,
      (preKeyStartId + preKeyBatchSize).toString(),
    );
    debugPrint('[Perf]   2 PreKey ID writes: ${_sw.elapsedMilliseconds}ms');
    _sw.reset();

    // Get the X25519 identity public key to include in upload
    final identityPublicKey = await _identityManager.getSignalPublicKey();
    debugPrint('[Perf]   getSignalPublicKey (read): ${_sw.elapsedMilliseconds}ms');
    _sw.reset();

    // Upload to server -- includes identityKey + Ed25519 verify key for server DB update
    try {
      await _apiClient.post(
        ApiEndpoints.preKeys,
        data: {
          if (identityPublicKey != null)
            'identityKey': _encodeBytes(identityPublicKey),
          if (_signal.verifyKey != null)
            'identityKeyEd25519': _encodeBytes(_signal.verifyKey!),
          'registrationId': _signal.registrationId ?? 0,
          'signedPreKey': {
            'keyId': signedPreKey['keyId'],
            'publicKey': _encodeBytes(signedPreKey['publicKey'] as Uint8List),
            'signature': _encodeBytes(signedPreKey['signature'] as Uint8List),
          },
          'oneTimePreKeys': oneTimePreKeys
              .map((k) => {
                    'keyId': k['keyId'],
                    'publicKey': _encodeBytes(k['publicKey'] as Uint8List),
                  })
              .toList(),
        },
      );
      debugPrint('[Perf]   POST /keys/prekeys (network): ${_sw.elapsedMilliseconds}ms');
      _sw.reset();
      debugPrint(
          '[SignalSessionManager] Uploaded signed prekey #$signedPreKeyId + '
          '$preKeyBatchSize one-time prekeys to server');

      // Phase 8.7 round 6 — CRITICAL fix: persist SPK/OPK private keys to
      // disk immediately after server upload. Without this call the freshly
      // generated private keys live ONLY in the signal service's in-memory
      // map. If the user kills the app before any other code path triggers
      // _saveSessionStore (e.g. a decrypt that advances the ratchet), the
      // next cold start loads an empty session store, and every incoming
      // X3DH prekey message fails with "Signed prekey X not found,
      // available: []" — forever, because the server already stored the
      // public keys and every peer will keep using them.
      //
      // Reproduction: CCC (5554) onboards → uploadPreKeys succeeds (server
      // has real SPK/OPK) → user swipe-kills before any message arrives →
      // restart → SessionStore.loadFromDB returns 0 sessions → SPK map is
      // [] → every SKDM wrapper from every peer dead-letters with 'Signed
      // prekey 1 not found'. Lost all X3DH private keys permanently.
      await _saveSessionStore();
      debugPrint('[SignalSessionManager] Session store persisted after '
          'uploadPreKeys');
    } catch (e) {
      debugPrint('[SignalSessionManager] Failed to upload pre-keys: $e');
      rethrow;
    }
  }

  /// Called when the server notifies us that pre-keys are running low.
  Future<void> handlePreKeysLow(int remaining) async {
    debugPrint(
        '[SignalSessionManager] Pre-keys low: $remaining remaining, generating more');
    if (remaining < preKeyLowThreshold) {
      await _uploadOneTimePreKeys();
    }
  }

  /// Check remaining pre-key count on server and replenish if below threshold.
  /// Server endpoint: GET /api/v2/keys/prekey-count
  /// Server returns: { count: int }
  Future<void> checkPreKeyCount() async {
    // Race guard: if restoreIdentity or another caller is currently uploading
    // prekeys, the server's count is still stale (upload hasn't landed yet).
    // Skip this check entirely — the in-flight upload will satisfy both the
    // count and the Ed25519 key requirements.
    if (_uploadPreKeysInFlight != null) {
      debugPrint('[SignalSessionManager] checkPreKeyCount skipped — '
          'full upload already in-flight');
      return;
    }
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        ApiEndpoints.preKeyCount,
      );
      final remaining = response.data?['count'] as int? ?? 0;
      final hasEd25519 = response.data?['hasEd25519'] as bool? ?? false;
      debugPrint(
          '[SignalSessionManager] Server has $remaining pre-keys remaining, '
          'hasEd25519=$hasEd25519');
      // If server has 0 pre-keys (e.g. DB was reset), our sessions are stale.
      // Clear all sessions and do a full re-upload.
      if (remaining == 0) {
        debugPrint('[SignalSessionManager] Server has 0 prekeys — clearing stale sessions');
        _signal.clearAllSessions();
        _recipientDeviceIds.clear();
        await _deleteSessionStore();
      }
      // If a full upload is needed (missing Ed25519), do ONLY that — it
      // already uploads 100 one-time prekeys, so _uploadOneTimePreKeys below
      // would duplicate work.
      if (!hasEd25519 && _signal.verifyKey != null) {
        debugPrint('[SignalSessionManager] Server missing Ed25519 key — triggering full upload');
        await uploadPreKeys();
        return;
      }
      if (remaining < preKeyLowThreshold) {
        await _uploadOneTimePreKeys();
      }
    } catch (e) {
      // Non-fatal: we'll check again later
      debugPrint('[SignalSessionManager] Could not check pre-key count: $e');
    }
  }

  /// Sync our real identity key + signed prekey to the server device record.
  /// This fixes devices that have a placeholder identity key from old
  /// authenticate() calls that sent all-zero keys in deviceInfo.
  /// Runs once per initialize() — no OPKs generated, lightweight POST.
  Future<void> _syncIdentityKeyToServer() async {
    final identityKey = await _identityManager.getSignalPublicKey();
    if (identityKey == null) return;

    final signedPreKeyId = await _nextSignedPreKeyId();
    final signedPreKey = await _signal.generateSignedPreKey(signedPreKeyId);
    await _secureStorage.write(
      _nextSignedPreKeyIdKey,
      (signedPreKeyId + 1).toString(),
    );

    await _apiClient.post(
      ApiEndpoints.preKeys,
      data: {
        'identityKey': _encodeBytes(identityKey),
        // Always include Ed25519 verify key when syncing identity key.
        // After DB reset, the server may have lost the Ed25519 key, which
        // causes peers to get identityKeyEd25519=null in prekey bundles.
        if (_signal.verifyKey != null)
          'identityKeyEd25519': _encodeBytes(_signal.verifyKey!),
        'registrationId': _signal.registrationId ?? 0,
        'signedPreKey': {
          'keyId': signedPreKey['keyId'],
          'publicKey': _encodeBytes(signedPreKey['publicKey'] as Uint8List),
          'signature': _encodeBytes(signedPreKey['signature'] as Uint8List),
        },
        'oneTimePreKeys': <Map<String, dynamic>>[],
      },
    );
    debugPrint('[SignalSessionManager] Identity key + Ed25519 synced to server');
  }

  // ---------------------------------------------------------------------------
  // Session Establishment
  // ---------------------------------------------------------------------------

  /// Ensure we have an active session with [recipientSnowchatId].
  /// If no session exists, fetch the recipient's pre-key bundle from the
  /// server and establish a new session via X3DH.
  ///
  /// Server endpoint: GET /api/v2/keys/prekeys/:snowchatId
  /// Server returns: { devices: [{ deviceId, identityKey, registrationId,
  ///                    signedPreKey: { keyId, publicKey, signature },
  ///                    oneTimePreKey: { keyId, publicKey } | null }] }
  /// Maximum retries when recipient's prekey bundle is not yet available.
  /// After DB reset, the recipient may still be uploading prekeys.
  static const _ensureSessionMaxRetries = 3;
  static const _ensureSessionRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  Future<void> ensureSession(String recipientSnowchatId) async {
    assert(
      recipientSnowchatId.length == 36 &&
          recipientSnowchatId.startsWith('snow'),
      'Invalid SnowChat ID: $recipientSnowchatId',
    );

    // Check local session store first (fast path)
    final cachedDeviceId = _recipientDeviceIds[recipientSnowchatId];
    if (cachedDeviceId != null) {
      final hasNativeSession =
          await _signal.hasSession(recipientSnowchatId, cachedDeviceId);
      if (hasNativeSession) {
        return; // Session already active
      }
    }

    // Fetch recipient's pre-key bundle from server — retry on 404
    // (recipient may still be uploading prekeys after DB reset/restore)
    for (var attempt = 0; attempt <= _ensureSessionMaxRetries; attempt++) {
      try {
        final response = await _apiClient.get<Map<String, dynamic>>(
          ApiEndpoints.preKeysForUser(recipientSnowchatId),
        );

        final data = response.data;
        if (data == null) {
          throw SignalProtocolException(
            'No pre-key bundle available for $recipientSnowchatId',
          );
        }

        final devices = data['devices'] as List<dynamic>?;
        if (devices == null || devices.isEmpty) {
          throw SignalProtocolException(
            'No devices found for $recipientSnowchatId',
          );
        }

        // Establish session with each device (cache first device ID)
        for (final deviceData in devices) {
          final device = deviceData as Map<String, dynamic>;
          final deviceId = device['deviceId'] as String;

          // Cache the first device ID for this recipient
          _recipientDeviceIds.putIfAbsent(
              recipientSnowchatId, () => deviceId);

          final exists =
              await _signal.hasSession(recipientSnowchatId, deviceId);
          if (!exists) {
            await _establishSession(recipientSnowchatId, deviceId, device);
          }
        }
        return; // Success — exit retry loop
      } catch (e) {
        final is404 = e.toString().contains('404') ||
            e.toString().contains('DEVICE_NOT_FOUND') ||
            e.toString().contains('No devices');

        if (is404 && attempt < _ensureSessionMaxRetries) {
          debugPrint(
              '[SignalSessionManager] Prekey bundle not ready for '
              '$recipientSnowchatId, retry ${attempt + 1}/$_ensureSessionMaxRetries '
              'in ${_ensureSessionRetryDelays[attempt].inSeconds}s');
          await Future.delayed(_ensureSessionRetryDelays[attempt]);
          continue; // Retry
        }

        debugPrint(
            '[SignalSessionManager] Failed to ensure session with '
            '$recipientSnowchatId after ${attempt + 1} attempts: $e');
        rethrow;
      }
    }
  }

  /// Get the cached device ID for a recipient.
  ///
  /// Phase 8.7 Bug A: the previous implementation silently fell back to the
  /// placeholder string 'primary' on cache miss. That caused the sender to
  /// store/encrypt under session key `(recipient, 'primary')` while the
  /// recipient stored under their real device UUID — permanent decrypt
  /// failure. Callers MUST invoke [ensureSession] (or [ensureSessionBatch]
  /// followed by [hasDeviceIdFor] verification) before calling this method.
  Future<String> getDeviceIdForRecipient(String recipientSnowchatId) async {
    final cached = _recipientDeviceIds[recipientSnowchatId];
    if (cached == null) {
      throw StateError(
        'getDeviceIdForRecipient: no cached deviceId for '
        '$recipientSnowchatId. Caller must invoke ensureSession() first.',
      );
    }
    return cached;
  }

  /// Phase 8.7 Bug A helper: check whether the device-id cache is populated
  /// for the given recipient. Use after [ensureSessionBatch] to detect
  /// stragglers that need an individual [ensureSession] retry before sending.
  bool hasDeviceIdFor(String recipientSnowchatId) =>
      _recipientDeviceIds.containsKey(recipientSnowchatId);

  /// Phase 8.7 Bug A helper for the receive path.
  ///
  /// Returns the cached deviceId if present. Otherwise — used only when
  /// processing an incoming message that already carries the sender's
  /// authoritative deviceId in its socket envelope — adopts that incoming
  /// value via [putIfAbsent] semantics so subsequent interactions stay
  /// consistent. Throws [StateError] only when both the cache and the
  /// incoming hint are missing (a real bug condition).
  String learnDeviceIdFromIncoming(
    String senderSnowchatId,
    String? incomingDeviceId,
  ) {
    final cached = _recipientDeviceIds[senderSnowchatId];
    if (cached != null) return cached;
    if (incomingDeviceId != null && incomingDeviceId.isNotEmpty) {
      _recipientDeviceIds[senderSnowchatId] = incomingDeviceId;
      return incomingDeviceId;
    }
    throw StateError(
      'learnDeviceIdFromIncoming: no cached deviceId for $senderSnowchatId '
      'and the incoming envelope did not provide one.',
    );
  }

  /// Phase 10 Mechanism 0: Archive the stale session and re-establish via X3DH.
  ///
  /// Unlike the previous hard-delete approach, this method **archives** the
  /// existing session(s) before creating a new one. Archived sessions are kept
  /// for 1 hour (Signal pattern) so that in-flight messages encrypted under
  /// the old ratchet can still be decrypted.
  ///
  /// Rate limited: same peer can only be reset once per 5 minutes to prevent
  /// rapid-fire reset loops (e.g. both peers resetting simultaneously).
  ///
  /// Atomicity: archiveSession() completes and is persisted BEFORE
  /// ensureSession() fetches the prekey bundle and runs X3DH. This guarantees
  /// that even if ensureSession() fails, the old sessions are safely archived.
  ///
  /// Triggered after repeated `SignalProtocolException` decrypt failures
  /// indicate the local Double Ratchet state has diverged from the peer
  /// (typically due to dropped chain hops, multi-device skew, or restored
  /// session stores).
  ///
  /// NOTE: this is a unilateral reset. The peer will only sync once we
  /// send the next outbound message (which becomes a new prekey msg).
  Future<void> archiveAndResetSession(
    String snowId, {
    bool force = false,
  }) async {
    // Rate limit check: skip if last reset for this peer was < 5 min ago.
    // [force]=true bypasses the cooldown — used by the retry_handler path
    // (2026-04-24 deadlock fix) where the peer explicitly asked for a resend,
    // meaning the current session is definitively broken and deferring the
    // reset only extends the deadlock.
    if (!force) {
      final lastReset = _lastResetTimestamps[snowId];
      if (lastReset != null) {
        final elapsed = DateTime.now().difference(lastReset);
        if (elapsed < _resetCooldown) {
          debugPrint('[SignalSessionManager] archiveAndResetSession SKIPPED '
              'for $snowId — last reset ${elapsed.inSeconds}s ago '
              '(cooldown: ${_resetCooldown.inSeconds}s)');
          return;
        }
      }
    } else {
      debugPrint('[SignalSessionManager] archiveAndResetSession FORCED '
          'for $snowId — bypassing cooldown');
    }

    final deviceId = _recipientDeviceIds[snowId];
    debugPrint('[SignalSessionManager] archiveAndResetSession START '
        'snowId=$snowId cachedDeviceId=$deviceId');

    // Step 1: Archive existing sessions (NOT delete).
    // This MUST complete before ensureSession() to guarantee atomicity.
    if (deviceId != null) {
      try {
        await _signal.archiveSession(snowId, deviceId);
      } catch (e) {
        debugPrint('[SignalSessionManager] archiveAndResetSession '
            'archiveSession error (non-fatal): $e');
      }
    }
    _recipientDeviceIds.remove(snowId);

    // Step 2: Persist the archived state to disk immediately.
    // If the app crashes after this point but before ensureSession(),
    // the archived sessions survive and can still decrypt in-flight messages.
    try {
      await _saveSessionStore();
    } catch (e) {
      debugPrint('[SignalSessionManager] archiveAndResetSession persist '
          'error (non-fatal): $e');
    }

    // Step 3: Establish a fresh session via X3DH prekey bundle fetch.
    await ensureSession(snowId);

    // Record the reset timestamp for rate limiting
    _lastResetTimestamps[snowId] = DateTime.now();

    // Step 4 (P1-A): Send session_reset notification to the peer.
    // This is a prekey message (type 2) which automatically establishes
    // the new session on the peer's side when they process it.
    try {
      final deviceId = await getDeviceIdForRecipient(snowId);
      final resetPayload = utf8.encode(jsonEncode({
        'type': 'system',
        'text': '',
        'metadata': {'isSessionReset': true},
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));
      final encrypted = await encrypt(
        snowId,
        deviceId,
        Uint8List.fromList(resetPayload),
      );
      _socketManager.sendPrivateMessage({
        'recipientId': snowId,
        'encryptedContent':
            base64Encode(encrypted['ciphertext'] as Uint8List),
        'messageType': encrypted['messageType'] as int,
        'type': 'session_reset',
        'metadata': jsonEncode({'isSessionReset': true}),
      });
      debugPrint('[SessionMgr] Session reset notification sent');
    } catch (e) {
      // Non-fatal — the new session will still work for future messages
      debugPrint('[SessionMgr] Session reset notification failed: $e');
    }

    debugPrint('[SignalSessionManager] archiveAndResetSession DONE');
  }

  /// Backward-compatible wrapper for [archiveAndResetSession].
  ///
  /// Existing callers (e.g. message_queue.dart retry logic) can continue
  /// calling resetSession() without modification. Internally delegates to
  /// archiveAndResetSession() which archives instead of hard-deleting.
  Future<void> resetSession(String snowId) async {
    await archiveAndResetSession(snowId);
  }

  /// Ensure sessions with multiple recipients in one batch API call (Phase 5.2).
  /// Significantly faster than calling ensureSession() 1024 times sequentially.
  Future<void> ensureSessionBatch(List<String> recipientIds) async {
    // Filter to only those needing a new session
    final needSession = <String>[];
    for (final id in recipientIds) {
      final cachedDeviceId = _recipientDeviceIds[id];
      if (cachedDeviceId != null) {
        final has = await _signal.hasSession(id, cachedDeviceId);
        if (has) continue;
      }
      needSession.add(id);
    }
    if (needSession.isEmpty) return;

    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '${ApiEndpoints.preKeys}/batch',
        data: {'snowchatIds': needSession},
      );
      final bundles = response.data?['bundles'] as Map<String, dynamic>? ?? {};
      for (final entry in bundles.entries) {
        final snowchatId = entry.key;
        final bundleData = entry.value as Map<String, dynamic>;
        final devices = bundleData['devices'] as List<dynamic>?;
        if (devices == null || devices.isEmpty) continue;
        for (final deviceData in devices) {
          final device = deviceData as Map<String, dynamic>;
          final deviceId = device['deviceId'] as String;
          _recipientDeviceIds.putIfAbsent(snowchatId, () => deviceId);
          final exists = await _signal.hasSession(snowchatId, deviceId);
          if (!exists) {
            await _establishSession(snowchatId, deviceId, device);
          }
        }
      }
    } catch (e) {
      debugPrint('[SignalSessionManager] Batch session failed: $e');
      // Fallback: establish individually
      for (final id in needSession) {
        try {
          await ensureSession(id);
        } catch (_) {}
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Encrypt / Decrypt
  // ---------------------------------------------------------------------------

  /// Encrypt [plaintext] for [recipientId]:[deviceId].
  /// Caller must ensure a session exists first (call [ensureSession]).
  ///
  /// Returns { 'ciphertext': Uint8List, 'messageType': int }
  /// where messageType 1 = normal cipher, 2 = pre-key message.
  Future<Map<String, dynamic>> encrypt(
    String recipientId,
    String deviceId,
    Uint8List plaintext,
  ) async {
    _assertInitialized();
    try {
      final result = await _signal.encryptMessage(
        recipientId: recipientId,
        deviceId: deviceId,
        plaintext: plaintext,
      );

      // Persist per-peer ratchet state immediately (10-30ms, fast path).
      // Whole-store snapshot is debounced — see `_scheduleSaveSessionStore`.
      _scheduleSaveSessionStore();
      await _sessionStore.saveSessionState(
        recipientId: recipientId,
        deviceId: deviceId,
      );

      return result;
    } on SignalProtocolException catch (e) {
      debugPrint('[SignalSessionManager] Encrypt error: $e');
      rethrow;
    }
  }

  /// Decrypt [ciphertext] from [senderId]:[deviceId].
  /// [messageType]: 1 = normal ciphertext, 2 = pre-key message (first message).
  ///
  /// For messageType 2 (pre-key messages), the session is automatically
  /// established from the initial message before decryption.
  ///
  /// P0-2 Stage 4 (receive-side TOFU): for prekey envelopes (messageType==2)
  /// we proactively fetch the sender's Ed25519 verify key from the prekey-
  /// bundle endpoint and forward it into the Signal layer so the new session
  /// is TOFU-checked against [_identityPinStore] BEFORE any X3DH state is
  /// installed. A mismatch raises [IdentityKeyChangedException] at the lower
  /// layer; the queue's typed catch in message_queue.dart converts that into
  /// the Safety-Number system message + DAO latch + dead-letter ACK pipeline.
  Future<Uint8List> decrypt(
    String senderId,
    String deviceId,
    Uint8List ciphertext,
    int messageType,
  ) async {
    _assertInitialized();

    // Pre-fetch sender Ed25519 verify key when this could trigger
    // _receiveSession. We always fetch on messageType == 2 — the existing
    // session might be missing (cold start, peer rotation, archived) so the
    // signal layer may fall through to _receiveSession. If a session exists
    // and trial-decrypts, the fetched key is simply unused.
    Uint8List? senderEd25519;
    if (messageType == 2) {
      try {
        senderEd25519 = await _fetchSenderEd25519(senderId);
      } catch (e) {
        // Surface as a SignalProtocolException so the queue treats this as
        // a normal ratchet failure (retry via backoff) rather than a TOFU
        // mismatch. Retries are bounded; persistent failure dead-letters.
        throw SignalProtocolException(
          'Failed to fetch sender Ed25519 key for prekey envelope from '
          '$senderId: $e',
        );
      }
    }

    try {
      // [DIAG-VOIP-2026-04-19] decrypt step timing — separate cipher vs disk I/O. Remove after diagnosis.
      final sw = Stopwatch()..start();
      final result = await _signal.decryptMessage(
        senderId: senderId,
        deviceId: deviceId,
        ciphertext: ciphertext,
        messageType: messageType,
        senderIdentityKeyEd25519: senderEd25519,
      );
      final cipherMs = sw.elapsedMilliseconds;

      // Cache the deviceId used for this sender so future lookups are
      // consistent. Without this, the first decrypt uses 'primary' (fallback)
      // but a later ensureSession populates the cache with the real deviceId,
      // causing session key mismatch (e.g. 'snowA:primary' vs 'snowA:uuid').
      _recipientDeviceIds.putIfAbsent(senderId, () => deviceId);

      // Persist per-peer ratchet state immediately (10-30ms).
      // Whole-store snapshot is debounced (see `_scheduleSaveSessionStore`).
      _scheduleSaveSessionStore();
      await _sessionStore.saveSessionState(
        recipientId: senderId,
        deviceId: deviceId,
      );
      final saveStateMs = sw.elapsedMilliseconds - cipherMs;
      debugPrint('[DIAG:SigDecrypt] cipher=${cipherMs}ms '
          'saveState=${saveStateMs}ms total=${sw.elapsedMilliseconds}ms '
          'ctextLen=${ciphertext.length}');

      return result;
    } on SignalProtocolException catch (e, st) {
      debugPrint('[SignalSessionManager] Decrypt error: $e\n$st');
      rethrow;
    } catch (e, st) {
      debugPrint('[SignalSessionManager] Decrypt unexpected error: $e\n$st');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Group Operations
  // ---------------------------------------------------------------------------

  /// Create and distribute a sender key for [groupId].
  /// Returns the sender key distribution message to send to group members.
  Future<Map<String, dynamic>> createGroupSenderKey(
    String groupId, {
    String? myId,
  }) async {
    _assertInitialized();
    final result = await _signal.createSenderKey(groupId, myId: myId);
    await _saveSessionStore();
    return result;
  }

  /// Process a received sender key from another group member.
  Future<void> processGroupSenderKey(
    String groupId,
    String senderId,
    Map<String, dynamic> senderKeyMessage,
  ) async {
    _assertInitialized();
    await _signal.processSenderKey(groupId, senderId, senderKeyMessage);
    await _saveSessionStore();
  }

  /// Encrypt a group message.
  Future<Uint8List> encryptGroup(
    String groupId,
    Uint8List plaintext, {
    String? myId,
  }) async {
    _assertInitialized();
    final result = await _signal.encryptGroupMessage(
      groupId,
      plaintext,
      myId: myId,
    );
    await _saveSessionStore();
    return result;
  }

  /// Decrypt a group message.
  Future<Uint8List> decryptGroup(
    String groupId,
    String senderId,
    Uint8List ciphertext,
  ) async {
    _assertInitialized();
    final result =
        await _signal.decryptGroupMessage(groupId, senderId, ciphertext);
    await _saveSessionStore();
    return result;
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Wipe all E2EE session data: in-memory sessions, session store file, DB.
  /// Call this on app reset or before fresh onboarding to prevent stale
  /// Double Ratchet state from surviving across server DB resets.
  Future<void> resetSessionData() async {
    _signal.clearAllSessions();
    _recipientDeviceIds.clear();
    await _deleteSessionStore();
    await _sessionStore.deleteAll();
    _initialized = false;
    debugPrint('[SignalSessionManager] All session data reset');
  }

  /// Persist current session state and release resources.
  Future<void> dispose() async {
    if (_initialized) {
      // Cancel any pending debounced save then force-flush — guarantees the
      // latest in-memory store snapshot reaches disk before shutdown.
      await _flushSaveSessionStore();
      await _saveSessionStore();
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Restore ALL identity keys from secure storage into SignalProtocolService.
  /// Restores: X25519 identity pair, Ed25519 signing seed/verify key, registration ID.
  Future<void> _restoreIdentityKeyToSignal() async {
    // X25519 identity key pair
    final publicKey = await _identityManager.getSignalPublicKey();
    final privateKey = await _identityManager.getSignalPrivateKey();
    if (publicKey != null && privateKey != null) {
      _signal.setIdentityKeyPair(publicKey, privateKey);
    } else {
      debugPrint('[SignalSessionManager] No X25519 identity key in secure storage');
      return;
    }

    // Ed25519 signing seed + verify key
    final signingSeed = await _identityManager.getSignalSigningSeed();
    final verifyKey = await _identityManager.getSignalVerifyKey();
    if (signingSeed != null && verifyKey != null) {
      _signal.setSigningKey(signingSeed, verifyKey);
    }

    // Registration ID
    final regId = await _identityManager.getSignalRegistrationId();
    if (regId != null) {
      _signal.setRegistrationId(regId);
    }

    debugPrint('[SignalSessionManager] Restored all identity keys from secure storage');
  }

  void _assertInitialized() {
    if (!_initialized) {
      throw StateError(
          'SignalSessionManager not initialized. Call initialize() first.');
    }
  }

  Future<String> _sessionStorePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/signal_session_store.bin';
  }

  /// Derive a 32-byte encryption key for the session store file from the
  /// identity private key in secure storage. This ensures the store is
  /// encrypted at rest without needing a separate passphrase.
  /// Also restores the persistent "store was encrypted" flag from secure storage
  /// so that plaintext fallback is disabled once encryption has been used.
  Future<void> _setupStoreEncryptionKey() async {
    final privateKey = await _identityManager.getSignalPrivateKey();
    if (privateKey != null) {
      final storeKey = hkdfDerive(
        ikm: privateKey,
        salt: Uint8List.fromList(utf8.encode('SnowChat_StoreKey')),
        info: Uint8List.fromList(utf8.encode('session_store_encryption')),
        length: 32,
      );
      _signal.setStoreEncryptionKey(storeKey);

      // Restore persistent flag: once encrypted, never allow plaintext fallback
      final flag = await _secureStorage.read(_storeEncryptedFlagKey);
      if (flag == 'true') {
        _signal.markStoreEncrypted();
      }
    }
  }

  /// Public method for GroupSessionManager to trigger session store save.
  /// Includes SenderKeyManager state in the persisted data.
  Future<void> saveGroupState() async => _saveSessionStore();

  Future<void> _saveSessionStore() async {
    final path = await _sessionStorePath();
    // Persist the "store encrypted" flag to secure storage on first encrypted save
    if (_signal.isStoreEncrypted) {
      await _secureStorage.write(_storeEncryptedFlagKey, 'true');
    }
    await _signal.saveSessionStore(path);
  }

  Future<void> _deleteSessionStore() async {
    try {
      final path = await _sessionStorePath();
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[SignalSessionManager] Session store file deleted');
      }
    } catch (e) {
      debugPrint('[SignalSessionManager] Failed to delete session store: $e');
    }
  }

  /// Upload only one-time pre-keys (used for replenishment).
  Future<void> _uploadOneTimePreKeys() async {
    final startId = await _nextPreKeyId();
    final preKeys = await _signal.generateOneTimePreKeys(
      startId,
      preKeyBatchSize,
    );

    await _secureStorage.write(
      _nextPreKeyIdKey,
      (startId + preKeyBatchSize).toString(),
    );

    // Re-upload with a fresh signed prekey as well (server requires it)
    final signedPreKeyId = await _nextSignedPreKeyId();
    final signedPreKey = await _signal.generateSignedPreKey(signedPreKeyId);

    await _secureStorage.write(
      _nextSignedPreKeyIdKey,
      (signedPreKeyId + 1).toString(),
    );

    // Always include identityKey + registrationId to keep server in sync
    final identityPublicKey = await _identityManager.getSignalPublicKey();

    try {
      await _apiClient.post(
        ApiEndpoints.preKeys,
        data: {
          if (identityPublicKey != null)
            'identityKey': _encodeBytes(identityPublicKey),
          'registrationId': _signal.registrationId ?? 0,
          'signedPreKey': {
            'keyId': signedPreKey['keyId'],
            'publicKey': _encodeBytes(signedPreKey['publicKey'] as Uint8List),
            'signature': _encodeBytes(signedPreKey['signature'] as Uint8List),
          },
          'oneTimePreKeys': preKeys
              .map((k) => {
                    'keyId': k['keyId'],
                    'publicKey': _encodeBytes(k['publicKey'] as Uint8List),
                  })
              .toList(),
        },
      );
      debugPrint(
          '[SignalSessionManager] Replenished ${preKeys.length} one-time prekeys');
    } catch (e) {
      debugPrint('[SignalSessionManager] Failed to replenish prekeys: $e');
      rethrow;
    }
  }

  /// Establish a session with a specific device using fetched pre-key bundle data.
  Future<void> _establishSession(
    String recipientId,
    String deviceId,
    Map<String, dynamic> deviceBundle,
  ) async {
    try {
      // Decode base64-encoded keys from server response
      final bundle = _decodePreKeyBundle(deviceBundle);

      // Validate: reject all-zero identity keys (server placeholder)
      final idKey = bundle['identityKey'] as Uint8List?;
      if (idKey == null || idKey.every((b) => b == 0)) {
        throw SignalProtocolException(
          'Recipient has not uploaded real identity key yet',
        );
      }

      await _signal.createSession(
        recipientId: recipientId,
        deviceId: deviceId,
        preKeyBundle: bundle,
      );

      // Persist session to local store
      await _saveSessionStore();
      await _sessionStore.saveSessionState(
        recipientId: recipientId,
        deviceId: deviceId,
      );

      debugPrint(
          '[SignalSessionManager] Session established with $recipientId:$deviceId');
    } catch (e) {
      debugPrint(
          '[SignalSessionManager] Failed to establish session with '
          '$recipientId:$deviceId: $e');
      rethrow;
    }
  }

  Future<int> _nextPreKeyId() async {
    final stored = await _secureStorage.read(_nextPreKeyIdKey);
    return stored != null ? int.parse(stored) : 1;
  }

  Future<int> _nextSignedPreKeyId() async {
    final stored = await _secureStorage.read(_nextSignedPreKeyIdKey);
    return stored != null ? int.parse(stored) : 1;
  }

  /// Wallet V2 Phase F — look up peer's Signal Ed25519 identity verify key.
  ///
  /// **Use**: TransferService's `_verifyWalletAddressSig` (P1-5) — verify
  /// the Ed25519 signature on the walletAddress the peer responded with.
  ///
  /// **Lookup priority**:
  /// 1. **IdentityPinStore TOFU cache** — the key pinned on first X3DH
  ///    (most trusted).
  /// 2. **Server prekey bundle** (`GET /keys/prekeys/:snowId`) — on pin
  ///    cache miss, fetch via `_fetchSenderEd25519` and store the result
  ///    into the pin.
  ///
  /// **Returns**: 32-byte raw Ed25519 verify key (Uint8List).
  ///   - null if peer is legacy pre-Phase5 (no Ed25519).
  ///   - throws on transient failures (network errors etc.) — caller
  ///     decides whether to retry.
  ///
  /// **Security note**: pin cache takes precedence, so a fake Ed25519 key
  /// freshly pushed by a server compromise after the first X3DH is ignored
  /// (TOFU integrity).
  Future<Uint8List?> getPeerEd25519PublicKey(String peerSnowchatId) async {
    if (peerSnowchatId.isEmpty) return null;

    // Step 1: TOFU pin cache (fast path).
    final pinStore = _identityPinStore;
    if (pinStore != null) {
      try {
        final pinned = await pinStore.getPinned(peerSnowchatId);
        if (pinned != null && pinned.isNotEmpty) {
          return pinned;
        }
      } catch (e) {
        // Pin store read failure is not fatal — fall back to server.
        debugPrint('[SignalSessionManager] getPeerEd25519PublicKey '
            'pin store read failed (fallback to server): $e');
      }
    }

    // Step 2: Server prekey bundle fallback.
    try {
      final ed25519 = await _fetchSenderEd25519(peerSnowchatId);
      // On successful server lookup, also store the pin (pre-pinning before
      // the first X3DH → no mismatch when X3DH later runs with the same
      // key). Skip in test environments where pinStore is null.
      if (ed25519 != null && pinStore != null) {
        try {
          await pinStore.pin(peerSnowchatId, ed25519);
        } catch (e) {
          debugPrint('[SignalSessionManager] getPeerEd25519PublicKey '
              'pin write failed (non-fatal): $e');
        }
      }
      return ed25519;
    } catch (e) {
      debugPrint('[SignalSessionManager] getPeerEd25519PublicKey '
          'server fetch failed for $peerSnowchatId: $e');
      rethrow;
    }
  }

  /// P0-2 Stage 4: fetch the sender's Ed25519 verify key from the prekey
  /// bundle endpoint, used to TOFU-check incoming prekey envelopes
  /// (messageType==2) before installing a fresh receive session.
  ///
  /// Returns the raw 32-byte verify key. Throws if the bundle is missing or
  /// has no devices — that turns into a SignalProtocolException at the
  /// caller and the message is retried under the queue's normal backoff
  /// (it will NOT be silently treated as a mismatch).
  ///
  /// Returns null if the server responded but the device record genuinely
  /// has no Ed25519 key (legacy pre-Phase5 peer). In that case the lower
  /// layer applies the fail-closed policy and refuses the session.
  Future<Uint8List?> _fetchSenderEd25519(String senderSnowchatId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.preKeysForUser(senderSnowchatId),
    );
    final data = response.data;
    if (data == null) {
      throw StateError('No prekey bundle returned for $senderSnowchatId');
    }
    final devices = data['devices'] as List<dynamic>?;
    if (devices == null || devices.isEmpty) {
      throw StateError('No devices in prekey bundle for $senderSnowchatId');
    }
    // Use the first device's Ed25519 key. Multi-device support (Stage B/C)
    // will key this by deviceId; today there is exactly one device per
    // SnowChat ID.
    final device = devices.first as Map<String, dynamic>;
    final ed25519 = device['identityKeyEd25519'];
    if (ed25519 == null) return null;
    return _safeDecodeKey(ed25519);
  }

  /// Decode base64-encoded keys from the server's PreKeyBundleDevice response.
  Map<String, dynamic> _decodePreKeyBundle(Map<String, dynamic> raw) {
    final signedPreKey = raw['signedPreKey'] as Map<String, dynamic>;

    return {
      'identityKey': _safeDecodeKey(raw['identityKey']),
      if (raw['identityKeyEd25519'] != null)
        'identityKeyEd25519': _safeDecodeKey(raw['identityKeyEd25519']),
      'signedPreKey': {
        'keyId': signedPreKey['keyId'],
        'publicKey': _safeDecodeKey(signedPreKey['publicKey']),
        'signature': _safeDecodeKey(signedPreKey['signature']),
      },
      if (raw['oneTimePreKey'] != null)
        'oneTimePreKey': {
          'keyId': (raw['oneTimePreKey'] as Map<String, dynamic>)['keyId'],
          'publicKey': _safeDecodeKey(
              (raw['oneTimePreKey'] as Map<String, dynamic>)['publicKey']),
        },
      'registrationId': raw['registrationId'],
    };
  }

  static String _encodeBytes(Uint8List bytes) => base64Encode(bytes);
  static Uint8List _decodeBytes(String b64) => base64Decode(b64);

  /// Constant-time byte comparison — prevents timing side-channel leaks
  /// when comparing identity keys or other secret material.
  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Decode a key value from the server prekey bundle.
  /// Server always sends base64 (Buffer.toString('base64')).
  /// Only treat as hex if the string is exactly 64 chars (32 bytes hex-encoded)
  /// AND contains no base64-specific chars, to avoid misidentifying base64
  /// strings that happen to contain only hex-valid characters.
  static Uint8List _safeDecodeKey(dynamic value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    final str = value as String;
    // Hex detection: exactly 64 hex chars = 32 bytes (X25519 key size).
    // base64 of 32 bytes = 44 chars, so 64-char strings are unambiguously hex.
    if (str.length == 64 &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(str)) {
      final bytes = <int>[];
      for (var i = 0; i < str.length; i += 2) {
        bytes.add(int.parse(str.substring(i, i + 2), radix: 16));
      }
      return Uint8List.fromList(bytes);
    }
    // Default: base64 (server's standard encoding)
    return base64Decode(str);
  }

}
