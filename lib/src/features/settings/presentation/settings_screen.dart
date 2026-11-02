import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/settings/application/settings_controller.dart';
import 'package:status_studio/src/features/settings/presentation/speech_model_guide.dart';
import 'package:status_studio/src/features/source/application/yt_dlp_updater.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';

/// The speech model: which one Whisper uses, and which are on the phone
/// (spec FR-12).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Models downloading now, with how far each has got.
  final _downloading = <SpeechModel, double>{};

  /// A download started earlier keeps running after Settings closes;
  /// reopening shows it rather than offering a second one.
  @override
  void initState() {
    super.initState();
    final manager = ref.read(modelManagerProvider);
    for (final model in SpeechModel.values.where(manager.isDownloading)) {
      _downloading[model] = 0;
      unawaited(_follow(model));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        ref.watch(whisperModelSettingProvider).value ?? defaultSpeechModel;
    final settings = ref.read(whisperModelSettingProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionLabel('Speech model'),
          const HintText(
            'Writes the script on your phone when a video has no captions. '
            'Downloaded once, then it works offline.',
          ),
          const SizedBox(height: 8),
          RadioGroup<SpeechModel>(
            groupValue: selected,
            onChanged: (model) {
              if (model != null) {
                unawaited(settings.select(model));
              }
            },
            child: Column(
              children: [
                for (final model in SpeechModel.values)
                  _ModelRow(
                    model: model,
                    downloadFraction: _downloading[model],
                    actions: (
                      select: () => unawaited(settings.select(model)),
                      download: () => unawaited(_download(model)),
                      delete: () => unawaited(_delete(model)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('YouTube support'),
          const HintText(
            'Reads YouTube videos. It updates itself weekly; update now if '
            'videos stop opening.',
          ),
          const _YtDlpRow(),
        ],
      ),
    );
  }

  Future<void> _download(SpeechModel model) async {
    setState(() => _downloading[model] = 0);
    await _follow(model);
  }

  Future<void> _follow(SpeechModel model) async {
    try {
      await for (final amount
          in ref.read(modelManagerProvider).download(model)) {
        if (mounted) {
          setState(() => _downloading[model] = amount.fraction);
        }
      }
    } on Exception catch (error) {
      _showFailure(error, retry: () => unawaited(_download(model)));
    } finally {
      if (mounted) {
        setState(() => _downloading.remove(model));
        ref.invalidate(modelSizeProvider(model));
      }
    }
  }

  Future<void> _delete(SpeechModel model) async {
    await ref.read(modelManagerProvider).delete(model);
    ref.invalidate(modelSizeProvider(model));
  }

  /// Spec §8: "Couldn't download the speech model." with Retry.
  void _showFailure(Object error, {required VoidCallback retry}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessageFor(error)),
        action: SnackBarAction(label: 'Retry', onPressed: retry),
      ),
    );
  }
}

typedef _ModelActions = ({
  VoidCallback select,
  VoidCallback download,
  VoidCallback delete,
});

class _ModelRow extends ConsumerWidget {
  const _ModelRow({
    required this.model,
    required this.downloadFraction,
    required this.actions,
  });

  final SpeechModel model;

  /// How far a download has got, while one is running.
  final double? downloadFraction;
  final _ModelActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(modelSizeProvider(model)).value ?? 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Radio<SpeechModel>(value: model),
      title: Row(
        children: [
          Flexible(child: Text(titleOf(model))),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            visualDensity: VisualDensity.compact,
            tooltip: 'About ${guideFor(model).name}',
            onPressed: () => unawaited(showSpeechModelGuide(context, model)),
          ),
        ],
      ),
      subtitle: Text(_status(bytes)),
      trailing: _action(bytes),
      onTap: actions.select,
    );
  }

  String _status(int bytes) {
    if (downloadFraction case final fraction?) {
      return 'Downloading… ${(fraction * 100).round()} %';
    }
    if (bytes > 0) {
      return '${sizeText(bytes)} on your phone';
    }
    return '${sizeText(guideFor(model).downloadBytes)} download';
  }

  Widget? _action(int bytes) {
    if (downloadFraction != null) {
      return null;
    }
    if (bytes > 0) {
      return TextButton(onPressed: actions.delete, child: const Text('Delete'));
    }
    return TextButton(
      onPressed: actions.download,
      child: const Text('Download'),
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
