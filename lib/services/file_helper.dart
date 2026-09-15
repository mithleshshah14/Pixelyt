import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class FileHelper {
  /// Writes cleaned image bytes to a scratch file (app cache dir) and
  /// returns it. Used both for sharing/saving in the normal flow and for
  /// handing a result back to another app in picker mode.
  static Future<File> writeCleanedFile(
    Uint8List bytes,
    String extension, {
    String? baseName,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/cleaned_images');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final name = baseName ?? 'cleaned_${DateTime.now().millisecondsSinceEpoch}';
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final path = '${dir.path}/$safeName.$extension';
    final file = File(path);
    return file.writeAsBytes(bytes, flush: true);
  }

  static String baseNameWithoutExtension(String fileName) {
    final slash = fileName.lastIndexOf(RegExp(r'[\\/]'));
    final justName = slash >= 0 ? fileName.substring(slash + 1) : fileName;
    final dot = justName.lastIndexOf('.');
    return dot > 0 ? justName.substring(0, dot) : justName;
  }
}
