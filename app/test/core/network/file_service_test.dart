/// @file        file_service_test.dart
/// @description The file download goes to POST /files/fetch with the fileId in
///              the JSON body — no fileId in the URL path (an access log keeps
///              the path next to the client address) — and returns the bytes
///              the server sent; an empty answer is an error.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - main(): the request shape, the bytes, an empty answer.
///  - _Adapter: a Dio adapter that records the request and answers bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/network/api_client.dart';
import 'package:snowchat/core/network/file_service.dart';

class _Adapter implements HttpClientAdapter {
  final List<int> answer;
  RequestOptions? seen;
  String? body;
  _Adapter(this.answer);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen = options;
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      body = utf8.decode(chunks.expand((c) => c).toList());
    }
    return ResponseBody.fromBytes(answer, 200, headers: {
      Headers.contentTypeHeader: ['application/octet-stream'],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Api extends Fake implements ApiClient {
  final Dio _dio;
  _Api(this._dio);

  @override
  Dio get dio => _dio;
}

void main() {
  const fileId = '6f1c2a4e-9b7d-4c3e-8a21-0d5e7f9b1c33';

  FileService serviceWith(_Adapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://server.test/api/v2'))
      ..httpClientAdapter = adapter;
    return FileService(apiClient: _Api(dio));
  }

  test('download is POST /files/fetch with the fileId in the body', () async {
    final blob = List<int>.generate(300, (i) => i % 256);
    final adapter = _Adapter(blob);
    final bytes = await serviceWith(adapter).downloadEncryptedFile(fileId);

    expect(adapter.seen!.method, 'POST');
    expect(adapter.seen!.uri.path, '/api/v2/files/fetch');
    expect(adapter.seen!.uri.toString().contains(fileId), isFalse,
        reason: 'the fileId must not be in the URL');
    expect(jsonDecode(adapter.body!), {'fileId': fileId});
    expect(bytes, Uint8List.fromList(blob));
  });

  test('an empty answer is an error', () async {
    final adapter = _Adapter(const []);
    await expectLater(
      serviceWith(adapter).downloadEncryptedFile(fileId),
      throwsA(isA<StateError>()),
    );
  });
}
