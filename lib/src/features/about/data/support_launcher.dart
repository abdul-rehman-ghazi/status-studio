import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/about/domain/support_contact.dart';
import 'package:status_studio/src/features/about/domain/support_message.dart';
import 'package:url_launcher/url_launcher.dart';

enum ContactChannel { email, whatsApp, call }

/// No app on the phone opened the link: no mail app, or a tablet that
/// can't call.
class ContactAppMissingException implements Exception {
  const ContactAppMissingException(this.channel);

  final ContactChannel channel;
}

final supportLauncherProvider = Provider<SupportLauncher>(
  (ref) => const SupportLauncher(),
);

/// Hands a support message to the user's own app, which sends it; the app
/// sends nothing itself (spec FR-31).
class SupportLauncher {
  const SupportLauncher();

  Future<void> email(SupportMessage message) =>
      _open(message.emailUri, ContactChannel.email);

  Future<void> whatsApp(SupportMessage message) =>
      _open(message.whatsAppUri, ContactChannel.whatsApp);

  Future<void> call() => _open(
    Uri(scheme: 'tel', path: SupportContact.phoneNumber),
    ContactChannel.call,
  );

  Future<void> _open(Uri link, ContactChannel channel) async {
    final opened = await _launch(link);
    if (!opened) throw ContactAppMissingException(channel);
  }

  /// Android reports a link no app opens as a [PlatformException]
  /// (`ACTIVITY_NOT_FOUND`) and iOS as `false`.
  Future<bool> _launch(Uri link) async {
    try {
      return await launchUrl(link, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }
}
