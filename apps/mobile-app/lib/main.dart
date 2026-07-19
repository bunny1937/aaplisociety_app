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
import 'core/socket/socket_service.dart';
import 'core/socket/socket_bus.dart';
import 'core/widgets/app_toast.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'app/router.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    AppConfig.current = AppConfig.resolve(); // pass --dart-define=FLAVOR=dev|staging|prod

    try {
      await OfflineCache.init();
      await OfflineOutbox.init();
    } catch (e, st) {
      AppLogger.error('Offline storage init failed', error: e, stackTrace: st);
    }

    FlutterError.onError = (details) {
      AppLogger.error(details.exceptionAsString(), error: details.exception, stackTrace: details.stack);
    };

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e, st) {
      AppLogger.error('Firebase.initializeApp failed', error: e, stackTrace: st);
    }

    runApp(const AapliApp());
  }, (error, stack) {
    AppLogger.error('Uncaught zone error', error: error, stackTrace: stack);
  });
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
              final token = await tokens.access;
              if (token == null) return;
              SocketService.instance.connect(
                token,
                (event, data) {
                  SocketBus.route(event, data);
                  if (event == 'VISITOR_SOS') {
                    scaffoldMessengerKey.currentState?.showSnackBar(
                      const SnackBar(content: Text('SOS alert from the gate'), backgroundColor: Colors.red),
                    );
                  }
                },
                onReconnect: () {
                  // Events that fired while disconnected aren't replayed by the
                  // server, so force every listening screen to refetch once the
                  // socket comes back rather than showing stale data silently.
                  SocketBus.visitorEvents.value++;
                  SocketBus.billEvents.value++;
                  SocketBus.noticeEvents.value++;
                  SocketBus.notificationEvents.value++;
                  OfflineOutbox.sync(dio);
                },
              );
              // Also flush any queued guard offline-entries on login/app start,
              // not only on socket reconnect (the socket may already be up
              // before this listener attaches, e.g. after an app relaunch
              // with a saved session).
              await OfflineOutbox.sync(dio);
              await PushService.instance.registerForUser(dio);
              await PushService.instance.listenNotificationTaps(router);
              await PushService.instance.listenForegroundMessages((message) {
                final ctx = scaffoldMessengerKey.currentContext;
                final text = message.notification?.title ?? message.notification?.body;
                if (ctx != null && text != null) showAppToast(ctx, text);
              });
            } else if (state is AuthInitial) {
              SocketService.instance.dispose();
              await PushService.instance.unregister(dio);
            }
          },
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
    );
  }
}
