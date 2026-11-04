# Status Studio

**Updated 2026-11-04.** The one project document: product spec, engineering rules, milestones, device checks and known issues. It is the source of truth for behaviour, copy, sizes and error messages. Code cites its section (§) and FR numbers, so keep them stable and add new sections at the end. Design canvas: <https://claude.ai/artifact/HcKksQmAu8ZYBfQdbnr2RN>

## 1. Summary

Status Studio turns any YouTube video, in any language, into a short clip for WhatsApp Status, Reels, TikTok or Shorts. The user pastes a link and the app writes out the video's script. The user taps the line where the clip starts and the line where it ends, then picks a size and caption. The export is an MP4 with the Status Studio name and logo.

- **On the phone:** everything after the download runs on the device: speech to text (Whisper), translation (ML Kit) and rendering (Media3 Transformer). No accounts, no servers, no analytics.
- **One opt-in exception:** a user who pastes their own Groq API key can have scripts written by Groq's hosted Whisper, which is much faster (FR-12a). Only then does script audio leave the phone, and only to Groq. The app ships no key and has no server of its own.
- **Saves data:** it downloads the script's audio at low quality (nothing when YouTube has captions), and only the clip's part of the video, once the user has picked it.
- **Saves work:** scripts are saved, so the same video opens straight to its script next time.

## 2. Screens

| # | Screen | Route | Job |
|---|---|---|---|
| 1 | Home | `/` | Start a reel; recent reels and saved scripts; open Settings |
| 2 | Source | `/source` | Paste a YouTube link; choose language (default automatic) |
| 3 | Processing | `/processing` | Download audio → detect language → transcribe → line up timestamps (skipped for a saved script, FR-14) |
| 4 | Script | `/script` | Full script; tap the start line, then the end line |
| 5 | Fine-tune | `/fine-tune` | Download only the clip (FR-15); preview; nudge start and end by ±0.5 s |
| 6 | Style | `/style` | Size, fill, crop, caption text/variant/position/size; live preview with branding |
| 7 | Export | `/export` | Render with progress; Cancel returns to Style |
| 8 | Done | `/done` | Final preview; Save to gallery; Share; Make another |
| 9 | Settings | `/settings` | Whisper models (tiny to large, pros and cons), download, pause or delete; optional Groq key with step-by-step help (FR-12a); background work |

- **Visual reference:** the design canvas prototype for screens 1–8. Settings follows the same visual language.
- **Progress on Processing:** each download and transcription step has its own bar with the percent beside it (`45 %`). Under the bar it shows amount done of total and speed (`220 of 487 MB · 3.2 MB/s`), with time left on the right (`1:24 left`).

## 3. Functional requirements

**FR-1 Link input.**
- **Accepted links:** `youtube.com/watch?v=ID`, `m.youtube.com/watch?v=ID`, `youtu.be/ID`, `youtube.com/shorts/ID` and `youtube.com/live/ID`. They may come with or without `https://`, extra query parameters (such as `si=`) or surrounding whitespace.
- **Video ID:** 11 characters of `[A-Za-z0-9_-]`.
- **Anything else:** "That doesn't look like a YouTube link."
- **A valid link** shows the title, channel and duration.

**FR-2 Language.** Dropdown: Detect automatically (default), Urdu, Arabic, Punjabi, Persian, Hindi, Bengali, English. Script has the same dropdown; changing it re-runs the script in that language, reusing the downloaded audio.

**FR-3 Script.** The first source that applies:
1. **Saved script** for this video and language (FR-14): open Script directly.
2. **YouTube captions** in the chosen language, manual tracks over auto-generated. Each caption becomes one line, and no audio is downloaded.
   - **Automatic language:** only manual tracks count, in any language. YouTube guesses an auto-generated track's language from the audio, and a wrong guess makes the script junk: an Urdu naat's only track was auto-generated Romanian.
   - **Which auto track:** only yt-dlp's `<lang>-orig` track is what YouTube heard; the other auto tracks are machine translations and are never used.
   - **Cleaning:** music symbols and sound tags (`♪`, `[♪♪♪]`, `[Music]`) are dropped.
3. **Speech to text** on the **lowest-bitrate MP4 audio stream**: by Groq when it's on (FR-12a), otherwise by Whisper on the phone. Each segment becomes one line.
   - **Pieces:** both engines work in **90-second pieces**, so lines appear while the rest is still being written. Each piece's times are offset by its start.
   - **Whisper on the phone** (`whisper_ggml`, `withSegments: true`): the audio is converted to 16 kHz mono WAV (Whisper hears nothing finer, so better audio only wastes data), cut into pieces, and run with the model kept loaded between pieces.
   - **Dropped segments:** silence, music and bracketed tokens (`[BLANK_AUDIO]`, `(music)`, `♪`) never become lines.
   - **Groq** (`whisper-large-v3-turbo`):
     - **Pieces:** stream-copied `.m4a` pieces, without WAV, about 0.5 MB each. Stream copy cuts at audio frame boundaries, so each offset is the piece's real start from FFmpeg's segment list.
     - **Request:** one multipart `POST https://api.groq.com/openai/v1/audio/transcriptions` per piece, in order, with `Authorization: Bearer <key>`. Fields: `file`, `model`, `response_format=verbose_json`, `timestamp_granularities[]=segment`, `temperature=0`, and `language=<whisperCode>` unless automatic.
     - **Lines:** segments with empty text, or `no_speech_prob` above 0.8, are dropped (cut-off to confirm, §10 Q5).
     - **HTTP 429:** wait `retry-after` and resend when it's 60 s or less, showing "Waiting for Groq · 0:42 left"; otherwise the §8 error.
     - **HTTP 5xx or 498:** resend once after 2 s, then the §8 error.
     - **Cancel** aborts the request in flight. Whisper on the phone stops only between pieces.
