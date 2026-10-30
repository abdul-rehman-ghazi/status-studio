# Status Studio

Turn any YouTube video into a short clip for WhatsApp Status, Reels, TikTok or Shorts, on your phone.

Paste a link. The app writes out the video's script on the device, in whatever language it's in. Tap the line where your clip starts and the line where it ends, pick a size, add a caption, and share. The speech-to-text and translation run offline after the first model download.

> **Status:** early setup. The app skeleton, dependencies and fonts are in place; the features below are being built milestone by milestone.

## Documentation

- **Product and technical spec:** [`docs/superpowers/specs/2026-10-29-status-studio-design.md`](docs/superpowers/specs/2026-10-29-status-studio-design.md). Flow, requirements, domain rules, error states, decisions and open questions.
- **Implementation plans:** one per milestone in [`docs/superpowers/plans/`](docs/superpowers/plans/), written as test-first tasks with checkboxes.
- **Design canvas:** clickable prototype, all screens, build plan and logo options: https://claude.ai/artifact/HcKksQmAu8ZYBfQdbnr2RN

## Roadmap

| Milestone | Delivers | Status |
|---|---|---|
| Setup | Project, dependencies, fonts, signing, docs | Done |
| [M1](docs/superpowers/plans/2026-10-29-m1-app-shell.md) | Every screen wired with fake services; real domain logic | Done (branch m1-app-shell) |
| [M2](docs/superpowers/plans/2026-10-29-m2-video-source.md) | YouTube metadata, downloads, cache, clip preview | Done (branch m2-video-source) |
| [M2b](docs/superpowers/plans/2026-10-30-m2b-data-saver.md) | Low-bitrate script audio, clip-only download via `sidx` + HTTP ranges | Done (branch m2b-data-saver) |
| [M3](docs/superpowers/plans/2026-10-29-m3-transcription.md) | On-device script: Whisper, YouTube captions, language detection | Done (branch m3-transcription) |
| [M4](docs/superpowers/plans/2026-10-29-m4-fine-tune.md) | Waveform, long-clip warning, language re-run | Done (branch m4-fine-tune) |
| [M5](docs/superpowers/plans/2026-10-29-m5-render.md) | Overlay, Roman Urdu, translation, Media3 export | Done (branch m5-render) |
| [M6](docs/superpowers/plans/2026-10-29-m6-library-settings-polish.md) | Save/share, recent reels, settings, icon, error states | Next |

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
| YouTube download | [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart) |
| Speech to text (on device) | [whisper_ggml](https://pub.dev/packages/whisper_ggml) (whisper.cpp) |
| Video and audio processing | [ffmpeg_kit_flutter_new_min](https://pub.dev/packages/ffmpeg_kit_flutter_new_min) (LGPL build) |
| Translation (on device) | [google_mlkit_translation](https://pub.dev/packages/google_mlkit_translation) |
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
fvm flutter analyze
fvm flutter test
fvm dart format lib test
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
docs/superpowers/            Spec and milestone implementation plans
assets/fonts/                Bundled Urdu and Arabic fonts (OFL)
test/                        Mirrors lib/
```

## Release signing

Release builds are signed with the upload keystore at `android/app/upload-keystore.jks`. Gradle reads the alias and passwords from `android/key.properties`. Both are committed because this repository is **private**: never make it public or share it, since anyone with the keystore can sign updates as this app.

Keep a separate backup of the keystore and its password outside the repo: an app can only be updated with the key it was first signed with.

## Platforms

- **Android**: primary target. Application ID `com.hotmail.arehmananis.statusstudio`. Minimum SDK 24 (required by FFmpeg Kit).
- **iOS**: same code, bundle ID `com.hotmail.arehmananis.statusstudio`. Not built yet. ML Kit translation needs iOS 15.5 or later.

Downloading from YouTube is against YouTube's terms and app store policies, so this app is meant to be installed directly (APK), not published to Google Play or the App Store.

## Fonts

- [Inter](https://rsms.me/inter/): the app's interface font (Regular, Medium, SemiBold, Bold).
- [Noto Nastaliq Urdu](https://fonts.google.com/noto/specimen/Noto+Nastaliq+Urdu): Urdu captions and script.
- [Noto Naskh Arabic](https://fonts.google.com/noto/specimen/Noto+Naskh+Arabic): Arabic captions, and a plainer option for Urdu.

All are licensed under the SIL Open Font License 1.1. The licence files sit next to the fonts in `assets/fonts/`.
