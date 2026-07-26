import 'dart:typed_data';

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
/// Uploads an already-compressed document from memory.
///
/// The path-based [uploadTenantDocument] re-reads the original file, which
/// defeated `compressForUpload` — pickers on high-megapixel phones handed back
/// multi-MB originals and the request timed out on a gate/lobby connection.
/// Sending the compressed bytes directly avoids a temp-file round trip.
Future<String> uploadTenantDocumentBytes(
  Dio dio,
  String field,
  Uint8List bytes, {
  String filename = 'document.jpg',
}) async {
  final form = FormData.fromMap({
    'file': MultipartFile.fromBytes(bytes, filename: filename),
  });
  final res = await dio.post('/tenant-requests/upload/$field', data: form);
  final key = (res.data as Map)['key'];
  if (key == null || key.toString().isEmpty) {
    // Fail loudly: a silent null key is what let the visitor-photo bug ship.
    throw StateError('Upload succeeded but no storage key was returned.');
  }
  return key.toString();
}

/// Owner enables/disables the tenant's app login for a tenancy.
///
/// The admin still has to confirm a disable that accompanies an ended lease;
/// this only flips the owner-controlled flag.
Future<Map<String, dynamic>> updateTenantLogin(
    Dio dio, String requestId, bool enabled) async {
  final res = await dio.patch('/tenant-requests/$requestId/login',
      data: {'loginEnabled': enabled});
  return Map<String, dynamic>.from(res.data as Map);
}

/// Tenant-side view of their OWN tenancy.
///
/// Older deployments do not expose `/tenant-requests/me`; on a 404 we fall back
/// to [fetchTenantHistory] and pick the current row, so the tenant profile is
/// never a blank screen just because the backend is a version behind.
Future<Map<String, dynamic>?> fetchMyTenancy(Dio dio) async {
  try {
    final res = await dio.get('/tenant-requests/me');
    final body = res.data;
    final raw = body is Map
        ? (body['tenancy'] ?? body['request'] ?? body['currentTenant'] ?? body)
        : null;
    if (raw is Map && raw.isNotEmpty) return Map<String, dynamic>.from(raw);
    return null;
  } on DioException catch (e) {
    if (e.response?.statusCode != 404) rethrow;
    final rows = await fetchTenantHistory(dio);
    for (final r in rows) {
      if (r is Map && r['_section'] == 'current') {
        return Map<String, dynamic>.from(r);
      }
    }
    return null;
  }
}
