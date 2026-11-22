/// @file        block_list_test.dart
/// @description BlockList (X1, design 2026-11-22 §5.9): this device's list is the source of
///              truth. A block or unblock is on this device at once and sent to the server (POST
///              /users/block | /users/unblock, the id in the body), with the account's name kept;
///              one the server did not take is sent again by sync(); the server's list is never
///              read or adopted; replaceOnServer() makes the server's tags exactly the device's
///              blocked accounts (never this account itself) and settles the rows; the backup's
///              blocks merge in without overriding a row of this device; the server's tag key
///              version of every answer is reported; this account itself cannot be blocked; a 400
///              or 404 settles a row. Review fixes: the server calls run one at a time — a block
///              made while a replace runs reaches the server after it, so the replace cannot wipe
///              it; at most 5,000 blocked accounts (BlockLimitReached; a restore takes in up to the
///              cap).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-22 (server calls one at a time; the 5,000 cap). Earlier 2026-11-22 (device
///              list as the source of truth: no server list adoption; unblock in
///              the body; replaceOnServer; mergeRestored; keyVersion; names; this account itself).
///              Earlier 2026-11-21
///
/// @functions
///  - main(): the test cases.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/blocking/block_list.dart';
import 'package:snowchat/core/network/api_client.dart';
import 'package:snowchat/core/network/api_endpoints.dart';
import 'package:snowchat/core/storage/database.dart';

const _a = 'snow0000000000000000000000000000000a';
const _b = 'snow0000000000000000000000000000000b';
const _me = 'snow000000000000000000000000000000ee';

class _Api extends Fake implements ApiClient {
  bool offline = false;
  int? status;
  int keyVersion = 1;
  final Set<String> server = {};
  final List<(String, Object?)> calls = [];

  /// When set, a replace waits for it after it was received (its list is
  /// taken when it completes).
  Completer<void>? replaceGate;

  DioException _down(String path) => DioException(
    requestOptions: RequestOptions(path: path),
    type: DioExceptionType.connectionError,
  );

  @override
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) =>
      throw StateError('the device never reads a server block list');

  @override
  Future<Response<T>> post<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options}) async {
    calls.add((path, data));
    if (offline) throw _down(path);
    final s = status;
    if (s != null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(requestOptions: RequestOptions(path: path), statusCode: s),
      );
    }
    final body = data as Map;
    if (path == ApiEndpoints.blocksReplace) await replaceGate?.future;
    if (path == ApiEndpoints.blockUser) server.add(body['snowchatId'] as String);
    if (path == ApiEndpoints.unblockUser) server.remove(body['snowchatId']);
    if (path == ApiEndpoints.blocksReplace) {
      server
        ..clear()
        ..addAll((body['snowchatIds'] as List).cast<String>());
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'ok': true, 'keyVersion': keyVersion} as T,
    );
  }
}

