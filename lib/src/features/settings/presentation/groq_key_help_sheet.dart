import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';

const _keysPage = 'console.groq.com/keys';

const _steps = [
  'Tap Copy link, then open your browser and paste it.',
  'Sign in with Google or your email. The free plan needs no card.',
  'Tap Create API Key. Give it any name, like "Status Studio", and tap '
      'Submit.',
  'Tap Copy next to the new key. It starts with gsk_. Groq shows it only '
      'once, so copy it now.',
  'Come back here, tap Paste, then Save.',
];

/// "How to get a free Groq key", written for people who have never seen
/// Groq's site (spec FR-12a).
Future<void> showGroqKeyHelp(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _GroqKeyHelpSheet(),
  );
}

class _GroqKeyHelpSheet extends StatefulWidget {
  const _GroqKeyHelpSheet();

  @override
  State<_GroqKeyHelpSheet> createState() => _GroqKeyHelpSheetState();
}

class _GroqKeyHelpSheetState extends State<_GroqKeyHelpSheet> {
  var _copied = false;

  /// The app doesn't open a browser itself, so the link goes on the
  /// clipboard.
  Future<void> _copyLink() async {
    await Clipboard.setData(const ClipboardData(text: _keysPage));
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to get a free Groq key',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const HintText(_keysPage),
            const SizedBox(height: 16),
            for (final (index, step) in _steps.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('${index + 1}. $step'),
              ),
            const SizedBox(height: 6),
            const HintText(
              'Free plan: about 2 hours of audio every hour, and 8 hours a '
              'day.',
            ),
            const SizedBox(height: 6),
            const HintText(
              'Keep the key private, like a password. You can delete it any '
              'time on the same Groq page.',
            ),
            const SizedBox(height: 16),
            if (_copied) const HintText('Link copied'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _copyLink,
                    child: const Text('Copy link'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
