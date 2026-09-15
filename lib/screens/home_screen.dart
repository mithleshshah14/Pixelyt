import 'dart:io';

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
  File? _cleanedFile;
  StripResult? _result;
  String? _error;

  Future<void> _pickAndClean({required bool fromCamera}) async {
    setState(() {
      _error = null;
    });
    final picked = fromCamera
        ? await _picker.pickImage(source: ImageSource.camera)
        : await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _working = true);
    try {
      final bytes = await picked.readAsBytes();
      final result = MetadataStripper.strip(bytes);
      final baseName = FileHelper.baseNameWithoutExtension(picked.name);
      final file = await FileHelper.writeCleanedFile(
        result.bytes,
        result.extension,
        baseName: baseName,
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
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _working ? null : () => _pickAndClean(fromCamera: false),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose photo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _working ? null : () => _pickAndClean(fromCamera: true),
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
    final file = _cleanedFile;
    final result = _result;
    if (file == null || result == null) {
      return const Center(
        child: Text(
          'Choose a photo. Pixelyt will strip GPS location, camera info, '
          'and every other hidden detail — keeping only when it was taken.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 12),
        _MetadataSummary(result: result),
      ],
    );
  }
}

class _MetadataSummary extends StatelessWidget {
  final StripResult result;

  const _MetadataSummary({required this.result});

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
