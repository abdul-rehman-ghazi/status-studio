import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/data/ranged_downloader.dart';
import 'package:status_studio/src/features/source/domain/segment_index.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

final fileBytes = List.generate(10000, (i) => i % 256);

/// Serves [fileBytes]; honours `Range` unless told to ignore it.
Future<HttpServer> serve({int? fixedStatus, bool ignoreRange = false}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final response = request.response;
    if (fixedStatus != null) {
      response.statusCode = fixedStatus;
      await response.close();
      return;
    }
    final range = RegExp(r'bytes=(\d+)-(\d+)')
        .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
    if (range == null || ignoreRange) {
      response.add(fileBytes);
      await response.close();
      return;
    }
    final first = int.parse(range.group(1)!);
    final last = int.parse(range.group(2)!).clamp(0, fileBytes.length - 1);
    response
      ..statusCode = HttpStatus.partialContent
      ..add(fileBytes.sublist(first, last + 1));
    await response.close();
  });
  addTearDown(server.close);
  return server;
}

void main() {
  late Directory folder;
  late HttpClient client;
  late RangedDownloader downloader;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('ranged_downloader_test');
    client = HttpClient();
    downloader = RangedDownloader(
      client,
      idleTimeout: const Duration(milliseconds: 300),
    );
  });

  tearDown(() async {
    client.close(force: true);
    await folder.delete(recursive: true);
  });

  Uri urlOf(HttpServer server) =>
      Uri.parse('http://127.0.0.1:${server.port}/stream');

  RangedDownload rangesOf(HttpServer server) => RangedDownload(
    url: urlOf(server),
    ranges: const [
      ByteRange(0, 99),
      ByteRange(1000, 1999),
      ByteRange(5000, 5499),
    ],
    target: File('${folder.path}/clip.mp4'),
  );

  test('downloads_requested_ranges_in_order', () async {
    final server = await serve();

    final file = await downloader.downloadRanges(
      rangesOf(server),
      onProgress: (_) {},
    );

    expect(await file.readAsBytes(), [
      ...fileBytes.sublist(0, 100),
      ...fileBytes.sublist(1000, 2000),
      ...fileBytes.sublist(5000, 5500),
    ]);
  });

  test('reports_progress_to_one', () async {
    final server = await serve();
    final reported = <double>[];

    await downloader.downloadRanges(rangesOf(server), onProgress: reported.add);

    expect(reported.last, 1.0);
  });

  test('reports_zero_before_the_first_byte', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((_) {});
    final reported = <double>[];

    unawaited(
      downloader
          .downloadRanges(rangesOf(server), onProgress: reported.add)
          .catchError((Object _) => File('')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(reported, [0.0]);
  });

  test('rejects_response_without_partial_content', () async {
    final server = await serve(ignoreRange: true);
    final download = rangesOf(server);

    await expectLater(
      downloader.downloadRanges(download, onProgress: (_) {}),
      throwsA(isA<RangeNotSupportedException>()),
    );

    expect(download.target.existsSync(), isFalse);
  });

  test('forbidden_throws_expired_url', () async {
    final server = await serve(fixedStatus: HttpStatus.forbidden);

    await expectLater(
      downloader.downloadRanges(rangesOf(server), onProgress: (_) {}),
      throwsA(isA<ExpiredStreamUrlException>()),
    );
  });

  test('fetch_head_returns_first_bytes', () async {
    final server = await serve();

    final head = await downloader.fetchHead(urlOf(server), 64);

    expect(head, fileBytes.sublist(0, 64));
  });

  test('server_error_is_retryable_not_range_unsupported', () async {
    final server = await serve(fixedStatus: HttpStatus.serviceUnavailable);

    await expectLater(
      downloader.downloadRanges(rangesOf(server), onProgress: (_) {}),
      throwsA(isA<StreamRequestFailedException>()),
    );
  });

  test('stalled_download_times_out_as_offline', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.partialContent
        ..contentLength = 100
        ..add(List.filled(10, 1));
      await request.response.flush();
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      downloader.downloadRanges(rangesOf(server), onProgress: (_) {}),
      throwsA(isA<OfflineException>()),
    );
  });
}
