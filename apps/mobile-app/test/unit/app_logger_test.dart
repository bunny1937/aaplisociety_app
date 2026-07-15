import 'package:flutter_test/flutter_test.dart';
import 'package:aapli_society/core/logging/app_logger.dart';

class _ThrowsOnToString {
  @override
  String toString() => throw StateError('nope');
}

void main() {
  group('AppLogger', () {
    test('debug/info/warn do not throw for plain messages', () {
      expect(() => AppLogger.debug('d'), returnsNormally);
      expect(() => AppLogger.info('i'), returnsNormally);
      expect(() => AppLogger.warn('w'), returnsNormally);
    });

    test('error does not throw when given an error object and stack trace', () {
      expect(
        () => AppLogger.error('boom', error: Exception('x'), stackTrace: StackTrace.current),
        returnsNormally,
      );
    });

    test('error does not throw when error/stackTrace are omitted', () {
      expect(() => AppLogger.error('boom without extras'), returnsNormally);
    });

    test('logging with structured data does not throw, even for an object whose toString() throws', () {
      final poison = _ThrowsOnToString();
      expect(() => AppLogger.info('has bad data', data: poison), returnsNormally);
    });
  });
}
