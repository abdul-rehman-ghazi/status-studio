import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';

/// Redraws a widget as [playhead] moves. The player reports its position
/// about ten times a second at best, so while playing a ticker redraws every
/// frame and the picture follows the time smoothly (spec FR-22).
class PlayheadRedraw {
  PlayheadRedraw({
    required TickerProvider vsync,
    required this.playhead,
    required this.isMounted,
    required this.redraw,
  }) {
    _ticker = vsync.createTicker((_) => _follow());
    playhead.addListener(_follow);
  }

  final ClipPlayhead playhead;
  final bool Function() isMounted;
  final void Function() redraw;
  late final Ticker _ticker;

  void dispose() {
    playhead.removeListener(_follow);
    _ticker.dispose();
  }

  void _follow() {
    if (playhead.isPlaying && !_ticker.isActive) {
      unawaited(_ticker.start());
    } else if (!playhead.isPlaying && _ticker.isActive) {
      _ticker.stop();
    }
    _redrawSafely();
  }

  // A report can arrive while the tree is building; draw after it then.
  void _redrawSafely() {
    if (!isMounted()) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _redrawSafely());
      return;
    }
    redraw();
  }
}
