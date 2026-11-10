import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/core/ffmpeg/local_video_facts.dart';
import 'package:status_studio/src/core/ffmpeg/media_probe.dart';
import 'package:status_studio/src/features/source/data/free_storage.dart';
import 'package:status_studio/src/features/source/data/io_error_mapping.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/video_converter.dart';
import 'package:status_studio/src/features/source/data/video_fingerprint.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

/// Room left on the phone after a copy, for the rest of the app (spec FR-1).
const _spareBytes = 50 * 1024 * 1024;

Future<File> _renameFile(File file, String newPath) => file.rename(newPath);

/// A converted copy is not the incoming size; H.264 needs about twice AV1's
/// bytes for the same picture.
const _convertedSizeFactor = 2;

/// One video being imported, as the steps after the probe need it.
class _IncomingVideo {
  const _IncomingVideo({
    required this.file,
    required this.displayName,
    required this.needsH264Copy,
    required this.onConversionProgress,
  });

  final File file;
  final String displayName;
  final bool needsH264Copy;
  final void Function(double fraction) onConversionProgress;
}

void _ignoreConversionProgress(double fraction) {}

class LocalVideoImporterServices {
  const LocalVideoImporterServices({
    required this.cache,
    required this.transcripts,
    required this.probe,
    required this.converter,
    required this.storage,
    required this.incomingFolder,
    required this.pickerCacheFolder,
    this.rename = _renameFile,
  });

  final SourceCache cache;
  final TranscriptStore transcripts;
  final MediaProbe probe;
  final VideoConverter converter;
  final FreeStorage storage;

  /// Where shared videos are staged (`files/incoming/`, spec FR-1).
  final Directory incomingFolder;

  /// The folder where `image_picker` puts its copy of a picked video.
  final Directory pickerCacheFolder;

  /// Moves a file to a new path; replaceable so tests can make it fail the
  /// way a move between volumes does.
  final Future<File> Function(File file, String newPath) rename;
}

/// The only code that reads a picked or shared video and keeps it in app
/// storage, as `sources/<videoId>/source.<ext>` (spec FR-1, §4).
class LocalVideoImporter {
  LocalVideoImporter(this._services);

  final LocalVideoImporterServices _services;

  /// Imports running now, by video ID, so the same video arriving twice at
  /// once is kept once.
  final _keeping = <String, Future<void>>{};

  /// Keeps the video at [path] and returns it. A file the app already owns
  /// (staged in the incoming folder, or the picker's copy in the cache) is
  /// moved; any other is copied, and left unchanged. An AV1 video is kept as
  /// an H.264 copy instead, and [onConversionProgress] hears how far that is,
  /// from 0 as it starts.
  ///
  /// Throws [VideoUnreadableException] when the file can't be read or has no
  /// audio track, [InsufficientStorageException] when a copy won't fit, and
  /// [VideoNotConvertibleException] when an AV1 video can't be converted.
  /// A file the app owns is deleted whether or not it could be kept.
  Future<SourceVideo> importVideo({
    required String path,
    required String displayName,
    void Function(double fraction) onConversionProgress =
        _ignoreConversionProgress,
  }) async {
    final file = File(path);
    try {
      final facts = await _services.probe.readLocalVideo(file.path);
      final video = await _describe(file, displayName, facts);
      final incoming = _IncomingVideo(
        file: file,
        displayName: displayName,
        needsH264Copy: facts.needsH264Copy,
        onConversionProgress: onConversionProgress,
      );
      await _keepOnce(video, incoming);
      return video;
    } finally {
      await _deleteIfOwned(file);
    }
  }

  Future<SourceVideo> _describe(
    File file,
    String displayName,
    LocalVideoFacts facts,
  ) async {
    return SourceVideo(
      videoId: await videoFingerprint(file),
      title: _titleOf(displayName, file.path),
      duration: facts.duration,
    );
  }

  Future<void> _keepOnce(SourceVideo video, _IncomingVideo incoming) {
    final running = _keeping[video.videoId];
    if (running != null) {
      return running;
    }
    final keeping = _keepAndRemember(video, incoming);
    _keeping[video.videoId] = keeping;
    return keeping;
  }

  Future<void> _keepAndRemember(
    SourceVideo video,
    _IncomingVideo incoming,
  ) async {
    try {
      await _keep(video.videoId, incoming);
      await _services.transcripts.saveVideo(video);
    } finally {
      // Awaiting it would wait for this very future.
      unawaited(_keeping.remove(video.videoId)!);
    }
  }

  Future<void> _keep(String videoId, _IncomingVideo incoming) async {
    final target = incoming.needsH264Copy
        ? await _keptConverted(videoId, incoming)
        : await _keptAsIs(videoId, incoming);
    await _deleteOtherKeptVideos(videoId, keep: target);
  }

  Future<File> _keptAsIs(String videoId, _IncomingVideo incoming) async {
    final file = incoming.file;
    final sizeBytes = await file.length();
    final intact = await _keptOfSize(videoId, sizeBytes);
    if (intact.isNotEmpty) {
      return intact.first;
    }
    final target = _services.cache.localVideoFile(
      videoId,
      _extensionOf(incoming.displayName, file.path),
    );
    await _place(file, target, sizeBytes);
    return target;
  }

