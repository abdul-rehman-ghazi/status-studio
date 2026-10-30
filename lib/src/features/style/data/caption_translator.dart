import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:status_studio/src/features/style/domain/translation_errors.dart';

/// Turns a caption into English for the English variant (spec FR-7).
abstract interface class CaptionTranslator {
  /// Whether [languageCode] (ISO 639-1) can be translated to English.
  bool supports(String languageCode);

  /// Throws [TranslationPackMissingException] when the language pack isn't
  /// on the phone and can't be downloaded.
  Future<String> toEnglish(String text, String languageCode);
}

/// ML Kit on-device translation. Packs download once, then work offline.
class MlKitCaptionTranslator implements CaptionTranslator {
  const MlKitCaptionTranslator();

  @override
  bool supports(String languageCode) =>
      languageCode != TranslateLanguage.english.bcpCode &&
      TranslateLanguage.values.any(
        (language) => language.bcpCode == languageCode,
      );

  @override
  Future<String> toEnglish(String text, String languageCode) async {
    final source = TranslateLanguage.values.firstWhere(
      (language) => language.bcpCode == languageCode,
      orElse: () => throw ArgumentError.value(languageCode, 'languageCode'),
    );
    await _ensurePack(source);
    await _ensurePack(TranslateLanguage.english);
    final translator = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: TranslateLanguage.english,
    );
    try {
      // Line by line, so the caption keeps its line breaks.
      final lines = <String>[];
      for (final line in text.split('\n')) {
        lines.add(
          line.trim().isEmpty ? line : await translator.translateText(line),
        );
      }
      return lines.join('\n');
    } finally {
      await translator.close();
    }
  }

  Future<void> _ensurePack(TranslateLanguage language) async {
    final packs = OnDeviceTranslatorModelManager();
    if (await packs.isModelDownloaded(language.bcpCode)) {
      return;
    }
    try {
      // Captions are short; the pack is about 30 MB, so mobile data is
      // allowed rather than leaving English unusable away from Wi-Fi.
      final downloaded = await packs.downloadModel(
        language.bcpCode,
        isWifiRequired: false,
      );
      if (!downloaded) {
        throw TranslationPackMissingException(language.bcpCode);
      }
    } on TranslationPackMissingException {
      rethrow;
    } on Exception {
      throw TranslationPackMissingException(language.bcpCode);
    }
  }
}

final captionTranslatorProvider = Provider<CaptionTranslator>(
  (ref) => const MlKitCaptionTranslator(),
);
