import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/data/groq_transcriber.dart';

class _FakeGroqClient extends GroqClient {
  _FakeGroqClient(this.replies) : super(apiKey: 'gsk_fake');

  final Map<String, List<GroqSegment>> replies;
  final languagesAsked = <String?>[];

  @override
  Future<List<GroqSegment>> transcribe(
    File piece, {
    required String? languageCode,
  }) async {
    languagesAsked.add(languageCode);
    return replies[piece.path]!;
  }
}

GroqSegment _segment(String text, {double noSpeech = 0.1}) => GroqSegment(
  from: const Duration(seconds: 1),
  to: const Duration(seconds: 2),
  text: text,
  noSpeechProbability: noSpeech,
);

void main() {
  final pieces = [File('a.m4a'), File('b.m4a')];

  List<ChunkWritten> written(List<ChunkEvent> events) =>
      events.whereType<ChunkWritten>().toList();

  test('lines_of_later_pieces_are_offset_by_the_piece_start', () async {
    final client = _FakeGroqClient({
      'a.m4a': [_segment('one')],
      'b.m4a': [_segment('two')],
    });

    final events = await GroqTranscriber(client)
        .transcribePieces(
          GroqTranscription(pieces: pieces, language: ScriptLanguage.english),
        )
        .toList();

    expect(written(events)[1].lines.single.start, const Duration(seconds: 91));
  });

  test('segments_above_the_no_speech_cutoff_are_dropped', () async {
    final client = _FakeGroqClient({
      'a.m4a': [_segment('music', noSpeech: 0.9), _segment('words')],
    });

    final events = await GroqTranscriber(client)
        .transcribePieces(
          GroqTranscription(
            pieces: [pieces.first],
            language: ScriptLanguage.english,
          ),
        )
        .toList();

    expect(written(events).single.lines.map((line) => line.text), ['words']);
  });

  test('automatic_language_sends_no_language_code', () async {
    final client = _FakeGroqClient({
      'a.m4a': [_segment('hi')],
    });

    await GroqTranscriber(client)
        .transcribePieces(
          GroqTranscription(
            pieces: [pieces.first],
            language: ScriptLanguage.auto,
          ),
        )
        .toList();

    expect(client.languagesAsked, [null]);
  });

  test('resuming_skips_finished_pieces_and_continues_numbering', () async {
    final client = _FakeGroqClient({
      'b.m4a': [_segment('two')],
    });

    final events = await GroqTranscriber(client)
        .transcribePieces(
          GroqTranscription(
            pieces: pieces,
            language: ScriptLanguage.english,
            completedPieces: 1,
            firstIndex: 5,
          ),
        )
        .toList();

    expect(written(events).single.lines.single.index, 5);
  });
}
