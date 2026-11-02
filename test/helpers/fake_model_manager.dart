import 'dart:async';
import 'dart:io';

import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';

/// Models "on disk" are entries in [sizes]. A download reports half, then
/// waits for [gate] (if set) before the model appears.
class FakeModelManager extends ModelManager {
  FakeModelManager({Map<SpeechModel, int>? sizes})
    : sizes = sizes ?? {},
      super(
        pathFor: (model) async => model.name,
        uriFor: (model) => Uri.parse('http://localhost/${model.name}'),
        httpClient: HttpClient(),
      );

  final Map<SpeechModel, int> sizes;
  Completer<void>? gate;
  final deleted = <SpeechModel>[];

  static const downloadedBytes = 147964211;

  @override
  Future<bool> isDownloaded(SpeechModel model) async =>
      sizes.containsKey(model);

  @override
  Future<int> sizeOnDisk(SpeechModel model) async => sizes[model] ?? 0;

  @override
  Future<void> delete(SpeechModel model) async {
    deleted.add(model);
    sizes.remove(model);
  }

  @override
  Stream<double> download(SpeechModel model) async* {
    yield 0.5;
    await gate?.future;
    sizes[model] = downloadedBytes;
    yield 1;
  }
}
