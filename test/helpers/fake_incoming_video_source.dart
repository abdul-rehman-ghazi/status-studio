import 'dart:async';

import 'package:status_studio/src/features/source/data/incoming_video_source.dart';
import 'package:status_studio/src/features/source/domain/incoming_video.dart';

/// Delivers the videos a test shares, with [share], and the failures it
/// makes, with [fail].
class FakeIncomingVideoSource implements IncomingVideoSource {
  final _controller = StreamController<IncomingVideo>();

  @override
  Stream<IncomingVideo> get videos => _controller.stream;

  void share(IncomingVideo video) => _controller.add(video);

  void fail(Exception failure) => _controller.addError(failure);

  Future<void> close() => _controller.close();
}
