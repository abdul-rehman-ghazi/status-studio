import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const channel = MethodChannel('status_studio/ytdlp');

PlatformException ytDlpFailure(String stderr) =>
    PlatformException(code: 'ytdlp_failed', message: stderr);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void answer(Object? Function(MethodCall call) reply) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => reply(call));
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }

  test('private_video_is_unavailable', () {
    final mapped = mapYtDlpError(
      ytDlpFailure(
        "ERROR: [youtube] abc: Private video. Sign in if you've been granted "
        'access to this video',
      ),
    );

    expect(mapped, isA<VideoUnavailableException>());
  });

  test('age_restricted_video_is_unavailable', () {
    final mapped = mapYtDlpError(
      ytDlpFailure('ERROR: [youtube] abc: Sign in to confirm your age.'),
    );

    expect(mapped, isA<VideoUnavailableException>());
  });

  test('dns_failure_is_offline', () {
    final mapped = mapYtDlpError(
      ytDlpFailure(
        'ERROR: [youtube] abc: Unable to download API page: <urlopen error '
        '[Errno 7] No address associated with hostname>',
      ),
    );

    expect(mapped, isA<OfflineException>());
  });

  test('unknown_error_means_youtube_changed', () {
    final mapped = mapYtDlpError(
      ytDlpFailure(
        'ERROR: [youtube] abc: Failed to extract any player response',
      ),
    );

    expect(mapped, isA<YouTubeChangedException>());
  });

  test('quick_video_info_decodes_the_channel_json', () async {
    answer(
      (call) => call.method == 'quickVideoInfo' && call.arguments == 'abc'
          ? '{"id": "abc", "title": "A video"}'
          : null,
    );

    final info = await const PlatformYtDlp().quickVideoInfo('abc');

    expect(info['title'], 'A video');
  });

  test('channel_failure_is_mapped', () async {
    answer((call) => throw ytDlpFailure('ERROR: Video unavailable'));

    await expectLater(
      const PlatformYtDlp().videoInfo('abc'),
      throwsA(isA<VideoUnavailableException>()),
    );
  });

  test('update_reports_whether_it_changed_anything', () async {
    answer((call) => 'up_to_date');

    expect(await const PlatformYtDlp().update(), YtDlpUpdate.upToDate);
  });
}
