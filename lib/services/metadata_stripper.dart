import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Result of stripping metadata from an image: the cleaned bytes plus the
/// one piece of metadata we deliberately kept (capture date/time).
class StripResult {
  final Uint8List bytes;
  final DateTime? dateTaken;
  final String extension;
  final int removedFieldCount;
  final bool hadGpsData;

  const StripResult({
    required this.bytes,
    required this.dateTaken,
    required this.extension,
    required this.removedFieldCount,
    required this.hadGpsData,
  });
}

/// Strips all EXIF/IPTC/XMP metadata from an image, keeping only the
/// original capture date/time (re-written as a fresh, minimal EXIF block).
/// Everything else — GPS location, camera make/model/serial, software,
/// thumbnails, comments — is dropped because we build a brand-new EXIF
/// block instead of editing the original one.
class MetadataStripper {
  static StripResult strip(Uint8List inputBytes) {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw const FormatException('Could not decode image');
    }

    final dateTaken = _extractDateTaken(decoded);
    final removedFieldCount = _countFields(decoded);
    final hadGpsData = decoded.hasExif && !decoded.exif.gpsIfd.isEmpty;

    // Orientation lives in EXIF; since we're about to wipe EXIF, bake the
    // rotation into the pixels first so the cleaned image still displays
    // right-side-up everywhere.
    final oriented = img.bakeOrientation(decoded);

    oriented.exif = img.ExifData();
    if (dateTaken != null) {
      final formatted = _formatExifDate(dateTaken);
      oriented.exif.imageIfd['DateTime'] = formatted;
      oriented.exif.exifIfd['DateTimeOriginal'] = formatted;
    }

    final isPng = _looksLikePng(inputBytes);
    final outBytes = isPng
        ? Uint8List.fromList(img.encodePng(oriented))
        : Uint8List.fromList(img.encodeJpg(oriented, quality: 95));

    return StripResult(
      bytes: outBytes,
      dateTaken: dateTaken,
      extension: isPng ? 'png' : 'jpg',
      removedFieldCount: removedFieldCount,
      hadGpsData: hadGpsData,
    );
  }

  static int _countFields(img.Image image) {
    if (!image.hasExif) return 0;
    var count = 0;
    for (final directory in image.exif.directories.values) {
      count += directory.keys.length;
      for (final sub in directory.sub.values) {
        count += sub.keys.length;
      }
    }
    return count;
  }

  static bool _looksLikePng(Uint8List bytes) {
    return bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
  }

  static DateTime? _extractDateTaken(img.Image image) {
    if (!image.hasExif) return null;
    final raw = image.exif.exifIfd['DateTimeOriginal']?.toString() ??
        image.exif.imageIfd['DateTime']?.toString();
    if (raw == null || raw.trim().isEmpty) return null;
    return _parseExifDate(raw);
  }

  static DateTime? _parseExifDate(String raw) {
    // EXIF date format: "YYYY:MM:DD HH:MM:SS"
    final match = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
        .firstMatch(raw.trim());
    if (match == null) return null;
    try {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }

  static String _formatExifDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year.toString().padLeft(4, '0')}:${two(dt.month)}:${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
