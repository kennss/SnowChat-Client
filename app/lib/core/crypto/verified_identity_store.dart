/// @file        verified_identity_store.dart
/// @description B-2 Identity Binding v1 — per-peer store of the remote
///              identity we have verified (or, for legacy peers, TOFU-seen).
///              Replaces the old IdentityPinStore whose keys were split across
///              `signal_identity_pin:<snowId>` and
///              `signal_identity_pin:<snowId>:<deviceId>` (SC-15c).
///
///              Storage layout (SecureStorageService — app-global
///              flutter_secure_storage config, never a second instance):
///                verified_identity_v1:<snowId>  → JSON record (schema 1)
///                identity_bound_latch:<snowId>  → decimal max accepted epoch
///                                                 (presence = latched; NEVER
///                                                 deleted by remove())
///                verified_identity_store_version → "1" once the legacy pins
///                                                 were migrated + deleted
///                verified_identity_ik_seeded     → "1" once legacy records
///                                                 were seeded with the X25519
///                                                 IK from the session store
///
///              Lazy migration behind a single `_ready` future: on a cold start
///              MessageQueue drains BEFORE SignalSessionManager.initialize()
///              (conversation_list_provider), so migration cannot live in
///              initialize(). Every public read/write awaits `_ready`. Order is
///              write new records → write version marker → delete legacy keys,
///              so a crash at any point leaves either the legacy keys or the
///              new records readable. Until the marker exists, reads fall back
///              per snowId to the legacy keys (bare, then `:<deviceIdHint>`).
///              readAll() enumeration is best-effort cleanup only (iOS hides
///              items by accessibility class; Android EncryptedSharedPreferences
///              can throw on one corrupt entry) and is skipped when the
///              keychain is not readable (BFU / locked).
///
///              The VoIP background isolate may run the same migration
///              concurrently — every step is idempotent.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-10
/// @lastUpdated 2026-11-10 (review fixes: M1 ambiguous device pins migrate no Ed, migrated Eds flagged legacy-sourced, IK seeding carries the deviceId; L6 a keychain-locked deferral is retried on a later read)
///
/// @functions
///  - VerifiedIdentityRecord: per-peer record (+ JSON codec)
///  - IdentityStoreEvent / IdentityEventKind: user-visible identity events
///  - VerifiedIdentityStore.get(): record for a snowId (legacy fallback)
///  - VerifiedIdentityStore.getFresh(): cache-bypassing read (cross-isolate safety)
///  - VerifiedIdentityStore.latchedEpoch(): highest bound epoch, null if never bound
///  - VerifiedIdentityStore.put(): persist a record
///  - VerifiedIdentityStore.raiseLatch(): monotonic latch update
///  - VerifiedIdentityStore.remove(): drop the record (latch is kept)
///  - VerifiedIdentityStore.pinFromInviteLink(): pin an account key from a link/QR
///  - VerifiedIdentityStore.rememberAccountKey(): store a derive-checked account key
///  - VerifiedIdentityStore.acceptPendingChange(): re-verify → adopt pending keys
///  - VerifiedIdentityStore.seedLegacyIdentityKeys(): one-time IK seeding
///  - VerifiedIdentityStore.isPeerVerified(): DAO-backed "user verified" lookup
///  - VerifiedIdentityStore.emit()/events: identity event broadcast
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../storage/secure_storage.dart';
import 'identity_binding.dart';
import 'identity_binding_exception.dart';

/// One remote identity, keyed by snowId.
class VerifiedIdentityRecord {
  static const int schema = 1;

  final String snowId;

  /// Peer ACCOUNT public key (snowId root). Present when a binding verified,
  /// when an invite link pinned it, or when the server supplied a key that
  /// derives the snowId (legacy peer).
  final Uint8List? accountPublicKey;

  /// Device the current keys belong to.
  final String? deviceId;

  /// Epoch of the accepted binding (bound records only).
  final int? epoch;

  /// X25519 identity key used in X3DH.
  final Uint8List? identityKey;

  /// Signal-layer Ed25519 signing key (SPK signatures, wallet sigs, GMK).
  final Uint8List? ed25519;

  /// M1: [ed25519] was carried over from a pre-B-2 TOFU pin (possibly a bare
  /// pin written by the server-trusting wallet lookup). Such an Ed is weak
  /// evidence: on legacy→bound promotion only the IK is compared.
  final bool edLegacySourced;

