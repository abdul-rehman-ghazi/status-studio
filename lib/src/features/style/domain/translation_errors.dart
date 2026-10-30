/// English needs ML Kit's language pack, and it couldn't be downloaded
/// (spec §8: "English needs a one-time download.").
class TranslationPackMissingException implements Exception {
  const TranslationPackMissingException(this.languageCode);

  final String languageCode;

  @override
  String toString() => 'TranslationPackMissingException: $languageCode';
}
