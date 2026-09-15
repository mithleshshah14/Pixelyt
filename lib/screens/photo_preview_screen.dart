import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Full-screen view of a photo from an album, with a share action.
class PhotoPreviewScreen extends StatelessWidget {
  final File file;

  const PhotoPreviewScreen({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: () => Share.shareXFiles([XFile(file.path)]),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