  /// Binding signature (bound records only).
  final Uint8List? bindingSignature;

  /// True once a valid binding was accepted for the current keys.
  final bool bound;

  /// ms since epoch of the last write.
  final int updatedAt;

  /// Legacy peer whose keys changed while the user had marked them verified:
  /// the new keys wait here until the user re-verifies (§5.5). While set, the
  /// peer is blocked for sending and new inbound sessions.
  final Uint8List? pendingIdentityKey;
  final Uint8List? pendingEd25519;
  final String? pendingDeviceId;

  const VerifiedIdentityRecord({
    required this.snowId,
    this.accountPublicKey,
    this.deviceId,
    this.epoch,
    this.identityKey,
    this.ed25519,
    this.edLegacySourced = false,
    this.bindingSignature,
    this.bound = false,
    required this.updatedAt,
    this.pendingIdentityKey,
    this.pendingEd25519,
    this.pendingDeviceId,
  });

  bool get hasPendingChange =>
      pendingIdentityKey != null || pendingEd25519 != null;

  VerifiedIdentityRecord copyWith({
    Uint8List? accountPublicKey,
    String? deviceId,
    int? epoch,
    Uint8List? identityKey,
    Uint8List? ed25519,
    Uint8List? bindingSignature,
    bool? bound,
    bool clearPending = false,
    Uint8List? pendingIdentityKey,
    Uint8List? pendingEd25519,
    String? pendingDeviceId,
  }) {
    return VerifiedIdentityRecord(
      snowId: snowId,
      accountPublicKey: accountPublicKey ?? this.accountPublicKey,
      deviceId: deviceId ?? this.deviceId,
      epoch: epoch ?? this.epoch,
      identityKey: identityKey ?? this.identityKey,
      ed25519: ed25519 ?? this.ed25519,
      edLegacySourced: ed25519 != null ? false : edLegacySourced,
      bindingSignature: bindingSignature ?? this.bindingSignature,
      bound: bound ?? this.bound,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      pendingIdentityKey: clearPending
          ? null
          : (pendingIdentityKey ?? this.pendingIdentityKey),
      pendingEd25519:
          clearPending ? null : (pendingEd25519 ?? this.pendingEd25519),
      pendingDeviceId:
          clearPending ? null : (pendingDeviceId ?? this.pendingDeviceId),
    );
  }

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'snowId': snowId,
        if (accountPublicKey != null)
          'accountPub': bytesToHexLower(accountPublicKey!),
        if (deviceId != null) 'deviceId': deviceId,
        if (epoch != null) 'epoch': epoch.toString(),
        if (identityKey != null) 'ik': base64Encode(identityKey!),
        if (ed25519 != null) 'ed': base64Encode(ed25519!),
        if (edLegacySourced) 'edLegacy': true,
        if (bindingSignature != null) 'sig': base64Encode(bindingSignature!),
        'bound': bound,
        'updatedAt': updatedAt,
        if (pendingIdentityKey != null)
          'pendingIk': base64Encode(pendingIdentityKey!),
        if (pendingEd25519 != null) 'pendingEd': base64Encode(pendingEd25519!),
        if (pendingDeviceId != null) 'pendingDeviceId': pendingDeviceId,
      };

  /// Strict decode; throws [FormatException] on any inconsistency so the
  /// caller can treat the entry as corrupt.
  factory VerifiedIdentityRecord.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != schema) {
      throw const FormatException('unknown record schema');
    }
    Uint8List? b64(String k, {int len = 32}) {
      final v = j[k];
      if (v == null) return null;
      final out = base64Decode(v as String);
      if (out.length != len) throw FormatException('bad length for $k');
      return out;
    }

    final accountHex = j['accountPub'] as String?;
    final account = accountHex == null
        ? null
        : IdentityBindingV1.parseAccountKeyHex(accountHex);
    if (accountHex != null && account == null) {
      throw const FormatException('bad accountPub');
    }
    final epochStr = j['epoch'] as String?;
    final epoch =
        epochStr == null ? null : IdentityBindingV1.parseEpoch(epochStr);
    if (epochStr != null && epoch == null) {
      throw const FormatException('bad epoch');
    }
    final rec = VerifiedIdentityRecord(
      snowId: j['snowId'] as String,
      accountPublicKey: account,
      deviceId: j['deviceId'] as String?,
      epoch: epoch,
      identityKey: b64('ik'),
      ed25519: b64('ed'),
      edLegacySourced: j['edLegacy'] as bool? ?? false,
      bindingSignature: b64('sig', len: 64),
      bound: j['bound'] as bool? ?? false,
      updatedAt: j['updatedAt'] as int? ?? 0,
      pendingIdentityKey: b64('pendingIk'),
      pendingEd25519: b64('pendingEd'),
      pendingDeviceId: j['pendingDeviceId'] as String?,
    );
    if (rec.bound &&
        (rec.identityKey == null ||
            rec.ed25519 == null ||
            rec.accountPublicKey == null ||
            rec.epoch == null)) {
      throw const FormatException('bound record missing fields');
    }
    return rec;
  }
}

