# M8 — Background Work Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Writing a script and exporting a reel keep running when the user leaves the app or locks the phone, and a notification says when they're done (spec FR-16). Today Android's battery saving pauses or kills the app once it's in the background, and the work is lost.

**Architecture:**
- The work stays where it is: the script pipeline and Media3 already run in the app process. An Android **foreground service** only keeps that process alive. It holds a partial wake lock, so the CPU keeps running with the screen off, and shows an ongoing notification. Doze and battery saving leave a foreground service running, network included.
- Dart decides when the service runs. `BackgroundWork.keepRunning(stream, notices)` wraps a work stream:
  - first event → start the service
  - each event → update the notification
  - done or error → stop the service, and post a result notification if the app isn't on screen
  - cancel → stop the service quietly
- Both work streams already close after their last event: `ScriptPipeline.run`/`writeAgain` and `Renderer.render`.
- Two jobs can run at once (Whisper keeps writing while the user exports). The service runs while either does, and the notification shows the one that started last.
- The first job ever asks for notifications (Android 13+) and for exemption from battery optimisation. Settings shows both states with "Allow", plus a hint for Xiaomi's own battery saver.

**Tech Stack:** `flutter_foreground_task` 11 (foreground service of type `dataSync`, wake lock, Wi-Fi lock, permission requests), `flutter_local_notifications` 22 (result notifications). No hand-written Kotlin: the user chose packages over a native service to keep Android code small, so the ongoing notification shows the percent as text instead of a bar.

**Spec:** FR-16, §5 Package map, §9.

## Global Constraints

- M1–M7 Global Constraints apply.
- Android only; iOS isn't built.
- No platform call in Dart tests: tests override `backgroundWorkPlatformProvider` with `FakeBackgroundWorkPlatform`.
- A failing platform call (no permission, service refused) is reported with `FlutterError.reportError` and never stops the work.
- The plugins are reached only through `BackgroundWorkPlatform`, so a store or iOS build could swap them.

## Review Focus

- **Cancel never posts a result**, and done/failed post only when the app is hidden. Tests: Task 3 `cancel_stops_without_a_result`, `result_is_posted_only_when_the_app_is_hidden`.
- **The service stops when the last job ends**, not the first. Test: Task 3 `service_keeps_running_while_another_job_runs`.
- **Platform calls stay in order**: show, then stop, never reordered by async gaps. Test: Task 3 `stop_follows_the_last_show`.
- **The wrapped stream behaves like the original**: same events, same error, cancel reaches the source. Task 4 tests.

---

### Task 1: Packages and Android setup

**Files:** Modify `pubspec.yaml`, `AndroidManifest.xml`, `android/app/build.gradle.kts`; Create `android/app/src/main/res/drawable/ic_notification.xml`.

**Interfaces:**
- `flutter_foreground_task` ^11.0.3 (service, wake lock, notification permission, battery exemption) and `flutter_local_notifications` ^22.3.3 (result notifications). No Kotlin.
- Manifest:
  - `FOREGROUND_SERVICE_DATA_SYNC` and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`; the plugins declare the rest.
  - The plugin's `ForegroundService` with `foregroundServiceType="dataSync"` and `stopWithTask="true"`.
  - Meta-data `com.hotmail.arehmananis.statusstudio.notification_icon` → `@drawable/ic_notification`, the Trim logo's brackets and bars.
- Gradle: core library desugaring (`desugar_jdk_libs` 2.1.4), which `flutter_local_notifications` needs.

- [x] **Step 1:** Add the packages, manifest entries, icon and desugaring.
- [x] **Step 2:** `fvm flutter build apk --debug` → builds.
- [x] **Step 3: Commit** `build: add background service and notification packages`

### Task 2: Dart platform client

**Files:** Create `lib/src/features/background/domain/work_notice.dart`, `lib/src/features/background/data/background_work_platform.dart`, `test/helpers/fake_background_work_platform.dart`; Test `test/src/features/background/domain/work_notice_test.dart`

**Interfaces:**
- `enum BackgroundJob { script, export }`, with a result notification id per job.
- `ProgressNotice {title, text, percent}`: immutable, value equality, `body` → `45 % · text`. `ResultNotice {title, text}`.
- `abstract interface class BackgroundWorkPlatform`:
  - `show(ProgressNotice)`, `stop()`, `postResult(BackgroundJob, ResultNotice)`
  - `requestNotifications()`, `notificationsEnabled()`, `runsUnrestricted()`, `askToRunUnrestricted()`, `openAppInfo()`
- `PluginBackgroundWorkPlatform` over the two packages. It initialises both lazily on first use, and `show` starts the service or updates it. `openAppInfo` uses the existing `status_studio/system` channel. A `ServiceRequestFailure` is thrown as its error. `backgroundWorkPlatformProvider`.
- `FakeBackgroundWorkPlatform` records calls; `TestSetup` overrides the provider with one.
- The plugin wrapper is thin glue over static plugin APIs and isn't unit-tested; it's covered by the device checks.

- [x] **Step 1: Failing tests** `progress_body_puts_the_percent_first`, `notices_with_the_same_words_and_percent_are_equal`.
- [x] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [x] **Step 5: Commit** `feat: background work platform over the plugins`

### Task 3: BackgroundWork and BackgroundAccess

**Files:** Create `lib/src/features/background/application/background_work.dart`, `background_access.dart`; Test `test/src/features/background/application/background_work_test.dart`, `background_access_test.dart`

**Interfaces:**
- `BackgroundAccess(platform, preferences)`:
  - `askOnce()`: notifications, then battery exemption unless already exempt. Remembered in preferences (`backgroundAccessAsked`).
  - `status()` → `({bool notifications, bool unrestricted})`
  - `allowNotifications()`: requests, and opens App info when still refused
  - `allowUnrestricted()`
- `BackgroundWork(BackgroundWorkServices)`, where `BackgroundWorkServices = ({platform, access, isAppVisible})`:
  - `showProgress(job, ProgressNotice)`
  - `finish(job, ResultNotice)`: ends the job; posts the result if `!isAppVisible()`
  - `cancel(job)`: ends the job quietly
- The platform sees only changes: the latest-started job's notice, deduplicated, and `stop` once the last job ends. Calls go through one queue so they keep their order. The first job of a run calls `access.askOnce()`.
- `appIsVisibleProvider`: `WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed`.

- [ ] **Step 1: Failing tests:**
  - `first_progress_shows_the_notice`
  - `unchanged_notice_is_not_sent_again`
  - `notice_shows_the_job_that_started_last`
  - `service_keeps_running_while_another_job_runs`
  - `stop_follows_the_last_show`
  - `cancel_stops_without_a_result`
  - `result_is_posted_only_when_the_app_is_hidden`
  - `result_is_not_posted_while_the_app_is_on_screen`
  - `failed_platform_call_does_not_stop_the_work`
  - `first_job_asks_for_access`
  - access: `asks_for_notifications_then_battery_once`, `skips_battery_request_when_already_exempt`, `refused_notifications_open_app_info`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: track background jobs and post their results`

