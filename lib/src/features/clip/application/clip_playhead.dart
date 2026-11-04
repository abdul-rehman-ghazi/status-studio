import 'package:flutter/foundation.dart';

/// Where the clip player is, in video time, and a way to move it, shared
/// between the player and the lines list (spec FR-21).
///
/// The platform reports its position only about twice a second, so while
/// playing [position] adds the time since the last report. Tap to time needs
/// that finer reading.
class ClipPlayhead extends ChangeNotifier {
  ClipPlayhead({Duration Function()? clock})
    : _clock = clock ?? _stopwatchClock();

  final Duration Function() _clock;
  Duration _reportedPosition = Duration.zero;
  Duration _reportedAt = Duration.zero;
  var _isPlaying = false;
  Future<void> Function(Duration videoTime)? _seek;

  bool get isPlaying => _isPlaying;

  /// False until a player is attached, and while none is.
  bool get isReady => _seek != null;

  Duration get position {
    if (!_isPlaying) {
      return _reportedPosition;
    }
    return _reportedPosition + (_clock() - _reportedAt);
  }

  void report({required Duration position, required bool isPlaying}) {
    _reportedPosition = position;
    _reportedAt = _clock();
    _isPlaying = isPlaying;
    notifyListeners();
  }

  /// Called by a player when it is created; it does not notify, because
  /// players are created while the tree builds.
  void attach(Future<void> Function(Duration videoTime) seek) => _seek = seek;

  void detach() {
    _seek = null;
    _isPlaying = false;
  }

  Future<void> seekTo(Duration videoTime) async {
    final seek = _seek;
    if (seek == null) {
      throw StateError('The playhead was moved before a player was ready.');
    }
    await seek(videoTime);
  }
}

Duration Function() _stopwatchClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}
