import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/stream_choice.dart';

StreamChoice video(int height, String container, {required int index}) =>
    StreamChoice(
      height: height,
      container: container,
      bitrate: height * 1000,
      index: index,
    );

StreamChoice audio(int bitrate, String container, {required int index}) =>
    StreamChoice(
      height: 0,
      container: container,
      bitrate: bitrate,
      index: index,
    );

void main() {
  test('picks_highest_mp4_at_or_below_cap', () {
    final streams = [
      video(1080, 'mp4', index: 0),
      video(720, 'webm', index: 1),
      video(720, 'mp4', index: 2),
      video(480, 'mp4', index: 3),
    ];

    expect(pickVideoStream(streams).index, 2);
  });

  test('prefers_mp4_over_webm_at_same_height', () {
    final streams = [video(480, 'webm', index: 0), video(480, 'mp4', index: 1)];

    expect(pickVideoStream(streams).index, 1);
  });

  test('falls_back_to_lowest_stream_above_cap', () {
    final streams = [
      video(1440, 'mp4', index: 0),
      video(1080, 'mp4', index: 1),
    ];

    expect(pickVideoStream(streams).index, 1);
  });

  test('falls_back_to_webm_when_no_mp4_exists', () {
    final streams = [
      video(720, 'webm', index: 0),
      video(360, 'webm', index: 1),
    ];

    expect(pickVideoStream(streams).index, 0);
  });

  test('picks_highest_bitrate_mp4_audio', () {
    final streams = [
      audio(160000, 'webm', index: 0),
      audio(128000, 'mp4', index: 1),
      audio(48000, 'mp4', index: 2),
    ];

    expect(pickAudioStream(streams).index, 1);
  });

  test('picks_webm_audio_when_no_mp4_exists', () {
    final streams = [audio(160000, 'webm', index: 0)];

    expect(pickAudioStream(streams).index, 0);
  });

  test('empty_list_throws_unavailable', () {
    expect(
      () => pickVideoStream(const []),
      throwsA(isA<VideoUnavailableException>()),
    );
  });

  test('empty_audio_list_throws_unavailable', () {
    expect(
      () => pickAudioStream(const []),
      throwsA(isA<VideoUnavailableException>()),
    );
  });

  test('prefers_h264_over_av1_at_same_height', () {
    const streams = [
      StreamChoice(
        height: 720,
        container: 'mp4',
        bitrate: 900000,
        index: 0,
        codec: 'av01.0.05M.08',
      ),
      StreamChoice(
        height: 720,
        container: 'mp4',
        bitrate: 800000,
        index: 1,
        codec: 'avc1.4d401f',
      ),
    ];

    expect(pickVideoStream(streams).index, 1);
  });

  test('vertical_video_quality_is_its_short_side', () {
    expect(qualityHeight(width: 720, height: 1280), 720);
  });

  test('prefers_original_audio_track_over_dub', () {
    const streams = [
      StreamChoice(
        height: 0,
        container: 'mp4',
        bitrate: 128000,
        index: 0,
        isDefaultTrack: false,
      ),
      StreamChoice(height: 0, container: 'mp4', bitrate: 128000, index: 1),
    ];

    expect(pickAudioStream(streams).index, 1);
  });

  test('script_audio_picks_lowest_bitrate_mp4', () {
    final streams = [
      audio(128000, 'mp4', index: 0),
      audio(50000, 'webm', index: 1),
      audio(48000, 'mp4', index: 2),
    ];

    expect(pickScriptAudioStream(streams).index, 2);
  });

  test('script_audio_falls_back_to_lowest_any_container', () {
    final streams = [
      audio(160000, 'webm', index: 0),
      audio(70000, 'webm', index: 1),
    ];

    expect(pickScriptAudioStream(streams).index, 1);
  });

  test('script_audio_prefers_original_track', () {
    const streams = [
      StreamChoice(
        height: 0,
        container: 'mp4',
        bitrate: 32000,
        index: 0,
        isDefaultTrack: false,
      ),
      StreamChoice(height: 0, container: 'mp4', bitrate: 48000, index: 1),
    ];

    expect(pickScriptAudioStream(streams).index, 1);
  });

  test('script_audio_empty_list_throws_unavailable', () {
    expect(
      () => pickScriptAudioStream(const []),
      throwsA(isA<VideoUnavailableException>()),
    );
  });
}
