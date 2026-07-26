import 'dart:io';
// foundation re-exports Uint8List, so dart:typed_data would be redundant.
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Re-encodes a picked photo to a bounded JPEG regardless of what the source
/// camera produced. image_picker's maxWidth/imageQuality are best-effort and
/// some OEM camera apps (high-megapixel phones especially) hand back
/// multi-MB files even with those set — this is the hard guarantee.
///
/// Runs on a background isolate via [compute]. Decoding and JPEG-encoding a
/// 12 MP photo with the pure-Dart `image` package takes 1–3 s; doing that on
/// the UI isolate froze the gate-entry screen mid-capture with no spinner,
/// which is what the "Image decoding logging dropped" / dropped-frame warnings
/// in the logcat were reporting.
Future<Uint8List> compressForUpload(
  File file, {
  int maxDimension = 1280,
  int quality = 70,
}) async {
  final bytes = await file.readAsBytes();
  return compute(
    _encode,
    _CompressRequest(
        bytes: bytes, maxDimension: maxDimension, quality: quality),
  );
}

/// Same as [compressForUpload] but for bytes already in memory.
Future<Uint8List> compressBytesForUpload(
  Uint8List bytes, {
  int maxDimension = 1280,
  int quality = 70,
}) {
  return compute(
    _encode,
    _CompressRequest(
        bytes: bytes, maxDimension: maxDimension, quality: quality),
  );
}

class _CompressRequest {
  final Uint8List bytes;
  final int maxDimension;
  final int quality;
  const _CompressRequest({
    required this.bytes,
    required this.maxDimension,
    required this.quality,
  });
}

/// Top-level so it can be sent to an isolate.
Uint8List _encode(_CompressRequest req) {
  final decoded = img.decodeImage(req.bytes);
  // Unreadable/HEIC-only payload: hand back the original rather than losing
  // the photo entirely. The caller still uploads something.
  if (decoded == null) return req.bytes;
  final needsResize = decoded.width > req.maxDimension ||
      decoded.height > req.maxDimension;
  final resized = needsResize
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? req.maxDimension : null,
          height: decoded.height > decoded.width ? req.maxDimension : null,
        )
      : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: req.quality));
}
