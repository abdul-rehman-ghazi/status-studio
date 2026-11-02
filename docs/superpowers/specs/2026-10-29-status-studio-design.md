# Status Studio — Product and Technical Spec

**Date:** 2026-10-29 (updated 2026-10-30: data saving, saved scripts, Media3 render) · **Status:** approved for implementation · **Design canvas:** https://claude.ai/artifact/HcKksQmAu8ZYBfQdbnr2RN

## 1. Summary

Status Studio turns any YouTube video, in any language, into a short clip for WhatsApp Status, Reels, TikTok or Shorts. The user pastes a link, the app writes out the video's script on the phone, the user taps the line where the clip starts and the line where it ends, picks a size and caption, and exports an MP4 carrying the Status Studio name and logo.

Everything after the download runs on the device: speech-to-text (Whisper), translation (ML Kit) and rendering (Media3 Transformer on Android). No accounts, no servers, no analytics.

To save the user's data, the app downloads only what it needs:
- The script's audio at low quality, or nothing when YouTube has captions.
- Only the clip's part of the video, once the user has picked it.

Scripts are saved, so the same video opens straight to its script next time.

## 2. Flow and screens

| # | Screen | Route | Job |
|---|---|---|---|
| 1 | Home | `/` | Start a reel; list recent reels; open Settings |
| 2 | Source | `/source` | Paste a YouTube link; choose language (default automatic) |
| 3 | Processing | `/processing` | Download audio → detect language → transcribe → line up timestamps (skipped when a saved script exists, FR-14) |
| 4 | Script | `/script` | Show the full script; tap the start line, then the end line |
| 5 | Fine-tune | `/fine-tune` | Download only the clip (FR-15); preview it; nudge start and end by ±0.5 s |
| 6 | Style | `/style` | Size, fill, crop, caption text/variant/position/size; live preview with branding |
| 7 | Export | `/export` | Render with progress; cancel returns to Style |
| 8 | Done | `/done` | Final preview; Save to gallery; Share; Make another |
| 9 | Settings | `/settings` | Whisper model (base or small), download or delete it |

The prototype on the design canvas is the visual reference for screens 1–8. Settings follows the same visual language.

## 3. Functional requirements

**FR-1 Link input.** Accept `youtube.com/watch?v=ID`, `m.youtube.com/watch?v=ID`, `youtu.be/ID`, `youtube.com/shorts/ID` and `youtube.com/live/ID`, with or without `https://`, extra query parameters or surrounding whitespace. A video ID is 11 characters of `[A-Za-z0-9_-]`. Anything else shows "That doesn't look like a YouTube link." After a valid link, show title, channel and duration.

**FR-2 Language.** Dropdown: Detect automatically (default), Urdu, Arabic, Punjabi, Persian, Hindi, Bengali, English. The Script screen has the same dropdown; changing it re-runs transcription in that language.

**FR-3 Script.** Sources, in this order:
1. A **saved script** for this video and language (FR-14): open Script directly.
2. A **YouTube caption track** in the chosen language: manual tracks over auto-generated. When the language is automatic, only manual tracks (in any language) are used: YouTube guesses an auto-generated track's language from the audio, and a wrong guess makes the whole script junk (found on the phone: an Urdu naat's only track was auto-generated Romanian). Each caption becomes one line, and no audio is downloaded.
3. **Whisper** (`whisper_ggml`, `withSegments: true`) on the **lowest-bitrate MP4 audio-only stream**. Whisper hears 16 kHz mono, so higher quality only wastes data. Each segment becomes one line.
- Transcribe in **90-second chunks**, keeping the model loaded, so lines appear while the rest is still being processed. Chunk timestamps are offset by the chunk start.
- With "Detect automatically", infer the language from the transcript text (§6.4) and show it ("Urdu (detected)").
- No speech found → error state (§8).

**FR-4 Line selection.** First tap sets the start line. A tap on the same or a later line sets the end line. A tap on an earlier line, or any tap once both are set, starts over with that line as the start. Lines between start and end are highlighted. "Next" is enabled only when both are set.

