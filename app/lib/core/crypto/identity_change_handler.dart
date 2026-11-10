/// @file        identity_change_handler.dart
/// @description Renders identity events into user-visible state. Subscribes
///              to VerifiedIdentityStore events (B-2 Identity Binding v1) and,
///              per event kind:
///                - legacyKeyChanged        → amber key-change latch +
///                                            "security keys changed" message
///                - legacyKeyChangeBlocked  → red latch + "verify again to
///                                            keep messaging" message
///                - deviceKeysChanged       → non-blocking "device keys
///                                            changed (reinstall?)" message
///                                            (Safety Number v2 is unchanged)
///                - interceptionSuspected   → red latch + "earlier messages
///                                            may have been intercepted"
///                - bindingRejected         → security warning message
///                                            (downgrade gets an "older app
///                                            version" wording)
///              System messages land in the peer's 1:1 conversation when one
///              exists. Persistent side-effects are rate-limited per
///              (peer, kind) so a hostile server flapping keys cannot spam the
///              DAO or the conversation. A broadcast stream mirrors every
///              event for live screens.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-11-10 (B-2: event-driven from VerifiedIdentityStore —
///              replaces handleMismatch(), which callers invoked from catch
///              blocks; Safety Number is no longer recomputed here because v2
///              is over ACCOUNT keys and does not change on device-key changes)
///
/// @functions
///  - IdentityChangeHandler: renders identity store events
///  - attachStore(store): subscribe to a VerifiedIdentityStore
///  - events: broadcast Stream of IdentityChangeEvent for live UI
///  - dispose(): cancel the subscription and close the stream
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../storage/daos/conversation_dao.dart';
import '../storage/daos/identity_verification_dao.dart';
import '../storage/daos/message_dao.dart';
import 'identity_binding_exception.dart';
import 'verified_identity_store.dart';

/// Event mirrored to live screens (chat banner, verify screen).
class IdentityChangeEvent {
  final String peerSnowchatId;
  final IdentityEventKind kind;
  final bool critical;
  final DateTime detectedAt;

  const IdentityChangeEvent({
    required this.peerSnowchatId,
    required this.kind,
    required this.critical,
    required this.detectedAt,
  });
}

class IdentityChangeHandler {
  final IdentityVerificationDao _dao;
  final MessageDao _messageDao;
  final ConversationDao _conversationDao;

  final StreamController<IdentityChangeEvent> _eventsController =
      StreamController<IdentityChangeEvent>.broadcast();
  StreamSubscription<IdentityStoreEvent>? _storeSub;

  /// Last persistent emission per "peer|kind".
  final Map<String, DateTime> _lastEmittedAt = {};

  /// Minimum interval between persistent emissions (DAO + system message)
  /// for the same peer and event kind. The live stream is not rate-limited.
  static const Duration _emissionCooldown = Duration(minutes: 1);

  IdentityChangeHandler({
    required IdentityVerificationDao dao,
    required MessageDao messageDao,
    required ConversationDao conversationDao,
  })  : _dao = dao,
        _messageDao = messageDao,
        _conversationDao = conversationDao;

  /// Live event stream.
  Stream<IdentityChangeEvent> get events => _eventsController.stream;

  /// Subscribe to [store] events (idempotent per handler).
  void attachStore(VerifiedIdentityStore store) {
    _storeSub?.cancel();
    _storeSub = store.events.listen((e) {
      unawaited(_render(e));
    });
  }

  Future<void> _render(IdentityStoreEvent e) async {
    final peer = e.peerSnowchatId;
    if (peer.isEmpty) return;
    final critical = e.kind == IdentityEventKind.legacyKeyChangeBlocked ||
        e.kind == IdentityEventKind.interceptionSuspected ||
        e.kind == IdentityEventKind.bindingRejected;

    final rateKey = '$peer|${e.kind.name}';
    final now = DateTime.now();
    final last = _lastEmittedAt[rateKey];
    final rateLimited =
        last != null && now.difference(last) < _emissionCooldown;

    if (!rateLimited) {
      _lastEmittedAt[rateKey] = now;
      try {
        await _persist(e, critical);
      } catch (err) {
        debugPrint('[IdentityChange] persist failed: ${err.runtimeType}');
      }
    } else {
      debugPrint('[IdentityChange] ${e.kind.name} rate-limited — event only');
    }

    if (!_eventsController.isClosed) {
      _eventsController.add(IdentityChangeEvent(
        peerSnowchatId: peer,
        kind: e.kind,
        critical: critical,
        detectedAt: e.at,
      ));
    }
  }

  Future<void> _persist(IdentityStoreEvent e, bool critical) async {
    final peer = e.peerSnowchatId;
    // 1. Banner latch (deviceKeysChanged is informational only — the account
    //    fingerprint did not change, so no banner).
    switch (e.kind) {
      case IdentityEventKind.legacyKeyChanged:
        await _dao.markKeyChange(snowchatId: peer);
      case IdentityEventKind.legacyKeyChangeBlocked:
      case IdentityEventKind.interceptionSuspected:
      case IdentityEventKind.bindingRejected:
        await _dao.markKeyChange(snowchatId: peer, critical: true);
      case IdentityEventKind.deviceKeysChanged:
        break;
    }

    // 2. In-conversation system message.
    final conv = await _conversationDao.findDirectByParticipant(peer);
    if (conv == null) return;
    await _messageDao.insertLocalSystemMessage(
      conversationId: conv.id,
      text: _textFor(e),
      eventType: _eventTypeFor(e.kind),
      metadata: {
        'peerSnowchatId': peer,
        'identityEvent': e.kind.name,
        if (e.reason != null) 'reason': e.reason!.name,
        'critical': critical,
        'detectedAtMs': e.at.millisecondsSinceEpoch,
      },
    );
  }

  static String _eventTypeFor(IdentityEventKind kind) {
    switch (kind) {
      case IdentityEventKind.legacyKeyChanged:
      case IdentityEventKind.legacyKeyChangeBlocked:
        return 'safety_number_changed';
      case IdentityEventKind.deviceKeysChanged:
        return 'device_keys_changed';
      case IdentityEventKind.interceptionSuspected:
        return 'identity_interception_suspected';
      case IdentityEventKind.bindingRejected:
        return 'identity_binding_rejected';
    }
  }

  static String _textFor(IdentityStoreEvent e) {
    switch (e.kind) {
      case IdentityEventKind.legacyKeyChanged:
        return "This contact's security keys changed (for example after a "
            'reinstall). Tap to verify.';
      case IdentityEventKind.legacyKeyChangeBlocked:
        return 'You verified this contact, but their security keys changed. '
            'Messaging is paused until you verify them again.';
      case IdentityEventKind.deviceKeysChanged:
        return "This contact's device keys changed (for example after a "
            'reinstall). Their account is the same.';
      case IdentityEventKind.interceptionSuspected:
        return 'Warning: the keys used earlier in this conversation were not '
            "signed by this contact's account. Earlier messages may have been "
            'intercepted. Verify this contact before sharing anything '
            'sensitive.';
      case IdentityEventKind.bindingRejected:
        if (e.reason == IdentityBindingFailure.downgrade) {
          return 'This contact appears to be using an older SnowChat version '
              "that cannot prove their identity. Messages can't be exchanged "
              'until they update.';
        }
        return "A message or session from this contact was rejected because "
            "their identity proof didn't verify. Someone may be trying to "
            'impersonate them.';
    }
  }

  void dispose() {
    _storeSub?.cancel();
    _storeSub = null;
    if (!_eventsController.isClosed) {
      _eventsController.close();
    }
  }
}
