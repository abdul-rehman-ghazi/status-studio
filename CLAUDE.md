# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

Status Studio: a general-purpose Flutter app that turns any YouTube video, in any language, into a short status clip. Flow: paste link → script (YouTube captions, or Groq with the user's key; language auto-detected or chosen) → user taps start and end lines → fine-tune ±0.5 s → size (9:16, 4:5, 1:1, 16:9 or free crop) → caption → export with app name and logo → save or share.

Design canvas (prototype, screens, build plan, logo): https://claude.ai/artifact/HcKksQmAu8ZYBfQdbnr2RN

## The project document

- Everything lives in one file: `docs/status-studio.md`. "The spec" means this file. It is the source of truth for behaviour, copy, sizes and error messages.
- It holds the product spec (§1–§11), milestones and their task lists (§12), behaviour that tests must cover (§13), device checks (§14) and known issues (§15).
- Code cites its § and FR numbers, so never renumber them; add new sections at the end.
- Workflow:
  - Work on one milestone per branch (`m9-groq-transcription`, …).
  - Write a milestone's tasks as a checklist under it in §12, test first, before coding.
  - Tick each checkbox as you go, and commit after each task.
  - Merge when `tool/check.sh` passes.
- If code and the document disagree, the document wins. Fix whichever is wrong in the same commit and say so in the commit message.
- Spikes record their results in §10 before dependent tasks start. Device checks go into §14, not onto the phone mid-milestone.
- Update the milestone's status in §12 when it is merged.

## Commands

Always go through FVM; the SDK version is pinned in `.fvmrc`.

```sh
fvm flutter pub get
tool/check.sh                # format + analyze + all tests; must exit 0 before every commit
fvm flutter test -r failures-only test/path/to/one_test.dart   # while writing a test or its code
fvm flutter build apk --debug
```

## Keeping sessions cheap

Every tool call re-reads the whole conversation, so cost grows with the number of calls and with session length, not with how much a command prints.
- **Test-first loop:** run only the test file you're working on, with `-r failures-only`. Run `tool/check.sh` once per task, just before the commit, never format, analyze and test as separate calls.
- **Batch work:** make all of a task's edits before running tests, and put independent reads or searches in one call.
- **Read narrowly:** read the lines you need (`sed -n` ranges, `grep -n`) rather than whole files, and don't re-read a file you've just edited.
- **One task per session:** state lives in `docs/status-studio.md` and git, so start a fresh session (`/clear`) for each milestone task instead of carrying a long one.
- **Subagents:** only for wide searches or an independent review, with a narrow brief.

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
- **One FFmpeg only.** Use `ffmpeg_kit_flutter_new_min` for all video work. Don't add `ffmpeg_kit_flutter_new` (full GPL build): it duplicates native libraries and would make the app GPL.
- **Heavy work off the UI thread.** Groq requests and FFmpeg runs are long. Stream progress to the UI, and stream transcript lines as they're produced so long videos are usable early.
- **Groq writes every script without captions.** With the user's own free key, by `whisper-large-v3-turbo` (spec FR-12a). There is no on-device Whisper (removed in M10: 0.2× real time on a Redmi Note 11) and no on/off switch: no key means the §8 "needs a free Groq key" error. Never ship a key in the app. Keep the key in `flutter_secure_storage`, and never log it or put it in saved files, notifications or error text.
- **Save the user's data.**
  - Script audio is the lowest-bitrate stream, or nothing when YouTube captions exist.
  - Video is never downloaded whole when it can be avoided: Fine-tune fetches only the clip window via the MP4 `sidx` index and HTTP range requests (spec FR-15).
  - Network I/O for media is Dart `HttpClient`.
- **Reuse earlier work.** Finished scripts are saved per video/language/source and reopened without downloading (spec FR-14). Groq progress is saved per 90-second piece and resumed.
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
- Override providers to fake YouTube, Groq and FFmpeg in tests. Never hit the network in tests.

## Platform notes

- Application ID (Android) and bundle ID (iOS): `com.hotmail.arehmananis.statusstudio`.
- Android `minSdk` is 24 (FFmpeg Kit requirement).
- Release signing reads `android/key.properties` and `android/app/upload-keystore.jks`. Both are committed intentionally because the repo is private. Never print their contents, never make the repo public, and never switch release builds back to debug signing.
- iOS hasn't been built yet. ML Kit translation needs a deployment target of iOS 15.5 or later.
