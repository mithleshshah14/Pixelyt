import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ResizeResult {
  final Uint8List bytes;
  final int width;
  final int height;
  final String extension;

  const ResizeResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.extension,
  });
}

/// Original image dimensions, read without fully processing the image.
class ImageDimensions {
  final int width;
  final int height;

  const ImageDimensions({required this.width, required this.height});
}

/// Arguments bundle for [performResize] so it can run as a single
/// top-level function inside an isolate via `compute()`.
class ResizeParams {
  final Uint8List bytes;
  final int width;
  final int height;
  final int? maxSizeBytes;

  const ResizeParams({
    required this.bytes,
    required this.width,
    required this.height,
    this.maxSizeBytes,
  });
}

ImageDimensions readDimensions(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Could not decode image');
  }
  return ImageDimensions(width: decoded.width, height: decoded.height);
}

/// Top-level entry point for `compute()`.
ResizeResult performResize(ResizeParams params) => ImageResizer.resize(
      params.bytes,
      targetWidth: params.width,
      targetHeight: params.height,
      maxSizeBytes: params.maxSizeBytes,
    );

class ImageResizer {
  /// Resizes an image to exact pixel dimensions. If [maxSizeBytes] is set,
  /// JPEG quality is stepped down (and the image is encoded as JPEG even if
  /// the source was PNG, since PNG has no quality knob to shrink with)
  /// until the result fits, or quality bottoms out.
  static ResizeResult resize(
    Uint8List inputBytes, {
    required int targetWidth,
    required int targetHeight,
    int? maxSizeBytes,
  }) {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw const FormatException('Could not decode image');
    }

    final oriented = img.bakeOrientation(decoded);
    final resized = img.copyResize(
      oriented,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.cubic,
    );

    final isPng = _looksLikePng(inputBytes);
    final needsJpeg = maxSizeBytes != null || !isPng;

    if (!needsJpeg) {
      final bytes = Uint8List.fromList(img.encodePng(resized));
      return ResizeResult(
        bytes: bytes,
        width: resized.width,
        height: resized.height,
        extension: 'png',
      );
    }

    var quality = 92;
    var bytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    if (maxSizeBytes != null) {
      while (bytes.length > maxSizeBytes && quality > 10) {
        quality -= 8;
        bytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      }
    }

    return ResizeResult(
      bytes: bytes,
      width: resized.width,
      height: resized.height,
      extension: 'jpg',
    );
  }

  static bool _looksLikePng(Uint8List bytes) {
    return bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
  }
}
