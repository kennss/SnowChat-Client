/// @file        signal_session_manager.dart
/// @description High-level manager for Signal Protocol sessions. PreKey upload, session establishment, encrypt/decrypt orchestration
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-10 (B-2 Identity Binding v1: every POST /keys/prekeys body (full upload AND OPK replenish) carries identityKeyEd25519 + identityBinding; checkPreKeyCount() self-checks hasIdentityBinding/identityBindingEpoch against the server and repairs via PUT /keys/identity-binding; ensureSession picks the highest-epoch validly-bound device and never retries a hard identity rejection (memoized cooldown, no OPK burn); ensureSessionBatch is per-entry fault isolated; decrypt() hands the envelope deviceId + a cached non-consuming GET /keys/identity lookup to the Signal layer instead of pre-fetching a TOFU pin; the incoming deviceId is cached only after a verified decrypt; getPeerEd25519PublicKey returns the bound Ed (verified directory fallback). Removed dead _syncIdentityKeyToServer (posted keys without a binding)). Earlier 2026-05-05 (Fix A: pin-cache-first on msgType=2 decrypt — eliminates the ~500ms HTTP race that let sealed_call_signaling overtake an in-flight session_reset on long-idle pre-warm)
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
///  - SignalSessionManager.getPeerEd25519PublicKey(): Peer Signal Ed25519 key — bound record first, verified identity-directory fallback (Wallet V2 Phase F)
///  - SignalSessionManager.fetchIdentityDirectory(): Non-consuming GET /keys/identity/:snowId (parsed, uncached)
///  - SignalSessionManager.peekDeviceIdForIncoming(): Resolve the deviceId for an inbound envelope WITHOUT caching it
///  - SignalSessionManager.refreshLocalIdentityBinding(): Mint/reuse our binding and install it for type-2 embedding
///  - SignalSessionManager.selfCheckIdentityBinding(): Compare server binding state with ours, PUT when missing/stale
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

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../network/socket_manager.dart';
import '../storage/secure_storage.dart';
import 'hkdf.dart' show hkdfDerive;
import 'identity_admission.dart';
import 'identity_binding.dart';
import 'identity_binding_exception.dart';
import 'identity_key_changed_exception.dart';
import 'identity_manager.dart';
import 'session_store.dart';
import 'signal_protocol_service.dart';
import 'verified_identity_store.dart';

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

  /// B-2: verified identity store (owned by the Signal layer).
  VerifiedIdentityStore? get _identityStore => _signal.identityStore;

  /// B-2: hard identity rejections are memoized per peer so callers that loop
  /// (group fan-out fallbacks, call recovery, queue resets) never refetch a
  /// bundle — and burn a one-time prekey — for a peer we just rejected.
  final Map<String, ({DateTime at, IdentityBindingInvalidException error})>
      _identityRejections = {};
  static const Duration _identityRejectionCooldown = Duration(minutes: 10);

  /// B-2: non-consuming identity directory cache (per snowId, short TTL) for
  /// binding-less senders on the receive path.
  final Map<String, ({DateTime at, Future<RemoteIdentityDirectory?> future})>
      _directoryCache = {};
  static const Duration _directoryCacheTtl = Duration(minutes: 10);

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

  /// 2026-05-04 — pre-warm 결정용. encrypt 성공 시점 기록 → CallService 가
  /// startCall 직전에 1h 이상 idle 면 archive_reset force 로 fresh X3DH
  /// 강제 → first invite 가 prekey-message 로 송신 → recipient 가 stale
  /// session 무시하고 fresh bootstrap → 첫 시도 부터 정상 decrypt.
  final Map<String, DateTime> _lastEncryptTimestamps = {};

  DateTime? lastEncryptTimestamp(String snowId) =>
      _lastEncryptTimestamps[snowId];

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
        return false;
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
  })  : _signal = signalService,
        _apiClient = apiClient,
        _secureStorage = secureStorage,
        _identityManager = identityManager,
        _sessionStore = sessionStore,
        _socketManager = socketManager;

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
        // B-2: install our binding (local only) so type-2 messages carry it
        // even if the self-check below cannot reach the server.
        try {
          await refreshLocalIdentityBinding();
        } catch (e) {
          debugPrint('[SignalSessionManager] local binding not ready: '
              '${e.runtimeType}');
        }
        try {
          await checkPreKeyCount();
        } catch (e) {
          debugPrint('[SignalSessionManager] PreKey count check failed: $e');
        }

        // SPK self-heal (2026-08-05): reconcile the LOCAL signed-prekey private
        // store against the signed prekey the server advertises. Runs AFTER
        // checkPreKeyCount so its remaining==0 / !hasEd25519 branches settle
        // first (they may already have re-uploaded). A healthy account whose
        // local store holds the advertised pubkey is a strict no-op here — no
        // SPK rotation, so no regression of the "rotate every restart breaks
        // in-flight X3DH" class. Fixes existing devices whose local store was
        // lost/torn while the server still advertises their SPK.
        try {
          await reconcileSignedPreKey();
        } catch (e) {
          debugPrint('[SignalSessionManager] SPK reconcile failed: $e');
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

    // B-2: the upload always carries the Signal Ed25519 key AND our binding
    // over (deviceId, IK, Ed). Minted BEFORE persisting/advertising so a
    // failure here aborts the upload instead of advertising unbound keys.
    final binding = await refreshLocalIdentityBinding();
    if (binding == null || identityPublicKey == null) {
      debugPrint('[SignalSessionManager] _doUploadPreKeys: identity binding '
          'unavailable (no deviceId / keys yet) — aborting upload');
      return;
    }

    // P1 ordering fix (2026-05-05): persist private keys to disk BEFORE the
    // server POST.
    //
    // Original ordering (POST → save) had a process-kill window: server stores
    // OPK public keys → process killed during the ~hundreds of ms before save
    // → restart loads empty store → peers fetch the bundle and run X3DH 5-DH
    // referencing OPK ids we no longer hold privately → silent 4-DH
    // fallthrough on receive (now caught by signal_protocol_service P0
    // fail-loud) → permanent decrypt failure for any session opened in that
    // window. The previous "Phase 8.7 round 6" save-after-POST closed the
    // process-killed-after-everything window but not this earlier one.
    //
    // New ordering (save → POST): a save failure aborts the upload (no
    // server-side state created). A POST failure after a successful save
    // leaves orphan private keys in the local store keyed by OPK ids the
    // server never knew about — harmless: no peer can ever request them.
    // Counter advance already happened above, so the next attempt uses fresh
    // ids and the orphans age out of the map naturally on the next session
    // store rewrite.
    // Fresh-install fix (2026-08-05): _setupStoreEncryptionKey() ran at the top
    // of this method BEFORE generateSignalIdentityKey() wrote the identity
    // private key, so on a brand-new install the store key was never derived
    // and this pre-upload save silently no-op'd — the SPK/OPK private keys were
    // POSTed to the server but never written to disk (empty-local-SPK bug).
    // Re-derive the key now that the identity key is guaranteed to exist.
    if (!_signal.hasStoreEncryptionKey) {
      await _setupStoreEncryptionKey();
    }
    // INV-2 (persist-before-advertise): fail closed if the private keys did not
    // reach disk — do not advertise a signed prekey we cannot persist locally.
    if (!await _saveSessionStore()) {
      debugPrint('[SignalSessionManager] _doUploadPreKeys: session store not '
          'persisted — aborting upload (will retry once identity is durable)');
      return;
    }
    debugPrint('[Perf]   _saveSessionStore (pre-upload persist): '
        '${_sw.elapsedMilliseconds}ms');
    _sw.reset();

    // Upload to server -- includes identityKey + Ed25519 verify key for server DB update
    try {
      final response = await _apiClient.post<dynamic>(
        ApiEndpoints.preKeys,
        data: {
          'identityKey': _encodeBytes(identityPublicKey),
          'identityKeyEd25519': _encodeBytes(binding.ed25519),
          'identityBinding': binding.wire.toWireJson(),
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
      _logBindingAcceptance(response.data);
      debugPrint(
          '[SignalSessionManager] Uploaded signed prekey #$signedPreKeyId + '
          '$preKeyBatchSize one-time prekeys to server');
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
      // H1: record the account-wide max binding epoch BEFORE any upload below
      // mints a binding, so a restore never signs below it.
      await _identityManager.recordAccountMaxBindingEpoch(
          response.data?['accountMaxIdentityBindingEpoch']);
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
        // The replenish body carries the binding — server state is now ours.
        await _uploadOneTimePreKeys();
        return;
      }
      // B-2 server-side self-check (no local "uploaded" flag: a server-side
      // delete or DB restore must be detectable). Old servers omit the field.
      await selfCheckIdentityBinding(response.data);
    } catch (e) {
      // Non-fatal: we'll check again later
      debugPrint('[SignalSessionManager] Could not check pre-key count: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // B-2 Identity Binding v1 — local binding + server self-check
  // ---------------------------------------------------------------------------

  /// Mint (or reuse) our Identity Binding over (deviceId, X25519 IK, Signal
  /// Ed25519) and install it into the Signal layer for type-2 embedding.
  /// Returns null when the inputs are not available yet (pre-auth: no
  /// deviceId; no identity keys). [minEpochExclusive] forces a fresh epoch
  /// above a value the server already holds.
  Future<LocalIdentityBinding?> refreshLocalIdentityBinding({
    int? minEpochExclusive,
  }) async {
    final deviceId = await _secureStorage.read(_deviceIdKey);
    if (deviceId == null || !IdentityBindingV1.isValidDeviceId(deviceId)) {
      return null;
    }
    final ik = await _identityManager.getSignalPublicKey();
    final edKey = _signal.verifyKey ?? await _identityManager.getSignalVerifyKey();
    if (ik == null || edKey == null || ik.length != 32 || edKey.length != 32) {
      return null;
    }
    final binding = await _identityManager.currentIdentityBinding(
      deviceId: deviceId,
      identityKey: ik,
      ed25519: edKey,
      minEpochExclusive: minEpochExclusive,
    );
    _signal.setLocalIdentityBinding(binding);
    return binding;
  }

  /// M3: at most one corrective action (re-sign or full upload) per app
  /// session, so a server that keeps refusing can never cause a loop.
  bool _bindingRepairAttempted = false;

  /// Reject reasons that a fresh epoch can fix.
  static const Set<String> _resignReasons = {'epoch_regression', 'epoch_range'};

  /// Reject reasons that mean the server's device row lacks / disagrees with
  /// our keys — a full prekey upload (IK + Ed + binding) repairs them.
  static const Set<String> _fullUploadReasons = {
    'missing_keys',
    'keys',
    'signature',
  };

  /// Compare the server's `hasIdentityBinding` / `identityBindingEpoch`
  /// (from GET /keys/prekey-count) with our binding and repair through
  /// PUT /keys/identity-binding when missing or different. No-op on servers
  /// that predate B-2 (field absent). Never throws.
  ///
  /// M3 recovery when the PUT is soft-rejected (`bindingAccepted:false` +
  /// `bindingRejectReason`), or when it was accepted but the server still
  /// reports no binding:
  ///  - epoch_regression / epoch_range → re-sign with a fresh epoch, PUT once
  ///  - missing_keys / keys / signature, or "still no binding" → one full
  ///    uploadPreKeys() (IK + Ed + binding in a single row update)
  ///  - anything else → logged only (a client/server format disagreement a
  ///    retry cannot fix).
  Future<void> selfCheckIdentityBinding(Map<String, dynamic>? countData) async {
    try {
      if (countData == null) return;
      // H1: learn the account-wide max epoch before minting anything.
      await _identityManager.recordAccountMaxBindingEpoch(
          countData['accountMaxIdentityBindingEpoch']);
      if (countData['hasIdentityBinding'] is! bool) {
        return; // pre-B-2 server
      }
      final hasBinding = countData['hasIdentityBinding'] as bool;
      final serverEpoch = IdentityBindingV1.parseEpoch(
          countData['identityBindingEpoch'] is String
              ? countData['identityBindingEpoch'] as String
              : null);
      var binding = await refreshLocalIdentityBinding();
      if (binding == null) return;
      if (hasBinding && serverEpoch == binding.epoch) return;
      if (hasBinding && serverEpoch != null && serverEpoch > binding.epoch) {
        // The server holds a newer epoch than our stored binding (e.g. our
        // local copy was lost). Re-sign above it so the server accepts it.
        binding = await refreshLocalIdentityBinding(
            minEpochExclusive: serverEpoch);
        if (binding == null) return;
      }
      debugPrint('[SignalSessionManager] identity binding missing/stale on '
          'server — PUT /keys/identity-binding');
      var data = await _putIdentityBinding(binding);
      if (_bindingRepairAttempted) return;

      if (data is Map && data['bindingAccepted'] == false) {
        final reason = data['bindingRejectReason']?.toString() ?? '';
        if (_resignReasons.contains(reason)) {
          _bindingRepairAttempted = true;
          debugPrint('[SignalSessionManager] binding rejected ($reason) — '
              're-signing with a fresh epoch (once)');
          final fresh = await refreshLocalIdentityBinding(
              minEpochExclusive: binding.epoch);
          if (fresh != null) await _putIdentityBinding(fresh);
          return;
        }
        if (_fullUploadReasons.contains(reason)) {
          _bindingRepairAttempted = true;
          debugPrint('[SignalSessionManager] binding rejected ($reason) — '
              'falling back to a full prekey upload (once)');
          await uploadPreKeys();
          return;
        }
        debugPrint('[SignalSessionManager] binding rejected ($reason) — '
            'not retryable from the client');
        return;
      }

      // Accepted (or old server without the flag): confirm the server now
      // reports a binding; if not, one full upload.
      final confirm = await _apiClient.get<Map<String, dynamic>>(
        ApiEndpoints.preKeyCount,
      );
      data = confirm.data;
      if (data is Map && data['hasIdentityBinding'] == false) {
        _bindingRepairAttempted = true;
        debugPrint('[SignalSessionManager] server still reports no binding '
            'after PUT — falling back to a full prekey upload (once)');
        await uploadPreKeys();
      }
    } catch (e) {
      debugPrint('[SignalSessionManager] identity binding self-check failed '
          '(non-fatal): ${e.runtimeType}');
    }
  }

  /// PUT /keys/identity-binding for [binding]; returns the response body.
  Future<Object?> _putIdentityBinding(LocalIdentityBinding binding) async {
    final resp = await _apiClient.put<dynamic>(
      ApiEndpoints.identityBinding,
      data: {
        'deviceId': binding.deviceId,
        'identityKey': _encodeBytes(binding.identityKey),
        'identityKeyEd25519': _encodeBytes(binding.ed25519),
        'identityBinding': binding.wire.toWireJson(),
      },
    );
    _logBindingAcceptance(resp.data);
    final data = resp.data;
    if (data is Map) {
      await _identityManager.recordAccountMaxBindingEpoch(
          data['accountMaxIdentityBindingEpoch']);
    }
    return data;
  }

  /// Log (never the values) when the server soft-rejected our binding.
  void _logBindingAcceptance(Object? data) {
    if (data is Map && data['bindingAccepted'] == false) {
      debugPrint('[SignalSessionManager] server reported bindingAccepted=false '
          '(${data['bindingRejectReason']}) — re-checked by the prekey-count '
          'self-check');
    }
  }

  /// SPK self-heal (2026-08-05): reconcile our LOCAL signed-prekey private store
  /// against the signed prekey the server currently advertises to peers, and
  /// re-arm iff we lack the private key for it.
  ///
  /// Root cause it heals: a device can end up with an empty/torn local store
  /// while the server still advertises its signed prekey (e.g. a replenish that
  /// POSTed a fresh SPK without persisting, or a fresh-install save that no-op'd
  /// before the store key existed). Peers then fetch that SPK and X3DH-encrypt
  /// their first message to it; the receiver's `_receiveSession` cannot find the
  /// private key → "Signed prekey not found" → the (sealed) message dead-letters
  /// silently. `checkPreKeyCount` never catches this because it only inspects the
  /// server-side OPK count, never the local↔server SPK match.
  ///
  /// Safety (design INV-3):
  ///  - Compare by PUBLIC KEY, not id — a same-id/different-key collision (from a
  ///    prior race) still re-arms.
  ///  - Rotate ONLY on a self-originated mismatch: the advertised id must be
  ///    below our secure-storage `nextSignedPreKeyId` counter (which survives a
  ///    session-store loss). A hostile server advertising an id we never minted
  ///    is refused — it cannot force perpetual rotation (which would break
  ///    in-flight X3DH).
  ///  - Re-arm delegates to the guarded [uploadPreKeys] (persist-before-advertise
  ///    + `_uploadPreKeysInFlight` mutex inherited for free).
  Future<void> reconcileSignedPreKey() async {
    // Don't fight an in-flight upload — it will leave us matched.
    if (_uploadPreKeysInFlight != null) {
      debugPrint('[SignalSessionManager] reconcileSignedPreKey skipped — '
          'prekey upload already in-flight');
      return;
    }
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        ApiEndpoints.preKeyCount,
      );
      final advertisedId = response.data?['signedPreKeyId'] as int?;
      final advertisedPubB64 = response.data?['signedPreKey'] as String?;

      // Old server (advertised SPK not returned): fall back to the fully-empty
      // signal only — it's all we can safely detect.
      if (advertisedId == null || advertisedPubB64 == null) {
        if (!_signal.hasAnySignedPreKey) {
          debugPrint('[SignalSessionManager] reconcileSignedPreKey: local SPK '
              'store empty (old-server fallback) — re-arming');
          await uploadPreKeys();
        }
        return;
      }

      // Already hold the exact advertised public key → strict no-op (INV-3).
      final localPub = _signal.signedPreKeyPublicKey(advertisedId);
      final advertisedPub = _decodeBytes(advertisedPubB64);
      if (localPub != null && _bytesEqual(localPub, advertisedPub)) {
        return;
      }

      // Anti-churn (INV-3): only re-arm for an id we plausibly generated. The
      // counter lives in secure storage and survives session-store loss, so a
      // genuine self-heal has advertisedId < nextId. An id >= our counter was
      // never minted by us → a hostile/desynced server → refuse to rotate.
      final nextId = await _nextSignedPreKeyId();
      if (advertisedId >= nextId) {
        // Edge case (uncommon): if BOTH the session store AND the secure-storage
        // counter were lost, nextId falls back to 1, so a legitimately-ours
        // SPK #1 would be refused here. In practice the counter lives in
        // Keychain/Keystore and survives a session-store file loss (the Kara
        // case), so this only bites a near-total secure-storage wipe — which the
        // initialize() "missing identity/seed" path already treats as a fresh
        // install + full upload. Logged (not force-rotated) so it stays visible
        // rather than becoming a silent refusal.
        debugPrint('[SignalSessionManager] reconcileSignedPreKey: server '
            'advertises SPK #$advertisedId >= local counter #$nextId — not '
            'self-originated, refusing to rotate');
        return;
      }

      debugPrint('[SignalSessionManager] reconcileSignedPreKey: local store '
          'lacks advertised SPK #$advertisedId public key — re-arming (self-heal)');
      await uploadPreKeys();
    } catch (e) {
      debugPrint('[SignalSessionManager] reconcileSignedPreKey failed '
          '(non-fatal): $e');
    }
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

    // B-2: fail fast — without a network call or OPK consumption — for a
    // peer we just hard-rejected or that awaits re-verification.
    await _throwIfIdentityBlocked(recipientSnowchatId);

    // B-2 M4: admit the peer from the NON-consuming identity directory first.
    // A forged / downgraded / replayed identity or a verified legacy key
    // change is refused here, before the bundle endpoint pops a one-time
    // prekey. Null → server predates the endpoint (legacy bundle path).
    final String? preAdmittedDevice;
    try {
      preAdmittedDevice = await _preAdmit(recipientSnowchatId);
    } on IdentityBindingInvalidException catch (e) {
      _identityRejections[recipientSnowchatId] = (at: DateTime.now(), error: e);
      rethrow;
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

        // B-2: pick ONE device — the one admitted from the directory (M4),
        // else the highest-epoch validly-bound one, or the first device when
        // nobody is bound (legacy). createSession re-verifies the bundle's own
        // binding, so a bundle that drifted from the directory between the two
        // requests is still judged on its own merits.
        final selected = await _selectBundleDevice(
          recipientSnowchatId,
          data['accountPublicKey'],
          devices,
          preferDeviceId: preAdmittedDevice,
        );
        final device = selected.device;
        final deviceId = device['deviceId'] as String;

        _recipientDeviceIds[recipientSnowchatId] = deviceId;

        final exists = await _signal.hasSession(recipientSnowchatId, deviceId);
        if (!exists) {
          await _establishSession(
            recipientSnowchatId,
            deviceId,
            device,
            accountPublicKey: selected.accountPublicKey,
          );
        }
        return; // Success — exit retry loop
      } on IdentityBindingInvalidException catch (e) {
        _identityRejections[recipientSnowchatId] =
            (at: DateTime.now(), error: e);
        rethrow; // never retried
      } on IdentityKeyChangedException {
        rethrow; // blocked until re-verification — never retried
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

  /// B-2: throw (without network) when [snowId] is in the hard-rejection
  /// cooldown or has a legacy key change awaiting re-verification.
  Future<void> _throwIfIdentityBlocked(String snowId) async {
    final rejected = _identityRejections[snowId];
    if (rejected != null) {
      if (DateTime.now().difference(rejected.at) < _identityRejectionCooldown) {
        throw rejected.error;
      }
      _identityRejections.remove(snowId);
    }
    final store = _identityStore;
    if (store == null) return;
    VerifiedIdentityRecord? rec;
    try {
      rec = await store.get(snowId);
    } catch (_) {
      return; // createSession re-checks with fail-closed semantics
    }
    if (rec != null && rec.hasPendingChange) {
      throw IdentityKeyChangedException(
        peerSnowchatId: snowId,
        deviceId: rec.pendingDeviceId,
        expectedKey: Uint8List.fromList(
            rec.identityKey ?? rec.ed25519 ?? Uint8List(32)),
        actualKey: Uint8List.fromList(
            rec.pendingIdentityKey ?? rec.pendingEd25519 ?? Uint8List(32)),
      );
    }
  }

  /// M4: non-consuming pre-admission. Returns the admitted deviceId, or null
  /// when the identity endpoint does not exist (pre-B-2 server → legacy
  /// bundle path). Typed identity failures propagate; other network errors
  /// surface as a transient SignalProtocolException (no bundle fetched).
  Future<String?> _preAdmit(String snowId) async {
    final store = _identityStore;
    if (store == null) return null;
    final RemoteIdentityDirectory dir;
    try {
      dir = await fetchIdentityDirectory(snowId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw SignalProtocolException(
          'Identity directory unavailable for $snowId (transient): '
          '${e.type.name}');
    }
    if (dir.devices.isEmpty) {
      throw SignalProtocolException('No devices found for $snowId');
    }
    final r = await IdentityAdmission(store)
        .admitDirectory(snowId: snowId, directory: dir);
    return r?.device.deviceId;
  }

  /// Clear the hard-rejection memo for [snowId] (verify screen re-check).
  void clearIdentityRejection(String snowId) {
    _identityRejections.remove(snowId);
    _directoryCache.remove(snowId);
  }

  /// B-2 device selection over a raw bundle `devices` list.
  Future<({Map<String, dynamic> device, Uint8List? accountPublicKey})>
      _selectBundleDevice(
    String snowId,
    Object? rawAccountKey,
    List<dynamic> devices, {
    String? preferDeviceId,
  }) async {
    final maps = devices.map((d) => Map<String, dynamic>.from(d as Map)).toList();
    if (preferDeviceId != null) {
      final store = _identityStore;
      Uint8List? account =
          IdentityBindingV1.parseAccountKeyHex(rawAccountKey as String?);
      if (store != null) {
        account ??= (await store.get(snowId))?.accountPublicKey;
      }
      for (final m in maps) {
        if (m['deviceId'] == preferDeviceId) {
          return (device: m, accountPublicKey: account);
        }
      }
      // The admitted device is not in the bundle (peer re-registered between
      // the requests) → treat as not-ready so the retry loop refetches.
      throw SignalProtocolException('No devices found for $snowId');
    }
    final store = _identityStore;
    if (store == null) {
      return (device: maps.first, accountPublicKey: null);
    }
    Uint8List? account =
        IdentityBindingV1.parseAccountKeyHex(rawAccountKey as String?);
    account ??= (await store.get(snowId))?.accountPublicKey;
    final parsed = <RemoteDeviceIdentity>[];
    for (var i = 0; i < maps.length; i++) {
      final r = _parseDeviceIdentity(maps[i], i);
      if (r != null) parsed.add(r);
    }
    final pick = IdentityAdmission(store).selectDevice(
      snowId: snowId,
      accountPublicKey: account,
      devices: parsed,
    );
    if (pick == null) {
      throw SignalProtocolException('No devices found for $snowId');
    }
    return (device: maps[pick.index], accountPublicKey: account);
  }

  /// Parse one device entry (bundle or identity directory). Returns null when
  /// the entry has no usable deviceId / identity key.
  RemoteDeviceIdentity? _parseDeviceIdentity(Map<String, dynamic> raw, int index) {
    final deviceId = raw['deviceId'];
    final ikRaw = raw['identityKey'];
    if (deviceId is! String || ikRaw == null) return null;
    try {
      final ik = _safeDecodeKey(ikRaw);
      final edRaw = raw['identityKeyEd25519'];
      final edKey = edRaw == null ? null : _safeDecodeKey(edRaw);
      final rawBinding = raw['identityBinding'];
      final binding =
          rawBinding == null ? null : IdentityBinding.tryParseWire(rawBinding);
      return RemoteDeviceIdentity(
        deviceId: deviceId,
        identityKey: ik,
        ed25519: (edKey != null && edKey.length == 32) ? edKey : null,
        binding: binding,
        bindingUnparseable: rawBinding != null && binding == null,
        index: index,
      );
    } catch (_) {
      return null;
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
  /// Returns the cached deviceId if present, otherwise the deviceId carried
  /// by the incoming envelope. B-2: this NO LONGER writes the cache — an
  /// unverified envelope must not be able to steer our outbound device
  /// selection. [decrypt] caches the deviceId only after a verified decrypt.
  /// Throws [StateError] only when both the cache and the incoming hint are
  /// missing (a real bug condition).
  String peekDeviceIdForIncoming(
    String senderSnowchatId,
    String? incomingDeviceId,
  ) {
    final cached = _recipientDeviceIds[senderSnowchatId];
    if (cached != null) return cached;
    if (incomingDeviceId != null && incomingDeviceId.isNotEmpty) {
      return incomingDeviceId;
    }
    throw StateError(
      'peekDeviceIdForIncoming: no cached deviceId for $senderSnowchatId '
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

    // B-2: a peer we hard-rejected or that awaits re-verification cannot be
    // re-established — fail before archiving the current session (the reset
    // would only tear down state and then throw anyway).
    await _throwIfIdentityBlocked(snowId);

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

    // B-2: skip peers in hard-rejection cooldown / awaiting re-verification
    // (no bundle fetch → no OPK burn for a peer we will refuse anyway).
    final unblocked = <String>[];
    for (final id in needSession) {
      try {
        await _throwIfIdentityBlocked(id);
        unblocked.add(id);
      } catch (_) {}
    }
    if (unblocked.isEmpty) return;

    // B-2 M4: non-consuming pre-admission per member (bounded concurrency)
    // BEFORE the consuming batch call. Rejected / blocked members are dropped
    // without burning their one-time prekeys; transient lookup failures are
    // dropped too (callers' individual ensureSession fallback retries them).
    final preAdmitted = <String, String?>{};
    const concurrency = 8;
    for (var i = 0; i < unblocked.length; i += concurrency) {
      final chunk = unblocked.skip(i).take(concurrency).toList();
      await Future.wait(chunk.map((id) async {
        try {
          preAdmitted[id] = await _preAdmit(id);
        } on IdentityBindingInvalidException catch (e) {
          _identityRejections[id] = (at: DateTime.now(), error: e);
          debugPrint('[SignalSessionManager] batch: identity rejected for one '
              'member (${e.reason.name}) — no bundle fetched');
        } on IdentityKeyChangedException {
          debugPrint('[SignalSessionManager] batch: member awaits identity '
              're-verification — no bundle fetched');
        } catch (e) {
          debugPrint('[SignalSessionManager] batch: identity lookup for one '
              'member failed (transient): ${e.runtimeType}');
        }
      }));
    }
    final eligible =
        unblocked.where((id) => preAdmitted.containsKey(id)).toList();
    if (eligible.isEmpty) return;

    Map<String, dynamic> bundles;
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '${ApiEndpoints.preKeys}/batch',
        data: {'snowchatIds': eligible},
      );
      bundles = response.data?['bundles'] as Map<String, dynamic>? ?? {};
    } catch (e) {
      debugPrint('[SignalSessionManager] Batch session failed: $e');
      // Request-level failure only: establish individually. A per-peer
      // identity rejection never reaches this fallback (handled below).
      for (final id in eligible) {
        try {
          await ensureSession(id);
        } catch (_) {}
      }
      return;
    }

    // B-2 per-entry isolation: one bad bundle (forged binding, legacy key
    // change, missing SPK) must not fail the whole batch and trigger a
    // re-fetch — and OPK re-consumption — for every other member.
    for (final entry in bundles.entries) {
      final snowchatId = entry.key;
      try {
        final bundleData = Map<String, dynamic>.from(entry.value as Map);
        final devices = bundleData['devices'] as List<dynamic>?;
        if (devices == null || devices.isEmpty) continue;
        final selected = await _selectBundleDevice(
          snowchatId,
          bundleData['accountPublicKey'],
          devices,
          preferDeviceId: preAdmitted[snowchatId],
        );
        final deviceId = selected.device['deviceId'] as String;
        _recipientDeviceIds[snowchatId] = deviceId;
        final exists = await _signal.hasSession(snowchatId, deviceId);
        if (!exists) {
          await _establishSession(
            snowchatId,
            deviceId,
            selected.device,
            accountPublicKey: selected.accountPublicKey,
          );
        }
      } on IdentityBindingInvalidException catch (e) {
        _identityRejections[snowchatId] = (at: DateTime.now(), error: e);
        _recipientDeviceIds.remove(snowchatId);
        debugPrint('[SignalSessionManager] batch: identity rejected for one '
            'member (${e.reason.name}) — skipped, not retried');
      } on IdentityKeyChangedException {
        _recipientDeviceIds.remove(snowchatId);
        debugPrint('[SignalSessionManager] batch: member awaits identity '
            're-verification — skipped');
      } catch (e) {
        _recipientDeviceIds.remove(snowchatId);
        debugPrint('[SignalSessionManager] batch: session for one member '
            'failed (transient): ${e.runtimeType}');
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

      // 2026-05-04 — pre-warm 결정용 timestamp 갱신.
      _lastEncryptTimestamps[recipientId] = DateTime.now();

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
  /// B-2: the Signal layer verifies the sender's binding embedded in the
  /// PreKey message (offline) against the X3DH header IK, [envelopeDeviceId]
  /// (socket envelope `senderDeviceId` / sealed certificate deviceId) and the
  /// epoch latch BEFORE deriving a session. Only binding-less senders unknown
  /// to the store trigger the non-consuming identity-directory lookup (cached
  /// per snowId). The sender's deviceId is cached only after the verified
  /// decrypt succeeds.
  Future<Uint8List> decrypt(
    String senderId,
    String deviceId,
    Uint8List ciphertext,
    int messageType, {
    String? envelopeDeviceId,
  }) async {
    _assertInitialized();

    try {
      // [DIAG-VOIP-2026-04-19] decrypt step timing — separate cipher vs disk I/O. Remove after diagnosis.
      final sw = Stopwatch()..start();
      final result = await _signal.decryptMessage(
        senderId: senderId,
        deviceId: deviceId,
        ciphertext: ciphertext,
        messageType: messageType,
        envelopeDeviceId: envelopeDeviceId,
        identityDirectoryLookup: () => _cachedIdentityDirectory(senderId),
      );
      final cipherMs = sw.elapsedMilliseconds;

      // Cache the deviceId used for this sender so future lookups are
      // consistent — only now that the message decrypted under a verified
      // identity (B-2: never from an unverified envelope).
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

  /// Cached (TTL) non-consuming identity directory for [snowId]. A failed
  /// fetch is evicted so the next attempt retries.
  Future<RemoteIdentityDirectory?> _cachedIdentityDirectory(String snowId) {
    final cached = _directoryCache[snowId];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _directoryCacheTtl) {
      return cached.future;
    }
    final future = fetchIdentityDirectory(snowId);
    _directoryCache[snowId] = (at: DateTime.now(), future: future);
    unawaited(future.then<void>((_) {}, onError: (Object _) {
      _directoryCache.remove(snowId);
    }));
    return future;
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

  /// 2026-05-04 회귀 fix: per-peer 로컬 세션 wipe (no peer notification).
  ///
  /// 1:1 대화방 삭제 시 호출. drift Conversations / Messages row 만 지우고
  /// Signal SessionStore 의 ratchet state 를 그대로 두면, 같은 peer 와 다시
  /// 메시지 주고받을 때 stale ratchet 으로 decrypt 시도 → 실패 →
  /// `archiveAndResetSession` (peer 한테 session_reset notification 보냄) →
  /// peer 도 reset → 양쪽 동시 X3DH bootstrap → 서로 다른 session 생성 →
  /// **session_reset 무한 loop** (사용자 보고 2026-05-04 "1:1 채팅 삭제 후
  /// 같은 peer 와 메시지 주고받을 때 그룹 통신 안 됨").
  ///
  /// archiveAndResetSession 과 다른 점:
  ///   - 이건 자기 쪽 store 만 wipe — peer 한테 알림 X. peer 의 session 은
  ///     그대로 (peer 도 자기 쪽 채팅을 별도로 삭제하면 둘 다 깨끗해짐).
  ///   - peer 가 다음 메시지 보낼 때 fresh prekey-message 가 X3DH bootstrap
  ///     트리거 → 우리 쪽에 fresh session 생성 → convergence.
  ///   - 양측 동시 reset race 의 위험 회피 (notification 안 보냄).
  Future<void> deleteSessionForPeer(String snowId) async {
    if (!_initialized) {
      // Init wasn't run — store doesn't have this peer's session anyway.
      // Just remove the cached deviceId mapping (if any) and bail.
      _recipientDeviceIds.remove(snowId);
      return;
    }
    final deviceId = _recipientDeviceIds[snowId];
    if (deviceId != null) {
      try {
        await _signal.deleteSession(snowId, deviceId);
      } catch (e) {
        debugPrint('[SessionMgr] deleteSessionForPeer delete error '
            '(non-fatal): $e');
      }
    }
    _recipientDeviceIds.remove(snowId);
    // Persist immediately so a crash mid-flight doesn't restore the wiped
    // session from disk.
    try {
      await _saveSessionStore();
    } catch (e) {
      debugPrint('[SessionMgr] deleteSessionForPeer persist error '
          '(non-fatal): $e');
    }
    debugPrint('[SessionMgr] deleteSessionForPeer($snowId) — local session '
        'wiped (no peer notification)');
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

  /// Persist the session store. Returns `true` iff bytes actually reached disk
  /// (see SignalProtocolService.saveSessionStore) so persist-before-advertise
  /// callers can fail closed (INV-2).
  Future<bool> _saveSessionStore() async {
    final path = await _sessionStorePath();
    // Persist the "store encrypted" flag to secure storage on first encrypted save
    if (_signal.isStoreEncrypted) {
      await _secureStorage.write(_storeEncryptedFlagKey, 'true');
    }
    return _signal.saveSessionStore(path);
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
  ///
  /// Guarded + persisted (2026-08-05 SPK self-heal design):
  ///  - Shares the [_uploadPreKeysInFlight] mutex with [uploadPreKeys] so a full
  ///    upload and a replenish can never race to generate two different signed
  ///    prekeys under different ids and leave the server advertising one the
  ///    client did not persist (INV-1).
  ///  - Persists the new SPK/OPK private keys to disk BEFORE advertising them to
  ///    the server (INV-2). This closes the live gap that caused the empty
  ///    local-SPK / "Signed prekey not found" receive-first failure: this path
  ///    (reached on every low-OPK replenish) previously POSTed a fresh signed
  ///    prekey with no _saveSessionStore() at all.
  Future<void> _uploadOneTimePreKeys() async {
    final inFlight = _uploadPreKeysInFlight;
    if (inFlight != null) {
      debugPrint('[SignalSessionManager] _uploadOneTimePreKeys merged with '
          'in-flight upload');
      return inFlight;
    }
    final future = _doUploadOneTimePreKeys();
    _uploadPreKeysInFlight = future;
    try {
      await future;
    } finally {
      _uploadPreKeysInFlight = null;
    }
  }

  Future<void> _doUploadOneTimePreKeys() async {
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

    // B-2: Body B also carries the Ed25519 key + binding. Previously it
    // omitted Ed, which the server's "IK/Ed changed without a valid binding"
    // invalidation would now misread as a key change.
    final binding = await refreshLocalIdentityBinding();
    if (binding == null || identityPublicKey == null) {
      debugPrint('[SignalSessionManager] _uploadOneTimePreKeys: identity '
          'binding unavailable — aborting replenish');
      return;
    }

    // INV-2 (persist-before-advertise): the SPK/OPK private keys just generated
    // live only in memory + the session store. Persist them to disk BEFORE the
    // POST. If the save did not reach disk, ABORT the upload — advertising a
    // signed prekey whose private key was never persisted is precisely the
    // empty-local-SPK bug this fix exists to prevent.
    if (!await _saveSessionStore()) {
      debugPrint('[SignalSessionManager] _uploadOneTimePreKeys: session store '
          'not persisted (no encryption key?) — aborting upload to avoid '
          'advertising an unpersisted signed prekey');
      return;
    }

    try {
      final response = await _apiClient.post<dynamic>(
        ApiEndpoints.preKeys,
        data: {
          'identityKey': _encodeBytes(identityPublicKey),
          'identityKeyEd25519': _encodeBytes(binding.ed25519),
          'identityBinding': binding.wire.toWireJson(),
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
      _logBindingAcceptance(response.data);
    } catch (e) {
      debugPrint('[SignalSessionManager] Failed to replenish prekeys: $e');
      rethrow;
    }
  }

  /// Establish a session with a specific device using fetched pre-key bundle data.
  Future<void> _establishSession(
    String recipientId,
    String deviceId,
    Map<String, dynamic> deviceBundle, {
    Uint8List? accountPublicKey,
  }) async {
    try {
      // Decode base64-encoded keys from server response
      final bundle = _decodePreKeyBundle(deviceBundle);
      // B-2: user-level account key travels with the selected device bundle
      // so createSession can verify the device's binding.
      if (accountPublicKey != null) {
        bundle['accountPublicKey'] = accountPublicKey;
      }

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
  /// **Lookup priority (B-2)**:
  /// 1. VerifiedIdentityStore bound record → the account-signed Ed.
  /// 2. Non-consuming `GET /keys/identity/:snowId` → highest-epoch device with
  ///    a VALID binding → admitted (recorded + latched) → its Ed.
  /// 3. Legacy peer (no binding anywhere): the TOFU Ed from our record, or
  ///    the directory Ed admitted under the legacy policy. A latched peer
  ///    without a binding is rejected (downgrade).
  /// The server response is never pinned without verification.
  ///
  /// **Returns**: 32-byte raw Ed25519 verify key, or null when the peer has
  /// none. Throws on transient failures and on identity rejections.
  Future<Uint8List?> getPeerEd25519PublicKey(String peerSnowchatId) async {
    if (peerSnowchatId.isEmpty) return null;
    final store = _identityStore;
    if (store != null) {
      final rec = await store.get(peerSnowchatId);
      if (rec != null && rec.bound && rec.ed25519 != null) return rec.ed25519;
      if (rec != null && rec.hasPendingChange) {
        await _throwIfIdentityBlocked(peerSnowchatId);
      }
    }

    final dir = await fetchIdentityDirectory(peerSnowchatId);
    if (dir.devices.isEmpty) return null;
    if (store == null) return dir.devices.first.ed25519;

    final admission = IdentityAdmission(store);
    final account =
        dir.accountPublicKey ?? (await store.get(peerSnowchatId))?.accountPublicKey;
    final pick = admission.selectDevice(
      snowId: peerSnowchatId,
      accountPublicKey: account,
      devices: dir.devices,
    );
    if (pick == null) return null;
    final b = pick.binding;
    if (b != null && pick.ed25519 != null && account != null) {
      final admitted = await admission.admitBound(
        snowId: peerSnowchatId,
        deviceId: pick.deviceId,
        identityKey: pick.identityKey,
        ed25519: pick.ed25519!,
        accountPublicKey: account,
        epoch: b.epoch,
        signature: b.signature,
      );
      return admitted.ed25519;
    }
    final admitted = await admission.admitUnbound(
      snowId: peerSnowchatId,
      deviceId: pick.deviceId,
      identityKey: pick.identityKey,
      ed25519: pick.ed25519,
      accountPublicKey: dir.accountPublicKey,
    );
    return admitted.ed25519;
  }

  /// B-2: non-consuming identity directory — `GET /keys/identity/:snowId` →
  /// `{accountPublicKey(hex), devices:[{deviceId, identityKey(b64),
  /// identityKeyEd25519(b64), identityBinding|null}]}`. Does NOT pop a
  /// one-time prekey and is not cached here (see decrypt's TTL cache).
  Future<RemoteIdentityDirectory> fetchIdentityDirectory(String snowId) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.identityForUser(snowId),
    );
    final data = response.data;
    if (data == null) {
      throw StateError('Empty identity directory response');
    }
    final account =
        IdentityBindingV1.parseAccountKeyHex(data['accountPublicKey'] as String?);
    final rawDevices = data['devices'] as List<dynamic>? ?? const [];
    final devices = <RemoteDeviceIdentity>[];
    for (var i = 0; i < rawDevices.length; i++) {
      final parsed = _parseDeviceIdentity(
          Map<String, dynamic>.from(rawDevices[i] as Map), i);
      if (parsed != null) devices.add(parsed);
    }
    return RemoteIdentityDirectory(accountPublicKey: account, devices: devices);
  }

  /// Decode base64-encoded keys from the server's PreKeyBundleDevice response.
  Map<String, dynamic> _decodePreKeyBundle(Map<String, dynamic> raw) {
    final signedPreKey = raw['signedPreKey'] as Map<String, dynamic>;
    final rawBinding = raw['identityBinding'];
    final binding =
        rawBinding == null ? null : IdentityBinding.tryParseWire(rawBinding);

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
      // B-2: per-device binding (absent for legacy peers). A present but
      // unparseable binding is flagged so admission rejects it (fail-closed).
      'identityBinding': ?binding,
      if (rawBinding != null && binding == null)
        'identityBindingUnparseable': true,
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
