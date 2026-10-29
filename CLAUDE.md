# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

Status Studio: a general-purpose Flutter app that turns any YouTube video, in any language, into a short status clip. Flow: paste link → on-device transcript (language auto-detected or chosen) → user taps start and end lines → fine-tune ±0.5 s → size (9:16, 4:5, 1:1, 16:9 or free crop) → caption → export with app name and logo → save or share.

Design canvas (prototype, screens, build plan, logo): https://claude.ai/artifact/HcKksQmAu8ZYBfQdbnr2RN

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

- Feature-first folders: `lib/src/features/<feature>/{data,domain,presentation}`. Create a layer only when there is code for it.
- State with Riverpod (`flutter_riverpod` 3). Expose services and repositories as providers so tests can override them. No global singletons.
- Navigation with `go_router`. Route paths live in `AppRoutes` (`lib/src/routing/app_router.dart`).
- Colours and font family names come from `lib/src/theme/app_theme.dart`. Don't hard-code hex colours or font names in widgets.
- Imports are `package:status_studio/...` (enforced by `always_use_package_imports`).
- Tests mirror `lib/` under `test/`.

## Domain rules that are easy to get wrong

- **Captions and branding are drawn by Flutter, not FFmpeg.** Render caption text plus the logo to a transparent PNG with Flutter's text engine, then overlay it with FFmpeg. FFmpeg's `drawtext` breaks Nastaliq letter joining.
- **One FFmpeg only.** `whisper_ggml` depends on `ffmpeg_kit_flutter_new_min` ^2.x. Use that same package for all video work. Don't add `ffmpeg_kit_flutter_new` (full GPL build): it duplicates native libraries and would make the app GPL. Upgrade `ffmpeg_kit_flutter_new_min` together with `whisper_ggml` when it moves to 3.x.
- **Heavy work off the UI thread.** Whisper transcription and FFmpeg runs are long. Stream progress to the UI, and stream transcript lines as they're produced so long videos are usable early.
- **Whisper model is downloaded on first use, not bundled.** Default `small`; `base` as a lighter option.
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