- **Automatic language** is inferred from the transcript text (§6.4) and shown, e.g. "Urdu (detected)".
- **No speech found** gives the §8 error.

**FR-4 Line selection.**
- The first tap sets the start line.
- A tap on the same or a later line sets the end line.
- A tap on an earlier line, or any tap once both are set, starts over with that line as the start.
- Lines between start and end are highlighted.
- "Next" is enabled only when both are set.

**FR-5 Fine-tune.**
- **Opening:** downloads the clip (FR-15); the preview shows download progress until it's ready.
- **Range:** the clip runs from the start line's start to the end line's end.
- **Nudges:** buttons move start or end by 0.5 s. A nudge is ignored when it would make the clip shorter than **3 s** or move it outside the video. A clip that starts out invalid (from transcript times) still accepts nudges towards a valid range; only nudges that make a rule worse are ignored.
- **Preview:** plays only the clip range and stops at its end; leaving the screen disposes the player.
- **Waveform:** 60 bars over the downloaded window, with the clip highlighted.
- **Long-clip warning:** above 60.0 s, "Longer than 60 s. WhatsApp Status may cut it." It never blocks.

**FR-6 Frame.**

| Preset | Output size |
|---|---|
| 9:16 (default) | 1080 × 1920 |
| 4:5 | 1080 × 1350 |
| 1:1 | 1080 × 1080 |
| 16:9 | 1920 × 1080 (original framing, no crop) |
| Free | the crop rectangle in source pixels, scaled so the long side ≤ 1920, both sides rounded down to even numbers |

- **Fill:** presets other than 16:9 offer Crop to fill (default) or Blur background. Crop to fill offers Keep in view: Left / Center (default) / Right.
- **Free crop:**
  - Drag to move, and drag the corner to resize.
  - Each side is at least 12 % of the source, and the rectangle never leaves the frame.
  - Reset returns to left 30 %, top 4 %, width 40 %, height 92 %.

**FR-7 Caption.**
- **Default text:** the selected lines' text, one per line.
- **Variants:**
  - **Original.**
  - **Roman:** only when the transcript is Urdu (§6.6).
  - **English:** ML Kit on the device; hidden when ML Kit doesn't support the source language (e.g. Punjabi).
- **Editing:** the text is editable, and switching variant replaces edits with that variant's text.
- **Position and size:** Top or Bottom (default). Size S, M (default) or L is a font size of 4.5 %, 5.5 % or 6.8 % of output width.
- **Font:** by script (§6.5), with line height 2.1 for Nastaliq and 1.3 otherwise.
- **Block:** centred, black at 38 % behind the text, padding 2 % of output width, margin 6 % of output height from the edge.
- **Overflow:** if the block would pass 35 % of output height, the font shrinks in 5 % steps down to 60 % of the chosen size, then the text is clipped with an ellipsis.

**FR-8 Branding (always on).**
- **Pill:** the Trim logo and "Status Studio" in Inter SemiBold.
- **Sizes:** logo height 4.5 % of output width, and text at 55 % of the logo height.
- **Look:** black at 45 %, inset 4 % of output width from the left edge and from the top or bottom edge.
- **Placement:** at the top when the caption is at the bottom, and at the bottom otherwise.

**FR-9 Export.**
- **Output:** MP4 with H.264 video (`video/avc`) and AAC audio (`audio/mp4a-latm`), at the source frame rate, rendered by Media3 Transformer (§5).
- **Progress:** Media3's own progress.
- **Cancel:** stops the render, deletes the partial file and returns to Style.
- **Failure:** a native render error shows "Couldn't make the reel." It never hangs.

**FR-10 Save and share.** Save to gallery (`gal`). Android 10+ needs no permission. Android 7–9 asks once; a refusal explains and offers "Open settings". Share opens the system share sheet with the MP4 (`share_plus`).

**FR-11 Recent.**
- **Reels:** newest first, at most 50; the oldest is dropped and its MP4 and thumbnail deleted.
  - A row shows a thumbnail, the first caption line, duration and date.
  - Tap opens Done. Long-press offers Delete.
  - A reel whose file was deleted outside the app is skipped.
- **Saved scripts:** every saved script (FR-14) has a row as soon as the video is processed, before any lines are picked.
  - Reels and scripts share one list, newest first. Empty, it reads "Your reels and scripts will appear here."
  - A script row shows a script icon, the title and `Script · <language> · <video length> · <d MMM>`, where an automatic script names its detected language ("Urdu (detected)").
  - Tap opens Script without Processing or downloads.
  - Long-press offers Delete, which removes that script and any unfinished progress for it.
  - There is one row per video and requested language. Scripts saved before video details were kept appear once their link is opened again.

**FR-12 Settings: speech models.**
- **Models:** every multilingual Whisper model (tiny, base, small, medium, large-v3), each as its 5-bit quantised file (§10 Q2). Small is the default and is marked "recommended". English-only models aren't offered: they can't write other languages.
- **Each row:** download size or size on disk, and Download / Delete. An info button opens the model's pros and cons: speed relative to small, accuracy and the memory it needs. Switching model keeps other downloaded files until they're deleted.
- **Downloads:**
  - A running download shows progress, with Pause and Cancel.
  - Pause keeps the bytes; the row shows "Paused · 45 %" with Resume and Cancel, also after a restart.
  - Resume continues with an HTTP range request, and starts over if the server sends the whole file.
  - Cancel deletes the bytes.
  - A failed download keeps its bytes, so Retry continues it. A full phone deletes them.
  - An interrupted download never leaves a file `whisper_ggml` would load.
