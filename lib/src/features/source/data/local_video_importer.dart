import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/core/ffmpeg/media_probe.dart';
import 'package:status_studio/src/features/source/data/free_storage.dart';
import 'package:status_studio/src/features/source/data/io_error_mapping.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/video_fingerprint.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

/// Room left on the phone after a copy, for the rest of the app (spec FR-1).
const _spareBytes = 50 * 1024 * 1024;

class LocalVideoImporterServices {
  const LocalVideoImporterServices({
    required this.cache,
    required this.transcripts,
    required this.probe,
    required this.storage,
    required this.incomingFolder,
  });

  final SourceCache cache;
  final TranscriptStore transcripts;
  final MediaProbe probe;
  final FreeStorage storage;

  /// Where shared videos are staged (`files/incoming/`, spec FR-1).
  final Directory incomingFolder;
}

/// The only code that reads a picked or shared video and keeps it in app
/// storage, as `sources/<videoId>/source.<ext>` (spec FR-1, §4).
class LocalVideoImporter {
  const LocalVideoImporter(this._services);

  final LocalVideoImporterServices _services;

  /// Keeps the video at [path] and returns it. A file staged in the
  /// incoming folder is moved; any other is copied, and left unchanged.
  ///
  /// Throws [VideoUnreadableException] when the file can't be read or has no
  /// audio track, and [InsufficientStorageException] when a copy won't fit.
  /// A staged file is deleted whenever it can't be kept.
  Future<SourceVideo> importVideo({
    required String path,
    required String displayName,
  }) async {
    final file = File(path);
    try {
      final video = await _keep(file, displayName);
      await _services.transcripts.saveVideo(video);
      return video;
    } catch (_) {
      await _deleteIfStaged(file);
      rethrow;
    }
  }

  Future<SourceVideo> _keep(File file, String displayName) async {
    final facts = await _services.probe.readLocalVideo(file.path);
    final videoId = await videoFingerprint(file);
    final video = SourceVideo(
      videoId: videoId,
      title: _nameWithoutExtension(displayName),
      duration: facts.duration,
    );
    if (_services.cache.keptLocalVideos(videoId).isNotEmpty) {
      await _deleteIfStaged(file);
      return video;
    }
    final target = _services.cache.localVideoFile(
      videoId,
      _extensionOf(displayName, file.path),
    );
    if (await _isStaged(file)) {
      await _move(file, target);
    } else {
      await _copy(file, target);
    }
    return video;
  }

  Future<void> _move(File staged, File target) async {
    await target.parent.create(recursive: true);
    try {
      await staged.rename(target.path);
    } on FileSystemException {
      // The staging folder and the sources folder are on different volumes.
      await _copy(staged, target);
      await staged.delete();
    }
  }

  Future<void> _copy(File file, File target) async {
    final sizeBytes = await file.length();
    await _requireRoomFor(sizeBytes);
    await guardIo(
      () => _services.cache.write(
        target,
        file.openRead(),
        totalBytes: sizeBytes,
        onProgress: (_) {},
      ),
    );
  }

  Future<void> _requireRoomFor(int sizeBytes) async {
    final freeBytes = await _services.storage.freeBytes();
    if (freeBytes - sizeBytes < _spareBytes) {
      throw const InsufficientStorageException(
        'Not enough free space for this video.',
      );
    }
  }

  Future<bool> _isStaged(File file) async {
    if (!await _services.incomingFolder.exists()) {
      return false;
    }
    final staging = await _services.incomingFolder.resolveSymbolicLinks();
    final location = await file.resolveSymbolicLinks();
    return location.startsWith('$staging${Platform.pathSeparator}');
  }

  Future<void> _deleteIfStaged(File file) async {
    if (await file.exists() && await _isStaged(file)) {
      await file.delete();
    }
  }
}

String _nameWithoutExtension(String displayName) {
  final dot = displayName.lastIndexOf('.');
  return dot > 0 ? displayName.substring(0, dot) : displayName;
}

/// Lower case and plain, since it becomes part of a file name; `mp4` when
/// the sender's name has none.
String _extensionOf(String displayName, String path) {
  for (final name in [displayName, path.split(Platform.pathSeparator).last]) {
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (RegExp(r'^[a-z0-9]{1,5}$').hasMatch(extension)) {
      return extension;
    }
  }
  return 'mp4';
}

final localVideoImporterProvider = FutureProvider<LocalVideoImporter>((
  ref,
) async {
  final support = await getApplicationSupportDirectory();
  return LocalVideoImporter(
    LocalVideoImporterServices(
      cache: await ref.watch(sourceCacheProvider.future),
      transcripts: await ref.watch(transcriptStoreProvider.future),
      probe: ref.watch(mediaProbeProvider),
      storage: ref.watch(freeStorageProvider),
      incomingFolder: Directory('${support.path}/incoming'),
    ),
  );
});
