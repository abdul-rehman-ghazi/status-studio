# Status Studio

Turn a video into a short clip for WhatsApp Status, Reels, TikTok or Shorts, on your phone.

Share or pick a video you trimmed, or paste a link to a long talk (Android) and pick the moments from its script. Trim, choose a size and what the crop follows at every scene (a face, a body or a fixed spot), add lyrics written by Groq's Whisper with your own free key or typed, and export with the app's name and logo.

> **Status:** released for Android: [download the latest APK](https://github.com/abdul-rehman-ghazi/status-studio/releases/latest). iOS builds but has never run on a device.

## Documentation

- **Project document:** [`docs/status-studio.md`](docs/status-studio.md). The spec (flow, requirements, domain rules, error states, decisions, measurements), milestones and their status, and known issues, all in one file.
- **Privacy policy:** [`PRIVACY.md`](PRIVACY.md). Your video never leaves your phone; only what Groq needs is sent, with your key and after you agree.
- **Design canvas:** clickable prototype, all screens, build plan and logo options: https://claude.ai/artifact/HcKksQmAu8ZYBfQdbnr2RN

## Status and roadmap

Version 0.1.5 is released for Android on [GitHub](https://github.com/abdul-rehman-ghazi/status-studio/releases/latest). Milestones M1–M79 are merged into `dev`. Still to come:

- **F-Droid:** the build recipe is in [`fdroid/`](fdroid/). F-Droid wants 3 months of maintenance first, so it will be submitted again in February 2027.
- **iOS:** builds, but has never run on a device (it needs an iPhone and an Apple Developer account).

Status per milestone: [§12 of the project document](docs/status-studio.md#12-milestones). Known issues: [§15](docs/status-studio.md#15-known-issues-found-on-the-phone-not-fixed).

## Features

**Two ways in**

- **A video you trimmed:** share it into the app or pick it from the gallery. It is copied into the app once and never changed or uploaded; an AV1 video gets an H.264 copy.
- **A link (Android only):** paste or share a link from YouTube, Facebook, Instagram or another site yt-dlp reads. Groq writes the script in the language you choose, you search it and tick the moments you want, and only those parts download. Several moments are joined with a transition; one is kept as it is. A link you leave can be continued later.

**Fine-tune · Video**

- **Trim:** the start and end in ±0.5 s steps, with the sound's waveform.
- **Size:** 9:16, 4:5, 1:1, 16:9 or a free crop, filled or on a blurred background.
- **Louder sound:** quiet sound can be made louder.
- **Crop that moves:** at every scene you choose what the crop follows: a face, a body or a fixed spot. Detection runs on the phone, and the app never picks for you.

**Fine-tune · Lyrics**

- **Optional:** a Show lyrics switch; a reel can have none.
- **Written by Groq:** the voice is cleaned on the phone, then Groq's `whisper-large-v3` writes the words with your own free Groq key, after you agree once. Or type them yourself.
- **Edit and time** each line; lines show one at a time, in their own language. A link clip's lyrics are translated into the language you chose.
- **Proper script:** Urdu, Arabic and Persian are drawn right to left in Nastaliq or Naskh.
- **Style:** the caption's position, size and look.

**Export and after**

- An H.264 MP4 at 4 Mbit/s with the app's name and logo, ready to save to the gallery or share.
- **Home** shows unfinished work under Carry on; **History** groups each video's reels, scripts and unfinished work, so another clip from the same video needs no new script.
- **Settings:** the theme, your Groq key and the audio minutes Groq has left this hour, background work, and yt-dlp's updates.

**Privacy:** no accounts, no servers, no ads, no analytics. Only what Groq needs is sent, with your key. See [`PRIVACY.md`](PRIVACY.md).

## Tech stack

| Area | Package |
|---|---|
| State | [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) |
| Navigation | [go_router](https://pub.dev/packages/go_router) |
| Video in | [image_picker](https://pub.dev/packages/image_picker) for the gallery; shared videos through the app's own platform channel |
| Links (Android) | [yt-dlp](https://github.com/yt-dlp/yt-dlp) through [youtubedl-android](https://github.com/JunkFood02/youtubedl-android) (Python and QuickJS bundled; updates itself weekly, except in the F-Droid build) |
| Speech to text, translation | Groq's hosted Whisper (`whisper-large-v3`) and chat model, with the user's own key, over `dart:io` `HttpClient` |
| Probing, voice cleaning, thumbnails, frame sampling | [ffmpeg_kit_flutter_new_min](https://pub.dev/packages/ffmpeg_kit_flutter_new_min) (LGPL build) |
| Rendering | Media3 Transformer on Android, AVFoundation on iOS, through a platform channel; captions and logo drawn by Flutter into overlay PNGs |
| Face and body detection (on device) | [tflite_flutter](https://pub.dev/packages/tflite_flutter) with MediaPipe BlazeFace full range and EfficientDet-Lite0 (Apache 2.0, `assets/models/`) |
| Background work | [flutter_foreground_task](https://pub.dev/packages/flutter_foreground_task), [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) |
| Groq key | [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) |
| Preview | [video_player](https://pub.dev/packages/video_player) |
| Save and share | [gal](https://pub.dev/packages/gal), [share_plus](https://pub.dev/packages/share_plus) |
| Files and settings | [path_provider](https://pub.dev/packages/path_provider), [shared_preferences](https://pub.dev/packages/shared_preferences) |

## Getting started

Requirements: [FVM](https://fvm.app), Android Studio with the Android SDK, and Xcode for iOS.

```sh
fvm install          # installs the Flutter version pinned in .fvmrc (3.47.8)
fvm flutter pub get
fvm flutter run
```

Common commands:

```sh
tool/check.sh        # format and analyze; also runs the tests when a test/ folder is present
fvm flutter build apk --debug
fvm flutter build ios --no-codesign   # after `fvm flutter precache --ios` once
```

The test suite is not kept in this repository, so `tool/check.sh` skips the tests unless you have a local `test/` folder.

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
      data/                  Repositories and external services (Groq, yt-dlp, FFmpeg, the renderer…)
      application/           Riverpod controllers and coordinating services
      presentation/          Screens and widgets
android/                     Media3 renderer, video in, links (Kotlin)
ios/                         AVFoundation renderer, Share Extension (Swift)
docs/status-studio.md        Spec, milestones, known issues
assets/fonts/                Bundled Urdu and Arabic fonts (OFL)
assets/models/               Face and body detection models
fastlane/metadata/           Store text and per-version changelogs
fdroid/                      F-Droid build recipe
tool/                        Logo export and helper scripts
PRIVACY.md                   Privacy policy (from §9.1 of the spec)
```

## Platforms and distribution

- **Android:** primary target. Application ID `com.hotmail.arehmananis.statusstudio`, minimum SDK 24 (required by FFmpeg Kit). Released as signed APKs on GitHub; F-Droid to follow. IzzyOnDroid declined the app (its AI-assistance policy and APK size limit).
- **iOS:** same code, bundle ID `com.hotmail.arehmananis.statusstudio`, deployment target 15.5. No link input. It builds, but has never run on a device.

The app is not on Google Play or the App Store. It uses no non-free SDKs (no Google Play Services, Firebase or analytics), so that F-Droid can build it.

## Release signing

Release builds read `key.properties` from `$STATUS_STUDIO_KEY_PROPERTIES`, else `~/.status-studio/key.properties`, else `android/key.properties`; its `storeFile` is relative to that file. The keystore and its properties are never committed, since this repository is public. Without them a release build is unsigned.

Keep a backup of the keystore and its password outside the repo: an app can only be updated with the key it was first signed with.

## Fonts

- [Inter](https://rsms.me/inter/): the app's interface font (Regular, Medium, SemiBold, Bold).
- [Noto Nastaliq Urdu](https://fonts.google.com/noto/specimen/Noto+Nastaliq+Urdu): Urdu captions and script.
- [Noto Naskh Arabic](https://fonts.google.com/noto/specimen/Noto+Naskh+Arabic): Arabic captions, and a plainer option for Urdu.

All are licensed under the SIL Open Font License 1.1. The licence files sit next to the fonts in `assets/fonts/`.

## Releasing

1. Raise the build number (`+n`) in `pubspec.yaml`.
2. Write the changelog in `fastlane/metadata/android/en-US/changelogs/` for `n` and for the per-ABI version codes `1000+n`, `2000+n` and `4000+n` (F-Droid builds per ABI too).
3. Build and check:

   ```sh
   tool/check.sh
   fvm flutter build apk --release --split-per-abi --split-debug-info=$HOME/.status-studio/symbols/X.Y.Z
   ```

   `--split-debug-info` keeps the Dart debug symbols out of the APK (about 0.6 MB smaller) and writes them to that folder. Keep them: `fvm flutter symbolize` needs them to read a crash's Dart stack trace.

4. The APKs are in `build/app/outputs/flutter-apk/` (`app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`, `app-x86_64-release.apk`). Most phones need `arm64-v8a`. Check the signature with `$ANDROID_HOME/build-tools/<version>/apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
5. Tag the release on `dev` (`vX.Y.Z`) and publish a GitHub release with the three APKs and a `SHA256SUMS.txt`.
6. In `fdroid/com.hotmail.arehmananis.statusstudio.yml`, set each build's `versionName`, `versionCode` and `commit` (the tag's full hash), and `CurrentVersion` and `CurrentVersionCode`.

To regenerate the launcher icon after a logo change: `fvm flutter test tool/export_logo_test.dart`, then `fvm dart run flutter_launcher_icons`. Afterwards, revert its change to `ios/Runner.xcodeproj/project.pbxproj`: the tool sets the wrong build setting.

Smoke test on a phone with a release build:

1. Share a video into the app, or pick one.
2. Trim it, try each size (9:16, 4:5, 1:1, 16:9, Free) with fill and blur, and choose what the crop follows at a scene.
3. Get the lyrics from Groq, edit a line and change the style.
4. Export the reel, save it to the gallery and share it.
5. Reopen it from History.
6. On Android, paste a link, get its script, tick two moments and make the clip.

## Licence

GPL-3.0: see [`LICENSE`](LICENSE). The bundled fonts are under the SIL Open Font License 1.1, and the detection models under Apache 2.0.
