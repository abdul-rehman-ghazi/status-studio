# M2 — Video Source Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pasted YouTube link shows real metadata. The audio downloads for transcription, a ≤720p source video is prepared in the background, and Fine-tune plays the real clip.

**Architecture:** `YouTubeVideoSource` (the only class that touches `youtube_explode_dart`) implements the M1 `VideoSource` interface, extended with downloads. Downloads go through `SourceCache` (`sources/<videoId>/` in the temp dir, `.part` files renamed on completion). Video and audio are muxed with FFmpeg stream copy into `source.mp4` for preview and rendering.

**Tech Stack:** youtube_explode_dart 3, ffmpeg_kit_flutter_new_min 2, video_player 2, path_provider 2.

**Spec:** `docs/superpowers/specs/2026-10-29-status-studio-design.md` (FR-1, FR-5, §4 Storage/Quality caps, §8)

## Global Constraints

- M1 Global Constraints apply.
- Video ≤ 720p, prefer MP4 container; audio = highest-bitrate audio-only, prefer MP4/M4A container.
- Only `YouTubeVideoSource` imports `youtube_explode_dart`. Only `lib/src/core/ffmpeg/` imports FFmpeg Kit.
- Never return null for failures: throw `VideoUnavailableException`, `OfflineException` or `InsufficientStorageException` (all in `lib/src/features/source/domain/source_errors.dart`).
- Tests never hit the network.

## Review Focus

- **A download interrupted midway** must not leave a file that later looks complete. Test: Task 2 `partial_download_is_not_reused`.
- **A video with no MP4 stream at or below 720p** must still pick something (lowest available above 720p, else WebM). Test: Task 1 `falls_back_to_lowest_stream_above_cap`.
- **Pasting the same link twice** must reuse the cached audio/video, not download again. Test: Task 2 `complete_file_is_reused`.
- **Private, age-restricted or removed videos** must show "This video can't be downloaded." Test: Task 3 `maps_unavailable_errors`.
- **Leaving Fine-tune while playing** must dispose the player (no audio continuing in the background). Test: Task 5 `player_disposed_when_screen_closes`.

---

### Task 1: Stream choice

**Files:** Create `lib/src/features/source/domain/stream_choice.dart`, `lib/src/features/source/domain/source_errors.dart` (needed here for `VideoUnavailableException`); Test `test/src/features/source/domain/stream_choice_test.dart`

**Interfaces:**
- Produces: `class StreamChoice { const StreamChoice({required int height, required String container, required int bitrate, required int index}); }`. Height is 0 for audio, and `index` points back into the manifest list.
- `StreamChoice pickVideoStream(List<StreamChoice> videoStreams, {int maxHeight = 720})`
- `StreamChoice pickAudioStream(List<StreamChoice> audioStreams)`
- Both throw `VideoUnavailableException` on an empty list.

- [x] **Step 1: Failing tests:** `picks_highest_mp4_at_or_below_cap` (720 mp4 over 1080 mp4 and 720 webm), `prefers_mp4_over_webm_at_same_height`, `falls_back_to_lowest_stream_above_cap` (only 1080 and 1440 → 1080), `picks_highest_bitrate_mp4_audio`, `empty_list_throws_unavailable`.
- [x] **Step 2: Run** `fvm flutter test test/src/features/source/domain` → FAIL.
- [x] **Step 3: Implement** the two pure functions.
- [x] **Step 4: Run** → PASS.
- [x] **Step 5: Commit** `feat: choose YouTube streams within quality caps`

### Task 2: Source cache and resumable-safe writes

**Files:** Create `lib/src/features/source/data/source_cache.dart`; Test `test/src/features/source/data/source_cache_test.dart`

**Interfaces:**
- Produces: `class SourceCache { SourceCache(Directory root); File audioFile(String videoId, String extension); File videoFile(String videoId); File sourceFile(String videoId); Future<File> write(File target, Stream<List<int>> bytes, {required int totalBytes, required void Function(double fraction) onProgress}); bool isComplete(File target); }`
- `final sourceCacheProvider = FutureProvider<SourceCache>(...)` rooted at `getTemporaryDirectory()/sources`.

- [x] **Step 1: Failing tests** (temp dir):
  - `write_reports_progress_to_one`
  - `write_renames_part_file_on_completion`
  - `partial_download_is_not_reused`: the stream errors halfway → `isComplete` is false and no target file exists.
  - `complete_file_is_reused`
- [x] **Step 2–4:** Run → FAIL, implement (`<name>.part` then `rename`), run → PASS.
- [x] **Step 5: Commit** `feat: add source cache with atomic writes`

### Task 3: YouTube video source

