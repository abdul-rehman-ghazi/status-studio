import 'package:flutter/foundation.dart';

/// How far a track's length may differ from the video's before it is
/// taken for another recording (spec FR-17).
const longestLengthGap = Duration(seconds: 10);

/// Share of the track's title words the video's title must contain.
const _titleOverlapNeeded = 0.6;

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// One song LRCLIB knows, with its synced lyrics when it has them.
@immutable
class LyricsCandidate {
  const LyricsCandidate({
    required this.trackName,
    required this.length,
    required this.syncedLyrics,
  });

  final String trackName;
  final Duration length;

  /// LRC text, or empty when LRCLIB has only plain lyrics (no times).
  final String syncedLyrics;
}

/// No song with synced lyrics matches the video (spec §8).
class LyricsNotFoundException implements Exception {
  const LyricsNotFoundException();

  @override
  String toString() => 'LyricsNotFoundException';
}

/// The candidate that is this video's song: synced, about as long as the
/// video, and named in its title; the closest in length wins. Throws
/// [LyricsNotFoundException] when none qualifies.
LyricsCandidate bestLyricsFor(
  List<LyricsCandidate> candidates, {
  required String videoTitle,
  required Duration videoLength,
}) {
  final titleWords = _wordsIn(videoTitle);
  final matching = candidates
      .where((candidate) => candidate.syncedLyrics.trim().isNotEmpty)
      .where(
        (candidate) =>
            _gap(candidate.length, videoLength) <= longestLengthGap &&
            _namedIn(candidate.trackName, titleWords),
      )
      .toList();
  if (matching.isEmpty) {
    throw const LyricsNotFoundException();
  }
  return matching.reduce(
    (best, next) =>
        _gap(next.length, videoLength) < _gap(best.length, videoLength)
        ? next
        : best,
  );
}

Duration _gap(Duration first, Duration second) => (first - second).abs();

bool _namedIn(String trackName, Set<String> titleWords) {
  final trackWords = _wordsIn(trackName);
  if (trackWords.isEmpty) {
    return false;
  }
  final shared = trackWords.where(titleWords.contains).length;
  return shared / trackWords.length >= _titleOverlapNeeded;
}

Set<String> _wordsIn(String text) => _word
    .allMatches(text.toLowerCase())
    .map((match) => match.group(0)!)
    .toSet();
