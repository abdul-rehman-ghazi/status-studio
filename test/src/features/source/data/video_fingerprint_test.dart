import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/data/video_fingerprint.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const _mebibyte = 1024 * 1024;

void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('fingerprint'));
  tearDown(() => folder.deleteSync(recursive: true));

  Uint8List patternBytes(int length) =>
      Uint8List.fromList([for (var i = 0; i < length; i++) (i * 7) % 251]);

  File videoWith(Uint8List bytes, [String name = 'clip.mp4']) =>
      File('${folder.path}/$name')..writeAsBytesSync(bytes);

  Uint8List withByteChangedAt(Uint8List bytes, int index) =>
      Uint8List.fromList(bytes)..[index] ^= 0xff;

  test('same_bytes_give_the_same_id', () async {
    final bytes = patternBytes(3 * _mebibyte);
    final original = videoWith(bytes, 'original.mp4');
    final renamedCopy = videoWith(bytes, 'copy.mov');

    expect(
      await videoFingerprint(original),
      await videoFingerprint(renamedCopy),
    );
  });

  test('a_different_file_gives_a_different_id', () async {
    final first = videoWith(patternBytes(3 * _mebibyte), 'a.mp4');
    final second = videoWith(patternBytes(3 * _mebibyte + 1), 'b.mp4');

    expect(
      await videoFingerprint(first),
      isNot(await videoFingerprint(second)),
    );
  });

  test('a_change_in_the_first_mebibyte_changes_the_id', () async {
    final bytes = patternBytes(3 * _mebibyte);
    final original = videoWith(bytes, 'a.mp4');
    final edited = videoWith(withByteChangedAt(bytes, 100), 'b.mp4');

    expect(
      await videoFingerprint(original),
      isNot(await videoFingerprint(edited)),
    );
  });

  test('a_change_in_the_last_mebibyte_changes_the_id', () async {
    final bytes = patternBytes(3 * _mebibyte);
    final original = videoWith(bytes, 'a.mp4');
    final edited = videoWith(
      withByteChangedAt(bytes, bytes.length - 100),
      'b.mp4',
    );

    expect(
      await videoFingerprint(original),
      isNot(await videoFingerprint(edited)),
    );
  });

  test('a_file_under_one_mebibyte_gets_an_id', () async {
    final tiny = videoWith(patternBytes(1000));

    expect(await videoFingerprint(tiny), matches(RegExp(r'^v_[0-9a-f]{16}$')));
  });

  test('a_change_in_a_file_under_two_mebibytes_changes_the_id', () async {
    final bytes = patternBytes(_mebibyte + 500);
    final original = videoWith(bytes, 'a.mp4');
    final edited = videoWith(withByteChangedAt(bytes, _mebibyte + 10), 'b.mp4');

    expect(
      await videoFingerprint(original),
      isNot(await videoFingerprint(edited)),
    );
  });

  test('the_id_is_v_and_sixteen_lowercase_hex_digits', () async {
    final video = videoWith(patternBytes(3 * _mebibyte));

    expect(await videoFingerprint(video), matches(RegExp(r'^v_[0-9a-f]{16}$')));
  });

  test('a_missing_file_throws_video_unreadable', () {
    final missing = File('${folder.path}/missing.mp4');

    expect(videoFingerprint(missing), throwsA(isA<VideoUnreadableException>()));
  });
}
