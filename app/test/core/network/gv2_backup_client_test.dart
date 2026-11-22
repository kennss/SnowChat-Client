/// @file        gv2_backup_client_test.dart
/// @description The group key backup over the app's API client: what the
///              two calls send, how the server's answers are read, and how
///              "no answer", "another blob is stored" and an answer that is
///              not the route's are told apart.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-20
///
/// @functions
///  - main(): fetch, store, failures.
///
/// Notes:
///  - The API client is a stand-in that keeps one blob and answers like
///    the server's route (server/src/routes/gv2Account.ts).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/group_v2/gv2_backup.dart';
import 'package:snowchat/core/network/api_client.dart';
import 'package:snowchat/core/network/gv2_backup_client.dart';

String _tag(List<int> bytes) => base64Encode(hash.sha256.convert(bytes).bytes);

class _Api extends Fake implements ApiClient {
  Uint8List? blob;
  final List<String> calls = [];
  Object? lastBody;

  /// Answers instead of the route's, one per request.
  final List<Object? Function(RequestOptions)> scripted = [];

  Response<T> _ok<T>(RequestOptions r, Object? data) =>
      Response<T>(requestOptions: r, statusCode: 200, data: data as T?);

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add('GET $path');
    final r = RequestOptions(path: path);
    if (scripted.isNotEmpty) return _ok<T>(r, scripted.removeAt(0)(r));
    final held = blob;
    return _ok<T>(r, {
      'blob': held == null ? null : base64Encode(held),
      'etag': held == null ? null : _tag(held),
    });
  }

  @override
  Future<Response<T>> put<T>(String path, {dynamic data}) async {
    calls.add('PUT $path');
    lastBody = data;
    final r = RequestOptions(path: path);
    if (scripted.isNotEmpty) return _ok<T>(r, scripted.removeAt(0)(r));
    final body = data as Map;
    final held = blob;
    if ((held == null ? null : _tag(held)) != body['ifMatch']) {
      throw DioException(
        requestOptions: r,
        response: Response(
          requestOptions: r,
          statusCode: 409,
          data: {
            'error': {'code': 'BACKUP_CONFLICT'},
          },
        ),
      );
    }
    blob = base64Decode(body['blob'] as String);
    return _ok<T>(r, {'etag': _tag(blob!)});
  }
}

Never _status(RequestOptions r, int status) => throw DioException(
  requestOptions: r,
  response: Response(requestOptions: r, statusCode: status),
);

void main() {
  late _Api api;
  late Gv2BackupClient client;
  final one = Uint8List.fromList(List.generate(300, (i) => i % 251));
  final two = Uint8List.fromList(List.generate(300, (i) => (i * 7) % 251));

  setUp(() {
    api = _Api();
    client = Gv2BackupClient(api);
  });

  test('no blob yet; then what was stored comes back with its tag', () async {
    final none = await client.fetch();
    expect(none.blob, isNull);
    expect(none.etag, isNull);

    final etag = await client.store(one, null);
    expect(etag, _tag(one));
    expect(api.calls, ['GET /gv2-account/backup', 'PUT /gv2-account/backup']);
    expect(api.lastBody, {'blob': base64Encode(one), 'ifMatch': null});

    final held = await client.fetch();
    expect(held.blob, one);
    expect(held.etag, etag);
  });

  test('a write names the blob it replaces; when the server holds another '
      'the answer is null and nothing is replaced', () async {
    final first = await client.store(one, null);
    expect(await client.store(two, null), isNull);
    expect(await client.store(two, _tag(two)), isNull);
    expect(api.blob, one);
    expect(await client.store(two, first), _tag(two));
    expect(api.lastBody, {'blob': base64Encode(two), 'ifMatch': first});
    expect(api.blob, two);
  });

  test('no answer at all is "unreachable"; an error the server answered '
      'with is not', () async {
    for (final call in [client.fetch, () => client.store(one, null)]) {
      api.scripted.add(
        (r) => throw DioException(
          requestOptions: r,
          type: DioExceptionType.connectionTimeout,
        ),
      );
      await expectLater(call(), throwsA(isA<Gv2BackupUnreachable>()));
      for (final status in [401, 429, 500]) {
        api.scripted.add((r) => _status(r, status));
        await expectLater(
          call(),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'status',
              status,
            ),
          ),
        );
      }
    }
    // A conflict is an answer of the write only.
    api.scripted.add((r) => _status(r, 409));
    await expectLater(client.fetch(), throwsA(isA<DioException>()));
  });

  test('an answer that is not the route\'s is refused', () async {
    final answers = <Object?>[
      null,
      'text',
      {'blob': base64Encode(one)}, // no tag
      {'etag': _tag(one)}, // no blob
      {'blob': 7, 'etag': _tag(one)},
      {'blob': base64Encode(one), 'etag': _tag(two)}, // not this blob's tag
      {'blob': '!!', 'etag': _tag(one)},
    ];
    for (final answer in answers) {
      api.scripted.add((_) => answer);
      await expectLater(
        client.fetch(),
        throwsA(isA<FormatException>()),
        reason: '$answer',
      );
    }
    // A write is recorded only under the tag of what was written.
    for (final answer in <Object?>[
      null,
      {'etag': 5},
      {'etag': _tag(two)},
      const <String, Object?>{},
    ]) {
      api.scripted.add((_) => answer);
      await expectLater(
        client.store(one, null),
        throwsA(isA<FormatException>()),
        reason: '$answer',
      );
    }
  });
}
