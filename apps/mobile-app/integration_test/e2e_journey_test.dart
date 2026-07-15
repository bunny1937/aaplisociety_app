// Real E2E: real app widget tree, real HTTP calls, real (isolated,
// in-memory) backend — no mocked Dio, no mocked backend, no mocked auth.
// Run against `apps/mobile-backend`'s `pnpm e2e:server` (a real Express app +
// real in-memory MongoDB seeded with one known user), never the live dev
// backend/database. See docs/testing/README.md for exact run instructions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:aapli_society/main.dart' as app;

const _username = 'e2e_member';
const _password = 'E2ePass123';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real E2E: login -> dashboard -> logout -> login again', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Splash should have routed to /login (no session yet).
    expect(find.text('Welcome back'), findsOneWidget, reason: 'splash did not route to login');

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), _username);
    await tester.enterText(fields.at(1), _password);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Real login round-trip against the real backend landed on the member dashboard.
    expect(find.textContaining('Good to see you'), findsOneWidget, reason: 'login did not reach dashboard');
    expect(find.text(_username), findsOneWidget, reason: 'dashboard did not show the real /auth/me username');

    // Navigate to profile tab and log out.
    await tester.tap(find.byIcon(Icons.person_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Log out'), findsOneWidget);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('Welcome back'), findsOneWidget, reason: 'logout did not return to login');

    // Log in again — proves the token was really cleared and a fresh real
    // login round-trip still works (session isn't fake/cached).
    final fields2 = find.byType(TextField);
    await tester.enterText(fields2.at(0), _username);
    await tester.enterText(fields2.at(1), _password);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.textContaining('Good to see you'), findsOneWidget, reason: 'second login did not reach dashboard');
  });
}
