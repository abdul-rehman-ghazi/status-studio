import 'package:flutter/material.dart';

/// One Settings category on its own screen, opened from the Settings list.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.section});

  final String title;
  final Widget section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.all(20), children: [section]),
    );
  }
}
