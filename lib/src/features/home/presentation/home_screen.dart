import 'package:flutter/material.dart';
import 'package:status_studio/src/theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status Studio', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Turn any video into a status clip.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'اپنا اسٹیٹس بنائیں',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: AppFonts.nastaliq,
                  fontSize: 20,
                  height: 2.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
