import 'package:flutter/material.dart';

import '../screens/album_detail_screen.dart';
import '../services/output_history_service.dart';

/// A big cover-photo card representing one album (e.g. "Cleaned photos"),
/// showing the most recent photo with its title and count overlaid at the
/// bottom. Tapping it opens the full album grid.
class AlbumCard extends StatelessWidget {
  final String title;
  final List<HistoryEntry> entries;
  final String emptyHint;
  final IconData emptyIcon;

  const AlbumCard({
    super.key,
    required this.title,
    required this.entries,
    required this.emptyHint,
    this.emptyIcon = Icons.photo_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final cover = entries.isEmpty ? null : entries.first;

    return GestureDetector(
      onTap: entries.isEmpty
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => AlbumDetailScreen(title: title, entries: entries),
                ),
              );
            },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cover != null)
                Image.file(cover.file, fit: BoxFit.cover)
              else
                Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Icon(
                      emptyIcon,
                      size: 40,
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: cover != null ? 0.65 : 0.15),
                      ],
                      stops: const [0.4, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entries.isEmpty
                          ? emptyHint
                          : '${entries.length} photo${entries.length == 1 ? '' : 's'}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
