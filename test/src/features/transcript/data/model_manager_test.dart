import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

const modelBytes = 4096;

/// Distinct byte values, so a file stitched from the wrong offsets shows.
final modelContent = List<int>.generate(modelBytes, (index) => index % 251);

/// Polls for up to two seconds; true once [model] is on disk.
Future<bool> untilDownloaded(ModelManager manager, SpeechModel model) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (await manager.isDownloaded(model)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return false;
}

/// The stalling first answer, or [modelContent] from the requested byte.
Future<void> answerRequest(
  Socket socket,
  String head, {
  required bool isFirst,
}) async {
  if (isFirst) {
    socket
      ..write('HTTP/1.1 200 OK\r\nContent-Length: $modelBytes\r\n\r\n')
      ..add(modelContent.sublist(0, modelBytes ~/ 4));
    await socket.flush();
    return;
  }
  final from = int.parse(
    RegExp(r'[Rr]ange: bytes=(\d+)-').firstMatch(head)?.group(1) ?? '0',
  );
  socket
    ..write(
      'HTTP/1.1 206 Partial Content\r\n'
      'Content-Range: bytes $from-${modelBytes - 1}/$modelBytes\r\n'
      'Content-Length: ${modelBytes - from}\r\n\r\n',
    )
    ..add(modelContent.sublist(from));
  await socket.flush();
  await socket.close();
}