- **With a script waiting:**
  - Transcription that needs a paused model resumes its download.
  - A script waiting on a download that gets paused or cancelled stops with the §8 message.
  - Without the model, the model downloads first, as a step on Processing.

**FR-12a Settings: cloud transcription (Groq, optional).** Off by default; it is a section below the models.
- **Key field:** "Groq API key", masked, with Paste, Show and Remove.
  - Saving checks the key with `GET https://api.groq.com/openai/v1/models`, which is free and sends no audio.
  - The field then reads "Key works" or "Groq didn't accept this key."
- **Help (ⓘ):** beside the label, it opens "How to get a free Groq key", written for non-technical users:
  1. Tap **Copy link**, then open your browser and paste it: `console.groq.com/keys`.
  2. Sign in with Google or your email. The free plan needs no card.
  3. Tap **Create API Key**. Give it any name, like "Status Studio", and tap **Submit**.
  4. Tap **Copy** next to the new key. It starts with `gsk_`. Groq shows it only once, so copy it now.
  5. Come back here, tap **Paste**, then **Save**.

  Below the steps: "Free plan: about 2 hours of audio every hour, and 8 hours a day." and "Keep the key private, like a password. You can delete it any time on the same Groq page." The sheet has Copy link and Done buttons. Copy link puts the link on the clipboard and shows "Link copied"; the app doesn't open a browser itself.
- **Switch:** "Write scripts with Groq", enabled only after a key passes the check. Subtext: "Much faster than the phone. Your video's audio is sent to Groq, which uses about as much data again as downloading it. Groq's terms apply."
- **Key storage:** `flutter_secure_storage` (Android Keystore). The key is never logged, and never written into saved files, notifications or error text. It goes only to `api.groq.com`.
- **Engine per run:** Groq when the switch is on and a key is saved; otherwise Whisper on the phone. Groq needs no Whisper model, so "Downloading the speech model" is skipped.
- **Offline at the start:** with the audio cached and a model downloaded, the script is written on the phone (FR-13), and Processing shows "Offline · writing on the phone".
- **Use on-device** (offered by the §8 Groq errors): keeps Groq's lines so far and continues on the phone from the next piece, downloading the model if needed. The script is saved under the on-device source, because the phone finished it.

**FR-13 Offline.** With the model downloaded and the source cached, transcription, translation (once its ML Kit pack is downloaded) and export work without a network, even with Groq on.

**FR-14 Saved scripts.**
- **Key:** video ID, requested language (`auto` or a code) and source: `captions`, `whisper-<model>` or `groq-whisper-large-v3-turbo`. The entry holds the transcript (with the inferred language), the source and the save date.
- **Files:** `transcripts/<videoId>/<requested>-<source>.json` in the app support directory. The video's folder also keeps `video.json` (title, channel, length) for Recent.
- **Same link again:** skips Processing and downloads. Script shows "Using the saved script from <d MMM> · Write it again".
- **Write it again:** runs speech to text with the current choice (Groq, or the current Whisper model) and replaces the saved script.
- **Resume:** progress is saved after each 90-second piece in `<requested>-<source>.partial.json` and deleted when the run completes. An interrupted run resumes from the next piece.
- **Retention:** 90 days after last use, at most 200 videos, least recently used dropped first.

**FR-15 Clip-only download.**
- **When:** nothing of the video is downloaded before Fine-tune.
- **Window:** from clip start − 5 s to max(clip end + 5 s, clip start + 30 s), clamped to the video.
- **What:** ≤ 720p MP4 video plus the highest-bitrate MP4 audio. With no MP4 at or below 720p, take the lowest above 720p, else WebM.
- **How:**
  - Read each stream's MP4 segment index (`sidx`) and fetch just those segments with HTTP range requests.
  - The index fetch starts at 64 KiB and doubles up to 2 MiB; beyond that the stream counts as having no index.
  - A `200` reply to a range request is never written as the clip.
- **Clip file:** video and audio are muxed by stream copy. Its time zero is `offset` in the video; times shown to the user stay in video time.
- **Reuse:** a window is reused while the clip still fits inside it. A nudge past it downloads a new window.
- **Fallback:** a stream that isn't MP4, or has no index, is downloaded whole.
- **Expired links:** an HTTP 403 refreshes the stream URLs and retries once, then gives a typed error.

**FR-16 Background work.** Writing a script and exporting keep running when the user leaves the app or locks the phone.
- **How:** while either runs, a foreground service (type `dataSync`, from `flutter_foreground_task`) holds a partial wake lock and a Wi-Fi lock, and shows an ongoing notification. Doze and battery saving leave such a service running, network included. The work stays in the app; the service only keeps the process alive.
- **Ongoing notification:**
  - It appears from the moment work starts, so the user can leave at once.
  - It starts as "Getting the script" or "Rendering your reel" at 0 %, then shows the running step as the title and `45 % · <video title>` as the text.
  - Script steps: "Downloading the speech model", "Downloading audio", "Detecting the language", "Writing the script", "Waiting for Groq", "Lining up timestamps". Export step: "Rendering your reel".
  - With both running, it shows the one that started last. The service stops when the last job ends.
- **Result notification:** posted only when the app isn't on screen; tapping it opens the app where the work left off. Cancel posts nothing.
  - Script done: "Script ready" · video title. Failed: "Script stopped" · the §8 message.
  - Export done: "Reel ready" · "Tap to save or share it." Failed: "Export stopped" · the §8 message.
