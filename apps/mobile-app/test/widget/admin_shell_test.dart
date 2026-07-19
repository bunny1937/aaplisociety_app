import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:aapli_society/features/admin/admin_shell.dart';

import '../helpers/pump_app.dart';
import '../mocks/mock_dio.dart';

void main() {
  setUpAll(registerMockDioFallbacks);

  testWidgets('admin quick actions no longer include "Add member"', (tester) async {
    final dio = MockDio();
    when(() => dio.get('/auth/members')).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(), data: <dynamic>[],
        ));
    when(() => dio.get('/complaints')).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(), data: <dynamic>[],
        ));
    when(() => dio.get('/visitors')).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(), data: <dynamic>[],
        ));
    when(() => dio.get('/bills')).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(), data: <dynamic>[],
        ));

    await pumpApp(tester, dio: dio, child: const AdminShell());
    await tester.pumpAndSettle();

    expect(find.text('Add member'), findsNothing);
    expect(find.text('Post a notice'), findsOneWidget);
    expect(find.text('Generate bill'), findsOneWidget);
    expect(find.text('Manage complaints'), findsOneWidget);
  });
}
