# Status Studio

**Updated 2026-11-04.** The one project document: product spec, engineering rules, milestones, device checks and known issues. It is the source of truth for behaviour, copy, sizes and error messages. Code cites its section (§) and FR numbers, so keep them stable and add new sections at the end. Design canvas: <https://claude.ai/artifact/HcKksQmAu8ZYBfQdbnr2RN>

## 1. Summary

Status Studio turns any YouTube video, in any language, into a short clip for WhatsApp Status, Reels, TikTok or Shorts. The user pastes a link and the app writes out the video's script. The user taps the line where the clip starts and the line where it ends, then picks a size and caption. The export is an MP4 with the Status Studio name and logo.

- **On the phone:** translation (ML Kit) and rendering (Media3 Transformer). No accounts, no servers, no analytics.
- **Groq writes scripts:** a video with no YouTube captions is written out by Groq's hosted Whisper, with the user's own free API key (FR-12a). Script audio leaves the phone only then, and only to Groq. The same key also powers Fix with Groq (FR-19), which sends the picked lines, the title and the link when the user taps it. The app ships no key and has no server of its own. On-device Whisper was dropped (M10): on a Redmi Note 11 it ran at 0.2× real time.
- **Saves data:** it downloads the script's audio at low quality (nothing when YouTube has captions), and only the clip's part of the video, once the user has picked it.
- **Saves work:** scripts are saved, so the same video opens straight to its script next time.

## 2. Screens

| # | Screen | Route | Job |
|---|---|---|---|
| 1 | Home | `/` | Start a reel; recent reels and saved scripts; open Settings |
| 2 | Source | `/source` | Paste a YouTube link; choose language (default automatic) |
| 3 | Processing | `/processing` | Download audio → detect language → transcribe → line up timestamps (skipped for a saved script, FR-14) |
| 4 | Script | `/script` | Full script; tap the start line, then the end line |
| 5 | Fine-tune · Video | `/fine-tune` | Step 1 of Fine-tune (M19): download only the clip (FR-15); play, pause, seek; nudge start and end by ±0.5 s; size, fill and crop, with a crop that can move during the clip (FR-22) |
| 5b | Fine-tune · Lyrics | `/fine-tune/lyrics` | Step 2 of Fine-tune (M19): only the clip's lines; edit them and set when each one shows; the video plays with the lyrics on it (FR-21) |
| 6 | Style | `/style` | Caption text/variant/position/size; live preview with branding. Size and crop moved to Fine-tune · Video in M19 |
| 7 | Export | `/export` | Render with progress; Cancel returns to Style |
| 8 | Done | `/done` | Final preview; Save to gallery; Share; Make another |
| 9 | Settings | `/settings` | Groq key with step-by-step help (FR-12a); YouTube reader; background work |

- **Visual reference:** the design canvas prototype for screens 1–8. Settings follows the same visual language.
- **Progress on Processing:** each download and transcription step has its own bar with the percent beside it (`45 %`). Under the bar it shows amount done of total and speed (`220 of 487 MB · 3.2 MB/s`), with time left on the right (`1:24 left`).

## 3. Functional requirements

**FR-1 Link input.**
- **Accepted links:** `youtube.com/watch?v=ID`, `m.youtube.com/watch?v=ID`, `youtu.be/ID`, `youtube.com/shorts/ID` and `youtube.com/live/ID`. They may come with or without `https://`, extra query parameters (such as `si=`) or surrounding whitespace.
- **Video ID:** 11 characters of `[A-Za-z0-9_-]`.
- **Anything else:** "That doesn't look like a YouTube link."
- **A valid link** shows the title, channel and duration.

**FR-2 Language.** Dropdown: Detect automatically (default), Urdu, Arabic, Punjabi, Persian, Hindi, Bengali, English. Script has the same dropdown; changing it re-runs the script in that language, reusing the downloaded audio.

**FR-3 Script.** The first source that applies:
1. **Saved script** for this video and language (FR-14): open Script directly.
2. **YouTube captions** in the chosen language, manual tracks over auto-generated. Each caption becomes one line, and no audio is downloaded.
   - **Automatic language:** only manual tracks count, in any language. YouTube guesses an auto-generated track's language from the audio, and a wrong guess makes the script junk: an Urdu naat's only track was auto-generated Romanian.
   - **Which auto track:** only yt-dlp's `<lang>-orig` track is what YouTube heard; the other auto tracks are machine translations and are never used.
   - **Cleaning:** music symbols and sound tags (`♪`, `[♪♪♪]`, `[Music]`) are dropped.
3. **Speech to text** on the **lowest-bitrate MP4 audio stream**, by Groq with the user's key (FR-12a). Each segment becomes one line. Without a key the run stops with the §8 message before any audio is downloaded.
   - **Pieces:** the audio is cut into **90-second pieces**, so lines appear while the rest is still being written. Each piece's times are offset by its start.
   - **Dropped segments:** silence, music and bracketed tokens (`[BLANK_AUDIO]`, `(music)`, `♪`) never become lines.
   - **Groq** (`whisper-large-v3-turbo`):
     - **Pieces:** stream-copied `.m4a` pieces, without WAV, about 0.5 MB each. Stream copy cuts at audio frame boundaries, so each offset is the piece's real start from FFmpeg's segment list.
     - **Request:** one multipart `POST https://api.groq.com/openai/v1/audio/transcriptions` per piece, in order, with `Authorization: Bearer <key>`. Fields: `file`, `model`, `response_format=verbose_json`, `timestamp_granularities[]=segment`, `temperature=0`, and `language=<whisperCode>` unless automatic.
     - **Lines:** segments with empty text are dropped. `no_speech_prob` is 0 on turbo (§10 Q5), so a piece whose segments are all known invented phrases ("Thank you.", "Thanks for watching.", "you", "bye") gives no lines; the same phrase beside real speech is kept.
     - **HTTP 429:** wait `retry-after` and resend when it's 60 s or less, showing "Waiting for Groq · 0:42 left"; otherwise the §8 error.
     - **HTTP 5xx or 498:** resend once after 2 s, then the §8 error.
     - **Cancel** stops before the next piece.
- **Automatic language** is inferred from the transcript text (§6.4) and shown, e.g. "Urdu (detected)".
- **No speech found** gives the §8 error.

**FR-4 Line selection.**
- The first tap sets the start line.
- A tap on the same or a later line sets the end line.
- A tap on an earlier line, or any tap once both are set, starts over with that line as the start.
- Lines between start and end are highlighted.
- "Next" is enabled only when both are set.

**FR-5 Fine-tune (two steps since M19).** Both steps keep their own player over the same downloaded clip (FR-15); Next on step 1 opens step 2, and Back returns.
- **Step 1, Video** (`/fine-tune`, "Step 3 of 5"):
  - **Opening:** downloads the clip (FR-15); the player shows download progress until it's ready.
  - **Player:** pinned above the scrolling rest; play, pause, and a seek bar over the whole downloaded window with the clip range marked. It does not stop at the clip end. "Play clip" seeks to the clip start and plays.
  - **Range:** the clip runs from the start line's start to the end line's end.
  - **Nudges:** buttons move start or end by 0.5 s. A nudge is ignored when it would make the clip shorter than **3 s** or move it outside the video. A clip that starts out invalid (from transcript times) still accepts nudges towards a valid range; only nudges that make a rule worse are ignored.
  - **Waveform:** 60 bars over the downloaded window, with the clip highlighted.
  - **Long-clip warning:** above 60.0 s, "Longer than 60 s. WhatsApp Status may cut it." It never blocks.
  - **Frame:** size, fill, keep in view and free crop (FR-6), and a crop that moves (FR-22). The crop window is drawn over the player.
- **Step 2, Lyrics** (`/fine-tune/lyrics`, "Step 4 of 5"): FR-21.

**FR-6 Frame (on Fine-tune · Video since M19).**

| Preset | Output size |
|---|---|
| 9:16 (default) | 1080 × 1920 |
| 4:5 | 1080 × 1350 |
| 1:1 | 1080 × 1080 |
| 16:9 | 1920 × 1080 (original framing, no crop) |
| Free | the crop rectangle in source pixels, scaled so the long side ≤ 1920, both sides rounded down to even numbers |

- **Fill:** presets other than 16:9 offer Crop to fill (default) or Blur background. Crop to fill offers Keep in view: Left / Center (default) / Right.
- **Free crop:**
  - Drag to move, and drag the corner to resize.
  - Each side is at least 12 % of the source, and the rectangle never leaves the frame.
  - Reset returns to left 30 %, top 4 %, width 40 %, height 92 %.

**FR-7 Caption.**
- **Default text:** the selected lines' text, one per line.
- **Variants:**
  - **Original.**
  - **Roman:** only when the transcript is Urdu (§6.6).
  - **English:** ML Kit on the device; hidden when ML Kit doesn't support the source language (e.g. Punjabi).
- **Editing:** the text is editable, and switching variant replaces edits with that variant's text.
- **Position and size:** Top or Bottom (default). Size S, M (default) or L is a font size of 4.5 %, 5.5 % or 6.8 % of output width.
- **Font:** by script (§6.5), with line height 2.1 for Nastaliq and 1.3 otherwise.
- **Block:** centred, black at 38 % behind the text, padding 2 % of output width, margin 6 % of output height from the edge.
- **Overflow:** if the block would pass 35 % of output height, the font shrinks in 5 % steps down to 60 % of the chosen size, then the text is clipped with an ellipsis.

**FR-7a Caption lines, one at a time (M11).** The exported reel shows one caption line at a time, never the whole caption at once.
- **Lines:** each non-blank line of the caption text is one cue.
- **Timing:** while the caption has one line per picked script line, each cue shows from its script line's start to its end, counted from the clip start and clamped to the clip (so a nudge moves them with the clip). A cue left with no time inside the clip is dropped.
- **Edited text:** adding or removing lines loses the pairing, so the clip is shared out in proportion to each line's length. Translation and Roman variants follow the same rule.
- **Between lines:** only the branding shows.
- **Look:** each line is laid out as in FR-7 on its own, so the font fits each line, not the longest.
- **Render:** Dart paints the branding on its own plus one transparent PNG per cue at output size. Kotlin lays the branding over the clip and swaps in the cue's PNG while it is due, opening each PNG only when its line is due. The PNGs stay until the render ends (cancel, error or done), then are deleted.
- **Style preview:** a still of the clip's first frame, so it shows the first line.

