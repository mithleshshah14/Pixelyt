import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/file_helper.dart';
import '../services/metadata_stripper.dart';
import '../services/picker_channel.dart';

/// Shown when another app asks the system to let the user pick a photo.
/// Lets the user browse their own gallery grid; whichever photo they tap is
/// cleaned of metadata before being handed back to the requesting app.
class PickerScreen extends StatefulWidget {
  const PickerScreen({super.key});

  @override
  State<PickerScreen> createState() => _PickerScreenState();
}

class _PickerScreenState extends State<PickerScreen> {
  List<AssetEntity> _assets = [];
  bool _loading = true;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await PhotoManager.requestPermissionExtend();
    if (!state.isAuth && !state.hasAccess) {
      setState(() {
        _loading = false;
        _error = 'Photo access was denied. Grant it in system settings to pick a photo.';
      });
      return;
    }

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (paths.isEmpty) {
      setState(() {
        _loading = false;
        _assets = [];
      });
      return;
    }
    final assets = await paths.first.getAssetListPaged(page: 0, size: 200);
    setState(() {
      _assets = assets;
      _loading = false;
    });
  }

  Future<void> _onAssetTap(AssetEntity asset) async {
    setState(() => _processing = true);
    try {
      final bytes = await asset.originBytes;
      if (bytes == null) {
        throw const FormatException('Could not read the original photo');
      }
      final result = MetadataStripper.strip(bytes);
      final title = await asset.titleAsync;
      final baseName = FileHelper.baseNameWithoutExtension(
        title.isNotEmpty ? title : 'photo_${asset.id}',
      );
      final file = await FileHelper.writeCleanedFile(
        result.bytes,
        result.extension,
        baseName: baseName,
      );
      await PickerChannel.returnPickedImage(file.path);
    } catch (e) {
      setState(() {
        _processing = false;
        _error = 'Could not prepare that photo: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) PickerChannel.cancelPicker();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Choose a photo to clean'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: PickerChannel.cancelPicker,
          ),
        ),
        body: Stack(
          children: [
            _buildBody(),
            if (_processing)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 12),
                      Text(
                        'Removing hidden metadata…',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_assets.isEmpty) {
      return const Center(child: Text('No photos found'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _assets.length,
      itemBuilder: (context, index) {
        final asset = _assets[index];
        return GestureDetector(
          onTap: _processing ? null : () => _onAssetTap(asset),
          child: AssetThumbnail(asset: asset),
        );
      },
    );
  }
}

class AssetThumbnail extends StatelessWidget {
  final AssetEntity asset;

  const AssetThumbnail({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize.square(200)),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return Container(color: Colors.grey.shade200);
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }
}
