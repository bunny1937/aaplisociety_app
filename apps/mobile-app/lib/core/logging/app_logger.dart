import 'dart:developer' as developer;

/// Thin wrapper around dart:developer's log() - visible in `flutter run` /
/// DevTools / adb logcat in every build mode (including release), unlike
/// debugPrint which is compiled out and produces nothing to inspect when a
/// real user hits a bug in production.
class AppLogger {
  static const _name = 'AapliSociety';

  static void debug(String message, {Object? data}) => _log(500, message, data: data);
  static void info(String message, {Object? data}) => _log(800, message, data: data);
  static void warn(String message, {Object? data}) => _log(900, message, data: data);

  static void error(String message, {Object? error, StackTrace? stackTrace, Object? data}) =>
      _log(1000, message, error: error, stackTrace: stackTrace, data: data);

  static void _log(int severity, String message, {Object? error, StackTrace? stackTrace, Object? data}) {
    final suffix = data == null ? '' : ' ${_safeEncode(data)}';
    developer.log(
      '$message$suffix',
      name: _name,
      level: severity,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static String _safeEncode(Object data) {
    try {
      return data.toString();
    } catch (_) {
      return '<unencodable ${data.runtimeType}>';
    }
  }
}
