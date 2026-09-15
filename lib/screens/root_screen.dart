import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'tools_screen.dart';

/// The app's normal (non-picker-intercept) entry point: a bottom-navigated
/// shell switching between the metadata-cleaning flow and other tools.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          ToolsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.cleaning_services_outlined),
            selectedIcon: Icon(Icons.cleaning_services),
            label: 'Clean',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build),
            label: 'Tools',
          ),
        ],
      ),
    );
  }
}
