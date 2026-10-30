import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// Emits progress from 0 to 1; throws [ModelDownloadException] on any
  /// failure and leaves no file behind.
  Stream<double> download(SpeechModel model) async* {
    final path = await pathFor(model);
    final part = File('$path.part');
    try {
      final response = await _request(uriFor(model));
      // await for, not yield*: yield* would pass a stream error straight
      // through and skip the cleanup below.
      await for (final fraction in _receive(response, part)) {
        yield fraction;
      }
      await part.rename(path);
      yield 1;
    } catch (error) {
      if (await part.exists()) {
        await part.delete();
      }
      throw error is ModelDownloadException
          ? error
          : ModelDownloadException('$error');
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

Stream<double> _receive(HttpClientResponse response, File part) async* {
  await part.parent.create(recursive: true);
  final sink = part.openWrite();
  final total = response.contentLength;
  var received = 0;
  try {
    await for (final chunk in response) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) {
        yield received / total;
      }
    }
  } finally {
    await sink.close();
  }
  if (total > 0 && received != total) {
    throw ModelDownloadException('Received $received of $total bytes.');
  }
}

/// whisper_ggml's name for [model].
WhisperModel whisperModelFor(SpeechModel model) => switch (model) {
  SpeechModel.base => WhisperModel.base,
  SpeechModel.small => WhisperModel.small,
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
