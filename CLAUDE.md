# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

Status Studio: a general-purpose Flutter app (Android and iOS) that turns a video the user already trimmed elsewhere, in any language, into a short status clip. Flow (since M30): share or pick a trimmed video → Fine-tune · Video, with a Trim tab (±0.5 s) and a Crop tab (size 9:16, 4:5, 1:1, 16:9 or free crop; the crop that moves at each scene, on a scene strip, with a per-scene choice of face, body or spot) → Fine-tune · Lyrics, one screen for the lyrics (a Show lyrics switch; Get lyrics from Groq with the user's key, after voice cleaning, or type them; edit and time the lines; caption position and size in a Style sheet; original language only) → export with app name and logo → save or share. There is no Processing or Caption screen any more. Until M22 the input was a YouTube link; YouTube was dropped in the 2026-11-05 pivot (M23–M27, spec §12).

Design canvas (prototype, screens, build plan, logo): https://claude.ai/artifact/HcKksQmAu8ZYBfQdbnr2RN

## The project document

- Everything lives in one file: `docs/status-studio.md`. "The spec" means this file. It is the source of truth for behaviour, copy, sizes and error messages.
- It holds the product spec (§1–§11), milestones and their task lists (§12), behaviour that tests must cover (§13) and known issues (§15). §14 (device checks) was emptied on 2026-11-10: the owner does all device testing outside the document.
- Code cites its § and FR numbers, so never renumber them; add new sections at the end.
- Workflow:
  - Work on one milestone per branch (`m9-groq-transcription`, …).
  - Write a milestone's tasks as a checklist under it in §12, test first, before coding.
  - Tick each checkbox as you go, and commit after each task.
  - Merge when `tool/check.sh` passes.
- If code and the document disagree, the document wins. Fix whichever is wrong in the same commit and say so in the commit message.
- Spikes record their results in §10 before dependent tasks start. Don't write device checks into the document or run them on a phone: the owner tests on devices themselves.
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

- **Final render is Media3 Transformer, not FFmpeg.** The bundled FFmpeg is built with `--disable-mediacodec --disable-openssl` and has no libx264: it can't encode H.264 or read https URLs. Android renders through a Kotlin platform channel to Media3 (hardware H.264/AAC). On iOS (from M26) AVFoundation renders the same spec over the same channel. FFmpeg is only for probing (duration, size, rotation, audio track), audio cleaning and splitting for Groq, thumbnails, and frame sampling for Follow the person.
- **Captions and branding are drawn by Flutter.** Render caption text plus the logo to one transparent PNG at output size with Flutter's text engine; Media3 overlays it. Text rendering elsewhere would break Nastaliq letter joining.
- **Video comes in as a local file.** It is shared into the app or chosen with the gallery picker, copied into app storage (`sources/<videoId>/source.<ext>`) and identified by a fingerprint (`v_<16 hex>`: file size plus SHA-256 of the first and last 1 MiB). No network for media. There is no YouTube code: don't bring back yt-dlp or `youtube_explode_dart` (spec §10 Q4 is history).
- **One FFmpeg only.** Use `ffmpeg_kit_flutter_new_min` for all video work (audio cleaning and splitting for Groq, thumbnails, frame sampling). Don't add `ffmpeg_kit_flutter_new` (full GPL build): it duplicates native libraries and would make the app GPL.
- **Heavy work off the UI thread.** Groq requests and FFmpeg runs are long. Stream progress to the UI, and stream transcript lines as they're produced so long videos are usable early.
- **Groq writes every script without captions.** With the user's own free key, by `whisper-large-v3` (spec FR-12a; turbo until M24, §10 item 8). There is no on-device Whisper (removed in M10: 0.2× real time on a Redmi Note 11) and no on/off switch: no key means the §8 "needs a free Groq key" error. Nothing is sent before the user taps Get lyrics from Groq and agrees once on the consent screen (FR-30, M27): `GroqClient` requires a `beforeUpload` check, and the app passes the consent check; keep it on every new upload. Fix with Groq (FR-19) was removed in M36. Never ship a key in the app. Keep the key in `flutter_secure_storage`, and never log it or put it in saved files, notifications or error text.
- **Captions show one line at a time** (spec FR-7a). Each line is its own overlay PNG and cue; Kotlin opens each PNG when due, so the PNGs must outlive `start` and be deleted when the render ends.
- **Save the user's data.**
  - No media is downloaded (ML Kit translation and its language packs were removed in M30), and no code is fetched at runtime. The only upload is the cleaned script-audio pieces (16 kHz mono FLAC), to Groq with the user's key.
  - The video is copied once into app storage and never changed or uploaded. An AV1 video is the exception (M31): the bundled FFmpeg can't decode AV1, so the native renderer's `convert` writes an H.264 copy, `source.h264.mp4`, which is kept instead.
  - Network I/O is Dart `HttpClient`, for Groq only.
- **Reuse earlier work.** Finished scripts are saved per video fingerprint, language and source and reopened without cleaning or uploading (spec FR-14); the kept source file reopens Fine-tune. Groq progress is saved per 90-second piece and resumed; cleaned pieces are cached per video.
- **The crop's subject is chosen by the user at every scene** (spec FR-27): a face, a body or a fixed spot, asked even with one face or none. Never auto-pick, never carry a choice to another scene by look-alike.
- **RTL text.** Urdu, Arabic and Persian text needs `TextDirection.rtl` and the Nastaliq or Naskh family. Nastaliq needs a tall line height (about 2.1).
- **Distribution.** No YouTube and no runtime-fetched code, so Play Store and App Store builds become possible. M27 did the policy work: consent before the first Groq upload (FR-30), no battery-optimisation request, the privacy policy and store answers (§9.1–9.2), listing rules (§9.3), `ios/Runner/PrivacyInfo.xcprivacy`, and permissions removed from the merged manifest. A new SDK or permission means re-checking §9.2. Keep the words "YouTube" and "WhatsApp" out of store listings.

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

- From M23 task 5 the user writes and runs the tests. Claude doesn't change tests or run `tool/check.sh`; it runs `fvm flutter analyze` only, lists tests that its change makes stale in the milestone's task text in `docs/status-studio.md` §12, and says in the commit message that tests were not run. This replaces "test first" and "`tool/check.sh` before every commit" until the user says otherwise.
- One assertion concept per test; Arrange-Act-Assert.
- Test names describe behaviour, e.g. `transcript_line_tap_sets_clip_start`.
- Override providers to fake the incoming video, Groq and FFmpeg in tests. Never hit the network in tests.

## Platform notes

- Application ID (Android) and bundle ID (iOS): `com.hotmail.arehmananis.statusstudio`.
- Android `minSdk` is 24 (FFmpeg Kit requirement).
- Release signing reads `android/key.properties` and `android/app/upload-keystore.jks`. Both are committed intentionally because the repo is private. Never print their contents, never make the repo public, and never switch release builds back to debug signing.
- iOS was built in M26 (branch `m26-ios`) and builds with `fvm flutter build ios --no-codesign`, but **its Share Extension, AVFoundation renderer and background work have never run**: they need an iPhone and the Apple Developer account (signing and the App Group `group.com.hotmail.arehmananis.statusstudio`).
  - Deployment target 15.5 (ML Kit 9 face detection). Five plugins have no Swift Package Manager support (CocoaPods stays); ML Kit and `ffmpeg_kit` have no arm64 simulator slice, so use a device. After `fvm flutter pub get`, `fvm flutter precache --ios` is needed once before `pod install`.
  - Native iOS code is in `ios/Runner/` (`VideoIn/`, `Render/`, `System/`), `ios/ShareExtension/` and `ios/Shared/`. The Xcode project is edited by script with the `xcodeproj` gem that CocoaPods bundles (no Xcode GUI needed); new Swift files must be added to the target that way. The Share Extension uses our own `status_studio/video_in` channel, not `receive_sharing_intent`.
  - iOS has no foreground service: scripts get a short background task and resume per saved piece; an export waits while the app is not in front (`ForegroundGate`), because Core Image can't use the GPU in the background.
