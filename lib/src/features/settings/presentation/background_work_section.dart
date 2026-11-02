import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/background/application/background_access.dart';

final _accessStatusProvider =
    FutureProvider.autoDispose<BackgroundAccessStatus>(
      (ref) => ref.watch(backgroundAccessProvider).status(),
    );

/// Whether Android lets scripts and exports run in the background, with a
/// way to allow what isn't (spec FR-16).
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
      onResume: () => ref.invalidate(_accessStatusProvider),
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
    final status = ref.watch(_accessStatusProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Background work'),
        const HintText(
          'Keeps writing scripts and exporting when you leave the app or '
          'lock the phone.',
        ),
        if (status != null) ..._accessRows(access, status),
        const SizedBox(height: 8),
        const HintText(
          'On Xiaomi and some other phones, also set Battery saver to No '
          'restrictions in App info.',
        ),
        TextButton(
          onPressed: () => unawaited(access.openAppInfo()),
          child: const Text('Open App info'),
        ),
      ],
    );
  }

  List<Widget> _accessRows(
    BackgroundAccess access,
    BackgroundAccessStatus status,
  ) => [
    _AccessRow(
      title: 'Notifications',
      subtitle: status.notifications
          ? 'On'
          : "Off: you won't hear when work is done",
      onAllow: status.notifications
          ? null
          : () => unawaited(_allow(access.allowNotifications)),
    ),
    _AccessRow(
      title: 'Battery optimisation',
      subtitle: status.unrestricted
          ? 'Off: work keeps going with the screen locked'
          : 'On: Android may pause work in the background',
      onAllow: status.unrestricted
          ? null
          : () => unawaited(_allow(access.allowUnrestricted)),
    ),
  ];

  Future<void> _allow(Future<void> Function() request) async {
    await request();
    ref.invalidate(_accessStatusProvider);
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
