/// @file        contact_backup_client.dart
/// @description The server's copy of the contact backup, reached with the account's login
///              through the app's API client (GET and PUT /contacts-backup — contract §12.1).
///              The blob is sealed and opened in core/contacts/contact_backup.dart; this file
///              only carries it.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (fetch() also reads blockKeyVersion — the block tag key version the
///              server answers with, so the app learns a rotated key on every start)
///
/// @functions
///  - ContactBackupClient.fetch(): the blob and its tag, or neither, and the block tag key version
///  - ContactBackupClient.store(): replace the blob with a given tag; ContactBackupConflict with
///    the server's tag (top level of the 409 body) when it holds another
///
/// Notes:
///  - No answer at all (no network, a timeout) is ContactBackupUnreachable; an answer that is
///    an error, or not what the route answers, is thrown as it is.
///  - The tag is the server's (base64 of the blob's SHA-256), checked here against the bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:dio/dio.dart';

import '../contacts/contact_backup.dart';
import 'api_client.dart';
import 'api_endpoints.dart';

class ContactBackupClient implements ContactBackupApi {
  final ApiClient _api;
  ContactBackupClient(this._api);

  @override
  Future<ContactBackupBlob> fetch() async {
    final data =
        await _call(() => _api.get<Object?>(ApiEndpoints.contactsBackup));
    if (data is! Map) throw const FormatException('contact backup: answer');
    final blob = data['blob'];
    final etag = data['etag'];
    final version = data['blockKeyVersion'];
    final keyVersion = version is int ? version : null;
    if (blob == null && etag == null) {
      return ContactBackupBlob(null, null, blockKeyVersion: keyVersion);
    }
    if (blob is! String || etag is! String) {
      throw const FormatException('contact backup: answer');
    }
    final bytes = base64Decode(blob);
    if (_tagOf(bytes) != etag) throw const FormatException('contact backup: tag');
    return ContactBackupBlob(bytes, etag, blockKeyVersion: keyVersion);
  }

  @override
  Future<String> store(Uint8List blob, String? ifMatch) async {
    final Object? data;
    try {
      data = await _call(
        () => _api.put<Object?>(
          ApiEndpoints.contactsBackup,
          data: {'blob': base64Encode(blob), 'ifMatch': ifMatch},
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // { error: { code: 'BACKUP_CONFLICT', message }, etag } — the tag is
        // at the top level of the body.
        final body = e.response?.data;
        final etag = body is Map ? body['etag'] : null;
        throw ContactBackupConflict(etag is String ? etag : null);
      }
      rethrow;
    }
    final etag = data is Map ? data['etag'] : null;
    if (etag is! String || etag != _tagOf(blob)) {
      throw const FormatException('contact backup: tag');
    }
    return etag;
  }

  Future<Object?> _call(Future<Response<Object?>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (e) {
      if (e.response == null) throw const ContactBackupUnreachable();
      rethrow;
    }
  }

  static String _tagOf(Uint8List bytes) =>
      base64Encode(hash.sha256.convert(bytes).bytes);
}
