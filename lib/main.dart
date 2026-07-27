import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'core/config/flavors.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/logging/app_logger.dart';
import 'core/network/dio_client.dart';
import 'core/storage/token_store.dart';
import 'core/storage/offline_cache.dart';
import 'core/storage/offline_outbox.dart';
import 'core/push/push_service.dart';
import 'core/push/firebase_bootstrap.dart';
import 'core/permissions/push_resume_gate.dart';
import 'core/socket/realtime_poller.dart';
import 'core/sos/sos_alarm.dart';
import 'core/widgets/app_toast.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'app/router.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
Future<void> main() async {
  runZonedGuarded(() async {
    // WidgetsFlutterBinding.ensureInitialized() and runApp() must run in the
    // SAME zone (Flutter's binding asserts this and prints "Zone mismatch"
    // otherwise) - both belong inside this guarded callback together.
    WidgetsFlutterBinding.ensureInitialized();
    AppConfig.current = AppConfig.resolve();
    debugPrint(
      '[config] flavor=${AppConfig.current.flavor.name} '
      'apiBaseUrl=${AppConfig.current.apiBaseUrl}',
    );
    FlutterError.onError = (details) {
      AppLogger.error(details.exceptionAsString(),
          error: details.exception, stackTrace: details.stack);
    };
    // Storage and Firebase are independent. Initializing them concurrently
    // shortens cold process restore without bypassing the remote-config gate.
    await Future.wait([_initOfflineStorage(), _initFirebaseWithRetry()]);
    runApp(const AapliApp());
  }, (error, stack) {
    AppLogger.error('Uncaught zone error', error: error, stackTrace: stack);
  });
}

Future<void> _initOfflineStorage() async {
  try {
    await OfflineCache.init();
    await OfflineOutbox.init();
  } catch (e, st) {
    AppLogger.error('Offline storage init failed', error: e, stackTrace: st);
  }
}

/// Firebase.initializeApp() has been observed to fail with
/// PlatformException(channel-error, Unable to establish connection on
/// channel.) on real devices where the native FirebaseApp auto-init (via
/// FirebaseInitProvider, confirmed in logcat as succeeding independently of
/// this call) completes fine but the Dart<->native platform-channel
/// round-trip times out - consistent with main-thread contention from OEM
/// background services on a busy device, not a config problem. Cheap and
/// safe to retry: Firebase.initializeApp() just returns the existing app if
/// one is already registered.
Future<void> _initFirebaseWithRetry() async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseBootstrap.available = true;
      AppLogger.info(
          '[boot] Firebase.initializeApp succeeded (attempt ${attempt + 1})');
      return;
    } catch (e) {
      AppLogger.warn(
          '[boot] Firebase.initializeApp failed (attempt ${attempt + 1}/3): $e');
      if (attempt < 2) {
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
  }
  AppLogger.error(
      'Firebase.initializeApp failed after 3 attempts - push notifications disabled this session');
}

class AapliApp extends StatelessWidget {
  const AapliApp({super.key});
  @override
  Widget build(BuildContext context) {
    final tokens = TokenStore();
    final dio = DioClient(tokens).dio;
    final router = buildRouter();
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<Dio>.value(value: dio),
        RepositoryProvider<TokenStore>.value(value: tokens),
      ],
      child: BlocProvider(
        create: (_) => AuthBloc(dio, tokens),
        child: BlocListener<AuthBloc, AuthState>(
          listener: (context, state) async {
            if (state is AuthAuthed) {
              AppLogger.info(
                  '[boot] AuthAuthed reached, checking session token before push registration');
              final token = await tokens.access;
              if (token == null) {
                AppLogger.warn(
                    '[boot] AuthAuthed but no stored access token - skipping push registration');
                return;
              }
              // Socket.IO is not available on the Vercel deployment; realtime
              // updates now come from polling GET /v1/notifications (plus FCM
              // pushes via PushService). RealtimePoller bumps the same
              // SocketBus counters a live socket event used to, so every screen
              // refreshes exactly as before. onEvent must NOT call
              // SocketBus.route (the poller already does) to avoid double
              // counting — it only surfaces the SOS toast here.
              RealtimePoller.instance.start(
                dio,
                onEvent: (event, data) {
                  debugPrint('[poll] $event -> $data');
                  if (event == 'VISITOR_SOS') {
                    // Was a 4-second grey-red SnackBar that said "SOS alert from
                    // the gate" and then vanished. If the guard was not staring
                    // at the screen at that exact moment, the emergency was
                    // gone. Now it rings on the alarm stream (audible on
                    // silent), vibrates, names the flat and the reason, and does
                    // not stop until somebody presses STOP.
                    final flat = [
                      if ('${data['wing'] ?? ''}'.isNotEmpty) '${data['wing']}',
                      if ('${data['flatNo'] ?? data['flat'] ?? ''}'.isNotEmpty)
                        '${data['flatNo'] ?? data['flat']}',
                    ].join('-');
                    SosAlarm.instance.ring(
                      messengerKey: scaffoldMessengerKey,
                      flatLabel: flat,
                      reason: '${data['purposeNote'] ?? data['note'] ?? ''}',
                    );
                  } else if (event == 'VISITOR_SOS_ACK') {
                    // Somebody (a guard, or a family member on another handset)
                    // has confirmed they are responding. Kill the alarm on THIS
                    // device too: STOP is local, so without this every other
                    // phone in the flat would keep ringing until each was picked
                    // up and tapped individually.
                    SosAlarm.instance.stop();
                    final by = '${data['by'] ?? ''}'.trim();
                    scaffoldMessengerKey.currentState?.showSnackBar(
                      SnackBar(
                        content: Text(by.isEmpty
                            ? 'SOS acknowledged \u2014 help is on the way.'
                            : 'SOS acknowledged by $by \u2014 help is on the way.'),
                      ),
                    );
                  }
                },
              );
              // Also flush any queued guard offline-entries on login/app start,
              // not only on socket reconnect (the socket may already be up
              // before this listener attaches, e.g. after an app relaunch
              // with a saved session).
              await OfflineOutbox.sync(dio);
              AppLogger.info('[boot] calling PushService.registerForUser');
              await PushService.instance.registerForUser(dio);
              await PushService.instance.listenNotificationTaps(router);
              await PushService.instance.listenForegroundMessages((message) {
                final ctx = scaffoldMessengerKey.currentContext;
                final text =
                    message.notification?.title ?? message.notification?.body;
                if (ctx != null && text != null) showAppToast(ctx, text);
              });
            } else if (state is AuthInitial) {
              RealtimePoller.instance.stop();
              await PushService.instance.unregister(dio);
            }
          },
          child: Builder(
            builder: (innerContext) => PushResumeGate(
              dio: dio,
              isAuthed: () => innerContext.read<AuthBloc>().state is AuthAuthed,
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: themeModeNotifier,
                builder: (_, mode, __) => MaterialApp.router(
                  title: 'Aapli Society',
                  debugShowCheckedModeBanner: false,
                  scaffoldMessengerKey: scaffoldMessengerKey,
                  theme: AppTheme.light(),
                  darkTheme: AppTheme.dark(),
                  themeMode: mode,
                  routerConfig: router,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
