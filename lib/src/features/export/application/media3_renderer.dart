import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:status_studio/src/core/ffmpeg/media_probe.dart';
import 'package:status_studio/src/features/export/application/renderer.dart';
import 'package:status_studio/src/features/export/domain/overlay_layout.dart';
import 'package:status_studio/src/features/export/domain/render_errors.dart';
import 'package:status_studio/src/features/export/domain/render_spec.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/data/io_error_mapping.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

const _methods = MethodChannel('status_studio/render');
const _events = EventChannel('status_studio/render/events');

/// What the renderer needs from the rest of the app, in one value.
class RenderServices {
  const RenderServices({
    required this.clipSourceFor,
    required this.probe,
    required this.paintOverlay,
    required this.outputDirectory,
  });

  /// The downloaded clip covering the draft's clip (FR-15).
  final Future<ClipSource> Function(ReelDraft draft) clipSourceFor;
  final MediaProbe probe;
  final Future<Uint8List> Function(OverlaySpec spec) paintOverlay;

  /// Where finished reels are written.
  final Future<Directory> outputDirectory;
}

/// Renders through the Kotlin Media3 Transformer on `status_studio/render`
/// (spec §5, FR-9).
class Media3Renderer implements Renderer {
  Media3Renderer(this.services);

  final RenderServices services;

  /// The file being written, deleted if the render is cancelled.
  File? _rendering;

  /// Built on a controller rather than `async*`, so cancelling the stream
  /// returns at once instead of waiting for the native render to end.
  @override
  Stream<RenderProgress> render(ReelDraft draft) {
    final run = _RenderRun();
    run.progress.onListen = () {
      unawaited(_begin(draft, run));
    };
    run.progress.onCancel = () {
      unawaited(run.stopListening());
    };
    return run.progress.stream;
  }

  Future<void> _begin(ReelDraft draft, _RenderRun run) async {
    try {
      final spec = await _specFor(draft, run);
      if (!run.progress.hasListener) {
        return;
      }
      _rendering = File(spec['outputPath']! as String);
      // Listening before `start`, so no event is missed.
      run.events = _events.receiveBroadcastStream().listen(
        (event) => _forward(event, run.progress),
        onError: (Object error) => _fail(run.progress, '$error'),
      );
      await _methods.invokeMethod<void>('start', spec);
    } on Object catch (error) {
      _failWith(run.progress, error);
    } finally {
      // Kotlin decodes the overlay inside `start`, so once `start` has
      // returned (or the render never started) the PNG is no longer needed.
      await run.deleteOverlay();
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _methods.invokeMethod<void>('cancel');
    } finally {
      final partial = _rendering;
      _rendering = null;
      if (partial != null && await partial.exists()) {
        await partial.delete();
      }
    }
  }

  Future<Map<String, Object?>> _specFor(ReelDraft draft, _RenderRun run) async {
    final clip = draft.clip;
    if (clip == null) {
      throw StateError('Export started without a clip.');
    }
    final source = await services.clipSourceFor(draft);
    final sourceSize = await services.probe.videoSize(source.file.path);
    final folder = await services.outputDirectory;
    await folder.create(recursive: true);
    final name = 'reel_${DateTime.now().millisecondsSinceEpoch}';
    final overlay = File('${folder.path}/${name}_overlay.png');
    run.overlay = overlay;
    await overlay.writeAsBytes(
      await services.paintOverlay(
        OverlaySpec(
          output: outputSizeFor(draft.frame, sourceSize),
          caption: draft.caption,
        ),
      ),
    );
    return renderSpecFor(
      RenderJob(
        source: source,
        clip: clip,
        frame: draft.frame,
        sourceSize: sourceSize,
        overlayPath: overlay.path,
        outputPath: '${folder.path}/$name.mp4',
      ),
    );
  }

  void _forward(Object? event, StreamController<RenderProgress> progress) {
    if (event is! Map) {
      _fail(progress, 'Unexpected render event $event.');
      return;
    }
    switch (event['type']) {
      case 'progress':
        progress.add(RenderRunning((event['value']! as num).toDouble()));
      case 'done':
        _rendering = null;
        progress.add(RenderFinished(event['path']! as String));
        unawaited(progress.close());
      case _:
        _fail(progress, '${event['message']}');
    }
  }

  void _fail(StreamController<RenderProgress> progress, String reason) =>
      _failWith(progress, RenderFailedException(reason));

  /// A full disk keeps its own message; anything else is a failed render.
  void _failWith(StreamController<RenderProgress> progress, Object error) {
    if (progress.isClosed) {
      return;
    }
    progress.addError(switch (mapIoError(error)) {
      final InsufficientStorageException full => full,
      final RenderFailedException failed => failed,
      _ => RenderFailedException('$error'),
    });
    unawaited(progress.close());
  }
}

/// One render's stream, its native event subscription and its overlay PNG.
class _RenderRun {
  final progress = StreamController<RenderProgress>();
  StreamSubscription<Object?>? events;
  File? overlay;

  Future<void> stopListening() async => events?.cancel();

  Future<void> deleteOverlay() async {
    final written = overlay;
    overlay = null;
    try {
      await written?.delete();
    } on PathNotFoundException {
      // Never written, or already gone: nothing to clean up.
    }
  }
}