/// Kinds of user-visible identity events (rendered by IdentityChangeHandler).
enum IdentityEventKind {
  /// Legacy (unbound) peer changed keys; user had NOT verified → keys updated,
  /// conversation continues, "safety number changed" notice.
  legacyKeyChanged,

  /// Legacy peer changed keys while marked verified → blocked until the user
  /// re-verifies on the verify screen.
  legacyKeyChangeBlocked,

  /// Bound peer, same account, new device keys (reinstall) — non-blocking
  /// notice (a clue if the peer's recovery phrase leaked).
  deviceKeysChanged,

  /// Legacy → bound promotion found the previously used keys differ from the
  /// account-signed ones: earlier traffic may have been intercepted.
  interceptionSuspected,

  /// A binding failed verification (see [IdentityStoreEvent.reason]).
  bindingRejected,
}

class IdentityStoreEvent {
  final IdentityEventKind kind;
  final String peerSnowchatId;
  final IdentityBindingFailure? reason;
  final DateTime at;

  IdentityStoreEvent({
    required this.kind,
    required this.peerSnowchatId,
    this.reason,
  }) : at = DateTime.now();
}

class VerifiedIdentityStore {
  final SecureStorageService _storage;

  static const String recordPrefix = 'verified_identity_v1:';
  static const String latchPrefix = 'identity_bound_latch:';
  static const String versionMarkerKey = 'verified_identity_store_version';
  static const String ikSeededMarkerKey = 'verified_identity_ik_seeded';
  static const String legacyPinPrefix = 'signal_identity_pin:';

  /// A key that exists on every onboarded install and lives in the regular
  /// (first-unlock) keychain class. If it cannot be read the keychain is not
  /// available (BFU / locked) and readAll() enumeration is skipped.
  static const String unlockProbeKey = 'snow_chat_id';

  /// Returns whether the user has marked [snowId] as verified (Safety Number
  /// v2). Wired to IdentityVerificationDao in providers; null → never verified.
  Future<bool> Function(String snowId)? verifiedLookup;

  final Map<String, VerifiedIdentityRecord?> _recordCache = {};
  final Map<String, int?> _latchCache = {};
  bool _markerConfirmed = false;
  Future<void>? _readyFuture;

  /// L6: set when migration was deferred because the keychain was not
  /// readable (BFU / locked). `ready` re-attempts after [_lockedRetryDelay]
  /// instead of caching the deferred result for the process lifetime.
  DateTime? _deferredLockedAt;
  static const Duration _lockedRetryDelay = Duration(seconds: 30);

  final StreamController<IdentityStoreEvent> _events =
      StreamController<IdentityStoreEvent>.broadcast();

  VerifiedIdentityStore(this._storage);

  /// Identity event stream (legacy key change, device key change, rejection…).
  Stream<IdentityStoreEvent> get events => _events.stream;

