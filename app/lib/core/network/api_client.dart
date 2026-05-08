/// @file        api_client.dart
/// @description Dio-based HTTP client. Handles REST communication with the SnowChat API server.
///              Phase 11 (2026-05-03): integrates TokenManager SSoT. Every
///              request is preceded by `tokenManager.ensureFresh(reason:
///              'pre-flight')` so the Authorization header always carries a
///              JWT with > 5 min remaining TTL. 401 responses trigger one
///              follow-up `ensureFresh(reason: 'on-401')` + a single retry
///              with the rotated bearer. Hard refresh failure (3× retries
///              exhausted inside TokenManager) propagates as the original
///              DioException.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-05-03 (Phase 11 — onTokenRefresh callback removed; pre-flight + 401 retry both go through TokenManager.ensureFresh)
///
/// @functions
///  - ApiClient: Dio-based HTTP client class with TokenManager integration
///  - ApiClient.tokenProvider: callback supplying the current TokenManager instance
///  - ApiClient.get(): GET request
///  - ApiClient.post(): POST request
///  - ApiClient.postRaw(): raw binary POST request (file upload)
///  - ApiClient.put(): PUT request
///  - ApiClient.patch(): PATCH request
///  - ApiClient.delete(): DELETE request
///  - ApiClient.upload(): multipart file upload

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_endpoints.dart';
import 'token_manager.dart';

/// Dio-based HTTP client for SnowChat API.
class ApiClient {
  late final Dio _dio;

  /// Phase 11: callback that returns the current TokenManager. Wired by
  /// `apiClientProvider` in `providers.dart`. Must be set before the first
  /// authenticated request, otherwise the request goes out without a bearer.
  TokenManager Function()? tokenProvider;

  /// Endpoints exempt from the pre-flight ensureFresh gate. The /auth/refresh
  /// route in particular MUST not recurse through ensureFresh — it would
  /// deadlock on the same `_inflight` mutex. /auth/challenge and /auth/verify
  /// run pre-authentication (no token to refresh).
  static const Set<String> _authExemptPaths = {
    '/auth/register',
    '/auth/challenge',
    '/auth/verify',
    '/auth/refresh',
    '/auth/server-key',
  };

  ApiClient({String? baseUrl}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? ApiEndpoints.getBaseUrl(),
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Logging interceptor (debug only)
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) {
        // ignore: avoid_print
        print('[API] $obj');
      },
    ));

    // Phase 11: pre-flight + 401 retry, both via TokenManager.ensureFresh.
    // The interceptor uses `extra['_retried']` to clamp retries to a single
    // attempt — TokenManager owns the 3× backoff inside ensureFresh.
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (_authExemptPaths.contains(options.path)) {
          return handler.next(options);
        }
        final tm = tokenProvider?.call();
        if (tm == null) {
          // Token plumbing not wired yet — let the request go out unauthenticated;
          // server returns 401 and the bootstrap path handles it.
          return handler.next(options);
        }
        try {
          final snap = await tm.ensureFresh(reason: 'pre-flight');
          options.headers['Authorization'] = 'Bearer ${snap.access}';
        } catch (e) {
          // ensureFresh failed (no snapshot yet, or 3× refresh exhausted).
          // Surface the original API call's failure rather than aborting here
          // — TokenManager already emitted expiredHard so the UI navigates.
          debugPrint('[ApiClient] pre-flight ensureFresh failed: $e');
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        final alreadyRetried = error.requestOptions.extra['_retried'] == true;
        if (error.response?.statusCode != 401 || alreadyRetried) {
          return handler.next(error);
        }
        final options = error.requestOptions;
        if (_authExemptPaths.contains(options.path)) {
          // refresh / challenge / verify produced 401 — let it propagate.
          return handler.next(error);
        }
        final tm = tokenProvider?.call();
        if (tm == null) {
          return handler.next(error);
        }
        try {
          final snap = await tm.ensureFresh(reason: 'on-401');
          options.headers['Authorization'] = 'Bearer ${snap.access}';
          options.extra['_retried'] = true;
          final response = await _dio.fetch(options);
          return handler.resolve(response);
        } catch (_) {
          // Refresh fully failed — propagate the original 401.
          return handler.next(error);
        }
      },
    ));
  }

  // --- HTTP Methods ---

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return _dio.get<T>(path, queryParameters: queryParameters);
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return _dio.post<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  /// POST with raw binary body and custom headers (for file uploads).
  Future<Response<T>> postRaw<T>(
    String path, {
    required List<int> bytes,
    required Map<String, String> headers,
  }) {
    return _dio.post<T>(
      path,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          ...headers,
          'Content-Length': bytes.length,
        },
      ),
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
  }) {
    return _dio.put<T>(path, data: data);
  }

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
  }) {
    return _dio.patch<T>(path, data: data);
  }

  Future<Response<T>> delete<T>(String path) {
    return _dio.delete<T>(path);
  }

  /// Upload file with multipart form data.
  Future<Response<T>> upload<T>(
    String path, {
    required FormData formData,
    void Function(int, int)? onSendProgress,
  }) {
    return _dio.post<T>(
      path,
      data: formData,
      onSendProgress: onSendProgress,
    );
  }

  /// Access the underlying Dio instance if needed.
  Dio get dio => _dio;
}
