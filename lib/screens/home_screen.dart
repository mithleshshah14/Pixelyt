import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart' hide XFile;
import 'package:share_plus/share_plus.dart';

import '../services/file_helper.dart';
import '../services/metadata_stripper.dart';
import '../services/output_history_service.dart';
import '../widgets/album_section.dart';
import '../widgets/save_name_dialog.dart';

/// Mutable per-photo state for a batch of picked photos. Each photo is
/// loaded, previewed and cleaned independently as the user swipes between
/// them.
class _PhotoEntry {
  final XFile source;
  Uint8List? bytes;
  String? baseName;
  MetadataPreview? preview;
  bool fetchingMetadata = false;
  File? cleanedFile;
  StripResult? result;
  String? error;

  _PhotoEntry(this.source);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();
  final _pageController = PageController();

  List<_PhotoEntry> _entries = [];
  int _currentIndex = 0;
  bool _working = false;

  // Past outputs, shown as albums on the idle home screen instead of
  // leaving it blank. Loaded once at startup and refreshed after each
  // successful clean.
  List<HistoryEntry> _cleanedAlbum = [];
  List<HistoryEntry> _resizedAlbum = [];

  bool get _isBrowsing => _entries.isEmpty;
  _PhotoEntry? get _current => _entries.isEmpty ? null : _entries[_currentIndex];

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    final cleaned = await OutputHistoryService.load(OutputHistoryService.cleaned);
    final resized = await OutputHistoryService.load(OutputHistoryService.resized);
    if (!mounted) return;
    setState(() {
      _cleanedAlbum = cleaned;
      _resizedAlbum = resized;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _pickAndInspect({required bool fromCamera}) async {
    if (fromCamera) {
      final picked = await _picker.pickImage(source: ImageSource.camera);
      if (picked == null) return;
      await _startBatch([picked]);
    } else {
      final picked = await _picker.pickMultiImage();
      if (picked.isEmpty) return;
      await _startBatch(picked);
    }
  }

  Future<void> _startBatch(List<XFile> files) async {
    setState(() {
      _entries = files.map((f) => _PhotoEntry(f)).toList();
      _currentIndex = 0;
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    await _loadEntry(0);
    unawaited(_prefetchRemaining());
  }

  /// Loads the rest of the batch's metadata in the background (one at a
  /// time, so it doesn't compete too hard with whatever the user is doing)
  /// so swiping to the next photo usually finds it already ready.
  Future<void> _prefetchRemaining() async {
    for (var i = 1; i < _entries.length; i++) {
      if (!mounted) return;
      await _loadEntry(i);
    }
  }

  Future<void> _loadEntry(int index) async {
    if (index < 0 || index >= _entries.length) return;
    final entry = _entries[index];
    if (entry.bytes != null || entry.fetchingMetadata) return;

    setState(() => entry.fetchingMetadata = true);
    try {
      final bytes = await entry.source.readAsBytes();
      final baseName = FileHelper.baseNameWithoutExtension(entry.source.name);
      if (!mounted) return;
      setState(() {
        entry.bytes = bytes;
        entry.baseName = baseName;
      });
      final preview = await compute(MetadataStripper.preview, bytes);
      if (!mounted) return;
      setState(() {
        entry.preview = preview;
        entry.fetchingMetadata = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        entry.error = 'Could not read that image: $e';
        entry.fetchingMetadata = false;
      });
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _loadEntry(index);
  }

  void _reset() {
    setState(() {
      _entries = [];
      _currentIndex = 0;
    });
  }

  Future<void> _promptAndClean(_PhotoEntry entry) async {
    final defaultName = '${entry.baseName ?? 'photo'}_clean';
    final chosenName = await showDialog<String>(
      context: context,
      builder: (context) => SaveNameDialog(
        defaultName: defaultName,
        title: 'Save cleaned copy as',
        confirmLabel: 'Clean & save',
      ),
    );
    if (chosenName == null) return; // cancelled
    await _cleanAndSave(entry, chosenName.isEmpty ? defaultName : chosenName);
  }

  Future<void> _cleanAndSave(_PhotoEntry entry, String baseName) async {
    final bytes = entry.bytes;
    if (bytes == null) return;
    setState(() => _working = true);
    try {
      final result = await compute(MetadataStripper.strip, bytes);
      final file = await FileHelper.writeCleanedFile(
        result.bytes,
        result.extension,
        baseName: baseName,
      );
      setState(() {
        entry.result = result;
        entry.cleanedFile = file;
      });
      final historyEntry = await OutputHistoryService.add(
        OutputHistoryService.cleaned,
        result.bytes,
        result.extension,
      );
      if (mounted) {
        setState(() => _cleanedAlbum = [historyEntry, ..._cleanedAlbum]);
      }
      await _saveToGallery(entry);
    } catch (e) {
      setState(() => entry.error = 'Could not clean that image: $e');
    } finally {
      setState(() => _working = false);
    }
  }

  Future<void> _showAllMetadata(_PhotoEntry entry) async {
    final bytes = entry.bytes;
    if (bytes == null) return;
    try {
      final fields = await compute(MetadataStripper.readAllFields, bytes);
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => _AllMetadataSheet(fields: fields),
      );
    } catch (e) {
      setState(() => entry.error = 'Could not read metadata: $e');
    }
  }

  Future<void> _saveToGallery(_PhotoEntry entry) async {
    final file = entry.cleanedFile;
    if (file == null) return;
    try {
      await Gal.putImage(file.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved cleaned photo to your gallery')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  Future<void> _share(_PhotoEntry entry) async {
    final file = entry.cleanedFile;
    if (file == null) return;
    await Share.shareXFiles([XFile(file.path)]);
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return PopScope(
      // While reviewing/cleaning photos, the system back gesture should
      // return to the app's home view, not exit the app.
      canPop: _isBrowsing && !_working,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_working) _reset();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _entries.length > 1
                ? 'Pixelyt (${_currentIndex + 1}/${_entries.length})'
                : 'Pixelyt',
          ),
          leading: _isBrowsing
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _working ? null : _reset,
                ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(
                  child: _isBrowsing
                      ? _buildIdlePreview()
                      : PageView.builder(
                          controller: _pageController,
                          physics: _working ? const NeverScrollableScrollPhysics() : null,
                          itemCount: _entries.length,
                          onPageChanged: _onPageChanged,
                          itemBuilder: (context, index) => _buildEntryPreview(_entries[index]),
                        ),
                ),
                if (_entries.length > 1) _buildPageDots(),
                if (current?.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      current!.error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 12),
                if (current != null) ...[
                  _buildActionRow(current),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _working ? null : () => _pickAndInspect(fromCamera: false),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose photo'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _working ? null : () => _pickAndInspect(fromCamera: true),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Camera'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageDots() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_entries.length, (i) {
          final active = i == _currentIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 10 : 7,
            height: active ? 10 : 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildActionRow(_PhotoEntry entry) {
    if (entry.cleanedFile != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _saveToGallery(entry),
              icon: const Icon(Icons.save_alt),
              label: const Text('Save cleaned copy'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _share(entry),
              icon: const Icon(Icons.ios_share),
              label: const Text('Share'),
            ),
          ),
        ],
      );
    }
    if (entry.preview != null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _working ? null : () => _showAllMetadata(entry),
              icon: const Icon(Icons.list_alt_outlined),
              label: const Text('Show metadata'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _working ? null : () => _promptAndClean(entry),
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Clean & save'),
            ),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildEntryPreview(_PhotoEntry entry) {
    final cleanedFile = entry.cleanedFile;
    final result = entry.result;
    if (cleanedFile != null && result != null) {
      return Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(cleanedFile, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 12),
          _CleanedSummary(result: result),
        ],
      );
    }

    final bytes = entry.bytes;
    if (bytes == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
              if (entry.fetchingMetadata)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            'Fetching metadata…',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (entry.preview != null) _MetadataPreviewCard(preview: entry.preview!),
      ],
    );
  }

  Widget _buildIdlePreview() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Albums', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          AlbumCard(
            title: 'Cleaned photos',
            entries: _cleanedAlbum,
            emptyHint: 'Photos you clean will show up here',
            emptyIcon: Icons.cleaning_services_outlined,
          ),
          const SizedBox(height: 16),
          AlbumCard(
            title: 'Resized photos',
            entries: _resizedAlbum,
            emptyHint: 'Photos you resize (in Tools) will show up here',
            emptyIcon: Icons.photo_size_select_large_outlined,
          ),
        ],
      ),
    );
  }
}

