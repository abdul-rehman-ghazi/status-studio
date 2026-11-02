# Device testing TODO

All on-phone checks are deferred until the milestones are built. Each milestone adds its checks here instead of running them. Tick an item only after checking it on a phone with a **release** build: debug builds compile whisper.cpp without optimisations.

Test phone so far: Pixel 6a (Tensor, 6 GB, Android 17). The spec's speed target is a mid-range phone, so a slower phone should also be tried.

## Already passed (Pixel 6a, M4 debug build, 2026-10-30)

- [x] Real YouTube title, channel and length on Source.
- [x] Captions path: the script appears in seconds and the language is detected (English).
- [x] Clip-only download (FR-15): YouTube accepted the range requests; no whole-video fallback (5.4 MB for a 35 s window).
- [x] The Fine-tune preview plays only the clip and stops at its end.
- [x] Waveform drawn with the clip highlighted; the phone's FFmpeg makes the same WAV as desktop ffmpeg (zero lag), so the `aresample` padding works in the min build.
- [x] Progressive lines: "Start picking lines" appears after the first chunk; Script shows "Still writing… NN %".
- [x] Urdu renders right to left in Nastaliq on Script.

## To check

### M2 / M2b: video source
- [ ] Lip sync in the Fine-tune preview (clip files mux audio and video with `-itsoffset`).
- [ ] Nudging past the downloaded window downloads a new window and plays correctly.
- [ ] A video whose streams don't support ranges falls back to the whole video; the preview and waveform still work.
- [ ] Reopening the same clip after an app restart reuses the cached clip (no new download).

### M3: script
- [ ] **Whisper speed spike (spec §10 Q2).** In a release build, time `small` and `base` on a 5-minute Urdu speech clip and a 5-minute sung clip. Switch the default to `base` if `small` is much slower than real time. Debug-build reference: 344 s for one 90 s chunk on the Pixel 6a.
  - *Pixel 6a, sung clip, done:* quantised small runs at 1.5× real time; the app now downloads quantised models (spec §10 Q2). Still to do: a speech clip, and the Redmi.
- [ ] Settings: each model's ⓘ sheet reads well; Medium and Large download and write a script (Large may close the app on a 6 GB phone).
- [ ] 90-second chunking doesn't damage lines at chunk boundaries.
- [ ] Whisper quality on real Urdu speech and on singing.
- [ ] Kill the app mid-transcription, reopen and restart: Whisper resumes from the saved chunk.
- [ ] A saved script reopens with the "Using the saved script from <date>" banner, and "Write it again" works.
- [ ] Airplane mode with the model and audio already on the phone: the script is still written (captions fail over to Whisper).
- [ ] System back on Processing stops the run (no CPU use afterwards).

### M4: fine-tune
- [ ] Waveform lines up with the audio you hear (the clip's loud parts sit under the highlighted bars).
- [ ] Long-clip warning appears above 60 s.
- [ ] Changing the language on Script reuses the downloaded audio (no data used).

### M5: render
- [ ] Effect chain (M5 Task 3 Step 5): render a 10 s clip with each fill (9:16 crop centre, 9:16 blur, 4:5 crop, 16:9 none, free) and a test overlay. Check it's H.264, each frame matches the layout, the overlay is full-frame and sharp, and audio is in sync.
- [ ] Blur background: Media3's blur stretches the frame behind the sharp copy instead of covering (spec §6.3.1). If it looks wrong, switch to the two-sequence `Composition`.
- [ ] In a release build, export 9:16 crop, 4:5 blur, 16:9 and free crop. Each MP4 plays in the gallery, shares to WhatsApp Status without an "unsupported" error, matches the preview, and shows the Urdu caption in proper Nastaliq.

### M7: yt-dlp video source
- [ ] A video with no captions: Source shows its title within about 10 s, and "Downloading audio" shows percent, MB and speed, finishing in seconds.
- [ ] A video with manual captions gets its script from the captions.
- [ ] Fine-tune downloads only the clip window (FR-15) from yt-dlp's URLs, and plays in sync.
- [ ] Switch between Wi-Fi and mobile data on Fine-tune: the clip still downloads (fresh URLs after a 403).
- [ ] Settings shows the yt-dlp version; Update says updated or up to date.
- [ ] First start after install: the weekly update runs once (about 3 MB), and videos still open afterwards.
- [ ] A private video shows "This video can't be downloaded."; airplane mode shows the offline message.
- [ ] Release build: Python unpacks on first use (first read about 13 s), later reads about 8 s.
- [ ] Working screen: every download and the script step show percent, done of total and speed.

### M6: library, settings, polish
- [ ] WhatsApp's Status limit: check the longest trim the Status composer allows. If it's 90 s, raise the long-clip warning threshold (spec §10 Q3).
- [ ] Android 10 and newer: Save works without a permission prompt.
- [ ] Android 7–9 (API 24–28): Save asks for storage access once; a refusal shows the message and "Open settings" opens the app's Settings page, where storage can be allowed.
- [ ] Launcher icon looks right as an adaptive icon (round, squircle and square masks) and on the home screen.
- [ ] Trigger each spec §8 condition (airplane mode, invalid link, private video, silent video) and confirm the message and actions match the table.
- [ ] Release smoke test: link → script → pick → fine-tune → each frame preset → export → save → share.

## Fixes found on the phone (not yet made)

- [x] YouTube caption lines keep `♪` symbols and `[♪♪♪]` placeholder lines; they would end up in the clip caption. *Fixed: music symbols and sound tags are dropped.*
- [ ] `whisper_ggml` converts each chunk to WAV again (`chunk_000.wav.wav`) although the chunks already are WAVs.
- [ ] Processing says "Downloading audio" even when the script audio is already cached.
- [x] The "Downloading the speech model" row disappears after it finishes instead of showing a tick. *Fixed.*
- [ ] The language list shows both "English (detected)" and "English".
- [x] Automatic language takes an auto-generated caption track in any language. For an Urdu naat (Owais Raza Qadri, "Main Madine Chala", `s6kE_uP3xH4`) YouTube's only track was auto-generated Romanian ("[Muzică]", "[Aplauze]", "ab", "Mad"), so the script was junk and labelled "Detected language". Auto-generated tracks should only be used when their language is the one the user chose; otherwise Whisper should write the script. *Fixed (spec FR-3 changed): automatic language uses manual tracks only.*
