import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;

/// Thin wrapper around dart:developer's log() - visible in DevTools / adb
/// logcat in every build mode (including release), unlike debugPrint which
/// is compiled out in release. Also mirrors to debugPrint (which shows up as
/// plain "I/flutter" lines in `flutter run`'s own terminal) since
/// developer.log() alone was observed to not reliably surface there -
/// debugging a "why don't I see any [push] logs" report turned out to be
/// this gap, not the underlying push code never running.
class AppLogger {
  static const _name = 'AapliSociety';
  static void debug(String message, {Object? data}) =>
      _log(500, message, data: data);
  static void info(String message, {Object? data}) =>
      _log(800, message, data: data);
  static void warn(String message, {Object? data}) =>
      _log(900, message, data: data);
  static void error(String message,
          {Object? error, StackTrace? stackTrace, Object? data}) =>
      _log(1000, message, error: error, stackTrace: stackTrace, data: data);
  static void _log(int severity, String message,
      {Object? error, StackTrace? stackTrace, Object? data}) {
    // Production logs are readable on compromised/debuggable devices and by
    // crash tooling. Drop routine logs and never append payloads/PII there.
    if (kReleaseMode && severity < 900) return;
    final suffix = data == null || kReleaseMode ? '' : ' ${_safeEncode(data)}';
    final full = '$message$suffix';
    developer.log(
      full,
      name: _name,
      level: severity,
      error: error,
      stackTrace: stackTrace,
    );
    if (!kReleaseMode) {
      debugPrint('[$_name] $full${error != null ? ' — $error' : ''}');
    }
  }

  static String _safeEncode(Object data) {
    try {
      return data.toString();
    } catch (_) {
      return '<unencodable ${data.runtimeType}>';
    }
  }
}
