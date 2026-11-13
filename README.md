# Status Studio

Turn any YouTube video into a short clip for WhatsApp Status, Reels, TikTok or Shorts, on your phone.

Paste a link. The app writes out the video's script on the device, in whatever language it's in. Tap the line where your clip starts and the line where it ends, pick a size, add a caption, and share. The speech-to-text and translation run offline after the first model download.

> **Status:** early setup. The app skeleton, dependencies and fonts are in place; the features below are being built milestone by milestone.

## Documentation

- **Project document:** [`docs/status-studio.md`](docs/status-studio.md). The spec (flow, requirements, domain rules, error states, decisions, measurements), milestones and their status, device checks and known issues, all in one file.
- **Design canvas:** clickable prototype, all screens, build plan and logo options: https://claude.ai/artifact/HcKksQmAu8ZYBfQdbnr2RN

## Roadmap

M1–M8 are done and merged into `dev`. Saved scripts in Recent and model download controls are done on their branches. M9, optional Groq cloud transcription, is specified. Status per milestone: [§12 of the project document](docs/status-studio.md#12-milestones).

## Features (planned)

- **Script from a link**: download the audio, detect the language (or choose it), and transcribe it on the phone with Whisper.
- **Pick by line**: tap the start and end lines of the script; nudge either end by ±0.5 s.
- **Sizes**: 9:16, 4:5, 1:1, 16:9 or free crop; crop to fill or blurred background.
- **Captions**: from the picked lines, in the original script, Roman Urdu or a translation, drawn in proper Nastaliq.
- **Branding**: the Status Studio name and logo on every export.
- **Save and share**: save to the gallery or open the system share sheet.

## Tech stack

| Area | Package |
|---|---|
| State | [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) |
| Navigation | [go_router](https://pub.dev/packages/go_router) |
| Reading YouTube videos (Android) | [yt-dlp](https://github.com/yt-dlp/yt-dlp) through [youtubedl-android](https://github.com/JunkFood02/youtubedl-android) (Python and QuickJS bundled, updates itself) |
| Downloads | `dart:io` `HttpClient` byte-range requests |
| Speech to text | Groq's hosted Whisper, with the user's own key (`dart:io` `HttpClient`) |
| Video and audio processing | [ffmpeg_kit_flutter_new_min](https://pub.dev/packages/ffmpeg_kit_flutter_new_min) (LGPL build) |
| Face and body detection (on device) | [tflite_flutter](https://pub.dev/packages/tflite_flutter) with MediaPipe BlazeFace full range and EfficientDet-Lite0 (Apache 2.0, `assets/models/`) |
| Preview | [video_player](https://pub.dev/packages/video_player) |
| Save and share | [gal](https://pub.dev/packages/gal), [share_plus](https://pub.dev/packages/share_plus) |
| Files | [path_provider](https://pub.dev/packages/path_provider) |

## Getting started

Requirements: [FVM](https://fvm.app), Android Studio with the Android SDK, and Xcode for iOS.

```sh
fvm install          # installs the Flutter version pinned in .fvmrc (3.47.8)
fvm flutter pub get
fvm flutter run
```

Common commands:

```sh
tool/check.sh        # format, analyze and test; prints only failures
fvm flutter build apk --debug
```

## Project structure

```
lib/
  main.dart                  App entry point
  src/
    app.dart                 MaterialApp, theme and router
    routing/                 Routes and the GoRouter provider
    theme/                   Colours, fonts and ThemeData
    features/<feature>/
      domain/                Models and pure logic
      data/                  Repositories and external services (YouTube, Whisper, FFmpeg…)
      application/           Riverpod controllers and coordinating services
      presentation/          Screens and widgets
docs/status-studio.md        Spec, milestones, device checks, known issues
assets/fonts/                Bundled Urdu and Arabic fonts (OFL)
test/                        Mirrors lib/
```

## Release signing

Release builds are signed with the upload keystore at `android/app/upload-keystore.jks`. Gradle reads the alias and passwords from `android/key.properties`. Both are committed because this repository is **private**: never make it public or share it, since anyone with the keystore can sign updates as this app.

Keep a separate backup of the keystore and its password outside the repo: an app can only be updated with the key it was first signed with.

## Platforms

- **Android**: primary target. Application ID `com.hotmail.arehmananis.statusstudio`. Minimum SDK 24 (required by FFmpeg Kit).
- **iOS**: same code, bundle ID `com.hotmail.arehmananis.statusstudio`, deployment target 15.5. It builds, but has never run on a device.

Downloading from YouTube is against YouTube's terms and app store policies, so this app is meant to be installed directly (APK), not published to Google Play or the App Store.

## Fonts

- [Inter](https://rsms.me/inter/): the app's interface font (Regular, Medium, SemiBold, Bold).
- [Noto Nastaliq Urdu](https://fonts.google.com/noto/specimen/Noto+Nastaliq+Urdu): Urdu captions and script.
- [Noto Naskh Arabic](https://fonts.google.com/noto/specimen/Noto+Naskh+Arabic): Arabic captions, and a plainer option for Urdu.

All are licensed under the SIL Open Font License 1.1. The licence files sit next to the fonts in `assets/fonts/`.

## Releasing

```sh
tool/check.sh
fvm flutter build apk --release --split-per-abi
```

- The APKs are in `build/app/outputs/flutter-apk/` (`app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk`). Most phones need `arm64-v8a`.
- Release builds are signed with `android/app/upload-keystore.jks` through `android/key.properties`. Check the signature with `$ANDROID_HOME/build-tools/<version>/apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
- To regenerate the launcher icon after a logo change: `fvm flutter test tool/export_logo_test.dart`, then `fvm dart run flutter_launcher_icons`. Afterwards, revert its change to `ios/Runner.xcodeproj/project.pbxproj`: the tool sets the wrong build setting.

Smoke test on a phone with a release build:

1. Paste a link and get the script.
2. Pick a start and an end line.
3. Fine-tune the clip and play it.
4. Try each frame preset (9:16, 4:5, 1:1, 16:9, Free), with crop and blur.
5. Export the reel.
6. Save it to the gallery.
7. Share it.
8. Reopen the reel from Recent.

The full on-phone checklist is in [§14 of the project document](docs/status-studio.md#14-device-checks).

