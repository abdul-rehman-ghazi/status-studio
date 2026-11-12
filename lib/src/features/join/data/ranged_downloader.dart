import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/join/domain/download_cancel.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/segment_index.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const _defaultIdleTimeout = Duration(seconds: 30);

/// Which byte [ranges] of [url] to write, in order, into [target].
class RangedDownload {
  const RangedDownload({
    required this.url,
    required this.ranges,
    required this.target,
    required this.cancel,
  });

  final Uri url;
  final List<ByteRange> ranges;
  final File target;
  final DownloadCancel cancel;

  int get totalBytes => ranges.fold(0, (sum, range) => sum + range.length);
}

/// Fetches parts of a stream with HTTP range requests (spec FR-37; M7's
/// downloader, restored from `a5294bf^`).
class RangedDownloader {
  RangedDownloader(this._client, {this._idleTimeout = _defaultIdleTimeout});

  final HttpClient _client;

  /// How long a request may go without receiving anything before it counts
  /// as offline, so a stalled connection can't hang a download forever.
  final Duration _idleTimeout;

  /// The first [length] bytes of [url].
  Future<Uint8List> fetchHead(Uri url, int length) async {
    final response = await _requestRange(url, ByteRange(0, length - 1));
    final builder = BytesBuilder(copy: false);
    await _watched(response, url).forEach(builder.add);
    return builder.toBytes();
  }

  /// Writes the ranges back to back into `<target>.part` and renames it
  /// once every byte arrived, so a cut-off download never looks complete.
  /// [onBytes] hears the bytes received so far.
  Future<File> downloadRanges(
    RangedDownload download, {
    required void Function(int receivedBytes) onBytes,
  }) async {
    final target = download.target;
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    try {
      await _writeRanges(download, sink, onBytes);
      await sink.close();
    } catch (_) {
      await sink.close();
      await part.delete();
      rethrow;
    }
    return part.rename(target.path);
  }

  Future<void> _writeRanges(
    RangedDownload download,
    IOSink sink,
    void Function(int receivedBytes) onBytes,
  ) async {
    var received = 0;
    for (final range in download.ranges) {
      download.cancel.throwIfCancelled();
      final response = await _requestRange(download.url, range);
      var rangeBytes = 0;
      // Leaving the loop by a throw cancels the response, which drops the
      // connection, so Cancel doesn't wait for the rest of the range.
      await for (final chunk in _watched(response, download.url)) {
        download.cancel.throwIfCancelled();
        sink.add(chunk);
        rangeBytes += chunk.length;
        onBytes(received + rangeBytes);
      }
      if (rangeBytes != range.length) {
        throw IncompleteDownloadException(
          'Received $rangeBytes of ${range.length} bytes for $range.',
        );
      }
      received += rangeBytes;
    }
  }

  Future<HttpClientResponse> _requestRange(Uri url, ByteRange range) async {
    final request = await _client
        .getUrl(url)
        .timeout(_idleTimeout, onTimeout: () => throw _stalled(url));
    request.headers.set(
      HttpHeaders.rangeHeader,
      'bytes=${range.first}-${range.last}',
    );
    final response = await request.close().timeout(
      _idleTimeout,
      onTimeout: () => throw _stalled(url),
    );
    if (response.statusCode == HttpStatus.partialContent) {
      return response;
    }
    // Draining would read a whole 200 body; drop the connection instead.
    await response.detachSocket().then((socket) => socket.destroy());
    throw switch (response.statusCode) {
      HttpStatus.ok => RangeNotSupportedException('HTTP 200 for $url'),
      HttpStatus.forbidden => ExpiredStreamUrlException('HTTP 403 for $url'),
      final status => StreamRequestFailedException('HTTP $status for $url'),
    };
  }

  Stream<List<int>> _watched(HttpClientResponse response, Uri url) => response
      .timeout(_idleTimeout, onTimeout: (sink) => sink.addError(_stalled(url)));
}

OfflineException _stalled(Uri url) =>
    OfflineException('No data for a while from $url.');

final rangedDownloaderProvider = Provider<RangedDownloader>((ref) {
  final client = HttpClient();
  ref.onDispose(client.close);
  return RangedDownloader(client);
});
