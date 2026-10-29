import 'package:flutter/material.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Model management arrives in M6; until then the screen only says so.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(
        child: Text(
          'Available in a later update',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}
