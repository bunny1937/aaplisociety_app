// Minimal integration_test skeleton — a template proving the pattern works,
// not a real end-to-end test. Expand this directory with one file per real
// user journey as E2E coverage is needed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('app boots without crashing', (tester) async {
    // A minimal stand-in for the app's root widget — enough to prove the
    // integration_test harness + a real widget tree pump correctly on a
    // device/emulator. Real journeys should pump the actual `AapliApp` (or
    // drive it via `app.main()`), not this placeholder.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Aapli Society')),
        ),
      ),
    );
    expect(find.text('Aapli Society'), findsOneWidget);
  });
}