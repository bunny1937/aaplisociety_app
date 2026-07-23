import 'dart:async';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../logging/app_logger.dart';
import '../socket/socket_bus.dart';
import 'firebase_bootstrap.dart';

// Runs in a separate headless isolate while the app is backgrounded/killed -
// must be a top-level (or static) function, no BuildContext, no UI. Actual
// notification display for this case is handled by the OS itself (the
// backend sends a `notification` block alongside `data` - see
// apps/mobile-backend/src/services/fcm.ts), this only logs + lets any
// data-only follow-up work run.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.info('[push] background message ${message.messageId}',
      data: message.data);
}

/// Registers this device for push (POST /v1/devices), listens for
/// foreground messages, and de-registers on logout so a signed-out session
/// stops receiving pushes. Mirrors SocketService's shape; like SocketService
/// this wraps a native plugin and isn't unit-tested for the same reason
/// (platform channel I/O, not pure logic - see test/unit/socket_bus_test.dart
/// for the piece of this that IS pure and IS tested).
class PushService {
  PushService._();
  static final instance = PushService._();
  String? _registeredToken;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  // Guards against overlapping registerForUser() calls racing each other -
  // e.g. resume + login listener firing close together - which would fire
  // duplicate getToken()/POST /devices calls concurrently.
  bool _registering = false;
  Future<void> registerForUser(Dio dio) async {
    AppLogger.info(
        '[push] registerForUser entered (kIsWeb=$kIsWeb, firebaseAvailable=${FirebaseBootstrap.available}, alreadyRegistering=$_registering)');
    if (kIsWeb) {
      return; // web push needs a separate VAPID-key setup, out of scope here
    }
    if (!FirebaseBootstrap.available) {
      AppLogger.warn('[push] Firebase unavailable - skipping registration');
      return;
    }
    if (_registering) return;
    _registering = true;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      AppLogger.info(
          '[push] permission status: ${settings.authorizationStatus}');
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        AppLogger.warn('[push] notification permission denied by user');
        return;
      }
      final token = await _getTokenWithRetry();
      if (token != null) await _sendToken(dio, token);
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh
          .listen((t) => _sendToken(dio, t));
    } catch (e, st) {
      AppLogger.error('[push] registerForUser failed',
          error: e, stackTrace: st);
    } finally {
      _registering = false;
    }
  }

  /// getToken() can transiently return null right after a fresh install
  /// (Play Services/APNs handshake still in flight) - a few short retries
  /// clear that without risking an infinite loop.
  Future<String?> _getTokenWithRetry() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        AppLogger.info(
            '[push] FCM token received: yes, length=${token.length}');
        return token;
      }
      AppLogger.warn(
          '[push] getToken() returned null (attempt ${attempt + 1}/3)');
      if (attempt < 2) await Future.delayed(Duration(seconds: 2 << attempt));
    }
    AppLogger.warn('[push] FCM token received: no, after 3 attempts');
    return null;
  }

  Future<void> _sendToken(Dio dio, String token) async {
    try {
      await dio.post('/devices', data: {
        'fcmToken': token,
        'platform':
            defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      });
      _registeredToken = token;
      AppLogger.info('[push] device registered');
    } on DioException catch (e) {
      AppLogger.error(
        '[push] device registration failed: ${e.response?.statusCode} ${e.response?.data}',
        error: e,
      );
    } catch (e, st) {
      AppLogger.error('[push] device registration failed',
          error: e, stackTrace: st);
    }
  }

  Future<void> unregister(Dio dio) async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    await _foregroundSub?.cancel();
    _foregroundSub = null;
    await _openedAppSub?.cancel();
    _openedAppSub = null;
    final token = _registeredToken;
    _registeredToken = null;
    if (token == null) return;
    try {
      await dio.delete('/devices/${Uri.encodeComponent(token)}');
    } catch (e, st) {
      AppLogger.error('[push] device unregister failed',
          error: e, stackTrace: st);
    }
  }

  /// Foreground messages don't get an OS tray notification automatically -
  /// the caller decides how to surface them (toast/snackbar) and this also
  /// bumps the same SocketBus counters a live socket event would, so badges
  /// refresh consistently whether the update arrived via socket or push.
  /// Safe to call repeatedly (e.g. on every re-auth) - replaces any previous
  /// subscription instead of stacking duplicates.
  Future<void> listenForegroundMessages(
      void Function(RemoteMessage message) onMessage) async {
    if (kIsWeb || !FirebaseBootstrap.available) return;
    await _foregroundSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
      final type = message.data['type'] as String?;
      final isNew = type == null || SocketBus.route(type, message.data);
      if (isNew) onMessage(message);
    });
  }

  /// Navigates to the notification center when the user taps a push
  /// notification — covers both the app-already-running case
  /// (`onMessageOpenedApp`) and cold-start-from-tap (`getInitialMessage`).
  /// Every notification type routes to the same destination (`/notifications`)
  /// rather than a per-type deep link: the notification center already shows
  /// role-appropriate content (see mobile-backend's notification.controller.ts),
  /// so one robust destination beats a brittle type->route mapping that has
  /// to be kept in sync with every NOTIFICATION_TYPES addition.
  Future<void> listenNotificationTaps(GoRouter router) async {
    if (kIsWeb || !FirebaseBootstrap.available) return;
    await _openedAppSub?.cancel();
    _openedAppSub = FirebaseMessaging.onMessageOpenedApp
        .listen((_) => router.push('/notifications'));
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) router.push('/notifications');
  }
}
