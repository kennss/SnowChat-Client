/// @file        turn_credential_manager.dart
/// @description Cloudflare Realtime TURN credential cache (Phase 8.2 §14.4~14.5)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - TurnCredentialManager.getIceServers(): return cached ICE servers (auto-refresh on expiry)
///  - TurnCredentialManager.invalidate(): invalidate cache (forces re-issuance after call failure)

import 'package:flutter/foundation.dart';

import '../network/api_client.dart';

/// Cloudflare TURN REST API (server proxy) credential cache.
///
/// - Reuse the same ICE servers within the 24h TTL (avoid unnecessary API calls)
/// - Proactive refresh 30 minutes before expiry (safety margin)
/// - Issuance happens at the `GET /api/v2/turn/credentials` server route (plan §14.4)
class TurnCredentialManager {
  TurnCredentialManager({required ApiClient apiClient})
      : _apiClient = apiClient;

  final ApiClient _apiClient;

  List<Map<String, dynamic>>? _cached;
  DateTime? _expiresAt;

  /// Return a valid list of ICE servers.
  ///
  /// If the cache is within 30 minutes of expiry, request re-issuance from the server.
  /// On network failure, reuse the cache even if expired (fallback to prevent call cutoff).
  Future<List<Map<String, dynamic>>> getIceServers() async {
    final safetyMargin = const Duration(minutes: 30);
    final now = DateTime.now();
    if (_cached != null &&
        _expiresAt != null &&
        _expiresAt!.subtract(safetyMargin).isAfter(now)) {
      return _cached!;
    }

    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/turn/credentials',
      );
      final data = response.data;
      if (data == null || data['iceServers'] == null) {
        throw StateError('Invalid TURN credentials response');
      }
      _cached = (data['iceServers'] as List).cast<Map<String, dynamic>>();
      final ttl = (data['ttl'] as int?) ?? (24 * 3600);
      _expiresAt = now.add(Duration(seconds: ttl));
      return _cached!;
    } catch (e) {
      // On Cloudflare/network transient failure, reuse the existing cache (prevents total call block)
      if (_cached != null) {
        debugPrint('[TURN] credentials fetch failed, using expired cache: $e');
        return _cached!;
      }
      rethrow;
    }
  }

  /// Invalidate cache. Used to force re-issuance after a call/ICE failure.
  void invalidate() {
    _cached = null;
    _expiresAt = null;
  }
}
