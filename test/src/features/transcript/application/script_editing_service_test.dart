import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/application/script_editing_service.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';

import '../../../../helpers/fixtures.dart';

void main() {
  late Directory folder;
  late TranscriptStore store;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('script_editing_test');
    store = TranscriptStore(folder, clock: DateTime.now);
  });

  tearDown(() => folder.delete(recursive: true));

  test('corrected_script_is_the_one_that_reopens', () async {
    const key = TranscriptKey(
      videoId: 'dQw4w9WgXcQ',
      language: ScriptLanguage.auto,
    );
    await store.save(
      key,
      SavedTranscript(
        transcript: fixture,
        source: groqSource,
        savedAt: DateTime(2026),
      ),
    );
    final corrected = fixture.copyWith(lines: fixture.lines.sublist(0, 1));

    await ScriptEditingService(
      store: Future.value(store),
      clock: () => DateTime(2026, 6),
    ).saveCorrected(sampleVideo, ScriptLanguage.auto, corrected);

    final reopened = await store.load(key);
    expect((reopened.source, reopened.transcript), (editedSource, corrected));
  });
}
