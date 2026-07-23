import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../push/firebase_bootstrap.dart';

/// Centralizes notification-permission state so it isn't scattered across
/// main.dart/PushService/onboarding UI. Notification permission is requested
/// through firebase_messaging (which also drives iOS APNs registration);
/// permission_handler is used only to distinguish "denied" from
/// "permanently denied" (Android's "don't ask again") and to deep-link to
/// OS settings, which firebase_messaging cannot do.
class AppPermissions {
  AppPermissions._();
  static const _storage = FlutterSecureStorage();
  static const _onboardingShownKey = 'notif_onboarding_shown';

  /// Whether the first-launch explanation screen has already been shown.
  /// Persisted so it never reappears after the first decision, regardless of
  /// whether the user picked Allow or Not now.
  static Future<bool> hasShownNotificationOnboarding() async {
    if (kIsWeb) return true;
    return (await _storage.read(key: _onboardingShownKey)) == 'true';
  }

  static Future<void> markNotificationOnboardingShown() async {
    if (kIsWeb) return;
    await _storage.write(key: _onboardingShownKey, value: 'true');
  }

  /// True once the user has made an irreversible choice at the OS level
  /// (Android: real permission dialog outcome; older Android has no runtime
  /// prompt at all, so this is always true there).
  static Future<bool> isPermanentlyDenied() async {
    if (kIsWeb) return false;
    final status = await ph.Permission.notification.status;
    return status.isPermanentlyDenied;
  }

  static Future<bool> isGranted() async {
    if (kIsWeb || !FirebaseBootstrap.available) return false;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Triggers the native OS prompt (a no-op if already decided). Returns
  /// whether permission ended up granted.
  static Future<bool> requestNotificationPermission() async {
    if (kIsWeb || !FirebaseBootstrap.available) return false;
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  static Future<void> openSettings() async {
    if (kIsWeb) return;
    await ph.openAppSettings();
  }
}
