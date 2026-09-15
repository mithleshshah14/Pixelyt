import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/picker_screen.dart';
import 'services/picker_channel.dart';

void main() {
  runApp(const PixelytApp());
}

class PixelytApp extends StatelessWidget {
  const PixelytApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pixelyt',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const _LaunchRouter(),
    );
  }
}

/// Decides, at startup, whether this app was opened normally or because
/// another app asked the system to let the user pick a photo.
class _LaunchRouter extends StatefulWidget {
  const _LaunchRouter();

  @override
  State<_LaunchRouter> createState() => _LaunchRouterState();
}

class _LaunchRouterState extends State<_LaunchRouter> {
  late final Future<String?> _launchAction = PickerChannel.getLaunchAction();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _launchAction,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final action = snapshot.data;
        final isPickerLaunch = action == PickerChannel.actionGetContent ||
            action == PickerChannel.actionPick;
        return isPickerLaunch ? const PickerScreen() : const HomeScreen();
      },
    );
  }
}
