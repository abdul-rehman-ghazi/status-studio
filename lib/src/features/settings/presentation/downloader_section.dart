import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/source/application/yt_dlp_updater.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';

/// yt-dlp's version, the last check and Update downloader (spec FR-35).
class DownloaderSection extends ConsumerStatefulWidget {
  const DownloaderSection({super.key});

  @override
  ConsumerState<DownloaderSection> createState() => _DownloaderSectionState();
}

class _DownloaderSectionState extends ConsumerState<DownloaderSection> {
  var _updating = false;
  String? _outcome;

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(ytDlpVersionProvider).value;
    final lastChecked = ref.watch(ytDlpLastCheckedProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(version == null ? 'yt-dlp' : 'yt-dlp $version'),
        HintText(
          lastChecked == null
              ? 'Not checked yet'
              : 'Last checked ${formatDayMonth(lastChecked)}',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _updating ? null : () => unawaited(_update()),
          icon: _updating
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update_alt),
          label: const Text('Update downloader'),
        ),
        if (_outcome case final outcome?) ...[
          const SizedBox(height: 8),
          Text(outcome),
        ],
        const SizedBox(height: 12),
        const HintText(
          'Video sites change often, so the downloader checks for a new yt-dlp '
          'once a week.',
        ),
      ],
    );
  }

  Future<void> _update() async {
    setState(() {
      _updating = true;
      _outcome = null;
    });
    final outcome = await _updateOutcome();
    if (!mounted) {
      return;
    }
    setState(() {
      _updating = false;
      _outcome = outcome;
    });
  }

  Future<String> _updateOutcome() async {
    try {
      final update = await ref
          .read(ytDlpUpdaterProvider)
          .updateNow(DateTime.now());
      ref
        ..invalidate(ytDlpVersionProvider)
        ..invalidate(ytDlpLastCheckedProvider);
      if (update == YtDlpUpdate.upToDate) {
        return 'Already up to date';
      }
      final version = await ref.read(ytDlpVersionProvider.future);
      return 'Updated to $version';
    } on Exception catch (error) {
      return errorMessageFor(error);
    }
  }
}
