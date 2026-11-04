# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

Status Studio: a general-purpose Flutter app that turns any YouTube video, in any language, into a short status clip. Flow: paste link → on-device transcript (language auto-detected or chosen) → user taps start and end lines → fine-tune ±0.5 s → size (9:16, 4:5, 1:1, 16:9 or free crop) → caption → export with app name and logo → save or share.

Design canvas (prototype, screens, build plan, logo): https://claude.ai/artifact/HcKksQmAu8ZYBfQdbnr2RN

## Spec and plans

- Spec: `docs/superpowers/specs/2026-10-29-status-studio-design.md`. It is the source of truth for behaviour, copy, sizes and error messages.
- Plans: `docs/superpowers/plans/*-m<N>-*.md`, one per milestone, in this order: **M1 → M2 → M2b → M3 → M4 → M5 → M6**. M2b (`2026-10-30-m2b-data-saver.md`) comes after M2 even though its date sorts later. Each task lists files, interfaces and the exact tests to write first.
- Workflow:
  - Work on one milestone per branch (`m1-app-shell`, …).
  - Follow the plan's tasks in order and write the failing test first.
  - Tick each checkbox in the plan as you go, and commit after each task.
  - Merge when `fvm flutter analyze` and `fvm flutter test` are clean.
- If the plan and the spec disagree, the spec wins. Fix the plan in the same commit and say so in the commit message.
- Spikes (M3 Task 1, M5 Task 1) record their results in spec §10 before dependent tasks start.
- Update the README Roadmap status when a milestone is merged.

## Commands

Always go through FVM; the SDK version is pinned in `.fvmrc`.

```sh
fvm flutter pub get
fvm flutter analyze          # must report no issues
fvm flutter test             # must pass
fvm dart format lib test     # format before committing
fvm flutter build apk --debug
```

## Architecture

- Feature-first folders: `lib/src/features/<feature>/{domain,data,application,presentation}`. `application` holds Riverpod controllers and services that coordinate several data sources. Create a layer only when there is code for it.
- State with Riverpod (`flutter_riverpod` 3). Expose services and repositories as providers so tests can override them. No global singletons.
- Navigation with `go_router`. Route paths live in `AppRoutes` (`lib/src/routing/app_router.dart`).
- Colours and font family names come from `lib/src/theme/app_theme.dart`. Don't hard-code hex colours or font names in widgets.
- Imports are `package:status_studio/...` (enforced by `always_use_package_imports`).
- Tests mirror `lib/` under `test/`.

## Domain rules that are easy to get wrong

- **Final render is Media3 Transformer, not FFmpeg.** The bundled FFmpeg is built with `--disable-mediacodec --disable-openssl` and has no libx264: it can't encode H.264 or read https URLs. Android renders through a Kotlin platform channel to Media3 (hardware H.264/AAC). FFmpeg is only for WAV conversion, splitting, stream-copy muxing and thumbnails.
- **Captions and branding are drawn by Flutter.** Render caption text plus the logo to one transparent PNG at output size with Flutter's text engine; Media3 overlays it. Text rendering elsewhere would break Nastaliq letter joining.
- **yt-dlp reads YouTube; Dart downloads.** `YouTubeVideoSource` runs yt-dlp (through `youtubedl-android`, on the `status_studio/ytdlp` Kotlin channel) only to get a video's title, length, stream URLs and caption tracks as JSON. The streams are downloaded in byte ranges with Dart `HttpClient`. Read without JavaScript first (`quickVideoInfo`, about 8 s on a mid-range phone) and with QuickJS only when that gives no streams (about 30 s). yt-dlp updates itself weekly and after a failed read. Don't bring back `youtube_explode_dart`: YouTube refused its stream URLs (spec §10 Q4).
- **One FFmpeg only.** `whisper_ggml` depends on `ffmpeg_kit_flutter_new_min` ^2.x. Use that same package for all video work. Don't add `ffmpeg_kit_flutter_new` (full GPL build): it duplicates native libraries and would make the app GPL. Upgrade `ffmpeg_kit_flutter_new_min` together with `whisper_ggml` when it moves to 3.x.
- **Heavy work off the UI thread.** Whisper transcription and FFmpeg runs are long. Stream progress to the UI, and stream transcript lines as they're produced so long videos are usable early.
- **Groq is the only cloud exception, and it's opt-in.** With the user's own key and the Settings switch on, scripts are written by Groq `whisper-large-v3-turbo` (spec FR-12a); otherwise Whisper runs on the phone. Never ship a key in the app. Keep the key in `flutter_secure_storage`, and never log it or put it in saved files, notifications or error text.
- **Whisper model is downloaded on first use, not bundled.** Default `small`; `base` as a lighter option.
- **Save the user's data.**
  - Script audio is the lowest-bitrate stream, or nothing when YouTube captions exist.
  - Video is never downloaded whole when it can be avoided: Fine-tune fetches only the clip window via the MP4 `sidx` index and HTTP range requests (spec FR-15).
  - Network I/O for media is Dart `HttpClient`.
- **Reuse earlier work.** Finished scripts are saved per video/language/source and reopened without downloading (spec FR-14). Whisper progress is saved per 90-second chunk and resumed.
- **RTL text.** Urdu, Arabic and Persian text needs `TextDirection.rtl` and the Nastaliq or Naskh family. Nastaliq needs a tall line height (about 2.1).
- **Distribution.** YouTube downloading keeps the app off Google Play and the App Store. Keep YouTube access behind one data-layer class so a store build could swap in local-file input.

## Code style

- Functions do one thing. If a block needs a section comment, extract it into a named function.
- Names carry meaning: no `data`, `info`, `mgr`, `tmp`, `x`. Prefer `clipStartSeconds` over `start`.
- Max 3 parameters; beyond that pass a value object.
- No boolean flag parameters that switch behaviour; write two functions.
- No output parameters; return values.
- Guard clauses and early returns; max 2 levels of nesting.
- Comments explain *why* or warn about non-obvious consequences. No comments that restate the code; no commented-out code.
- Errors: throw or return typed errors. Never return null or sentinels like -1 to signal failure.
- Prefer `const` constructors and `final` locals (enforced by lints).
- Don't build abstractions for a second caller that doesn't exist yet.

## Tests

- One assertion concept per test; Arrange-Act-Assert.
- Test names describe behaviour, e.g. `transcript_line_tap_sets_clip_start`.
- Override providers to fake YouTube, Whisper and FFmpeg in tests. Never hit the network in tests.

## Platform notes

- Application ID (Android) and bundle ID (iOS): `com.hotmail.arehmananis.statusstudio`.
- Android `minSdk` is 24 (FFmpeg Kit requirement).
- Release signing reads `android/key.properties` and `android/app/upload-keystore.jks`. Both are committed intentionally because the repo is private. Never print their contents, never make the repo public, and never switch release builds back to debug signing.
- iOS hasn't been built yet. ML Kit translation needs a deployment target of iOS 15.5 or later.
