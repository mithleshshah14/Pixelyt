import 'package:flutter/material.dart';

import 'photo_preview_screen.dart';
import '../services/output_history_service.dart';

/// A grid of every photo in one album (all "cleaned" or all "resized"
/// outputs), reached by tapping that album's cover card on the home screen.
class AlbumDetailScreen extends StatelessWidget {
  final String title;
  final List<HistoryEntry> entries;

  const AlbumDetailScreen({
    super.key,
    required this.title,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => PhotoPreviewScreen(file: entry.file),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(entry.file, fit: BoxFit.cover),
              ),
            );
          },
        ),
      ),
    );
  }
}
