import 'package:dio/dio.dart';
import '../config/app_config.dart';
import 'api_exception.dart';
import 'json.dart';

class ApiClient {
  ApiClient(AppConfig config, {Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options = BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      contentType: Headers.jsonContentType,
      headers: {'Accept': 'application/json'},
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final requestToken = options.extra['authenticated'] == false
              ? null
              : token;
          if (requestToken != null) {
            options.headers['Authorization'] = 'Bearer $requestToken';
            options.extra['sessionToken'] = requestToken;
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final rejected = error.requestOptions.extra['sessionToken'];
          // A late response from an old session must never log out a new session.
          if (error.response?.statusCode == 401 &&
              rejected is String &&
              rejected == token) {
            await onUnauthorized?.call(rejected);
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  String? token;
  Future<void> Function(String rejectedToken)? onUnauthorized;

  Future<T> send<T>(
    String path,
    T Function(Json) parse, {
    String method = 'GET',
    Json? data,
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          extra: {'authenticated': authenticated},
        ),
      );
      return parse(jsonObject(response.data));
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    } on FormatException {
      throw ApiException.invalidResponse;
    } on TypeError {
      throw ApiException.invalidResponse;
    }
  }

  void close() => _dio.close(force: true);
}
