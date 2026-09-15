import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart' hide XFile;
import 'package:share_plus/share_plus.dart';

import '../services/file_helper.dart';
import '../services/image_resizer.dart';
import '../services/output_history_service.dart';
import '../widgets/save_name_dialog.dart';

enum _SizeUnit { kb, mb }

class ResizeScreen extends StatefulWidget {
  const ResizeScreen({super.key});

  @override
  State<ResizeScreen> createState() => _ResizeScreenState();
}

class _ResizeScreenState extends State<ResizeScreen> {
  final _picker = ImagePicker();

  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _maxSizeController = TextEditingController();
  bool _lockAspectRatio = true;
  _SizeUnit _sizeUnit = _SizeUnit.kb;
  bool _suppressAspectSync = false;

  Uint8List? _originalBytes;
  String? _originalBaseName;
  ImageDimensions? _originalDimensions;

  bool _working = false;
  String? _error;
  ResizeResult? _result;
  File? _resultFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage());
    _widthController.addListener(() => _onDimensionChanged(isWidth: true));
    _heightController.addListener(() => _onDimensionChanged(isWidth: false));
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _maxSizeController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _error = null);
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _working = true);
    try {
      final dims = await compute(readDimensions, bytes);
      setState(() {
        _originalBytes = bytes;
        _originalBaseName = FileHelper.baseNameWithoutExtension(picked.name);
        _originalDimensions = dims;
        _result = null;
        _resultFile = null;
        _widthController.text = dims.width.toString();
        _heightController.text = dims.height.toString();
      });
    } catch (e) {
      setState(() => _error = 'Could not read that image: $e');
    } finally {
      setState(() => _working = false);
    }
  }

  void _onDimensionChanged({required bool isWidth}) {
    if (_suppressAspectSync || !_lockAspectRatio) return;
    final dims = _originalDimensions;
    if (dims == null) return;
    final aspect = dims.width / dims.height;

    final sourceText = isWidth ? _widthController.text : _heightController.text;
    final value = int.tryParse(sourceText);
    if (value == null || value <= 0) return;

    final derived = isWidth ? (value / aspect).round() : (value * aspect).round();
    final target = isWidth ? _heightController : _widthController;
    final derivedText = derived.toString();
    if (target.text == derivedText) return;

    _suppressAspectSync = true;
    target.value = TextEditingValue(
      text: derivedText,
      selection: TextSelection.collapsed(offset: derivedText.length),
    );
    _suppressAspectSync = false;
  }

  int? _parseMaxSizeBytes() {
    final text = _maxSizeController.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value <= 0) return null;
    final multiplier = _sizeUnit == _SizeUnit.kb ? 1024 : 1024 * 1024;
    return (value * multiplier).round();
  }

  Future<void> _resize() async {
    final bytes = _originalBytes;
    if (bytes == null) return;
    final width = int.tryParse(_widthController.text);
    final height = int.tryParse(_heightController.text);
    if (width == null || height == null || width <= 0 || height <= 0) {
      setState(() => _error = 'Enter a valid width and height');
      return;
    }

    setState(() {
      _error = null;
      _working = true;
    });
    try {
      final result = await compute(
        performResize,
        ResizeParams(
          bytes: bytes,
          width: width,
          height: height,
          maxSizeBytes: _parseMaxSizeBytes(),
        ),
      );
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = 'Could not resize that image: $e');
    } finally {
      setState(() => _working = false);
    }
  }

  Future<void> _promptAndSave() async {
    final result = _result;
    if (result == null) return;
    final defaultName = '${_originalBaseName ?? 'photo'}_${result.width}x${result.height}';
    final chosenName = await showDialog<String>(
      context: context,
      builder: (context) => SaveNameDialog(
        defaultName: defaultName,
        title: 'Save resized copy as',
      ),
    );
    if (chosenName == null) return;
    final baseName = chosenName.isEmpty ? defaultName : chosenName;

    setState(() => _working = true);
    try {
      final file = await FileHelper.writeCleanedFile(
        result.bytes,
        result.extension,
        baseName: baseName,
      );
      setState(() => _resultFile = file);
      await OutputHistoryService.add(
        OutputHistoryService.resized,
        result.bytes,
        result.extension,
      );
      await Gal.putImage(file.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved resized photo to your gallery')),
        );
      }
    } catch (e) {
      setState(() => _error = 'Could not save that image: $e');
    } finally {
      setState(() => _working = false);
    }
  }

  Future<void> _share() async {
    final file = _resultFile;
    if (file == null) return;
    await Share.shareXFiles([XFile(file.path)]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resize image')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _originalBytes == null ? _buildEmptyState() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_working) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose photo'),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final bytes = _originalBytes!;
    final dims = _originalDimensions!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: dims.width / dims.height,
              child: Image.memory(bytes, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Original: ${dims.width} × ${dims.height} • ${_formatBytes(bytes.length)}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text('Dimensions (pixels)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _widthController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Width',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: _lockAspectRatio ? 'Aspect ratio locked' : 'Aspect ratio unlocked',
                icon: Icon(_lockAspectRatio ? Icons.link : Icons.link_off),
                onPressed: () => setState(() => _lockAspectRatio = !_lockAspectRatio),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _heightController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Height',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Target file size (optional)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maxSizeController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  decoration: const InputDecoration(
                    labelText: 'Max size',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<_SizeUnit>(
                segments: const [
                  ButtonSegment(value: _SizeUnit.kb, label: Text('KB')),
                  ButtonSegment(value: _SizeUnit.mb, label: Text('MB')),
                ],
                selected: {_sizeUnit},
                onSelectionChanged: (value) => setState(() => _sizeUnit = value.first),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: _working ? null : _resize,
            icon: const Icon(Icons.photo_size_select_large_outlined),
            label: const Text('Resize'),
          ),
          if (_working) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_result != null) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Text('Result', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: _result!.width / _result!.height,
                child: Image.memory(_result!.bytes, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_result!.width} × ${_result!.height} • ${_formatBytes(_result!.bytes.length)}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _working ? null : _promptAndSave,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _resultFile == null ? null : _share,
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _working ? null : _pickImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Choose a different photo'),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
}
