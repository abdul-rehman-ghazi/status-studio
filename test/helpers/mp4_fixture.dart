import 'dart:typed_data';

/// An MP4 head as YouTube's DASH streams start: `ftyp` + `moov` (filler)
/// making [initBytes] in all, then a `sidx` box listing [references] as
/// (referenced size in bytes, duration in [timescale] ticks).
Uint8List buildMp4Head({
  required int initBytes,
  required int timescale,
  required List<(int size, int duration)> references,
  int version = 0,
}) {
  final builder = BytesBuilder()
    ..add(_box('ftyp', [..._ascii('iso6'), 0, 0, 0, 0]))
    ..add(_box('moov', List.filled(initBytes - 16 - 8, 0)))
    ..add(_sidx(timescale, references, version));
  return builder.toBytes();
}

/// A box of [type] whose payload is [payload].
Uint8List box(String type, List<int> payload) => _box(type, payload);

Uint8List _sidx(
  int timescale,
  List<(int size, int duration)> references,
  int version,
) {
  final timeBytes = version == 0 ? 4 : 8;
  final payload = ByteData(12 + timeBytes * 2 + 4 + references.length * 12);
  var at = 0;
  payload.setUint32(at, version << 24);
  at += 4;
  payload.setUint32(at, 1);
  at += 4;
  payload.setUint32(at, timescale);
  at += 4;
  at += timeBytes * 2;
  payload.setUint16(at + 2, references.length);
  at += 4;
  for (final (size, duration) in references) {
    payload
      ..setUint32(at, size & 0x7fffffff)
      ..setUint32(at + 4, duration)
      ..setUint32(at + 8, 0x90000000);
    at += 12;
  }
  return _box('sidx', payload.buffer.asUint8List());
}

Uint8List _box(String type, List<int> payload) {
  final header = ByteData(8)..setUint32(0, 8 + payload.length);
  return (BytesBuilder()
        ..add(header.buffer.asUint8List(0, 4))
        ..add(_ascii(type))
        ..add(payload))
      .toBytes();
}

List<int> _ascii(String text) => text.codeUnits;
