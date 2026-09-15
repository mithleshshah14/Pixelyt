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

/// A human-readable metadata field found in the original image, shown to
/// the user before they decide whether to strip it.
class MetadataField {
  final String label;
  final String value;

  const MetadataField(this.label, this.value);
}

/// What's in an image's metadata, read without modifying it. Shown to the
/// user before they choose to clean the image.
class MetadataPreview {
  final DateTime? dateTaken;
  final List<MetadataField> fields;
  final int totalFieldCount;
  final bool hasGpsData;

  const MetadataPreview({
    required this.dateTaken,
    required this.fields,
    required this.totalFieldCount,
    required this.hasGpsData,
  });

  bool get hasAnyMetadata => totalFieldCount > 0;
}

/// Strips all EXIF/IPTC/XMP metadata from an image, keeping only the
/// original capture date/time (re-written as a fresh, minimal EXIF block).
/// Everything else — GPS location, camera make/model/serial, software,
/// thumbnails, comments — is dropped because we build a brand-new EXIF
/// block instead of editing the original one.
class MetadataStripper {
  /// Reads every metadata tag found in the image, without modifying it —
  /// unlike [preview]'s curated highlights, this is the full raw list.
  static List<MetadataField> readAllFields(Uint8List inputBytes) {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw const FormatException('Could not decode image');
    }
    if (!decoded.hasExif) return [];

    final exif = decoded.exif;
    final fields = <MetadataField>[];
    for (final directory in exif.directories.values) {
      for (final tag in directory.keys) {
        final value = directory[tag]?.toString().trim() ?? '';
        if (value.isEmpty) continue;
        fields.add(MetadataField(exif.getTagName(tag), value));
      }
      for (final sub in directory.sub.values) {
        for (final tag in sub.keys) {
          final value = sub[tag]?.toString().trim() ?? '';
          if (value.isEmpty) continue;
          fields.add(MetadataField(exif.getTagName(tag), value));
        }
      }
    }
    return fields;
  }

  /// Reads what metadata an image has, without modifying it.
  static MetadataPreview preview(Uint8List inputBytes) {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw const FormatException('Could not decode image');
    }

    final dateTaken = _extractDateTaken(decoded);
    final hasGpsData = _hasGpsCoordinates(decoded);
    final totalFieldCount = _countFields(decoded);

    final fields = <MetadataField>[];
    if (decoded.hasExif) {
      void addIfPresent(String label, String? value) {
        if (value == null || value.trim().isEmpty) return;
        fields.add(MetadataField(label, value.trim()));
      }

      addIfPresent('Camera make', decoded.exif.imageIfd.make);
      addIfPresent('Camera model', decoded.exif.imageIfd.model);
      addIfPresent('Software', decoded.exif.imageIfd.software);
      addIfPresent('Artist', decoded.exif.imageIfd['Artist']?.toString());
      addIfPresent('Copyright', decoded.exif.imageIfd.copyright);
      if (hasGpsData) {
        addIfPresent('GPS location', _formatGpsCoordinate(decoded.exif.gpsIfd));
      }
    }

    return MetadataPreview(
      dateTaken: dateTaken,
      fields: fields,
      totalFieldCount: totalFieldCount,
      hasGpsData: hasGpsData,
    );
  }

  static StripResult strip(Uint8List inputBytes) {
    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw const FormatException('Could not decode image');
    }

    final dateTaken = _extractDateTaken(decoded);
    final removedFieldCount = _countFields(decoded);
    final hadGpsData = _hasGpsCoordinates(decoded);

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

  /// True only if the image actually has a GPS coordinate (latitude AND
  /// longitude) — not just a non-empty GPS block, which some cameras write
  /// (e.g. a GPSVersionID stub) even when no location fix was recorded.
  static bool _hasGpsCoordinates(img.Image image) {
    if (!image.hasExif) return false;
    final gps = image.exif.gpsIfd;
    return gps.hasGPSLatitude && gps.hasGPSLongitude;
  }

  /// Converts the degrees/minutes/seconds GPS tags into a human-readable
  /// decimal coordinate, e.g. "37.4220° N, 122.0841° W".
  static String? _formatGpsCoordinate(img.IfdDirectory gpsIfd) {
    final lat = _dmsToDecimal(gpsIfd['GPSLatitude']);
    final lon = _dmsToDecimal(gpsIfd['GPSLongitude']);
    if (lat == null || lon == null) return null;
    final latRef = gpsIfd['GPSLatitudeRef']?.toString().trim().toUpperCase();
    final lonRef = gpsIfd['GPSLongitudeRef']?.toString().trim().toUpperCase();
    final latDeg = lat.toStringAsFixed(4);
    final lonDeg = lon.toStringAsFixed(4);
    return '$latDeg° ${latRef ?? ''}, $lonDeg° ${lonRef ?? ''}'.trim();
  }

  static double? _dmsToDecimal(img.IfdValue? value) {
    if (value == null || value.length < 3) return null;
    final degrees = value.toDouble(0);
    final minutes = value.toDouble(1);
    final seconds = value.toDouble(2);
    return degrees + (minutes / 60) + (seconds / 3600);
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
