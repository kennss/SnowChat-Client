/// @file        block_list_test.dart
/// @description BlockList (X1): a block or unblock is on this device at once and sent to the
///              server; one the server did not take is sent again by sync(); a new install takes
///              the server's list; an unblock not yet taken is never overridden by it.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - main(): the test cases.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/blocking/block_list.dart';
import 'package:snowchat/core/network/api_client.dart';
import 'package:snowchat/core/storage/database.dart';

const _a = 'snow0000000000000000000000000000000a';
const _b = 'snow0000000000000000000000000000000b';

class _Api extends Fake implements ApiClient {
  bool offline = false;
  final Set<String> server = {};
  final List<String> calls = [];

  DioException _down(String path) => DioException(
    requestOptions: RequestOptions(path: path),
    type: DioExceptionType.connectionError,
  );

  @override
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) async {
    if (offline) throw _down(path);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {
        'blockedUsers': [for (final id in server) {'snowchatId': id}],
      } as T,
    );
  }

  @override
  Future<Response<T>> post<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options}) async {
    calls.add('block');
    if (offline) throw _down(path);
    server.add((data as Map)['snowchatId'] as String);
    return Response<T>(requestOptions: RequestOptions(path: path), statusCode: 200);
  }

  @override
  Future<Response<T>> delete<T>(String path) async {
    calls.add('unblock');
    if (offline) throw _down(path);
    server.remove(path.split('/').last);
    return Response<T>(requestOptions: RequestOptions(path: path), statusCode: 200);
  }
}

void main() {
  late SnowDatabase db;
  late _Api api;
  late BlockList list;

  setUp(() {
    db = SnowDatabase(NativeDatabase.memory());
    api = _Api();
    list = BlockList(store: db.blockListDao, api: api);
  });
  tearDown(() => db.close());

  test('a block is on this device at once and on the server', () async {
    await list.block(_a);
    expect(await list.isBlocked(_a), isTrue);
    expect(api.server, {_a});
    expect((await db.blockListDao.allRows()).single.synced, isTrue);
    expect(() => list.block('not an account'), throwsArgumentError);
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

  test('an unblock the server did not take is kept and never overridden by '
      'its list; it goes once taken', () async {
    await list.block(_a);
    api.offline = true;
    await list.unblock(_a);
    expect(await list.isBlocked(_a), isFalse);
    api.offline = false;
    await list.sync(); // the server still lists _a
    expect(await list.isBlocked(_a), isFalse);
    expect(api.server, isEmpty);
    expect(await db.blockListDao.allRows(), isEmpty);
  });

  test('a new install takes the server\'s list; a block the server lost is '
      'sent again', () async {
    api.server.add(_b);
    await list.sync();
    expect(await list.isBlocked(_b), isTrue);
    api.server.clear(); // the server lost it
    await list.sync();
    expect(api.server, {_b});
  });
}
