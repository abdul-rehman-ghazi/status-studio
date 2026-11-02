import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/theme/app_theme.dart';

const _bytesPerMegabyte = 1000000;
const _bytesPerGigabyte = 1000000000;

/// What Settings tells the user about a speech model before they spend
/// data on it. Speeds are relative to Small, measured at 0.7× real time on
/// a Pixel 6a (spec §10 Q2).
class SpeechModelGuide {
  const SpeechModelGuide({
    required this.name,
    required this.downloadBytes,
    required this.pros,
    required this.cons,
  });

  final String name;

  /// whisper.cpp's file for the model, as served by Hugging Face.
  final int downloadBytes;
  final List<String> pros;
  final List<String> cons;
}

SpeechModelGuide guideFor(SpeechModel model) => switch (model) {
  SpeechModel.tiny => _tiny,
  SpeechModel.base => _base,
  SpeechModel.small => _small,
  SpeechModel.medium => _medium,
  SpeechModel.large => _large,
};

const _tiny = SpeechModelGuide(
  name: 'Tiny',
  downloadBytes: 77691713,
  pros: [
    'The fastest: about five times faster than Small.',
    'The smallest download.',
  ],
  cons: [
    'Makes the most mistakes, especially in languages other than English.',
    'Often mishears names and fast speech.',
  ],
);

const _base = SpeechModelGuide(
  name: 'Base',
  downloadBytes: 147951465,
  pros: [
    'About three times faster than Small.',
    'A small download that runs well on older phones.',
  ],
  cons: [
    'More mistakes than Small, especially in languages other than English.',
  ],
);

const _small = SpeechModelGuide(
  name: 'Small',
  downloadBytes: 487601967,
  pros: [
    'Good accuracy in most languages.',
    'The best balance of quality and speed on a phone.',
  ],
  cons: [
    'Slower than the video itself: a 5-minute video takes about 7 minutes '
        'on a mid-range phone.',
  ],
);

const _medium = SpeechModelGuide(
  name: 'Medium',
  downloadBytes: 1533763059,
  pros: [
    'Fewer mistakes than Small.',
    'Better with accents and less common languages.',
  ],
  cons: [
    'About three times slower than Small.',
    'Needs about 2 GB of free memory; on phones with less, the app may '
        'close.',
  ],
);

const _large = SpeechModelGuide(
  name: 'Large',
  downloadBytes: 3095033483,
  pros: ['The most accurate model.'],
  cons: [
    'About six times slower than Small: a 5-minute video can take 40 '
        'minutes or more.',
    'Needs about 4 GB of free memory, so only phones with 8 GB or more '
        'can run it.',
  ],
);

/// The model's name in its Settings row.
String titleOf(SpeechModel model) => switch (model) {
  defaultSpeechModel => '${guideFor(model).name} (recommended)',
  _ => guideFor(model).name,
};

/// `78 MB`, `488 MB`, `1.5 GB`.
String sizeText(int bytes) {
  if (bytes < _bytesPerGigabyte) {
    return '${(bytes / _bytesPerMegabyte).round()} MB';
  }
  return '${(bytes / _bytesPerGigabyte).toStringAsFixed(1)} GB';
}

/// The pros and cons of [model], from its row's info button.
Future<void> showSpeechModelGuide(BuildContext context, SpeechModel model) {
  final guide = guideFor(model);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(
            '${guide.name} · ${sizeText(guide.downloadBytes)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          const SectionLabel('Pros'),
          for (final pro in guide.pros)
            _Point(text: pro, icon: Icons.add_circle_outline),
          const SizedBox(height: 12),
          const SectionLabel('Cons'),
          for (final con in guide.cons)
            _Point(text: con, icon: Icons.remove_circle_outline),
        ],
      ),
    ),
  );
}

class _Point extends StatelessWidget {
  const _Point({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
