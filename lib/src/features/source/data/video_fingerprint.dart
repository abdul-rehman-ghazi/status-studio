import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const _edgeBytes = 1024 * 1024;
const _idHexLength = 16;

/// Every video ID starts with this; folders named otherwise are older.
const videoIdPrefix = 'v_';

/// The video's ID: `v_<16 hex>` from its size and the SHA-256 of its first and
/// last 1 MiB (the whole file when it is under 2 MiB), so the same bytes give
/// the same ID however the file arrives (spec FR-1).
///
/// Throws [VideoUnreadableException] when the file can't be read or is empty.
Future<String> videoFingerprint(File video) async {
  try {
    final sizeBytes = await video.length();
    if (sizeBytes == 0) {
      throw VideoUnreadableException('Empty file: ${video.path}');
    }
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink)
      ..add(_sizeBytes(sizeBytes));
    await _addRange(hasher, video.openRead(0, min(sizeBytes, _edgeBytes)));
    final tailStart = max(sizeBytes - _edgeBytes, _edgeBytes);
    if (tailStart < sizeBytes) {
      await _addRange(hasher, video.openRead(tailStart, sizeBytes));
    }
    hasher.close();
    return '$videoIdPrefix${digestSink.digest.toString().substring(0, _idHexLength)}';
  } on FileSystemException catch (error) {
    throw VideoUnreadableException('${error.message}: ${error.path}');
  }
}

List<int> _sizeBytes(int sizeBytes) {
  final bytes = List<int>.filled(8, 0);
  var remaining = sizeBytes;
  for (var index = 7; index >= 0; index--) {
    bytes[index] = remaining & 0xff;
    remaining >>= 8;
  }
  return bytes;
}

Future<void> _addRange(Sink<List<int>> hasher, Stream<List<int>> range) async {
  await for (final chunk in range) {
    hasher.add(chunk);
  }
}

class _DigestSink implements Sink<Digest> {
  late final Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
