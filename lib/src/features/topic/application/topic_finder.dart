import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/data/linked_audio_downloader.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/topic/application/topic_progress.dart';
import 'package:status_studio/src/features/topic/data/topic_store.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';
import 'package:status_studio/src/features/topic/domain/topic_errors.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/data/youtube_captions_fetcher.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// What [TopicFinder] works with; tests override each.
class TopicFinderServices {
  const TopicFinderServices({
    required this.captions,
    required this.audio,
    required this.scripts,
    required this.store,
  });

  final YouTubeCaptionsFetcher captions;
  final LinkedAudioDownloader audio;
  final ScriptPipeline scripts;
  final Future<TopicStore> store;
}

/// Gets the script of a linked or kept video, cheapest first (spec FR-36,
/// FR-43, FR-51): the user picks every moment from it. It is saved, so the
/// same video again sends nothing.
class TopicFinder {
  const TopicFinder(this.services);

  final TopicFinderServices services;

  /// Ends with [TopicFound]. Throws [LinkTooLongException] and the Groq,
  /// network and script errors.
  Stream<TopicProgress> find(TopicRequest request) async* {
    if (isTooLongForTopics(request)) {
      throw LinkTooLongException(request.source.duration);
    }
    final transcript = _Holder<List<TranscriptBlock>>();
    yield* _transcriptBlocks(request, transcript);
    yield TopicFound(transcript.value);
  }

  /// Stops an audio download under way; the stream's own cancel stops the
  /// rest at its next step.
  Future<void> cancel(TopicRequest request) async {
    if (request.source case LinkedMoments(:final video)) {
      await services.audio.cancel(video);
    }
  }

  /// The transcript in the output language (spec FR-36, M50): YouTube's
  /// captions when they are in it, else written by Groq from the audio in
  /// it. Saved per language, so a transcript in another one isn't reused.
  Stream<TopicProgress> _transcriptBlocks(
    TopicRequest request,
    _Holder<List<TranscriptBlock>> result,
  ) async* {
    final store = await services.store;
    final videoKey = request.source.key;
    final language = request.outputLanguage;
    final saved = await store.savedBlocks(videoKey, language);
    if (saved != null) {
      result.value = saved;
      return;
    }
    final lines = _Holder<List<TranscriptLine>>();
    final captionsUrl = captionsUrlFor(request);
    if (captionsUrl != null) {
      yield const TopicStep('Getting the captions');
      lines.value = await services.captions.fetch(captionsUrl);
    } else {
      yield* _writtenByGroq(request, lines);
    }
    result.value = blocksFromLines(lines.value);
    await store.saveBlocks(videoKey, language, result.value);
    // Only after the save: until then the audio and pieces let an
    // interrupted Groq run resume. A transcript in another language
    // downloads the audio again (FR-47).
    if (request.source case LinkedMoments(:final video)) {
      await services.audio.deleteDownloaded(video);
    }
  }

  /// From a link, the audio is downloaded first; a kept video's own file
  /// is cleaned and sent, as Lyrics does (spec FR-51). A saved script for
  /// the video and language (FR-14) opens without sending anything.
  Stream<TopicProgress> _writtenByGroq(
    TopicRequest request,
    _Holder<List<TranscriptLine>> result,
  ) async* {
    final audio = _Holder<SourceVideo>();
    switch (request.source) {
      case LinkedMoments(:final video):
        yield* _downloadedAudio(video, audio);
      case LocalMoments(:final video):
        audio.value = video;
    }
    await for (final progress in services.scripts.run(
      audio.value,
      request.outputLanguage,
    )) {
      yield TopicStep(progress.stage.label, fraction: progress.fraction);
      result.value = progress.transcript.lines;
    }
  }

  Stream<TopicProgress> _downloadedAudio(
    LinkedVideo video,
    _Holder<SourceVideo> result,
  ) async* {
    final downloaded = StreamController<double>();
    final download =
        services.audio
            .download(video, onProgress: downloaded.add)
            .whenComplete(downloaded.close)
          ..ignore();
    await for (final fraction in downloaded.stream) {
      yield TopicStep('Downloading the audio', fraction: fraction);
    }
    result.value = await download;
  }
}

/// Carries a generator's result out to its caller: a generator can't both
/// yield progress and return a value.
class _Holder<T> {
  late T value;
}

final topicFinderProvider = Provider<TopicFinder>(
  (ref) => TopicFinder(
    TopicFinderServices(
      captions: ref.watch(youTubeCaptionsFetcherProvider),
      audio: ref.watch(linkedAudioDownloaderProvider),
      scripts: ref.watch(scriptPipelineProvider),
      store: ref.watch(topicStoreProvider.future),
    ),
  ),
);
