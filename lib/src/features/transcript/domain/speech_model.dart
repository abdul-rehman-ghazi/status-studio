/// The speech-to-text models the app offers (spec FR-12), smallest first.
/// Kept apart from whisper_ggml's own enum so only the Whisper data classes
/// import it.
enum SpeechModel { tiny, base, small, medium, large }

/// Used until the user picks another in Settings, which marks it
/// recommended.
const defaultSpeechModel = SpeechModel.small;
