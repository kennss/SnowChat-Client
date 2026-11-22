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
/// @lastUpdated 2026-11-22 (review fixes: the server calls — a block, an unblock, the resend of a
///              sync, the replace — run one at a time, so a replace can never wipe a block made while
///              it ran; at most maxBlocked (5,000 — the server's cap for a replace and for one owner)
///              accounts: one more is refused with BlockLimitReached, and a restore takes in blocks up
///              to the cap). Earlier 2026-11-22 (design 2026-11-22-friend-graph-off-server §5.9: this device's list is
///              the source of truth — the server holds only tags it cannot read without its key,
///              and the app never adopts a server list (GET /users/blocked is gone); unblock is
///              POST /users/unblock; replaceOnServer() — POST /users/blocks/replace — makes the
///              server's tags exactly this device's list (first launch, after a backup restore);
///              a block keeps the account's name; mergeRestored() for the contact backup;
///              onUserChange — a block / unblock is written to the backup at once; onKeyVersion —
///              the server's tag key version from every answer (a change replaces the tags once);
///              this account itself is never blocked nor sent in a replace list; a 400 settles a row
///              like a 404). Earlier 2026-11-21
///
/// @functions
///  - BlockList.isBlocked(): whether an account is blocked (after the stored list is read)
///  - BlockList.block() / unblock(): this user's action — on this device first, then the server
///  - BlockList.canBlock(): whether one more account can be blocked (the cap)
///  - BlockList.sync(): send again what the server did not take
///  - BlockList.replaceOnServer(): the server's tags become exactly this device's list
///  - BlockList.mergeRestored(): blocks of the contact backup this device has no row of
///  - BlockList.blockedWithNames(): the blocked accounts with their names (backup, screen)
///  - BlockList.blocked / changes: the blocked accounts, and when they change
///  - BlockedSenderException: what a decrypt of something a blocked account sent throws
///  - BlockLimitReached: the list holds maxBlocked accounts already
///
/// Notes:
///  - This device's rows are the truth (one device per account): an unblock the server did
///    not take yet is kept as a row and sent again; a block the server did not take is sent
///    again. The server's tags only follow: replaced as a whole at first launch and after a
///    restore, otherwise changed one by one. A tag the server has that this device does not
///    would be a block the user can neither see nor lift — replace removes it.
///  - The server's block, unblock and replace calls are idempotent; a 404 (the account is
///    gone) settles a row. They go one at a time (a single queue): a block sent while a replace
///    runs reaches the server after it.
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

/// Thrown by [BlockList.block] when the list already holds
/// [BlockList.maxBlocked] accounts (the server takes no more for one owner).
class BlockLimitReached implements Exception {
  const BlockLimitReached();

  @override
  String toString() => 'BlockLimitReached';
}

class BlockList {
  /// The most accounts one user can block (the server's cap — contract
  /// §12.1 — for a replace and for one owner's tags).
  static const int maxBlocked = 5000;

  final BlockListDao _store;
  final ApiClient _api;
  final int Function() _nowMs;

  BlockList({
    required BlockListDao store,
    required ApiClient api,
    String Function()? mySnowId,
    int Function()? nowMs,
  }) : _store = store,
       _api = api,
       _me = mySnowId,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// This account (never blocked, never in a replace list).
  final String Function()? _me;

  /// Called after this user blocked or unblocked an account (wired to the
  /// contact backup's immediate write).
  void Function()? onUserChange;

  /// Called with the server's block tag key version from each block /
  /// unblock / replace answer (wired to ContactBackup.noteBlockKeyVersion).
  void Function(int keyVersion)? onKeyVersion;

  final Set<String> _blocked = {};
  Future<void>? _loading;
  Future<void>? _syncing;

  /// The server calls, one after another.
  Future<void> _serverTail = Future<void>.value();

  Future<T> _serverSerial<T>(Future<T> Function() call) {
    final result = _serverTail.then((_) => call());
    _serverTail = result.then((_) {}, onError: (_) {});
    return result;
  }
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
  /// then drops what it sends). [nickname] — the name the account had here —
  /// is kept for the blocked-list screen. Not reaching the server is not a
  /// failure — [sync] sends it again. Throws ArgumentError for what is not
  /// an account, [BlockLimitReached] when [maxBlocked] accounts are blocked
  /// already.
  Future<void> block(String snowId, {String? nickname}) =>
      _set(snowId, true, nickname: nickname);

