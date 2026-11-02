import 'dart:async';
import 'dart:io';

import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/settings/presentation/speech_model_guide.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';

/// Models "on disk" are entries in [sizes], half-downloaded ones entries in
/// [partial]. A download reports half, then waits for [gate] (if set)
/// before the model appears; stopping it at the gate keeps the half.
class FakeModelManager extends ModelManager {
  FakeModelManager({Map<SpeechModel, int>? sizes})
    : sizes = sizes ?? {},
      super(
        pathFor: (model) async => model.name,
        uriFor: (model) => Uri.parse('http://localhost/${model.name}'),
        httpClient: HttpClient(),
      );

  final Map<SpeechModel, int> sizes;
  final partial = <SpeechModel, int>{};
  Completer<void>? gate;

  /// When set, downloads fail with this after reporting half.
  Exception? failure;
  final deleted = <SpeechModel>[];

  static const downloadedBytes = 147964211;

  static const _half = WorkAmount(
    done: downloadedBytes ~/ 2,
    total: downloadedBytes,
    unit: WorkUnit.bytes,
  );

  static const _whole = WorkAmount(
    done: downloadedBytes,
    total: downloadedBytes,
    unit: WorkUnit.bytes,
  );

  @override
  Future<bool> isDownloaded(SpeechModel model) async =>
      sizes.containsKey(model);

  @override
  Future<int> sizeOnDisk(SpeechModel model) async => sizes[model] ?? 0;

  @override
  Future<int> partialSize(SpeechModel model) async => partial[model] ?? 0;

  @override
  Future<void> delete(SpeechModel model) async {
    deleted.add(model);
    sizes.remove(model);
  }

  @override
  Future<void> deletePart(SpeechModel model) async => partial.remove(model);

  /// A controller rather than `async*`, so stopping it at the gate takes
  /// effect at once, as the real transfer's does. onCancel is async: a
  /// plain one makes cancel() return a root-zone future that widget tests'
  /// fake clock never completes.
  @override
  Stream<WorkAmount> fetch(SpeechModel model) {
    var stopped = false;
    late final StreamController<WorkAmount> transfer;
    transfer = StreamController<WorkAmount>(
      onListen: () => unawaited(_run(model, transfer, () => stopped)),
      onCancel: () async => stopped = true,
    );
    return transfer.stream;
  }

  Future<void> _run(
    SpeechModel model,
    StreamController<WorkAmount> transfer,
    bool Function() isStopped,
  ) async {
    transfer.add(_half);
    partial[model] = guideFor(model).downloadBytes ~/ 2;
    await gate?.future;
    if (isStopped()) {
      return;
    }
    if (failure case final failure?) {
      transfer.addError(failure);
      await transfer.close();
      return;
    }
    partial.remove(model);
    sizes[model] = downloadedBytes;
    transfer.add(_whole);
    await transfer.close();
  }
}
