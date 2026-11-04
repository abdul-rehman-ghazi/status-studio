import 'dart:async';
import 'dart:io';

import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/style/data/frame_extractor.dart';
import 'package:status_studio/src/features/style/data/subject_detector.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';

/// Makes [frameCount] real files in a temp folder, so deleting them is seen.
class FakeFrameExtractor implements FrameExtractor {
  FakeFrameExtractor({this.frameCount = 8, this.failure});

  final int frameCount;
  final Exception? failure;
  Directory? made;
  FfmpegCancelHandle? handle;

  @override
  Future<SampledFrames> extract(
    ClipSource source,
    ClipRange clip,
    FfmpegCancelHandle cancel,
  ) async {
    handle = cancel;
    if (failure case final failure?) {
      throw failure;
    }
    final directory = made = Directory.systemTemp.createTempSync('follow_test');
    return SampledFrames(
      directory: directory,
      frames: [
        for (var i = 0; i < frameCount; i++)
          File('${directory.path}/frame$i.jpg')..writeAsBytesSync(const [1]),
      ],
      framesPerSecond: 4,
      sceneCuts: const [],
    );
  }
}

class FakeSubjectDetector implements SubjectDetector {
  FakeSubjectDetector({this.facesAt, this.failure});

  final List<SubjectBox> Function(int call)? facesAt;
  final Exception? failure;

  /// When set, each look waits for it.
  Completer<void>? gate;
  var calls = 0;
  var closed = false;

  @override
  Future<List<SubjectBox>> facesIn(File frame) async {
    final call = calls++;
    await gate?.future;
    if (failure case final failure?) {
      throw failure;
    }
    return facesAt?.call(call) ?? const [];
  }

  @override
  Future<void> close() async => closed = true;
}

const centredFace = SubjectBox(left: 0.45, top: 0.35, width: 0.1, height: 0.1);
