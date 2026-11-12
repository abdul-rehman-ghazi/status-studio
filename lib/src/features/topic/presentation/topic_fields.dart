import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';

const _presetLengths = [
  Duration(seconds: 15),
  Duration(seconds: 30),
  Duration(seconds: 60),
  Duration(seconds: 90),
];
const _shortestCustom = 5;
const _longestCustom = 300;

/// Topic, length and Find the moments under a read link (spec FR-36).
class TopicFields extends StatefulWidget {
  const TopicFields({required this.video, required this.onFind, super.key});

  final LinkedVideo video;
  final ValueChanged<TopicRequest> onFind;

  @override
  State<TopicFields> createState() => _TopicFieldsState();
}

class _TopicFieldsState extends State<TopicFields> {
  final _topicField = TextEditingController();
  var _length = const Duration(seconds: 60);

  @override
  void dispose() {
    _topicField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final custom = !_presetLengths.contains(_length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Topic'),
        TextField(
          controller: _topicField,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'What should the clip be about?',
          ),
        ),
        const SectionLabel('Length'),
        Wrap(
          spacing: 8,
          children: [
            for (final preset in _presetLengths)
              ChoiceChip(
                label: Text('${preset.inSeconds} s'),
                selected: _length == preset,
                onSelected: (_) => setState(() => _length = preset),
              ),
            ChoiceChip(
              label: Text(custom ? '${_length.inSeconds} s' : 'Custom'),
              selected: custom,
              onSelected: (_) => unawaited(_askCustomLength()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _topicField.text.trim().isEmpty ? null : _find,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Find the moments'),
        ),
      ],
    );
  }

  void _find() => widget.onFind(
    TopicRequest(
      video: widget.video,
      topic: _topicField.text.trim(),
      length: _length,
    ),
  );

  Future<void> _askCustomLength() async {
    final seconds = await showDialog<int>(
      context: context,
      builder: (context) => const _CustomLengthDialog(),
    );
    if (seconds != null && mounted) {
      setState(() => _length = Duration(seconds: seconds));
    }
  }
}

class _CustomLengthDialog extends StatefulWidget {
  const _CustomLengthDialog();

  @override
  State<_CustomLengthDialog> createState() => _CustomLengthDialogState();
}

class _CustomLengthDialogState extends State<_CustomLengthDialog> {
  final _secondsField = TextEditingController();

  @override
  void dispose() {
    _secondsField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = int.tryParse(_secondsField.text);
    final valid =
        seconds != null &&
        seconds >= _shortestCustom &&
        seconds <= _longestCustom;
    return AlertDialog(
      title: const Text('Clip length'),
      content: TextField(
        controller: _secondsField,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          hintText: 'Seconds, from 5 to 300',
          suffixText: 's',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: valid ? () => Navigator.of(context).pop(seconds) : null,
          child: const Text('Set'),
        ),
      ],
    );
  }
}
