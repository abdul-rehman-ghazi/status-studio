import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const _edgeBytes = 1024 * 1024;
const _idHexLength = 16;

/// The video's ID: `v_<16 hex>` from its size and the SHA-256 of its first and
/// last 1 MiB (the whole file when it is under 2 MiB), so the same bytes give
/// the same ID however the file arrives (spec FR-1).
///
/// Throws [VideoUnreadableException] when the file can't be read.
Future<String> videoFingerprint(File video) async {
  try {
    final sizeBytes = await video.length();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink)
      ..add(_sizeBytes(sizeBytes));
    await _addRange(
      hasher,
      video,
      0,
      sizeBytes < _edgeBytes ? sizeBytes : _edgeBytes,
    );
    final tailStart = sizeBytes - _edgeBytes > _edgeBytes
        ? sizeBytes - _edgeBytes
        : _edgeBytes;
    await _addRange(hasher, video, tailStart, sizeBytes);
    hasher.close();
    return 'v_${digestSink.digest.toString().substring(0, _idHexLength)}';
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

Future<void> _addRange(
  Sink<List<int>> hasher,
  File video,
  int startByte,
  int endByte,
) async {
  if (startByte >= endByte) return;
  await for (final chunk in video.openRead(startByte, endByte)) {
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
