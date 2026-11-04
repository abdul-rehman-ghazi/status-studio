import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/media_probe.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/export/application/media3_renderer.dart';
import 'package:status_studio/src/features/export/application/renderer.dart';
import 'package:status_studio/src/features/export/domain/render_errors.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

import '../../../../helpers/fixtures.dart';

const methods = MethodChannel('status_studio/render');
const events = EventChannel('status_studio/render/events');

class FixedProbe extends MediaProbe {
  const FixedProbe();

  @override
  Future<OutputSize> videoSize(String path) async =>
      const OutputSize(1920, 1080);
}

/// Native side stand-in: records calls and answers `start` with [script].
class FakeNative {
  FakeNative(this.script);

  final void Function(MockStreamHandlerEventSink sink) script;
  final calls = <MethodCall>[];
  MockStreamHandlerEventSink? sink;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger
      ..setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        if (call.method == 'start') {
          scheduleMicrotask(() => script(sink!));
        }
        return null;
      })
      ..setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (arguments, events) => sink = events,
        ),
      );
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(methods, null)
        ..setMockStreamHandler(events, null);
    });
  }
}

/// Waits until the renderer has called `start`: it writes files first, which
/// takes real time, so a fixed number of event-loop turns isn't enough.
Future<void> untilStarted(FakeNative native) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (native.calls.isEmpty && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void finishWithProgress(MockStreamHandlerEventSink sink) {
  sink
    ..success({'type': 'progress', 'value': 0.5})
    ..success({'type': 'done', 'path': '/files/reel.mp4'});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late Media3Renderer renderer;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('media3_renderer_test');
    final window = ClipWindow(
      start: pickedDraft.clip!.start - const Duration(seconds: 5),
      end: pickedDraft.clip!.end + const Duration(seconds: 5),
    );
    renderer = Media3Renderer(
      RenderServices(
        clipSourceFor: (draft) async => ClipSource(
          file: File('${folder.path}/clip.mp4'),
          offset: window.start,
          window: window,
        ),
        probe: const FixedProbe(),
        paintOverlay: (spec) async => Uint8List(4),
        outputDirectory: Future.value(folder),
      ),
    );
  });

  tearDown(() async {
    // A render cleans up just after its stream ends; let it finish first.
    await pumpEventQueue();
    await folder.delete(recursive: true);
  });

  test('start_sends_render_spec', () async {
    final native = FakeNative(finishWithProgress)..install();

    await renderer.render(pickedDraft).drain<void>();

    final spec = native.calls.single.arguments as Map<Object?, Object?>;
    expect(
      (spec['inputPath'], spec['clipStartMs'], spec['outputWidth']),
      ('${folder.path}/clip.mp4', 5000, 1080),
    );
  });

  test(
    'output_file_is_named_after_the_kalam_and_its_first_and_last_lines',
    () async {
      final native = FakeNative(finishWithProgress)..install();

      await renderer.render(pickedDraft).drain<void>();

      final spec = native.calls.single.arguments as Map<Object?, Object?>;
      expect(spec['outputPath'], '${folder.path}/Sample-علم_بڑی-وقت_کی.mp4');
    },
  );

  test('a_second_reel_with_the_same_name_gets_a_number', () async {
    File('${folder.path}/Sample-علم_بڑی-وقت_کی.mp4').writeAsStringSync('x');
    final native = FakeNative(finishWithProgress)..install();

    await renderer.render(pickedDraft).drain<void>();

    final spec = native.calls.single.arguments as Map<Object?, Object?>;
    expect(spec['outputPath'], '${folder.path}/Sample-علم_بڑی-وقت_کی-2.mp4');
  });

  test('progress_events_become_render_running', () async {
    FakeNative(finishWithProgress).install();

    final progress = await renderer.render(pickedDraft).first;

    expect((progress as RenderRunning).fraction, 0.5);
  });

  test('done_event_finishes_with_path', () async {
    FakeNative(finishWithProgress).install();

    final last = await renderer.render(pickedDraft).last;

    expect((last as RenderFinished).videoPath, '/files/reel.mp4');
  });

  test('native_error_surfaces_render_exception', () async {
    FakeNative(
      (sink) => sink.success({'type': 'error', 'message': 'codec failed'}),
    ).install();

    await expectLater(
      renderer.render(pickedDraft).drain<void>(),
      throwsA(isA<RenderFailedException>()),
    );
  });

  test('refused_start_surfaces_render_exception', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    FakeNative((_) {}).install();
    messenger.setMockMethodCallHandler(
      methods,
      (call) async => throw PlatformException(code: 'busy'),
    );

    await expectLater(
      renderer.render(pickedDraft).drain<void>(),
      throwsA(isA<RenderFailedException>()),
    );
  });

  test('cancel_invokes_native_cancel_and_deletes_partial', () async {
    final native = FakeNative((_) {})..install();
    final run = renderer.render(pickedDraft).listen((_) {});
    await untilStarted(native);
    final partial = File(
      (native.calls.single.arguments as Map<Object?, Object?>)['outputPath']!
          as String,
    )..writeAsStringSync('partial');

    await renderer.cancel();
    await run.cancel();

    expect((native.calls.last.method, partial.existsSync()), ('cancel', false));
  });

  List<String> overlays() => folder
      .listSync()
      .map((entry) => entry.path)
      .where((path) => path.contains('_overlay'))
      .toList();

  test('overlay_pngs_are_deleted_when_the_render_ends', () async {
    FakeNative(finishWithProgress).install();

    await renderer.render(pickedDraft).drain<void>();
    await pumpEventQueue();

    expect(overlays(), isEmpty);
  });

  test('overlay_pngs_stay_while_the_render_runs', () async {
    final native = FakeNative((_) {})..install();
    final run = renderer.render(pickedDraft).listen((_) {});
    await untilStarted(native);

    expect(overlays(), hasLength(4));
    await renderer.cancel();
    await run.cancel();
  });

  test('start_sends_one_timed_cue_per_caption_line', () async {
    final native = FakeNative(finishWithProgress)..install();

    await renderer.render(pickedDraft).drain<void>();

    final spec = native.calls.single.arguments as Map<Object?, Object?>;
    final cues = (spec['captionCues']! as List).cast<Map<Object?, Object?>>();
    expect(cues.map((cue) => (cue['startMs'], cue['endMs'])).toList(), [
      (0, 8600),
      (9400, 18000),
      (18800, 27400),
    ]);
  });

  test('overlay_png_is_deleted_when_start_is_refused', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    FakeNative((_) {}).install();
    messenger.setMockMethodCallHandler(
      methods,
      (call) async => throw PlatformException(code: 'busy'),
    );

    await renderer.render(pickedDraft).drain<void>().catchError((_) {});
    await pumpEventQueue();

    expect(overlays(), isEmpty);
  });

  test('cancel_deletes_partial_even_when_native_cancel_fails', () async {
    final native = FakeNative((_) {})..install();
    final run = renderer.render(pickedDraft).listen((_) {}, onError: (_) {});
    await untilStarted(native);
    final partial = File(
      (native.calls.single.arguments as Map<Object?, Object?>)['outputPath']!
          as String,
    )..writeAsStringSync('partial');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          methods,
          (call) async => throw PlatformException(code: 'cancel_failed'),
        );

    await renderer.cancel().catchError((_) {});
    await run.cancel();

    expect(partial.existsSync(), isFalse);
  });
}
