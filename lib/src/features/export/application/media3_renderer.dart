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
  _RenderRun? _current;

  /// Built on a controller rather than `async*`, so cancelling the stream
  /// returns at once instead of waiting for the native render to end.
  @override
  Stream<RenderProgress> render(ReelDraft draft) {
    final run = _RenderRun();
    _current = run;
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
        (event) => _forward(event, run),
        onError: (Object error) => _fail(run, '$error'),
      );
      await _methods.invokeMethod<void>('start', spec);
    } on Object catch (error) {
      await _failWith(run, error);
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _methods.invokeMethod<void>('cancel');
    } finally {
      await _current?.deleteOverlays();
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
    final output = outputSizeFor(draft.frame, sourceSize);
    final stem = '${folder.path}/${name}_overlay';
    final branding = await _writeOverlay(
      run,
      '$stem.png',
      OverlaySpec(
        output: output,
        caption: draft.caption.copyWith(text: ''),
      ),
    );
    return renderSpecFor(
      RenderJob(
        source: source,
        clip: clip,
        frame: draft.frame,
        sourceSize: sourceSize,
        overlayPath: branding.path,
        captionCues: await _writeCueOverlays(draft, run, stem, output),
        outputPath: '${folder.path}/$name.mp4',
      ),
    );
  }

  /// One image per caption line, so only that line shows at a time.
  Future<List<RenderCue>> _writeCueOverlays(
    ReelDraft draft,
    _RenderRun run,
    String stem,
    OutputSize output,
  ) async {
    final cues = <RenderCue>[];
    for (final (position, cue) in draft.captionCues.indexed) {
      final file = await _writeOverlay(
        run,
        '${stem}_${position + 1}.png',
        OverlaySpec(
          output: output,
          caption: draft.caption.copyWith(text: cue.text),
        ),
      );
      cues.add(
        RenderCue(start: cue.start, end: cue.end, overlayPath: file.path),
      );
    }
    return cues;
  }

  Future<File> _writeOverlay(
    _RenderRun run,
    String path,
    OverlaySpec spec,
  ) async {
    final file = File(path);
    run.overlays.add(file);
    await file.writeAsBytes(await services.paintOverlay(spec));
    return file;
  }

  void _forward(Object? event, _RenderRun run) {
    if (event is! Map) {
      unawaited(_fail(run, 'Unexpected render event $event.'));
      return;
    }
    switch (event['type']) {
      case 'progress':
        run.progress.add(RenderRunning((event['value']! as num).toDouble()));
      case 'done':
        _rendering = null;
        run.progress.add(RenderFinished(event['path']! as String));
        unawaited(_finish(run));
      case _:
        unawaited(_fail(run, '${event['message']}'));
    }
  }

  Future<void> _fail(_RenderRun run, String reason) =>
      _failWith(run, RenderFailedException(reason));

  Future<void> _finish(_RenderRun run) async {
    await run.deleteOverlays();
    await run.progress.close();
  }

  /// A full disk keeps its own message; anything else is a failed render.
  Future<void> _failWith(_RenderRun run, Object error) async {
    final progress = run.progress;
    if (progress.isClosed) {
      return;
    }
    progress.addError(switch (mapIoError(error)) {
      final InsufficientStorageException full => full,
      final RenderFailedException failed => failed,
      _ => RenderFailedException('$error'),
    });
    await _finish(run);
  }
}

/// One render's stream, its native event subscription and its overlay PNGs.
class _RenderRun {
  final progress = StreamController<RenderProgress>();
  StreamSubscription<Object?>? events;

  /// Kept until the render ends: Kotlin opens each caption image when its
  /// line is due, not up front.
  final overlays = <File>[];

  Future<void> stopListening() async => events?.cancel();

  Future<void> deleteOverlays() async {
    final written = List.of(overlays);
    overlays.clear();
    for (final file in written) {
      try {
        await file.delete();
      } on PathNotFoundException {
        // Never written, or already gone: nothing to clean up.
      }
    }
  }
}
