/// @file        verified_identity_store.dart
/// @description B-2 Identity Binding v1 — per-peer store of the remote
///              identity we have verified. Bindings are mandatory, so a record
///              is either BOUND (account key, device, epoch, IK, Ed, binding
///              signature — written by IdentityAdmission.admitBound) or holds
///              only a pinned ACCOUNT key (pinAccountKey /
///              rememberAccountKey). No record carries keys that were not
///              proven by a binding.
///
///              Storage layout (SecureStorageService — app-global
///              flutter_secure_storage config, never a second instance):
///                verified_identity_v1:<snowId>  → JSON record (schema 1)
///                identity_bound_latch:<snowId>  → decimal max accepted epoch
///                                                 (presence = latched; NEVER
///                                                 deleted by remove())
///                identity_vouched:<snowId>      → the first way this user
///                                                 vouched (VouchSource name)
///                                                 (NEVER deleted by remove())
///
///              The latch says the account proved its key; it is raised by
///              every 1:1 session, whoever started it. Being VOUCHED says
///              this user chose the account by an action of their own on
///              this device (VouchSource) — what the group pickers treat as
///              "known" (design 2026-11-20-community-roster §4).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-10
/// @lastUpdated 2026-11-22 (friend graph off the server: the nickname lookup names the account,
///              so a request is vouched for when it is made — rememberNickRequest /
///              settleNickRequests are gone; VouchSource.restored — an account of this user's list
///              restored from the sealed contact backup; pinFromInviteLink → pinAccountKey (a link,
///              a QR, or the backup pin the account key)). Earlier 2026-11-21 (rememberNickRequest / settleNickRequests: a friend request sent by
///              nickname vouches once the accepted friend list shows that nickname — that path
///              never names the account at send time). Earlier 2026-11-21 (vouch() / isVouched(): accounts this user chose by an action of their own — the "known" accounts of the group pickers). Earlier same day (legacy TOFU removed: no legacy pin migration and readiness gate, no IK seeding, no pending key changes or acceptPendingChange, no edLegacySourced, no isPeerVerified / verifiedLookup, no legacyKeyChanged / legacyKeyChangeBlocked / interceptionSuspected events; rememberAccountKey only fills a missing record). Earlier 2026-11-20 (comment: no GMK signatures). Earlier 2026-11-10 (review fixes: M1 ambiguous device pins migrate no Ed, migrated Eds flagged legacy-sourced, IK seeding carries the deviceId; L6 a keychain-locked deferral is retried on a later read)
///
/// @functions
///  - VerifiedIdentityRecord: per-peer record (+ JSON codec)
///  - IdentityStoreEvent / IdentityEventKind: user-visible identity events
///  - VerifiedIdentityStore.get(): record for a snowId
///  - VerifiedIdentityStore.getFresh(): cache-bypassing read (cross-isolate safety)
///  - VerifiedIdentityStore.latchedEpoch(): highest bound epoch, null if never bound
///  - VerifiedIdentityStore.put(): persist a record
///  - VerifiedIdentityStore.raiseLatch(): monotonic latch update
///  - VerifiedIdentityStore.remove(): drop the record (latch is kept)
///  - VerifiedIdentityStore.pinAccountKey(): pin an account key from a link / QR / the contact backup
///  - VerifiedIdentityStore.rememberAccountKey(): store a derive-checked account key
///  - VerifiedIdentityStore.vouch(): this user vouched for an account (kept)
///  - VerifiedIdentityStore.isVouched(): whether this user ever did
///  - VouchSource: the actions of the user that vouch
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
  /// derives the snowId (the verify screen).
  final Uint8List? accountPublicKey;

  /// Device the current keys belong to.
  final String? deviceId;

  /// Epoch of the accepted binding (bound records only).
  final int? epoch;

  /// X25519 identity key used in X3DH.
  final Uint8List? identityKey;

  /// Signal-layer Ed25519 signing key (SPK signatures, wallet sigs).
  final Uint8List? ed25519;

  /// Binding signature (bound records only).
  final Uint8List? bindingSignature;

  /// True once a valid binding was accepted for the current keys.
  final bool bound;

  /// ms since epoch of the last write.
  final int updatedAt;

  const VerifiedIdentityRecord({
    required this.snowId,
    this.accountPublicKey,
    this.deviceId,
    this.epoch,
    this.identityKey,
    this.ed25519,
    this.bindingSignature,
    this.bound = false,
    required this.updatedAt,
  });

  /// The record with [accountPublicKey] set (the only field a non-binding
  /// write changes).
  VerifiedIdentityRecord copyWith({Uint8List? accountPublicKey}) {
    return VerifiedIdentityRecord(
      snowId: snowId,
      accountPublicKey: accountPublicKey ?? this.accountPublicKey,
      deviceId: deviceId,
      epoch: epoch,
      identityKey: identityKey,
      ed25519: ed25519,
      bindingSignature: bindingSignature,
      bound: bound,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
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
        if (bindingSignature != null) 'sig': base64Encode(bindingSignature!),
        'bound': bound,
        'updatedAt': updatedAt,
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
      bindingSignature: b64('sig', len: 64),
      bound: j['bound'] as bool? ?? false,
      updatedAt: j['updatedAt'] as int? ?? 0,
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
  /// Bound peer, same account, new device keys (reinstall) — non-blocking
  /// notice (a clue if the peer's recovery phrase leaked).
  deviceKeysChanged,

  /// A binding failed verification, or the peer presented none (see
  /// [IdentityStoreEvent.reason]).
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

/// The actions of this user, on this device, that vouch for an account.
/// Nothing the network does — a message, a session, a key — vouches.
enum VouchSource {
  /// Sent a friend request to it (typed, scanned or from its invite link).
  friendRequest,

  /// Accepted its friend request.
  friendAccepted,

  /// Wrote it a message in a 1:1 chat.
  message,

  /// Marked its safety number as verified.
  safetyNumber,

  /// Restored into this user's list from the account's own sealed contact
  /// backup — it was chosen on an earlier install (the backup is
  /// authenticated with the recovery phrase's key: the server cannot add to
  /// it).
  restored,
}

class VerifiedIdentityStore {
  final SecureStorageService _storage;

  static const String recordPrefix = 'verified_identity_v1:';
  static const String latchPrefix = 'identity_bound_latch:';
  static const String vouchedPrefix = 'identity_vouched:';

  final Map<String, VerifiedIdentityRecord?> _recordCache = {};
  final Map<String, int?> _latchCache = {};
  final Map<String, bool> _vouchedCache = {};

  final StreamController<IdentityStoreEvent> _events =
      StreamController<IdentityStoreEvent>.broadcast();

  VerifiedIdentityStore(this._storage);

  /// Identity event stream (device key change, rejection).
  Stream<IdentityStoreEvent> get events => _events.stream;

  /// Broadcast an identity event. Never throws.
  void emit(IdentityStoreEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Record for [snowId], or null.
  Future<VerifiedIdentityRecord?> get(String snowId) async {
    if (snowId.isEmpty) return null;
    if (_recordCache.containsKey(snowId)) return _recordCache[snowId];
    final rec = await _readRecordRaw(snowId);
    _recordCache[snowId] = rec;
    return rec;
  }

  /// Like [get] but bypasses the in-memory cache (re-reads secure storage).
  /// Used before destructive decisions (session purge) so a record changed by
  /// another isolate (VoIP background isolate) is never acted on stale.
  Future<VerifiedIdentityRecord?> getFresh(String snowId) async {
    if (snowId.isEmpty) return null;
    _recordCache.remove(snowId);
    return get(snowId);
  }

  /// Highest accepted binding epoch for [snowId]; null when the peer never
  /// proved a binding. A corrupt latch value fails closed (latched at 0).
  /// [fresh] bypasses the in-memory cache (cross-isolate safety for
  /// admission decisions and latch writes).
  Future<int?> latchedEpoch(String snowId, {bool fresh = false}) async {
    if (snowId.isEmpty) return null;
    if (!fresh && _latchCache.containsKey(snowId)) return _latchCache[snowId];
    final raw = await _storage.read('$latchPrefix$snowId');
    final int? value =
        raw == null ? null : (IdentityBindingV1.parseEpoch(raw) ?? 0);
    _latchCache[snowId] = value;
    return value;
  }

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  Future<void> put(VerifiedIdentityRecord record) => _writeRecordRaw(record);

  /// Monotonic latch: stores max(current, [epoch]). Never lowers.
  Future<void> raiseLatch(String snowId, int epoch) async {
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
    await _storage.delete('$recordPrefix$snowId');
    _recordCache[snowId] = null;
  }

  /// Pin [accountPublicKey] for [snowId] — from an invite link / QR the peer
  /// generated, or from this account's own sealed contact backup. Latches
  /// the peer so a server can never downgrade this contact to unbound keys.
  /// Returns false when the key does not derive [snowId] or conflicts with an
  /// already pinned key.
  Future<bool> pinAccountKey(
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

  /// Remember a server-supplied account key for a peer this device has no
  /// record of yet, only if it derives [snowId]. Used for the account-key
  /// Safety Number of a peer not met yet. (Every existing record already
  /// holds the account key: a binding carries it, a pin is one.)
  Future<void> rememberAccountKey(
      String snowId, Uint8List? accountPublicKey) async {
    if (!IdentityBindingV1.accountKeyMatchesSnowId(accountPublicKey, snowId)) {
      return;
    }
    if (await get(snowId) != null) return;
    await put(VerifiedIdentityRecord(
      snowId: snowId,
      accountPublicKey: accountPublicKey,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  // ---------------------------------------------------------------------------
  // Vouching
  // ---------------------------------------------------------------------------

  /// This user vouched for [snowId] by [source]. The first source is kept;
  /// the mark survives remove() (a deleted chat) and goes only with the
  /// whole store (an account reset). Not a snowId: ignored.
  Future<void> vouch(String snowId, VouchSource source) async {
    if (!IdentityBindingV1.isValidSnowId(snowId)) return;
    if (await isVouched(snowId)) return;
    await _storage.write('$vouchedPrefix$snowId', source.name);
    _vouchedCache[snowId] = true;
  }

  /// Whether this user ever vouched for [snowId] on this device.
  Future<bool> isVouched(String snowId) async {
    if (!IdentityBindingV1.isValidSnowId(snowId)) return false;
    final cached = _vouchedCache[snowId];
    if (cached != null) return cached;
    final value = await _storage.read('$vouchedPrefix$snowId') != null;
    _vouchedCache[snowId] = value;
    return value;
  }

  /// Drop in-memory caches (tests / account wipe).
  void clearCache() {
    _recordCache.clear();
    _latchCache.clear();
    _vouchedCache.clear();
  }

  void dispose() {
    if (!_events.isClosed) _events.close();
  }

  // ---------------------------------------------------------------------------
  // Internal — raw IO
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
}
