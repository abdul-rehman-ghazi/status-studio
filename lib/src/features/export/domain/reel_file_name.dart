import 'package:status_studio/src/features/lyrics/domain/lyrics_query.dart';

const _wordsPerPart = 2;
const _fallbackStem = 'reel';

// Everything but letters, marks and digits: it removes characters that are
// illegal in file names, and punctuation such as `،` and `۔`.
final _notWordCharacter = RegExp(r'[^\p{L}\p{M}\p{N}]', unicode: true);

/// The exported file's name without `.mp4`, from the video's title and the
/// caption: `{kalam 2 words}-{first line 2 words}-{last line 2 words}`
/// (spec FR-9). Words are joined by `_`. A part with no words is left out.
String reelFileStem({required String videoTitle, required String captionText}) {
  final lines = captionText
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final parts = [
    _firstWords(lyricsQueryFor(videoTitle)),
    if (lines.isNotEmpty) _firstWords(lines.first),
    if (lines.isNotEmpty) _firstWords(lines.last),
  ].where((part) => part.isNotEmpty);
  return parts.isEmpty ? _fallbackStem : parts.join('-');
}

String _firstWords(String text) => text
    .split(RegExp(r'\s+'))
    .map((word) => word.replaceAll(_notWordCharacter, ''))
    .where((word) => word.isNotEmpty)
    .take(_wordsPerPart)
    .join('_');