- **Asking once:** the first time work starts, the app asks for notifications (Android 13+), then for exemption from battery optimisation. It never asks again on its own.
- **Settings, "Background work":**
  - Two rows: notifications on, and battery optimisation off. Each shows "Allow" when it isn't so; a refused notification permission opens App info instead.
  - A hint: "On Xiaomi and some other phones, also set Battery saver to No restrictions in App info." with "Open App info".
- **Lifetime:** the service survives Home and lock, and stops when the task is swiped away (manifest `android:stopWithTask`), because the work's Flutter engine ends with the task. The plugin's own `stopWithTask` option isn't used: it stops whenever the app leaves the screen.
- **Limits:** Android 15+ gives `dataSync` 6 hours a day. After that the service stops, and work continues only while the app is open.

## 4. Non-functional requirements

- **Platforms:** Android first (minSdk 24, sideloaded APK). iOS later (deployment target 15.6, needed by `whisper_ggml`).
- **Responsiveness:** transcription, FFmpeg, waveform peaks and file I/O never block the UI isolate. Every long step shows progress and can be cancelled.
- **Storage:**
  - Media cache: `sources/<videoId>/` in the temp directory, holding script audio, WAV pieces and clip windows. It's reused, and deleted on app start after 7 days.
  - Saved scripts: `transcripts/` in app support (FR-14).
  - Exports: `reels/` in app documents.
  - Downloads go to `.part` files and are renamed when complete. Whole streams download in 10 MB ranges.
- **Data caps:** script audio is the lowest-bitrate MP4 audio. The clip is ≤ 720p H.264 plus the highest-bitrate MP4 audio, for the clip window only.
- **Privacy:** nothing leaves the device except YouTube, model and language-pack downloads, and, only while Groq is on (FR-12a), script audio pieces sent to Groq with the user's key.

## 5. Architecture

- **Folders:** feature-first, `lib/src/features/<feature>/{domain,data,application,presentation}`, with a layer only when it has code.
- **State:** Riverpod 3 (`Notifier`/`NotifierProvider`). The reel in progress is one immutable `ReelDraft` in `reelDraftProvider`. Changing the transcript clears the selection and clip.
- **Services:** small interfaces exposed as providers, so fakes can replace them in tests: `VideoSource`, `Transcriber`, `CaptionTranslator`, `Renderer`, `RecentReelsRepository`, `BackgroundWorkPlatform`.
- **Speech to text:** `WhisperTranscriber` (on the phone) and `GroqTranscriber` (FR-12a) emit the same per-piece progress and lines. The pipeline picks one per run.
- **Navigation:** `go_router`, with route paths in `AppRoutes`.
- **Rendering (Android):** Media3 Transformer behind the Kotlin channels `status_studio/render` (`start`, `cancel`) and `status_studio/render/events`.
  - Input: the clip file plus one transparent PNG, exactly the output size, holding caption and branding drawn by Flutter. It is applied last.
  - Media3 trims, crops or blurs, scales, overlays and encodes on the phone's hardware.
  - Preview and export share `cropRectFor` and `layoutOverlay`.
  - iOS will need AVFoundation later.
- **FFmpeg:** only WAV conversion, splitting, stream-copy muxing and thumbnails. The bundled build can't encode H.264 or read https (§10 Q1).

### Package map

| Need | Package | Notes |
|---|---|---|
| YouTube metadata, stream URLs, captions | yt-dlp via `youtubedl-android` 0.18.1 (Gradle) | Channel `status_studio/ytdlp`: `quickVideoInfo` (`-J --no-js-runtimes`), `videoInfo` (`-J` with QuickJS), `update`, `version`. Bundles Python, yt-dlp and QuickJS (§10 Q4) |
| Speech to text (phone) | `whisper_ggml` | `transcribe(model:, audioPath:, lang:, withSegments: true, keepModelLoaded: true)` returns `null` on failure |
| Speech to text (cloud, optional) | `dart:io` `HttpClient` | Hand-built multipart to `api.groq.com`; `GET /openai/v1/models` checks a key |
| Secret storage | `flutter_secure_storage` | The Groq key only |
| FFmpeg | `ffmpeg_kit_flutter_new_min` ^2.x | The only FFmpeg (LGPL, from `whisper_ggml`); no mediacodec, no TLS, no libx264 |
| Final render (Android) | Media3 `transformer`, `effect`, `common` 1.11.1 | `Transformer`, `ClippingConfiguration`, `Crop`, `Presentation`, `GaussianBlurWithFrameOverlaid`, `OverlayEffect` + `BitmapOverlay` |
| Downloads | `dart:io` `HttpClient` | Range requests for clip windows and whole streams; captions as `json3` |
| Translation | `google_mlkit_translation` | `OnDeviceTranslator`, `OnDeviceTranslatorModelManager` |
| Preview / gallery / share | `video_player` / `gal` / `share_plus` | |
| Key-value storage | `shared_preferences` | `settings.whisperModel`, `recentReels` (JSON) |
| Background work | `flutter_foreground_task`, `flutter_local_notifications` | No TaskHandler: the work stays in the app's isolate. Notifications need core library desugaring |

### Engineering rules

- **No code generation:** `copyWith`, `==` and `hashCode` are written by hand.
- **Copy:** literal from this document and the canvas. The app is general-purpose: never name a content type (naat, bayan…) in UI or code.
- **Import boundaries:**
  - Only `YouTubeVideoSource` reaches yt-dlp.
  - Only `lib/src/core/ffmpeg/` imports FFmpeg Kit.
  - Only `whisper_transcriber.dart` and `model_manager.dart` import `whisper_ggml`.
  - Only the Kotlin `render/` package imports Media3.
  - The background plugins are reached only through `BackgroundWorkPlatform`.
