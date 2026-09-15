import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/picker_screen.dart';
import 'screens/root_screen.dart';
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
  bool _loading = true;
  String? _action;
  StreamSubscription<String?>? _subscription;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final action = await PickerChannel.getLaunchAction();
    if (!mounted) return;
    setState(() {
      _action = action;
      _loading = false;
    });
    // Covers the case where Pixelyt is already running (e.g. in the
    // background) and gets chosen again from another app's picker request:
    // Android delivers that as onNewIntent, not a fresh launch, so this
    // stream is what makes the app switch into picker mode for it.
    _subscription = PickerChannel.onLaunchAction.listen((action) {
      if (!mounted) return;
      setState(() => _action = action);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isPickerLaunch = _action == PickerChannel.actionGetContent ||
        _action == PickerChannel.actionPick;
    return isPickerLaunch
        ? const PickerScreen(key: ValueKey('picker'))
        : const RootScreen(key: ValueKey('home'));
  }
}
