# M6 — Library, Settings and Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finished reels can be saved and shared, appear in Recent on Home, the Whisper model is managed in Settings, caches are cleaned, every error state from the spec is shown, and the app has its Trim launcher icon.

**Architecture:**
- `shared_preferences` stores recent-reel metadata and settings as JSON.
- MP4s and thumbnails live in `documents/reels/`.
- `ReelActions` wraps `gal` and `share_plus`.
- The launcher icon is rendered from `LogoPainter` to a PNG by a test-run tool, then generated with `flutter_launcher_icons`.

**Tech Stack:** shared_preferences, gal, share_plus, flutter_launcher_icons (dev).

**Spec:** FR-10, FR-11, FR-12, §4 Storage, §7, §8, §10 Q3.

## Global Constraints

- M1–M5 Global Constraints apply.
- Add dependencies with `fvm flutter pub add shared_preferences` and `fvm flutter pub add --dev flutter_launcher_icons`. Check pub.dev that each is maintained with high downloads before adding.
- Recent reels: newest first, max 50; dropping one deletes its files.
- Caches in `temp/sources/` older than 7 days are deleted on app start.
- Settings keys: `settings.whisperModel` (`small`|`base`), `recentReels` (JSON list).

## Review Focus

- **Denied gallery permission** must explain and offer to open settings, not fail silently. Test: Task 1 `save_without_access_shows_permission_message`.
- **The 51st reel** removes the oldest entry and deletes its MP4 and thumbnail. Test: Task 2 `adding_beyond_fifty_drops_oldest_and_its_files`.
- **A recent reel whose file was deleted outside the app** must disappear from the list, not crash on open. Test: Task 2 `load_skips_reels_with_missing_files`.
- **Corrupt JSON in preferences** must yield an empty list, not a crash. Test: Task 2 `corrupt_json_yields_empty_list`.
- **Switching model in Settings while the other is downloaded** keeps both files until deleted explicitly. Test: Task 4 `switching_model_keeps_downloaded_files`.

---

### Task 1: Save and share

**Files:** Create `lib/src/features/export/data/reel_actions.dart`; Modify `done_screen.dart`; Test `test/src/features/export/presentation/done_screen_test.dart`

**Interfaces:**
- `abstract interface class ReelActions { Future<void> saveToGallery(String videoPath); Future<void> share(String videoPath); }`
  - `GalReelActions`: `Gal.hasAccess()`/`requestAccess()`, then `Gal.putVideo`; throws `GalleryAccessDeniedException`.
  - Share uses `SharePlus.instance.share(ShareParams(files: [XFile(videoPath)]))`.
- `reelActionsProvider`. `ReelActions` also has `openAppSettings()`, which goes through a `status_studio/system` channel in `MainActivity`, since neither `gal` nor `share_plus` can open the app's Settings page.
- Until Task 3, Done takes the reel's file as `/done?path=…` (`AppRoutes.doneFor`).

- [x] **Step 1: Failing tests** (fake actions):
  - `save_shows_saved_state`
  - `save_without_access_shows_permission_message`: "Allow Photos access in Settings to save reels." with an "Open settings" action.
  - `share_calls_share_with_video_path`
- [x] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [x] **Step 5: Commit** `feat: save reels to gallery and share`

### Task 2: Recent reels repository

**Files:** Create `lib/src/features/library/domain/recent_reel.dart`, `lib/src/features/library/data/recent_reels_repository.dart`, `lib/src/core/ffmpeg/thumbnail_arguments.dart`; Test `test/src/features/library/data/recent_reels_repository_test.dart`, `test/src/core/ffmpeg/thumbnail_arguments_test.dart`

**Interfaces:**
- `RecentReel` per spec §6.1, with `toJson`/`fromJson`.
- `class RecentReelsRepository { RecentReelsRepository(SharedPreferencesAsync prefs); Future<List<RecentReel>> load(); Future<void> add(RecentReel reel); Future<void> delete(String id); static const maximum = 50; }`
- `List<String> thumbnailArguments({required String videoPath, required String outputPath})` → `['-y', '-ss', '0', '-i', videoPath, '-frames:v', '1', '-vf', 'scale=270:-2', outputPath]`
- After `RenderFinished`, the Export screen calls `RecentReelsController.keep(videoPath, draft)`. The renderer already writes into `documents/reels/` as `reel_<ms>.mp4`, so nothing moves and the id is that name. `keep` writes `<id>.jpg` with `thumbnailArguments` via `FfmpegRunner` (a failure only loses the picture) and calls `add`. `RecentReelsController` (`recentReelsProvider`, an `AsyncNotifier`) is created here rather than in Task 3, because Export needs it. `RecentReel.title` is the caption's first line. (The M5 renderer is `Media3Renderer`; FFmpeg can still decode H.264 for thumbnails.)