  /// Broadcast an identity event. Never throws.
  void emit(IdentityStoreEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// Single readiness gate — every public method awaits it. A migration that
  /// was deferred by a locked keychain is retried (throttled) on a later read.
  Future<void> get ready {
    final deferredAt = _deferredLockedAt;
    if (_readyFuture != null &&
        deferredAt != null &&
        DateTime.now().difference(deferredAt) >= _lockedRetryDelay) {
      _deferredLockedAt = null;
      _readyFuture = null;
    }
    return _readyFuture ??= _migrateLegacyPins();
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Record for [snowId], or null. [legacyDeviceIdHint] lets the
  /// pre-migration fallback find a `signal_identity_pin:<snowId>:<device>`
  /// entry when enumeration was not possible.
  Future<VerifiedIdentityRecord?> get(
    String snowId, {
    String? legacyDeviceIdHint,
  }) async {
    if (snowId.isEmpty) return null;
    await ready;
    if (_recordCache.containsKey(snowId)) return _recordCache[snowId];
    final rec = await _readRecordRaw(snowId);
    if (rec != null) {
      _recordCache[snowId] = rec;
      return rec;
    }
    if (!_markerConfirmed) {
      final legacy = await _readLegacyPin(snowId, legacyDeviceIdHint);
      if (legacy != null) {
        await _writeRecordRaw(legacy);
        return legacy;
      }
      // Pre-marker misses are not cached: a later call may carry the
      // deviceId hint that reaches a `:device` legacy slot.
      return null;
    }
    _recordCache[snowId] = null;
    return null;
  }

  /// Like [get] but bypasses the in-memory cache (re-reads secure storage).
  /// Used before destructive decisions (session purge) so a record changed by
  /// another isolate (VoIP background isolate) is never acted on stale.
  Future<VerifiedIdentityRecord?> getFresh(
    String snowId, {
    String? legacyDeviceIdHint,
  }) async {
    if (snowId.isEmpty) return null;
    await ready;
    _recordCache.remove(snowId);
    return get(snowId, legacyDeviceIdHint: legacyDeviceIdHint);
  }

  /// Highest accepted binding epoch for [snowId]; null when the peer never
  /// proved a binding. A corrupt latch value fails closed (latched at 0).
  /// [fresh] bypasses the in-memory cache (cross-isolate safety for
  /// admission decisions and latch writes).
  Future<int?> latchedEpoch(String snowId, {bool fresh = false}) async {
    if (snowId.isEmpty) return null;
    await ready;
    if (!fresh && _latchCache.containsKey(snowId)) return _latchCache[snowId];
    final raw = await _storage.read('$latchPrefix$snowId');
    final int? value =
        raw == null ? null : (IdentityBindingV1.parseEpoch(raw) ?? 0);
    _latchCache[snowId] = value;
    return value;
  }

  /// User verification state (Safety Number v2). False when not wired.
  Future<bool> isPeerVerified(String snowId) async {
    final lookup = verifiedLookup;
    if (lookup == null) return false;
    try {
      return await lookup(snowId);
    } catch (e) {
      debugPrint('[VerifiedIdentityStore] verifiedLookup failed: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  Future<void> put(VerifiedIdentityRecord record) async {
    await ready;
    await _writeRecordRaw(record);
  }

  /// Monotonic latch: stores max(current, [epoch]). Never lowers.
  Future<void> raiseLatch(String snowId, int epoch) async {
    await ready;
    // Read-through so a latch raised by another isolate is never lowered.
    final current = await latchedEpoch(snowId, fresh: true);
    if (current != null && current >= epoch) return;
    await _storage.write('$latchPrefix$snowId', epoch.toString());
    _latchCache[snowId] = epoch;
  }

  /// Drop the record for [snowId] (contact removed / chat deleted). The latch
  /// is intentionally KEPT so a peer that once proved a binding can never be
  /// silently downgraded to an unbound key afterwards.
  Future<void> remove(String snowId) async {
    if (snowId.isEmpty) return;
    await ready;
    await _storage.delete('$recordPrefix$snowId');
    _recordCache[snowId] = null;
    if (!_markerConfirmed) {
      // Pre-migration: also drop the legacy slots so the fallback read does
      // not resurrect them.
      try {
        await _storage.delete('$legacyPinPrefix$snowId');
      } catch (_) {}
    }
  }

  /// Pin [accountPublicKey] for [snowId] from an invite link / QR the peer
  /// generated (new clients only). Latches the peer so a server can never
  /// downgrade this first contact to unbound keys. Returns false when the key
  /// does not derive [snowId] or conflicts with an already pinned key.
  Future<bool> pinFromInviteLink(
      String snowId, Uint8List accountPublicKey) async {
    if (!IdentityBindingV1.accountKeyMatchesSnowId(accountPublicKey, snowId)) {
      return false;
    }
    final existing = await get(snowId);
    if (existing?.accountPublicKey != null &&
        !constantTimeEquals(existing!.accountPublicKey, accountPublicKey)) {
      return false;
    }
    final rec = existing == null
        ? VerifiedIdentityRecord(
            snowId: snowId,
            accountPublicKey: accountPublicKey,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          )
        : existing.copyWith(accountPublicKey: accountPublicKey);
    await put(rec);
    if (await latchedEpoch(snowId) == null) {
      await raiseLatch(snowId, 0);
    }
    return true;
  }

  /// Remember a server-supplied account key for a legacy peer, only if it
  /// derives [snowId] and does not conflict with a pinned one. Used for the
  /// account-key Safety Number of peers that have no binding yet.
  Future<void> rememberAccountKey(
      String snowId, Uint8List? accountPublicKey) async {
    if (!IdentityBindingV1.accountKeyMatchesSnowId(accountPublicKey, snowId)) {
      return;
    }
    final existing = await get(snowId);
    if (existing == null) {
      await put(VerifiedIdentityRecord(
        snowId: snowId,
        accountPublicKey: accountPublicKey,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      return;
    }
    if (existing.accountPublicKey != null) return;
    await put(existing.copyWith(accountPublicKey: accountPublicKey));
  }

  /// Re-verification on the verify screen: adopt the pending (blocked) keys
  /// as current and clear the block. Returns true when something changed.
  Future<bool> acceptPendingChange(String snowId) async {
    final rec = await get(snowId);
    if (rec == null || !rec.hasPendingChange) return false;
    await put(VerifiedIdentityRecord(
      snowId: snowId,
      accountPublicKey: rec.accountPublicKey,
      deviceId: rec.pendingDeviceId ?? rec.deviceId,
      identityKey: rec.pendingIdentityKey ?? rec.identityKey,
      ed25519: rec.pendingEd25519 ?? rec.ed25519,
      bound: false,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    return true;
  }

  /// One-time seeding (§5.2): legacy pins never stored the X25519 IK, but the
  /// session store persisted `remoteIdentityKeys`. Fill the IK of unbound
  /// records (creating a legacy baseline for peers that had a session but no
  /// pin). Runs once per install, guarded by [ikSeededMarkerKey], so a later
  /// remove() is not undone on the next launch.
  ///
  /// [deviceIds] (optional) gives the device the IK was learned from (the
  /// session key `snowId:deviceId`); it is the reinstall evidence M1 uses to
  /// tell an honest reinstall from interception on promotion.
  Future<void> seedLegacyIdentityKeys(
    Map<String, Uint8List> remoteIks, {
    Map<String, String> deviceIds = const {},
  }) async {
    await ready;
    try {
      if (await _storage.read(ikSeededMarkerKey) == '1') return;
    } catch (_) {
      return; // keychain not readable — try again next launch
    }
    for (final entry in remoteIks.entries) {
      final snowId = entry.key;
      final ik = entry.value;
      if (!IdentityBindingV1.isValidSnowId(snowId) || ik.length != 32) continue;
      try {
        final rec = await get(snowId);
        final dev = deviceIds[snowId];
        if (rec == null) {
          await put(VerifiedIdentityRecord(
            snowId: snowId,
            identityKey: ik,
            deviceId: dev,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ));
        } else if (!rec.bound && rec.identityKey == null) {
          await put(rec.copyWith(
              identityKey: ik, deviceId: rec.deviceId == null ? dev : null));
        }
      } catch (e) {
        debugPrint('[VerifiedIdentityStore] IK seed failed for one peer: $e');
      }
    }
    try {
      await _storage.write(ikSeededMarkerKey, '1');
    } catch (_) {}
  }

  /// Drop in-memory caches (tests / account wipe).
  void clearCache() {
    _recordCache.clear();
    _latchCache.clear();
  }

  void dispose() {
    if (!_events.isClosed) _events.close();
  }

  // ---------------------------------------------------------------------------
  // Internal — raw IO (never awaits `ready`; used by the migration itself)
  // ---------------------------------------------------------------------------

  Future<VerifiedIdentityRecord?> _readRecordRaw(String snowId) async {
    final raw = await _storage.read('$recordPrefix$snowId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final rec = VerifiedIdentityRecord.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
      if (rec.snowId != snowId) return null;
      return rec;
    } catch (_) {
      // Corrupt entry: treat as absent. The separate latch key still blocks
      // a downgrade for peers that had proven a binding.
      debugPrint('[VerifiedIdentityStore] corrupt record ignored');
      return null;
    }
  }

  Future<void> _writeRecordRaw(VerifiedIdentityRecord rec) async {
    await _storage.write(
        '$recordPrefix${rec.snowId}', jsonEncode(rec.toJson()));
    _recordCache[rec.snowId] = rec;
  }

  /// Pre-marker fallback: bare `signal_identity_pin:<snowId>` (written by the
  /// old wallet lookup path), then `signal_identity_pin:<snowId>:<device>`
  /// (written by the old createSession/_receiveSession).
  Future<VerifiedIdentityRecord?> _readLegacyPin(
      String snowId, String? deviceHint) async {
    Uint8List? ed;
    String? deviceId;
    try {
      ed = _decodeLegacy(await _storage.read('$legacyPinPrefix$snowId'));
      if (ed == null && deviceHint != null && deviceHint.isNotEmpty) {
        ed = _decodeLegacy(
            await _storage.read('$legacyPinPrefix$snowId:$deviceHint'));
        if (ed != null) deviceId = deviceHint;
      }
    } catch (_) {
      return null;
    }
    if (ed == null) return null;
    return VerifiedIdentityRecord(
      snowId: snowId,
      deviceId: deviceId,
      ed25519: ed,
      edLegacySourced: true,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Uint8List? _decodeLegacy(String? v) {
    if (v == null || v.isEmpty) return null;
    try {
      final out = base64Decode(v);
      return out.length == 32 ? out : null;
    } catch (_) {
      return null;
    }
  }

  /// Lazy migration (see file header). Never throws.
  Future<void> _migrateLegacyPins() async {
    try {
      if (await _storage.read(versionMarkerKey) == '1') {
        _markerConfirmed = true;
        return;
      }
      // BFU / locked guard — enumeration only when the keychain is readable.
      final probe = await _storage.read(unlockProbeKey);
      if (probe == null || probe.isEmpty) {
        _deferredLockedAt = DateTime.now();
        return;
      }

      final Map<String, String> all;
      try {
        all = await _storage.readAll();
      } catch (e) {
        debugPrint('[VerifiedIdentityStore] readAll failed — per-peer '
            'fallback stays active: $e');
        return;
      }

      // snowId → (bare Ed, [(deviceId, Ed)])
      final bare = <String, Uint8List>{};
      final perDevice = <String, List<MapEntry<String, Uint8List>>>{};
      final legacyKeys = <String>[];
      for (final e in all.entries) {
        if (!e.key.startsWith(legacyPinPrefix)) continue;
        legacyKeys.add(e.key);
        final rest = e.key.substring(legacyPinPrefix.length);
        final ed = _decodeLegacy(e.value);
        if (ed == null) continue;
        if (rest.length == 36 && IdentityBindingV1.isValidSnowId(rest)) {
          bare[rest] = ed;
        } else if (rest.length > 37 && rest[36] == ':') {
          final snow = rest.substring(0, 36);
          if (!IdentityBindingV1.isValidSnowId(snow)) continue;
          perDevice
              .putIfAbsent(snow, () => [])
              .add(MapEntry(rest.substring(37), ed));
        }
      }

      final snowIds = {...bare.keys, ...perDevice.keys};
      for (final snowId in snowIds) {
        // Never overwrite a record written by the new code.
        if (await _readRecordRaw(snowId) != null) continue;
        final devs = perDevice[snowId] ?? const [];
        // M1: the `:device` pin is the key actually used in X3DH; the bare pin
        // came from a server-trusting lookup. Several device pins are
        // ambiguous (readAll order carries no recency) → migrate NO Ed for
        // that peer rather than guess; the IK seeding + next contact rebuild
        // the baseline. Every migrated Ed is flagged legacy-sourced.
        Uint8List? ed;
        String? deviceId;
        if (devs.length > 1) {
          continue;
        } else if (devs.length == 1) {
          ed = devs.first.value;
          deviceId = devs.first.key;
        } else {
          ed = bare[snowId];
        }
        if (ed == null) continue;
        await _writeRecordRaw(VerifiedIdentityRecord(
          snowId: snowId,
          deviceId: deviceId,
          ed25519: ed,
          edLegacySourced: true,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }

      await _storage.write(versionMarkerKey, '1');
      _markerConfirmed = true;

      for (final k in legacyKeys) {
        try {
          await _storage.delete(k);
        } catch (_) {}
      }
      debugPrint('[VerifiedIdentityStore] migrated ${snowIds.length} legacy '
          'pin(s)');
    } catch (e) {
      // A throwing read is the locked-keychain signature → retry later.
      _deferredLockedAt = DateTime.now();
      debugPrint('[VerifiedIdentityStore] migration deferred: $e');
    }
  }
}