- **Errors are typed:** `VideoUnavailableException`, `OfflineException`, `InsufficientStorageException`, `TranscriptionFailedException`, `NoSpeechFoundException`, and so on. Screens map them to §8. A failing background-platform call is reported with `FlutterError.reportError` and never stops the work.
- **Whisper:** release the parked model (`releaseModel()`) when a run finishes, fails or is cancelled.
- **yt-dlp:**
  - It updates itself at most weekly (about 3 MB), and once more after a failed read.
  - A failed read ends in a §8 message after one update and retry.
  - HLS formats are skipped. Live streams and videos without a length are unavailable.
- **New dependencies:** maintained and widely downloaded on pub.dev. Add them with `fvm flutter pub add`.
- **Tests never touch the network or platform:**
  - Fake `YtDlp`, Whisper, Groq and FFmpeg.
  - Downloads run against a loopback `HttpServer`.
  - Override `backgroundWorkPlatformProvider` with `FakeBackgroundWorkPlatform`.

## 6. Domain model and rules

### 6.1 Types (Dart)

```dart
class SourceVideo { String videoId; String title; String channel; Duration duration; }
enum ScriptLanguage { auto, urdu, arabic, punjabi, persian, hindi, bengali, english } // whisperCode ('auto','ur',…) and label
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
class RecentReel { String id; String title; String videoPath; String thumbnailPath; Duration duration; OutputSize size; DateTime createdAt; } // title: first caption line
class SavedTranscript { Transcript transcript; String source; DateTime savedAt; } // captions | whisper-<model> | groq-whisper-large-v3-turbo
class SavedScript { SourceVideo video; ScriptLanguage language; SavedTranscript saved; } // a Recent row
enum SpeechEngine { onDevice, groq }
class CloudTranscriptionSettings { bool enabled; bool keyChecked; } // the key itself lives only in secure storage
class ClipWindow { Duration start; Duration end; }                  // FR-15, video time
class ClipSource { File file; Duration offset; ClipWindow window; } // offset = video time of the file's zero
```

All are immutable, with `copyWith` and value equality.

### 6.2 Time formats

| What | Format | Example |
|---|---|---|
| Clip times | `m:ss.t` | `1:23.0` |
| Line timestamps | `m:ss` | `1:23` |
| Durations | seconds | `18.5 s` |
| Long videos | `h:mm:ss` | `1:02:15` |

### 6.3 Crop maths

The target aspect is `aw:ah` and the source is `sw × sh`. Crop sizes are even integers rounded down, and offsets are whole pixels rounded down. Free crop is computed in the source's own pixels, whatever its size or orientation.
- **Crop to fill:** take the largest `aw:ah` rectangle in the source, vertically centred. Its left edge is 0 (left), (sw − cw)/2 (center) or sw − cw (right). Then scale to the output size.
- **Blur background:** the source scaled to cover the output with `boxblur=20:2`, under the source scaled to the output width and vertically centred.

### 6.3.1 Crop for Media3

`Crop` takes normalised device coordinates: left = 2x/sw − 1, right = 2(x+w)/sw − 1, top = 1 − 2y/sh, bottom = 1 − 2(y+h)/sh. It is followed by `Presentation.createForWidthAndHeight(outW, outH, LAYOUT_SCALE_TO_FIT)`.
- **Blur:**
  - `GaussianBlurWithFrameOverlaid` (σ ≈ 20), then `Presentation`.
  - The effect draws the whole input frame sharp, scaled to fit the output width (or its height for a taller source), over a blurred copy stretched to the output's shape. That blur is stretched, not covering.
  - It can't follow a covering `Presentation`.
  - If it looks wrong on a phone, switch to a two-sequence `Composition` (device check pending, §14).
- **16:9:** `Presentation` only.

### 6.4 Language inference (automatic)

From the transcript text, first match wins:

| Text contains | Language |
|---|---|
| Arabic script with any of `ٹ ڈ ڑ ں ے ھ ہ` | Urdu |
| Arabic script with any of `پ چ ژ گ` | Persian |
| Other Arabic script | Arabic |
| Devanagari | Hindi |
| Bengali script | Bengali |
| Gurmukhi | Punjabi |
| Latin | English |
| Anything else | `und`, shown as "Detected language" |

### 6.5 Caption font by script

| Script | Font |
|---|---|
| Urdu letters (as in §6.4) | Noto Nastaliq Urdu |
| Other Arabic script | Noto Naskh Arabic |
| Everything else | Inter; glyphs it lacks fall back to system fonts |

Urdu, Arabic and Persian text is right to left.

### 6.6 Roman Urdu

A rule-based, letter-by-letter transliteration, with a short list of common-word overrides (`پہ`→`pe`, `ہے`→`hai`, `اور`→`aur`). It is imperfect by design, and the text stays editable.

## 7. Logo

"Trim": trim brackets around a five-bar waveform on a rounded tile, in a 100-unit viewBox. One `LogoPainter` serves the UI, the export overlay and the launcher icon.

| Part | Spec |
|---|---|
| Tile | rx 24 |
| Brackets | `M33 24 H24 V76 H33` and `M67 24 H76 V76 H67`, stroke 6, round caps and joins |
| Bars | x = 38, 44, 50, 56, 62 spanning y 42–58, 35–65, 30–70, 37–63, 43–57, stroke 4.5, round caps |
| Colours | tile `#3DD68C`, ink `#06140D`; dark variant tile `#18201C`, ink `#3DD68C` |

## 8. Error states

