# M2b — Data Saver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app downloads only what it needs: the lowest-bitrate audio for the script, and only the clip window of video and audio once the user reaches Fine-tune. For a 30-second clip from a 1-hour video, that's roughly 10–30 MB instead of over 1 GB.

**Architecture:**
- MP4 DASH streams carry a segment index (`sidx` box) near the start of the file. `SegmentIndex` parses it.
- `segmentsCovering` picks the byte ranges for a time window. `RangedDownloader` fetches only those ranges with HTTP `Range` requests and writes init + segments as one fragmented MP4.
- `ClipSourcePreparer` downloads video and audio for the window and muxes them by stream copy (`FfmpegRunner`) into a clip file with a known `offset`. Streams without an index fall back to M2's full download.

**Tech Stack:** dart:io `HttpClient`, youtube_explode_dart (stream URLs only), ffmpeg_kit_flutter_new_min (stream-copy mux only).

**Spec:** FR-3 (script audio), FR-5, FR-15, §4 Quality and data caps, §6.1 `ClipWindow`/`ClipSource`.

**Builds on M2 as implemented:** `VideoSource` (`fetchVideo`, `downloadAudio`, `prepareSourceVideo`), `SourceCache`, `StreamChoice` + `pickVideoStream`/`pickAudioStream`, `FfmpegRunner`, `muxArguments`, `SourceVideoController`, `ClipPlayer(source:, clip:)`.

## Global Constraints

- M1 and M2 Global Constraints apply.
- The bundled FFmpeg has no TLS: it can't read stream URLs. All network I/O is Dart `HttpClient`.
- Clip window = from clip start − 5 s to max(clip end + 5 s, clip start + 30 s), clamped to the video.
- Script audio = lowest-bitrate MP4 audio. Clip audio = highest-bitrate MP4 audio. Video ≤ 720p, MP4 preferred (unchanged from M2).
- The head fetch for the index starts at 64 KiB and doubles up to 2 MiB; beyond that the stream counts as having no index.
- Nothing of the video is downloaded before Fine-tune.
- Only `YouTubeVideoSource` imports `youtube_explode_dart`.

## Review Focus

- **A clip at the very start or end of the video** gives a window clamped to 0 and to the duration. Tests: Task 3 `window_clamped_at_video_start`, `window_clamped_at_video_end`.
- **A server that ignores `Range` and returns 200 with the whole file** must not be written as the clip. Test: Task 4 `rejects_response_without_partial_content`.
- **An expired stream URL (403)** refreshes the manifest and retries once, then fails with a typed error. Test: Task 5 `retries_once_after_expired_url`.
- **Nudging past the downloaded window** downloads a new window; nudging inside it reuses the file. Tests: Task 5 `reuses_window_that_still_covers_clip`, `downloads_new_window_when_clip_leaves_it`.
- **A stream without `sidx`** (WebM, or unusual MP4) falls back to the full download instead of failing. Test: Task 5 `falls_back_to_full_download_without_index`.

---

### Task 1: Script audio at the lowest bitrate

**Files:**
- Modify `lib/src/features/source/domain/stream_choice.dart`, `lib/src/features/source/data/video_source.dart`, `lib/src/features/source/data/youtube_video_source.dart`, `lib/src/features/source/data/source_cache.dart`
- Test `test/src/features/source/domain/stream_choice_test.dart`

**Interfaces:**
- Produces:
  - `StreamChoice pickScriptAudioStream(List<StreamChoice> audioStreams)`: lowest bitrate among MP4; if there's no MP4, the lowest overall. Throws `VideoUnavailableException` when empty.
  - `VideoSource.downloadAudio` is renamed **`downloadScriptAudio`** (same signature) and uses `pickScriptAudioStream`.
  - `SourceCache.audioFile` is renamed `scriptAudioFile`.
  - `pickAudioStream` (highest bitrate) stays for clip audio.

- [ ] **Step 1: Failing tests:**
  - `script_audio_picks_lowest_bitrate_mp4`: 48 k mp4 over 128 k mp4 and 50 k webm.
  - `script_audio_falls_back_to_lowest_any_container`
  - `script_audio_empty_list_throws_unavailable`
- [ ] **Step 2:** Run `fvm flutter test test/src/features/source` → FAIL.
- [ ] **Step 3:** Implement, then rename and update every caller (Processing, fakes, tests).
- [ ] **Step 4:** Run → PASS. Then `fvm flutter analyze` → "No issues found!".
- [ ] **Step 5: Commit** `feat: download script audio at the lowest bitrate`

### Task 2: MP4 segment index parser

**Files:** Create `lib/src/features/source/domain/segment_index.dart`; Test `test/src/features/source/domain/segment_index_test.dart`, `test/helpers/mp4_fixture.dart`

