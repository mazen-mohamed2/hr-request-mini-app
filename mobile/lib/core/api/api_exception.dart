import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException(
    this.code,
    this.message, {
    this.statusCode,
    this.fields = const [],
  });

  final String code;
  final String message;
  final int? statusCode;
  final List<String> fields;

  factory ApiException.fromDio(DioException error) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    final problem = body is Map ? body['error'] : null;
    final code = problem is Map && problem['code'] is String
        ? problem['code'] as String
        : 'HTTP_ERROR';
    final fields = <String>[];
    if (problem is Map && problem['details'] is List) {
      for (final item in problem['details'] as List) {
        if (item is Map && item['path'] is String) {
          final field = item['path'] as String;
          if ([
            'email',
            'password',
            'type',
            'subject',
            'description',
            'comment',
            'status',
          ].contains(field)) {
            fields.add(field);
          }
        }
      }
    }
    final message = switch (status ?? 0) {
      400 =>
        fields.isEmpty
            ? 'Please check the information and try again.'
            : 'Please check: ${fields.toSet().join(', ')}.',
      401 =>
        code == 'INVALID_CREDENTIALS'
            ? 'Email or password is incorrect.'
            : 'Your session has expired. Please sign in again.',
      403 => 'You do not have permission to do this.',
      404 => 'This request could not be found.',
      409 =>
        'This request has already been reviewed. Its latest status will be loaded.',
      429 => 'Too many sign-in attempts. Please try again later.',
      >= 500 => 'The service is temporarily unavailable. Please try again.',
      _ =>
        error.type == DioExceptionType.cancel
            ? 'The operation was cancelled.'
            : 'Could not connect to the service. Check your connection and try again.',
    };
    return ApiException(
      code,
      message,
      statusCode: status,
      fields: List.unmodifiable(fields),
    );
  }

  static const invalidResponse = ApiException(
    'INVALID_RESPONSE',
    'The service returned an unreadable response. Please try again.',
  );
  static const storage = ApiException(
    'STORAGE_ERROR',
    'Secure session storage is unavailable. Please try again.',
  );

  static ApiException from(Object error) => error is ApiException
      ? error
      : const ApiException(
          'UNEXPECTED',
          'Something went wrong. Please try again.',
        );

  @override
  String toString() => message;
}
