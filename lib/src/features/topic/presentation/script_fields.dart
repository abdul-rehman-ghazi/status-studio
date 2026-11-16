import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/topic/data/output_language_store.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/features/transcript/presentation/groq_usage_text.dart';

/// Output language and Get the script under a read link (spec FR-43) or a
/// kept video (FR-51), and on From a link Use the whole video (FR-52).
/// The last language used is preselected.
class ScriptFields extends ConsumerStatefulWidget {
  const ScriptFields({
    required this.source,
    required this.onGet,
    this.onUseWhole,
    super.key,
  });

  final MomentSource source;
  final ValueChanged<TopicRequest> onGet;

  /// Shows Use the whole video, on for a video up to [longestWholeLink].
  final ValueChanged<TopicRequest>? onUseWhole;

  @override
  ConsumerState<ScriptFields> createState() => _ScriptFieldsState();
}

class _ScriptFieldsState extends ConsumerState<ScriptFields> {
  var _outputLanguage = ScriptLanguage.urdu;
  var _chosen = false;

  @override
  void initState() {
    super.initState();
    unawaited(_preselectLastLanguage());
  }

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
            if (language == null) {
              return;
            }
            setState(() {
              _outputLanguage = language;
              _chosen = true;
            });
          },
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _choose(widget.onGet),
          icon: const Icon(Icons.subject),
          label: const Text('Get the script'),
        ),
        const GroqUsageHint(),
        if (widget.onUseWhole case final onUseWhole?)
          ..._wholeVideoButton(onUseWhole),
      ],
    );
  }

  List<Widget> _wholeVideoButton(ValueChanged<TopicRequest> onUseWhole) {
    final fits = widget.source.duration <= longestWholeLink;
    return [
      const SizedBox(height: 8),
      TextButton(
        onPressed: fits ? () => _choose(onUseWhole) : null,
        child: const Text('Use the whole video'),
      ),
      if (!fits)
        HintText(
          'For a video up to ${longestWholeLink.inMinutes} minutes. Pick '
          'moments from a longer one.',
        ),
    ];
  }

  TopicRequest _request() =>
      TopicRequest(source: widget.source, outputLanguage: _outputLanguage);

  /// A choice made before the saved one is read wins.
  Future<void> _preselectLastLanguage() async {
    try {
      final saved = await ref.read(outputLanguageStoreProvider).read();
      if (mounted && !_chosen) setState(() => _outputLanguage = saved);
    } on Exception {
      // Urdu stays preselected.
    }
  }

  /// The language is kept for next time, whichever button was tapped.
  void _choose(ValueChanged<TopicRequest> action) {
    unawaited(
      ref
          .read(outputLanguageStoreProvider)
          .save(_outputLanguage)
          .catchError((Object _) {}),
    );
    action(_request());
  }
}
