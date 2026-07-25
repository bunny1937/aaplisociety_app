import 'package:dio/dio.dart';

/// Uploads one document file to the mobile-backend, returning the R2 object
/// key the server hands back — pass this key into submitTenantRequest's
/// `documents` map.
Future<String> uploadTenantDocument(
    Dio dio, String field, String filePath) async {
  final form = FormData.fromMap({
    'file': await MultipartFile.fromFile(filePath),
  });
  final res = await dio.post('/tenant-requests/upload/$field', data: form);
  return res.data['key'] as String;
}

Future<Map<String, dynamic>> submitTenantRequest(
    Dio dio, Map<String, dynamic> payload) async {
  final res = await dio.post('/tenant-requests', data: payload);
  return Map<String, dynamic>.from(res.data as Map);
}

Future<List> fetchTenantRequests(Dio dio) async {
  final res = await dio.get('/tenant-requests');
  return res.data['requests'] as List;
}

Future<Map<String, dynamic>> confirmTenantMoveOut(
    Dio dio, String requestId) async {
  final res = await dio.post('/tenant-requests/$requestId/confirm-move-out');
  return Map<String, dynamic>.from(res.data as Map);
}

Future<Map<String, dynamic>> recordRentPayment(
    Dio dio, Map<String, dynamic> payload) async {
  final res = await dio.post('/rent-payments', data: payload);
  return Map<String, dynamic>.from(res.data as Map);
}

Future<List> fetchRentPayments(Dio dio) async {
  final res = await dio.get('/rent-payments');
  return res.data['rentPayments'] as List;
}

Future<Map<String, dynamic>> submitTenantHistory(
    Dio dio, Map<String, dynamic> payload) async {
  final res = await dio.post('/tenant-history', data: payload);
  return Map<String, dynamic>.from(res.data as Map);
}

Future<List> fetchTenantHistory(Dio dio) async {
  final res = await dio.get('/tenant-history');
  final data = res.data as Map;
  final out = <Map>[];
  if (data['currentTenant'] is Map) {
    out.add({...data['currentTenant'] as Map, '_section': 'current'});
  }
  out.addAll((data['history'] as List? ?? const [])
      .cast<Map>()
      .map((e) => {...e, '_section': 'past'}));
  return out;
}

// ---------------------------------------------------------------------------
// Owner-side tenant lifecycle + rent management.
// ---------------------------------------------------------------------------

/// Owner confirms or rejects a rent payment the tenant submitted.
Future<Map<String, dynamic>> confirmRentPayment(
    Dio dio, String id, bool approve, {String? reason}) async {
  final res = await dio.patch('/rent-payments/$id',
      data: {'action': approve ? 'confirm' : 'reject', if (reason != null) 'reason': reason});
  return Map<String, dynamic>.from(res.data as Map);
}

/// Owner edits a rent record (amount / mode / month / notes).
Future<Map<String, dynamic>> updateRentPayment(
    Dio dio, String id, Map<String, dynamic> patch) async {
  final res = await dio.patch('/rent-payments/$id', data: patch);
  return Map<String, dynamic>.from(res.data as Map);
}

/// Owner deletes a rent record.
Future<void> deleteRentPayment(Dio dio, String id) async {
  await dio.delete('/rent-payments/$id');
}

/// Owner ends the active lease (tenant moves out).
Future<Map<String, dynamic>> endLease(Dio dio, String requestId,
    {String? endDate, String? note}) async {
  final res = await dio.post('/tenant-requests/$requestId/end-lease',
      data: {if (endDate != null) 'leaseEndDate': endDate, if (note != null) 'note': note});
  return Map<String, dynamic>.from(res.data as Map);
}

/// Owner aborts a still-pending onboarding request.
Future<void> abortTenantRequest(Dio dio, String requestId) async {
  await dio.post('/tenant-requests/$requestId/abort');
}

/// Owner requests a lease-date change (needs admin approval).
Future<Map<String, dynamic>> requestLeaseDateChange(
    Dio dio, String requestId, Map<String, dynamic> payload) async {
  final res = await dio.post('/tenant-requests/$requestId/lease-change', data: payload);
  return Map<String, dynamic>.from(res.data as Map);
}

/// Owner attaches a document that was missing at onboarding time.
Future<Map<String, dynamic>> attachTenantDocument(
    Dio dio, String requestId, String field, String key) async {
  final res = await dio.post('/tenant-requests/$requestId/documents',
      data: {'field': field, 'key': key});
  return Map<String, dynamic>.from(res.data as Map);
}

/// Owner adds a private note to the tenancy.
Future<Map<String, dynamic>> addTenantNote(
    Dio dio, String requestId, String note) async {
  final res = await dio.post('/tenant-requests/$requestId/notes', data: {'note': note});
  return Map<String, dynamic>.from(res.data as Map);
}

/// Owner nudges the tenant about pending rent (push + in-app).
Future<void> sendRentReminder(Dio dio, {required String month, required num amount}) async {
  await dio.post('/rent-payments/remind', data: {'month': month, 'amount': amount});
}
