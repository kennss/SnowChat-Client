/// @file        file_service.dart
/// @description Encrypted file upload/download service. Handles encrypted blob transfer with the server.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - FileService: encrypted file upload/download service class
///  - FileService.uploadEncryptedFile(): upload encrypted file blob to server
///  - FileService.downloadEncryptedFile(): download encrypted file blob from server

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_endpoints.dart';

/// Service for uploading and downloading encrypted file blobs.
///
/// The server stores encrypted blobs as-is with no knowledge of file
/// contents, names, types, or encryption keys. Only authenticated users
/// can upload or download files.
class FileService {
  final ApiClient _apiClient;

  FileService({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Upload an encrypted file blob to the server.
  ///
  /// [encryptedData] — the encrypted file bytes (nonce + ciphertext + tag).
  /// [contentHash] — SHA-256 hex hash of [encryptedData] for integrity.
  ///
  /// Server endpoint: POST /api/v2/files/upload
  /// Server expects: raw binary body + x-content-hash header.
  /// Server returns: { fileId: string, size: int }
  ///
  /// Returns the server-assigned file ID.
  Future<String> uploadEncryptedFile(
    Uint8List encryptedData,
    String contentHash, {
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        ApiEndpoints.uploadFile,
        data: Stream.fromIterable([encryptedData]),
        options: Options(
          headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Length': encryptedData.length.toString(),
            'x-content-hash': contentHash,
          },
        ),
        onSendProgress: onProgress != null
            ? (sent, total) => onProgress(sent, total)
            : null,
      );

      final fileId = response.data?['fileId'] as String?;
      if (fileId == null) {
        throw StateError('Server did not return a fileId');
      }

      debugPrint(
        '[FileService] Uploaded encrypted file: $fileId '
        '(${encryptedData.length} bytes)',
      );

      return fileId;
    } catch (e) {
      debugPrint('[FileService] Upload failed: $e');
      rethrow;
    }
  }

  /// Download an encrypted file blob from the server.
  ///
  /// [fileId] — the server-assigned file ID.
  ///
  /// Server endpoint: GET /api/v2/files/:fileId
  /// Server returns: raw binary (application/octet-stream).
  ///
  /// Returns the encrypted file bytes.
  Future<Uint8List> downloadEncryptedFile(String fileId) async {
    try {
      final response = await _apiClient.dio.get<List<int>>(
        ApiEndpoints.downloadFile(fileId),
        options: Options(responseType: ResponseType.bytes),
      );

      final data = response.data;
      if (data == null || data.isEmpty) {
        throw StateError('Server returned empty file data');
      }

      final bytes = Uint8List.fromList(data);
      debugPrint(
        '[FileService] Downloaded encrypted file: $fileId '
        '(${bytes.length} bytes)',
      );

      return bytes;
    } catch (e) {
      debugPrint('[FileService] Download failed: $e');
      rethrow;
    }
  }
}
