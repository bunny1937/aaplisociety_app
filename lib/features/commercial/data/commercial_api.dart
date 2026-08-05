import 'package:dio/dio.dart';

/// Thin wrapper over the EXISTING DioClient (base URL, bearer token, refresh,
/// error mapping and retry are all inherited). No new HTTP stack, no new
/// interceptor, no second auth path.
///
/// Reads are cacheable; writes are online-only and never queued in
/// OfflineOutbox - a shop's public listing must not be edited from a stale
/// device state.
class CommercialApi {
  final Dio _dio;
  const CommercialApi(this._dio);

  Future<Map<String, dynamic>> directory({
    String? categoryId,
    String? search,
    String? cursor,
    int limit = 20,
  }) async {
    final res = await _dio.get('/commercial/directory', queryParameters: {
      if (categoryId != null && categoryId.isNotEmpty) 'categoryId': categoryId,
      if (search != null && search.trim().length >= 2) 'q': search.trim(),
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> categories() async {
    final res = await _dio.get('/commercial/categories');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> business(String id) async {
    final res = await _dio.get('/commercial/directory/$id');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> myBusiness() async {
    final res = await _dio.get('/commercial/me');
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Partial update. `expectedUpdatedAt` is optimistic concurrency: the server
  /// rejects the write with 409 if someone else edited the profile meanwhile,
  /// instead of silently overwriting them.
  Future<Map<String, dynamic>> updateMyBusiness(
    Map<String, dynamic> patch, {
    String? expectedUpdatedAt,
  }) async {
    final res = await _dio.patch('/commercial/me', data: {
      ...patch,
      if (expectedUpdatedAt != null) 'expectedUpdatedAt': expectedUpdatedAt,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}
