import 'package:status_studio/src/features/about/domain/app_version.dart';
import 'package:status_studio/src/features/about/domain/support_contact.dart';

enum SupportTopic {
  feedback('Feedback'),
  complaint('Complaint');

  const SupportTopic(this.label);

  final String label;
}

/// The phone and app a message is sent from, so a complaint arrives with
/// what's needed to reproduce it.
class DeviceDetails {
  const DeviceDetails({required this.appVersion, required this.phone});

  final AppVersion appVersion;

  /// "Xiaomi 2201117TG (Android 13, SDK 33)" or "iPhone 15 (iOS 18.1)".
  final String phone;
}

/// A feedback or complaint message, laid out as spec FR-31 says.
class SupportMessage {
  const SupportMessage({
    required this.topic,
    required this.text,
    required this.device,
  });

  final SupportTopic topic;
  final String text;
  final DeviceDetails device;

  String get subject => 'Status Studio ${topic.label.toLowerCase()}';

  String get body =>
      '${text.trim()}\n\n'
      '—\n'
      '${topic.label} · Status Studio ${device.appVersion.shown}\n'
      'Phone: ${device.phone}';

  /// WhatsApp has no subject, so it leads the text.
  String get whatsAppText => '$subject\n\n$body';

  /// Built by hand because `Uri(queryParameters:)` writes spaces as `+`,
  /// which mail apps show literally.
  Uri get emailUri => Uri.parse(
    'mailto:${SupportContact.email}'
    '?subject=${Uri.encodeComponent(subject)}'
    '&body=${Uri.encodeComponent(body)}',
  );

  Uri get whatsAppUri => Uri.parse(
    'https://wa.me/${SupportContact.whatsAppNumber}'
    '?text=${Uri.encodeComponent(whatsAppText)}',
  );
}