| Condition | Where | Message | Actions |
|---|---|---|---|
| Invalid link | Source | That doesn't look like a YouTube link. | Edit |
| Video unavailable, private, age-restricted or live | Processing | This video can't be downloaded. | Back |
| No network during download | Processing | You're offline. Connect and try again. | Retry, Back |
| yt-dlp can't read the video, even after updating | Source / Processing | Couldn't read this video from YouTube. Try again later. | Retry, Back |
| Model download failed | Processing / Settings | Couldn't download the speech model. | Retry |
| Model download paused or cancelled while a script waits | Processing | The speech model download was stopped. | Retry, Back |
| Groq rejected the key (401/403) | Processing | Groq didn't accept your API key. | Settings, Use on-device, Back |
| Groq limit (429, wait over 60 s) | Processing | Groq's free limit is used up for now. Try again in <n> min. | Use on-device, Back |
| Groq failed (other error, or 5xx/498 twice) | Processing | Groq couldn't write this script. | Retry, Use on-device, Back |
| Network lost while Groq writes | Processing | You're offline. Connect and try again. | Retry, Use on-device, Back |
| Key check failed | Settings | Groq didn't accept this key. | Edit |
| No speech found | Processing | No speech found in this video. | Try another language, Back |
| Translation pack missing and offline | Style | English needs a one-time download. | Retry |
| Gallery access refused | Done | Allow Photos access in Settings to save reels. | Open settings |
| Render failed | Export | Couldn't make the reel. | Retry, Back |
| Not enough storage | any download or export | Not enough space on your phone. | Back |

Each error is a typed exception from the data layer. Screens map them to these messages, and nothing returns `null` or a sentinel.

## 9. Decisions

| Decision | Choice and why |
|---|---|
| Scope | General-purpose: any video, any language. No content-type picker, no automatic segment finding; the user picks lines |
| Distribution | Sideloaded APK, since downloading from YouTube keeps it off the stores. YouTube access sits behind `VideoSource`, so a store build could swap in local files |
| YouTube access | yt-dlp on the phone resolves videos and Dart downloads. YouTube refused `youtube_explode_dart`'s URLs (§10 Q4). Android only |
| Speech model | Whisper small by default; tiny to large-v3 optional; 5-bit quantised files downloaded on first use (§10 Q2) |
| Cloud transcription | Optional Groq `whisper-large-v3-turbo` with the user's own key, off by default (FR-12a), because small runs at about 1.5× real time on a Pixel 6a. A key shipped in the APK could be extracted, and the app has no server. Groq is fast, multilingual and cheap ($0.04 per audio hour, with a free plan). Pieces go as `.m4a`, not WAV, to save data. Groq's `url` input isn't used because YouTube stream URLs are tied to the phone's IP |
| FFmpeg | `ffmpeg_kit_flutter_new_min` only (LGPL). The full GPL build would duplicate native libraries and make the app GPL. Upgrade it together with `whisper_ggml` |
| Renderer | Media3 Transformer (hardware H.264), because the bundled FFmpeg can't encode H.264 |
| Captions and branding | Drawn by Flutter to one PNG and overlaid by Media3. Other text engines break Nastaliq letter joining |
| Data saving | Script audio at the lowest bitrate (none with captions); video and clip audio only for the clip window |
| Reuse | Scripts saved per video, language and source for 90 days; resume per 90-second piece |
| Background work | One foreground service kept by Dart. The work already runs in the app process, so keeping the process alive is enough. Packages rather than hand-written Kotlin, so the notification shows the percent as text, not a bar |
| Name, logo, IDs | Status Studio; Trim; `com.hotmail.arehmananis.statusstudio` |
| Fonts | Inter (UI), Noto Nastaliq Urdu, Noto Naskh Arabic (OFL) |
| Signing | Upload keystore and `key.properties` committed, because the repo is private |

## 10. Spikes and measurements

1. **FFmpeg build (resolved 2026-10-30).** `--disable-mediacodec --disable-openssl`, no libx264 or openh264: no H.264 encoder and no https input. So the app renders with Media3 and downloads in Dart.
2. **Whisper speed (Pixel 6a, profile build, 2026-11-02).** One 90 s piece of a sung Urdu clip (`s6kE_uP3xH4`), whisper_ggml 2.8.1 at 6 threads:

   | Model | File | Time | Speed | Text |
   |---|---|---|---|---|
   | small f16 | 488 MB | 123.7 s | 0.73× real time | Best |
   | small q5_1 | 190 MB | 60.7 s | 1.48× | One phrase misheard |
   | base f16 | 148 MB | 29.1 s | 3.09× | Loops |
   | base q5_1 | 60 MB | 22.8 s | 3.94× | Loops, more errors |

   **Decision:** quantised files for every model (q5_1 for tiny to small, q5_0 for medium and large-v3); small stays the default. **Still to measure:** a 5-minute speech clip, the Redmi Note 11, and lines at piece boundaries.

   **Why it's slow:** `whisper_ggml` builds whisper.cpp for baseline ARMv8 (no dot-product, so it doesn't crash on old phones) and CPU only. Speed-ups for later: runtime CPU-variant dispatch, the built-in Silero VAD (`vadModelPath`), and no temperature fallback.
