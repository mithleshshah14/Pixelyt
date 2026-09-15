import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart' hide XFile;
import 'package:share_plus/share_plus.dart';

import '../services/file_helper.dart';
import '../services/metadata_stripper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _picker = ImagePicker();

  bool _working = false;
  String? _error;

  // Set once a photo is picked, before cleaning.
  Uint8List? _originalBytes;
  String? _originalBaseName;
  MetadataPreview? _preview;

  // Set only after the user taps "Clean & save".
  File? _cleanedFile;
  StripResult? _result;

  Future<void> _pickAndInspect({required bool fromCamera}) async {
    setState(() => _error = null);
    final picked = fromCamera
        ? await _picker.pickImage(source: ImageSource.camera)
        : await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _working = true);
    try {
      final bytes = await picked.readAsBytes();
      final preview = MetadataStripper.preview(bytes);
      setState(() {
        _originalBytes = bytes;
        _originalBaseName = FileHelper.baseNameWithoutExtension(picked.name);
        _preview = preview;
        _cleanedFile = null;
        _result = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not read that image: $e');
    } finally {
      setState(() => _working = false);
    }
  }

  Future<void> _cleanAndSave() async {
    final bytes = _originalBytes;
    if (bytes == null) return;
    setState(() => _working = true);
    try {
      final result = MetadataStripper.strip(bytes);
      final file = await FileHelper.writeCleanedFile(
        result.bytes,
        result.extension,
        baseName: _originalBaseName,
      );
      setState(() {
        _result = result;
        _cleanedFile = file;
      });
    } catch (e) {
      setState(() => _error = 'Could not clean that image: $e');
    } finally {
      setState(() => _working = false);
    }
  }

  Future<void> _saveToGallery() async {
    final file = _cleanedFile;
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

  Future<void> _share() async {
    final file = _cleanedFile;
    if (file == null) return;
    await Share.shareXFiles([XFile(file.path)]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pixelyt')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(child: _buildPreview()),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              if (_cleanedFile != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saveToGallery,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Save cleaned copy'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Share'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ] else if (_preview != null) ...[
                FilledButton.icon(
                  onPressed: _working ? null : _cleanAndSave,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('Clean & save a copy'),
                ),
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
    );
  }

  Widget _buildPreview() {
    if (_working) {
      return const Center(child: CircularProgressIndicator());
    }
    final cleanedFile = _cleanedFile;
    final result = _result;
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

    final bytes = _originalBytes;
    final preview = _preview;
    if (bytes != null && preview != null) {
      return Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 12),
          _MetadataPreviewCard(preview: preview),
        ],
      );
    }

    return const Center(
      child: Text(
        'Choose a photo to see what metadata it carries — GPS location, '
        'camera info, and more — before deciding whether to clean it.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey),
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
            for (final field in preview.fields) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.warning_amber_outlined, size: 18, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${field.label}: ${field.value}')),
                ],
              ),
            ],
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