- [x] **Step 1: Failing tests:**
  - `add_puts_newest_first`
  - `adding_beyond_fifty_drops_oldest_and_its_files`
  - `delete_removes_entry_and_files`
  - `load_skips_reels_with_missing_files`
  - `corrupt_json_yields_empty_list`
  - `thumbnail_takes_first_frame_at_270_wide`
- [x] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [x] **Step 5: Commit** `feat: store recent reels`

### Task 3: Home list and reopening a reel

**Files:** Modify `home_screen.dart`, `done_screen.dart`, `app_router.dart` (`/done?id=<reelId>`); Test `test/src/features/home/presentation/home_screen_test.dart`

- [ ] **Step 1: Failing tests:**
  - `home_lists_recent_reels_newest_first`
  - `tapping_recent_reel_opens_done`
  - `long_press_offers_delete`
  - `empty_state_text_when_no_reels`
- [ ] **Step 2–4:** Run → FAIL, implement (`recentReelsProvider` as `AsyncNotifier`), run → PASS.
- [ ] **Step 5: Commit** `feat: list and reopen recent reels`

### Task 4: Settings

**Files:** Create `lib/src/features/settings/application/settings_controller.dart`, `lib/src/features/settings/presentation/settings_screen.dart`; Modify the M3 `whisperModelProvider` to read settings; Test `test/src/features/settings/presentation/settings_screen_test.dart`

**Interfaces:**
- `final whisperModelSettingProvider = AsyncNotifierProvider<SettingsController, WhisperModel>(...)` with `Future<void> select(WhisperModel model)`.
- Settings screen:
  - Two radio rows, "Small (better, slower)" and "Base (faster)", each showing size on disk or "Not downloaded" with Download/Delete.
  - Download progress comes from `ModelManager.download`.

- [ ] **Step 1: Failing tests:**
  - `selecting_base_persists_setting`
  - `download_shows_progress_then_size`
  - `delete_returns_to_not_downloaded`
  - `switching_model_keeps_downloaded_files`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: add settings for the speech model`

### Task 5: Cache cleanup and error-state audit

**Files:** Create `lib/src/core/cache_cleanup.dart`; Modify `lib/main.dart` (run cleanup after first frame, unawaited with error logging); Modify screens to cover every row of spec §8; Test `test/src/core/cache_cleanup_test.dart`, extend `test/src/core/error_messages_test.dart`

**Interfaces:**
- `Future<int> deleteStaleSources(Directory root, {required DateTime now, Duration maxAge = const Duration(days: 7)})` returns the number of folders deleted.
- On start, also call `TranscriptStore.prune()` (M3), which keeps saved scripts 90 days and at most 200 videos.

- [ ] **Step 1: Failing tests:**
  - `deletes_folders_older_than_seven_days`
  - `keeps_recent_folders`
  - `missing_root_deletes_nothing`
  - `startup_cleanup_prunes_saved_scripts` (fake store records the `prune` call)
  - `maps_insufficient_storage`
  - `maps_render_failed`
  - `maps_translation_pack_missing`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Manual audit:** trigger each spec §8 condition on a phone (airplane mode, invalid link, private video, silent video) and confirm message and actions match the table.
- [ ] **Step 6: Commit** `feat: clean stale caches and complete error states`

### Task 6: Launcher icon and release checklist

**Files:**
- Create `tool/export_logo_test.dart` (a `flutter test` that paints `LogoPainter` at 1024 px to `assets/branding/logo_1024.png` and the foreground-only variant to `assets/branding/logo_foreground_1024.png`)
- Create `flutter_launcher_icons.yaml`
- Modify `README.md` (release section)

- [ ] **Step 1:** Run `fvm flutter test tool/export_logo_test.dart`. Expected: both PNGs exist at 1024×1024.
- [ ] **Step 2:** Configure `flutter_launcher_icons` (adaptive background `#3DD68C`, foreground PNG, iOS from the full PNG). Run `fvm dart run flutter_launcher_icons`; expected: Android mipmaps and the iOS AppIcon set are updated.
- [ ] **Step 3:** Check WhatsApp's current Status video limit. Update spec §10 Q3 and, if it differs from 60 s, the M4 warning threshold and its tests.
- [ ] **Step 4:** Add a "Releasing" section to README: `fvm flutter build apk --release --split-per-abi`, where outputs go, how to verify the signature with `apksigner verify --print-certs`, and a manual smoke-test list (link → script → pick → fine-tune → each frame preset → export → save → share).
- [ ] **Step 5: Run everything:** `fvm flutter analyze && fvm flutter test && fvm flutter build apk --release --split-per-abi`. Expected: no issues, all tests pass, three signed APKs.
- [ ] **Step 6: Commit** `feat: add launcher icon and release checklist`
