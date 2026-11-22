/// @file        contact_lookup.dart
/// @description Finding an account (design 2026-11-22-friend-graph-off-server §5.5, contract
///              §12.1): by nickname (POST /users/lookup-by-nick) and by snowId (POST
///              /users/resolve — a typed id, a QR, a link). Both answers name the account and its
///              public key; the key is checked to derive the snowId before anything uses it. No id
///              travels in a URL path.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (ResolveResult.rateLimited: the server's 429 on a resolve is told
///              apart from "not found" and from a failure)
///
/// @functions
///  - ContactLookup.byNick(): exact nickname → account (rate limited by the server)
///  - ContactLookup.resolve(): snowId → account, or not found
///  - FoundAccount: an account a lookup returned (snowId, checked account key, name)
///  - NickLookupResult / ResolveResult: what a lookup came to
///
/// Notes:
///  - The server can still answer a nickname with another real account (SC-28): only a link,
///    a QR or the safety number fixes an identity. The add screen shows the short snowId and
///    warns when the name is already another account's in the list.
///  - Nothing here logs a nickname or an account.
library;


import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../crypto/identity_binding.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';

/// An account a lookup returned. [accountPub] derives [snowId] (checked).
class FoundAccount {
  final String snowId;
  final Uint8List accountPub;

  /// The account's display name as the server says it (null when none).
  final String? displayName;

  const FoundAccount({
    required this.snowId,
    required this.accountPub,
    required this.displayName,
  });
}

/// What a nickname lookup came to.
class NickLookupResult {
  /// The account holding the nickname, or null (none, or refused).
  final FoundAccount? account;

  /// The nickname was given up by another account recently (an
  /// impersonation hint for the screen).
  final bool recentlyReassigned;

  /// The server's rate limit was reached (not the same as "no such name").
  final bool rateLimited;

  /// The answer could not be had or was not consistent (no network, a key
  /// that does not derive the snowId).
  final bool failed;

  const NickLookupResult({
    this.account,
    this.recentlyReassigned = false,
    this.rateLimited = false,
    this.failed = false,
  });
}

/// What a resolve came to.
class ResolveResult {
  /// The account, or null.
  final FoundAccount? account;

  /// The server says there is no such (active) account.
  final bool notFound;

  /// The server's rate limit was reached (not the same as "no such account").
  final bool rateLimited;

  /// The answer could not be had or was not consistent.
  final bool failed;

  const ResolveResult({
    this.account,
    this.notFound = false,
    this.rateLimited = false,
    this.failed = false,
  });
}

class ContactLookup {
  final ApiClient _api;
  ContactLookup(this._api);

  /// The account holding exactly [nick].
  Future<NickLookupResult> byNick(String nick) async {
    try {
      final res = await _api.post<dynamic>(
        ApiEndpoints.lookupByNick,
        data: {'nick': nick.trim()},
      );
      final d = res.data;
      if (d is! Map || d['exists'] != true) return const NickLookupResult();
      final account = _account(d['snowchatId'], d['publicKey'], null);
      if (account == null) return const NickLookupResult(failed: true);
      return NickLookupResult(
        account: FoundAccount(
          snowId: account.snowId,
          accountPub: account.accountPub,
          // The name asked for is the name the server matched.
          displayName: nick.trim(),
        ),
        recentlyReassigned: d['recentlyReassigned'] == true,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        return const NickLookupResult(rateLimited: true);
      }
      debugPrint('[ContactLookup] nickname lookup failed: ${e.type.name}');
      return const NickLookupResult(failed: true);
    } catch (e) {
      debugPrint('[ContactLookup] nickname lookup failed: ${e.runtimeType}');
      return const NickLookupResult(failed: true);
    }
  }

  /// The account [snowId] names.
  Future<ResolveResult> resolve(String snowId) async {
    if (!IdentityBindingV1.isValidSnowId(snowId)) {
      return const ResolveResult(notFound: true);
    }
    try {
      final res = await _api.post<dynamic>(
        ApiEndpoints.resolveUser,
        data: {'snowchatId': snowId},
      );
      final d = res.data;
      if (d is! Map) return const ResolveResult(failed: true);
      final name = d['displayName'];
      final account =
          _account(d['snowchatId'], d['publicKey'], name is String ? name : null);
      if (account == null || account.snowId != snowId) {
        return const ResolveResult(failed: true);
      }
      return ResolveResult(account: account);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const ResolveResult(notFound: true);
      }
      if (e.response?.statusCode == 429) {
        return const ResolveResult(rateLimited: true);
      }
      debugPrint('[ContactLookup] resolve failed: ${e.type.name}');
      return const ResolveResult(failed: true);
    } catch (e) {
      debugPrint('[ContactLookup] resolve failed: ${e.runtimeType}');
      return const ResolveResult(failed: true);
    }
  }

  /// The account of an answer, or null when its key does not derive its
  /// snowId (an answer that is not consistent is not used).
  static FoundAccount? _account(Object? snowId, Object? publicKeyHex, String? name) {
    if (snowId is! String || publicKeyHex is! String) return null;
    final key = _unhex(publicKeyHex);
    if (key == null || !IdentityBindingV1.accountKeyMatchesSnowId(key, snowId)) {
      return null;
    }
    return FoundAccount(snowId: snowId, accountPub: key, displayName: name);
  }

  static Uint8List? _unhex(String hex) {
    final h = hex.toLowerCase();
    if (h.length != 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(h)) return null;
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = int.parse(h.substring(2 * i, 2 * i + 2), radix: 16);
    }
    return out;
  }
}
