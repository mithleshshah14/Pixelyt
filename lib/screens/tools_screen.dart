import 'package:flutter/material.dart';

import 'resize_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: const CircleAvatar(
                  child: Icon(Icons.photo_size_select_large_outlined),
                ),
                title: const Text('Resize image'),
                subtitle: const Text(
                  'Set exact width/height and optionally a target file size',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const ResizeScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
