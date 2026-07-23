import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Re-encodes a picked photo to a bounded JPEG regardless of what the source
/// camera produced. image_picker's maxWidth/imageQuality are best-effort and
/// some OEM camera apps (high-megapixel phones especially) hand back
/// multi-MB files even with those set — this is the hard guarantee.
Future<Uint8List> compressForUpload(File file,
    {int maxDimension = 1280, int quality = 70}) async {
  final bytes = await file.readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final needsResize =
      decoded.width > maxDimension || decoded.height > maxDimension;
  final resized = needsResize
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxDimension : null,
          height: decoded.height > decoded.width ? maxDimension : null,
        )
      : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}
