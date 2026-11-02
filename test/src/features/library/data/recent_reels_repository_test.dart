import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:status_studio/src/features/library/data/recent_reels_repository.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

void main() {
  late Directory folder;
  late RecentReelsRepository repository;
  final created = DateTime.utc(2026, 11, 2, 12);

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    folder = await Directory.systemTemp.createTemp('recent_reels_test');
    repository = RecentReelsRepository(SharedPreferencesAsync());
  });

  tearDown(() => folder.delete(recursive: true));

  /// A reel whose MP4 and thumbnail exist on disk.
  RecentReel reel(int number) {
    final video = File('${folder.path}/$number.mp4')..writeAsStringSync('v');
    final thumbnail = File('${folder.path}/$number.jpg')
      ..writeAsStringSync('t');
    return RecentReel(
      id: '$number',
      title: 'Reel $number',
      videoPath: video.path,
      thumbnailPath: thumbnail.path,
      duration: const Duration(seconds: 27),
      size: const OutputSize(1080, 1920),
      createdAt: created.add(Duration(minutes: number)),
    );
  }

  test('add_puts_newest_first', () async {
    await repository.add(reel(1));
    await repository.add(reel(2));

    final ids = (await repository.load()).map((reel) => reel.id);

    expect(ids, ['2', '1']);
  });

  test('round_trips_every_field', () async {
    final first = reel(1);
    await repository.add(first);

    expect((await repository.load()).single, first);
  });

  test('adding_beyond_fifty_drops_oldest_and_its_files', () async {
    for (var number = 1; number <= 50; number++) {
      await repository.add(reel(number));
    }
    final oldest = (await repository.load()).last;

    await repository.add(reel(51));

    final reels = await repository.load();
    expect(
      (
        reels.length,
        reels.any((reel) => reel.id == oldest.id),
        File(oldest.videoPath).existsSync(),
        File(oldest.thumbnailPath).existsSync(),
      ),
      (50, false, false, false),
    );
  });

  test('delete_removes_entry_and_files', () async {
    final doomed = reel(1);
    await repository.add(doomed);

    await repository.delete(doomed.id);

    expect(
      (
        (await repository.load()).length,
        File(doomed.videoPath).existsSync(),
        File(doomed.thumbnailPath).existsSync(),
      ),
      (0, false, false),
    );
  });

  test('load_skips_reels_with_missing_files', () async {
    final gone = reel(1);
    await repository.add(gone);
    await repository.add(reel(2));
    File(gone.videoPath).deleteSync();

    final ids = (await repository.load()).map((reel) => reel.id);

    expect(ids, ['2']);
  });

  test('unreadable_entry_hides_only_itself', () async {
    await repository.add(reel(1));
    final stored = jsonDecode(
      (await SharedPreferencesAsync().getString('recentReels'))!,
    ) as List<Object?>;
    await SharedPreferencesAsync().setString(
      'recentReels',
      jsonEncode([
        ...stored,
        {'id': 'from a later version'},
      ]),
    );

    final ids = (await repository.load()).map((reel) => reel.id);

    expect(ids, ['1']);
  });

  test('add_keeps_unreadable_entries', () async {
    const unreadable = {'id': 'from a later version'};
    await SharedPreferencesAsync().setString(
      'recentReels',
      jsonEncode([unreadable]),
    );

    await repository.add(reel(1));

    final stored = jsonDecode(
      (await SharedPreferencesAsync().getString('recentReels'))!,
    ) as List<Object?>;
    expect(stored, contains(equals(unreadable)));
  });

  test('add_keeps_an_unreadable_list', () async {
    await SharedPreferencesAsync().setString('recentReels', '{not json');

    await repository.add(reel(1));

    final stored = jsonDecode(
      (await SharedPreferencesAsync().getString('recentReels'))!,
    ) as List<Object?>;
    expect(stored, contains('{not json'));
  });

  test('corrupt_json_yields_empty_list', () async {
    await SharedPreferencesAsync().setString('recentReels', '{not json');

    expect(await repository.load(), isEmpty);
  });
}
