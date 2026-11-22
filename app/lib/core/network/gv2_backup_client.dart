/// @file        gv2_backup_client.dart
/// @description Group protocol v2 — the server's copy of the group key
///              backup, reached with the account's login through the app's
///              API client (GET and PUT /gv2-account/backup). The blob is
///              sealed and opened in core/group_v2/gv2_backup.dart; this
///              file only carries it.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-19
/// @lastUpdated 2026-11-20
///
/// @functions
///  - Gv2BackupClient.fetch(): the blob and its tag, or neither
///  - Gv2BackupClient.store(): replace the blob with a given tag; null when
///    the server holds another
///
/// Notes:
///  - No answer at all (no network, a timeout) is Gv2BackupUnreachable; an
///    answer that is an error, or not what the route answers, is thrown as
///    it is — the caller then waits before it asks again.
///  - The tag is the server's (base64 of the blob's SHA-256). It is checked
///    here against the bytes: a write is only recorded under the tag of
///    what was written.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:dio/dio.dart';

import '../group_v2/gv2_backup.dart';
import 'api_client.dart';
import 'api_endpoints.dart';

class Gv2BackupClient implements Gv2BackupApi {
  final ApiClient _api;
  Gv2BackupClient(this._api);

  @override
  Future<Gv2BackupBlob> fetch() async {
    final data = await _call(() => _api.get<Object?>(ApiEndpoints.gv2Backup));
    if (data is! Map) throw const FormatException('gv2 backup: answer');
    final blob = data['blob'];
    final etag = data['etag'];
    if (blob == null && etag == null) return const Gv2BackupBlob(null, null);
    if (blob is! String || etag is! String) {
      throw const FormatException('gv2 backup: answer');
    }
    final bytes = base64Decode(blob);
    if (_tagOf(bytes) != etag) throw const FormatException('gv2 backup: tag');
    return Gv2BackupBlob(bytes, etag);
  }

  @override
  Future<String?> store(Uint8List blob, String? ifMatch) async {
    final Object? data;
    try {
      data = await _call(
        () => _api.put<Object?>(
          ApiEndpoints.gv2Backup,
          data: {'blob': base64Encode(blob), 'ifMatch': ifMatch},
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) return null;
      rethrow;
    }
    final etag = data is Map ? data['etag'] : null;
    if (etag is! String || etag != _tagOf(blob)) {
      throw const FormatException('gv2 backup: tag');
    }
    return etag;
  }

  Future<Object?> _call(Future<Response<Object?>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (e) {
      if (e.response == null) throw const Gv2BackupUnreachable();
      rethrow;
    }
  }

  static String _tagOf(Uint8List bytes) =>
      base64Encode(hash.sha256.convert(bytes).bytes);
}
