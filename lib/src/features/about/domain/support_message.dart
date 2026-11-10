import 'package:status_studio/src/features/about/domain/app_version.dart';
import 'package:status_studio/src/features/about/domain/support_contact.dart';

enum SupportTopic {
  feedback('Feedback'),
  complaint('Complaint');

  const SupportTopic(this.label);

  final String label;
}

class MemorySize {
  const MemorySize({required this.totalMegabytes, required this.freeMegabytes});

  final int totalMegabytes;
  final int freeMegabytes;

  /// "5.5 GB, 1.8 GB free".
  String get shown =>
      '${_gigabytes(totalMegabytes)}, ${_gigabytes(freeMegabytes)} free';

  static String _gigabytes(int megabytes) =>
      '${(megabytes / 1024).toStringAsFixed(1)} GB';
}

class ScreenSize {
  const ScreenSize({
    required this.widthPixels,
    required this.heightPixels,
    required this.pixelRatio,
  });

  final int widthPixels;
  final int heightPixels;
  final double pixelRatio;

  /// "1080 × 2400 px at 2.75×".
  String get shown =>
      '$widthPixels × $heightPixels px at ${_trimmed(pixelRatio)}×';

  static String _trimmed(double ratio) =>
      ratio.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// The phone and app a message is sent from, so a complaint arrives with
/// what's needed to reproduce it (spec FR-31).
class DeviceDetails {
  const DeviceDetails({
    required this.appVersion,
    required this.phone,
    required this.system,
    required this.processor,
    required this.memory,
    required this.screen,
    required this.network,
  });

  final AppVersion appVersion;

  /// "Xiaomi 2201117TG" or "iPhone 15".
  final String phone;

  /// "Android 13 (SDK 33)" or "iOS 18.1".
  final String system;

  /// "QTI SM6225 · arm64-v8a", or the model code on iOS ("iPhone15,4").
  final String processor;

  final MemorySize memory;
  final ScreenSize screen;

  /// "Wi-Fi", "Mobile data", "None": the connection type, which doesn't
  /// prove the internet is reachable.
  final String network;
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
      'Phone: ${device.phone}\n'
      'System: ${device.system}\n'
      'Processor: ${device.processor}\n'
      'RAM: ${device.memory.shown}\n'
      'Screen: ${device.screen.shown}\n'
      'Network: ${device.network}';

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
