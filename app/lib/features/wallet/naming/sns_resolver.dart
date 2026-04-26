/// @file        sns_resolver.dart
/// @description Bonfida SNS (.sol domain) resolver — uses the official HTTP
///              API (Spike S8). 1-hour in-memory cache. On failure surface
///              the error explicitly to the user (anti-spoofing).
///              Phase 6.1 §3.6.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - SnsResolver.resolveDomain(): "name.sol" → Solana address
///  - SnsResolver.reverseLookup(): address → favorite domain
///  - SnsCacheEntry: cached result
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SnsResolveResult {
  const SnsResolveResult({
    required this.domain,
    required this.address,
    required this.fetchedAtMs,
  });

  final String domain;
  final String address;
  final int fetchedAtMs;
}

class SnsResolveException implements Exception {
  SnsResolveException(this.message);
  final String message;

  @override
  String toString() => 'SnsResolveException: $message';
}

/// Bonfida SNS domain resolver.
///
/// API used: `https://sns-api.bonfida.com/v2/domains/resolve/<domain>`
/// Example response: `{ "result": "<base58 address>" }` or 404.
///
/// Policy:
/// - Cache TTL: 1 hour (in-memory Map)
/// - On failure, throw SnsResolveException to caller → caller blocks the transfer
/// - Result is a plain address String. Caller must explicitly show the user
///   the resolution result alongside the address.
class SnsResolver {
  SnsResolver({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Map<String, SnsResolveResult> _cache = {};

  static const _baseUrl = 'https://sns-api.bonfida.com';
  static const _cacheTtl = Duration(hours: 1);
  static const _timeout = Duration(seconds: 8);

  /// Check whether the input ends with `.sol`.
  static bool isSnsDomain(String input) {
    final trimmed = input.trim().toLowerCase();
    return trimmed.endsWith('.sol') && trimmed.length > 4;
  }

  /// Resolve a `.sol` domain to a Solana address.
  ///
  /// [domain] form "vitalik.sol". Case-insensitive.
  /// Returns: SnsResolveResult.
  /// Throws [SnsResolveException] on failure.
  Future<SnsResolveResult> resolveDomain(String domain) async {
    final normalized = domain.trim().toLowerCase();
    if (!isSnsDomain(normalized)) {
      throw SnsResolveException('Not a .sol domain: $domain');
    }

    // cache lookup
    final now = DateTime.now().millisecondsSinceEpoch;
    final cached = _cache[normalized];
    if (cached != null &&
        now - cached.fetchedAtMs < _cacheTtl.inMilliseconds) {
      return cached;
    }

    final namePart = normalized.substring(0, normalized.length - 4);
    final url = Uri.parse('$_baseUrl/v2/domains/resolve/$namePart');

    try {
      final res = await _http.get(url).timeout(_timeout);
      if (res.statusCode == 404) {
        throw SnsResolveException('Domain not found: $domain');
      }
      if (res.statusCode != 200) {
        throw SnsResolveException(
          'Resolver HTTP ${res.statusCode}: ${res.body}',
        );
      }

      final body = jsonDecode(res.body);
      final dynamic addr = body is Map ? body['result'] : null;
      if (addr is! String || addr.isEmpty) {
        throw SnsResolveException('Resolver returned empty address');
      }

      final result = SnsResolveResult(
        domain: normalized,
        address: addr,
        fetchedAtMs: now,
      );
      _cache[normalized] = result;
      return result;
    } on SnsResolveException {
      rethrow;
    } catch (e) {
      debugPrint('[SnsResolver] resolve $domain failed: $e');
      throw SnsResolveException('Resolver request failed: $e');
    }
  }

  /// Solana address → favorite `.sol` domain (if any). Display-only.
  ///
  /// Returns null on failure or no registered domain.
  Future<String?> reverseLookup(String address) async {
    if (address.length < 32 || address.length > 44) return null;
    final url = Uri.parse(
      '$_baseUrl/v2/user/domains/$address',
    );
    try {
      final res = await _http.get(url).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is Map && body['result'] is List) {
        final list = body['result'] as List;
        if (list.isEmpty) return null;
        // domain field of the first entry (per Bonfida's response format)
        final first = list.first;
        if (first is Map && first['domain'] is String) {
          return '${first['domain']}.sol';
        }
        if (first is String) {
          return '$first.sol';
        }
      }
      return null;
    } catch (e) {
      debugPrint('[SnsResolver] reverse lookup $address failed: $e');
      return null;
    }
  }

  void clearCache() => _cache.clear();
  void close() => _http.close();
}
