import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

const modelBytes = 4096;

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

  test('download_reports_progress_and_creates_model', () async {
    final server = await serveWholeModel();
    final manager = managerFor(uriOf(server.port));

    final progress = await manager.download(SpeechModel.small).toList();

    expect(
      (progress.last, await manager.isDownloaded(SpeechModel.small)),
      (1.0, true),
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
}
