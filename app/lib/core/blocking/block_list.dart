/// @file        block_list.dart
/// @description The accounts this user blocked, as this device holds them (X1). What a blocked
///              account sends is dropped where it arrives — sealed messages and controls, the
///              non-sealed 1:1, call signals, group invites — before anything is stored or shown.
///              The server drops it too (it knows the sender when it relays); this list decides
///              also for what was queued before a block reached the server, and while the server
///              cannot be asked.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - BlockList.isBlocked(): whether an account is blocked (after the stored list is read)
///  - BlockList.block() / unblock(): this user's action — on this device first, then the server
///  - BlockList.sync(): send what the server did not take; take in blocks it holds that this
///    device has no row of (a new install)
///  - BlockList.blocked / changes: the blocked accounts, and when they change
///  - BlockedSenderException: what a decrypt of something a blocked account sent throws
///
/// Notes:
///  - This device's rows are the truth (one device per account): an unblock the server did
///    not take yet is kept as a row and sent again; a block the server lost is sent again.
///    A block the server holds that this device has no row of is taken in on every sync — a
///    new install, a block from before this list existed, a friend ban (the server blocks
///    then). A server that adds accounts could only drop more of what it delivers, which it
///    can do anyway.
///  - The server's block and unblock calls are idempotent; a 404 (the account is gone) settles
///    a row.
///  - Never log the accounts.
library;

import 'dart:async';

import 'package:dio/dio.dart';

import '../crypto/identity_binding.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../storage/daos/block_list_dao.dart';

/// Thrown by a decrypt of something a blocked account sent, once its sender
/// is known (after the decrypt, so the 1:1 session stays in step). Terminal:
/// the message is acknowledged and dropped — never retried, never answered
/// (no retry request, no session reset, no placeholder), nothing stored or
/// shown. Carries nothing: the account is not logged.
class BlockedSenderException implements Exception {
  const BlockedSenderException();

  @override
  String toString() => 'BlockedSenderException';
}

class BlockList {
  final BlockListDao _store;
  final ApiClient _api;
  final int Function() _nowMs;

  BlockList({
    required BlockListDao store,
    required ApiClient api,
    int Function()? nowMs,
  }) : _store = store,
       _api = api,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Set<String> _blocked = {};
  Future<void>? _loading;
  Future<void>? _syncing;
  final StreamController<Set<String>> _changes =
      StreamController<Set<String>>.broadcast();

  /// Read the stored list (once; later calls share it).
  Future<void> load() => _loading ??= () async {
    for (final row in await _store.allRows()) {
      if (row.blocked) _blocked.add(row.snowId);
    }
  }();

  /// Whether [snowId] is blocked. Waits for the stored list the first time:
  /// what arrives right after a start is judged by it too.
  Future<bool> isBlocked(String snowId) async {
    await load();
    return _blocked.contains(snowId);
  }

  /// The blocked accounts as read so far (empty before [load]).
  Set<String> get blocked => Set.unmodifiable(_blocked);

  /// The blocked accounts, each time they change.
  Stream<Set<String>> get changes => _changes.stream;

  /// Block [snowId]: on this device at once, then on the server (which
  /// then drops what it sends). Not reaching the server is not a failure —
  /// [sync] sends it again. Throws ArgumentError for what is not an account.
  Future<void> block(String snowId) => _set(snowId, true);

  /// Unblock [snowId] (what it sent meanwhile does not come back).
  Future<void> unblock(String snowId) => _set(snowId, false);

  Future<void> _set(String snowId, bool blocked) async {
    if (!IdentityBindingV1.isValidSnowId(snowId)) {
      throw ArgumentError('block list: not an account');
    }
    await load();
    final at = _nowMs();
    await _store.setBlocked(snowId, blocked, at);
    final changed = blocked ? _blocked.add(snowId) : _blocked.remove(snowId);
    if (changed) _emit();
    await _send(snowId, blocked, at);
  }

  /// Bring the server and this device in step: what this device changed
  /// and the server did not take is sent again, a block the server lost is
  /// sent again, and blocks the server holds that this device has no row of
  /// are taken in. Concurrent calls share one run. Never throws.
  Future<void> sync() =>
      _syncing ??= _sync().whenComplete(() => _syncing = null);

  Future<void> _sync() async {
    try {
      await load();
      final response = await _api.get<dynamic>(ApiEndpoints.blockedUsers);
      final data = response.data;
      final list = data is Map ? data['blockedUsers'] : null;
      if (list is! List) return;
      final onServer = <String>{
        for (final entry in list)
          if (entry is Map &&
              entry['snowchatId'] is String &&
              IdentityBindingV1.isValidSnowId(entry['snowchatId'] as String))
            entry['snowchatId'] as String,
      };
      final taken = await _store.adoptServerBlocks(onServer.toList(), _nowMs());
      if (taken.isNotEmpty) {
        _blocked.addAll(taken);
        _emit();
      }
      for (final row in await _store.allRows()) {
        final lost = row.blocked && row.synced && !onServer.contains(row.snowId);
        if (!row.synced || lost) {
          await _send(row.snowId, row.blocked, row.updatedAtMs);
        }
      }
    } catch (_) {
      // No server now: the next sync (on connect) tries again.
    }
  }

  /// Tell the server what the row of [snowId] says (at [at]). Returns
  /// whether it took it. Never throws.
  Future<bool> _send(String snowId, bool blocked, int at) async {
    try {
      if (blocked) {
        await _api.post<dynamic>(
          ApiEndpoints.blockUser,
          data: {'snowchatId': snowId},
        );
      } else {
        await _api.delete<dynamic>(ApiEndpoints.unblockUser(snowId));
      }
    } on DioException catch (e) {
      // The account is gone: there is nothing for the server to hold.
      if (e.response?.statusCode != 404) return false;
    } catch (_) {
      return false;
    }
    try {
      await _store.markSynced(snowId, at);
    } catch (_) {
      return false; // sent again by the next sync (idempotent)
    }
    return true;
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(Set.unmodifiable(_blocked));
  }

  void dispose() => unawaited(_changes.close());
}
