import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// How long the controls stay after playback starts or the last touch.
const controlsHideDelay = Duration(seconds: 3);

const _fade = Duration(milliseconds: 200);

/// A player's [controls] over its [picture] (spec M76): shown while paused,
/// faded out [controlsHideDelay] after playing starts or after the last
/// touch, and back on any touch on the player. The touch still reaches
/// what is under it, so a crop window can be dragged at once.
class AutoHidingControls extends StatefulWidget {
  const AutoHidingControls({
    required this.player,
    required this.picture,
    required this.controls,
    super.key,
  });

  final ValueListenable<VideoPlayerValue> player;
  final Widget picture;

  /// Laid out in a [Stack] over [picture]; [Positioned] works in it.
  final List<Widget> controls;

  @override
  State<AutoHidingControls> createState() => _AutoHidingControlsState();
}

class _AutoHidingControlsState extends State<AutoHidingControls> {
  var _visible = true;
  var _wasPlaying = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_onPlayerChanged);
    _onPlayerChanged();
  }

  @override
  void didUpdateWidget(AutoHidingControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.player, widget.player)) {
      return;
    }
    oldWidget.player.removeListener(_onPlayerChanged);
    widget.player.addListener(_onPlayerChanged);
    _onPlayerChanged();
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerChanged);
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reveal(),
      child: Stack(
        children: [
          widget.picture,
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: _fade,
              child: IgnorePointer(
                ignoring: !_visible,
                child: Stack(children: widget.controls),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _isPlaying => widget.player.value.isPlaying;

  /// Only a change between playing and paused counts: the player reports
  /// its position many times a second.
  void _onPlayerChanged() {
    final playing = _isPlaying;
    if (playing == _wasPlaying) {
      return;
    }
    _wasPlaying = playing;
    if (playing) {
      _hideLater();
      return;
    }
    _hideTimer?.cancel();
    _show();
  }

  void _reveal() {
    _show();
    if (_isPlaying) {
      _hideLater();
    }
  }

  void _show() {
    if (!_visible && mounted) setState(() => _visible = true);
  }

  void _hideLater() {
    _hideTimer?.cancel();
    _hideTimer = Timer(controlsHideDelay, () {
      if (mounted && _isPlaying) setState(() => _visible = false);
    });
  }
}
