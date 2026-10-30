import 'dart:io';

import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// Answers instantly with a sample video and placeholder files.
class FakeVideoSource implements VideoSource {
  const FakeVideoSource();

  @override
  Future<SourceVideo> fetchVideo(String videoId) async {
    return SourceVideo(
      videoId: videoId,
      title: 'Sample video',
      channel: 'Sample channel',
      duration: const Duration(minutes: 6, seconds: 48),
    );
  }

  @override
  Future<File> downloadScriptAudio(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  }) async {
    onProgress(1);
    return File('${video.videoId}-audio.m4a');
  }

  /// No captions, so pipelines built on this fake take the Whisper path.
  @override
  Future<Transcript> fetchCaptions(
    SourceVideo video,
    ScriptLanguage language,
  ) async => throw const NoCaptionTrackException();

  @override
  Future<StreamUrls> streamUrls(SourceVideo video) async {
    return StreamUrls(
      video: Uri.parse('https://example.com/${video.videoId}/video.mp4'),
      audio: Uri.parse('https://example.com/${video.videoId}/audio.m4a'),
      videoIsMp4: true,
      audioIsMp4: true,
    );
  }

  @override
  Future<File> prepareSourceVideo(
    SourceVideo video, {
    required void Function(double fraction) onProgress,
  }) async {
    onProgress(1);
    return File('${video.videoId}-source.mp4');
  }
}