### Task 4: keepRunning stream wrapper

**Files:** Modify `background_work.dart`; Test `background_work_test.dart`

**Interfaces:**
- `abstract interface class JobNotices<T> { BackgroundJob get job; ProgressNotice progress(T event); ResultNotice get done; ResultNotice failed(Object error); }`
- `Stream<T> BackgroundWork.keepRunning<T>(Stream<T> work, JobNotices<T> notices)`: passes events and the error through unchanged; cancelling it cancels `work` and returns that cancel's future.

- [ ] **Step 1: Failing tests:**
  - `kept_stream_passes_events_through`
  - `each_event_updates_the_notice`
  - `finished_work_posts_done`
  - `failed_work_posts_failed_and_passes_the_error`
  - `cancelled_work_cancels_the_source_and_posts_nothing`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: keep a work stream running in the background`

### Task 5: Script in the background

**Files:** Create `lib/src/features/transcript/application/script_notices.dart`; Modify `script_pipeline.dart` (step names on `ScriptStage`), `script_progress_controller.dart`, `processing_screen.dart`; Test `script_notices_test.dart`, `script_progress_controller_test.dart`

**Interfaces:**
- `ScriptStage.label`: "Downloading the speech model", "Downloading audio", "Detecting the language", "Writing the script", "Lining up timestamps". Processing uses it for its step rows.
- `ScriptNotices(SourceVideo)`:
  - progress: stage label · video title · overall percent
  - done: "Script ready" · title
  - failed: "Script stopped" · §8 message
- `ScriptProgressController` follows `keepRunning(pipeline.run(…), ScriptNotices(video))`, and the same for `writeAgain`.

- [ ] **Step 1: Failing tests:**
  - `script_progress_notice_names_the_step_and_video`
  - `script_done_notice_says_ready`
  - `script_failed_notice_shows_the_error_message`
  - `running_script_keeps_the_app_in_the_background`
  - `cancelled_script_stops_the_background_service`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: keep writing the script in the background`

### Task 6: Export in the background

**Files:** Create `lib/src/features/export/application/export_notices.dart`; Modify `export_screen.dart`; Test `export_notices_test.dart`, `export_flow_test.dart`

**Interfaces:**
- `ExportNotices(String videoTitle)`:
  - progress: "Rendering your reel" · title · percent (100 on `RenderFinished`)
  - done: "Reel ready" · "Tap to save or share it."
  - failed: "Export stopped" · §8 message
- `ExportScreen` renders through `keepRunning(renderer.render(draft), ExportNotices(...))`.

- [ ] **Step 1: Failing tests:**
  - `export_progress_notice_shows_the_percent`
  - `export_done_notice_says_ready`
  - `export_failed_notice_shows_the_error_message`
  - `rendering_keeps_the_app_in_the_background`
  - `cancelled_export_stops_the_background_service`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: keep exporting in the background`

### Task 7: Settings, "Background work"

**Files:** Create `lib/src/features/settings/presentation/background_work_section.dart`; Modify `settings_screen.dart`; Test `test/src/features/settings/presentation/background_work_section_test.dart`

**Interfaces:**
- A section under "YouTube support" with:
  - HintText: "Keeps writing scripts and exporting when you leave the app or lock the phone."
  - Row "Notifications": "On" or "Off: you won't hear when work is done", with "Allow" when off
  - Row "Battery optimisation": "Off: work keeps going with the screen locked" or "On: Android may pause work in the background", with "Allow" when on
  - Hint "On Xiaomi and some other phones, also set Battery saver to No restrictions in App info." with "Open App info"
- Status re-reads when the app resumes, after the user returns from a system dialog or App info.

- [ ] **Step 1: Failing tests:**
  - `battery_optimised_offers_allow`
  - `allow_battery_asks_android`
  - `notifications_off_offers_allow`
  - `allowed_rows_offer_nothing`
  - `open_app_info_opens_it`
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `feat: show background work access in Settings`

### Task 8: Wrap up

- [ ] Device checks in `docs/device-testing-todo.md` (M8 section).
- [ ] README Roadmap: M8.
- [ ] `fvm flutter analyze`, `fvm flutter test`, `fvm flutter build apk --debug` clean.
- [ ] Review by a fresh subagent; fix findings test-first.
- [ ] Commit, push the branch.
