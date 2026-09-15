import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class HistoryEntry {
  final File file;
  final DateTime savedAt;

  const HistoryEntry({required this.file, required this.savedAt});
}

/// Keeps a small durable history of past outputs (cleaned or resized
/// photos), grouped by category, so the app can show "albums" of past work
/// instead of losing track of it once the in-memory review state resets.
class OutputHistoryService {
  static const cleaned = 'cleaned';
  static const resized = 'resized';

  static const _maxEntries = 30;

  static Future<Directory> _categoryDir(String category) async {
    final dir = await getApplicationDocumentsDirectory();
    final catDir = Directory('${dir.path}/history_$category');
    if (!await catDir.exists()) {
      await catDir.create(recursive: true);
    }
    return catDir;
  }

  static Future<File> _manifestFile(String category) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/history_$category.json');
  }

  /// Newest first.
  static Future<List<HistoryEntry>> load(String category) async {
    try {
      final manifest = await _manifestFile(category);
      if (!await manifest.exists()) return [];
      final list = jsonDecode(await manifest.readAsString()) as List;
      final entries = <HistoryEntry>[];
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final file = File(map['path'] as String);
        if (await file.exists()) {
          entries.add(HistoryEntry(
            file: file,
            savedAt: DateTime.parse(map['savedAt'] as String),
          ));
        }
      }
      return entries;
    } catch (_) {
      return [];
    }
  }

  static Future<HistoryEntry> add(
    String category,
    Uint8List bytes,
    String extension,
  ) async {
    final catDir = await _categoryDir(category);
    final fileName = '${DateTime.now().microsecondsSinceEpoch}.$extension';
    final file = File('${catDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    final entry = HistoryEntry(file: file, savedAt: DateTime.now());

    final entries = await load(category);
    entries.insert(0, entry);

    final kept =
        entries.length > _maxEntries ? entries.sublist(0, _maxEntries) : entries;
    final toDelete = entries.length > _maxEntries ? entries.sublist(_maxEntries) : const <HistoryEntry>[];
    for (final old in toDelete) {
      if (await old.file.exists()) await old.file.delete();
    }

    final manifest = await _manifestFile(category);
    await manifest.writeAsString(jsonEncode(kept
        .map((e) => {
              'path': e.file.path,
              'savedAt': e.savedAt.toIso8601String(),
            })
        .toList()));

    return entry;
  }
}
