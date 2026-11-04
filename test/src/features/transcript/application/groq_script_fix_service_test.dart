import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/transcript/application/groq_script_fix_service.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/script_exchange.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

import '../../../../helpers/fixtures.dart';

Transcript scriptOf(int lineCount) => Transcript(
  languageCode: 'ur',
  lines: [
    for (var index = 0; index < lineCount; index++)
      TranscriptLine(
        index: index,
        text: 'line $index',
        start: Duration(seconds: index * 5),
        end: Duration(seconds: index * 5 + 4),
      ),
  ],
);

void main() {
  late List<String> prompts;

  GroqScriptFixService serviceReplying(String reply) {
    prompts = [];
    return GroqScriptFixService(
      askGroq: (prompt) async {
        prompts.add(prompt);
        return reply;
      },
    );
  }

  test('fix_sends_only_the_picked_lines_and_the_video_link', () async {
    final service = serviceReplying('3 | 00:10.00 | 00:14.00 | fixed 3');

    await service.fix(
      video: sampleVideo,
      transcript: scriptOf(10),
      selection: const RangeSelected(2, 4),
    );

    expect(prompts.single, contains('3 | 00:10.00 | 00:14.00 | line 2'));
    expect(prompts.single, isNot(contains('line 5')));
    expect(prompts.single, contains('https://youtu.be/dQw4w9WgXcQ'));
  });

  test('fix_returns_the_script_with_the_replied_text', () async {
    final service = serviceReplying('3 | 00:10.00 | 00:14.00 | fixed 3');

    final corrected = await service.fix(
      video: sampleVideo,
      transcript: scriptOf(10),
      selection: const RangeSelected(2, 4),
    );

    expect(corrected.transcript.lines[2].text, 'fixed 3');
    expect(corrected.changedLines, 1);
  });

  test('fix_rejects_more_than_thirty_lines_without_asking_groq', () async {
    final service = serviceReplying('');

    final attempt = service.fix(
      video: sampleVideo,
      transcript: scriptOf(mostLinesForGroq + 1),
      selection: const NoSelection(),
    );

    await expectLater(attempt, throwsA(isA<TooManyLinesForAiException>()));
    expect(prompts, isEmpty);
  });

  test('fix_rejects_a_reply_without_rows', () {
    final service = serviceReplying('Sorry, I cannot do that.');

    expect(
      service.fix(
        video: sampleVideo,
        transcript: scriptOf(10),
        selection: const NoSelection(),
      ),
      throwsA(isA<NoScriptRowsException>()),
    );
  });

  test('fix_passes_on_a_missing_key', () {
    final service = GroqScriptFixService(
      askGroq: (_) async => throw const NoGroqKeyException(),
    );

    expect(
      service.fix(
        video: sampleVideo,
        transcript: scriptOf(10),
        selection: const NoSelection(),
      ),
      throwsA(isA<NoGroqKeyException>()),
    );
  });
}
