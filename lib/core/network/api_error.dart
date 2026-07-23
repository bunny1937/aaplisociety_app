import 'package:dio/dio.dart';

// Central place so every screen shows the same, real reason a request failed
// instead of a generic "something went wrong" with nothing in the logs.
String apiErrorMessage(Object error,
    [String fallback = 'Something went wrong. Please try again.']) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final e = data['error'];
      if (e is String) return e;
      if (e is Map &&
          e['formErrors'] is List &&
          (e['formErrors'] as List).isNotEmpty) {
        return (e['formErrors'] as List).first.toString();
      }
      if (e is Map && e['fieldErrors'] is Map) {
        for (final msgs in (e['fieldErrors'] as Map).values) {
          if (msgs is List && msgs.isNotEmpty) return msgs.first.toString();
        }
      }
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Connection timed out. Check your network and try again.';
      case DioExceptionType.connectionError:
        return 'Could not reach the server. Check your connection.';
      default:
        return fallback;
    }
  }
  return fallback;
}
