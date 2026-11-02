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
