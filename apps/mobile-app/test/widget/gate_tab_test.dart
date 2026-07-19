import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:aapli_society/features/security/gate_tab.dart';

import '../helpers/pump_app.dart';
import '../mocks/mock_dio.dart';

void main() {
  setUpAll(registerMockDioFallbacks);

  testWidgets('shows sectioned visitor cards computed from the fetched list', (tester) async {
    final dio = MockDio();
    when(() => dio.get('/visitors')).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(),
          data: [
            {'_id': '1', 'name': 'Rajesh Kumar', 'purpose': 'Delivery', 'phone': '9000000001', 'status': 'Pending', 'createdAt': DateTime.now().toIso8601String()},
            {'_id': '2', 'name': 'Priya Mehta', 'purpose': 'Guest', 'phone': '9000000002', 'status': 'Approved', 'createdAt': DateTime.now().toIso8601String()},
            {'_id': '3', 'name': 'Urban Company', 'purpose': 'Vendor', 'phone': '9000000003', 'status': 'Entered', 'createdAt': DateTime.now().toIso8601String(), 'entryTime': DateTime.now().toIso8601String()},
          ],
        ));

    await pumpApp(tester, dio: dio, child: const GateTab());
    await tester.pumpAndSettle();

    expect(find.text('Gate Dashboard'), findsOneWidget);
    expect(find.text('Awaiting resident approval'), findsOneWidget);
    expect(find.text('Rajesh Kumar'), findsOneWidget);
    expect(find.text('Approved — let them in'), findsOneWidget);
    expect(find.text('Priya Mehta'), findsOneWidget);
    expect(find.text('Currently inside'), findsOneWidget);
    expect(find.text('Urban Company'), findsOneWidget);
    // Pending cards must NOT have Allow-in/Deny — only Remind + icon actions.
    expect(find.text('Remind'), findsOneWidget);
    expect(find.text('Allow in'), findsNothing);
    expect(find.text('Deny'), findsNothing);
  });

  testWidgets('tapping Admit on an approved visitor posts to /visitors/:id/enter', (tester) async {
    final dio = MockDio();
    when(() => dio.get('/visitors')).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(),
          data: [
            {'_id': 'v2', 'name': 'Priya Mehta', 'purpose': 'Guest', 'phone': '9000000002', 'status': 'Approved', 'createdAt': DateTime.now().toIso8601String()},
          ],
        ));
    when(() => dio.post('/visitors/v2/enter')).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(), data: {},
        ));

    await pumpApp(tester, dio: dio, child: const GateTab());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Admit'));
    await tester.pumpAndSettle();

    verify(() => dio.post('/visitors/v2/enter')).called(1);
  });

  testWidgets('shows the all-clear empty state when there are no visitors', (tester) async {
    final dio = MockDio();
    when(() => dio.get('/visitors')).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(), data: <dynamic>[],
        ));

    await pumpApp(tester, dio: dio, child: const GateTab());
    await tester.pumpAndSettle();

    expect(find.text('All clear — nobody waiting.'), findsOneWidget);
  });
}
