/// @file        identity_change_handler.dart
/// @description Central handler for IdentityKeyChangedException events. The
///              SignalProtocolService raises a typed exception when the TOFU
///              pin store sees a new Ed25519 key for an existing peer; the
///              upper layers (EncryptedMessageHandler send path, MessageQueue
///              dead-letter path) call into here to:
///                1. Recompute the Safety Number against the NEW peer key.
///                2. Latch the mismatch in IdentityVerificationDao
///                   (snapshots wasPreviouslyVerified for banner severity).
///                3. Insert a single in-conversation system message
///                   ("Safety number with {peer} changed."), if a
///                   conversationId is known.
///                4. Broadcast the event on a Stream so live screens can
///                   render an in-line banner without polling the DAO.
///
///              The handler is intentionally async-fire-and-forget so the
///              callers (which are mostly in error paths) don't have to
///              await UI persistence work.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-26 (header English translation; P0-2 Stage 4-2: per-peer 1s rate-limit on DAO write + system message — block DoS / key-flapping)
///
/// @functions
///  - IdentityChangeHandler: orchestrates Safety Number + DAO + system msg
///  - handleMismatch(...): full TOFU mismatch pipeline
///  - events: broadcast Stream of IdentityChangeEvent for UI banners
///  - dispose(): close the broadcast controller
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../storage/daos/identity_verification_dao.dart';
import '../storage/daos/message_dao.dart';
import '../storage/tables/messages_table.dart';
import 'identity_manager.dart';
import 'safety_number.dart';

/// Public event emitted whenever the local TOFU pin store catches a new
/// remote key for a peer we already had a session with.
class IdentityChangeEvent {
  final String peerSnowchatId;
  final String? conversationId;
  final String newSafetyNumber;
  final bool wasPreviouslyVerified;
  final DateTime detectedAt;

  const IdentityChangeEvent({
    required this.peerSnowchatId,
    required this.conversationId,
    required this.newSafetyNumber,
    required this.wasPreviouslyVerified,
    required this.detectedAt,
  });
}

class IdentityChangeHandler {
  final IdentityVerificationDao _dao;
  final MessageDao _messageDao;
  final IdentityManager _identityManager;

  final StreamController<IdentityChangeEvent> _eventsController =
      StreamController<IdentityChangeEvent>.broadcast();

  /// In-memory dedupe so a flapping ratchet doesn't insert the same banner /
  /// system message twice in a row for the same (peer, key) pair.
  final Map<String, String> _lastSeenKeyB64 = {};

  /// P0-2 Stage 4-2: per-peer rate-limit. Protects against a malicious server
  /// (or a bug) flapping the peer's identity key A→B→A→B at high frequency,
  /// which would otherwise spam the IdentityVerificationDao with writes and
  /// pollute the conversation with repeated "safety number changed" system
  /// messages. Within [_emissionCooldown] of the previous emission, we only
  /// fire the broadcast event (so a freshly opened banner still renders) and
  /// skip the persistent side-effects.
  final Map<String, DateTime> _lastEmittedAt = {};

  /// Minimum interval between persistent emissions (DAO + system message)
  /// per peer. The event stream is NOT rate-limited so live screens still
  /// see every transition.
  static const Duration _emissionCooldown = Duration(seconds: 1);

  IdentityChangeHandler({
    required IdentityVerificationDao dao,
    required MessageDao messageDao,
    required IdentityManager identityManager,
  })  : _dao = dao,
        _messageDao = messageDao,
        _identityManager = identityManager;

  /// Live event stream — chat screens listen and show a banner.
  Stream<IdentityChangeEvent> get events => _eventsController.stream;

