import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/about/data/device_details_reader.dart';
import 'package:status_studio/src/features/about/data/support_launcher.dart';
import 'package:status_studio/src/features/about/domain/support_contact.dart';
import 'package:status_studio/src/features/about/domain/support_message.dart';

/// Feedback or a complaint by email or WhatsApp, with the device details
/// added, or a call (spec FR-31).
class SupportSection extends ConsumerStatefulWidget {
  const SupportSection({super.key});

  @override
  ConsumerState<SupportSection> createState() => _SupportSectionState();
}

class _SupportSectionState extends ConsumerState<SupportSection> {
  final _messageField = TextEditingController();
  var _topic = SupportTopic.feedback;

  @override
  void dispose() {
    _messageField.dispose();
    super.dispose();
  }

  Future<SupportMessage> _composeMessage() async {
    final device = await ref.read(deviceDetailsReaderProvider).read();
    return SupportMessage(
      topic: _topic,
      text: _messageField.text,
      device: device,
    );
  }

  Future<void> _sendByEmail() async {
    final message = await _composeMessage();
    await _reach(() => ref.read(supportLauncherProvider).email(message));
  }

  Future<void> _sendByWhatsApp() async {
    final message = await _composeMessage();
    await _reach(() => ref.read(supportLauncherProvider).whatsApp(message));
  }

  Future<void> _call() =>
      _reach(() => ref.read(supportLauncherProvider).call());

  Future<void> _reach(Future<void> Function() openContactApp) async {
    try {
      await openContactApp();
    } on ContactAppMissingException catch (missing) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_missingAppText(missing.channel))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Support'),
        const HintText(
          'Tell us what you like or what went wrong. Details of your phone '
          '(model, system, processor, memory, screen, network) and the app '
          'version are added to the message, so you can see them before you '
          'send.',
        ),
        const SizedBox(height: 12),
        SegmentedButton<SupportTopic>(
          segments: [
            for (final topic in SupportTopic.values)
              ButtonSegment(value: topic, label: Text(topic.label)),
          ],
          selected: {_topic},
          onSelectionChanged: (chosen) =>
              setState(() => _topic = chosen.single),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _messageField,
          minLines: 3,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Your message'),
        ),
        const SizedBox(height: 12),
        _ContactButtons(
          messageField: _messageField,
          actions: (
            email: () => unawaited(_sendByEmail()),
            whatsApp: () => unawaited(_sendByWhatsApp()),
            call: () => unawaited(_call()),
          ),
        ),
      ],
    );
  }
}

String _missingAppText(ContactChannel channel) => switch (channel) {
  ContactChannel.email =>
    'No email app found. Write to ${SupportContact.email}.',
  ContactChannel.whatsApp =>
    "Couldn't open WhatsApp. Message ${SupportContact.phoneNumberShown}.",
  ContactChannel.call =>
    "This device can't make calls. Call ${SupportContact.phoneNumberShown}.",
};

typedef _ContactActions = ({
  VoidCallback email,
  VoidCallback whatsApp,
  VoidCallback call,
});

/// Email and WhatsApp carry the message, so they wait for text; a call
/// carries nothing and is always on.
class _ContactButtons extends StatelessWidget {
  const _ContactButtons({required this.messageField, required this.actions});

  final TextEditingController messageField;
  final _ContactActions actions;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: messageField,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: hasText ? actions.email : null,
              icon: const Icon(Icons.email_outlined),
              label: const Text('Email'),
            ),
            OutlinedButton.icon(
              onPressed: hasText ? actions.whatsApp : null,
              icon: const Icon(Icons.chat_outlined),
              label: const Text('WhatsApp'),
            ),
            OutlinedButton.icon(
              onPressed: actions.call,
              icon: const Icon(Icons.call_outlined),
              label: const Text('Call'),
            ),
          ],
        );
      },
    );
  }
}
