import 'dart:io';
import 'package:dio/dio.dart';
import '../logging/app_logger.dart';

/// Direct-to-R2 uploads.
///
/// ## Why this exists
///
/// Every upload used to be a multipart POST straight at a Vercel function,
/// which buffered the whole file in memory before forwarding it to R2. Vercel
/// rejects request bodies over **4.5 MB** at the edge, before the route handler
/// runs, and that rejection has no JSON body — so Dio surfaced it as a generic
/// failure and the UI said "upload failed, try again", which never worked
/// because the same file was always the same size.
///
/// The backend limits made this worse by advertising ceilings that were not
/// reachable: 10 MB for tenant documents, 5 MB for visitor photos. Anything
/// between 4.5 MB and those numbers failed 100% of the time.
///
/// The new flow is three steps:
///
///   1. `POST /v1/uploads/sign` — ~300 bytes, returns a presigned PUT URL.
///      Auth and society scoping happen here; the key is derived from the
///      caller's own token, so a client cannot write outside its society.
///   2. `PUT <uploadUrl>` — the bytes go straight to Cloudflare R2. This
///      request never touches Vercel, so there is no body limit and no
///      function invocation billed for the transfer.
///   3. `POST` the returned key to the attach endpoint, which verifies size
///      and magic bytes server-side and persists it.
///
/// Note the separate [Dio] instance for step 2: the app's shared client adds an
/// `Authorization` header and a `/v1` base URL. Sending our own auth header to
/// R2 makes it reject the presigned signature, so the PUT must go out clean.
class UploadService {
  UploadService(this._api);

  /// The app's configured client (base URL + auth interceptor).
  final Dio _api;

  /// Bare client for talking to R2. No interceptors, no auth, no base URL.
  static final Dio _raw = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    // Uploads on a weak gate-side connection legitimately take a while; the
    // shared client's 20s receive timeout was killing large documents.
    sendTimeout: const Duration(minutes: 3),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Uploads [file] and returns the storage key to attach.
  ///
  /// [target] must be one of the ids in the backend's `lib/v1/uploadPolicy.js`:
  /// `visitor-photo`, `tenant-contract`, `tenant-signature`, `tenant-aadhaar`,
  /// `tenant-police-verification`.
  Future<String> uploadFile({
    required File file,
    required String target,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final length = await file.length();

    // Step 1 — ask the backend to sign it. Sending the size lets the server
    // reject an oversized file before we spend the user's data uploading it.
    final signRes = await _api.post('/uploads/sign', data: {
      'target': target,
      'contentType': contentType,
      'size': length,
    });

    final signed = signRes.data as Map;
    final uploadUrl = signed['uploadUrl'] as String;
    final key = signed['key'] as String;

    // Step 2 — straight to R2. Content-Type must match exactly what was
    // signed or R2 returns 403: it is part of the signature, which is what
    // stops a client declaring image/jpeg and uploading something else.
    await _raw.put(
      uploadUrl,
      data: file.openRead(),
      options: Options(
        headers: {
          Headers.contentTypeHeader: contentType,
          Headers.contentLengthHeader: length,
        },
      ),
      onSendProgress: onProgress,
    );

    AppLogger.info('[upload] $target -> $key ($length bytes, direct to R2)');
    return key;
  }

  /// Visitor photo: upload, then attach to the visitor record.
  /// Returns the presigned display URL the server hands back.
  Future<String?> uploadVisitorPhoto({
    required String visitorId,
    required File file,
    String contentType = 'image/jpeg',
    void Function(int sent, int total)? onProgress,
  }) async {
    final key = await uploadFile(
      file: file,
      target: 'visitor-photo',
      contentType: contentType,
      onProgress: onProgress,
    );

    // Step 3 — attach. JSON body signals the new flow; the same endpoint still
    // accepts legacy multipart from older builds.
    final res = await _api.post(
      '/visitors/$visitorId/upload-photo',
      data: {'key': key},
    );
    final data = res.data as Map;
    return (data['photoUrl'] ?? data['url']) as String?;
  }

  /// Tenant document. [field] is the legacy path segment the backend expects:
  /// `contract`, `signature`, `aadhaar`, `police-verification`.
  Future<String> uploadTenantDocument({
    required String field,
    required File file,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    const targets = {
      'contract': 'tenant-contract',
      'signature': 'tenant-signature',
      'aadhaar': 'tenant-aadhaar',
      'police-verification': 'tenant-police-verification',
    };
    final target = targets[field];
    if (target == null) throw ArgumentError('Unknown tenant document field: $field');

    final key = await uploadFile(
      file: file,
      target: target,
      contentType: contentType,
      onProgress: onProgress,
    );

    final res = await _api.post(
      '/tenant-requests/upload/$field',
      data: {'key': key},
    );
    return (res.data as Map)['key'] as String;
  }
}