**FR-5 Fine-tune.** Opening Fine-tune downloads the clip (FR-15); the preview shows download progress until it's ready. The clip starts at the start line's start and ends at the end line's end. Buttons move start or end by 0.5 s. A nudge that would make the clip shorter than **3 s** or move it outside the video is ignored. The preview plays only the clip range and stops at its end.

**FR-6 Frame.**

| Preset | Output size |
|---|---|
| 9:16 (default) | 1080 × 1920 |
| 4:5 | 1080 × 1350 |
| 1:1 | 1080 × 1080 |
| 16:9 | 1920 × 1080 (original framing, no crop) |
| Free | the crop rectangle in source pixels, scaled so the long side ≤ 1920, both sides rounded down to even numbers |

- Presets other than 16:9 offer **Fill: Crop to fill** (default) or **Blur background**. Crop to fill offers **Keep in view: Left / Center (default) / Right**.
- Free crop: drag to move, drag the corner to resize. Each side is at least **12 %** of the source. The rectangle never leaves the frame. Reset returns to the default rectangle (left 30 %, top 4 %, width 40 %, height 92 %).

**FR-7 Caption.**
- Default text: the selected lines' text, one per line.
- Variants: **Original**, **Roman** (only when the transcript language is Urdu; rule-based transliteration), **English** (ML Kit on-device; hidden when ML Kit doesn't support the source language, e.g. Punjabi).
- The text is editable. Switching variant replaces edits with that variant's text.
- Position: Top or Bottom (default). Size: S, M (default), L = font size of 4.5 %, 5.5 %, 6.8 % of output width.
- Font by script (§6.5). Line height 2.1 for Nastaliq, 1.3 otherwise.
- Block: centred, black at 38 % opacity behind the text, padding 2 % of output width, margin 6 % of output height from the edge.
- If the block would exceed 35 % of output height, shrink the font in 5 % steps down to 60 % of the chosen size, then clip with an ellipsis.

**FR-8 Branding (always on).** A pill with the Trim logo and "Status Studio" in Inter SemiBold. Logo height 4.5 % of output width; text at 55 % of the logo height; pill black at 45 % opacity; inset 4 % of output width from the left edge and from the top or bottom edge. It sits at the top when the caption is at the bottom, and at the bottom otherwise.

**FR-9 Export.** MP4, H.264 video, AAC audio, source frame rate, rendered by Media3 Transformer (§5). Progress comes from Media3's progress. Cancel stops the render, deletes the partial file and returns to Style.

**FR-10 Save and share.** Save to gallery (`gal`). Share opens the system share sheet with the MP4 (`share_plus`).

**FR-11 Recent reels.** Newest first, at most 50 (oldest dropped and its file deleted). Each row shows a thumbnail, the first caption line, duration and date. Tap opens Done for that reel. Long-press offers Delete.

**FR-12 Settings.** Model: any multilingual Whisper model (tiny, base, small, medium, large-v3; default small, marked "recommended"), each with its download size or size on disk and Download / Delete. An info button opens a sheet with the model's pros and cons (speed relative to small, accuracy, memory it needs). English-only models aren't offered: they can't write other languages. Downloads show progress. If transcription starts without the model, the model downloads first as a step on the Processing screen.

**FR-13 Offline.** With the model downloaded and the source cached, transcription, translation (once its ML Kit language pack is downloaded) and export work without a network.

**FR-14 Saved scripts.**
- **What's saved:** every finished script, keyed by video ID, requested language (`auto` or a code) and source (`captions` or `whisper-<model>`, e.g. `whisper-small`). The entry holds the transcript (with the inferred language), the source and the save date.
- **Same link again:** pasting a link whose script is saved for the chosen language skips Processing. Script opens with the banner "Using the saved script from <d MMM> · Write it again".
- **Write it again:** runs Whisper with the current model and replaces the saved script.
- **Resume:** Whisper progress is saved after each 90-second piece, so an interrupted run resumes from the next piece.
- **Storage:** scripts live in the app support directory under `transcripts/`. Each is kept 90 days after last use, with at most 200 videos (least recently used dropped).

**FR-15 Clip-only download.**
- **When:** nothing of the video is downloaded before Fine-tune.
- **Window:** Fine-tune downloads only the part covering the clip **window**: from clip start − 5 s to max(clip end + 5 s, clip start + 30 s), clamped to the video.
- **What:** ≤ 720p MP4 video plus highest-bitrate MP4 audio.
- **How:** the app reads each stream's MP4 segment index (`sidx`) and fetches just those segments with HTTP range requests.
- **Clip file:** video and audio are muxed by stream copy into one clip file. Its time zero is `offset` in the video; times shown to the user stay in video time.
- **Reuse:** a downloaded window is reused while the clip still fits inside it. A nudge past it downloads a new window around the new clip.
- **Fallback:** if a stream isn't MP4 or has no segment index, download the whole stream.
- **Expired links:** an expired stream URL (HTTP 403) refreshes the manifest and retries once.

## 4. Non-functional requirements

- **Platforms:** Android first (minSdk 24, sideloaded APK). iOS later (deployment target 15.6, required by `whisper_ggml`).
- **Responsiveness:** transcription, FFmpeg and file I/O never block the UI isolate. Every long step shows progress and can be cancelled.
- **Storage:**
  - Downloaded media is cached in the app's temporary directory under `sources/<videoId>/` and reused: script audio, WAV pieces, clip windows.
  - Media caches older than 7 days are deleted on app start.
  - Saved scripts (FR-14) live in the app support directory under `transcripts/`.
  - Exports live in the app documents directory under `reels/`.
- **Quality and data caps:**
  - Script audio: the lowest-bitrate MP4 audio stream.
  - Clip: ≤ 720p MP4/H.264 video plus the highest-bitrate MP4 audio, for the clip window only (FR-15).
- **Privacy:** nothing leaves the device except YouTube and model/language-pack downloads.

## 5. Architecture

- Feature-first: `lib/src/features/<feature>/{domain,data,application,presentation}`; layers are created only when they have code.
- State: Riverpod 3 (`Notifier`/`NotifierProvider`, no code generation). The reel being made is one immutable `ReelDraft` owned by `reelDraftProvider`.
- Services sit behind small interfaces exposed as providers: `VideoSource`, `Transcriber`, `CaptionTranslator`, `Renderer`, `RecentReelsRepository`. Fakes implement the same interfaces for tests and for M1.
- Navigation: `go_router`; route paths in `AppRoutes`.
- Rendering (Android): **Media3 Transformer** behind a small Kotlin platform channel.
  - Input: the clip file plus one transparent PNG holding caption and branding, drawn by Flutter at output size.
  - Media3 trims, crops or blurs, scales, overlays the PNG and encodes H.264/AAC on the phone's hardware.
  - iOS will need an AVFoundation equivalent later.
- FFmpeg handles only audio conversion (WAV), splitting, stream-copy muxing and thumbnails. The bundled build can't encode H.264 (§10 Q1).

### Package map

| Need | Package | Notes |
|---|---|---|
| YouTube metadata, stream URLs, caption tracks | yt-dlp via `io.github.junkfood02.youtubedl-android:library` 0.18.1 (Gradle) | Kotlin channel `status_studio/ytdlp`: `quickVideoInfo` (`-J --no-js-runtimes`), `videoInfo` (`-J` with the bundled QuickJS), `update`, `version`. Bundles Python, yt-dlp and QuickJS; updates yt-dlp from GitHub. Replaced `youtube_explode_dart` in M7 (§10 Q4) |
| Speech to text | `whisper_ggml` | `WhisperController.transcribe(model:, audioPath:, lang:, withSegments: true, keepModelLoaded: true)`; returns `null` on failure. Model file at `getPath(model)`, URL `model.modelUri` |
| FFmpeg | `ffmpeg_kit_flutter_new_min` ^2.x | The only FFmpeg; `whisper_ggml` depends on it. Built with `--disable-mediacodec --disable-openssl`, no libx264: decode, filter, AAC/PCM, stream copy only. `FFmpegKit.executeWithArgumentsAsync`, `FFmpegKit.cancel` |
| Final render (Android) | `androidx.media3:media3-transformer`, `media3-effect`, `media3-common` 1.11.1 (Gradle) | `Transformer`, `ClippingConfiguration`, `Crop`, `Presentation`, `GaussianBlurWithFrameOverlaid`, `OverlayEffect` + `BitmapOverlay` |
| Downloads | `dart:io` `HttpClient` | `Range: bytes=a-b` requests against the stream URL: clip windows (FR-15), and whole streams in 10 MB ranges; caption tracks as `json3` |
| Translation | `google_mlkit_translation` | `OnDeviceTranslator`, `OnDeviceTranslatorModelManager` |
| Preview | `video_player` | |
| Gallery / share | `gal` / `share_plus` | `Gal.putVideo`, `SharePlus.instance.share(ShareParams(files: [XFile(path)]))` |
| Key-value storage | `shared_preferences` | Added in M6 for recent reels and settings |

## 6. Domain model and rules

### 6.1 Types (Dart)

```dart
class SourceVideo { String videoId; String title; String channel; Duration duration; }
enum ScriptLanguage { auto, urdu, arabic, punjabi, persian, hindi, bengali, english } // each has whisperCode ('auto','ur',…) and label
class TranscriptLine { int index; String text; Duration start; Duration end; }
class Transcript { String languageCode; List<TranscriptLine> lines; }
sealed class LineSelection { NoSelection, StartSelected(int start), RangeSelected(int start, int end) }
class ClipRange { Duration start; Duration end; }
enum AspectPreset { story9x16, portrait4x5, square1x1, landscape16x9, free }
enum FillMode { crop, blur }  enum CropFocus { left, center, right }
class FreeCropRect { double left, top, width, height; } // fractions of the source frame
class FrameSettings { AspectPreset preset; FillMode fill; CropFocus focus; FreeCropRect freeCrop; }
class OutputSize { int width; int height; }
enum CaptionVariant { original, roman, english }  enum CaptionPosition { top, bottom }  enum CaptionSize { small, medium, large }
class CaptionSettings { CaptionVariant variant; String text; CaptionPosition position; CaptionSize size; }
class ReelDraft { SourceVideo? video; ScriptLanguage language; Transcript? transcript; LineSelection selection; ClipRange? clip; FrameSettings frame; CaptionSettings caption; }
class RecentReel { String id; String title; String videoPath; String thumbnailPath; Duration duration; OutputSize size; DateTime createdAt; } // title: the caption's first line; size: shown on Done
class SavedTranscript { Transcript transcript; String source; DateTime savedAt; } // source: captions | whisper-small | whisper-base
class ClipWindow { Duration start; Duration end; }        // FR-15 window in video time
class ClipSource { File file; Duration offset; ClipWindow window; } // offset = video time of the file's zero
```

All are immutable with `copyWith` and value equality (`==`/`hashCode` written by hand; no codegen).

### 6.2 Time formats
- Clip times: `m:ss.t` (`1:23.0`).
- Line timestamps: `m:ss` (`1:23`).
- Durations: `18.5 s`.
- Hours, for long videos: `h:mm:ss`.

### 6.3 Crop maths (presets)
The target aspect is `aw:ah` and the source is `sw × sh`.
- **Crop to fill:** take the largest `aw:ah` rectangle inside the source. Its horizontal position is left = 0, center = (sw − cw) / 2, right = sw − cw, and it is vertically centred. Scale to the output size.
- **Blur background:**
  - Background: the source scaled to cover the output, `boxblur=20:2`.
  - Foreground: the source scaled to fit the output width, vertically centred.

### 6.3.1 Crop for Media3
Media3's `Crop` takes normalised device coordinates, so convert each pixel crop rectangle (§6.3):
- left = 2·x/sw − 1
- right = 2·(x + w)/sw − 1
- top = 1 − 2·y/sh
- bottom = 1 − 2·(y + h)/sh

Then `Presentation.createForWidthAndHeight(outW, outH, LAYOUT_SCALE_TO_FIT)`.
- **Blur background:** `GaussianBlurWithFrameOverlaid` (σ ≈ 20) on the source frame, then `Presentation` to the output size. Read from Media3 1.11.1's source (M5 Task 3): the effect draws the *whole input frame* sharp, scaled by (`sharpScaleX`, `sharpScaleY`) of the output, over a blurred copy of the input stretched to the output's shape. So it can't follow a covering `Presentation` (the sharp layer would be the cropped centre). The sharp scale fits the frame to the output width, or to its height for a taller source. The background is therefore a stretched, not a covered, blur. If that looks wrong on a phone, switch to the two-sequence `Composition` from the M5 plan. Pending the device check in `docs/device-testing-todo.md`.
- **16:9:** `Presentation` only.

### 6.4 Language inference (automatic mode)
Use the transcript text:
- Arabic script containing any of `ٹ ڈ ڑ ں ے ھ ہ` → Urdu.
- Otherwise Arabic script containing any of `پ چ ژ گ` → Persian.
- Other Arabic script → Arabic.
- Devanagari → Hindi.
- Bengali script → Bengali.
- Gurmukhi → Punjabi.
- Latin → English.
- Anything else → `und` (shown as "Detected language").

### 6.5 Caption font by script
- Urdu letters (as in §6.4) → Noto Nastaliq Urdu.
- Other Arabic script → Noto Naskh Arabic.
- Everything else → Inter. Glyphs Inter lacks (Devanagari, Bengali, Gurmukhi…) fall back to system fonts.

### 6.6 Roman Urdu
A rule-based, letter-by-letter transliteration with a short list of common-word overrides (e.g. `پہ`→`pe`, `ہے`→`hai`, `اور`→`aur`). It is imperfect by design; the text stays editable.

## 7. Logo

"Trim": trim brackets around a five-bar waveform on a rounded tile, in a 100-unit viewBox:
- Tile: rx 24.
- Brackets: `M33 24 H24 V76 H33` and `M67 24 H76 V76 H67`, stroke 6, round caps and joins.
- Bars: x = 38, 44, 50, 56, 62 spanning y 42–58, 35–65, 30–70, 37–63, 43–57, stroke 4.5, round caps.
- Colours: tile `#3DD68C`, ink `#06140D`; dark variant tile `#18201C`, ink `#3DD68C`.

It is drawn by one `LogoPainter`. The same painter serves the app UI, the export overlay and the launcher-icon PNG.

## 8. Error states

| Condition | Where | Message | Actions |
|---|---|---|---|
| Invalid link | Source | That doesn't look like a YouTube link. | Edit |
| Video unavailable, private or age-restricted | Processing | This video can't be downloaded. | Back |
| No network during download | Processing | You're offline. Connect and try again. | Retry, Back |
| YouTube changed and yt-dlp can't read the video, even after updating itself | Source / Processing | Couldn't read this video from YouTube. Try again later. | Retry, Back |
| Model download failed | Processing / Settings | Couldn't download the speech model. | Retry |
| No speech found | Processing | No speech found in this video. | Try another language, Back |
| Translation pack missing and offline | Style | English needs a one-time download. | Retry |
| Render failed | Export | Couldn't make the reel. | Retry, Back |
| Not enough storage | any download/export | Not enough space on your phone. | Back |

Each error is a typed exception from the data layer; screens map exceptions to these messages. No `null` or sentinel returns.

## 9. Decisions log

| Decision | Choice |
|---|---|
| Scope | General-purpose: any video, any language. No content-type picker. |
| Selection | User picks start/end lines from the transcript; no automatic segment detection |
| Distribution | Sideloaded APK; YouTube access isolated in `YouTubeVideoSource` |
| YouTube access | yt-dlp on the phone resolves videos; the app downloads in Dart. Android only: iOS would need another resolver behind `VideoSource` |
| Model | Whisper small default, base optional, downloaded on first use |
| FFmpeg | `ffmpeg_kit_flutter_new_min` only (LGPL) |
| Captions/branding rendering | Flutter → PNG → FFmpeg overlay |
| Name / logo | Status Studio / Trim |
| IDs | `com.hotmail.arehmananis.statusstudio` |
| Signing | Upload keystore committed (private repo) |
| Fonts | Inter (UI), Noto Nastaliq Urdu, Noto Naskh Arabic |
| Data saving | Script audio at lowest bitrate (none with captions); video and clip audio downloaded only for the clip window (FR-15) |
| Reuse | Scripts saved per video/language/source for 90 days; Whisper resumes per 90-second piece (FR-14) |
| Renderer | Media3 Transformer on Android (hardware H.264), because the bundled FFmpeg can't encode H.264 |

## 10. Open questions (resolved by spikes in the milestones)

1. ~~H.264 encoder in the min FFmpeg build~~ **Resolved 2026-10-30.** The bundled `libavutil` build flags include `--disable-mediacodec` and `--disable-openssl`, with no `libx264` or `libopenh264`, so there is no H.264 encoder and no https input. **Decision:** render with Media3 Transformer (Android), and do partial downloads in Dart.
2. **Whisper speed and quality** (M3 Task 1). Measure small and base on a mid-range Android phone with a 5-minute Urdu speech clip and a 5-minute sung clip. Confirm that 90-second chunking doesn't damage lines at chunk boundaries.
3. **Status length limit** (M6). Check WhatsApp's current Status video limit. Until confirmed, show a warning (not a block) when the clip is longer than 60 s.
   - **Checked 2026-11-02 (M6 Task 6):** 60 s has been the general limit since 2024. A 90 s limit was reported in beta in 2025, but there's no official confirmation that it rolled out to everyone. The 60 s warning stays. Confirm on a phone by checking the longest trim the Status composer allows (`docs/device-testing-todo.md`).
4. **YouTube extraction reliability** (M2). If `youtube_explode_dart` breaks, update it. Track failures in the error state rather than crashing.
   - **Broke 2026-11-02 (device testing):** YouTube answered every `youtube_explode_dart` 3.1.0 stream URL with HTTP 403, and the library re-fetched manifests in a loop (65 MB used, no audio). **Decision (M7):** resolve videos with yt-dlp, bundled through `youtubedl-android` 0.18.1 (Python, yt-dlp, QuickJS), and keep downloading in Dart. yt-dlp's URLs download at about 10 MB/s with plain range requests.
   - **Measured on a Redmi Note 11 (Snapdragon 680), M7 Task 1**, for a 9-minute video:
     - Python start alone (`--version`): 2.7 s. First run after install also unpacks Python.
     - Bundled yt-dlp 2025.11.12 with QuickJS: 16.3 s first run, then 15.1 s and 11.6 s.
     - After a self-update (6.5 s) to 2026.10.26 with QuickJS: about 30 s.
     - 2026.10.26 without a JavaScript runtime (`--no-js-runtimes`): 13.4 s first, then 8.4 s, with the same 31 formats. yt-dlp then asks only YouTube clients that need no challenge solving.
     - The arm64 APK went from 57.4 MB to 45.4 MB: legacy packaging stores native libraries compressed, so the installed size grows instead.
   - **Decision:** read a video without JavaScript first, and with QuickJS only when that run has no usable formats. Read each video once and keep the result while its URLs are valid.

## 11. Out of scope for v1

- iOS release.
- Play Store or App Store builds.
- Local-file or share-into-app input.
- Multiple clips per reel, music, stickers, text animation.
- Accounts, cloud sync, analytics.

## 12. Milestones

| Milestone | Plan | Deliverable |
|---|---|---|
| M1 | `plans/2026-10-29-m1-app-shell.md` | All screens wired with fakes; real domain logic (selection, clip, crop maths, link parsing) |
| M2 | `plans/2026-10-29-m2-video-source.md` | Real YouTube metadata, audio/video download, cache, preview |
| M2b | `plans/2026-10-30-m2b-data-saver.md` | Low-bitrate script audio, clip-only download via `sidx` + HTTP ranges |
| M3 | `plans/2026-10-29-m3-transcription.md` | Model manager, Whisper chunked transcription, YouTube captions, language inference, saved scripts and resume |
| M4 | `plans/2026-10-29-m4-fine-tune.md` | Waveform, clip playback, language re-run |
| M5 | `plans/2026-10-29-m5-render.md` | Overlay PNG, Roman Urdu, translation, Media3 render |
| M6 | `plans/2026-10-29-m6-library-settings-polish.md` | Save/share, recent reels, settings, launcher icon, cache cleanup, error states |
| M7 | `plans/2026-11-02-m7-yt-dlp.md` | yt-dlp video source, kept up to date; percent, sizes and speed per Processing step |
