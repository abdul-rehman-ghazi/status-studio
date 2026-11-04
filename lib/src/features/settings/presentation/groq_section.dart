import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/settings/application/groq_settings_controller.dart';
import 'package:status_studio/src/features/settings/presentation/groq_key_help_sheet.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';

/// What the last Save found, shown under the key field.
sealed class _KeyCheck {
  const _KeyCheck();
}

class _Checking extends _KeyCheck {
  const _Checking();
}

class _Failed extends _KeyCheck {
  const _Failed(this.message);

  final String message;
}

/// The Groq key that writes every script without captions (spec FR-12a).
class GroqSection extends ConsumerStatefulWidget {
  const GroqSection({super.key});

  @override
  ConsumerState<GroqSection> createState() => _GroqSectionState();
}

class _GroqSectionState extends ConsumerState<GroqSection> {
  final _field = TextEditingController();
  var _showKey = false;
  _KeyCheck? _check;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text case final text?) {
      _field.text = text.trim();
    }
  }

  Future<void> _save() async {
    setState(() => _check = const _Checking());
    try {
      await ref.read(groqKeySavedProvider.notifier).saveKey(_field.text);
      _field.clear();
      _setCheck(null);
    } on GroqKeyRejectedException {
      _setCheck(const _Failed("Groq didn't accept this key."));
    } on Exception catch (error) {
      _setCheck(_Failed(errorMessageFor(error)));
    }
  }

  void _setCheck(_KeyCheck? check) {
    if (mounted) {
      setState(() => _check = check);
    }
  }

  Future<void> _remove() async {
    await ref.read(groqKeySavedProvider.notifier).removeKey();
    _setCheck(null);
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = ref.watch(groqKeySavedProvider).value ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading(),
        const HintText(
          'Writes the script when a video has no captions. Your video\'s '
          'audio is sent to Groq, which uses about as much data again as '
          "downloading it. Groq's terms apply.",
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _field,
          obscureText: !_showKey,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: hasKey ? '••••••••••••' : 'gsk_…',
          ),
        ),
        _KeyButtons(
          field: _field,
          showingKey: _showKey,
          hasKey: hasKey,
          checking: _check is _Checking,
          actions: (
            paste: () => unawaited(_paste()),
            toggleShow: () => setState(() => _showKey = !_showKey),
            save: () => unawaited(_save()),
            remove: () => unawaited(_remove()),
          ),
        ),
        _status(context, hasKey),
      ],
    );
  }

  Widget _status(BuildContext context, bool hasKey) {
    final errorColor = Theme.of(context).colorScheme.error;
    return switch (_check) {
      _Checking() => const HintText('Checking the key…'),
      _Failed(:final message) => Text(
        message,
        style: TextStyle(color: errorColor),
      ),
      null when hasKey => const HintText('Key works'),
      null => const SizedBox.shrink(),
    };
  }
}

class _Heading extends StatelessWidget {
  const _Heading();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Groq API key',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        IconButton(
          icon: const Icon(Icons.info_outline, size: 20),
          tooltip: 'How to get a free Groq key',
          onPressed: () => unawaited(showGroqKeyHelp(context)),
        ),
      ],
    );
  }
}

typedef _KeyActions = ({
  VoidCallback paste,
  VoidCallback toggleShow,
  VoidCallback save,
  VoidCallback remove,
});

class _KeyButtons extends StatelessWidget {
  const _KeyButtons({
    required this.field,
    required this.showingKey,
    required this.hasKey,
    required this.checking,
    required this.actions,
  });

  final TextEditingController field;
  final bool showingKey;
  final bool hasKey;
  final bool checking;
  final _KeyActions actions;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: field,
      builder: (context, value, _) => Wrap(
        spacing: 8,
        children: [
          TextButton(onPressed: actions.paste, child: const Text('Paste')),
          TextButton(
            onPressed: actions.toggleShow,
            child: Text(showingKey ? 'Hide' : 'Show'),
          ),
          FilledButton(
            onPressed: value.text.trim().isEmpty || checking
                ? null
                : actions.save,
            child: const Text('Save'),
          ),
          if (hasKey)
            TextButton(onPressed: actions.remove, child: const Text('Remove')),
        ],
      ),
    );
  }
}