**Interfaces:**
- Produces:
  - `class ByteRange { const ByteRange(int first, int last); int get length; }`. Both ends are inclusive, as in HTTP.
  - `class MediaSegment { const MediaSegment({required ByteRange bytes, required Duration start, required Duration duration}); Duration get end; }`
  - `class SegmentIndex { const SegmentIndex({required ByteRange init, required List<MediaSegment> segments}); }`. `init` covers from byte 0 to the byte before `sidx` (ftyp + moov).
  - `SegmentIndex parseSegmentIndex(Uint8List head)`. It walks top-level ISO-BMFF boxes (32-bit size + type, with size 1 meaning a 64-bit size) until it finds `sidx`. It throws `SegmentIndexNotFoundException(int bytesNeeded)` when `head` ends before `sidx` is complete, and `NoSegmentIndexException` when a `moof`/`mdat` appears before any `sidx`.
  - `sidx` layout:
    - version (1 byte) + flags (3); reference_ID (4); timescale (4).
    - earliest_presentation_time and first_offset: 4 bytes each if version 0, 8 if version 1.
    - reserved (2); reference_count (2).
    - Per reference: 1-bit type + 31-bit referenced_size, subsegment_duration (4), SAP fields (4).
  - The first segment starts at (end of `sidx` box) + first_offset. Segment start times accumulate from earliest_presentation_time ÷ timescale.
- Test helper: `Uint8List buildMp4Head({required int initBytes, required int timescale, required List<(int size, int duration)> references, int version = 0})` builds an `ftyp` + `moov` (filler) + `sidx`.

- [ ] **Step 1: Failing tests:**
  - `parses_segments_from_version_0_sidx`: timescale 1000, refs (100000 B, 5000), (120000 B, 5000) after 800 B of init. The first segment's bytes start right after `sidx`; starts are 0 s and 5 s.
  - `parses_version_1_sidx_with_64_bit_times`
  - `init_range_ends_before_sidx`
  - `short_head_throws_not_found_with_bytes_needed`
  - `moof_before_sidx_throws_no_index`
- [ ] **Step 2:** Run `fvm flutter test test/src/features/source/domain/segment_index_test.dart` → FAIL.
- [ ] **Step 3:** Implement with `ByteData` big-endian reads. The parser is pure, with no I/O.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat: parse MP4 segment index`

### Task 3: Clip window and segment selection

**Files:** Create `lib/src/features/clip/domain/clip_window.dart`; Modify `segment_index.dart`; Test `test/src/features/clip/domain/clip_window_test.dart`, extend `segment_index_test.dart`

**Interfaces:**
- Produces:
  - `class ClipWindow { const ClipWindow({required Duration start, required Duration end}); bool covers(ClipRange clip); }`
  - `ClipWindow clipWindowFor(ClipRange clip, Duration videoDuration)`. M4's waveform uses the same window.
  - `List<MediaSegment> segmentsCovering(SegmentIndex index, ClipWindow window)`: the contiguous run of segments from the one containing `window.start` through the one containing `window.end`.
  - `ByteRange mergedRange(List<MediaSegment> segments)`

- [ ] **Step 1: Failing tests:**
  - `window_pads_five_seconds_each_side`: clip 1:00–1:40, video 6:48 → 0:55–1:45.
  - `window_is_at_least_thirty_seconds`: clip 1:00–1:05 → 0:55–1:30.
  - `window_clamped_at_video_start`
  - `window_clamped_at_video_end`
  - `covers_clip_inside_window`
  - `selects_segments_overlapping_window`: 5 s segments, window 0:12–0:31 → segments starting 0:10…0:30.
  - `merged_range_spans_first_to_last_segment`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: compute clip window and covering segments`

### Task 4: Ranged downloader

**Files:** Create `lib/src/features/source/data/ranged_downloader.dart`; Test `test/src/features/source/data/ranged_downloader_test.dart`

**Interfaces:**
- Produces:
  - `class RangedDownloader { RangedDownloader(HttpClient client); Future<Uint8List> fetchHead(Uri url, int length); Future<File> downloadRanges(Uri url, List<ByteRange> ranges, File target, {required void Function(double fraction) onProgress}); }`
  - Each request sends `Range: bytes=first-last` and requires status 206; otherwise it throws `RangeNotSupportedException`. Status 403 throws `ExpiredStreamUrlException`.
  - Ranges are appended in order to `target.part`, then renamed (same atomic pattern as `SourceCache.write`).

