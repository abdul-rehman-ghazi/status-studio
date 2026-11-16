import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/features/transcript/presentation/groq_usage_text.dart';

/// Output language and Get the script under a read link (spec FR-43).
class ScriptFields extends StatefulWidget {
  const ScriptFields({required this.video, required this.onGet, super.key});

  final LinkedVideo video;
  final ValueChanged<TopicRequest> onGet;

  @override
  State<ScriptFields> createState() => _ScriptFieldsState();
}

class _ScriptFieldsState extends State<ScriptFields> {
  var _outputLanguage = ScriptLanguage.urdu;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Output language'),
        DropdownButton<ScriptLanguage>(
          value: _outputLanguage,
          isExpanded: true,
          items: [
            for (final language in outputLanguages)
              DropdownMenuItem(value: language, child: Text(language.label)),
          ],
          onChanged: (language) {
            if (language != null) setState(() => _outputLanguage = language);
          },
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => widget.onGet(
            TopicRequest(
              source: LinkedMoments(widget.video),
              outputLanguage: _outputLanguage,
            ),
          ),
          icon: const Icon(Icons.subject),
          label: const Text('Get the script'),
        ),
        const GroqUsageHint(),
      ],
    );
  }
}
