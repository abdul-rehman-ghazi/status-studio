import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/export/application/fake_renderer.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';

sealed class RenderProgress {
  const RenderProgress();
}

class RenderRunning extends RenderProgress {
  const RenderRunning(this.fraction);

  /// Share of the clip duration processed, from 0 to 1.
  final double fraction;
}

class RenderFinished extends RenderProgress {
  const RenderFinished(this.videoPath);

  final String videoPath;
}

abstract interface class Renderer {
  Stream<RenderProgress> render(ReelDraft draft);

  Future<void> cancel();
}

final rendererProvider = Provider<Renderer>((ref) => const FakeRenderer());
