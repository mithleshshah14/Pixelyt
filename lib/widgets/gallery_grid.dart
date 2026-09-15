import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// A grid of the device's photos. Used both for normal in-app picking and
/// for the Android picker-intercept flow, so filenames and thumbnails
/// resolve the same way (and correctly) in both places.
class GalleryGrid extends StatefulWidget {
  final ValueChanged<AssetEntity> onTap;
  final bool disabled;

  const GalleryGrid({super.key, required this.onTap, this.disabled = false});

  @override
  State<GalleryGrid> createState() => _GalleryGridState();
}

class _GalleryGridState extends State<GalleryGrid> {
  List<AssetEntity> _assets = [];
  bool _loading = true;
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
        _error = 'Photo access was denied. Grant it in system settings to browse your photos.';
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
    if (!mounted) return;
    setState(() {
      _assets = assets;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
          onTap: widget.disabled ? null : () => widget.onTap(asset),
          child: _AssetThumbnail(asset: asset),
        );
      },
    );
  }
}

class _AssetThumbnail extends StatelessWidget {
  final AssetEntity asset;

  const _AssetThumbnail({required this.asset});

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
