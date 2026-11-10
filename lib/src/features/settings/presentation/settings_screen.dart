import 'package:flutter/material.dart';
import 'package:status_studio/src/features/about/presentation/about_section.dart';
import 'package:status_studio/src/features/about/presentation/support_section.dart';
import 'package:status_studio/src/features/settings/presentation/background_work_section.dart';
import 'package:status_studio/src/features/settings/presentation/groq_section.dart';

/// The Groq key that writes scripts, background work, support and about
/// (spec FR-12a, FR-16, FR-31).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          GroqSection(),
          SizedBox(height: 24),
          BackgroundWorkSection(),
          SizedBox(height: 24),
          SupportSection(),
          SizedBox(height: 24),
          AboutSection(),
        ],
      ),
    );
  }
}
