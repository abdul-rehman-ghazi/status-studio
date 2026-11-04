// Brackets and what is inside them: "(Official Video)", "[HD]", "【MV】".
final _bracketed = RegExp(r'\([^)]*\)|\[[^\]]*\]|【[^】]*】');

// Words YouTube titles add that no song title contains.
final _noise = RegExp(
  r'\b(official|lyrical|lyrics?|video|audio|music|full song|hd|4k|mv|visualizer)\b',
  caseSensitive: false,
);

/// The words to search LRCLIB for, from a YouTube [videoTitle]: brackets,
/// "Official Video"-style words and anything after a `|` removed.
String lyricsQueryFor(String videoTitle) {
  final beforeBar = videoTitle.split('|').first;
  return beforeBar
      .replaceAll(_bracketed, ' ')
      .replaceAll(_noise, ' ')
      .replaceAll(RegExp(r'[-–—_]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
