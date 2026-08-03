// lib/core/deeplink/deep_link_service.dart
//
// Turns an onboarding email link into an in-app route.
//
// The link in the email is and stays a normal https URL:
//   https://aaplisociety.vercel.app/onboarding/set-credentials?token=...
//
// That is the whole point of the "always fall back to the website" rule. We do
// NOT mint a custom scheme like aaplisociety:// for the email, because a custom
// scheme is a dead link for anyone without the app installed - which is most
// people the first time they are invited.
//
// Android App Links + iOS Universal Links let the SAME url open the app when it
// is installed. If it is not, the browser handles it and the member completes
// setup on the website. Either way the link works. Nothing to configure per
// member, nothing to explain in the email.
//
// Requires (see DEEPLINK-SETUP.md):
//   - app_links: ^6.3.2 in pubspec.yaml
//   - the intent-filter in AndroidManifest.xml
//   - /.well-known/assetlinks.json served by the web app

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Everything the app can be asked to do by an incoming link.
@immutable
class DeepLinkIntent {
  const DeepLinkIntent._(this.kind, {this.token, this.raw});

  final DeepLinkKind kind;
  final String? token;
  final Uri? raw;

  const DeepLinkIntent.none()
      : kind = DeepLinkKind.none,
        token = null,
        raw = null;

  factory DeepLinkIntent.onboarding(String token, Uri raw) =>
      DeepLinkIntent._(DeepLinkKind.onboarding, token: token, raw: raw);

  factory DeepLinkIntent.resetPassword(String token, Uri raw) =>
      DeepLinkIntent._(DeepLinkKind.resetPassword, token: token, raw: raw);

  factory DeepLinkIntent.unknown(Uri raw) =>
      DeepLinkIntent._(DeepLinkKind.unknown, raw: raw);

  bool get isActionable =>
      kind == DeepLinkKind.onboarding || kind == DeepLinkKind.resetPassword;

  /// Where the router should send the user.
  String? get route {
    switch (kind) {
      case DeepLinkKind.onboarding:
        return '/onboarding?token=${Uri.encodeComponent(token ?? '')}';
      case DeepLinkKind.resetPassword:
        return '/reset-password?token=${Uri.encodeComponent(token ?? '')}';
      case DeepLinkKind.unknown:
      case DeepLinkKind.none:
        return null;
    }
  }
}

enum DeepLinkKind { none, onboarding, resetPassword, unknown }

class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  final _controller = StreamController<DeepLinkIntent>.broadcast();

  /// Links that arrive while the app is already running.
  Stream<DeepLinkIntent> get stream => _controller.stream;

  /// A link that launched the app cold. Consumed once by the splash screen.
  DeepLinkIntent? _pending;

  DeepLinkIntent? consumePending() {
    final p = _pending;
    _pending = null;
    return p;
  }

  Future<void> init() async {
    // Cold start.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        final intent = parse(initial);
        if (intent.isActionable) _pending = intent;
      }
    } catch (e) {
      debugPrint('[DeepLink] initial link failed: $e');
    }

    // Warm start / app already foregrounded.
    _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen(
      (uri) {
        final intent = parse(uri);
        if (intent.isActionable) _controller.add(intent);
      },
      onError: (Object e) => debugPrint('[DeepLink] stream error: $e'),
    );
  }

  /// Pure and public so it can be unit tested without a platform channel.
  ///
  /// Only paths we explicitly recognise are honoured. An unrecognised https
  /// link that somehow reaches us is reported as unknown and IGNORED rather
  /// than routed - an app that navigates anywhere an arbitrary link tells it to
  /// is an open redirect with a nicer UI.
  DeepLinkIntent parse(Uri uri) {
    final host = uri.host.toLowerCase();

    // Host allowlist. Without this, a link on any domain that happened to be
    // routed here could drive the app.
    const allowedHosts = {
      'aaplisociety.vercel.app',
      'www.aaplisociety.vercel.app',
    };
    if (uri.scheme == 'https' && !allowedHosts.contains(host)) {
      return DeepLinkIntent.unknown(uri);
    }

    final path = uri.path.toLowerCase().replaceAll(RegExp(r'/+$'), '');
    final token = uri.queryParameters['token']?.trim();

    // A token is required for both flows, and JWTs are never this short. This
    // also stops an empty ?token= from opening a broken setup screen.
    final hasToken = token != null && token.length >= 20;

    if (path == '/onboarding/set-credentials' || path == '/onboarding') {
      return hasToken
          ? DeepLinkIntent.onboarding(token, uri)
          : DeepLinkIntent.unknown(uri);
    }

    if (path == '/reset-password' || path == '/auth/reset-password') {
      return hasToken
          ? DeepLinkIntent.resetPassword(token, uri)
          : DeepLinkIntent.unknown(uri);
    }

    return DeepLinkIntent.unknown(uri);
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
