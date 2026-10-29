import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/export/application/fake_renderer.dart';
import 'package:status_studio/src/features/export/application/renderer.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';

void main() {
  test('fake_renderer_finishes_with_video_path', () async {
    const renderer = FakeRenderer(step: Duration.zero);

    final last = await renderer.render(const ReelDraft()).last;

    expect(last, isA<RenderFinished>());
  });
}
