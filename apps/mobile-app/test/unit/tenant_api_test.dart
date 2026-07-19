import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:aapli_society/features/tenant/tenant_api.dart';

import '../mocks/mock_dio.dart';

Future<File> _writeTempFile(String contents) async {
  final dir = await Directory.systemTemp.createTemp('tenant_api_test');
  final file = File('${dir.path}/upload.pdf');
  await file.writeAsString(contents);
  return file;
}

void main() {
  setUpAll(registerMockDioFallbacks);
  late MockDio dio;

  setUp(() => dio = MockDio());

  test('uploadTenantDocument posts multipart form data and returns the key', () async {
    when(() => dio.post(
          '/tenant-requests/upload/contract',
          data: any(named: 'data'),
        )).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(),
          data: {'key': 'society1/tenant-requests/contract/uuid.pdf'},
        ));

    // A tiny temp file to hand to MultipartFile.fromFile — created by the test itself.
    final tmp = await _writeTempFile('fake pdf bytes');
    final key = await uploadTenantDocument(dio, 'contract', tmp.path);
    expect(key, 'society1/tenant-requests/contract/uuid.pdf');
    await tmp.delete();
  });

  test('submitTenantRequest posts the payload and returns the created request', () async {
    final payload = {'tenantName': 'Rohan Mehta'};
    when(() => dio.post('/tenant-requests', data: payload)).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(),
          data: {'_id': 'req1', 'status': 'Pending'},
        ));
    final created = await submitTenantRequest(dio, payload);
    expect(created['status'], 'Pending');
  });

  test('fetchTenantRequests returns the list', () async {
    when(() => dio.get('/tenant-requests')).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(), data: [{'_id': 'req1'}],
        ));
    final list = await fetchTenantRequests(dio);
    expect(list, hasLength(1));
  });

  test('confirmTenantMoveOut posts to the confirm-move-out route', () async {
    when(() => dio.post('/tenant-requests/req1/confirm-move-out')).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(), data: {'_id': 'req1', 'status': 'Closed'},
        ));
    final result = await confirmTenantMoveOut(dio, 'req1');
    expect(result['status'], 'Closed');
  });

  test('recordRentPayment posts the payload', () async {
    final payload = {'month': '2026-08', 'amount': 18000, 'paymentMode': 'UPI', 'paidAt': '2026-08-03T10:00:00.000Z'};
    when(() => dio.post('/rent-payments', data: payload)).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(), data: {'_id': 'pay1', 'amount': 18000},
        ));
    final created = await recordRentPayment(dio, payload);
    expect(created['amount'], 18000);
  });

  test('fetchRentPayments returns the list', () async {
    when(() => dio.get('/rent-payments')).thenAnswer((_) async => Response(
          requestOptions: FakeRequestOptions(), data: [{'_id': 'pay1'}],
        ));
    final list = await fetchRentPayments(dio);
    expect(list, hasLength(1));
  });
}
