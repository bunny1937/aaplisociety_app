import 'package:dio/dio.dart';

/// Uploads one document file to the mobile-backend, returning the R2 object
/// key the server hands back — pass this key into submitTenantRequest's
/// `documents` map.
Future<String> uploadTenantDocument(Dio dio, String field, String filePath) async {
  final form = FormData.fromMap({
    'file': await MultipartFile.fromFile(filePath),
  });
  final res = await dio.post('/tenant-requests/upload/$field', data: form);
  return res.data['key'] as String;
}

Future<Map<String, dynamic>> submitTenantRequest(Dio dio, Map<String, dynamic> payload) async {
  final res = await dio.post('/tenant-requests', data: payload);
  return Map<String, dynamic>.from(res.data as Map);
}

Future<List> fetchTenantRequests(Dio dio) async {
  final res = await dio.get('/tenant-requests');
  return res.data as List;
}

Future<Map<String, dynamic>> confirmTenantMoveOut(Dio dio, String requestId) async {
  final res = await dio.post('/tenant-requests/$requestId/confirm-move-out');
  return Map<String, dynamic>.from(res.data as Map);
}

Future<Map<String, dynamic>> recordRentPayment(Dio dio, Map<String, dynamic> payload) async {
  final res = await dio.post('/rent-payments', data: payload);
  return Map<String, dynamic>.from(res.data as Map);
}

Future<List> fetchRentPayments(Dio dio) async {
  final res = await dio.get('/rent-payments');
  return res.data as List;
}

Future<Map<String, dynamic>> submitTenantHistory(Dio dio, Map<String, dynamic> payload) async {
  final res = await dio.post('/tenant-history', data: payload);
  return Map<String, dynamic>.from(res.data as Map);
}

Future<List> fetchTenantHistory(Dio dio) async {
  final res = await dio.get('/tenant-history');
  return res.data as List;
}