void main() {
  late SnowDatabase db;
  late _Api api;
  late BlockList list;
  late List<int> versions;

  setUp(() {
    db = SnowDatabase(NativeDatabase.memory());
    api = _Api();
    versions = [];
    list = BlockList(store: db.blockListDao, api: api, mySnowId: () => _me)
      ..onKeyVersion = versions.add;
  });
  tearDown(() => db.close());

  test('a block is on this device at once and on the server, with its name; '
      'the id travels in the body', () async {
    var changes = 0;
    list.onUserChange = () => changes++;
    await list.block(_a, nickname: 'alice');
    expect(await list.isBlocked(_a), isTrue);
    expect(api.server, {_a});
    expect(api.calls.single.$1, ApiEndpoints.blockUser);
    expect(api.calls.single.$2, {'snowchatId': _a});
    final row = (await db.blockListDao.allRows()).single;
    expect(row.synced, isTrue);
    expect(row.nickname, 'alice');
    expect(await list.blockedWithNames(), {_a: 'alice'});
    expect(changes, 1, reason: 'the backup is written at once');
    expect(versions, [1]);
    expect(() => list.block('not an account'), throwsArgumentError);
    expect(() => list.block(_me), throwsArgumentError);
  });

  test('offline: blocked here at once, sent again by sync', () async {
    api.offline = true;
    await list.block(_a);
    expect(await list.isBlocked(_a), isTrue);
    expect(api.server, isEmpty);
    api.offline = false;
    await list.sync();
    expect(api.server, {_a});
  });

  test('an unblock goes in the body; one the server did not take is sent '
      'again, and the row goes once taken', () async {
    await list.block(_a);
    api.offline = true;
    await list.unblock(_a);
    expect(await list.isBlocked(_a), isFalse);
    api.offline = false;
    await list.sync();
    expect(api.calls.last.$1, ApiEndpoints.unblockUser);
    expect(api.calls.last.$2, {'snowchatId': _a});
    expect(api.server, isEmpty);
    expect(await db.blockListDao.allRows(), isEmpty);
  });

  test('the server\'s list is never adopted: a tag only the server has stays '
      'until replace removes it', () async {
    api.server.add(_b);
    await list.sync();
    expect(await list.isBlocked(_b), isFalse);
    await list.block(_a);
    expect(await list.replaceOnServer(), isTrue);
    expect(api.server, {_a});
  });

  test('replace: exactly the blocked rows, never this account; rows settled; '
      'an unblock row goes', () async {
    api.offline = true;
    await list.block(_a);
    await list.block(_b);
    await list.unblock(_b);
    api.offline = false;
    await db.blockListDao.setBlocked(_me, true, 1); // a row that must not leave
    expect(await list.replaceOnServer(), isTrue);
    final sent = api.calls.last;
    expect(sent.$1, ApiEndpoints.blocksReplace);
    expect(sent.$2, {'snowchatIds': [_a]});
    final rows = {for (final r in await db.blockListDao.allRows()) r.snowId: r};
    expect(rows[_a]!.synced, isTrue);
    expect(rows.containsKey(_b), isFalse);
    expect(versions.last, 1);

    api.offline = true;
    expect(await list.replaceOnServer(), isFalse);
  });

  test('restored blocks merge in; a row of this device is kept', () async {
    api.offline = true;
    await list.unblock(_a); // an unblock this device made
    api.offline = false;
    await list.mergeRestored({_a: 'alice', _b: 'bob'});
    expect(await list.isBlocked(_a), isFalse);
    expect(await list.isBlocked(_b), isTrue);
    expect(await list.blockedWithNames(), {_b: 'bob'});
  });

  test('a 400 or a 404 settles the row (nothing to send again)', () async {
    api.status = 400;
    await list.block(_a);
    expect((await db.blockListDao.allRows()).single.synced, isTrue);
    api.status = 404;
    await list.block(_b);
    expect(
        (await db.blockListDao.allRows()).firstWhere((r) => r.snowId == _b).synced,
        isTrue);
  });

  test('a block made while a replace runs reaches the server after it — the '
      'replace cannot wipe it', () async {
    await list.block(_a);
    api.calls.clear();
    api.replaceGate = Completer<void>();
    final replace = list.replaceOnServer();
    await pumpEventQueue();
    final block = list.block(_b);
    await pumpEventQueue();
    expect(await list.isBlocked(_b), isTrue, reason: 'on this device at once');
    expect(api.calls.map((c) => c.$1), [ApiEndpoints.blocksReplace],
        reason: 'the block waits for the replace');
    api.replaceGate!.complete();
    expect(await replace, isTrue);
    await block;
    expect(api.calls.map((c) => c.$1),
        [ApiEndpoints.blocksReplace, ApiEndpoints.blockUser]);
    expect(api.server, {_a, _b});
    expect((await db.blockListDao.allRows()).every((r) => r.synced), isTrue);
  });

  test('at most 5,000 blocked accounts: one more is refused; blocking one '
      'again is not; a restore takes in up to the cap', () async {
    // Far from _a / _b (they are ids 10 and 11).
    String id(int i) => 'snow${(i + 0x10000).toRadixString(16).padLeft(32, '0')}';
    await db.batch((b) {
      for (var i = 0; i < BlockList.maxBlocked; i++) {
        b.insert(
          db.blockedAccounts,
          BlockedAccountsCompanion.insert(
            snowId: id(i),
            blocked: true,
            synced: const Value(true),
            updatedAtMs: 1,
          ),
        );
      }
    });
    final full = BlockList(store: db.blockListDao, api: api, mySnowId: () => _me);
    expect(await full.canBlock(_a), isFalse);
    expect(await full.canBlock(id(3)), isTrue);
    await expectLater(full.block(_a), throwsA(isA<BlockLimitReached>()));
    expect(await full.isBlocked(_a), isFalse);
    expect(api.calls, isEmpty);
    await full.block(id(3));
    await full.mergeRestored({_a: null, _b: null});
    expect(await full.isBlocked(_a), isFalse);
    await full.unblock(id(0));
    await full.mergeRestored({_a: null, _b: null});
    expect((await full.blockedWithNames()).length, BlockList.maxBlocked);
  });
}