  /// A finished conversion is only ever renamed into place, so a kept copy
  /// is whole and is reused.
  Future<File> _keptConverted(String videoId, _IncomingVideo incoming) async {
    final target = _services.cache.convertedVideoFile(videoId);
    if (await target.exists()) {
      return target;
    }
    incoming.onConversionProgress(0);
    await _requireRoomFor(await incoming.file.length() * _convertedSizeFactor);
    final working = _services.cache.convertingVideoFile(videoId);
    await _deleteIfPresent(working);
    await working.parent.create(recursive: true);
    try {
      await _services.converter.convertToH264(
        inputPath: incoming.file.path,
        outputPath: working.path,
        onProgress: incoming.onConversionProgress,
      );
      await working.rename(target.path);
    } finally {
      await _deleteIfPresent(working);
    }
    return target;
  }

  Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Kept videos that are as long as the incoming file: an earlier copy that
  /// was cut short is not reused.
  Future<List<File>> _keptOfSize(String videoId, int sizeBytes) async {
    final intact = <File>[];
    for (final kept in _services.cache.keptLocalVideos(videoId)) {
      if (await kept.length() == sizeBytes) {
        intact.add(kept);
      }
    }
    return intact;
  }

  Future<void> _deleteOtherKeptVideos(
    String videoId, {
    required File keep,
  }) async {
    for (final kept in _services.cache.keptLocalVideos(videoId)) {
      if (kept.path != keep.path) {
        await kept.delete();
      }
    }
  }

  Future<void> _place(File file, File target, int sizeBytes) async {
    if (await _isOwned(file)) {
      await _move(file, target, sizeBytes);
      return;
    }
    await _copy(file, target, sizeBytes);
  }

  Future<void> _move(File owned, File target, int sizeBytes) async {
    await target.parent.create(recursive: true);
    try {
      await _services.rename(owned, target.path);
    } on FileSystemException {
      // The incoming or cache folder and the sources folder are on
      // different volumes. The owned file is deleted once the import ends.
      await _copy(owned, target, sizeBytes);
    }
  }

  Future<void> _copy(File file, File target, int sizeBytes) async {
    await _requireRoomFor(sizeBytes);
    try {
      await guardIo(
        () => _services.cache.write(
          target,
          file.openRead(),
          totalBytes: sizeBytes,
          onProgress: (_) {},
        ),
      );
    } on IncompleteDownloadException catch (error) {
      throw VideoUnreadableException(
        'The video changed while it was copied: ${error.reason}',
      );
    }
  }

  /// Skipped when the phone can't say how much is free: the copy then fails
  /// on its own if the space runs out.
  Future<void> _requireRoomFor(int sizeBytes) async {
    final int freeBytes;
    try {
      freeBytes = await _services.storage.freeBytes();
    } on StorageUnknownException {
      return;
    }
    if (freeBytes - sizeBytes < _spareBytes) {
      throw const InsufficientStorageException(
        'Not enough free space for this video.',
      );
    }
  }

  Future<bool> _isOwned(File file) async {
    for (final folder in [
      _services.incomingFolder,
      _services.pickerCacheFolder,
    ]) {
      if (await _isInside(file, folder)) {
        return true;
      }
    }
    return false;
  }

  /// Symbolic links and `..` are resolved first, so a path can't claim to
  /// be inside a folder it only points into.
  Future<bool> _isInside(File file, Directory folder) async {
    if (!await folder.exists()) {
      return false;
    }
    final folderPath = await folder.resolveSymbolicLinks();
    final location = await file.resolveSymbolicLinks();
    return location.startsWith('$folderPath${Platform.pathSeparator}');
  }

  Future<void> _deleteIfOwned(File file) async {
    if (await file.exists() && await _isOwned(file)) {
      await file.delete();
    }
  }
}

/// The sender's name without its extension; the file's own name when the
/// sender gave none, and a plain word when that is empty too.
String _titleOf(String displayName, String path) {
  for (final name in [displayName, path.split(Platform.pathSeparator).last]) {
    final title = _withoutExtension(name).trim();
    if (title.isNotEmpty) {
      return title;
    }
  }
  return 'Video';
}

String _withoutExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
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

/// Where `image_picker` leaves its copy of a picked video: the cache folder
/// on Android, but iOS's `tmp` folder, which is not what `path_provider` calls
/// the temporary folder there (it answers `Library/Caches`). Dart's
/// `systemTemp` is `tmp` on iOS.
Future<Directory> _pickerCopyFolder() async =>
    Platform.isIOS ? Directory.systemTemp : getTemporaryDirectory();

final localVideoImporterProvider = FutureProvider<LocalVideoImporter>((
  ref,
) async {
  final support = await getApplicationSupportDirectory();
  final pickerFolder = await _pickerCopyFolder();
  return LocalVideoImporter(
    LocalVideoImporterServices(
      cache: await ref.watch(sourceCacheProvider.future),
      transcripts: await ref.watch(transcriptStoreProvider.future),
      probe: ref.watch(mediaProbeProvider),
      converter: ref.watch(videoConverterProvider),
      storage: ref.watch(freeStorageProvider),
      incomingFolder: Directory('${support.path}/incoming'),
      pickerCacheFolder: pickerFolder,
    ),
  );
});
