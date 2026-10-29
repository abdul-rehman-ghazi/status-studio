# M3 — On-device Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Script screen shows the video's real script with timestamps. It comes from YouTube captions when available, otherwise from Whisper on the phone, and appears progressively. With automatic language, the language is inferred and shown.

**Architecture:**
- `RealScriptPipeline` implements M1's `ScriptPipeline`, composing `ModelManager`, `VideoSource`, `YouTubeCaptionSource`, `AudioPreparer` and `WhisperTranscriber`.
- Whisper runs on 90-second WAV chunks with `keepModelLoaded: true`, emitting lines per chunk.
- A `ScriptProgressController` holds the pipeline stream, so Processing and Script both watch it.

**Tech Stack:** whisper_ggml 2.8, youtube_explode_dart 3, ffmpeg_kit_flutter_new_min 2.

**Spec:** FR-2, FR-3, FR-12 (download part), FR-13, §6.4, §8, §10 Q2.

## Global Constraints

- M1 and M2 Global Constraints apply.
- Chunk length 90 s. Model default `WhisperModel.small`; `WhisperModel.base` is selectable (M6 adds the setting; until then a `whisperModelProvider` returns `small`).
- `whisper_ggml` returns `null` on failure: wrap it and throw `TranscriptionFailedException`. An empty full transcript throws `NoSpeechFoundException`.
- Release the parked model (`releaseModel()`) when a run finishes, fails or is cancelled.
- Only `whisper_transcriber.dart` and `model_manager.dart` import `whisper_ggml`.

## Review Focus

- **Cancelling during transcription** must stop work and release the model. Test: Task 6 `cancel_releases_model`.
- **Silence, music-only or bracketed tokens** (`[BLANK_AUDIO]`, `(music)`, `♪`) must not become lines. Test: Task 4 `drops_non_speech_segments`.
- **A model download interrupted** must not leave a file that `whisper_ggml` loads as a model. Test: Task 2 `interrupted_download_leaves_no_model`.
- **A video with only auto-generated captions in another language** must fall back to Whisper when the user picked a language. Test: Task 5 `ignores_tracks_in_other_language_when_language_chosen`.
- **Lines straddling a chunk boundary** keep the correct absolute times. Test: Task 4 `offsets_segment_times_by_chunk_start`.

---

### Task 1: Spike — Whisper speed and quality on device

**Files:** Modify `docs/superpowers/specs/2026-10-29-status-studio-design.md` §10 Q2 (record results). Throwaway code lives on a spike branch and is not merged.

- [ ] **Step 1:** On a branch `spike/whisper`, add a debug-only route that transcribes a WAV from the source cache with `WhisperModel.base` and `.small`, logging wall time and the first five segments.
- [ ] **Step 2:** On a mid-range Android phone in `--release`, run a 5-minute Urdu speech clip and a 5-minute sung clip, each as one file and as 90-second chunks.
- [ ] **Step 3:** Record in spec §10 Q2: times per model, whether chunking split words badly, and the recommended default model. If small takes longer than 2× real time, change the default to base in the spec and Global Constraints.
- [ ] **Step 4:** Commit the spec change only — `docs: record whisper spike results`

### Task 2: Model manager

**Files:** Create `lib/src/features/transcript/data/model_manager.dart`; Test `test/src/features/transcript/data/model_manager_test.dart`

**Interfaces:**
- `class ModelManager { ModelManager({required Future<String> Function(WhisperModel) pathFor, required HttpClient httpClient}); Future<bool> isDownloaded(WhisperModel model); Stream<double> download(WhisperModel model); Future<void> delete(WhisperModel model); Future<int> sizeOnDisk(WhisperModel model); }`
- Downloads `model.modelUri` to `pathFor(model) + '.part'` with progress, renames on success, and throws `ModelDownloadException` on any failure.
- `modelManagerProvider` wires `WhisperController().getPath` and a real `HttpClient`.

