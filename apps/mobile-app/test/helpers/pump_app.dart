import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aapli_society/core/storage/token_store.dart';
import 'package:aapli_society/core/theme/app_theme.dart';
import 'package:aapli_society/features/auth/bloc/auth_bloc.dart';

import '../mocks/fake_token_store.dart';
import '../mocks/mock_dio.dart';

/// Pumps [child] wrapped in the same ancestry the real app builds in
/// `lib/main.dart` (`MultiRepositoryProvider` providing `Dio` + `TokenStore`,
/// a `BlocProvider<AuthBloc>`, and a themed `MaterialApp`), so widget tests
/// can pump any screen with realistic ancestors in one line instead of
/// hand-wiring providers every time.
///
/// Unlike the real app, this uses a plain `MaterialApp` (no `GoRouter`) so
/// tests don't need a full router configuration just to render one screen.
/// If a test needs `context.push`/`GoRouter` behavior, wrap `child` in its
/// own `MaterialApp.router` instead of using this helper.
///
/// Pass [dio]/[tokenStore] to control what the page/bloc sees; otherwise a
/// fresh [MockDio] (unstubbed) and [FakeTokenStore] are used.
Future<void> pumpApp(
  WidgetTester tester, {
  required Widget child,
  Dio? dio,
  TokenStore? tokenStore,
}) async {
  final effectiveDio = dio ?? MockDio();
  final effectiveTokenStore = tokenStore ?? FakeTokenStore();

  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<Dio>.value(value: effectiveDio),
        RepositoryProvider<TokenStore>.value(value: effectiveTokenStore),
      ],
      child: BlocProvider(
        create: (_) => AuthBloc(effectiveDio, effectiveTokenStore),
        child: MaterialApp(
          theme: AppTheme.light(),
          debugShowCheckedModeBanner: false,
          home: child,
        ),
      ),
    ),
  );
}
