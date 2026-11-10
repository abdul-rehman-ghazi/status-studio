import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Lyrics before there are any (spec FR-3, M30): the language, Get lyrics
/// from Groq, and Type them myself, which needs no key.
class LyricsGetCard extends StatefulWidget {
  const LyricsGetCard({
    super.key,
    required this.initialLanguage,
    required this.onGet,
    required this.onType,
  });

  final ScriptLanguage initialLanguage;
  final ValueChanged<ScriptLanguage> onGet;
  final VoidCallback onType;

  @override
  State<LyricsGetCard> createState() => _LyricsGetCardState();
}

class _LyricsGetCardState extends State<LyricsGetCard> {
  late ScriptLanguage _language = widget.initialLanguage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScriptLanguagePicker(
                language: _language,
                onChanged: (language) => setState(() => _language = language),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => widget.onGet(_language),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Get lyrics from Groq'),
              ),
              const SizedBox(height: 8),
              const HintText(
                'Sends the cleaned voice to Groq with your key. The picture '
                'never leaves your phone.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: widget.onType,
          child: const Text('Type them myself'),
        ),
      ],
    );
  }
}

/// The script's language (spec FR-2), automatic by default.
class ScriptLanguagePicker extends StatelessWidget {
  const ScriptLanguagePicker({
    super.key,
    required this.language,
    required this.onChanged,
  });

  final ScriptLanguage language;
  final ValueChanged<ScriptLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ScriptLanguage>(
      initialValue: language,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Language'),
      items: [
        for (final option in ScriptLanguage.values)
          DropdownMenuItem(value: option, child: Text(option.label)),
      ],
      onChanged: (chosen) {
        if (chosen != null) {
          onChanged(chosen);
        }
      },
    );
  }
}