  /// Whether [snowId] can be blocked now: it is blocked already, or the
  /// list holds fewer than [maxBlocked] accounts.
  Future<bool> canBlock(String snowId) async {
    await load();
    return _blocked.contains(snowId) || _blocked.length < maxBlocked;
  }

  /// Unblock [snowId] (what it sent meanwhile does not come back).
  Future<void> unblock(String snowId) => _set(snowId, false);

  Future<void> _set(String snowId, bool blocked, {String? nickname}) async {
    if (!IdentityBindingV1.isValidSnowId(snowId)) {
      throw ArgumentError('block list: not an account');
    }
    if (snowId == _me?.call()) {
      throw ArgumentError('block list: this account itself');
    }
    await load();
    if (blocked && !_blocked.contains(snowId) && _blocked.length >= maxBlocked) {
      throw const BlockLimitReached();
    }
    final at = _nowMs();
    await _store.setBlocked(snowId, blocked, at, nickname: nickname);
    final changed = blocked ? _blocked.add(snowId) : _blocked.remove(snowId);
    if (changed) _emit();
    onUserChange?.call();
    await _serverSerial(() => _send(snowId, blocked, at));
  }

  /// Send again what this device changed and the server did not take.
  /// Concurrent calls share one run. Never throws.
  Future<void> sync() =>
      _syncing ??= _sync().whenComplete(() => _syncing = null);

  Future<void> _sync() => _serverSerial(() async {
        try {
          await load();
          for (final row in await _store.allRows()) {
            if (!row.synced) {
              await _send(row.snowId, row.blocked, row.updatedAtMs);
            }
          }
        } catch (_) {
          // No server now: the next sync (on connect) tries again.
        }
      });

  /// Make the server's tags exactly this device's blocked accounts (POST
  /// /users/blocks/replace). Returns whether the server took it; never
  /// throws.
  Future<bool> replaceOnServer() => _serverSerial(_replace);

  Future<bool> _replace() async {
    try {
      await load();
      final snapshot = _nowMs();
      final me = _me?.call();
      final ids = [
        for (final row in await _store.allRows())
          if (row.blocked &&
              row.snowId != me &&
              IdentityBindingV1.isValidSnowId(row.snowId))
            row.snowId,
      ];
      final response = await _api.post<dynamic>(
        ApiEndpoints.blocksReplace,
        data: {'snowchatIds': ids},
      );
      await _store.markAllSynced(snapshot);
      _noteKeyVersion(response.data);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Blocks of the contact backup ([blocks]: snowId → nickname) this
  /// device has no row of are taken in (the server's tags are replaced
  /// afterwards — ContactBackup).
  Future<void> mergeRestored(Map<String, String?> blocks) async {
    await load();
    final room = maxBlocked - _blocked.length;
    if (room <= 0) return;
    final taken = await _store.mergeRestored(blocks, _nowMs(), limit: room);
    if (taken.isNotEmpty) {
      _blocked.addAll(taken);
      _emit();
    }
  }

  /// The blocked accounts with the names kept with them (snowId →
  /// nickname).
  Future<Map<String, String?>> blockedWithNames() async {
    await load();
    return {
      for (final row in await _store.allRows())
        if (row.blocked) row.snowId: row.nickname,
    };
  }

  /// Tell the server what the row of [snowId] says (at [at]). Returns
  /// whether it took it. Never throws.
  Future<bool> _send(String snowId, bool blocked, int at) async {
    try {
      final response = await _api.post<dynamic>(
        blocked ? ApiEndpoints.blockUser : ApiEndpoints.unblockUser,
        data: {'snowchatId': snowId},
      );
      _noteKeyVersion(response.data);
    } on DioException catch (e) {
      // The account is gone (404) or the server will never take this row
      // (400): there is nothing for the server to hold — settled.
      final status = e.response?.statusCode;
      if (status != 404 && status != 400) return false;
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

  void _noteKeyVersion(Object? data) {
    final version = data is Map ? data['keyVersion'] : null;
    if (version is int) onKeyVersion?.call(version);
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(Set.unmodifiable(_blocked));
  }

  void dispose() => unawaited(_changes.close());
}
