import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'backend_resolver.dart';

class ApiClient {
  final Dio dio;

  ApiClient({
    required TokenStorage tokenStorage,
    Dio? dio,
    VoidCallback? onPermissionDenied,
    Future<String?> Function()? sessionId,
    VoidCallback? onSessionEnded,
    Future<void> Function()? prepareAccountRequest,
    Future<String> Function()? resolveBackend,
    void Function(String)? backendUnavailable,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: AppConfig.apiBaseUrl,
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 15),
               headers: const {'Accept': 'application/json'},
             ),
           ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            if (options.path == 'session' || options.path.startsWith('auth/')) {
              await prepareAccountRequest?.call();
            }
            final token = await tokenStorage.readAccessToken();
            if (token != null && token.trim().isNotEmpty) {
              options.headers['Authorization'] = 'Bearer ${token.trim()}';
            }
            if (options.path != 'session' &&
                !options.path.startsWith('auth/') &&
                !options.path.startsWith('sessions/')) {
              final id = await sessionId?.call();
              if (id != null) options.headers['X-FitNEP-Session'] = id;
              // Do not mix a previous user's JWT with a new user's session.
              if (await tokenStorage.readAccessToken() != token) {
                throw StateError('The signed-in account changed.');
              }
            }
            if (resolveBackend != null) {
              options.baseUrl = await resolveBackend();
            }
            handler.next(options);
          } catch (error) {
            handler.reject(DioException(requestOptions: options, error: error));
          }
        },
        onError: (error, handler) async {
          if (isBackendConnectionFailure(error) && resolveBackend != null) {
            backendUnavailable?.call(error.requestOptions.baseUrl);
            if (const {'GET', 'HEAD'}.contains(error.requestOptions.method) &&
                error.requestOptions.extra['backend_retry'] != true) {
              final next = await resolveBackend();
              if (next != error.requestOptions.baseUrl) {
                try {
                  final response = await this.dio.fetch<Object?>(
                    error.requestOptions.copyWith(
                      baseUrl: next,
                      extra: {
                        ...error.requestOptions.extra,
                        'backend_retry': true,
                      },
                    ),
                  );
                  handler.resolve(response);
                  return;
                } on DioException catch (retryError) {
                  handler.next(retryError);
                  return;
                }
              }
            }
          }
          if (error.response?.statusCode == 403 &&
              error.requestOptions.path != 'session' &&
              !error.requestOptions.path.startsWith('auth/')) {
            onPermissionDenied?.call();
          }
          if (error.response?.statusCode == 401) onSessionEnded?.call();
          handler.next(error);
        },
      ),
    );
  }
}