3. **WhatsApp Status limit (2026-11-02).** 60 s is the general limit, and 90 s has been seen only in beta. The 60 s warning stays; confirm on a phone (§14).
4. **YouTube reading.** YouTube refused every `youtube_explode_dart` 3.1.0 stream URL (HTTP 403), so the app moved to yt-dlp, whose URLs download at about 10 MB/s. Redmi Note 11, 9-minute video:
   - Python start: 2.7 s.
   - yt-dlp with QuickJS: 12–16 s, or about 30 s after updating to 2026.10.26.
   - Without JavaScript: 8–13 s, with the same 31 formats.
   - The arm64 APK went from 57.4 to 45.4 MB, but the installed size grows.

   **Decision:** read without JavaScript first and with QuickJS only when that finds no usable formats. Each video is read once and kept while its URLs are valid.
5. **Groq (M9 Task 1, to do).** Send the Q2 piece to Groq as a stream-copied `.m4a`, with a free key:
   - Time it on Wi-Fi and on mobile data, and compare the text with small q5_1.
   - Check timestamps after the segment-list offset.
   - Pick the `no_speech_prob` cut-off on a music-only piece.
   - Try automatic language.
   - Confirm the free-plan limits. Groq's docs on 2026-11-04 list 20 requests a minute, 7,200 audio seconds an hour and 28,800 a day.
   - Confirm the button names in the FR-12a help sheet.

## 11. Out of scope for v1

- iOS release; Play Store or App Store builds.
- Local-file or share-into-app input.
- Multiple clips per reel, music, stickers, text animation.
- Accounts, cloud sync, analytics.
- Cloud transcription other than Groq, or a key shipped with the app.

## 12. Milestones

**Workflow:**
- One branch per milestone.
- Each task is a checklist under its milestone here, test first, ticked as it's done, with a commit per task.
- Merge when `tool/check.sh` (format, analyze, all tests) passes.
- If code and this document disagree, this document wins; fix it in the same commit.
- Spike results go into §10 before dependent tasks start.
- Device checks go into §14.

| Milestone | Delivered | Status |
|---|---|---|
| M1 App shell | Every screen with fakes; selection, clip, crop maths, link parsing | Done, in `dev` |
| M2 Video source | Metadata, downloads, cache, preview | Done, in `dev` |
| M2b Data saver | Low-bitrate script audio, clip-only download (FR-15) | Done, in `dev` |
| M3 Transcription | Model manager, chunked Whisper, captions, language inference, saved scripts, resume | Done, in `dev` |
| M4 Fine-tune | Waveform, long-clip warning, language re-run | Done, in `dev` |
| M5 Render | Overlay PNG, Roman Urdu, translation, Media3 export | Done, in `dev` |
| M6 Library and settings | Save/share, Recent, Settings, launcher icon, cache cleanup, §8 errors | Done, in `dev` |
| M7 yt-dlp | yt-dlp source, self-updating; percent, sizes and speed per step | Done, in `dev`; device check pending |
| M8 Background work | Foreground service, result notifications, battery access (FR-16) | Done, in `dev`; device check pending |
| Speech models | Quantised files for all models, with pros and cons | Done, in `dev` |
| Saved scripts in Recent | Script rows in Recent (FR-11) | Done, branch `saved-scripts-in-recent` |
| Model download controls | Pause, resume, cancel (FR-12) | Done, branch `model-download-controls` |
| M9 Groq | Optional cloud transcription (FR-12a, §8) | Spec done; tasks to write, branch `m9-groq-transcription` |

### M9 tasks (branch `m9-groq-transcription`)

Each task: test first, tick it, commit.

