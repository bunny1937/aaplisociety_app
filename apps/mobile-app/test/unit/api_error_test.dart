import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aapli_society/core/network/api_error.dart';

RequestOptions _reqOptions() => RequestOptions(path: '/test');

DioException _dioExceptionWithData(dynamic data, {int statusCode = 400}) {
  final req = _reqOptions();
  return DioException(
    requestOptions: req,
    response: Response(requestOptions: req, data: data, statusCode: statusCode),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  group('apiErrorMessage', () {
    test('returns the string from `error` when response data has a plain string error', () {
      final err = _dioExceptionWithData({'error': 'Invalid credentials'});
      expect(apiErrorMessage(err), 'Invalid credentials');
    });

    test('returns the first formErrors entry for the zod-flatten shape', () {
      final err = _dioExceptionWithData({
        'error': {
          'formErrors': ['first', 'second'],
        },
      });
      expect(apiErrorMessage(err), 'first');
    });

    test('falls back when formErrors is present but empty', () {
      final err = _dioExceptionWithData({
        'error': {'formErrors': <String>[]},
      });
      expect(apiErrorMessage(err), 'Something went wrong. Please try again.');
    });

    test('returns the timeout message for connectionTimeout with no response', () {
      final req = _reqOptions();
      final err = DioException(
        requestOptions: req,
        type: DioExceptionType.connectionTimeout,
      );
      expect(apiErrorMessage(err), 'Connection timed out. Check your network and try again.');
    });

    test('returns the timeout message for receiveTimeout too', () {
      final req = _reqOptions();
      final err = DioException(
        requestOptions: req,
        type: DioExceptionType.receiveTimeout,
      );
      expect(apiErrorMessage(err), 'Connection timed out. Check your network and try again.');
    });

    test('returns the timeout message for sendTimeout too', () {
      final req = _reqOptions();
      final err = DioException(
        requestOptions: req,
        type: DioExceptionType.sendTimeout,
      );
      expect(apiErrorMessage(err), 'Connection timed out. Check your network and try again.');
    });

    test('returns the "could not reach the server" message for connectionError', () {
      final req = _reqOptions();
      final err = DioException(
        requestOptions: req,
        type: DioExceptionType.connectionError,
      );
      expect(apiErrorMessage(err), 'Could not reach the server. Check your connection.');
    });

    test('returns the default fallback for a plain non-Dio exception', () {
      expect(apiErrorMessage(Exception('boom')), 'Something went wrong. Please try again.');
    });

    test('returns a custom fallback passed as the second argument for a plain exception', () {
      expect(apiErrorMessage(Exception('boom'), 'Custom fallback message'), 'Custom fallback message');
    });

    test('returns the custom fallback for a DioException with an unhandled type and no matching data', () {
      final req = _reqOptions();
      final err = DioException(
        requestOptions: req,
        type: DioExceptionType.unknown,
      );
      expect(apiErrorMessage(err, 'Custom fallback message'), 'Custom fallback message');
    });
  });
}
