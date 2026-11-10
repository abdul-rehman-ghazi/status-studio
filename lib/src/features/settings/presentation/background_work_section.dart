import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/background/application/background_access.dart';

final _notificationsEnabledProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(backgroundAccessProvider).notificationsEnabled(),
);

/// Background work and whether its notifications are on, with a way to
/// allow them (spec FR-16).
class BackgroundWorkSection extends ConsumerStatefulWidget {
  const BackgroundWorkSection({super.key});

  @override
  ConsumerState<BackgroundWorkSection> createState() =>
      _BackgroundWorkSectionState();
}

class _BackgroundWorkSectionState extends ConsumerState<BackgroundWorkSection> {
  /// The answers change in system dialogs and App info, outside the app;
  /// they're read again when the user comes back.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(_notificationsEnabledProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.read(backgroundAccessProvider);
    final notificationsOn = ref.watch(_notificationsEnabledProvider).value;
    final onIos = defaultTargetPlatform == TargetPlatform.iOS;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Background work'),
        HintText(
          onIos
              ? 'iOS lets work go on for only a short while after you leave '
                    'the app. A script then pauses and carries on from its '
                    'last saved piece when you come back. Keep the app open '
                    'while it exports.'
              : 'Keeps writing scripts and exporting when you leave the app '
                    'or lock the phone.',
        ),
        if (notificationsOn != null) _notificationsRow(access, notificationsOn),
        const SizedBox(height: 8),
        if (!onIos)
          const HintText(
            'On Xiaomi and some other phones, also set Battery saver to No '
            'restrictions in App info.',
          ),
        TextButton(
          onPressed: () => unawaited(access.openAppInfo()),
          child: Text(onIos ? 'Open Settings' : 'Open App info'),
        ),
      ],
    );
  }

  Widget _notificationsRow(BackgroundAccess access, bool notificationsOn) =>
      _AccessRow(
        title: 'Notifications',
        subtitle: notificationsOn
            ? 'On'
            : "Off: you won't hear when work is done",
        onAllow: notificationsOn
            ? null
            : () => unawaited(_allowNotifications(access)),
      );

  Future<void> _allowNotifications(BackgroundAccess access) async {
    await access.allowNotifications();
    ref.invalidate(_notificationsEnabledProvider);
  }
}

class _AccessRow extends StatelessWidget {
  const _AccessRow({
    required this.title,
    required this.subtitle,
    required this.onAllow,
  });

  final String title;
  final String subtitle;

  /// Null once it's allowed.
  final VoidCallback? onAllow;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: switch (onAllow) {
        final allow? => TextButton(
          onPressed: allow,
          child: const Text('Allow'),
        ),
        null => null,
      },
    );
  }
}
