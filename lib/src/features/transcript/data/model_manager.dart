import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/source/data/io_error_mapping.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Downloads, finds and deletes speech models. A model is written as
/// `<path>.part` and renamed only when every byte arrived, so whisper never
/// loads a truncated file.
class ModelManager {
  ModelManager({
    required this.pathFor,
    required this.uriFor,
    required this.httpClient,
  });

  final Future<String> Function(SpeechModel model) pathFor;
  final Uri Function(SpeechModel model) uriFor;
  final HttpClient httpClient;

  Future<bool> isDownloaded(SpeechModel model) async =>
      File(await pathFor(model)).exists();

  Future<int> sizeOnDisk(SpeechModel model) async {
    final file = File(await pathFor(model));
    return await file.exists() ? file.length() : 0;
  }

  Future<void> delete(SpeechModel model) async {
    final file = File(await pathFor(model));
    if (await file.exists()) {
      await file.delete();
    }
  }

  final _running = <SpeechModel, _Download>{};

  /// Emits the bytes received so far; throws [ModelDownloadException], or
  /// [InsufficientStorageException] for a full disk, on any failure.
  ///
  /// One transfer per model: a second caller joins the running one rather
  /// than writing into the same `.part` file, and the transfer finishes
  /// even if every listener leaves (Settings closed mid-download).
  Stream<WorkAmount> download(SpeechModel model) =>
      (_running[model] ?? _start(model)).join();

  bool isDownloading(SpeechModel model) => _running.containsKey(model);

  _Download _start(SpeechModel model) {
    final running = _Download();
    _running[model] = running;
    fetch(model).listen(
      running.report,
      onError: running.fail,
      onDone: () {
        _running.remove(model);
        running.finish();
      },
    );
    return running;
  }

  /// One transfer, leaving no file behind on failure.
  @protected
  Stream<WorkAmount> fetch(SpeechModel model) async* {
    final path = await pathFor(model);
    final part = File('$path.part');
    try {
      final response = await _request(uriFor(model));
      var received = _noBytes;
      // await for, not yield*: yield* would pass a stream error straight
      // through and skip the cleanup below.
      await for (final amount in _receive(response, part)) {
        received = amount;
        yield amount;
      }
      await part.rename(path);
      yield WorkAmount(
        done: received.done,
        total: received.done,
        unit: WorkUnit.bytes,
      );
    } catch (error) {
      if (await part.exists()) {
        await part.delete();
      }
      throw modelDownloadError(error);
    }
  }

  Future<HttpClientResponse> _request(Uri uri) async {
    final request = await httpClient.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw ModelDownloadException('HTTP ${response.statusCode} for $uri');
    }
    return response;
  }
}

/// A running transfer, shared by everyone following it. Each follower
/// gets its own controller, which buffers while its listener is paused.
class _Download {
  final _followers = <StreamController<WorkAmount>>[];
  WorkAmount _latest = _noBytes;

  void report(WorkAmount amount) {
    _latest = amount;
    for (final follower in [..._followers]) {
      follower.add(amount);
    }
  }

  void fail(Object error) {
    for (final follower in [..._followers]) {
      follower.addError(error);
    }
  }

  void finish() {
    for (final follower in [..._followers]) {
      unawaited(follower.close());
    }
  }

  /// Starts with how far the transfer has got, so a late joiner shows it
  /// at once.
  Stream<WorkAmount> join() {
    final follower = StreamController<WorkAmount>()..add(_latest);
    follower.onCancel = () => _followers.remove(follower);
    _followers.add(follower);
    return follower.stream;
  }
}

const _noBytes = WorkAmount(done: 0, total: 0, unit: WorkUnit.bytes);

/// A full disk is reported as such; retrying the download wouldn't help.
Exception modelDownloadError(Object error) {
  return switch (mapIoError(error)) {
    final InsufficientStorageException full => full,
    final ModelDownloadException failure => failure,
    _ => ModelDownloadException('$error'),
  };
}

Stream<WorkAmount> _receive(HttpClientResponse response, File part) async* {
  await part.parent.create(recursive: true);
  final sink = part.openWrite();
  // contentLength is -1 when the server doesn't say; WorkAmount wants 0.
  final total = math.max(0, response.contentLength);
  var received = 0;
  try {
    await for (final chunk in response) {
      sink.add(chunk);
      received += chunk.length;
      yield WorkAmount(done: received, total: total, unit: WorkUnit.bytes);
    }
  } finally {
    await sink.close();
  }
  if (total > 0 && received != total) {
    throw ModelDownloadException('Received $received of $total bytes.');
  }
}

/// whisper_ggml's name for [model].
/// Only multilingual models: the English-only ones can't write any other
/// language.
WhisperModel whisperModelFor(SpeechModel model) => switch (model) {
  SpeechModel.tiny => WhisperModel.tiny,
  SpeechModel.base => WhisperModel.base,
  SpeechModel.small => WhisperModel.small,
  SpeechModel.medium => WhisperModel.medium,
  SpeechModel.large => WhisperModel.large,
};

final modelManagerProvider = Provider<ModelManager>((ref) {
  final client = HttpClient();
  ref.onDispose(client.close);
  final whisper = WhisperController();
  return ModelManager(
    pathFor: (model) => whisper.getPath(whisperModelFor(model)),
    uriFor: (model) => whisperModelFor(model).modelUri,
    httpClient: client,
  );
});
