import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/segment_index.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// Which byte [ranges] of [url] to write, in order, into [target].
class RangedDownload {
  const RangedDownload({
    required this.url,
    required this.ranges,
    required this.target,
  });

  final Uri url;
  final List<ByteRange> ranges;
  final File target;
}

/// Fetches parts of a file with HTTP range requests (FR-15).
class RangedDownloader {
  RangedDownloader(this._client);

  final HttpClient _client;

  /// The first [length] bytes of [url].
  Future<Uint8List> fetchHead(Uri url, int length) async {
    final response = await _requestRange(url, ByteRange(0, length - 1));
    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add);
    return builder.toBytes();
  }

  /// Writes the ranges back to back into `<target>.part` and renames it
  /// once every byte arrived, so a cut-off download never looks complete.
  Future<File> downloadRanges(
    RangedDownload download, {
    required void Function(double fraction) onProgress,
  }) async {
    final target = download.target;
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    try {
      await _writeRanges(download, sink, onProgress);
      await sink.close();
    } catch (_) {
      await sink.close();
      await part.delete();
      rethrow;
    }
    onProgress(1);
    return part.rename(target.path);
  }

  Future<void> _writeRanges(
    RangedDownload download,
    IOSink sink,
    void Function(double fraction) onProgress,
  ) async {
    final total = download.ranges.fold(0, (sum, range) => sum + range.length);
    var received = 0;
    for (final range in download.ranges) {
      final response = await _requestRange(download.url, range);
      var rangeBytes = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        rangeBytes += chunk.length;
        onProgress((received + rangeBytes) / total);
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
    final request = await _client.getUrl(url);
    request.headers.set(
      HttpHeaders.rangeHeader,
      'bytes=${range.first}-${range.last}',
    );
    final response = await request.close();
    if (response.statusCode == HttpStatus.forbidden) {
      await response.drain<void>();
      throw ExpiredStreamUrlException('HTTP 403 for $url');
    }
    if (response.statusCode != HttpStatus.partialContent) {
      // Draining a 200 would download the whole stream; just drop it.
      await response.detachSocket().then((socket) => socket.destroy());
      throw RangeNotSupportedException('HTTP ${response.statusCode} for $url');
    }
    return response;
  }
}

final rangedDownloaderProvider = Provider<RangedDownloader>((ref) {
  final client = HttpClient();
  ref.onDispose(client.close);
  return RangedDownloader(client);
});