- [ ] **Step 1: Failing tests** with a local `HttpServer` and temp dir:
  - `download_reports_progress_and_creates_model`
  - `interrupted_download_leaves_no_model` (server closes the socket halfway)
  - `delete_removes_model`
  - `is_downloaded_false_for_part_file`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: download and manage whisper models`

### Task 3: Audio preparation

**Files:** Create `lib/src/core/ffmpeg/audio_arguments.dart`, `lib/src/features/transcript/data/audio_preparer.dart`; Test `test/src/core/ffmpeg/audio_arguments_test.dart`

**Interfaces:**
- `List<String> wavArguments({required String inputPath, required String outputPath})` → `['-y', '-i', inputPath, '-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le', outputPath]`
- `List<String> chunkArguments({required String wavPath, required String outputPattern, required int chunkSeconds})` → `['-y', '-i', wavPath, '-f', 'segment', '-segment_time', '$chunkSeconds', '-c', 'copy', outputPattern]` (pattern `chunk_%03d.wav`)
- `class AudioPreparer { AudioPreparer(FfmpegRunner runner); Future<File> toWav(File audio); Future<List<File>> splitIntoChunks(File wav, {int chunkSeconds = 90}); }` returns chunks sorted by name. `toWav` output (`audio.wav`) is reused by M4's waveform.

- [ ] **Step 1: Failing tests:** `wav_arguments_make_16khz_mono_pcm`, `chunk_arguments_use_segment_muxer`.
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: prepare 16 kHz WAV chunks for whisper`

### Task 4: Whisper transcriber and language inference

**Files:**
- Create `lib/src/features/transcript/data/whisper_transcriber.dart`, `lib/src/features/transcript/domain/segment_lines.dart`, `lib/src/features/transcript/domain/language_inference.dart`
- Test `test/src/features/transcript/domain/segment_lines_test.dart`, `language_inference_test.dart`

**Interfaces:**
- `class SpeechSegment { const SpeechSegment({required Duration from, required Duration to, required String text}); }`
- `List<TranscriptLine> linesFromSegments(List<SpeechSegment> segments, {required Duration offset, required int firstIndex})`
  - Trims text and adds `offset` to times.
  - Drops segments whose trimmed text is empty or entirely a bracketed token (`[...]`, `(...)`) or music symbols.
- `String inferLanguageCode(String text)`, per spec §6.4, using `core/script_detection.dart` (extend it with Persian letters, Devanagari, Bengali, Gurmukhi ranges).
- `class WhisperTranscriber { Stream<List<TranscriptLine>> transcribeChunks(List<File> chunks, {required ScriptLanguage language, required WhisperModel model}); Future<void> cancel(); }`
  - Emits each chunk's lines.
  - Chunk *i* has offset *i* × 90 s.
  - Calls `transcribe(..., withSegments: true, keepModelLoaded: true, lang: language.whisperCode)`.
  - Throws `TranscriptionFailedException` on `null`.
  - Calls `releaseModel()` in a `finally`.

