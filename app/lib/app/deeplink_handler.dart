/// @file        deeplink_handler.dart
/// @description Handles SnowChat deeplinks (Phase 1 — custom URL scheme). Two
///              first-contact forms are routed:
///                - snowchat://invite/<code>  → /invite/<code>   (community join)
///                - snowchat://user/<id>      → /add-friend?id=<id> (friend first
///                  contact — A shares their OWN id via QR/link; B taps/scans and
///                  lands on the add-friend confirm pre-filled with that id).
///              Phase 2 will replace the custom scheme with Universal Link /
///              App Link on https://snowchat.calidalab.ai/{invite,u}/... (AASA +
///              assetlinks.json hosting + web fallback for not-yet-installed
///              users). Both phases route to the same internal GoRoutes.
///
///              Why a singleton: app_links cold-start delivery can fire BEFORE
///              the router is wired (race during app startup). We capture and
///              hold the pending internal path, and consume it once the router is
///              available. Same applies to the not-yet-onboarded case (deeplink
///              arrives, user is on /welcome — store and replay after onboard).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-26
/// @lastUpdated 2026-11-10 (B-2: user deeplinks forward the inviter account key ?k=). Earlier 2026-08-05 (route snowchat://user/<id> first-contact deeplinks in
///              addition to community invites; pending model generalised to an
///              internal path)
///
/// @functions
///  - addFriendDeeplinkPath(): /add-friend route incl. optional inviter account key (B-2)
///  - DeeplinkHandler.start(): wires app_links cold + warm streams, maps a
///    SnowChat deeplink URI to its internal path, navigates via GoRouter.
///  - DeeplinkHandler.consumePending(): returns the queued internal path (if the
///    deeplink fired before the router was ready) and clears it. Called on /chat
///    mount to drain after onboarding.

library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// Internal /add-friend route for a first-contact deeplink. B-2: forwards the
/// inviter's optional account public key ([accountKeyHex], `?k=`), which
/// AddFriendScreen derive-checks and pins on send.
String addFriendDeeplinkPath(String id, String? accountKeyHex) {
  final k = (accountKeyHex != null && accountKeyHex.isNotEmpty)
      ? '&k=${Uri.encodeComponent(accountKeyHex)}'
      : '';
  return '/add-friend?id=${Uri.encodeComponent(id)}$k';
}

class DeeplinkHandler {
  DeeplinkHandler._();
  static final DeeplinkHandler instance = DeeplinkHandler._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  String? _pendingPath;
  GoRouter? _router;
  bool Function()? _canNavigateNow;

  /// Wired once from app.dart after the router is built. [canNavigateNow]
  /// returns true when the app is past onboarding + PIN unlock so we can
  /// safely push /invite — otherwise the code is held until consumePending().
  Future<void> start(
    GoRouter router, {
    required bool Function() canNavigateNow,
  }) async {
    _router = router;
    _canNavigateNow = canNavigateNow;

    // Warm start: app already running, deeplink arrives mid-session.
    _sub ??= _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) => debugPrint('[Deeplink] stream error: $e'),
    );

    // Cold start: app launched FROM a deeplink. getInitialLink fires once.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handleUri(initial);
      }
    } catch (e) {
      debugPrint('[Deeplink] initial link fetch failed: $e');
    }
  }

  void _handleUri(Uri uri) {
    debugPrint('[Deeplink] received: $uri');
    final path = _extractInternalPath(uri);
    if (path == null) {
      debugPrint('[Deeplink] not a SnowChat deeplink — ignored');
      return;
    }
    _routeOrQueue(path);
  }

  /// Maps a SnowChat deeplink URI to its internal GoRouter path, or null if it
  /// is not a recognised form. Accepts, in Phase 1 (custom scheme) and Phase 2
  /// (Universal Link) shapes:
  ///  - snowchat://invite/<code>                       → /invite/<code>
  ///  - https://snowchat.calidalab.ai/invite/<code>    → /invite/<code>
  ///  - snowchat://user/<id>                           → /add-friend?id=<id>
  ///  - https://snowchat.calidalab.ai/u/<id>           → /add-friend?id=<id>
  String? _extractInternalPath(Uri uri) {
    final code = _extractSegment(uri, snowchatHost: 'invite', httpsSeg: 'invite');
    if (code != null) return '/invite/$code';
    final id = _extractSegment(uri, snowchatHost: 'user', httpsSeg: 'u');
    // B-2: forward the inviter's account key (`?k=`) when present.
    if (id != null) return addFriendDeeplinkPath(id, uri.queryParameters['k']);
    return null;
  }

  /// Pulls the trailing token for one deeplink family. [snowchatHost] is the
  /// host in the custom scheme (snowchat://<host>/<token>); [httpsSeg] is the
  /// first path segment in the Universal Link (https://.../<httpsSeg>/<token>).
  String? _extractSegment(
    Uri uri, {
    required String snowchatHost,
    required String httpsSeg,
  }) {
    if (uri.scheme == 'snowchat' && uri.host == snowchatHost) {
      // iOS sometimes yields pathSegments=[token], sometimes path='/token'.
      if (uri.pathSegments.isNotEmpty) return uri.pathSegments.last;
      final cleaned = uri.path.replaceFirst(RegExp(r'^/'), '');
      return cleaned.isEmpty ? null : cleaned;
    }
    if (uri.scheme == 'https' &&
        uri.host == 'snowchat.calidalab.ai' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == httpsSeg) {
      return uri.pathSegments[1];
    }
    return null;
  }

  void _routeOrQueue(String path) {
    if (_router != null && (_canNavigateNow?.call() ?? false)) {
      debugPrint('[Deeplink] navigating to $path');
      _router!.push(path);
    } else {
      debugPrint('[Deeplink] queued (not ready) — path=$path');
      _pendingPath = path;
    }
  }

  /// Called from /chat tab mount after onboarding + PIN unlock complete.
  /// Returns the pending internal path (if any) and clears it.
  String? consumePending() {
    final path = _pendingPath;
    _pendingPath = null;
    return path;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
