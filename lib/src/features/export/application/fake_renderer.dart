import 'package:status_studio/src/features/export/application/renderer.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';

const _stepCount = 25;

/// Counts from 0 to 1 in 25 steps (about three seconds), then finishes.
class FakeRenderer implements Renderer {
  const FakeRenderer({this.step = const Duration(milliseconds: 120)});

  final Duration step;

  @override
  Stream<RenderProgress> render(ReelDraft draft) {
    // Stream.periodic cancels its timer when the listener cancels.
    return Stream<RenderProgress>.periodic(
      step,
      _progressAt,
    ).take(_stepCount + 1);
  }

  @override
  Future<void> cancel() async {}
}

RenderProgress _progressAt(int tick) {
  if (tick < _stepCount) {
    return RenderRunning((tick + 1) / _stepCount);
  }
  return const RenderFinished('fake.mp4');
}
