import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// The published copy of spec §9.1 (M60), on the default branch.
final privacyPolicyUrl = Uri.parse(
  'https://github.com/abdul-rehman-ghazi/status-studio/blob/dev/PRIVACY.md',
);

/// No app on the phone opened the policy's link.
class NoBrowserException implements Exception {
  const NoBrowserException();
}

final privacyPolicyOpenerProvider = Provider<PrivacyPolicyOpener>(
  (ref) => const PrivacyPolicyOpener(),
);

/// Opens the privacy policy in the user's browser (spec FR-31).
class PrivacyPolicyOpener {
  const PrivacyPolicyOpener();

  Future<void> open() async {
    if (!await _launch()) throw const NoBrowserException();
  }

  /// Android reports a link no app opens as a [PlatformException]
  /// (`ACTIVITY_NOT_FOUND`) and iOS as `false`.
  Future<bool> _launch() async {
    try {
      return await launchUrl(
        privacyPolicyUrl,
        mode: LaunchMode.externalApplication,
      );
    } on PlatformException {
      return false;
    }
  }
}