void main() {
  late Directory folder;
  late HttpClient client;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('model_manager_test');
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await folder.delete(recursive: true);
  });

  ModelManager managerFor(Uri uri) => ModelManager(
    pathFor: (model) async => '${folder.path}/ggml-${model.name}.bin',
    uriFor: (_) => uri,
    httpClient: client,
  );

  Future<HttpServer> serveWholeModel() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..contentLength = modelBytes
        ..add(List.filled(modelBytes, 7));
      await request.response.close();
    });
    addTearDown(server.close);
    return server;
  }

  /// Promises the whole model, sends a tenth of it, then hangs up.
  Future<ServerSocket> serveHalfThenHangUp() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) async {
      socket
        ..write('HTTP/1.1 200 OK\r\nContent-Length: $modelBytes\r\n\r\n')
        ..add(List.filled(modelBytes ~/ 10, 7));
      await socket.flush();
      await socket.close();
    });
    addTearDown(server.close);
    return server;
  }

  Uri uriOf(int port) => Uri.parse('http://127.0.0.1:$port/model.bin');

  File partOf(SpeechModel model) =>
      File('${folder.path}/ggml-${model.name}.bin.part');

  File modelFileOf(SpeechModel model) =>
      File('${folder.path}/ggml-${model.name}.bin');

  /// Serves [modelContent], honouring `Range: bytes=N-` unless
  /// [ignoreRanges]; records every Range header it sees.
  Future<(HttpServer, List<String?>)> serveWithRanges({
    bool ignoreRanges = false,
  }) async {
    final ranges = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      final from = ignoreRanges || range == null
          ? 0
          : int.parse(range.substring('bytes='.length, range.length - 1));
      if (from > 0) {
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $from-${modelBytes - 1}/$modelBytes',
          );
      }
      request.response
        ..contentLength = modelBytes - from
        ..add(modelContent.sublist(from));
      await request.response.close();
    });
    addTearDown(server.close);
    return (server, ranges);
  }

  /// Promises the whole model, sends a quarter, then goes quiet without
  /// hanging up, like a stalled connection.
  Future<ServerSocket> serveQuarterThenStall() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    server.listen((socket) async {
      sockets.add(socket);
      socket
        ..write('HTTP/1.1 200 OK\r\nContent-Length: $modelBytes\r\n\r\n')
        ..add(modelContent.sublist(0, modelBytes ~/ 4));
      await socket.flush();
    });
    addTearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      await server.close();
    });
    return server;
  }

  /// The first answer sends a quarter and goes quiet without hanging up;
  /// later ones honour `Range: bytes=N-`. Raw sockets: HttpServer holds
  /// back a body it hasn't finished.
  Future<ServerSocket> serveStallThenRanges() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    server.listen((socket) {
      sockets.add(socket);
      final isFirst = sockets.length == 1;
      final head = StringBuffer();
      var answered = false;
      socket.listen((bytes) {
        head.write(latin1.decode(bytes));
        if (answered || !head.toString().contains('\r\n\r\n')) {
          return;
        }
        answered = true;
        unawaited(answerRequest(socket, head.toString(), isFirst: isFirst));
      });
    });
    addTearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      await server.close();
    });
    return server;
  }

  /// Starts a download from a stalling server and waits for its first
  /// bytes.
  Future<ModelManager> stalledDownload(SpeechModel model) async {
    final server = await serveQuarterThenStall();
    final manager = managerFor(uriOf(server.port));
    await manager.download(model).firstWhere((amount) => amount.done > 0);
    return manager;
  }

  test('download_reports_progress_and_creates_model', () async {
    final server = await serveWholeModel();
    final manager = managerFor(uriOf(server.port));

    final progress = await manager.download(SpeechModel.small).toList();

    expect(
      (progress.last.fraction, await manager.isDownloaded(SpeechModel.small)),
      (1.0, true),
    );
  });

  test('download_reports_received_and_total_bytes', () async {
    final server = await serveWholeModel();
    final manager = managerFor(uriOf(server.port));

    final progress = await manager.download(SpeechModel.small).toList();

    expect(
      progress.last,
      const WorkAmount(
        done: modelBytes,
        total: modelBytes,
        unit: WorkUnit.bytes,
      ),
    );
  });

  test('interrupted_download_leaves_no_model', () async {
    final server = await serveHalfThenHangUp();
    final manager = managerFor(uriOf(server.port));

    await expectLater(
      manager.download(SpeechModel.small).drain<void>(),
      throwsA(isA<ModelDownloadException>()),
    );

    expect(await manager.isDownloaded(SpeechModel.small), isFalse);
  });

  test('concurrent_downloads_share_one_transfer', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      request.response
        ..contentLength = modelBytes
        ..add(List.filled(modelBytes, 7));
      await request.response.close();
    });
    addTearDown(server.close);
    final manager = managerFor(uriOf(server.port));

    await Future.wait([
      manager.download(SpeechModel.small).drain<void>(),
      manager.download(SpeechModel.small).drain<void>(),
    ]);

    expect(requests, 1);
  });

  test('download_finishes_after_its_listener_leaves', () async {
    final server = await serveWholeModel();
    final manager = managerFor(uriOf(server.port));

    await manager.download(SpeechModel.small).first;

    expect(await untilDownloaded(manager, SpeechModel.small), isTrue);
  });

  group('pause and resume', () {
    test('pause_keeps_the_bytes_received', () async {
      final manager = await stalledDownload(SpeechModel.small);

      await manager.pause(SpeechModel.small);

      expect(await manager.partialSize(SpeechModel.small), modelBytes ~/ 4);
    });

    test('pause_tells_followers_the_download_stopped', () async {
      final manager = await stalledDownload(SpeechModel.small);
      final following = manager.download(SpeechModel.small).drain<void>();

      unawaited(manager.pause(SpeechModel.small));

      await expectLater(
        following,
        throwsA(isA<ModelDownloadStoppedException>()),
      );
    });

    test('paused_download_is_no_longer_running', () async {
      final manager = await stalledDownload(SpeechModel.small);

      await manager.pause(SpeechModel.small);

      expect(manager.isDownloading(SpeechModel.small), isFalse);
    });

    test('cancel_deletes_the_bytes_received', () async {
      final manager = await stalledDownload(SpeechModel.small);

      await manager.cancel(SpeechModel.small);

      expect(await manager.partialSize(SpeechModel.small), 0);
    });

    test('resume_asks_only_for_the_missing_bytes', () async {
      final (server, ranges) = await serveWithRanges();
      await partOf(SpeechModel.small)
          .writeAsBytes(modelContent.sublist(0, 1000));
      final manager = managerFor(uriOf(server.port));

      await manager.download(SpeechModel.small).drain<void>();

      expect(ranges, ['bytes=1000-']);
    });

    test('resumed_model_is_the_whole_file', () async {
      final (server, _) = await serveWithRanges();
      await partOf(SpeechModel.small)
          .writeAsBytes(modelContent.sublist(0, 1000));
      final manager = managerFor(uriOf(server.port));

      await manager.download(SpeechModel.small).drain<void>();

      expect(await modelFileOf(SpeechModel.small).readAsBytes(), modelContent);
    });

    test('resumed_progress_counts_the_kept_bytes', () async {
      final (server, _) = await serveWithRanges();
      await partOf(SpeechModel.small)
          .writeAsBytes(modelContent.sublist(0, 1000));
      final manager = managerFor(uriOf(server.port));

      final progress = await manager.download(SpeechModel.small).toList();

      expect(progress[1].total, modelBytes);
    });

    test('server_ignoring_the_range_starts_over', () async {
      final (server, _) = await serveWithRanges(ignoreRanges: true);
      await partOf(SpeechModel.small).writeAsBytes(List.filled(1000, 0));
      final manager = managerFor(uriOf(server.port));

      await manager.download(SpeechModel.small).drain<void>();

      expect(await modelFileOf(SpeechModel.small).readAsBytes(), modelContent);
    });

    test('unsatisfiable_range_deletes_the_bytes_kept', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await request.response.close();
      });
      addTearDown(server.close);
      await partOf(SpeechModel.small).writeAsBytes(List.filled(5000, 0));
      final manager = managerFor(uriOf(server.port));

      await manager
          .download(SpeechModel.small)
          .drain<void>()
          .catchError((Object _) {});

      expect(await manager.partialSize(SpeechModel.small), 0);
    });

    test('download_right_after_pause_installs_the_whole_model', () async {
      final server = await serveStallThenRanges();
      final manager = managerFor(uriOf(server.port));
      await manager
          .download(SpeechModel.small)
          .firstWhere((amount) => amount.done > 0);

      unawaited(manager.pause(SpeechModel.small));
      await manager.download(SpeechModel.small).drain<void>();

      expect(await modelFileOf(SpeechModel.small).readAsBytes(), modelContent);
    });

    test('download_right_after_cancel_installs_the_whole_model', () async {
      final server = await serveStallThenRanges();
      final manager = managerFor(uriOf(server.port));
      await manager
          .download(SpeechModel.small)
          .firstWhere((amount) => amount.done > 0);

      unawaited(manager.cancel(SpeechModel.small));
      await manager.download(SpeechModel.small).drain<void>();

      expect(await modelFileOf(SpeechModel.small).readAsBytes(), modelContent);
    });

    test('resume_reports_the_kept_bytes_before_new_ones', () async {
      final (server, _) = await serveWithRanges();
      await partOf(SpeechModel.small)
          .writeAsBytes(modelContent.sublist(0, 1000));
      final manager = managerFor(uriOf(server.port));

      final progress = await manager.download(SpeechModel.small).toList();

      expect(progress[1].done, 1000);
    });

    test('range_starting_elsewhere_is_rejected', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-${modelBytes - 1}/$modelBytes',
          )
          ..contentLength = modelBytes
          ..add(modelContent);
        await request.response.close();
      });
      addTearDown(server.close);
      await partOf(SpeechModel.small)
          .writeAsBytes(modelContent.sublist(0, 1000));
      final manager = managerFor(uriOf(server.port));

      await expectLater(
        manager.download(SpeechModel.small).drain<void>(),
        throwsA(isA<ModelDownloadException>()),
      );
    });

    test('whole_part_is_installed_when_nothing_is_left', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$modelBytes');
        await request.response.close();
      });
      addTearDown(server.close);
      await partOf(SpeechModel.small).writeAsBytes(modelContent);
      final manager = managerFor(uriOf(server.port));

      await manager.download(SpeechModel.small).drain<void>();

      expect(await modelFileOf(SpeechModel.small).readAsBytes(), modelContent);
    });

    test('unwritable_part_fails_the_download', () async {
      final server = await serveWholeModel();
      await Directory(partOf(SpeechModel.small).path).create();
      final manager = managerFor(uriOf(server.port));

      await expectLater(
        manager.download(SpeechModel.small).drain<void>(),
        throwsA(isA<ModelDownloadException>()),
      );
    });

    test('failed_download_keeps_its_bytes_for_retry', () async {
      final server = await serveHalfThenHangUp();
      final manager = managerFor(uriOf(server.port));

      await manager
          .download(SpeechModel.small)
          .drain<void>()
          .catchError((Object _) {});

      expect(await manager.partialSize(SpeechModel.small), greaterThan(0));
    });
  });

  test('delete_removes_model', () async {
    final server = await serveWholeModel();
    final manager = managerFor(uriOf(server.port));
    await manager.download(SpeechModel.base).drain<void>();

    await manager.delete(SpeechModel.base);

    expect(await manager.isDownloaded(SpeechModel.base), isFalse);
  });

  test('is_downloaded_false_for_part_file', () async {
    final manager = managerFor(uriOf(1));
    await File('${folder.path}/ggml-small.bin.part').writeAsBytes([1, 2]);

    expect(await manager.isDownloaded(SpeechModel.small), isFalse);
  });

  test('size_on_disk_counts_model_bytes', () async {
    final server = await serveWholeModel();
    final manager = managerFor(uriOf(server.port));
    await manager.download(SpeechModel.small).drain<void>();

    expect(await manager.sizeOnDisk(SpeechModel.small), modelBytes);
  });

  test('server_error_is_a_model_download_failure', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    addTearDown(server.close);
    final manager = managerFor(uriOf(server.port));

    await expectLater(
      manager.download(SpeechModel.small).drain<void>(),
      throwsA(isA<ModelDownloadException>()),
    );
  });

  test('full_disk_is_reported_as_insufficient_storage', () {
    const full = FileSystemException(
      'Write failed',
      'ggml-small.bin.part',
      OSError('No space left on device', 28),
    );

    expect(modelDownloadError(full), isA<InsufficientStorageException>());
  });

  test('every_speech_model_is_multilingual', () {
    final names = [
      for (final model in SpeechModel.values) whisperModelFor(model).modelName,
    ];

    expect(names, ['tiny', 'base', 'small', 'medium', 'large-v3']);
  });

  test('models_download_their_quantised_files', () {
    final files = [
      for (final model in SpeechModel.values)
        modelDownloadUri(model).pathSegments.last,
    ];

    expect(files, [
      'ggml-tiny-q5_1.bin',
      'ggml-base-q5_1.bin',
      'ggml-small-q5_1.bin',
      'ggml-medium-q5_0.bin',
      'ggml-large-v3-q5_0.bin',
    ]);
  });
}
