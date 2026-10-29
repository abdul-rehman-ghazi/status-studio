import 'package:flutter/foundation.dart';

@immutable
class TranscriptLine {
  const TranscriptLine({
    required this.index,
    required this.text,
    required this.start,
    required this.end,
  });

  final int index;
  final String text;
  final Duration start;
  final Duration end;

  TranscriptLine copyWith({
    int? index,
    String? text,
    Duration? start,
    Duration? end,
  }) {
    return TranscriptLine(
      index: index ?? this.index,
      text: text ?? this.text,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TranscriptLine &&
      other.index == index &&
      other.text == text &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(index, text, start, end);
}

@immutable
class Transcript {
  const Transcript({required this.languageCode, required this.lines});

  /// Whisper language code (`ur`, `ar`, …), or `und` when undetermined.
  final String languageCode;
  final List<TranscriptLine> lines;

  Transcript copyWith({String? languageCode, List<TranscriptLine>? lines}) {
    return Transcript(
      languageCode: languageCode ?? this.languageCode,
      lines: lines ?? this.lines,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Transcript &&
      other.languageCode == languageCode &&
      listEquals(other.lines, lines);

  @override
  int get hashCode => Object.hash(languageCode, Object.hashAll(lines));
}
