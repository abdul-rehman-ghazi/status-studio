import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/application/fake_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';

import '../../../../helpers/fixtures.dart';

void main() {
  test('fake_pipeline_finishes_with_nine_lines', () async {
    const pipeline = FakeScriptPipeline(step: Duration.zero);

    final last = await pipeline.run(sampleVideo, ScriptLanguage.auto).last;

    expect((last.stage, last.transcript.lines.length), (ScriptStage.done, 9));
  });

  test('fixture_line_three_ends_at_48_8_seconds', () {
    expect(sampleTranscript.lines[3].end, const Duration(milliseconds: 48800));
  });
}
