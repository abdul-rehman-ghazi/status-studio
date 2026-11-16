import 'dart:io';
import 'dart:math' as math;
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
    this.headers = const {},
  });

  final Uri url;

  /// Sent with every request (spec FR-50).
  final Map<String, String> headers;
  final List<ByteRange> ranges;
  final File target;
  final DownloadCancel cancel;

  int get totalBytes => ranges.fold(0, (sum, range) => sum + range.length);
}

/// One whole file at [url], written into [target] (spec FR-50).
class WholeDownload {
  const WholeDownload({
    required this.url,
    required this.headers,
    required this.target,
    required this.cancel,
  });

  final Uri url;

  /// Sent with the request.
  final Map<String, String> headers;
  final File target;
  final DownloadCancel cancel;
}

/// Fetches parts of a stream with HTTP range requests (spec FR-37; M7's
/// downloader, restored from `a5294bf^`).
class RangedDownloader {
  RangedDownloader(this._client, {this._idleTimeout = _defaultIdleTimeout});

  final HttpClient _client;

  /// How long a request may go without receiving anything before it counts
  /// as offline, so a stalled connection can't hang a download forever.
  final Duration _idleTimeout;

  /// The first [length] bytes of [url], asked for with [headers].
  Future<Uint8List> fetchHead(
    Uri url,
    int length, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _requestRange((
      url: url,
      headers: headers,
    ), ByteRange(0, length - 1));
    final builder = BytesBuilder(copy: false);
    await _watched(response, url).forEach(builder.add);
    return builder.toBytes();
  }

  /// The size of the file at [url] from the answer to a one-byte request
  /// (spec FR-50): its `Content-Range`, or the `Content-Length` of a server
  /// that sends the whole file instead. Null when the server doesn't say.
  Future<int?> totalBytesOf(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _request((
      url: url,
      headers: headers,
    ), range: const ByteRange(0, 0));
    // Draining could read a whole 200 body; drop the connection instead.
    await response.detachSocket().then((socket) => socket.destroy());
    return switch (response.statusCode) {
      HttpStatus.partialContent => _totalOf(
        response.headers.value(HttpHeaders.contentRangeHeader),
      ),
      HttpStatus.ok when response.contentLength >= 0 => response.contentLength,
      HttpStatus.ok => null,
      final status => throw _failureFor(status, url),
    };
  }

  /// Writes the whole file into `<target>.part` and renames it once every
  /// byte arrived. [onBytes] hears the bytes so far and the total, which is
  /// 0 when the server doesn't say.
  Future<File> downloadWhole(
    WholeDownload download, {
    required void Function(int receivedBytes, int totalBytes) onBytes,
  }) async {
    final target = download.target;
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    try {
      await _writeWhole(download, sink, onBytes);
      await sink.close();
    } catch (_) {
      await sink.close();
      await part.delete();
      rethrow;
    }
    return part.rename(target.path);
  }

  Future<void> _writeWhole(
    WholeDownload download,
    IOSink sink,
    void Function(int receivedBytes, int totalBytes) onBytes,
  ) async {
    final url = download.url;
    final response = await _request((url: url, headers: download.headers));
    if (response.statusCode != HttpStatus.ok) {
      await response.detachSocket().then((socket) => socket.destroy());
      throw _failureFor(response.statusCode, url);
    }
    final total = math.max(response.contentLength, 0);
    var received = 0;
    await for (final chunk in _watched(response, url)) {
      download.cancel.throwIfCancelled();
      sink.add(chunk);
      received += chunk.length;
      onBytes(received, total);
    }
    if (total > 0 && received != total) {
      throw IncompleteDownloadException('Received $received of $total bytes.');
    }
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
      final response = await _requestRange((
        url: download.url,
        headers: download.headers,
      ), range);
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

  Future<HttpClientResponse> _requestRange(
    _StreamAddress address,
    ByteRange range,
  ) async {
    final url = address.url;
    final response = await _request(address, range: range);
    if (response.statusCode == HttpStatus.partialContent) {
      return response;
    }
    // Draining would read a whole 200 body; drop the connection instead.
    await response.detachSocket().then((socket) => socket.destroy());
    throw switch (response.statusCode) {
      HttpStatus.ok => RangeNotSupportedException('HTTP 200 for $url'),
      final status => _failureFor(status, url),
    };
  }

  /// The site's headers go first, so none of them can change the range.
  Future<HttpClientResponse> _request(
    _StreamAddress address, {
    ByteRange? range,
  }) async {
    final url = address.url;
    final request = await _client
        .getUrl(url)
        .timeout(_idleTimeout, onTimeout: () => throw _stalled(url));
    address.headers.forEach(request.headers.set);
    if (range != null) {
      request.headers.set(
        HttpHeaders.rangeHeader,
        'bytes=${range.first}-${range.last}',
      );
    }
    return request.close().timeout(
      _idleTimeout,
      onTimeout: () => throw _stalled(url),
    );
  }

  Stream<List<int>> _watched(HttpClientResponse response, Uri url) => response
      .timeout(_idleTimeout, onTimeout: (sink) => sink.addError(_stalled(url)));
}

typedef _StreamAddress = ({Uri url, Map<String, String> headers});

Exception _failureFor(int status, Uri url) => status == HttpStatus.forbidden
    ? ExpiredStreamUrlException('HTTP 403 for $url')
    : StreamRequestFailedException('HTTP $status for $url');

final _contentRangeTotal = RegExp(r'/(\d+)$');

/// `bytes 0-0/84000000` gives 84000000; `bytes 0-0/*` gives null.
int? _totalOf(String? contentRange) {
  final match = contentRange == null
      ? null
      : _contentRangeTotal.firstMatch(contentRange.trim());
  return match == null ? null : int.parse(match.group(1)!);
}

OfflineException _stalled(Uri url) =>
    OfflineException('No data for a while from $url.');

final rangedDownloaderProvider = Provider<RangedDownloader>((ref) {
  final client = HttpClient();
  ref.onDispose(client.close);
  return RangedDownloader(client);
});
