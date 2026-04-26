/// @file        sender_certificate_manager.dart
/// @description Sealed Sender certificate cache management. Issues certificates from the server, in-memory cache, TTL-1h auto-renew
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-11
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - SenderCertificateManager: Certificate cache/renewal management class
///  - SenderCertificateManager.getCertificate(): Return a valid certificate (from cache or fresh from server)
///  - SenderCertificateManager.invalidate(): Force-invalidate the cached certificate
///  - SenderCertificateManager.dispose(): Release the renewal timer

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import 'sender_certificate.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Certificate endpoint path (appended to ApiClient base URL).
const String _certificateEndpoint = '/auth/sender-certificate';

/// Renew the certificate this many milliseconds before expiry.
/// Algorithm spec: "Schedule renewal at T - 1 hour".
const int _renewalMarginMs = 60 * 60 * 1000; // 1 hour

// ---------------------------------------------------------------------------
// SenderCertificateManager
// ---------------------------------------------------------------------------

/// Manages fetching, caching, and auto-renewing [SenderCertificate] instances
/// from the SnowChat server.
///
/// Thread-safety: all access is serialized through a single [Completer] gate
/// so concurrent callers share the same in-flight fetch rather than issuing
/// duplicate requests.
///
/// Usage:
/// ```dart
/// final manager = SenderCertificateManager(apiClient: apiClient);
/// final cert = await manager.getCertificate();
/// // cert is guaranteed non-expired (or an exception is thrown)
/// ```
class SenderCertificateManager {
  final ApiClient _apiClient;

  /// Cached certificate (null if never fetched or explicitly invalidated).
  SenderCertificate? _cached;

  /// In-flight fetch future. When non-null, concurrent callers await this
  /// instead of issuing a new HTTP request.
  Completer<SenderCertificate>? _inflight;

  /// Timer for proactive renewal before expiry.
  Timer? _renewalTimer;

  SenderCertificateManager({
    required ApiClient apiClient,
  }) : _apiClient = apiClient;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Return a valid (non-expired) [SenderCertificate].
  ///
  /// - Returns the cached certificate if it is still valid (expiry > now + margin).
  /// - Otherwise, fetches a new one from the server and caches it.
  /// - Concurrent calls share a single in-flight fetch.
  ///
  /// Throws on network errors or if the server returns an error (401, 429, etc.).
  Future<SenderCertificate> getCertificate() async {
    // Fast path: cached certificate is still well within validity.
    final cached = _cached;
    if (cached != null && !_needsRenewal(cached)) {
      return cached;
    }

    // Slow path: need to fetch. Serialize concurrent callers.
    if (_inflight != null) {
      return _inflight!.future;
    }

    final completer = Completer<SenderCertificate>();
    _inflight = completer;

    try {
      final cert = await _fetchFromServer();
      _cached = cert;
      _scheduleRenewal(cert);
      completer.complete(cert);
      return cert;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _inflight = null;
    }
  }

  /// Force-invalidate the cached certificate (e.g., after identity key change).
  void invalidate() {
    _cached = null;
    _renewalTimer?.cancel();
    _renewalTimer = null;
  }

  /// Cancel renewal timer and release resources.
  void dispose() {
    _renewalTimer?.cancel();
    _renewalTimer = null;
    _cached = null;
    _inflight = null;
  }

  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------

  /// Whether [cert] is close enough to expiry that we should proactively renew.
  bool _needsRenewal(SenderCertificate cert) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return cert.expiryMs - nowMs < _renewalMarginMs;
  }

  /// Fetch a fresh certificate from POST /api/v2/auth/sender-certificate.
  ///
  /// The server responds with:
  /// ```json
  /// { "certificate": "<base64 177-byte cert>", "expiresAt": "<ISO 8601>" }
  /// ```
  Future<SenderCertificate> _fetchFromServer() async {
    debugPrint('[SenderCertificateManager] Fetching new sender certificate');

    final response = await _apiClient.post(_certificateEndpoint);
    final data = response.data as Map<String, dynamic>;

    final certBase64 = data['certificate'] as String;
    final certBytes = base64Decode(certBase64);

    final cert = SenderCertificate.fromBytes(Uint8List.fromList(certBytes));

    debugPrint(
      '[SenderCertificateManager] Certificate received: '
      'sender=${cert.senderSnowchatId}, '
      'expiry=${DateTime.fromMillisecondsSinceEpoch(cert.expiryMs).toIso8601String()}',
    );

    return cert;
  }

  /// Schedule a background renewal at (expiry - margin).
  void _scheduleRenewal(SenderCertificate cert) {
    _renewalTimer?.cancel();

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final renewAtMs = cert.expiryMs - _renewalMarginMs;
    final delayMs = renewAtMs - nowMs;

    if (delayMs <= 0) {
      // Already past the renewal point -- will be fetched on next getCertificate().
      return;
    }

    _renewalTimer = Timer(Duration(milliseconds: delayMs), () async {
      debugPrint('[SenderCertificateManager] Auto-renewing certificate');
      try {
        final newCert = await _fetchFromServer();
        _cached = newCert;
        _scheduleRenewal(newCert);
      } catch (e) {
        // Renewal failure is non-fatal. The next getCertificate() call will
        // retry. Log and move on.
        debugPrint(
          '[SenderCertificateManager] Auto-renewal failed: $e '
          '(will retry on next getCertificate())',
        );
        _cached = null;
      }
    });

    debugPrint(
      '[SenderCertificateManager] Renewal scheduled in '
      '${(delayMs / 1000 / 60).toStringAsFixed(1)} minutes',
    );
  }
}
