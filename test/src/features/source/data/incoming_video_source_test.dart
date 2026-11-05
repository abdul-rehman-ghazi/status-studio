import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:status_studio/src/features/source/data/incoming_video_source.dart';
import 'package:status_studio/src/features/source/domain/incoming_video.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

import '../../../../helpers/fake_incoming_video_source.dart';

const channel = MethodChannel('status_studio/video_in');

Map<Object?, Object?> shareMessage({
  String path = '/files/incoming/1_clip.mp4',
  String displayName = 'clip.mp4',
  String mimeType = 'video/mp4',
}) => {'path': path, 'displayName': displayName, 'mimeType': mimeType};

Map<Object?, Object?> waitingShare() => {
  'method': 'incomingVideo',
  'arguments': shareMessage(),
};

const clip = IncomingVideo(
  path: '/files/incoming/1_clip.mp4',
  displayName: 'clip.mp4',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('incomingVideosFrom', () {
    late StreamController<Map<Object?, Object?>> messages;

    setUp(() => messages = StreamController());
    tearDown(() => messages.close());

    test('a_video_share_becomes_an_incoming_video', () async {
      final videos = incomingVideosFrom(messages.stream).toList();

      messages.add(shareMessage());
      await messages.close();

      expect(await videos, [clip]);
    });

    test('a_share_reported_twice_is_delivered_once', () async {
      final videos = incomingVideosFrom(messages.stream).toList();

      messages
        ..add(shareMessage())
        ..add(shareMessage());
      await messages.close();

      expect(await videos, [clip]);
    });

    test('two_different_videos_are_both_delivered', () async {
      final videos = incomingVideosFrom(messages.stream).toList();

      messages
        ..add(shareMessage())
        ..add(shareMessage(path: '/files/incoming/2_other.mp4'));
      await messages.close();

      expect((await videos).map((video) => video.path), [
        '/files/incoming/1_clip.mp4',
        '/files/incoming/2_other.mp4',
      ]);
    });

    test('a_share_that_is_not_a_video_is_ignored', () async {
      final videos = incomingVideosFrom(messages.stream).toList();

      messages.add(shareMessage(mimeType: 'image/jpeg'));
      await messages.close();

      expect(await videos, isEmpty);
    });

    test('a_share_without_a_path_is_ignored', () async {
      final videos = incomingVideosFrom(messages.stream).toList();

      messages.add({'displayName': 'clip.mp4', 'mimeType': 'video/mp4'});
      await messages.close();

      expect(await videos, isEmpty);
    });

    test('a_share_without_a_name_is_named_after_its_file', () async {
      final videos = incomingVideosFrom(messages.stream).toList();

      messages.add({
        'path': '/files/incoming/1_clip.mp4',
        'mimeType': 'video/mp4',
      });
      await messages.close();

      expect((await videos).single.displayName, '1_clip.mp4');
    });
  });

  group('PlatformIncomingVideoSource', () {
    late List<String> platformCalls;

    void platformHolds(List<Map<Object?, Object?>> waiting) {
      platformCalls = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        platformCalls.add(call.method);
        if (call.method == 'listen') return waiting;
        if (call.method == 'stopListening') return null;
        throw MissingPluginException();
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    Future<void> platformSends(String method, Object? arguments) async {
      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
    }

    test('a_share_that_launched_the_app_is_delivered_once', () async {
      platformHolds([waitingShare()]);
      final source = PlatformIncomingVideoSource();
      final received = <IncomingVideo>[];
      final subscription = source.videos.listen(received.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();

      expect(received, [clip]);
    });

    test('a_second_listener_does_not_throw_and_gets_later_shares', () async {
      platformHolds([]);
      final source = PlatformIncomingVideoSource();
      final first = <IncomingVideo>[];
      final second = <IncomingVideo>[];
      final firstSubscription = source.videos.listen(first.add);
      final secondSubscription = source.videos.listen(second.add);
      addTearDown(firstSubscription.cancel);
      addTearDown(secondSubscription.cancel);
      await pumpEventQueue();

      await platformSends('incomingVideo', shareMessage());
      await pumpEventQueue();

      expect(
        [first, second],
        [
          [clip],
          [clip],
        ],
      );
    });

    test(
      'the_last_listener_leaving_tells_the_platform_to_keep_shares',
      () async {
        platformHolds([]);
        final source = PlatformIncomingVideoSource();
        final subscription = source.videos.listen((_) {});
        await pumpEventQueue();

        await subscription.cancel();
        await pumpEventQueue();

        expect(platformCalls, ['listen', 'stopListening']);
      },
    );

    test('listening_again_asks_the_platform_for_kept_shares', () async {
      platformHolds([]);
      final source = PlatformIncomingVideoSource();
      final first = source.videos.listen((_) {});
      await pumpEventQueue();
      await first.cancel();
      await pumpEventQueue();

      final second = source.videos.listen((_) {});
      addTearDown(second.cancel);
      await pumpEventQueue();

      expect(platformCalls, ['listen', 'stopListening', 'listen']);
    });

    test('a_later_share_is_delivered_after_the_launch_share', () async {
      platformHolds([waitingShare()]);
      final source = PlatformIncomingVideoSource();
      final received = <IncomingVideo>[];
      final subscription = source.videos.listen(received.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await platformSends(
        'incomingVideo',
        shareMessage(path: '/files/incoming/2_other.mp4', displayName: 'o.mp4'),
      );
      await pumpEventQueue();

      expect(received.map((video) => video.displayName), ['clip.mp4', 'o.mp4']);
    });

    test(
      'a_failed_copy_with_no_space_is_an_insufficient_storage_error',
      () async {
        platformHolds([]);
        final source = PlatformIncomingVideoSource();
        final errors = <Object>[];
        final subscription = source.videos.listen((_) {}, onError: errors.add);
        addTearDown(subscription.cancel);
        await pumpEventQueue();

        await platformSends('incomingVideoFailed', {
          'code': 'no_space',
          'message': 'No space left on device',
        });
        await pumpEventQueue();

        expect(errors.single, isA<InsufficientStorageException>());
      },
    );

    test('a_failed_copy_for_any_other_reason_is_an_unreadable_video', () async {
      platformHolds([]);
      final source = PlatformIncomingVideoSource();
      final errors = <Object>[];
      final subscription = source.videos.listen((_) {}, onError: errors.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await platformSends('incomingVideoFailed', {
        'code': 'copy_failed',
        'message': 'Permission denied',
      });
      await pumpEventQueue();

      expect(errors.single, isA<VideoUnreadableException>());
    });

    test('a_platform_without_the_channel_delivers_no_videos', () async {
      final source = PlatformIncomingVideoSource();
      final received = <IncomingVideo>[];
      final subscription = source.videos.listen(received.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();

      expect(received, isEmpty);
    });
  });

  test('the_provider_can_be_replaced_by_a_fake_in_tests', () async {
    final fake = FakeIncomingVideoSource();
    final container = ProviderContainer(
      overrides: [incomingVideoSourceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    addTearDown(fake.close);

    final next = container.read(incomingVideoSourceProvider).videos.first;
    fake.share(clip);

    expect(await next, clip);
  });
}