**Files:**
- Create `lib/src/features/source/data/youtube_video_source.dart`, `lib/src/features/source/domain/source_errors.dart`, `lib/src/core/ffmpeg/mux_arguments.dart`, `lib/src/core/ffmpeg/ffmpeg_runner.dart`
- Modify `video_source.dart` (interface + provider now returns `YouTubeVideoSource`)
- Test `test/src/features/source/data/youtube_error_mapping_test.dart`, `test/src/core/ffmpeg/mux_arguments_test.dart`

**Interfaces:**
- `VideoSource` becomes:
  - `Future<SourceVideo> fetchVideo(String videoId)`
  - `Future<File> downloadAudio(SourceVideo video, {required void Function(double fraction) onProgress})`
  - `Future<File> prepareSourceVideo(SourceVideo video, {required void Function(double fraction) onProgress})`
- `Exception mapYouTubeError(Object error)`: youtube_explode `VideoUnavailableException`/`VideoRequiresPurchaseException`/`VideoUnplayableException` → `VideoUnavailableException`; `SocketException`/`HttpException` → `OfflineException`; `FileSystemException` with "No space" → `InsufficientStorageException`; anything else rethrown as is.
- `List<String> muxArguments({required String videoPath, required String audioPath, required String outputPath})` → `['-y', '-i', videoPath, '-i', audioPath, '-map', '0:v:0', '-map', '1:a:0', '-c', 'copy', '-movflags', '+faststart', outputPath]`
- `class FfmpegRunner { Future<void> run(List<String> arguments, {void Function(Duration processed)? onTime}); Future<void> cancel(); }` throws `FfmpegFailedException(String log)` on a non-success return code. This is the single FFmpeg entry point, also used by M3/M5.

- [x] **Step 1: Failing tests:** `maps_unavailable_errors`, `maps_socket_errors_to_offline`, `mux_copies_streams_without_reencoding` (exact list above).
- [x] **Step 2–4:** Run → FAIL. Implement:
  - Metadata via `yt.videos.get(videoId)`.
  - The manifest via `yt.videos.streamsClient.getManifest(videoId)`, mapped to `StreamChoice`s.
  - Bytes via `yt.videos.streamsClient.get(streamInfo)`.
  - `prepareSourceVideo` downloads the video, reuses the audio, muxes into `sourceFile`, and splits progress 90 % download / 10 % mux.
  - Close `YoutubeExplode` in `ref.onDispose`.
  
  Run → PASS.
- [ ] **Step 5: Manual check:** `fvm flutter run --release` on a phone. Paste a public video link; the title, channel and duration match YouTube.
- [x] **Step 6: Commit** `feat: fetch YouTube metadata and download sources`

### Task 4: Source preparation in the background

**Files:** Create `lib/src/features/source/application/source_video_controller.dart`; Modify `source_screen.dart`, `processing_screen.dart`; Test `test/src/features/source/application/source_video_controller_test.dart`

**Interfaces:**
- `final sourceVideoProvider = AsyncNotifierProvider.family<SourceVideoController, File?, String>(...)`, keyed by video ID, with `Future<void> prepare(SourceVideo video)`. Progress is a separate `sourceVideoProgressProvider` family (`NotifierProvider.family<…, double, String>`). Keying by video ID keeps a second reel from ever seeing the first reel's file or progress; `prepare` shares an in-flight run and retries only after a failure.
- Processing calls `prepare` once the audio download finishes, so the video downloads while transcription runs.

- [x] **Step 1: Failing tests** with a fake `VideoSource`:
  - `prepare_exposes_file_when_done`
  - `prepare_twice_for_same_video_downloads_once`
  - `failure_surfaces_as_error_state`
- [x] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [x] **Step 5: Commit** `feat: prepare source video in the background`

### Task 5: Clip player on Fine-tune

**Files:** Create `lib/src/features/clip/presentation/clip_player.dart`, `lib/src/features/clip/domain/clip_playback.dart`; Modify `fine_tune_screen.dart`; Test `test/src/features/clip/domain/clip_playback_test.dart`, `test/src/features/clip/presentation/fine_tune_screen_test.dart`

**Interfaces:**
- `bool shouldStopPlayback(Duration position, ClipRange clip)`: true when `position >= clip.end`.
- `class ClipPlayer extends StatefulWidget { const ClipPlayer({super.key, required File source, required ClipRange clip}); }`
  - Owns a `VideoPlayerController.file` and seeks to `clip.start` on play.
  - A listener pauses when `shouldStopPlayback`.
  - Disposes in `dispose`.
- While the source isn't ready, Fine-tune shows the M1 placeholder with "Preparing video… NN %".

- [x] **Step 1: Failing tests:**
  - `stops_at_clip_end`
  - `keeps_playing_before_clip_end`
  - `player_disposed_when_screen_closes`: the widget test injects a fake controller factory through a `videoPlayerFactoryProvider` and asserts `dispose` was called after `pop`.
- [x] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Manual check:** play a selected clip; it starts at the start line and stops at the end line.
- [x] **Step 6: Commit** `feat: play the selected clip on fine-tune`
