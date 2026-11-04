import 'dart:io';
import 'dart:ui';

import 'package:video_player/video_player.dart';

/// A player that never touches the platform; it only moves its value.
class FakeVideoPlayerController extends VideoPlayerController {
  FakeVideoPlayerController({this.frameSize = const Size(1280, 720)})
    : super.file(File('fake.mp4'));

  final Size frameSize;

  var disposed = false;

  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(minutes: 6, seconds: 48),
      size: frameSize,
    );
  }

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> seekTo(Duration position) async =>
      value = value.copyWith(position: position);

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

VideoPlayerController fakePlayerFactory(File source) =>
    FakeVideoPlayerController();

/// Hands out fake players and remembers them for assertions.
class RecordingPlayerFactory {
  final created = <FakeVideoPlayerController>[];

  VideoPlayerController call(File source) {
    final player = FakeVideoPlayerController();
    created.add(player);
    return player;
  }
}

/// A player whose file can't be opened, like an unsupported codec.
class BrokenVideoPlayerController extends FakeVideoPlayerController {
  @override
  Future<void> initialize() async =>
      throw const FormatException('unsupported codec');
}

VideoPlayerController brokenPlayerFactory(File source) =>
    BrokenVideoPlayerController();

/// A player of a vertical video, like a Short.
VideoPlayerController portraitPlayerFactory(File source) =>
    FakeVideoPlayerController(frameSize: const Size(720, 1280));
