import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/source/data/io_error_mapping.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Downloads, finds and deletes speech models.
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

  /// Bytes kept from a paused or failed download, which [download]
  /// continues.
  Future<int> partialSize(SpeechModel model) async {
    final part = await _partOf(model);
    return await part.exists() ? part.length() : 0;
  }

  Future<void> delete(SpeechModel model) async {
    final file = File(await pathFor(model));
    if (await file.exists()) {
      await file.delete();
    }
  }

  final _running = <SpeechModel, _Download>{};

  /// The last work on each model's `.part` file: a transfer or a delete.
  /// The next waits for it, because two at once corrupt the file.
  final _partWork = <SpeechModel, Future<void>>{};

  /// Emits the bytes received so far; throws [ModelDownloadException], or
  /// [InsufficientStorageException] for a full disk, on any failure, and
  /// [ModelDownloadStoppedException] when paused or cancelled.
  ///
  /// One transfer per model: a second caller joins the running one rather
  /// than writing into the same `.part` file, and the transfer finishes
  /// even if every listener leaves (Settings closed mid-download).
  Stream<WorkAmount> download(SpeechModel model) =>
      (_running[model] ?? _start(model)).join();

  bool isDownloading(SpeechModel model) => _running.containsKey(model);

  /// Stops the transfer at once and keeps what arrived for [download] to
  /// continue. Completes once the transfer has let go of the file.
  Future<void> pause(SpeechModel model) {
    final running = _running.remove(model);
    if (running != null) {
      unawaited(running.stop());
    }
    return _partWork[model] ?? Future.value();
  }

  /// Stops the transfer and deletes what arrived. The delete is queued
  /// before this returns, so a download started meanwhile waits for it.
  Future<void> cancel(SpeechModel model) =>
      _queuePartWork(model, pause(model).then((_) => deletePart(model)));

  @protected
  Future<void> deletePart(SpeechModel model) async {
    final part = await _partOf(model);
    if (await part.exists()) {
      await part.delete();
    }
  }

  _Download _start(SpeechModel model) {
    final running = _Download();
    _running[model] = running;
    running.follow(
      fetch(model),
      onDone: () {
        if (_running[model] == running) {
          _running.remove(model);
        }
      },
    );
    return running;
  }

  /// One transfer of [model] into its `.part` file, started once the work
  /// before it on that file is done.
  @protected
  Stream<WorkAmount> fetch(SpeechModel model) {
    final previous = _partWork[model] ?? Future<void>.value();
    final transfer = _PartDownload(
      httpClient,
      uriFor(model),
      previous.then((_) => pathFor(model)),
    );
    unawaited(_queuePartWork(model, transfer.settled));
    return transfer.progress;
  }

  /// The queue keeps going after a failed step; the caller still sees it.
  Future<void> _queuePartWork(SpeechModel model, Future<void> work) {
    _partWork[model] = work.catchError((Object _) {});
    return work;
  }

  Future<File> _partOf(SpeechModel model) async =>
      File('${await pathFor(model)}.part');
}

/// A running transfer, shared by everyone following it. Each follower
/// gets its own controller, which buffers while its listener is paused.
class _Download {
  final _followers = <StreamController<WorkAmount>>[];
  WorkAmount _latest = _noBytes;
  late final StreamSubscription<WorkAmount> _transfer;

  void follow(Stream<WorkAmount> transfer, {required VoidCallback onDone}) {
    _transfer = transfer.listen(
      _report,
      onError: _fail,
      onDone: () {
        onDone();
        _finish();
      },
    );
  }

  /// Followers hear that it stopped at once; the returned future completes
  /// once the transfer has closed its file.
  Future<void> stop() {
    _fail(const ModelDownloadStoppedException());
    _finish();
    return _transfer.cancel();
  }

  /// Starts with how far the transfer has got, so a late joiner shows it
  /// at once.
  Stream<WorkAmount> join() {
    final follower = StreamController<WorkAmount>()..add(_latest);
    follower.onCancel = () => _followers.remove(follower);
    _followers.add(follower);
    return follower.stream;
  }

  void _report(WorkAmount amount) {
    _latest = amount;
    for (final follower in [..._followers]) {
      follower.add(amount);
    }
  }

  void _fail(Object error) {
    for (final follower in [..._followers]) {
      follower.addError(error);
    }
  }