**FR-8 Branding (always on).**
- **Pill:** the Trim logo and "Status Studio" in Inter SemiBold.
- **Sizes:** logo height 4.5 % of output width, and text at 55 % of the logo height.
- **Look:** black at 45 %, inset 4 % of output width from the left edge and from the top or bottom edge.
- **Placement:** at the top when the caption is at the bottom, and at the bottom otherwise.

**FR-9 Export.**
- **File name:** `<kalam>-<start>-<end>.mp4`, e.g. `Arsh_e-علم_بڑی-وقت_کی.mp4`.
  - **kalam:** the first 2 words of the video title, cleaned the same way (brackets, "Official Video"-style words and anything after a `|` removed).
  - **start / end:** the first 2 words of the caption's first line and of its last line. A one-line caption uses it for both.
  - **Words:** letters, marks and digits only, so punctuation and characters illegal in file names are dropped; joined by `_`. A part with no words is left out; with none at all the name is `reel`.
  - **Same name again:** `-2`, `-3`, … is added, so a new reel never replaces an earlier one. The name is also the reel's id in Recent, and what Save to gallery and Share show.
- **Output:** MP4 with H.264 video (`video/avc`) and AAC audio (`audio/mp4a-latm`), at the source frame rate, rendered by Media3 Transformer (§5).
- **Progress:** Media3's own progress.
- **Cancel:** stops the render, deletes the partial file and returns to Style.
- **Failure:** a native render error shows "Couldn't make the reel." It never hangs.

**FR-10 Save and share.** Done plays the exported file, not a still: tap to play or pause, with a progress bar that can be dragged, and back to the start at the end. The thumbnail shows until the file opens and stays if it won't play; Save and Share work either way. Save to gallery (`gal`). Android 10+ needs no permission. Android 7–9 asks once; a refusal explains and offers "Open settings". Share opens the system share sheet with the MP4 (`share_plus`).

**FR-11 Recent.**
- **Reels:** newest first, at most 50; the oldest is dropped and its MP4 and thumbnail deleted.
  - A row shows a thumbnail, the first caption line, duration and date.
  - Tap opens Done. Long-press offers Delete.
  - A reel whose file was deleted outside the app is skipped.
- **Saved scripts:** every saved script (FR-14) has a row as soon as the video is processed, before any lines are picked.
  - Reels and scripts share one list, newest first. Empty, it reads "Your reels and scripts will appear here."
  - A script row shows a script icon, the title and `Script · <language> · <video length> · <d MMM>`, where an automatic script names its detected language ("Urdu (detected)").
  - Tap opens Script without Processing or downloads.
  - Long-press offers Delete, which removes that script and any unfinished progress for it.
  - There is one row per video and requested language. Scripts saved before video details were kept appear once their link is opened again.

**FR-12 Settings: speech models (retired in M10, 2026-11-04).** On-device Whisper and its model downloads were removed; the number stays so code and history keep their references. The Settings screen now starts with FR-12a.

**FR-12a Settings: script writing (Groq).** The first section of Settings. Scripts for videos without captions need a saved key.
- **Key field:** "Groq API key", masked, with Paste, Show, Save and Remove (Remove appears while a key is saved). Save is off while the field is empty.
  - Save checks the key with `GET https://api.groq.com/openai/v1/models`, which is free and sends no audio, and stores it only if Groq accepts it. A wrong key never replaces a good one.
  - The field then reads "Key works", "Groq didn't accept this key." or, offline, "You're offline. Connect and try again."
- **Help (ⓘ):** beside the label, it opens "How to get a free Groq key", written for non-technical users:
  1. Tap **Copy link**, then open your browser and paste it: `console.groq.com/keys`.
  2. Sign in with Google or your email. The free plan needs no card.
  3. Tap **Create API Key**. Give it any name, like "Status Studio", and tap **Submit**.
  4. Tap **Copy** next to the new key. It starts with `gsk_`. Groq shows it only once, so copy it now.
  5. Come back here, tap **Paste**, then **Save**.

  Below the steps: "Free plan: about 2 hours of audio every hour, and 8 hours a day." and "Keep the key private, like a password. You can delete it any time on the same Groq page." The sheet has Copy link and Done buttons. Copy link puts the link on the clipboard and shows "Link copied"; the app doesn't open a browser itself.
- **Privacy note** under the heading: "Writes the script when a video has no captions. Your video's audio is sent to Groq, which uses about as much data again as downloading it. Tapping Fix with Groq on the Script screen also sends the lines you picked, the title and the link. Groq's terms apply." (FR-19) There is no switch: a saved key turns Groq on and Remove turns it off.
- **Key storage:** `flutter_secure_storage` (Android Keystore). The key is never logged, and never written into saved files, notifications or error text. It goes only to `api.groq.com`.
- **No key:** a script without captions stops with "Writing a script needs a free Groq key." (§8), with Settings and Back, before any audio is downloaded. Captions and saved scripts need no key.

**FR-17 Real lyrics (M12; removed in M17).** Script had a "Real lyrics" button that replaced the script with time-synced lyrics from lrclib.net. M17 removed the button and the whole lyrics feature (`lib/src/features/lyrics`) to keep only Fix with Groq (FR-19). Git history before M17 has the design. Scripts already saved with source `lrclib` still reopen like any saved script.

**FR-18 Fix the script with an AI agent (M13; both buttons removed from Script in M17).** What is left is the prompt and reply parsing that FR-19 uses; nothing copies to or pastes from the clipboard any more. The rest of this section is the design they share.** For text the lyrics service lacks (a naat with verses from another poem), the user takes the script to any AI chat that can search the web and brings the corrected text back. Two buttons on Script, next to "Real lyrics", both off while a script is still being written.
- **Copy for AI:** copies one block to the clipboard: a ready prompt (video title, `https://youtu.be/<id>`, rules) followed by the lines as `<number> | <mm:ss.xx> | <mm:ss.xx> | <text>`. Row numbers are the line's index in the whole script + 1. The user pastes it into the chat unchanged. Snackbar: "Copied <n> lines. Paste them into ChatGPT (or any AI that can search the web), copy its reply, then tap Paste AI reply."
  - **Which lines:** the picked clip's lines when a range is picked; otherwise the whole script if it has at most **60** lines. More than 60 lines, picked or not, gives the §8 message instead. Why: a chat refuses or skims a long script (a 225-row script made ChatGPT ask for it in sections, and no rows came back), and only the clip's lines matter.
- **The prompt asks the agent to:** search for the real lyrics and never invent words; keep numbers and times and change only the text; correct rows that belong to a different poem from that poem; keep the script (no Roman, no translation); mark rows with no source by ` [?]`; never ask for fewer rows or for sections; never move a line from another part of the poem into a row (M15); reply with the rows in one code block, then list changed rows with source links.
- **Paste AI reply:** reads the clipboard and takes every row that matches the format, from anywhere in the reply (code fences, links and chatter are ignored). Citation marks such as `【1†L10-L12】` are removed from the text (M15). FR-19 does the same through Groq, with no copying.
  - **Matched by row number, text only.** Times always stay as they were, so an agent that changes a time can't move a line. Rows missing from the reply, empty, or with unknown numbers keep their text or are ignored.
  - **`[?]`:** the mark is removed from the text; the snackbar names those lines: "Updated 12 lines. The AI found no source for line 3, 7: read it before you use it."
  - **No rows found:** the §8 message, and the script is unchanged.
- **After:** the lines keep the picked range and clip; the caption is refilled from the corrected lines. The script is saved as the newest script (source `edited`, FR-14), so the video reopens corrected.
- **Privacy:** nothing is sent by the app. The user chooses what to paste into which chat.

