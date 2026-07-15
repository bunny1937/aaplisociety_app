import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/flavors.dart';
import '../logging/app_logger.dart';
import '../storage/token_store.dart';

class DioClient {
  final Dio dio;
  final TokenStore _tokens;

  DioClient(this._tokens) : dio = Dio(BaseOptions(
          baseUrl: AppConfig.current.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        )) {
    if (!kReleaseMode) {
      dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true, error: true));
    }
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _tokens.access;
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (e, handler) async {
        AppLogger.warn(
          '[dio] ${e.requestOptions.method} ${e.requestOptions.uri} -> '
          '${e.type} ${e.response?.statusCode ?? ''} ${e.message}',
        );
        if (e.response?.statusCode == 401) {
          final ok = await _refresh();
          if (ok) {
            final token = await _tokens.access;
            e.requestOptions.headers['Authorization'] = 'Bearer $token';
            return handler.resolve(await dio.fetch(e.requestOptions));
          }
        }
        handler.next(e);
      },
    ));
  }

  Future<bool> _refresh() async {
    final r = await _tokens.refresh;
    if (r == null) return false;
    try {
      final res = await Dio().post('${AppConfig.current.apiBaseUrl}/auth/refresh', data: {'refreshToken': r});
      await _tokens.save(res.data['tokens']['accessToken'], res.data['tokens']['refreshToken']);
      return true;
    } catch (e) {
      AppLogger.warn('[dio] token refresh failed', data: e);
      return false;
    }
  }
}
