import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/file_helper.dart';
import '../services/metadata_stripper.dart';
import '../services/picker_channel.dart';
import '../widgets/gallery_grid.dart';

/// Shown when another app asks the system to let the user pick a photo.
/// Lets the user browse their own gallery grid; whichever photo they tap is
/// cleaned of metadata before being handed back to the requesting app.
class PickerScreen extends StatefulWidget {
  const PickerScreen({super.key});

  @override
  State<PickerScreen> createState() => _PickerScreenState();
}

class _PickerScreenState extends State<PickerScreen> {
  bool _processing = false;
  String? _error;

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
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              )
            else
              GalleryGrid(onTap: _onAssetTap, disabled: _processing),
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
}