/// Shown after a photo is picked, before the user chooses to clean it.
class _MetadataPreviewCard extends StatelessWidget {
  final MetadataPreview preview;

  const _MetadataPreviewCard({required this.preview});

  @override
  Widget build(BuildContext context) {
    if (!preview.hasAnyMetadata) {
      return const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
              SizedBox(width: 8),
              Expanded(child: Text('This image has no hidden metadata.')),
            ],
          ),
        ),
      );
    }

    final dateText = preview.dateTaken != null
        ? _formatDate(preview.dateTaken!)
        : 'not found';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This image carries ${preview.totalFieldCount} metadata field(s)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.schedule, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Date taken: $dateText (kept when cleaning)')),
              ],
            ),
            if (preview.hasGpsData) ...[
              const SizedBox(height: 4),
              const Row(
                children: [
                  Icon(Icons.warning_amber_outlined, size: 18, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(child: Text('Includes GPS location')),
                ],
              ),
            ],
            const SizedBox(height: 4),
            const Text(
              'Tap "Show metadata" to see every field found.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

/// Full raw metadata field list, opened from "Show metadata".
class _AllMetadataSheet extends StatelessWidget {
  final List<MetadataField> fields;

  const _AllMetadataSheet({required this.fields});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        fields.isEmpty
                            ? 'No metadata found'
                            : 'All metadata (${fields.length} field(s))',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: fields.length,
                  separatorBuilder: (context, index) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final field = fields[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          field.label,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 2),
                        Text(field.value),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shown after the user taps "Clean & save".
class _CleanedSummary extends StatelessWidget {
  final StripResult result;

  const _CleanedSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final dateText = result.dateTaken != null
        ? _formatDate(result.dateTaken!)
        : 'No capture date found in the original';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Kept: $dateText')),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.removedFieldCount > 0
                        ? 'Removed ${result.removedFieldCount} metadata field(s)'
                            '${result.hadGpsData ? ', including GPS location' : ''}'
                        : 'No hidden metadata was found in this image',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}
