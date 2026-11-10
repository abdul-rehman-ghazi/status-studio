import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/about/data/device_details_reader.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/theme/app_theme.dart';

const appName = 'Status Studio';

/// The logo, name, version and open-source licences (spec FR-31).
class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionShown = ref.watch(appVersionProvider).value?.shown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NameAndVersion(versionShown: versionShown),
        const SizedBox(height: 12),
        const HintText(
          'Turns a video you have trimmed into a short status clip, with its '
          'lyrics in any language.',
        ),
        const SizedBox(height: 4),
        TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: () => showLicensePage(
            context: context,
            applicationName: appName,
            applicationVersion: versionShown,
            applicationIcon: const Padding(
              padding: EdgeInsets.all(12),
              child: LogoMark(size: 48),
            ),
          ),
          child: const Text('Open-source licences'),
        ),
      ],
    );
  }
}

class _NameAndVersion extends StatelessWidget {
  const _NameAndVersion({required this.versionShown});

  /// Null while the package details are still being read.
  final String? versionShown;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        const LogoMark(size: 48),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appName, style: textTheme.titleMedium),
            if (versionShown != null)
              Text(
                'Version $versionShown',
                style: textTheme.bodySmall?.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
