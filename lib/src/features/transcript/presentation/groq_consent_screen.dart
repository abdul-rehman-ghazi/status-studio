import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/screen_title.dart';
import 'package:status_studio/src/features/transcript/application/groq_consent_controller.dart';

const _points = [
  "To write the lyrics, and a linked video's script and its moments' "
      'words, Status Studio sends to Groq, a third-party AI service, using '
      'your own Groq key.',
  "What is sent: the video's sound, cleaned to one channel, in pieces; and, "
      "to update a moment's words or translate a linked clip's lyrics, the "
      'words of the script involved.',
  'What is not sent: the picture. Nothing goes to us: Status Studio has '
      'no server and no account.',
  "Groq's terms and privacy policy apply (groq.com). You can withdraw "
      'this any time in Settings.',
];

/// Asks once before anything is sent to Groq (spec FR-30). True when the
/// user agreed; the answer is then kept.
Future<bool> askForGroqConsent(BuildContext context) async {
  final agreed = await showDialog<bool>(
    context: context,
    builder: (_) => const _GroqConsentScreen(),
  );
  return agreed ?? false;
}

class _GroqConsentScreen extends ConsumerStatefulWidget {
  const _GroqConsentScreen();

  @override
  ConsumerState<_GroqConsentScreen> createState() => _GroqConsentScreenState();
}

class _GroqConsentScreenState extends ConsumerState<_GroqConsentScreen> {
  var _saving = false;

  Future<void> _agree() async {
    setState(() => _saving = true);
    await ref.read(groqConsentProvider.notifier).give();
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: const ScreenTitle('Send to Groq?'),
          automaticallyImplyLeading: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final point in _points)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(point),
              ),
            const HintText(
              'Without lyrics or a link, nothing leaves your phone and you '
              'need no key.',
            ),
          ],
        ),
        bottomNavigationBar: BottomAction(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => unawaited(_agree()),
                  child: const Text('Agree'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
