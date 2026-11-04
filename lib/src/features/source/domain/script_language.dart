enum ScriptLanguage {
  auto('auto', 'Detect automatically'),
  urdu('ur', 'Urdu'),
  arabic('ar', 'Arabic'),
  punjabi('pa', 'Punjabi'),
  persian('fa', 'Persian'),
  hindi('hi', 'Hindi'),
  bengali('bn', 'Bengali'),
  english('en', 'English');

  const ScriptLanguage(this.whisperCode, this.label);

  final String whisperCode;
  final String label;
}

/// What a script asked for in [language] is called. An automatic one is
/// named after [detectedCode], the language found in it, e.g.
/// `Urdu (detected)`.
String scriptLanguageLabel(ScriptLanguage language, String? detectedCode) {
  if (language != ScriptLanguage.auto) {
    return language.label;
  }
  final detected = ScriptLanguage.values
      .where((candidate) => candidate.whisperCode == detectedCode)
      .firstOrNull;
  return detected == null
      ? 'Detected language'
      : '${detected.label} (detected)';
}
