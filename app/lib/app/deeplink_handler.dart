/// @file        deeplink_handler.dart
/// @description Handles snowchat://invite/<code> deeplinks (Phase 1 — custom
///              URL scheme). Phase 2 will replace this with Universal Link /
///              App Link on https://snowchat.calidalab.ai/invite/<code> with
///              AASA + assetlinks.json hosting + web fallback for not-yet-installed
///              users. Both phases route to the same /invite/<code> GoRoute.
///
///              Why a singleton: app_links cold-start delivery can fire BEFORE
///              the router is wired (race during app startup). We capture and
///              hold the pending code, and consume it once the router is
///              available. Same applies to the not-yet-onboarded case (deeplink
///              arrives, user is on /welcome — store and replay after onboard).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-26
/// @lastUpdated 2026-04-26
///
/// @functions
///  - DeeplinkHandler.start(): wires app_links cold + warm streams, processes
///    snowchat://invite/<code>, navigates via GoRouter.
///  - DeeplinkHandler.consumePending(): returns the queued invite code (if
///    deeplink fired before router was ready) and clears it. Called on /chat
///    mount to drain after onboarding.

library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

class DeeplinkHandler {
  DeeplinkHandler._();
  static final DeeplinkHandler instance = DeeplinkHandler._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  String? _pendingInviteCode;
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
    final code = _extractInviteCode(uri);
    if (code == null) {
      debugPrint('[Deeplink] not an invite uri — ignored');
      return;
    }
    _routeOrQueue(code);
  }

  /// Accepts both:
  ///  - snowchat://invite/<code>      (Phase 1)
  ///  - https://snowchat.calidalab.ai/invite/<code> (Phase 2 — Universal Link)
  String? _extractInviteCode(Uri uri) {
    final isSnowchatScheme =
        uri.scheme == 'snowchat' && uri.host == 'invite';
    final isUniversalLink = uri.scheme == 'https' &&
        uri.host == 'snowchat.calidalab.ai' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'invite';
    if (!isSnowchatScheme && !isUniversalLink) return null;

    // snowchat://invite/<code>           → host=invite, path=/<code> OR pathSegments=[<code>]
    // snowchat://invite/<code> on iOS    → sometimes pathSegments=[code], sometimes path='/code'
    // https://...calidalab.ai/invite/<code> → pathSegments=[invite, <code>]
    if (isSnowchatScheme) {
      if (uri.pathSegments.isNotEmpty) return uri.pathSegments.last;
      // Fallback: strip leading slash from path.
      final cleaned = uri.path.replaceFirst(RegExp(r'^/'), '');
      return cleaned.isEmpty ? null : cleaned;
    }
    return uri.pathSegments.length >= 2 ? uri.pathSegments[1] : null;
  }

  void _routeOrQueue(String code) {
    if (_router != null && (_canNavigateNow?.call() ?? false)) {
      debugPrint('[Deeplink] navigating to /invite/$code');
      _router!.push('/invite/$code');
    } else {
      debugPrint('[Deeplink] queued (not ready) — code=$code');
      _pendingInviteCode = code;
    }
  }

  /// Called from /chat tab mount after onboarding + PIN unlock complete.
  /// Returns the pending code (if any) and clears it.
  String? consumePending() {
    final code = _pendingInviteCode;
    _pendingInviteCode = null;
    return code;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
