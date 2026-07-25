import 'dart:typed_data';
import 'package:image/image.dart' as img;

class PrivacyBlurService {
  /// Processes image bytes entirely ON-DEVICE (0 Cloud API cost, works on Web & Mobile).
  /// Applies privacy pixelation & Gaussian blurring directly in memory before network upload.
  static Future<Uint8List> processPrivacyBlur(Uint8List rawBytes) async {
    // Decode image (supports JPEG, PNG, WebP)
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;

    // Resize giant images for mobile/web memory efficiency
    img.Image processed = decoded;
    if (processed.width > 1000) {
      processed = img.copyResize(processed, width: 1000);
    }

    // 1. Apply pixelate block filter across lower/street zone
    processed = img.pixelate(processed, size: 12);

    // 2. Apply gaussian blur pass to smooth facial features & plate characters
    processed = img.gaussianBlur(processed, radius: 3);

    // Encode to high-quality JPEG
    final output = img.encodeJpg(processed, quality: 80);
    return Uint8List.fromList(output);
  }
}
