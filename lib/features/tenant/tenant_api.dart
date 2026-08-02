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
  // `currentTenant._id` is Member.currentTenant's own embedded subdocument
  // id — NOT the TenantRequest id every lifecycle action (login toggle,
  // notes, end-lease, document attach...) actually looks up. Every one of
  // those calls was 404ing "Tenant request not found" because it was being
  // handed this wrong id. `requests` (also returned by /tenant-history) has
  // the real TenantRequest docs; swap in the Approved one's _id here so every
  // caller of this function gets an id the backend can actually find.
  final requests = (data['requests'] as List? ?? const []).cast<Map>();
  Map? activeRequest;
  for (final r in requests) {
    if (r['status']?.toString() == 'Approved') {
      activeRequest = r;
      break;
    }
  }
  if (data['currentTenant'] is Map) {
    final current = Map<String, dynamic>.from(data['currentTenant'] as Map);
    if (activeRequest != null) current['_id'] = activeRequest['_id'];
    out.add({...current, '_section': 'current'});
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

/// Reads the shared tenancy message thread (oldest first).
///
/// Both the owner and the tenant may read it. Older deployments only had the
/// owner-only POST and no GET at all, so a 404 is treated as "no messages yet"
/// rather than an error -- the thread UI must not break the whole profile page
/// on an older backend.
Future<List<Map<String, dynamic>>> fetchTenancyNotes(Dio dio, String requestId) async {
  try {
    final res = await dio.get('/tenant-requests/$requestId/notes');
    final raw = (res.data as Map)['notes'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return const [];
    rethrow;
  }
}

/// Posts a message to the tenancy thread. Either side may call this.
///
/// The note IS the notification: the backend pushes it to the other party, so
/// there is no separate "notify" call to keep in sync. Sent by the tenant it
/// reaches the flat's owners; sent by the owner it reaches the tenants.
Future<List<Map<String, dynamic>>> postTenancyNote(
    Dio dio, String requestId, String note) async {
  final res = await dio.post('/tenant-requests/$requestId/notes', data: {'note': note});
  final raw = (res.data as Map)['notes'];
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}
