import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/data/linked_audio_downloader.dart';
import 'package:status_studio/src/features/topic/application/topic_progress.dart';
import 'package:status_studio/src/features/topic/data/topic_store.dart';
import 'package:status_studio/src/features/topic/domain/moment_candidate.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/topic_errors.dart';
import 'package:status_studio/src/features/topic/domain/topic_prompts.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/data/groq_chat_client.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/data/youtube_captions_fetcher.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// A wait this long can only be the daily allowance (spec FR-36).
const _dailyLimitWait = Duration(minutes: 15);

/// What [TopicFinder] works with; tests override each.
class TopicFinderServices {
  const TopicFinderServices({
    required this.captions,
    required this.audio,
    required this.scripts,
    required this.store,
    required this.groq,
    this.wait = Future<void>.delayed,
    this.clock = DateTime.now,
  });

  final YouTubeCaptionsFetcher captions;
  final LinkedAudioDownloader audio;
  final ScriptPipeline scripts;
  final Future<TopicStore> store;

  /// Throws [NoGroqKeyException], then [NoGroqConsentException].
  final Future<GroqClient> Function() groq;
  final Future<void> Function(Duration) wait;
  final DateTime Function() clock;
}

/// Finds the moments of a linked video about a topic (spec FR-36): the
/// transcript, cheapest first, then Groq reads it in parts. Every moment
/// found comes back for the user to tick; everything is saved, so the same
/// link or topic again sends nothing.
class TopicFinder {
  const TopicFinder(this.services);

  final TopicFinderServices services;

  /// Ends with [TopicFound]. Throws [LinkTooLongException],
  /// [NoMomentsFoundException], [GroqDailyLimitException] and the Groq,
  /// network and script errors.
  Stream<TopicProgress> find(TopicRequest request) async* {
    if (isTooLongForTopics(request)) {
      throw LinkTooLongException(request.video.duration);
    }
    final transcript = _Holder<List<TranscriptBlock>>();
    yield* _transcriptBlocks(request, transcript);
    final found = _Holder<List<MomentCandidate>>();
    yield* _candidates(request, transcript.value, found);
    final cuts = candidatesAsCuts(found.value, transcript.value);
    if (cuts.isEmpty) {
      throw const NoMomentsFoundException();
    }
    yield TopicFound(cuts: cuts, blocks: transcript.value);
  }

  /// Stops an audio download under way; the stream's own cancel stops the
  /// rest at its next step.
  Future<void> cancel(TopicRequest request) =>
      services.audio.cancel(request.video);

  /// The transcript in the output language (spec FR-36, M50): YouTube's
  /// captions when they are in it, else written by Groq from the audio in
  /// it. Saved per language, so a transcript in another one isn't reused.
  Stream<TopicProgress> _transcriptBlocks(
    TopicRequest request,
    _Holder<List<TranscriptBlock>> result,
  ) async* {
    final store = await services.store;
    final youTubeId = request.video.videoId;
    final language = request.outputLanguage;
    final saved = await store.savedBlocks(youTubeId, language);
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
    await store.saveBlocks(youTubeId, language, result.value);
  }

  Stream<TopicProgress> _writtenByGroq(
    TopicRequest request,
    _Holder<List<TranscriptLine>> result,
  ) async* {
    final video = request.video;
    final downloaded = StreamController<double>();
    final download =
        services.audio
            .download(video, onProgress: downloaded.add)
            .whenComplete(downloaded.close)
          ..ignore();
    await for (final fraction in downloaded.stream) {
      yield TopicStep('Downloading the audio', fraction: fraction);
    }
    final audio = await download;
    await for (final progress in services.scripts.run(
      audio,
      request.outputLanguage,
    )) {
      yield TopicStep(progress.stage.label, fraction: progress.fraction);
      result.value = progress.transcript.lines;
    }
  }

  Stream<TopicProgress> _candidates(
    TopicRequest request,
    List<TranscriptBlock> blocks,
    _Holder<List<MomentCandidate>> result,
  ) async* {
    final store = await services.store;
    final youTubeId = request.video.videoId;
    final key = (
      search: (topic: request.topic, outputLanguage: request.outputLanguage),
      transcript: transcriptKeyOf(blocks),
    );
    final saved = await store.savedCandidates(youTubeId, key);
    if (saved != null) {
      result.value = saved;
      return;
    }
    final client = await services.groq();
    final candidates = <MomentCandidate>[];
    final parts = partsOf(blocks);
    for (final (index, part) in parts.indexed) {
      yield TopicStep(
        'Reading the transcript, part ${index + 1} of ${parts.length}',
        fraction: index / parts.length,
      );
      final reply = _Holder<Map<String, Object?>>();
      yield* _patiently(client, _partChat(request, part), reply);
      candidates.addAll(candidatesFromReply(reply.value, part));
    }
    result.value = candidates;
    await store.saveCandidates(youTubeId, key, candidates);
  }

  /// Sends [chat], waiting out Groq's limits and saying when it carries on
  /// (spec FR-36). The client already waits out a minute or less.
  Stream<TopicProgress> _patiently(
    GroqClient client,
    GroqChatRequest chat,
    _Holder<Map<String, Object?>> result,
  ) async* {
    while (true) {
      try {
        result.value = await client.chatJson(chat);
        return;
      } on GroqRateLimitedException catch (limit) {
        if (limit.retryAfter > _dailyLimitWait) {
          throw GroqDailyLimitException(limit.retryAfter);
        }
        yield WaitingForGroq(services.clock().add(limit.retryAfter));
        await services.wait(limit.retryAfter);
      }
    }
  }

  GroqChatRequest _partChat(TopicRequest request, List<TranscriptBlock> part) =>
      GroqChatRequest(
        model: topicModel,
        instructions: partInstructions(request.topic, request.outputLanguage),
        message: partMessage(part),
      );
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
      groq: ref.watch(groqChatClientProvider),
    ),
  ),
);
