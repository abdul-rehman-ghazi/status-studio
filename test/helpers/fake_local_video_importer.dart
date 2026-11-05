import 'package:status_studio/src/features/source/data/local_video_importer.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

/// Imports every file as a 6:48 video named after the file, or throws
/// [failure] from every import when it is set. Nothing touches the disk.
class FakeLocalVideoImporter implements LocalVideoImporter {
  FakeLocalVideoImporter({this.failure});

  final Exception? failure;
  final imported = <String>[];

  @override
  Future<SourceVideo> importVideo({
    required String path,
    required String displayName,
  }) async {
    imported.add(path);
    if (failure case final failure?) {
      throw failure;
    }
    final dot = displayName.lastIndexOf('.');
    return SourceVideo(
      videoId: 'v_0123456789abcdef',
      title: dot > 0 ? displayName.substring(0, dot) : displayName,
      duration: const Duration(minutes: 6, seconds: 48),
    );
  }
}
