/// @file        api_client.dart
/// @description Dio-based HTTP client. Handles REST communication with the SnowChat API server.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation; postRaw added — raw binary upload support)
///
/// @functions
///  - ApiClient: Dio-based HTTP client class
///  - ApiClient.setAuthToken(): set JWT auth token
///  - ApiClient.clearAuthToken(): clear auth token
///  - ApiClient.get(): GET request
///  - ApiClient.post(): POST request
///  - ApiClient.postRaw(): raw binary POST request (file upload)
///  - ApiClient.put(): PUT request
///  - ApiClient.patch(): PATCH request
///  - ApiClient.delete(): DELETE request
///  - ApiClient.upload(): multipart file upload

import 'package:dio/dio.dart';
import 'api_endpoints.dart';

/// Dio-based HTTP client for SnowChat API.
class ApiClient {
  late final Dio _dio;

  /// Callback for token refresh. Set by the auth layer to handle 401 responses.
  Future<String> Function()? onTokenRefresh;

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
        // In production, use proper logger
        // ignore: avoid_print
        print('[API] $obj');
      },
    ));

    // Auth retry interceptor: automatically refresh token on 401
    // Uses '_retried' extra flag to prevent infinite retry loop
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) async {
        final alreadyRetried = error.requestOptions.extra['_retried'] == true;
        if (error.response?.statusCode == 401 &&
            onTokenRefresh != null &&
            !alreadyRetried) {
          try {
            final newToken = await onTokenRefresh!();
            // Retry the original request with the new token (only once)
            final options = error.requestOptions;
            options.headers['Authorization'] = 'Bearer $newToken';
            options.extra['_retried'] = true;
            final response = await _dio.fetch(options);
            return handler.resolve(response);
          } catch (_) {
            // Token refresh failed, propagate the original error
            return handler.next(error);
          }
        }
        return handler.next(error);
      },
    ));
  }

  /// Set the JWT auth token for subsequent requests.
  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Clear the auth token.
  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
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