- [ ] **1. Spike (needs the user's Groq key, on a phone).** Results go into §10 Q5 before tasks 4 and 8 settle their constants.
- [x] **2. `GroqClient` (data).** Typed `GroqException`s (rejected key, rate limit with wait, server, offline); `checkKey` via `GET /models`; `transcribe` of one `.m4a` piece via `POST /audio/transcriptions` (`verbose_json`, segments). 429 under 60 s waits and resends; 5xx/498 retried once. The key is never in a log or error text. Faked HTTP in tests.
- [ ] **3. `GroqKeyStore`.** Key in `flutter_secure_storage`, plus the switch in settings; the switch can only be on while a key is saved.
- [ ] **4. `GroqTranscriber`.** Emits the same `ChunkEvent`s as `WhisperTranscriber`; offsets segments by piece start; drops segments over the `no_speech_prob` cut-off.
- [ ] **5. Stream-copied `.m4a` pieces.** `AudioPreparer.splitAudioCopy` (FFmpeg `-c copy`, 90 s pieces).
- [ ] **6. Pipeline engine choice.** Groq when on and a key is saved, else Whisper; skip the model step; save under `groq-whisper-large-v3-turbo`; partial progress per piece.
- [ ] **7. Errors and Use on-device.** §8 messages and actions on Processing; Use on-device keeps Groq's lines and continues from the next piece on the phone.
- [ ] **8. Settings section.** Key field (Paste, Show, Remove, check result), ⓘ help sheet with Copy link, switch with subtext.
- [ ] **9. Docs.** §13 tests list, §14 device checks, milestone status.

## 13. Behaviour that must stay covered by tests

- **Links:** a link with whitespace, `si=` parameters or the `m.` host parses.
- **Selection and nudges:**
  - A tap before the start restarts the selection; it never makes a reversed range.
  - Nudges past either end of the video are ignored. A nudge that improves an invalid clip is applied.
  - A free-crop drag stays inside the frame.
  - A new transcript clears the selection and clip.
- **Downloads:**
  - An interrupted download is never reused as complete; a complete one is reused.
  - Pasting a link twice doesn't download again.
- **Captions:** translated auto-captions never become a script, and automatic language skips auto-generated tracks.
- **Transcription:**
  - Non-speech tokens never become lines.
  - Lines keep absolute times across piece boundaries.
  - Cancel releases the model.
  - A killed run resumes from the next piece.
  - A saved script opens without downloading.
- **Waveform:**
  - It maps samples to video time when the window starts after 0.
  - Very short audio still gives the requested number of bars.
  - Silence gives flat bars, not NaN.
  - The warning appears at 60.5 s and not at 60.0 s.
- **Render:**
  - Free crop is right for 720p and vertical sources.
  - Trims respect the clip file's offset.
  - A long caption shrinks, then ellipsizes.
  - Cancel deletes the partial MP4.
  - A native error surfaces as "Couldn't make the reel."
- **Library:**
  - The 51st reel drops the oldest and its files.
  - Reels with missing files are skipped, and corrupt preferences give an empty list.
  - Refused gallery access explains and offers settings.
- **Background:**
  - Cancel posts no result, and results post only when the app is hidden.
  - The service outlives the first of two jobs.
  - Platform calls stay in order.
- **Groq (M9):**
  - The key never appears in logs, files or errors.
  - A 429 under 60 s waits and resends.
  - Use on-device keeps Groq's lines.

## 14. Device checks

Run on a **release** build; debug builds compile whisper.cpp unoptimised. Phones: Pixel 6a (Tensor, 6 GB, Android 17); a slower phone such as the Redmi Note 11 is still needed.

**Passed (Pixel 6a, M4 build, 2026-10-30):**
- Real metadata.
- The captions path.
- Clip-only download: 5.4 MB for a 35 s window.
- Clip-only preview.
- Waveform matches desktop FFmpeg.
- Lines appear progressively.
- Urdu in right-to-left Nastaliq.

**To check:**
- **Video source:**
  - [ ] Lip sync in the Fine-tune preview.
  - [ ] A nudge past the window downloads a new one.
  - [ ] A stream without range support falls back to the whole video.
  - [ ] A cached clip is reused after a restart.
  - [ ] Without captions, the title shows in about 10 s and "Downloading audio" shows percent, MB and speed.
  - [ ] Manual captions become the script.
  - [ ] Wi-Fi ↔ mobile data on Fine-tune still downloads (fresh URLs after a 403).
  - [ ] The yt-dlp version and Update in Settings.
  - [ ] The first-run weekly update.
  - [ ] A private video and airplane mode give the right messages.
  - [ ] The first read is about 13 s, later reads about 8 s.
  - [ ] Each step's bar shows percent, done of total, speed, and a time left that counts down and then disappears.
- **Script:**
  - [ ] Whisper on a 5-minute speech clip and on singing; quality and speed (§10 Q2).
  - [ ] Lines at piece boundaries.
  - [ ] Every model's ⓘ sheet reads well; medium and large write a script (large may close the app on 6 GB).
  - [ ] A killed run resumes.
  - [ ] The saved-script banner and "Write it again".
  - [ ] Airplane mode with the model and audio cached still writes the script.
  - [ ] Back on Processing stops all CPU work.
- **Fine-tune:**
  - [ ] The waveform lines up with the sound.
  - [ ] The warning appears above 60 s.
  - [ ] A language change reuses the audio.
- **Render:**
  - [ ] A 10 s clip with each fill (9:16 crop and blur, 4:5, 16:9, free) is H.264, matches the layout, with a sharp full-frame overlay and audio in sync.
  - [ ] The stretched blur looks acceptable (§6.3.1).
  - [ ] Each preset plays in the gallery, shares to WhatsApp Status, matches the preview and shows Nastaliq.
- **Library:**
  - [ ] The longest trim WhatsApp Status allows (§10 Q3).
  - [ ] Save on Android 10+ with no prompt; on Android 7–9, one prompt, and a refusal leads to Open settings.
  - [ ] The adaptive launcher icon under every mask.
  - [ ] Each §8 condition shows its message and actions.
  - [ ] The full smoke test, from link to share.
- **Background:**
  - [ ] Notification and battery prompts each come once.
  - [ ] Locking within 2 s of starting still finishes the run.
  - [ ] The notification survives Home, lock and dialogs, and goes when the app is swiped away.
  - [ ] The step and percent update.
  - [ ] A locked run of 5+ minutes finishes and "Script ready" opens Script.
  - [ ] "Reel ready" opens Done.
  - [ ] Airplane mode while hidden gives "Script stopped".
  - [ ] No result notification while the app is on screen.
  - [ ] Export over a running script: the notification switches and the service stops last.
  - [ ] Redmi with the default battery saver; note whether "No restrictions" was needed.
  - [ ] The Background work rows update after "Allow".
  - [ ] Small plus the service on a 4 GB phone without running out of memory.
  - [ ] The notification icon isn't a white square.
- **Saved scripts in Recent:**
  - [ ] A processed video's row is above older reels.
  - [ ] Tapping it opens Script with no download.
  - [ ] Deleting it means the next paste writes the script again.
- **Model downloads:**
  - [ ] Pause shows "Paused · 30 %" at once.
  - [ ] Resume continues from 30 % and the model works.
  - [ ] Paused survives a restart.
  - [ ] Cancel leaves no `.part` file.
  - [ ] Airplane mode, then Retry continues.
  - [ ] Pausing under a waiting script shows the message, and Retry resumes.
- **Groq (M9):**
  - [ ] The key check, help sheet and Copy link.
  - [ ] A 10-minute video's script time.
  - [ ] Data used.
  - [ ] A revoked key, the rate limit and Use on-device.

## 15. Known issues (found on the phone, not fixed)

- `whisper_ggml` converts each piece to WAV again (`chunk_000.wav.wav`), although the pieces already are WAVs.
- Processing says "Downloading audio" even when the audio is cached.
- The language list shows both "English (detected)" and "English".