- [ ] **Step 1: Failing tests:**
  - `offsets_segment_times_by_chunk_start`: offset 90 s, segment 3–7 s → line 1:33–1:37.
  - `numbers_lines_from_first_index`
  - `drops_non_speech_segments`
  - `trims_whitespace`
  - Language inference:
    - `urdu_letters_infer_ur` (`یہ اچھی بات ہے`)
    - `persian_letters_without_urdu_infer_fa` (`چگونه`: has `چ` and `گ`, no Urdu-only letters)
    - `plain_arabic_infers_ar` (`السلام عليكم`)
    - `devanagari_infers_hi` (`नमस्ते`)
    - `latin_infers_en`
    - `unknown_script_infers_und` (`你好`)
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: transcribe chunks with whisper and infer language`

### Task 5: YouTube captions

**Files:** Create `lib/src/features/transcript/data/youtube_caption_source.dart`, `lib/src/features/transcript/domain/caption_track_choice.dart`; Test `test/src/features/transcript/domain/caption_track_choice_test.dart`

**Interfaces:**
- `class CaptionTrackChoice { const CaptionTrackChoice({required String languageCode, required bool isAutoGenerated, required int index}); }`
- `CaptionTrackChoice pickCaptionTrack(List<CaptionTrackChoice> tracks, ScriptLanguage language)`
  - Throws `NoCaptionTrackException`.
  - With `auto`, any language is allowed; otherwise the code must match `language.whisperCode`.
  - Manual tracks beat auto-generated ones.
- `class YouTubeCaptionSource { Future<Transcript> fetch(SourceVideo video, ScriptLanguage language); }`
  - Uses `yt.videos.closedCaptions.getManifest` and `.get`.
  - Each `ClosedCaption` (`text`, `offset`, `end`) becomes a line; empty ones are skipped.
  - `languageCode` comes from the track.

- [ ] **Step 1: Failing tests:**
  - `prefers_manual_track`
  - `auto_language_accepts_any_track`
  - `ignores_tracks_in_other_language_when_language_chosen`
  - `no_tracks_throws`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: use YouTube captions when available`

### Task 6: Real script pipeline and progressive script

**Files:**
- Create `lib/src/features/transcript/application/real_script_pipeline.dart`, `lib/src/features/transcript/application/script_progress_controller.dart`
- Modify `script_pipeline.dart` (provider → real), `processing_screen.dart`, `script_screen.dart`
- Test `test/src/features/transcript/application/real_script_pipeline_test.dart`, `script_progress_controller_test.dart`

**Interfaces:**
- `class ScriptPipelineServices { const ScriptPipelineServices({required ModelManager models, required VideoSource videos, required YouTubeCaptionSource captions, required AudioPreparer audio, required WhisperTranscriber whisper}); }`. It's a value object, which keeps the pipeline within the 3-parameter rule.
- `RealScriptPipeline(ScriptPipelineServices services, {required WhisperModel model})`
- Stage order and overall `fraction` ranges:

  | Stage | Fraction | When |
  |---|---|---|
  | `downloadingModel` | 0.00–0.15 | only when the model is missing |
  | `downloadingAudio` | → 0.30 | |
  | `detectingLanguage` | 0.35 | |
  | `transcribing` | → 1.00 | proportional to finished chunks |
  | `done` | 1.00 | |

  When captions succeed, `transcribing` jumps straight to 1.0.
- With `ScriptLanguage.auto`, the transcript's `languageCode` = `inferLanguageCode(all line text)` for Whisper output, or the track code for captions.
- `final scriptProgressProvider = NotifierProvider<ScriptProgressController, AsyncValue<ScriptProgress>>(...)` with `void start(SourceVideo video, ScriptLanguage language)` and `Future<void> cancel()`.
- Processing shows "Start picking lines" once the transcript has ≥ 1 line. Script appends lines as they arrive and shows "Still writing… NN %" at the bottom until `done`.

- [ ] **Step 1: Failing tests** with fakes for every dependency:
  - `uses_captions_when_track_exists`
  - `falls_back_to_whisper_without_captions`
  - `downloads_model_first_when_missing`
  - `emits_lines_progressively_per_chunk`
  - `auto_language_sets_inferred_code`
  - `empty_transcript_throws_no_speech`
  - `cancel_releases_model`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Error states.** Processing maps exceptions to spec §8 messages using `errorMessageFor` (create `lib/src/core/error_messages.dart` with tests `maps_no_speech`, `maps_offline`, `maps_model_download`).
- [ ] **Step 6: Manual check** in `--release`:
  - A video with captions: the script appears within seconds.
  - A video without captions: lines appear chunk by chunk, and the language shows "Urdu (detected)" for Urdu speech.
- [ ] **Step 7: Commit** `feat: real script pipeline with progressive lines`