- [ ] **Step 1: Failing tests** against a local `HttpServer` that honours `Range`:
  - `downloads_requested_ranges_in_order`: init + two segments; the bytes equal the concatenation.
  - `reports_progress_to_one`
  - `rejects_response_without_partial_content`: the server ignores `Range` and returns 200 → throws, and no target exists.
  - `forbidden_throws_expired_url`
  - `fetch_head_returns_first_bytes`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: download byte ranges`

### Task 5: Clip source preparer

**Files:**
- Create `lib/src/features/source/data/clip_source_preparer.dart`, `lib/src/features/source/domain/clip_source.dart`
- Modify `video_source.dart`, `youtube_video_source.dart`, `source_cache.dart`
- Test `test/src/features/source/data/clip_source_preparer_test.dart`

**Interfaces:**
- Consumes: Tasks 2–4; `muxArguments` and `FfmpegRunner` (M2).
- Produces:
  - `class ClipSource { const ClipSource({required File file, required Duration offset, required ClipWindow window}); }`
  - `VideoSource` gains `Future<StreamUrls> streamUrls(SourceVideo video)`, where `class StreamUrls { const StreamUrls({required Uri video, required Uri audio, required bool videoIsMp4, required bool audioIsMp4}); }`. The booleans describe the streams; they aren't behaviour-switching parameters. The video stream uses `pickVideoStream`, the audio `pickAudioStream`.
  - `class ClipSourcePreparer { ClipSourcePreparer({required VideoSource videos, required RangedDownloader downloader, required FfmpegRunner ffmpeg}); Future<ClipSource> prepare(ClipPrepareRequest request, {required void Function(double fraction) onProgress}); }`, with `class ClipPrepareRequest { const ClipPrepareRequest({required SourceVideo video, required ClipRange clip, required SourceCache cache}); }`
  - Behaviour:
    1. Reuse the cached `ClipSource` for this video if its window covers the clip.
    2. Otherwise compute `clipWindowFor`. For each stream, `fetchHead` (64 KiB, doubling to 2 MiB on `SegmentIndexNotFoundException`), `parseSegmentIndex`, `segmentsCovering`, then download `[init, mergedRange]`.
    3. Mux with `muxArguments` into `SourceCache.clipFile(videoId, window)` (`clip_<startMs>_<endMs>.mp4`).
    4. `offset` = the earlier of the first video and first audio segment start.
    5. Without an index, or on `RangeNotSupportedException`, fall back to `prepareSourceVideo` with `offset: Duration.zero` and a window of the whole video.
    6. On `ExpiredStreamUrlException`, call `streamUrls` again and retry once.
  - Progress is split as video 70 %, audio 25 %, mux 5 %.

- [ ] **Step 1: Failing tests** with fake `VideoSource`, `RangedDownloader` and `FfmpegRunner`:
  - `downloads_only_covering_ranges`
  - `reuses_window_that_still_covers_clip`
  - `downloads_new_window_when_clip_leaves_it`
  - `offset_is_earliest_segment_start`
  - `falls_back_to_full_download_without_index`
  - `retries_once_after_expired_url`
  - `second_expired_url_surfaces_unavailable`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: prepare clip-only sources`

### Task 6: Fine-tune downloads only the clip

**Files:**
- Modify `source_video_controller.dart` (becomes `ClipSourceController`), `processing_screen.dart`, `fine_tune_screen.dart`, `clip_player.dart`, and the style preview if it reads the source file
- Test `test/src/features/source/application/clip_source_controller_test.dart`, `test/src/features/clip/presentation/fine_tune_screen_test.dart`

**Interfaces:**
- Produces:
  - `final clipSourceProvider = AsyncNotifierProvider<ClipSourceController, ClipSource?>(...)` with `Future<void> prepareFor(SourceVideo video, ClipRange clip)`. It's single-flight per window (reuse M2's `single_flight.dart`).
  - `ClipPlayer({required ClipSource source, required ClipRange clip})` seeks to `clip.start - source.offset` and stops at `clip.end - source.offset`.
- Behaviour:
  - Processing no longer starts any video download.
  - Fine-tune calls `prepareFor` on open and after any nudge whose clip leaves the current window.
  - It shows "Downloading clip… NN %" until ready.

- [ ] **Step 1: Failing tests:**
  - `processing_does_not_download_video` (fake `VideoSource` records calls)
  - `fine_tune_prepares_clip_on_open`
  - `nudge_inside_window_does_not_redownload`
  - `player_seeks_relative_to_offset` (fake controller factory records the seek: clip 1:00, offset 0:55 → 0:05)
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Manual check** in `--release` on a phone with a long public video:
  - Pick a 30 s clip near the middle and watch Android's per-app data usage. The clip download should be tens of MB, not the full video.
  - The clip plays in sync.
  - Nudging past the window triggers a short new download.
- [ ] **Step 6:** Run `fvm flutter analyze && fvm flutter test`. Expected: clean, all pass.
- [ ] **Step 7: Commit** `feat: download only the clip on fine-tune`