  void _finish() {
    for (final follower in [..._followers]) {
      unawaited(follower.close());
    }
    _followers.clear();
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

/// The kept bytes don't belong to the file the server has.
class _PartMismatchException implements Exception {
  const _PartMismatchException(this.uri);

  final Uri uri;

  @override
  String toString() => 'Kept bytes do not match the model at $uri';
}

/// What the server answered for the bytes the `.part` file lacks.
sealed class _ServerAnswer {
  const _ServerAnswer();
}

/// Bytes to write from [startAt] on; [total] is 0 when unknown.
final class _Body extends _ServerAnswer {
  const _Body(this.response, {required this.startAt, required this.total});

  final HttpClientResponse response;
  final int startAt;
  final int total;
}

/// The `.part` file is already the whole model: the app stopped between
/// the last byte and the rename.
final class _AlreadyWhole extends _ServerAnswer {
  const _AlreadyWhole(this.bytes);

  final int bytes;
}

/// `bytes 1000-4095/4096`, or `bytes */4096` on a 416.
final _contentRangePattern = RegExp(r'^bytes (?:(\d+)-\d+|\*)/(\d+|\*)$');

/// One HTTP transfer into `<path>.part`, renamed to `<path>` only once every
/// byte has arrived, so whisper never loads a truncated file.
///
/// It continues a `.part` left by a pause or a failure. Cancelling its
/// stream stops at once, even on a stalled connection (`async*` can't: its
/// cancel waits for the next chunk), and keeps the bytes written.
class _PartDownload {
  _PartDownload(this._client, this._uri, this._destination);

  final HttpClient _client;
  final Uri _uri;

  /// Where the model goes, once the transfer may start.
  final Future<String> _destination;
  late final _progress = StreamController<WorkAmount>(
    onListen: () => unawaited(_run().whenComplete(_settled.complete)),
    onCancel: _stop,
  );
  final _settled = Completer<void>();
  StreamSubscription<List<int>>? _body;
  Completer<void>? _copied;
  var _received = 0;
  var _stopped = false;

  Stream<WorkAmount> get progress => _progress.stream;

  /// Completes once the transfer no longer touches its files, however it
  /// ended; it never fails.
  Future<void> get settled => _settled.future;

  Future<void> _run() async {
    final String path;
    try {
      path = await _destination;
    } on Object catch (error) {
      return _report(error);
    }
    final part = File('$path.part');
    try {
      await _transfer(part, path);
    } on Object catch (error) {
      await _fail(error, part);
    }
  }

  Future<void> _transfer(File part, String path) async {
    await part.parent.create(recursive: true);
    final answer = await _ask(part);
    if (_stopped) {
      if (answer case _Body(:final response)) {
        await response.listen(null).cancel();
      }
      return;
    }
    switch (answer) {
      case _AlreadyWhole(:final bytes):
        await _install(part, path, bytes);
      case final _Body body:
        await _write(body, part, path);
    }
  }

  /// Asks only for the bytes the `.part` file lacks. A server that sends
  /// the whole file anyway (200) starts it over.
  Future<_ServerAnswer> _ask(File part) async {
    final keptBytes = await part.exists() ? await part.length() : 0;
    final request = await _client.getUrl(_uri);
    if (keptBytes > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$keptBytes-');
    }
    final response = await request.close();
    switch (response.statusCode) {
      case HttpStatus.ok:
        final length = response.contentLength;
        // contentLength is -1 when the server doesn't say.
        return _Body(response, startAt: 0, total: length < 0 ? 0 : length);
      case HttpStatus.partialContent:
        return _resumed(response, keptBytes);
      case HttpStatus.requestedRangeNotSatisfiable:
        return _nothingLeft(response, keptBytes);
      default:
        await response.drain<void>();
        throw ModelDownloadException('HTTP ${response.statusCode} for $_uri');
    }
  }

  /// The range must start where the kept bytes end; anything else, from a
  /// proxy say, would be stitched on at the wrong place.
  Future<_ServerAnswer> _resumed(
    HttpClientResponse response,
    int keptBytes,
  ) async {
    final range = _contentRangeOf(response);
    if (range?.start != keptBytes) {
      await response.drain<void>();
      throw _PartMismatchException(_uri);
    }
    return _Body(response, startAt: keptBytes, total: range?.size ?? 0);
  }

  /// A 416 means the kept bytes are already the whole file when they match
  /// its size, and don't belong to it otherwise.
  Future<_ServerAnswer> _nothingLeft(
    HttpClientResponse response,
    int keptBytes,
  ) async {
    final size = _contentRangeOf(response)?.size;
    await response.drain<void>();
    if (keptBytes > 0 && size == keptBytes) {
      return _AlreadyWhole(keptBytes);
    }
    throw _PartMismatchException(_uri);
  }

  ({int? start, int? size})? _contentRangeOf(HttpClientResponse response) {
    final header = response.headers.value(HttpHeaders.contentRangeHeader);
    final match = _contentRangePattern.firstMatch(header ?? '');
    if (match == null) {
      return null;
    }
    return (
      start: int.tryParse(match.group(1) ?? ''),
      size: int.tryParse(match.group(2) ?? ''),
    );
  }

  Future<void> _write(_Body body, File part, String path) async {
    final file = await part.open(mode: FileMode.append);
    try {
      await _alignTo(file, body.startAt);
      await _copy(body, file);
    } finally {
      await file.close();
    }
    if (_stopped) {
      return;
    }
    if (body.total > 0 && _received != body.total) {
      throw ModelDownloadException(
        'Received $_received of ${body.total} bytes.',
      );
    }
    await _install(part, path, _received);
  }

  /// A resume appends exactly where the kept bytes end; anywhere else
  /// would corrupt the model.
  Future<void> _alignTo(RandomAccessFile file, int startAt) async {
    if (startAt == 0) {
      await file.truncate(0);
      await file.setPosition(0);
      return;
    }
    if (await file.length() != startAt) {
      throw _PartMismatchException(_uri);
    }
  }

  /// Writes each chunk before taking the next, so a write error (a full
  /// disk) stops the download at once rather than after the last byte.
  Future<void> _copy(_Body body, RandomAccessFile file) {
    final copied = _copied = Completer<void>();
    _received = body.startAt;
    _reportReceived(body.total);
    late final StreamSubscription<List<int>> subscription;
    subscription = _body = body.response.listen(
      (chunk) async {
        subscription.pause();
        try {
          await file.writeFrom(chunk);
        } on Object catch (error) {
          await subscription.cancel();
          _completeCopy(copied, error);
          return;
        }
        _received += chunk.length;
        _reportReceived(body.total);
        subscription.resume();
      },
      onError: (Object error) => _completeCopy(copied, error),
      onDone: () => _completeCopy(copied, null),
      cancelOnError: true,
    );
    return copied.future;
  }

  void _completeCopy(Completer<void> copied, Object? error) {
    if (copied.isCompleted) {
      return;
    }
    if (error == null) {
      copied.complete();
      return;
    }
    copied.completeError(error);
  }

  void _reportReceived(int total) => _progress.add(
    WorkAmount(done: _received, total: total, unit: WorkUnit.bytes),
  );

  Future<void> _install(File part, String path, int bytes) async {
    await part.rename(path);
    _progress.add(WorkAmount(done: bytes, total: bytes, unit: WorkUnit.bytes));
    await _progress.close();
  }

  /// Keeps the bytes for the next download to continue, unless they can't
  /// be used: a full disk needs the space, and a mismatch would corrupt
  /// the model.
  Future<void> _fail(Object error, File part) async {
    if (_stopped) {
      return;
    }
    final failure = modelDownloadError(error);
    if (failure is InsufficientStorageException ||
        error is _PartMismatchException) {
      await _deleteIfPresent(part);
    }
    await _report(failure);
  }

  Future<void> _report(Object error) async {
    _progress.addError(modelDownloadError(error));
    await _progress.close();
  }

  /// The copy is told it's over too, so [_run] closes the file and settles.
  Future<void> _stop() async {
    _stopped = true;
    await _body?.cancel();
    final copied = _copied;
    if (copied != null) {
      _completeCopy(copied, null);
    }
  }
}

Future<void> _deleteIfPresent(File file) async {
  if (await file.exists()) {
    await file.delete();
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

/// The 5-bit quantised file: on a Pixel 6a small-q5_1 wrote a 90 s chunk
/// twice as fast as the full small model with nearly the same text, at 40 %
/// of the download (spec §10 Q2). It's saved where whisper_ggml looks for
/// the full model; whisper.cpp reads the quantisation from the file.
Uri modelDownloadUri(SpeechModel model) {
  final file = switch (model) {
    SpeechModel.tiny => 'tiny-q5_1',
    SpeechModel.base => 'base-q5_1',
    SpeechModel.small => 'small-q5_1',
    SpeechModel.medium => 'medium-q5_0',
    SpeechModel.large => 'large-v3-q5_0',
  };
  return Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$file.bin',
  );
}

final modelManagerProvider = Provider<ModelManager>((ref) {
  final client = HttpClient();
  ref.onDispose(client.close);
  final whisper = WhisperController();
  return ModelManager(
    pathFor: (model) => whisper.getPath(whisperModelFor(model)),
    uriFor: modelDownloadUri,
    httpClient: client,
  );
});
