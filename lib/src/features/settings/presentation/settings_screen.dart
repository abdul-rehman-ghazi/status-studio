import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/settings/presentation/background_work_section.dart';
import 'package:status_studio/src/features/settings/presentation/groq_section.dart';
import 'package:status_studio/src/features/source/application/yt_dlp_updater.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';

/// The Groq key that writes scripts, the YouTube reader, and background
/// work (spec FR-12a, FR-16).
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
          SectionLabel('YouTube support'),
          HintText(
            'Reads YouTube videos. It updates itself weekly; update now if '
            'videos stop opening.',
          ),
          _YtDlpRow(),
          SizedBox(height: 24),
          BackgroundWorkSection(),
        ],
      ),
    );
  }
}

/// yt-dlp's version, fetched by running it (about 3 s on a mid-range
/// phone).
final _ytDlpVersionProvider = FutureProvider.autoDispose<String>(
  (ref) => ref.watch(ytDlpProvider).version(),
);

class _YtDlpRow extends ConsumerStatefulWidget {
  const _YtDlpRow();

  @override
  ConsumerState<_YtDlpRow> createState() => _YtDlpRowState();
}

class _YtDlpRowState extends ConsumerState<_YtDlpRow> {
  var _updating = false;

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(_ytDlpVersionProvider);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(switch (version) {
        AsyncData(:final value) => 'yt-dlp $value',
        AsyncError() => 'yt-dlp',
        _ => 'yt-dlp …',
      }),
      subtitle: _updating ? const Text('Updating…') : null,
      trailing: TextButton(
        onPressed: _updating ? null : () => unawaited(_update()),
        child: const Text('Update'),
      ),
    );
  }

  Future<void> _update() async {
    setState(() => _updating = true);
    try {
      final result = await ref
          .read(ytDlpUpdaterProvider)
          .updateNow(DateTime.now());
      _tell(switch (result) {
        YtDlpUpdate.updated => 'YouTube support updated.',
        YtDlpUpdate.upToDate => 'YouTube support is up to date.',
      });
      ref.invalidate(_ytDlpVersionProvider);
    } on Exception catch (error) {
      _tell(errorMessageFor(error));
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  void _tell(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