  /// Run the full mismatch pipeline. Safe to call from a catch{}.
  ///
  /// [conversationId] may be null when the mismatch is detected in a path
  /// that does not yet have a conversation row (e.g. first SKDM exchange).
  /// In that case the system message step is skipped.
  Future<void> handleMismatch({
    required String peerSnowchatId,
    required String? conversationId,
    required Uint8List oldKey,
    required Uint8List newKey,
  }) async {
    if (peerSnowchatId.isEmpty) return;
    if (newKey.length != 32) {
      debugPrint('[IdentityChange] ignoring mismatch with bad key length '
          '(${newKey.length})');
      return;
    }

    // Dedupe: if we already processed this exact new key for this peer in
    // this process lifetime, skip the DAO/system message work but DO emit
    // the event again so a freshly opened screen still shows the banner.
    final newKeyB64 = base64Encode(newKey);
    final alreadySeen = _lastSeenKeyB64[peerSnowchatId] == newKeyB64;
    _lastSeenKeyB64[peerSnowchatId] = newKeyB64;

    // P0-2 Stage 4-2: per-peer 1s rate-limit on persistent side-effects.
    // A malicious server (or a bug) flapping keys A→B→A→B would otherwise
    // hammer the DAO and spam system messages. The broadcast event is NOT
    // suppressed — live banners still react instantly.
    final now = DateTime.now();
    final lastEmittedAt = _lastEmittedAt[peerSnowchatId];
    final rateLimited = lastEmittedAt != null &&
        now.difference(lastEmittedAt) < _emissionCooldown;
    _lastEmittedAt[peerSnowchatId] = now;

    // 1. Recompute Safety Number against NEW key.
    final mySnow = await _identityManager.getSnowChatId();
    final myEd = await _identityManager.getPublicKey();
    if (mySnow == null || mySnow.isEmpty || myEd == null) {
      debugPrint('[IdentityChange] cannot compute Safety Number — '
          'local identity unavailable');
      return;
    }

    final String newSafetyNumber;
    try {
      newSafetyNumber = SafetyNumber.compute(
        mySnowId: mySnow,
        myEd25519: myEd,
        theirSnowId: peerSnowchatId,
        theirEd25519: newKey,
      );
    } catch (e) {
      debugPrint('[IdentityChange] SafetyNumber.compute failed: $e');
      return;
    }

    bool wasPreviouslyVerified = false;
    // Persist DAO latch + system message only when (a) we have not already
    // processed this exact key, AND (b) the per-peer rate limit has elapsed.
    // Either condition skipping → still emit the event so live UI updates.
    if (!alreadySeen && !rateLimited) {
      // 2. DAO latch (markMismatch reads the existing verified flag and
      //    snapshots it into wasPreviouslyVerified).
      try {
        final existing = await _dao.getByPeer(peerSnowchatId);
        wasPreviouslyVerified = existing?.verified ?? false;
        await _dao.markMismatch(
          snowchatId: peerSnowchatId,
          newKey: newKey,
          newSafetyNumber: newSafetyNumber,
        );
      } catch (e) {
        debugPrint('[IdentityChange] DAO markMismatch failed: $e');
      }

      // 3. System message (only if we know the conversation).
      if (conversationId != null && conversationId.isNotEmpty) {
        try {
          await _messageDao.insertLocalSystemMessage(
            conversationId: conversationId,
            text:
                'The safety number with $peerSnowchatId changed. Tap to verify.',
            eventType: 'safety_number_changed',
            metadata: {
              'peerSnowchatId': peerSnowchatId,
              'wasPreviouslyVerified': wasPreviouslyVerified,
              'detectedAtMs': DateTime.now().millisecondsSinceEpoch,
            },
          );
        } catch (e) {
          debugPrint('[IdentityChange] insertLocalSystemMessage failed: $e');
        }
      }
    } else {
      if (rateLimited) {
        debugPrint('[IdentityChange] rate-limited for $peerSnowchatId '
            '(< ${_emissionCooldown.inMilliseconds}ms since last emission) — '
            'skipping DAO write + system message; emitting event only');
      }
      // Even on dedupe / rate-limit, fetch the latched verified-snapshot
      // for the event so any newly opened banner has correct severity.
      try {
        final existing = await _dao.getByPeer(peerSnowchatId);
        wasPreviouslyVerified = existing?.wasPreviouslyVerified ??
            (existing?.verified ?? false);
      } catch (_) {}
    }

    // 4. Emit event.
    if (!_eventsController.isClosed) {
      _eventsController.add(IdentityChangeEvent(
        peerSnowchatId: peerSnowchatId,
        conversationId: conversationId,
        newSafetyNumber: newSafetyNumber,
        wasPreviouslyVerified: wasPreviouslyVerified,
        detectedAt: DateTime.now(),
      ));
    }
  }

  void dispose() {
    if (!_eventsController.isClosed) {
      _eventsController.close();
    }
  }
}

// Keep the unused-import warning quiet — Value/LocalMessagesCompanion are
// referenced indirectly via insertLocalSystemMessage's signature.
// ignore: unused_element
const _keepImports = [Value, LocalMessages];
