import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// Transcript lines merged into a stretch of at least five seconds (spec
/// FR-36). Cuts are runs of whole blocks, so none starts or stops mid-line,
/// and fewer, longer numbered rows cost fewer tokens than raw captions.
@immutable
class TranscriptBlock {
  const TranscriptBlock({
    required this.number,
    required this.start,
    required this.end,
    required this.text,
  });

  factory TranscriptBlock.fromJson(Map<String, Object?> json) =>
      TranscriptBlock(
        number: json['n']! as int,
        start: Duration(milliseconds: json['startMs']! as int),
        end: Duration(milliseconds: json['endMs']! as int),
        text: json['text']! as String,
      );

  /// Its position in the transcript, from 0; what Groq names it by.
  final int number;
  final Duration start;
  final Duration end;
  final String text;

  Map<String, Object?> toJson() => {
    'n': number,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'text': text,
  };

  /// How the block is written for Groq: its number, its start in whole
  /// seconds and its text, on one line.
  String get promptRow => '$number|${start.inSeconds}|$text';

  @override
  bool operator ==(Object other) =>
      other is TranscriptBlock &&
      other.number == number &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(number, start, end, text);
}

const _shortestBlock = Duration(seconds: 5);

/// Merges [lines] in order: a block ends at the first line end at least
/// five seconds after the block's start.
List<TranscriptBlock> blocksFromLines(List<TranscriptLine> lines) {
  final blocks = <TranscriptBlock>[];
  var pending = <TranscriptLine>[];
  for (final line in lines) {
    pending.add(line);
    if (line.end - pending.first.start >= _shortestBlock) {
      blocks.add(_blockOf(pending, blocks.length));
      pending = [];
    }
  }
  if (pending.isNotEmpty) {
    blocks.add(_blockOf(pending, blocks.length));
  }
  return blocks;
}

TranscriptBlock _blockOf(List<TranscriptLine> lines, int number) =>
    TranscriptBlock(
      number: number,
      start: lines.first.start,
      end: lines.last.end,
      text: lines.map((line) => line.text.trim()).join(' '),
    );

/// Hindi-script captions measured about 5 UTF-8 bytes a token (§10 item
/// 11), Latin text about 4, so a part is 4,000 to 5,000 tokens and it and
/// its reply fit in a minute of Groq's free plan (8,000 tokens).
const partBudgetBytes = 20000;

/// [blocks] split into parts of at most [partBudgetBytes] prompt bytes; a
/// block bigger than that is a part on its own.
List<List<TranscriptBlock>> partsOf(List<TranscriptBlock> blocks) {
  final parts = <List<TranscriptBlock>>[];
  var part = <TranscriptBlock>[];
  var partBytes = 0;
  for (final block in blocks) {
    final bytes = utf8.encode(block.promptRow).length + 1;
    if (part.isNotEmpty && partBytes + bytes > partBudgetBytes) {
      parts.add(part);
      part = [];
      partBytes = 0;
    }
    part.add(block);
    partBytes += bytes;
  }
  if (part.isNotEmpty) {
    parts.add(part);
  }
  return parts;
}
