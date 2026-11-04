import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/json_files.dart';

void main() {
  late Directory folder;
  late File target;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('json_files_test');
    target = File('${folder.path}/nested/value.json');
  });

  tearDown(() => folder.delete(recursive: true));

  test('written_json_reads_back', () async {
    await writeJsonAtomically(target, {'name': 'علم', 'count': 3});

    expect(await readJsonObject(target), {'name': 'علم', 'count': 3});
  });

  test('writing_leaves_no_part_file', () async {
    await writeJsonAtomically(target, {'a': 1});

    expect(File('${target.path}.part').existsSync(), isFalse);
  });

  test('a_leftover_part_file_does_not_change_the_target', () async {
    await writeJsonAtomically(target, {'a': 1});
    await File('${target.path}.part').writeAsString('{"a": 2');

    expect(await readJsonObject(target), {'a': 1});
  });

  test('a_json_list_is_rejected', () async {
    await target.parent.create(recursive: true);
    await target.writeAsString('[1, 2]');

    await expectLater(readJsonObject(target), throwsFormatException);
  });
}