**FR-19 Fix the script with Groq (M15; the §10 spike #6 said go).** The one fixing button on Script (since M17), **Fix with Groq**, does what Copy for AI plus Paste AI reply did, with the key from FR-12a and no clipboard. It sits alone on the row above the lines. Real lyrics, Copy for AI and Paste AI reply were removed in M17.
- **Same rules as FR-18:** the same prompt and the same lines (the picked clip's, or the whole script up to the row cap), the same reply handling (matched by row number, text only, times unchanged, `[?]` marks named in the snackbar) and the same result (the lines keep the range and clip, the caption is refilled, the script is saved as the newest script with source `edited`).
- **Model and row cap:** `openai/gpt-oss-120b` with Groq's `browser_search` tool. At most **30** lines (the picked clip's, or the whole script); more gives the same §8 message. Why 30: at 54 rows the model moved lines of the poem into the wrong rows (§10 #6).
- **While it runs:** the button shows progress and a Cancel. Cancel stops waiting: the reply is ignored and nothing is saved (a request already sent still counts against the plan).
- **No key:** the button is shown, and tapping it gives the §8 "needs a free Groq key" message with Settings.
- **Privacy:** the picked lines, the video title and its link go to Groq, only when the user taps this button. Say so in the FR-12a help text: the key is also used for this.
- **Limits:** a call counts against the same free plan as writing scripts. A 429 is handled as in FR-12a.

**FR-13 Offline.** Saved scripts, translation (once its ML Kit pack is downloaded) and export work without a network. Writing a new script needs one (Groq).

**FR-14 Saved scripts.**
- **Key:** video ID, requested language (`auto` or a code) and source: `captions` or `groq-whisper-large-v3-turbo`. Scripts and progress saved by earlier versions under `whisper-<model>` are deleted when the app starts (M10). The entry holds the transcript (with the inferred language), the source and the save date.
- **Files:** `transcripts/<videoId>/<requested>-<source>.json` in the app support directory. The video's folder also keeps `video.json` (title, channel, length) for Recent.
- **Same link again:** skips Processing and downloads. Script shows "Using the saved script from <d MMM> · Write it again".
- **Write it again:** runs speech to text with Groq and replaces the saved script.
- **Resume:** progress is saved after each 90-second piece in `<requested>-<source>.partial.json` and deleted when the run completes. An interrupted run resumes from the next piece.
- **Retention:** 90 days after last use, at most 200 videos, least recently used dropped first.

**FR-15 Clip-only download.**
- **When:** nothing of the video is downloaded before Fine-tune.
- **Window:** from clip start − 5 s to max(clip end + 5 s, clip start + 30 s), clamped to the video.
- **What:** ≤ 720p MP4 video plus the highest-bitrate MP4 audio. With no MP4 at or below 720p, take the lowest above 720p, else WebM.
- **How:**
  - Read each stream's MP4 segment index (`sidx`) and fetch just those segments with HTTP range requests.
  - The index fetch starts at 64 KiB and doubles up to 2 MiB; beyond that the stream counts as having no index.
  - A `200` reply to a range request is never written as the clip.
- **Clip file:** video and audio are muxed by stream copy. Its time zero is `offset` in the video; times shown to the user stay in video time.
- **Reuse:** a window is reused while the clip still fits inside it. A nudge past it downloads a new window.
- **Fallback:** a stream that isn't MP4, or has no index, is downloaded whole.
- **Expired links:** an HTTP 403 refreshes the stream URLs and retries once, then gives a typed error.

**FR-16 Background work.** Writing a script and exporting keep running when the user leaves the app or locks the phone.
- **How:** while either runs, a foreground service (type `dataSync`, from `flutter_foreground_task`) holds a partial wake lock and a Wi-Fi lock, and shows an ongoing notification. Doze and battery saving leave such a service running, network included. The work stays in the app; the service only keeps the process alive.
- **Ongoing notification:**
  - It appears from the moment work starts, so the user can leave at once.
  - It starts as "Getting the script" or "Rendering your reel" at 0 %, then shows the running step as the title and `45 % · <video title>` as the text.
  - Script steps: "Downloading audio", "Detecting the language", "Writing the script", "Waiting for Groq", "Lining up timestamps". Export step: "Rendering your reel".
  - With both running, it shows the one that started last. The service stops when the last job ends.
- **Result notification:** posted only when the app isn't on screen; tapping it opens the app where the work left off. Cancel posts nothing.
  - Script done: "Script ready" · video title. Failed: "Script stopped" · the §8 message.
  - Export done: "Reel ready" · "Tap to save or share it." Failed: "Export stopped" · the §8 message.
- **Asking once:** the first time work starts, the app asks for notifications (Android 13+), then for exemption from battery optimisation. It never asks again on its own.
- **Settings, "Background work":**
  - Two rows: notifications on, and battery optimisation off. Each shows "Allow" when it isn't so; a refused notification permission opens App info instead.
  - A hint: "On Xiaomi and some other phones, also set Battery saver to No restrictions in App info." with "Open App info".
- **Lifetime:** the service survives Home and lock, and stops when the task is swiped away (manifest `android:stopWithTask`), because the work's Flutter engine ends with the task. The plugin's own `stopWithTask` option isn't used: it stops whenever the app leaves the screen.
- **Limits:** Android 15+ gives `dataSync` 6 hours a day. After that the service stops, and work continues only while the app is open.

**FR-20 Launch animation (M16).** Opening the app never shows a white screen.
- **Native splash:** Android's launch window is the app background `#0E1311` with the §7 logo (light variant) centred at 144 dp. Android 12+ shows the same logo through its splash API (`windowSplashScreenAnimatedIcon`, a 288 dp icon with the 144 dp logo in the middle). iOS's launch screen has the same background.
- **Animation:** Flutter's first frame matches the native splash exactly, then plays for 1.7 s over Home, which is already built underneath:
  - the five bars move like a voice waveform and settle back;
  - the brackets close in on the bars and open again, like trimming a clip;
  - "Status Studio" fades in under the logo;
  - the splash fades out while the logo grows slightly.
- **No overlap:** bars never reach the bracket arms and brackets never touch the bars.
- **Reduce motion:** when the system asks for no animations, Home shows straight away.
- **Taps:** taps don't reach Home while the splash covers it.

**FR-21 Fine-tune lyrics (M18; its own step since M19).** Step 2 of Fine-tune lists the clip's lines, editable, with the video playing with the lyrics on it.
- **Lines:** only the picked clip's lines are listed. Lines around the clip are not shown. Every listed line reacts to a tap.
- **Player:** the reel as it will look: the video cut to the output frame (FR-6) with the crop where FR-22 puts it at that moment, and the line due on it, laid out as FR-7 says (caption position and size). Play and pause, and a seek bar over the clip.
- **Tap a line:**
  - **While paused:** seeks to the line's start.
  - **While playing (tap to time):** the line's start becomes the playhead. The line that was highlighted at that moment ends there, so the new highlight replaces it. The tapped line keeps its length (at least 1 s), cut at the next line's start.
  - **Ignored:** a tap earlier than the previous line's start, or on a line earlier than the one playing, so lines stay in time order.
- **Highlight:** the line whose start ≤ playhead < end is highlighted, only while it lasts; between lines nothing is, and the video shows no lyrics.
- **Edit:** a pencil opens a text field with the line's text. Saving an empty text keeps the old one. A line break becomes a space, so a line stays one caption line.
- **Reorder:** a drag handle moves a line's text to another place. Times stay where they are, so lines stay in time order: reordering swaps which text sits at which time.
- **Add:** "Add line" asks for text and inserts a line at the playhead, 2 s long (cut at the next line's start; the line it lands in ends there). When a line starts exactly at the playhead (right after tapping it while paused), that line's time is shared: the new line takes the first half, at most 2 s. The playhead must be inside the clip; Add line is off outside it.
- **Delete:** removes a line. The last line can't be deleted.
- **After an edit:** the clip's edges follow the first and last lines only when that line's time changes (or an add or delete makes another line first or last); a nudge on the other edge is kept. The caption is refilled from the lines (as FR-18 does), and the script is saved as the newest script (source `edited`, FR-14) after 1 s without edits and when the screen closes.
- **Script still being written:** once any line is edited, lines that arrive later are not added to this reel (the edited lines win).

**FR-22 Moving crop (M19).** Where the crop window sits can change while the clip plays, for Crop to fill and Free crop. Blur background and 16:9 keep the whole frame, so nothing moves.
- **What moves:** the window's position only. Its size is fixed for the clip: the preset's largest rectangle, or the free crop's width and height. It moves only along an axis where it has room (a 9:16 window in a 16:9 frame moves left and right; a 4:5 window in a 9:16 video moves up and down). With room on neither axis, the switch is hidden.
- **Anchor:** a position is an anchor `(x, y)`, each from 0 to 1 across the room the window has to move (0 = left or top, 1 = right or bottom). The frame keeps a base anchor (default 0.5, 0.5). Keep in view's Left, Center and Right set its x to 0, 0.5 and 1. A free crop's anchor is `left / (1 − width)` and `top / (1 − height)`, and its base is `freeCrop.left` and `top` themselves.
- **Keyframes:** a keyframe is a time in video time, an anchor and how it is reached: **Glide** or **Cut**.
  - **Glide:** the anchor moves in a straight line from the previous keyframe's anchor to this one, arriving at this keyframe's time.
  - **Cut:** the anchor holds the previous keyframe's value until this keyframe's time, then jumps. At exactly that time it has jumped (Dart and Kotlin agree).
  - Before the first keyframe the anchor is the first keyframe's; after the last it holds. The first keyframe's way of arriving has no effect, so its Glide and Cut choice is hidden.
  - Keyframes are kept in video time, so nudging the clip does not move them. A new keyframe's time is inside the clip; it snaps to 0.1 s, and one within 0.25 s of another replaces it.
  - A keyframe outside the clip (after a nudge or a line edit) has no effect on the reel except as the position the crop starts from or holds. Its chip is dimmed, and it can still be deleted.
- **Off by default:** "Move the crop during the clip" is a switch on step 1. Off, the crop is as FR-6 says. Turning it on creates a first keyframe at the clip start from the current crop. Turning it off removes the keyframes and keeps the crop where it was at the clip start: Crop to fill stores it as the base anchor, Free crop writes it into its rectangle.
- **Editing (on):**
  - **Drag:** dragging the crop window over the player moves it with the finger and writes one keyframe, at the playhead where the drag started, when the finger lifts: it replaces the one there or adds one that glides in. Keep in view is hidden while the switch is on.
  - **Chips:** a row under the player, in the pinned part, shows each keyframe's time. Tap one to jump to it. The selected keyframe offers Glide or Cut (not on the first) and Delete. Any keyframe can be deleted except the only one left.
  - **Touch:** the window can be dragged from anywhere inside it, and from a margin around its outline.
- **Changing the size or fill:** keyframes stay but have no effect while Blur or 16:9 is chosen, and come back when a crop is chosen again. Changing the free crop's size keeps them.
- **Rounding:** each keyframe's pixel rectangle is rounded as §6.3 says. The preview moves in whole pixels; the render moves in fractions of one.
- **Render:** the keyframes go to Kotlin as rectangles (§6.3.1) with their times counted from the clip start; the crop between them is computed per frame (§6.3.2). A reel with the switch off renders exactly as before.
- **Previews:**
  - Both Fine-tune steps follow the playhead frame by frame while playing (the player reports its position every 100 ms or so, so a ticker adds the time since the last report).
  - Fine-tune · Lyrics shows the moving crop and the lyric line due (FR-21), by extending `reel_preview.dart`. Style shows the crop at the clip start.
- **One decoder at a time:** when Lyrics opens, the Video step's player is released, and it is made again when Lyrics closes.

## 4. Non-functional requirements

- **Platforms:** Android first (minSdk 24, sideloaded APK). iOS later (deployment target 15.5, needed by ML Kit translation).
- **Responsiveness:** transcription, FFmpeg, waveform peaks and file I/O never block the UI isolate. Every long step shows progress and can be cancelled.
- **Storage:**
  - Media cache: `sources/<videoId>/` in the temp directory, holding script audio, WAV pieces and clip windows. It's reused, and deleted on app start after 7 days.
  - Saved scripts: `transcripts/` in app support (FR-14).
  - Exports: `reels/` in app documents.
  - Downloads go to `.part` files and are renamed when complete. Whole streams download in 10 MB ranges.
- **Data caps:** script audio is the lowest-bitrate MP4 audio. The clip is ≤ 720p H.264 plus the highest-bitrate MP4 audio, for the clip window only.
- **Privacy:** nothing leaves the device except YouTube, language-pack downloads and, when a video has no captions (FR-12a), script audio pieces sent to Groq with the user's key, and, when the user taps Fix with Groq (FR-19), the picked lines, the video title and its link.

## 5. Architecture

- **Folders:** feature-first, `lib/src/features/<feature>/{domain,data,application,presentation}`, with a layer only when it has code.
- **State:** Riverpod 3 (`Notifier`/`NotifierProvider`). The reel in progress is one immutable `ReelDraft` in `reelDraftProvider`. Changing the transcript clears the selection and clip.
- **Services:** small interfaces exposed as providers, so fakes can replace them in tests: `VideoSource`, `Transcriber`, `CaptionTranslator`, `Renderer`, `RecentReelsRepository`, `BackgroundWorkPlatform`.
- **Speech to text:** `GroqTranscriber` (FR-12a) sends the pieces one by one and emits per-piece progress and lines.
- **Navigation:** `go_router`, with route paths in `AppRoutes`.
- **Rendering (Android):** Media3 Transformer behind the Kotlin channels `status_studio/render` (`start`, `cancel`) and `status_studio/render/events`.
  - Input: the clip file plus one transparent PNG, exactly the output size, holding caption and branding drawn by Flutter. It is applied last.
  - Media3 trims, crops or blurs, scales, overlays and encodes on the phone's hardware.
  - Preview and export share `cropRectFor` and `layoutOverlay`.
  - iOS will need AVFoundation later.
- **FFmpeg:** only WAV conversion, splitting, stream-copy muxing and thumbnails. The bundled build can't encode H.264 or read https (§10 Q1).

### Package map

| Need | Package | Notes |
|---|---|---|
| YouTube metadata, stream URLs, captions | yt-dlp via `youtubedl-android` 0.18.1 (Gradle) | Channel `status_studio/ytdlp`: `quickVideoInfo` (`-J --no-js-runtimes`), `videoInfo` (`-J` with QuickJS), `update`, `version`. Bundles Python, yt-dlp and QuickJS (§10 Q4) |
| Speech to text (cloud) | `dart:io` `HttpClient` | Hand-built multipart to `api.groq.com`; `GET /openai/v1/models` checks a key |
| Secret storage | `flutter_secure_storage` | The Groq key only |
| FFmpeg | `ffmpeg_kit_flutter_new_min` ^2.x | The only FFmpeg (LGPL); no mediacodec, no TLS, no libx264 |
| Final render (Android) | Media3 `transformer`, `effect`, `common` 1.11.1 | `Transformer`, `ClippingConfiguration`, `Crop`, `Presentation`, `GaussianBlurWithFrameOverlaid`, `OverlayEffect` + `BitmapOverlay` |
| Downloads | `dart:io` `HttpClient` | Range requests for clip windows and whole streams; captions as `json3` |
| Translation | `google_mlkit_translation` | `OnDeviceTranslator`, `OnDeviceTranslatorModelManager` |
| Preview / gallery / share | `video_player` / `gal` / `share_plus` | |
| Key-value storage | `shared_preferences` | `recentReels` (JSON) |
| Background work | `flutter_foreground_task`, `flutter_local_notifications` | No TaskHandler: the work stays in the app's isolate. Notifications need core library desugaring |

### Engineering rules

- **No code generation:** `copyWith`, `==` and `hashCode` are written by hand.
- **Copy:** literal from this document and the canvas. The app is general-purpose: never name a content type (naat, bayan…) in UI or code.
- **Import boundaries:**
  - Only `YouTubeVideoSource` reaches yt-dlp.
  - Only `lib/src/core/ffmpeg/` imports FFmpeg Kit.
  - Only the Kotlin `render/` package imports Media3.
  - The background plugins are reached only through `BackgroundWorkPlatform`.
- **Errors are typed:** `VideoUnavailableException`, `OfflineException`, `InsufficientStorageException`, `NoGroqKeyException`, `NoSpeechFoundException`, and so on. Screens map them to §8. A failing background-platform call is reported with `FlutterError.reportError` and never stops the work.
- **yt-dlp:**
  - It updates itself at most weekly (about 3 MB), and once more after a failed read.
  - A failed read ends in a §8 message after one update and retry.
  - HLS formats are skipped. Live streams and videos without a length are unavailable.
- **New dependencies:** maintained and widely downloaded on pub.dev. Add them with `fvm flutter pub add`.
- **Tests never touch the network or platform:**
  - Fake `YtDlp`, Groq and FFmpeg.
  - Downloads run against a loopback `HttpServer`.
  - Override `backgroundWorkPlatformProvider` with `FakeBackgroundWorkPlatform`.

## 6. Domain model and rules

### 6.1 Types (Dart)

```dart
class SourceVideo { String videoId; String title; String channel; Duration duration; }
enum ScriptLanguage { auto, urdu, arabic, punjabi, persian, hindi, bengali, english } // whisperCode ('auto','ur',…) and label
class TranscriptLine { int index; String text; Duration start; Duration end; }
class Transcript { String languageCode; List<TranscriptLine> lines; }
sealed class LineSelection { NoSelection, StartSelected(int start), RangeSelected(int start, int end) }
class ClipRange { Duration start; Duration end; }
enum AspectPreset { story9x16, portrait4x5, square1x1, landscape16x9, free }
enum FillMode { crop, blur }  enum CropFocus { left, center, right }
class FreeCropRect { double left, top, width, height; } // fractions of the source frame
class FrameSettings { AspectPreset preset; FillMode fill; CropAnchor anchor; FreeCropRect freeCrop; CropPath cropPath; } // anchor replaces CropFocus (M19); Left/Center/Right set anchor.x
class CropAnchor { double x, y; }                                    // 0..1 across the window's room to move (FR-22)
enum CropArrival { glide, cut }
class CropKeyframe { Duration time; CropAnchor anchor; CropArrival arrival; } // video time
class CropPath { List<CropKeyframe> keyframes; }                      // empty = a fixed crop
class OutputSize { int width; int height; }
enum CaptionVariant { original, roman, english }  enum CaptionPosition { top, bottom }  enum CaptionSize { small, medium, large }
class CaptionSettings { CaptionVariant variant; String text; CaptionPosition position; CaptionSize size; }
class ReelDraft { SourceVideo? video; ScriptLanguage language; Transcript? transcript; LineSelection selection; ClipRange? clip; FrameSettings frame; CaptionSettings caption; }
class RecentReel { String id; String title; String videoPath; String thumbnailPath; Duration duration; OutputSize size; DateTime createdAt; } // title: first caption line
class SavedTranscript { Transcript transcript; String source; DateTime savedAt; } // captions | groq-whisper-large-v3-turbo 
class SavedScript { SourceVideo video; ScriptLanguage language; SavedTranscript saved; } // a Recent row
enum SpeechEngine { onDevice, groq }
class CloudTranscriptionSettings { bool enabled; bool keyChecked; } // the key itself lives only in secure storage
class ClipWindow { Duration start; Duration end; }                  // FR-15, video time
class ClipSource { File file; Duration offset; ClipWindow window; } // offset = video time of the file's zero
```

All are immutable, with `copyWith` and value equality.

### 6.2 Time formats

| What | Format | Example |
|---|---|---|
| Clip times | `m:ss.t` | `1:23.0` |
| Line timestamps | `m:ss` | `1:23` |
| Durations | seconds | `18.5 s` |
| Long videos | `h:mm:ss` | `1:02:15` |

### 6.3 Crop maths

The target aspect is `aw:ah` and the source is `sw × sh`. Crop sizes are even integers rounded down, and offsets are whole pixels rounded down. Free crop is computed in the source's own pixels, whatever its size or orientation.
- **Crop to fill:** take the largest `aw:ah` rectangle in the source, vertically centred. Its left edge is 0 (left), (sw − cw)/2 (center) or sw − cw (right). Then scale to the output size.
- **Blur background:** the source scaled to cover the output with `boxblur=20:2`, under the source scaled to the output width and vertically centred.

### 6.3.1 Crop for Media3

`Crop` takes normalised device coordinates: left = 2x/sw − 1, right = 2(x+w)/sw − 1, top = 1 − 2y/sh, bottom = 1 − 2(y+h)/sh. It is followed by `Presentation.createForWidthAndHeight(outW, outH, LAYOUT_SCALE_TO_FIT)`.
- **Blur:**
  - `GaussianBlurWithFrameOverlaid` (σ ≈ 20), then `Presentation`.
  - The effect draws the whole input frame sharp, scaled to fit the output width (or its height for a taller source), over a blurred copy stretched to the output's shape. That blur is stretched, not covering.
  - It can't follow a covering `Presentation`.
  - If it looks wrong on a phone, switch to a two-sequence `Composition` (device check pending, §14).
- **16:9:** `Presentation` only.

### 6.3.2 Moving crop for Media3 (M19)

With keyframes, `Crop` is replaced by a `MatrixTransformation` whose matrix is computed for each frame from the keyframes. The time is the frame's presentation time counted from the clip start, from one helper (`clipTimeMs`) that the caption overlay uses too, so the crop and the caption lines can't drift apart.
- **Rectangle at a time:** a pure function `ndcRectAt(keyframes, timeMs)` (unit-tested without Android): before the first keyframe the first rectangle; after the last the last; between two a Glide interpolates each edge linearly and a Cut holds the earlier until the later's time, and from that time on is the later. This is the same rule as `CropPath.anchorAt` in Dart.
- **Matrix:** the rectangle in NDC (§6.3.1) scaled to fill the frame (`scale = 2/(right−left)`, `2/(top−bottom)`, translated by `−(right+left)/(right−left)`, `−(top+bottom)/(top−bottom)`), built as a plain 4 × 4 array (no `android.graphics.Matrix`, which unit tests can't use).
- **Size:** `configure` returns the window's pixel size, as `Crop` does, so the `Presentation.createForWidthAndHeight(outW, outH, LAYOUT_STRETCH_TO_FIT)` after it is the same near-1:1 step as the fixed crop's.
- **Unchanged:** the overlay still comes last, and Blur and 16:9 never send keyframes. Device check pending (§14).

### 6.4 Language inference (automatic)

From the transcript text, first match wins:

| Text contains | Language |
|---|---|
| Arabic script with any of `ٹ ڈ ڑ ں ے ھ ہ` | Urdu |
| Arabic script with any of `پ چ ژ گ` | Persian |
| Other Arabic script | Arabic |
| Devanagari | Hindi |
| Bengali script | Bengali |
| Gurmukhi | Punjabi |
| Latin | English |
| Anything else | `und`, shown as "Detected language" |

### 6.5 Caption font by script

| Script | Font |
|---|---|
| Urdu letters (as in §6.4) | Noto Nastaliq Urdu |
| Other Arabic script | Noto Naskh Arabic |
| Everything else | Inter; glyphs it lacks fall back to system fonts |

Urdu, Arabic and Persian text is right to left.

### 6.6 Roman Urdu

A rule-based, letter-by-letter transliteration, with a short list of common-word overrides (`پہ`→`pe`, `ہے`→`hai`, `اور`→`aur`). It is imperfect by design, and the text stays editable.

## 7. Logo

"Trim": trim brackets around a five-bar waveform on a rounded tile, in a 100-unit viewBox. One `LogoPainter` serves the UI, the export overlay and the launcher icon.

| Part | Spec |
|---|---|
| Tile | rx 24 |
| Brackets | `M33 24 H24 V76 H33` and `M67 24 H76 V76 H67`, stroke 6, round caps and joins |
| Bars | x = 38, 44, 50, 56, 62 spanning y 42–58, 35–65, 30–70, 37–63, 43–57, stroke 4.5, round caps |
| Colours | tile `#3DD68C`, ink `#06140D`; dark variant tile `#18201C`, ink `#3DD68C` |

The Android launch screen (FR-20) draws the same shapes as vector drawables (`launch_logo.xml`, `splash_icon.xml`), since it shows before Flutter starts; keep them in step with `LogoPainter`. `LogoPainter` also takes a `LogoPose` (bracket inset, bar half-lengths) for the launch animation; the rest pose is the table above.

## 8. Error states

| Condition | Where | Message | Actions |
|---|---|---|---|
| Invalid link | Source | That doesn't look like a YouTube link. | Edit |
| Video unavailable, private, age-restricted or live | Processing | This video can't be downloaded. | Back |
| No network during download | Processing | You're offline. Connect and try again. | Retry, Back |
| yt-dlp can't read the video, even after updating | Source / Processing | Couldn't read this video from YouTube. Try again later. | Retry, Back |
| No Groq key saved, script has no captions | Processing | Writing a script needs a free Groq key. | Settings, Back |
| Groq rejected the key (401/403) | Processing / Script | Groq didn't accept your API key. | Settings, Back |
| Groq limit (429, wait over 60 s) | Processing / Script | Groq's free limit is used up for now. Try again in <n> min. | Back |
| Groq failed (other error, or 5xx/498 twice) | Processing | Groq couldn't write this script. | Retry, Back |
| Network lost while Groq writes | Processing / Script | You're offline. Connect and try again. | Retry, Back |
| Key check failed | Settings | Groq didn't accept this key. | Edit |
| No speech found | Processing | No speech found in this video. | Try another language, Back |
| Translation pack missing and offline | Style | English needs a one-time download. | Retry |
| Gallery access refused | Done | Allow Photos access in Settings to save reels. | Open settings |
| Render failed | Export | Couldn't make the reel. | Retry, Back |
| More than 60 lines to copy for an AI, or more than 30 for Fix with Groq | Script | Too many lines for an AI to check. Tap the start and end lines of your clip first. | (snackbar) |
| No Groq key, Fix with Groq | Script | Fixing a script needs a free Groq key. | Settings (snackbar action) |
| Groq failed while fixing (other error, or 5xx/498 twice) | Script | Groq couldn't fix this script. | (snackbar) |
| Groq's reply to Fix with Groq has no script rows | Script | Groq's reply had no script lines. Try again. | (snackbar) |
| Not enough storage | any download or export | Not enough space on your phone. | Back |

Each error is a typed exception from the data layer. Screens map them to these messages, and nothing returns `null` or a sentinel.

## 9. Decisions

| Decision | Choice and why |
|---|---|
| Scope | General-purpose: any video, any language. No content-type picker, no automatic segment finding; the user picks lines |
| Distribution | Sideloaded APK, since downloading from YouTube keeps it off the stores. YouTube access sits behind `VideoSource`, so a store build could swap in local files |
| YouTube access | yt-dlp on the phone resolves videos and Dart downloads. YouTube refused `youtube_explode_dart`'s URLs (§10 Q4). Android only |
| Speech to text | Groq `whisper-large-v3-turbo` only. On-device Whisper (`whisper_ggml`) was dropped in M10: medium q5_0 ran at 0.2× real time on a Redmi Note 11 (Snapdragon 680), and small was only 1.5× on a Pixel 6a (§10 Q2) |
| Cloud transcription | Groq `whisper-large-v3-turbo` with the user's own key (FR-12a), because the phone is too slow (§10 Q2). A key shipped in the APK could be extracted, and the app has no server. Groq is fast, multilingual and cheap ($0.04 per audio hour, with a free plan). Pieces go as `.m4a`, not WAV, to save data. Groq's `url` input isn't used because YouTube stream URLs are tied to the phone's IP |
| FFmpeg | `ffmpeg_kit_flutter_new_min` only (LGPL). The full GPL build would duplicate native libraries and make the app GPL |
| Renderer | Media3 Transformer (hardware H.264), because the bundled FFmpeg can't encode H.264 |
| Captions and branding | Drawn by Flutter to one PNG and overlaid by Media3. Other text engines break Nastaliq letter joining |
| Data saving | Script audio at the lowest bitrate (none with captions); video and clip audio only for the clip window |
| Reuse | Scripts saved per video, language and source for 90 days; resume per 90-second piece |
| Background work | One foreground service kept by Dart. The work already runs in the app process, so keeping the process alive is enough. Packages rather than hand-written Kotlin, so the notification shows the percent as text, not a bar |
| Name, logo, IDs | Status Studio; Trim; `com.hotmail.arehmananis.statusstudio` |
| Fonts | Inter (UI), Noto Nastaliq Urdu, Noto Naskh Arabic (OFL) |
| Signing | Upload keystore and `key.properties` committed, because the repo is private |

## 10. Spikes and measurements

1. **FFmpeg build (resolved 2026-10-30).** `--disable-mediacodec --disable-openssl`, no libx264 or openh264: no H.264 encoder and no https input. So the app renders with Media3 and downloads in Dart.
2. **Whisper speed (historical: on-device Whisper was removed in M10).** Pixel 6a, profile build, 2026-11-02. One 90 s piece of a sung Urdu clip (`s6kE_uP3xH4`), whisper_ggml 2.8.1 at 6 threads:

   | Model | File | Time | Speed | Text |
   |---|---|---|---|---|
   | small f16 | 488 MB | 123.7 s | 0.73× real time | Best |
   | small q5_1 | 190 MB | 60.7 s | 1.48× | One phrase misheard |
   | base f16 | 148 MB | 29.1 s | 3.09× | Loops |
   | base q5_1 | 60 MB | 22.8 s | 3.94× | Loops, more errors |

   **Decision:** quantised files for every model (q5_1 for tiny to small, q5_0 for medium and large-v3); small stays the default. **Redmi Note 11 (Snapdragon 680, 5.5 GB, no dot-product), profile build, 2026-11-04:** medium q5_0 ran at 0.2× real time by the app's own meter ("39:50 left" for a 9:08 video), about 7½ minutes per 90 s piece. Cancelled; this is why on-device Whisper was dropped (M10). Text quality on a Mac, same weights, piece 1 of the sung clip: medium best, small garbles and merges lines, base loops; Groq turbo is clean but merges whole choruses into 30 s segments.

   **Why it's slow:** `whisper_ggml` builds whisper.cpp for baseline ARMv8 (no dot-product, so it doesn't crash on old phones) and CPU only. Speed-ups for later: runtime CPU-variant dispatch, the built-in Silero VAD (`vadModelPath`), and no temperature fallback.
3. **WhatsApp Status limit (2026-11-02).** 60 s is the general limit, and 90 s has been seen only in beta. The 60 s warning stays; confirm on a phone (§14).
4. **YouTube reading.** YouTube refused every `youtube_explode_dart` 3.1.0 stream URL (HTTP 403), so the app moved to yt-dlp, whose URLs download at about 10 MB/s. Redmi Note 11, 9-minute video:
   - Python start: 2.7 s.
   - yt-dlp with QuickJS: 12–16 s, or about 30 s after updating to 2026.10.26.
   - Without JavaScript: 8–13 s, with the same 31 formats.
   - The arm64 APK went from 57.4 to 45.4 MB, but the installed size grows.

   **Decision:** read without JavaScript first and with QuickJS only when that finds no usable formats. Each video is read once and kept while its URLs are valid.
5. **Groq (M9 Task 1, desktop part done 2026-11-04).** The 90 s pieces of `s6kE_uP3xH4` (sung Urdu, 9:08) were cut from the lowest-bitrate m4a (format 139, 49 kbps HE-AAC) with `ffmpeg -c copy -f segment`, and sent from a Mac on Wi-Fi with the user's free key. Results:
   - **Key check:** `GET /models` gives 200.
   - **Piece size:** 0.55 MB per 90 s, as the spec says.
   - **Offsets:** FFmpeg's segment list starts pieces at 90.000544 s, 180.001088 s and so on. They match the nominal 90 s multiples to under 1 ms, so `transcriptionChunk * position` is accurate enough.
   - **Speed:** about 1.4–2.2 s per piece (0.55 MB up), roughly 45× real time. Mobile data and the phone are still to measure (§14).
   - **Automatic language:** detected "Urdu" correctly; forcing `ur` gave the same lines, with segment times differing by under 0.1 s.
   - **Segments:** sung audio comes back in long segments (up to 30 s) with the same text repeated across the chorus; speech comes back as sentence-sized lines.
   - **`no_speech_prob` does not work on `whisper-large-v3-turbo`.** It is 0.000 on every segment, including a 90 s piano-only piece and 60 s of digital silence. Both came back as invented text ("Thank you." in 30 s segments, with `avg_logprob` −0.3 to −0.6 and `compression_ratio` 0.58). Those values overlap real sung Urdu (0.74–0.88), so no cut-off on them separates the two. `whisper-large-v3` (not turbo) does report it: 0.701 on silence. So the 0.6 cut-off in `groqNoSpeechCutoff` does nothing today. **Decided 2026-11-04 (M10 task 6): (a), keeping turbo.** Options were: (a) drop segments that are known hallucinations ("Thank you.", "you", "Thanks for watching.") or identical text repeated over 30 s segments, keeping turbo; or (b) use `whisper-large-v3`, which costs more per audio hour (check Groq's pricing page) and has a working `no_speech_prob`.
   - **Limits from the response headers (free plan):** 7,200 audio seconds per hour (`x-ratelimit-limit-audio-seconds`) and 2,000 requests (`x-ratelimit-limit-requests`, reset in about 2 min, so the daily/minute split in Groq's docs isn't visible). One 90 s piece uses 90 s of the hour budget. The reset time is a duration string such as `2m12s`; `retry-after` is only sent with a 429.
   - **Still to do on a phone:** timing on mobile data, and the FR-12a help-sheet button names (depends on task 8).
6. **Groq web-search model for the script fix (M15 task 1, run 2026-11-04, decision: go).** Question: can the user's Groq key fix a script the way ChatGPT does in FR-18? It only can if the model searches the web. Run from a Mac with the user's free key, using the exact FR-18 prompt on a 54-row script that Groq turbo wrote for `s6kE_uP3xH4` (sung Urdu naat; title in the prompt was "Main Madine Chala", guessed from the lyrics).
   - **Models:** `GET /models` lists `openai/gpt-oss-120b`, `openai/gpt-oss-20b`, `openai/gpt-oss-safeguard-20b`, `qwen/qwen3.8-27b`, `allam-2-7b` and the speech and prompt-guard models. **`groq/compound`, `groq/compound-mini` and `compound-beta` are not available to this key** ("model_not_found"). Web search comes from `openai/gpt-oss-120b` with `"tools": [{"type": "browser_search"}]`; the reply's `executed_tools` lists each search and page open. Not tested: `gpt-oss-20b`.
   - **30 rows (15 s, 33k tokens in total, 6 searches/opens):** every row came back, in order. 24 rows were corrected from a lyrics page, 6 were marked `[?]` (two verses it could not find). Quality looked good on a read-through, with the problems below. Not checked against a published lyrics page by a native reader.
   - **54 rows (19 s, 29k tokens):** rows 1 to 32 were not checked line by line, but rows 33 to 52 were **replaced with other lines of the poem, out of order, by position and not by sound.** Example: row 35 "وہ اہد کی زمین" (the singer says Uhud) became "وہ بقی کی زمیں" (the page says Baqi), and rows 37 to 52 were lines from elsewhere in the poem. Rows 53 ("موسیقی") and 54 ("Thank you.") were kept and marked `[?]`, which is right.
   - **120 rows (the 54 repeated, 19 s, 57k tokens):** only 11 rows came back, in the poem's order with added commas, so rule 4 and the row-count rule both failed. No cap above about 54 is worth trying.
   - **Problems that need code or prompt work:** (1) the 30-row reply put citation marks like `【1†L10-L12】` inside the row text, so `applyCorrectedScript` must strip `【…】`; (2) short filler rows ("محمدینِ چلا") were sometimes replaced with a different real verse, so the prompt needs "if a row sounds like a refrain, keep or repair it; never fill it with a line from another place"; (3) the model sometimes returns times that are wrong (`02:60.00`), which is harmless because FR-18 ignores times.
   - **Limits (free plan, from the response headers):** 8,000 tokens per minute and 1,000 requests for `gpt-oss-120b`. One search call uses 30k to 57k tokens in total, so a second call within the same minute got HTTP 429 (`Used 7973, Requested 2535`) and one call every minute or so is the practical rate. The daily token limit is not in the headers: check it on Groq's limits page before shipping.
   - **Whether it is worth it:** at 30 rows or fewer it did the job in 15 s with no copy and paste. Above that it mis-assigns rows (FR-18's 60-row cap was set for a different reason: chats skim long scripts). The picked clip is usually well under 30 rows.
   - **Decision (2026-11-04, the user): go.** Model `openai/gpt-oss-120b` with `browser_search`. Row cap **30** on this path (FR-18 keeps 60). The shared prompt gets a rule against moving lines from elsewhere into a row, and reply parsing strips `【…】` citation marks. The daily token limit is still unknown (not in the headers): a 429 whose wait is over 60 s already gives the §8 message. The naat with verses from another poem was not tested, so it goes to the §14 device check.

## 11. Out of scope for v1

- iOS release; Play Store or App Store builds.
- Local-file or share-into-app input.
- Multiple clips per reel, music, stickers, text animation.
- Accounts, cloud sync, analytics.
- Cloud transcription other than Groq, or a key shipped with the app.

## 12. Milestones

**Workflow:**
- One branch per milestone.
- Each task is a checklist under its milestone here, test first, ticked as it's done, with a commit per task.
- Merge when `tool/check.sh` (format, analyze, all tests) passes.
- If code and this document disagree, this document wins; fix it in the same commit.
- Spike results go into §10 before dependent tasks start.
- Device checks go into §14.

| Milestone | Delivered | Status |
|---|---|---|
| M1 App shell | Every screen with fakes; selection, clip, crop maths, link parsing | Done, in `dev` |
| M2 Video source | Metadata, downloads, cache, preview | Done, in `dev` |
| M2b Data saver | Low-bitrate script audio, clip-only download (FR-15) | Done, in `dev` |
| M3 Transcription | Model manager, chunked Whisper (both removed in M10), captions, language inference, saved scripts, resume | Done, in `dev` |
| M4 Fine-tune | Waveform, long-clip warning, language re-run | Done, in `dev` |
| M5 Render | Overlay PNG, Roman Urdu, translation, Media3 export | Done, in `dev` |
| M6 Library and settings | Save/share, Recent, Settings, launcher icon, cache cleanup, §8 errors | Done, in `dev` |
| M7 yt-dlp | yt-dlp source, self-updating; percent, sizes and speed per step | Done, in `dev`; device check pending |
| M8 Background work | Foreground service, result notifications, battery access (FR-16) | Done, in `dev`; device check pending |
| Speech models | Quantised files for all models, with pros and cons | Done, in `dev` |
| Saved scripts in Recent | Script rows in Recent (FR-11) | Done, branch `saved-scripts-in-recent` |
| Model download controls | Pause, resume, cancel (FR-12) | Done, branch `model-download-controls` |
| M9 Groq | Optional cloud transcription (FR-12a, §8) | Spec done; tasks to write, branch `m9-groq-transcription` |
| M10 Groq only | Remove on-device Whisper; Groq writes every script that has no captions | Tasks 1–7 done, branch `m10-groq-only` (stacked on M9); device check pending |
| M11 Timed captions | One caption line at a time (FR-7a) | Done, branch `m11-timed-captions` (stacked on M10); device check pending |
| M12 Real lyrics | Lyrics from lrclib.net replace the script (FR-17) | Done, branch `m12-online-lyrics` (stacked on M11); device check pending; removed in M17 |
| M13 AI script fix | Copy the script with a prompt for an AI agent; paste its corrected reply (FR-18) | Done, branch `m13-ai-script-fix` (stacked on M12); device check pending |
| M14 Preview and file name | Done plays the reel; the file is named `<kalam>-<start>-<end>` (FR-9, FR-10) | Done, branch `m14-reel-preview` (stacked on M13); device check pending |
| M15 Fix with Groq | Script button that fixes the lines with a Groq web-search model and the existing key (FR-19) | Done, branch `m15-groq-script-fix` (stacked on M14); device check pending |
| M16 Launch animation | Dark native splash with the logo; Flutter animates the logo, then shows Home (FR-20) | Done, merged into `main`; device check pending |
| M17 Fix with Groq only | Script keeps only the Fix with Groq button; Real lyrics, Copy for AI and Paste AI reply and the lyrics feature are removed | Done, branch `m17-groq-fix-only`; device check pending |
| M18 Fine-tune lines | Play, pause and seek; edit, reorder, add and delete lines; tap a line while playing to time it (FR-5, FR-21) | Done, branch `m18-fine-tune-lines` (stacked on M17); device check pending |
| M19 Fine-tune steps | Fine-tune in two steps: Video (nudges, size, crop that can move) and Lyrics (the clip's lines, timing, video with the lyrics on it) (FR-5, FR-21, FR-22) | In progress, branch `m19-fine-tune-steps` (stacked on M18) |

### M9 tasks (branch `m9-groq-transcription`)

Each task: test first, tick it, commit.

- [ ] **1. Spike (needs the user's Groq key, on a phone).** Results go into §10 Q5 before tasks 4 and 8 settle their constants. Desktop part done; the `no_speech_prob` finding needs a decision; mobile data and help-sheet names remain.
- [x] **2. `GroqClient` (data).** Typed `GroqException`s (rejected key, rate limit with wait, server, offline); `checkKey` via `GET /models`; `transcribe` of one `.m4a` piece via `POST /audio/transcriptions` (`verbose_json`, segments). 429 under 60 s waits and resends; 5xx/498 retried once. The key is never in a log or error text. Faked HTTP in tests.
- [x] **3. `GroqKeyStore`.** Key in `flutter_secure_storage`, plus the switch in settings; the switch can only be on while a key is saved.
- [x] **4. `GroqTranscriber`.** Emits the same `ChunkEvent`s as `WhisperTranscriber`; offsets segments by piece start; drops segments over the `no_speech_prob` cut-off.
- [x] **5. Stream-copied `.m4a` pieces.** `AudioPreparer.splitAudioCopy` (FFmpeg `-c copy`, 90 s pieces).
- [x] **6. Pipeline engine choice.** (Superseded by M10: Groq is the only engine.) Groq when on and a key is saved, else Whisper; skip the model step; save under `groq-whisper-large-v3-turbo`; partial progress per piece.
- [x] **7. Errors and Use on-device.** (Use on-device was removed in M10.) §8 messages and actions on Processing; Use on-device keeps Groq's lines and continues from the next piece on the phone.
- [ ] **8. Settings section.** Key field (Paste, Show, Remove, check result), ⓘ help sheet with Copy link, switch with subtext.
- [ ] **9. Docs.** §13 tests list, §14 device checks, milestone status.

### M10 tasks (branch `m10-groq-only`)

Decision, 2026-11-04: on this phone class (Redmi Note 11, Snapdragon 680) Whisper medium runs at 0.2× real time, so on-device Whisper is dropped. Scripts without YouTube captions are written by Groq with the user's own key. This replaces FR-12 (models), FR-13 (offline scripts), the on-device engine and Use on-device; the spec text is rewritten in task 5. Each task: test first, tick it, commit.

- [x] **1. Remove on-device Whisper.** Delete `WhisperTranscriber`, `ModelManager`, `SpeechModel`, `WhisperEngine`/`ScriptEngine`, the WAV conversion, the "Downloading the speech model" step and the Settings models section. `ChunkEvent` moves next to `GroqTranscriber`. With no saved key, a script without captions stops with `NoGroqKeyException` ("Writing a script needs a free Groq key.", actions Settings and Back).
- [x] **2. Drop Use on-device and the switch.** A saved key is the only switch; Remove turns it off. §8 actions: key rejected → Settings, Back; limit → Back; failed or offline → Retry, Back.
- [x] **3. Settings: Groq key section.** Key field (Paste, Show, Save, Remove, check result) and the ⓘ help sheet with Copy link. (M9 task 8, without the switch.)
- [x] **4. Remove `whisper_ggml`.** Drop the dependency and its Android settings (NDK note), WAV-only FFmpeg arguments and dead test helpers.
- [x] **5. Docs.** Rewrite the affected FR text, §6, §8, §10, §13, §14; update `CLAUDE.md`; merge status.
- [x] **6. Turbo hallucination guard.** Turbo reports `no_speech_prob` 0 and invents "Thank you." on silence and music (§10 Q5). A piece whose segments are all known phrases gives no lines; the same phrase beside real speech is kept.
- [x] **7. Clean-up.** Delete scripts and progress saved under `whisper-*` on startup; unpin the NDK; install the new build on the Redmi.

### M11 tasks (branch `m11-timed-captions`)

Request, 2026-11-04: show one line of caption at a time. Each task: test first, tick it, commit.

- [x] **1. Cue timing (domain).** `buildCaptionCues`: spoken times when counts match, shared by length otherwise, clamped to the clip, blank lines and empty cues dropped. `ReelDraft.captionCues`.
- [x] **2. Render spec and overlays (Dart).** `RenderJob.captionCues`; the renderer paints the branding PNG plus one PNG per cue and keeps them until the render ends.
- [x] **3. Timed overlay (Kotlin).** `RenderSpec.captionCues`, `overlayPathAt`, and a `BitmapOverlay` that opens each cue's PNG when it is due.
- [x] **4. Preview and hint.** The Style preview shows the first line; the caption hint explains that lines show one at a time.
- [x] **5. Docs.** FR-7a, §13, §14.

### M12 tasks (branch `m12-online-lyrics`)

Request, 2026-11-04: lyrics have many issues; get the correct lyrics online. Each task: test first, tick it, commit.

- [x] **1. LRC parsing (domain).** `parseSyncedLyrics`: rows to lines, ends from the next row, empty rows, metadata tags, repeated timestamps, track-end cap.
- [x] **2. Query and matching (domain).** `lyricsQueryFor`, `bestLyricsFor`: length within 10 s, title overlap, synced only, closest length wins; `LyricsNotFoundException`.
- [x] **3. `LrclibClient` (data).** `GET /api/search`; instrumentals skipped; failures become `OfflineException`.
- [x] **4. `LyricsService` (application).** Search, match, parse, infer language, save as source `lrclib`.
- [x] **5. Script screen.** "Real lyrics" button, results and §8 messages in a snackbar.
- [x] **6. Docs.** FR-17, §8, §13, §14.

### M13 tasks (branch `m13-ai-script-fix`)

Request, 2026-11-04: export the script with timing for an AI agent and paste the fixed script back, with the least work from the user. Each task: test first, tick it, commit.

- [x] **1. Prompt and reply parsing (domain).** `scriptPromptFor`, `applyCorrectedScript`: rows matched by number, text only, `[?]` marks, tolerant of fences and chatter, `NoScriptRowsException`.
- [x] **2. Corrected lines in the draft.** `ReelDraft.withCorrectedLines` keeps the picked range and clip and refills the caption.
- [x] **3. Saving.** `ScriptEditingService` saves source `edited` as the newest script.
- [x] **4. Script screen.** Copy for AI and Paste AI reply on one compact row with Real lyrics; snackbars; §8 message.
- [x] **5. Docs.** FR-18, §8, §13, §14.

### M14 tasks (branch `m14-reel-preview`)

Requests, 2026-11-04: no way to view the output before saving and sharing; name the exported reel `{kalam 2 words}-{start 2 words}-{end 2 words}`. Each task: test first, tick it, commit.

- [x] **1. Player on Done.** `ReelPlayer`: tap to play or pause, progress bar, rewinds at the end, thumbnail until ready or if the file won't open; disposed on leaving.
- [x] **2. File name.** `reelFileStem` and a free output path (`-2`, `-3`, …).
- [x] **3. Overlay clean-up race.** The renderer deleted the overlay PNGs after reporting the end of a render, so a listener could still see them; it now deletes first (found by a flaky test).
- [x] **4. Docs.** FR-9, FR-10, §13, §14.

### M15 tasks (branch `m15-groq-script-fix`)

Request, 2026-11-04: merge the script fix (FR-18) and Groq transcription into one API key. Each task: test first, tick it, commit. Tasks 2 to 6 start only after task 1 records "go".

- [x] **1. Spike §10 #6.** Find the web-search models the key can call and test them on the FR-18 prompt; record the results and the go or stop decision in §10. On "stop", mark M15 cancelled in the §12 table and do nothing else.
- [x] **2. Chat call in `GroqClient`.** `fixScript(prompt)` posts to `/chat/completions` with the spiked model and returns the reply text. Reuses `_send`, so 401/403, 429 waits, 5xx retries and offline map to the existing typed exceptions. Tests with a fake server: reply text returned, the key only in the header, 429 wait and retry, rejected key.
- [x] **3. `GroqScriptFixService` (application).** Builds the FR-18 prompt for the same lines, calls `fixScript`, applies the reply with `applyCorrectedScript`, leaves saving to the screen, which saves after Cancel is no longer possible, as Paste AI reply does. Throws the existing `NoScriptRowsException` when the reply has no rows and `TooManyLinesForAiException` above the 30-line cap. Tests with a fake `GroqClient` provider.
- [x] **4. Script screen.** Fix with Groq button: progress and Cancel, other fix buttons off meanwhile, no-key message with Settings, snackbars as FR-18 (`[?]` lines named). Widget tests with provider overrides.
- [x] **5. Help text.** The Settings note says the key also fixes scripts and that the picked lines, title and link go to Groq on tap. (The help sheet only explains how to get a key, so it is unchanged.)
- [x] **6. Docs.** FR-12a and FR-18 cross-links, §1 summary line, §8 rows for Groq failing during a fix, §13, §14 device check (a real naat on the phone, mobile data), and `CLAUDE.md`'s "Groq writes every script" bullet.

### M16 tasks (branch `m16-launch-animation`)

Request, 2026-11-04: the app opens on a white screen; make a launch animation from the logo. Each task: test first, tick it, commit.

- [x] **1. Logo pose and timeline.** `LogoPose` (bracket inset, bar half-lengths) and `LogoPainter(pose:)`; `launchFrameAt(progress)`: rest pose at 0 and from the exit on, bars within their limits, brackets clear of the bars, wordmark shown before the exit, splash gone at 1.
- [x] **2. `LaunchSplash` widget.** Over the app from the first frame, removed when the animation ends, skipped with reduce motion, blocks taps; wired in `StatusStudioApp` behind `launchSplashEnabledProvider`, which app tests turn off.
- [x] **3. Native splash.** Android launch window and Android 12+ splash: background `#0E1311` and the logo; dark `NormalTheme` background; iOS launch screen background.
- [x] **4. Docs.** FR-20, §7, §13, §14.

### M17 tasks (branch `m17-groq-fix-only`)

Request, 2026-11-04: keep only the Fix with Groq button on the Script screen. Each task: test first, tick it, commit.

- [x] **1. Script screen.** A test that Script offers Fix with Groq and not Real lyrics, Copy for AI or Paste AI reply; the three buttons, their widget tests and the clipboard fake are removed; Fix with Groq sits alone and keeps its Cancel while it runs.
- [x] **2. Delete the lyrics feature (request 2026-11-04: "do it").** Test first: the file-name test for a title with a `|`. Then `lib/src/features/lyrics` and its tests are removed.
- [x] **3. Docs.** FR-17, FR-18, FR-19, §8, §13, §14 and `CLAUDE.md`. The lyrics feature is deleted (tests with it); title cleaning for the file name moved into `reel_file_name.dart`; the `LyricsNotFoundException` message and `lyricsSource` are gone.

### M18 tasks (branch `m18-fine-tune-lines`)

Request, 2026-11-04: Fine-tune gets play, pause and seek, editable lines (edit, reorder, add) and tap-to-time while playing. The 5 s extra video of FR-15 stays. Each task: test first, tick it, commit.

- [x] **1. Line edits (domain).** Pure functions on a script and its picked range: edit text, reorder (text moves, times stay), add at the playhead, delete, sync a line to the playhead, and which line is highlighted at a time.
- [x] **2. Draft.** Applying an edit keeps the range on the same lines, refills the caption, and moves the clip only when the range or its first or last line's times change.
- [x] **3. Player.** Play, pause and seek over the window; no stop at the clip end; a playhead that Fine-tune can read and seek.
- [x] **4. Lines list.** All lines in the window, dimmed outside the range, highlight, tap to seek or to time, edit, reorder, add, delete.
- [x] **5. Save.** The edited script is saved as `edited` after 1 s idle and when the screen closes.
- [x] **6. Docs.** §13 and §14 entries; mark M18 done.

### M19 tasks (branch `m19-fine-tune-steps`)

Request, 2026-11-04: crop position that changes while the video plays (glide or cut, both); Fine-tune in two steps, video then lyrics, with the lyrics on the video. The plan was checked by an Opus reviewer before task 3, and its changes are in FR-22 and §6.3.2: Kotlin comes before any UI that can make keyframes, the base anchor replaces Keep in view's three values, a drag writes one keyframe, a ticker moves the previews smoothly. Each task: test first, tick it, commit.

- [x] **1. Crop path (domain).** Anchor, keyframes with Glide or Cut, the anchor at a time, set a keyframe at a time (snap, replace within 0.25 s), change how one arrives, remove one.
- [x] **2. Frame carries the path.** `FrameSettings.cropPath`; the pixel crop at a time (`cropRectAt`), equal to `cropRectFor` with no keyframes; keyframes in the render spec as NDC rectangles from the clip start.
- [x] **3. Kotlin.** `RenderSpec` reads `cropKeyframes`; pure `ndcRectAt` with the boundary cases the Dart tests use; the matrix transformation with `configure` and one `clipTimeMs` helper shared with the caption overlay. Before any UI can make keyframes, because Kotlin refuses a spec with keyframes today.
- [x] **4. Base anchor.** `FrameSettings.anchor` replaces `focus` (Keep in view sets it); keyframes can be removed unless the last one; a new keyframe time is clamped into the clip.
- [ ] **5. Two steps.** Routes, step labels for all screens ("of 5") and buttons; the Video step keeps the player, nudges and warnings and takes size, fill and crop from Style; the Lyrics step takes the lines (only the clip's); Style keeps the caption.
- [ ] **6. Moving crop on Video.** The crop window over the player, with the switch (hidden without room); drag writes one keyframe on release; chips in the pinned part with Glide, Cut and Delete; a ticker for the playhead.
- [ ] **7. Lyrics preview.** `ReelPreview` follows the playhead (moving crop and the due cue); the Video step's player is released while Lyrics is open.
- [ ] **8. Docs and review.** §13, §14, §15; reviewer pass; push.

## 13. Behaviour that must stay covered by tests

- **Links:** a link with whitespace, `si=` parameters or the `m.` host parses.
- **Selection and nudges:**
  - A tap before the start restarts the selection; it never makes a reversed range.
  - Nudges past either end of the video are ignored. A nudge that improves an invalid clip is applied.
  - A free-crop drag stays inside the frame.
  - A new transcript clears the selection and clip.
- **Downloads:**
  - An interrupted download is never reused as complete; a complete one is reused.
  - Pasting a link twice doesn't download again.
- **Captions:** translated auto-captions never become a script, and automatic language skips auto-generated tracks.
- **Transcription:**
  - Non-speech tokens never become lines.
  - Lines keep absolute times across piece boundaries.
  - A killed run resumes from the next piece.
  - A saved script opens without downloading.
- **Waveform:**
  - It maps samples to video time when the window starts after 0.
  - Very short audio still gives the requested number of bars.
  - Silence gives flat bars, not NaN.
  - The warning appears at 60.5 s and not at 60.0 s.
- **Render:**
  - Free crop is right for 720p and vertical sources.
  - Trims respect the clip file's offset.
  - A long caption shrinks, then ellipsizes.
  - Cancel deletes the partial MP4.
  - A native error surfaces as "Couldn't make the reel."
  - **File name (FR-9):** two words from the title, the caption's first line and its last line; punctuation dropped; a repeated name gets `-2`.
  - **Done player (FR-10):** it plays and pauses on tap, rewinds at the end, falls back to the thumbnail for a file that won't open, and is disposed on leaving.
  - **Caption lines (FR-7a):**
    - Each line is a cue at its script line's time, counted from the clip start and clamped to a nudged clip.
    - An edited line count shares the clip by line length.
    - One overlay PNG per cue is written, kept while the render runs and deleted when it ends.
    - Kotlin picks the line due at a time, with the end exclusive, and the branding between lines.
- **Fine-tune lines (FR-21):**
  - A tap while playing sets the line's start to the playhead and ends the highlighted line there.
  - A tap earlier than the previous line's start changes nothing.
  - Reorder moves text only; times stay in place.
  - A new line lands at the playhead; the line it lands in ends there.
  - Delete refuses the last picked line, and the range keeps the same lines.
  - The clip follows the range's end lines, and a plain nudge survives an edit elsewhere.
  - Highlight lasts from a line's start to its end, and nothing between lines.
  - An edit is saved after 1 s without edits and when the screen closes; closing with no edit saves nothing.
- **Library:**
  - The 51st reel drops the oldest and its files.
  - Reels with missing files are skipped, and corrupt preferences give an empty list.
  - Refused gallery access explains and offers settings.
- **Background:**
  - Cancel posts no result, and results post only when the app is hidden.
  - The service outlives the first of two jobs.
  - Platform calls stay in order.
- **AI script fix (M13):**
  - The prompt holds the title, link and each row with its time and its row number in the whole script.
  - Only the picked clip's lines are sent; more than 60 lines, picked or not, are refused.
  - A reply's text replaces lines by row number; its times are never used.
  - Fences and chatter around rows are ignored; rows with bars in the text stay whole.
  - Missing rows keep their text; `[?]` rows are kept and named; a reply with no rows is rejected and changes nothing.
  - Corrected lines keep the picked range and clip, and the corrected script is the one that reopens.
- **Groq script fix (M15):**
  - The request goes to `/chat/completions` with the web-search model and the key only in the Authorization header; a 429 waits and resends; a 401 is "key rejected".
  - Only the picked clip's lines are sent; more than 30 are refused before anything is sent.
  - Citation marks `【…】` never end up in a line's text.
  - Cancel ignores the reply and saves nothing; the other fix buttons are off while it runs.
  - No key gives the §8 message with a Settings action; a Groq failure says "Groq couldn't fix this script."
- **Groq (M9):**
  - The key never appears in logs, files or errors.
  - A 429 under 60 s waits and resends.
  - A script without captions and without a key stops before downloading audio.

- **Launch animation (M16):**
  - The first frame is the logo's rest pose, the same as the native splash.
  - Outer bars stay under y 31 and the brackets move in at most 7 units, so nothing overlaps.
  - The splash covers Home, blocks taps, and goes when the animation ends; reduce motion skips it.

## 14. Device checks

Run on a **release** build (or profile; debug builds are slow). Phones: Pixel 6a (Tensor, 6 GB, Android 17) and Redmi Note 11 (Snapdragon 680, 5.5 GB, Android 13).

**Passed (Pixel 6a, M4 build, 2026-10-30):**
- Real metadata.
- The captions path.
- Clip-only download: 5.4 MB for a 35 s window.
- Clip-only preview.
- Waveform matches desktop FFmpeg.
- Lines appear progressively.
- Urdu in right-to-left Nastaliq.

**To check:**
- **Video source:**
  - [ ] Lip sync in the Fine-tune preview.
  - [ ] A nudge past the window downloads a new one.
  - [ ] A stream without range support falls back to the whole video.
  - [ ] A cached clip is reused after a restart.
  - [ ] Without captions, the title shows in about 10 s and "Downloading audio" shows percent, MB and speed.
  - [ ] Manual captions become the script.
  - [ ] Wi-Fi ↔ mobile data on Fine-tune still downloads (fresh URLs after a 403).
  - [ ] The yt-dlp version and Update in Settings.
  - [ ] The first-run weekly update.
  - [ ] A private video and airplane mode give the right messages.
  - [ ] The first read is about 13 s, later reads about 8 s.
  - [ ] Each step's bar shows percent, done of total, speed, and a time left that counts down and then disappears.
- **Script:**
  - [ ] Groq on a 5-minute speech clip and on singing; quality and speed (§10 Q5).
  - [ ] Lines at piece boundaries.
  - [ ] A killed run resumes.
  - [ ] The saved-script banner and "Write it again".
  - [ ] Airplane mode with a saved script still opens it; a new script says "You're offline."
  - [ ] Back on Processing stops all CPU work.
- **Fine-tune:**
  - [ ] The waveform lines up with the sound.
  - [ ] The warning appears above 60 s.
  - [ ] A language change reuses the audio.
  - [ ] Play, pause and the seek bar work over the window; playback runs past the clip end.
  - [ ] Tapping lines while a naat plays times them, and the highlight follows without lag.
  - [ ] Editing, reordering, adding and deleting lines with Urdu text; the edited script reopens for the same video.
- **Render:**
  - [ ] A 10 s clip with each fill (9:16 crop and blur, 4:5, 16:9, free) is H.264, matches the layout, with a sharp full-frame overlay and audio in sync.
  - [ ] The stretched blur looks acceptable (§6.3.1).
  - [ ] Each preset plays in the gallery, shares to WhatsApp Status, matches the preview and shows Nastaliq.
- **Library:**
  - [ ] The longest trim WhatsApp Status allows (§10 Q3).
  - [ ] Save on Android 10+ with no prompt; on Android 7–9, one prompt, and a refusal leads to Open settings.
  - [ ] The adaptive launcher icon under every mask.
  - [ ] Each §8 condition shows its message and actions.
  - [ ] The full smoke test, from link to share.
- **Background:**
  - [ ] Notification and battery prompts each come once.
  - [ ] Locking within 2 s of starting still finishes the run.
  - [ ] The notification survives Home, lock and dialogs, and goes when the app is swiped away.
  - [ ] The step and percent update.
  - [ ] A locked run of 5+ minutes finishes and "Script ready" opens Script.
  - [ ] "Reel ready" opens Done.
  - [ ] Airplane mode while hidden gives "Script stopped".
  - [ ] No result notification while the app is on screen.
  - [ ] Export over a running script: the notification switches and the service stops last.
  - [ ] Redmi with the default battery saver; note whether "No restrictions" was needed.
  - [ ] The Background work rows update after "Allow".
  - [ ] Small plus the service on a 4 GB phone without running out of memory.
  - [ ] The notification icon isn't a white square.
- **Saved scripts in Recent:**
  - [ ] A processed video's row is above older reels.
  - [ ] Tapping it opens Script with no download.
  - [ ] Deleting it means the next paste writes the script again.
- **Preview and file name (M14):**
  - [ ] Done plays the reel with sound; tap pauses; the bar can be dragged; it rewinds at the end.
  - [ ] A reel with timed captions shows each line when expected (this is the first place the Media3 timing can be seen).
  - [ ] The saved file in the gallery and the shared file show the `<kalam>-<start>-<end>` name, with Urdu words intact.
  - [ ] The Recent list thumbnail still appears for a file with an Urdu name (FFmpeg reads the path).
  - [ ] Exporting the same clip twice gives `…-2.mp4`.
- **Caption lines (M11):**
  - [ ] A reel with 3+ lines shows one line at a time, each when it is said, and only the branding between lines.
  - [ ] Cue times line up with the video (Media3 hands the overlay times counted from the clip start; if the first line is early or late by the clip's lead-in, fix the offset in `TimedCaptionOverlay`).
  - [ ] A 60 s clip with ~20 lines renders without running out of memory.
  - [ ] Cancel mid-render leaves no overlay PNGs in the reels folder.
- **Groq script fix (M15):**
  - [ ] Fix with Groq on a real naat clip (10–30 rows) over mobile data: time taken, and the corrected lines read right to a native reader.
  - [ ] A naat with verses from another poem (not yet tested, §10 #6): the other poem's lines come back right, and nothing is moved into a wrong row.
  - [ ] Free-plan limit: two fixes in a row (the 8,000 tokens per minute limit) and what the daily limit allows.
  - [ ] Cancel mid-run; no key (Settings opens); revoked key; airplane mode.
- **Groq (M9):**
  - [ ] The key check, help sheet and Copy link.
  - [ ] A 10-minute video's script time.
  - [ ] Data used.
  - [ ] A revoked key, the rate limit, and no key at all (Settings opens).
  - [ ] Settings: Paste, Show, Save and Remove; help sheet and Copy link.

**Launch animation (M16), on both phones:**
- [ ] Cold start from the launcher: dark background with the logo from the first moment, no white flash.
- [ ] The native logo hands over to Flutter's without a jump in size or position (Android 13 splash API on the Redmi, and with three-button navigation if possible).
- [ ] The animation plays once and Home is usable straight after; with "Remove animations" on, Home shows at once.
- [ ] Returning to the app from Recents doesn't replay it.

## 15. Known issues (found on the phone, not fixed)

- Processing says "Downloading audio" even when the audio is cached.
- The language list shows both "English (detected)" and "English".
- **Fine-tune lines (M18):** (a) dragging a line's handle does not scroll the screen, so text can only be dragged to rows in view; fixing it means a sliver reorderable list. (b) Timing a line beyond the downloaded window starts a new download (FR-15) and replaces the player in the middle of playing. (c) A script that finishes writing after the user edited lines saves itself as a newer script than the `edited` one, so the video reopens without the edits.
