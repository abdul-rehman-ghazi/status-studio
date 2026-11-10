import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/screen_title.dart';
import 'package:status_studio/src/features/about/data/device_details_reader.dart';
import 'package:status_studio/src/routing/app_router.dart';

/// The Settings categories, each opening its own screen: the Groq key,
/// background work, support and about (spec FR-12a, FR-16, FR-31).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionShown = ref.watch(appVersionProvider).value?.shown;
    return Scaffold(
      appBar: AppBar(title: const ScreenTitle('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _CategoryRow(
            icon: Icons.key_outlined,
            title: 'Groq key',
            subtitle: 'Writes the lyrics, and what is sent to Groq',
            route: AppRoutes.groqSettings,
          ),
          const _CategoryRow(
            icon: Icons.notifications_outlined,
            title: 'Background work',
            subtitle: 'Notifications when work is done',
            route: AppRoutes.backgroundSettings,
          ),
          const _CategoryRow(
            icon: Icons.support_agent_outlined,
            title: 'Support',
            subtitle: 'Feedback or a complaint, by email, WhatsApp or a call',
            route: AppRoutes.supportSettings,
          ),
          _CategoryRow(
            icon: Icons.info_outline,
            title: 'About',
            subtitle: versionShown == null
                ? 'Version and licences'
                : 'Version $versionShown and licences',
            route: AppRoutes.aboutSettings,
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );
  }
}
