import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/settings/application/settings_controller.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';

const _bytesPerMegabyte = 1000000;

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

  @override
  Widget build(BuildContext context) {
    final selected =
        ref.watch(whisperModelSettingProvider).value ?? SpeechModel.small;
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
                for (final model in const [SpeechModel.small, SpeechModel.base])
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
        ],
      ),
    );
  }

  Future<void> _download(SpeechModel model) async {
    setState(() => _downloading[model] = 0);
    try {
      await for (final fraction
          in ref.read(modelManagerProvider).download(model)) {
        if (mounted) {
          setState(() => _downloading[model] = fraction);
        }
      }
    } on Exception catch (error) {
      _showFailure(error);
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

  void _showFailure(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(errorMessageFor(error))));
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
      title: Text(_labelOf(model)),
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
      return '${(bytes / _bytesPerMegabyte).round()} MB on your phone';
    }
    return 'Not downloaded';
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

String _labelOf(SpeechModel model) => switch (model) {
  SpeechModel.small => 'Small (better, slower)',
  SpeechModel.base => 'Base (faster)',
};
