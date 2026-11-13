import 'package:status_studio/src/features/source/domain/script_language.dart';

/// The chat model Update words and the lyrics' translation use (spec
/// FR-40, FR-37; the topic search used it until M53). One constant, so
/// the spike in §10 can swap it.
const topicModel = 'openai/gpt-oss-120b';

/// YouTube writes Urdu speech in Hindi script, so Urdu and Punjabi are
/// asked for in their Perso-Arabic script by name (§10 item 10).
String scriptNoteFor(ScriptLanguage output) => switch (output) {
  ScriptLanguage.urdu => ' in Urdu (Nastaliq) script, not Hindi script',
  ScriptLanguage.punjabi => ' in Shahmukhi script',
  _ => '',
};
