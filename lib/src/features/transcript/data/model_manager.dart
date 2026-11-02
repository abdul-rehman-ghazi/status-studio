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

  /// Completes once a paused transfer has let go of its `.part` file.
  final _stopping = <SpeechModel, Future<void>>{};

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
  /// continue.
  Future<void> pause(SpeechModel model) {
    final running = _running.remove(model);
    if (running == null) {
      return _stopping[model] ?? Future.value();
    }
    return _stopping[model] = running.stop();
  }

  /// Stops the transfer and deletes what arrived.
  Future<void> cancel(SpeechModel model) async {
    await pause(model);
    await deletePart(model);
  }

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

  /// One transfer of [model] into its `.part` file.
  @protected
  Stream<WorkAmount> fetch(SpeechModel model) {
    // A resumed transfer appends to the paused one's file, so it starts
    // once that one has closed it.
    final previousStopped = _stopping.remove(model) ?? Future<void>.value();
    final path = previousStopped.then((_) => pathFor(model));
    return _PartDownload(httpClient, uriFor(model), path).progress;
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

/// The server says the kept bytes don't fit the model (HTTP 416).
class _PartMismatchException implements Exception {
  const _PartMismatchException(this.uri);

  final Uri uri;

  @override
  String toString() => 'Kept bytes are longer than the model at $uri';
}

typedef _OpenedTransfer = ({HttpClientResponse response, int startAt});

/// One HTTP transfer into `<path>.part`, renamed to `<path>` only once every
/// byte has arrived, so whisper never loads a truncated file.
///
/// It continues a `.part` left by a pause or a failure. Cancelling its
/// stream stops at once, even on a stalled connection, and keeps the bytes
/// written; `async*` can't, because its cancel waits for the next chunk.
class _PartDownload {
  _PartDownload(this._client, this._uri, this._destination);

  final HttpClient _client;
  final Uri _uri;

  /// Where the model goes, once the transfer may start.
  final Future<String> _destination;
  late final String _path;
  File? _part;
  late final _progress = StreamController<WorkAmount>(
    onListen: () => unawaited(_start()),
    onCancel: _stop,
  );
  StreamSubscription<List<int>>? _body;
  IOSink? _sink;
  var _stopped = false;

  Stream<WorkAmount> get progress => _progress.stream;

  Future<void> _start() async {
    try {
      _path = await _destination;
      final part = _part = File('$_path.part');
      await part.parent.create(recursive: true);
      final opened = await _open(part);
      if (_stopped) {
        await opened.response.listen(null).cancel();
        return;
      }
      _receive(opened, part);
    } on Object catch (error) {
      await _fail(error);
    }
  }

  /// Asks only for the bytes the `.part` file lacks. A server that sends
  /// the whole file anyway (200) starts it over.
  Future<_OpenedTransfer> _open(File part) async {
    final keptBytes = await part.exists() ? await part.length() : 0;
    final request = await _client.getUrl(_uri);
    if (keptBytes > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$keptBytes-');
    }
    final response = await request.close();
    return switch (response.statusCode) {
      HttpStatus.partialContent => (response: response, startAt: keptBytes),
      HttpStatus.ok => (response: response, startAt: 0),
      HttpStatus.requestedRangeNotSatisfiable => throw _PartMismatchException(
        _uri,
      ),
      final status => throw ModelDownloadException('HTTP $status for $_uri'),
    };
  }

  void _receive(_OpenedTransfer opened, File part) {
    final length = opened.response.contentLength;
    // contentLength is -1 when the server doesn't say; WorkAmount wants 0.
    final total = length < 0 ? 0 : opened.startAt + length;
    var received = opened.startAt;
    final sink = _sink = part.openWrite(
      mode: opened.startAt > 0 ? FileMode.append : FileMode.write,
    );
    _body = opened.response.listen(
      (chunk) {
        sink.add(chunk);
        received += chunk.length;
        _progress.add(
          WorkAmount(done: received, total: total, unit: WorkUnit.bytes),
        );
      },
      onError: (Object error) => unawaited(_fail(error)),
      onDone: () => unawaited(_finish(received, total)),
      cancelOnError: true,
    );
  }

  Future<void> _finish(int received, int total) async {
    try {
      await _sink?.close();
      if (total > 0 && received != total) {
        throw ModelDownloadException('Received $received of $total bytes.');
      }
      await _part!.rename(_path);
      _progress.add(
        WorkAmount(done: received, total: received, unit: WorkUnit.bytes),
      );
      await _progress.close();
    } on Object catch (error) {
      await _fail(error);
    }
  }

  /// Keeps the bytes for the next download to continue, unless they can't
  /// be used: a full disk needs the space, and a mismatch would corrupt
  /// the model.
  Future<void> _fail(Object error) async {
    await _closeSink();
    final failure = modelDownloadError(error);
    if (failure is InsufficientStorageException ||
        error is _PartMismatchException) {
      await _deletePart();
    }
    _progress.addError(failure);
    await _progress.close();
  }

  Future<void> _stop() async {
    _stopped = true;
    await _body?.cancel();
    await _closeSink();
  }

  /// A write error has already been reported by the transfer it broke.
  Future<void> _closeSink() async {
    try {
      await _sink?.close();
    } on FileSystemException {
      return;
    }
  }

  /// Nothing to delete when it failed before the file was named.
  Future<void> _deletePart() async {
    final part = _part;
    if (part != null && await part.exists()) {
      await part.delete();
    }
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
