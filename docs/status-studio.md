# Status Studio

**Updated 2026-11-05.** The one project document: product spec, engineering rules, milestones, device checks and known issues. It is the source of truth for behaviour, copy, sizes and error messages. Code cites its section (§) and FR numbers, so keep them stable and add new sections at the end. Design canvas: <https://claude.ai/artifact/HcKksQmAu8ZYBfQdbnr2RN>

## 1. Summary

Status Studio turns a video the user has already trimmed in another app, in any language, into a short clip for WhatsApp Status, Reels, TikTok or Shorts. The user shares the video into the app or picks it from the gallery. The app cleans the voice and writes out the script. The user fine-tunes the start and end by ±0.5 s and the lyrics, picks a size, and chooses what the crop follows at every scene: a face, a body or a fixed spot. Then a caption. The export is an MP4 with the Status Studio name and logo.

- **On the phone:** voice cleaning (FFmpeg), translation (ML Kit) and rendering (Media3 Transformer on Android, AVFoundation on iOS from M26). No accounts, no servers, no analytics.
- **Groq writes scripts:** every script is written by Groq's hosted Whisper, with the user's own free API key (FR-12a), from the cleaned audio (FR-26). Script audio leaves the phone only then, and only to Groq. The same key also powers Fix with Groq (FR-19), which sends the clip's lines and the title when the user taps it. The app ships no key and has no server of its own. On-device Whisper was dropped (M10): on a Redmi Note 11 it ran at 0.2× real time.
- **No media downloads:** the video comes in as a local file, copied into the app's storage. Nothing is fetched from the internet except language packs and the Groq requests above.
- **Saves work:** scripts are saved by the video's fingerprint, so the same video opens straight to its script next time.
- **Pivot (2026-11-05, M23):** until M22 the input was a YouTube link. YouTube is dropped entirely: no links, yt-dlp, stream downloads or caption tracks.

## 2. Screens

| # | Screen | Route | Job |
|---|---|---|---|
| 1 | Home | `/` | Start a reel; recent reels, saved scripts and fine-tunes to continue (FR-24); open Settings; a shared video opens Source (FR-1) |
| 2 | Source | `/source` | "Choose a video" from the gallery, or the video shared into the app (FR-1); a card with thumbnail, name and length; choose language (default automatic); Get script (changed in M23) |
| 3 | Processing | `/processing` | Clean the voice (FR-26, M24) → write the script with Groq → detect language → line up timestamps (skipped for a saved script, FR-14). Nothing is downloaded (changed in M23) |
| 4 | Script | `/script` | Review the whole script: language, Fix with Groq, Next. No start or end line to pick (changed in M23) |
| 5 | Fine-tune · Video | `/fine-tune` | Step 1 of Fine-tune (M19): plays the kept video file; play, pause, seek over the whole video; nudge start and end by ±0.5 s; size, fill and crop, with a crop that can move during the clip (FR-22) and is chosen scene by scene (FR-27, M25) |
| 5b | Fine-tune · Lyrics | `/fine-tune/lyrics` | Step 2 of Fine-tune (M19): only the clip's lines; edit them and set when each one shows; the video plays with the lyrics on it (FR-21) |
| 6 | Style | `/style` | Caption text/variant/position/size; live preview with branding. Size and crop moved to Fine-tune · Video in M19 |
| 7 | Export | `/export` | Render with progress; Cancel returns to Style |
| 8 | Done | `/done` | Final preview; Save to gallery; Share; Make another |
| 9 | Settings | `/settings` | Groq key with step-by-step help (FR-12a); background work. The YouTube reader section was removed in M23 |

- **Visual reference:** the design canvas prototype for screens 1–8. Settings follows the same visual language.
- **Progress on Processing:** each step (cleaning the voice, writing the script) has its own bar with the percent beside it (`45 %`), and time left on the right (`1:24 left`) once it can be told. Nothing is downloaded, so there is no speed or size line (changed in M23).

## 3. Functional requirements

**FR-1 Video input (changed in M23; it was "Link input" for YouTube links).** The input is a video the user has already trimmed in another app. There are no links.
- **Share in:** the app accepts a shared video (Android `SEND` of `video/*` and `VIEW` of a `content` URI of `video/*`, received by our own `status_studio/video_in` channel; iOS Share Extension from M26). The copy is refused when the phone has less than the file's size plus 50 MiB free ("Not enough space on your phone.", §8), and `file` URIs into the app's own data folder are never read. A shared video opens Source with its card and starts the script. If a reel is in progress, the app asks first: "Start a new reel from this video? The one you're making will close." with Start and Keep. The kept fine-tune (FR-24) stays either way.
- **Pick:** "Choose a video" opens the system gallery picker (`image_picker` `pickVideo`: the Android Photo Picker, PHPicker on iOS), which needs no permission.
- **Both ways** put the file in the app's storage, `sources/<videoId>/source.<ext>` (§4). A shared file is already staged in `files/incoming/`, and `image_picker` already copied a picked one into the app's cache folder; those files are moved into place (copied, then deleted, when the folders are on different volumes), and deleted whether or not the import succeeds, so no video is kept twice. A file outside those two folders is streamed into place and left unchanged. The free-space check (size plus 50 MiB) applies to a copy only, and is skipped when the phone can't report its free space.
- **Already kept:** a video kept under the same ID is reused only if its length equals the incoming file's; a shorter or missing one is replaced (written as `.part`, then renamed), and only one `source.<ext>` is ever kept per ID. Two imports of the same video at once keep it once.
- **Lost pick (Android):** the system may close the app while the picker is open. Source asks the picker for a lost result when it starts (`VideoPicker.retrieveLostVideo`) and imports it if there is one.
- **Video ID:** `v_<16 hex>`, a fingerprint of the file: its size and the SHA-256 of its first and last 1 MiB. The same bytes give the same ID, so the same video is recognised however it arrives. The name `videoId` is kept in code.
- **Probe:** FFprobe reads the duration, size, rotation and whether there is an audio track. A video with no audio track, or one that can't be read, gives "Can't read this video." (§8).
- **Card:** thumbnail, display name (the file's name without its extension; the file's own name when the sender gave none) and length (`SourceVideo.title`, §6.1). Under the button Source says "Trim it in another app first, or share it to Status Studio."
- **Old IDs:** folders whose ID doesn't start with `v_` belong to YouTube videos and are deleted at every start (a quick listing; once they are gone it finds nothing). A folder counts as a video's only when its name is `v_` and 16 hex digits.

**FR-2 Language.** Dropdown: Detect automatically (default), Urdu, Arabic, Punjabi, Persian, Hindi, Bengali, English. Script has the same dropdown; changing it re-runs the script in that language, reusing the cleaned audio pieces (FR-26).

**FR-3 Script (changed in M23).** The first source that applies:
1. **Saved script** for this video and language (FR-14): open Script directly.
2. **YouTube captions (removed in M23).** There are no caption tracks any more: a local video has none. The §10 history about auto tracks stays as history.
3. **Speech to text** on the video's own audio track, by Groq with the user's key (FR-12a). Each segment becomes one line. Without a key the run stops with the §8 message before any audio is cut.
   - **Audio:** one FFmpeg run reads the kept file and writes 16 kHz mono FLAC pieces of 90 s: `-vn -map 0:a:0 -ac 1 -ar 16000 -sample_fmt s16 -c:a flac -f segment -segment_time 90 -reset_timestamps 1 -segment_list pieces.csv -segment_list_type csv chunk_%03d.flac`. 16 kHz mono FLAC is what Groq recommends. From M24 the voice-cleaning filters (FR-26) run first in the same command.
   - **Pieces:** 90 seconds each, so lines appear while the rest is still being written. Each piece's times are offset by its start, read from the `pieces.csv` segment list that FFmpeg writes.
   - **Dropped segments:** silence, music and bracketed tokens (`[BLANK_AUDIO]`, `(music)`, `♪`) never become lines.
   - **Groq** (`whisper-large-v3-turbo`):
     - **Request:** one multipart `POST https://api.groq.com/openai/v1/audio/transcriptions` per piece, in order, with `Authorization: Bearer <key>`. Fields: `file`, `model`, `response_format=verbose_json`, `timestamp_granularities[]=segment`, `temperature=0`, and `language=<whisperCode>` unless automatic.
     - **Lines:** segments with empty text are dropped. `no_speech_prob` is 0 on turbo (§10 Q5), so a piece whose segments are all known invented phrases ("Thank you.", "Thanks for watching.", "you", "bye") gives no lines; the same phrase beside real speech is kept.
     - **HTTP 429:** wait `retry-after` and resend when it's 60 s or less, showing "Waiting for Groq · 0:42 left"; otherwise the §8 error.
     - **HTTP 5xx or 498:** resend once after 2 s, then the §8 error.
     - **Cancel** stops before the next piece.
- **Automatic language** is inferred from the transcript text (§6.4) and shown, e.g. "Urdu (detected)".
- **No speech found** gives the §8 error.
- **Whole clip:** the script covers the whole video. There are no start and end lines to pick (FR-4).

**FR-4 Line selection (removed in M23).** The user no longer taps a start and an end line: the video is already the clip. `ClipRange` defaults to the whole video (FR-5), and every line counts as selected. The tap rules, the highlight and the Next-when-both-set rule went away. The number stays so code and history keep their references.

**FR-5 Fine-tune (two steps since M19; changed in M23).** Both steps keep their own player over the same kept video file (FR-1); Next on step 1 opens step 2, and Back returns.
- **Step 1, Video** (`/fine-tune`, "Step 3 of 5"):
  - **Opening:** the player opens the kept video file at once. Nothing is downloaded (changed in M23).
  - **Player:** pinned above the scrolling rest; play, pause, and a seek bar over the whole video, drawn as an outline with only the clip range filled; the time already played is not coloured, so it never hides the clip range. The bar and its time follow the interpolated playhead, so they move smoothly between the player's reports; a report that differs a little is blended in, a big one is a seek. The time has a fixed width with equal-width digits, so the bar never changes size. It does not stop at the clip end. "Play clip" seeks to the clip start and plays.
  - **Range:** the clip defaults to the whole video, from 0 to its length. The nudges narrow it.
  - **Nudges:** buttons move start or end by 0.5 s. A nudge is ignored when it would make the clip shorter than **3 s** or move it outside the video. Both ends can be nudged, so a clip over 60 s can be shortened from either side. A clip that starts out invalid still accepts nudges towards a valid range; only nudges that make a rule worse are ignored.
  - **Set to the playhead:** tapping the Start time, or the End time, sets it to where the video is now, rounded to 0.1 s. The nudge rules apply: a time that would leave the clip under **3 s**, or outside the video, changes nothing. It does nothing until the player is ready.
  - **Waveform:** 60 bars over the whole video, with the clip highlighted.
  - **Long-clip warning:** above 60.0 s, "Longer than 60 s. WhatsApp Status may cut it." It never blocks.
  - **Frame:** size, fill, keep in view and free crop (FR-6), and a crop that moves (FR-22). The crop window is drawn over the player.
- **Step 2, Lyrics** (`/fine-tune/lyrics`, "Step 4 of 5"): FR-21.
- **Kept:** progress is kept as it changes and continued from Recent (FR-24).

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
- **Default text:** the clip's lines' text, one per line.
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
  - **kalam:** the first 2 words of the video's name (`SourceVideo.title`, the file's display name), cleaned the same way (brackets, "Official Video"-style words and anything after a `|` removed).
  - **start / end:** the first 2 words of the caption's first line and of its last line. A one-line caption uses it for both.
  - **Words:** letters, marks and digits only, so punctuation and characters illegal in file names are dropped; joined by `_`. A part with no words is left out; with none at all the name is `reel`.
  - **Same name again:** `-2`, `-3`, … is added, so a new reel never replaces an earlier one. The name is also the reel's id in Recent, and what Save to gallery and Share show.
- **Output:** MP4 with H.264 video (`video/avc`) and AAC audio (`audio/mp4a-latm`), at the source frame rate, rendered by Media3 Transformer (§5).
- **Kept fine-tune:** a finished export deletes the kept fine-tune (FR-24).
- **Progress:** Media3's own progress.
- **Cancel:** stops the render, deletes the partial file and returns to Style.
- **Failure:** a native render error shows "Couldn't make the reel." It never hangs.

**FR-10 Save and share.** Done plays the exported file, not a still: tap to play or pause, with a progress bar that can be dragged, and back to the start at the end. The thumbnail shows until the file opens and stays if it won't play; Save and Share work either way. Save to gallery (`gal`). Android 10+ needs no permission. Android 7–9 asks once; a refusal explains and offers "Open settings". Share opens the system share sheet with the MP4 (`share_plus`).

**FR-11 Recent (changed in M23).**
- **Reels:** newest first, at most 50; the oldest is dropped and its MP4 and thumbnail deleted.
  - A row shows a thumbnail, the first caption line, duration and date.
  - Tap opens Done. Long-press offers Delete.
  - A reel whose file was deleted outside the app is skipped.
- **Saved scripts:** every saved script (FR-14) has a row as soon as the video is processed.
  - Reels and scripts share one list, newest first. Empty, it reads "Your reels and scripts will appear here."
  - A script row shows a script icon, the video's name and `Script · <language> · <video length> · <d MMM>`, where an automatic script names its detected language ("Urdu (detected)").
  - Tap opens Script without Processing. It reopens from the kept `source.<ext>`. When that file is missing, the row says "Choose or share the video again" and the §8 "Video not found" message shows.
  - Long-press offers Delete, which removes that script, its unfinished progress and the kept video.
- **Fine-tunes to continue (FR-24):** a Continue row replaces the video's script row; long-press offers Delete progress.
  - There is one row per video and requested language.

**FR-12 Settings: speech models (retired in M10, 2026-11-04).** On-device Whisper and its model downloads were removed; the number stays so code and history keep their references. The Settings screen now starts with FR-12a.

**FR-12a Settings: script writing (Groq).** The first section of Settings. Every script needs a saved key.
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
- **Privacy note** under the heading: "Writes the script. Your video's audio (cleaned, mono, 16 kHz) is sent to Groq in pieces. Tapping Fix with Groq on the Script screen also sends the lines and the title. Groq's terms apply." (FR-19; changed in M23: no link is sent) There is no switch: a saved key turns Groq on and Remove turns it off.
- **Key storage:** `flutter_secure_storage` (Android Keystore). The key is never logged, and never written into saved files, notifications or error text. It goes only to `api.groq.com`.
- **No key:** a new script stops with "Writing a script needs a free Groq key." (§8), with Settings and Back, before any audio is cut. Saved scripts need no key.

**FR-17 Real lyrics (M12; removed in M17).** Script had a "Real lyrics" button that replaced the script with time-synced lyrics from lrclib.net. M17 removed the button and the whole lyrics feature (`lib/src/features/lyrics`) to keep only Fix with Groq (FR-19). Git history before M17 has the design. Scripts already saved with source `lrclib` still reopen like any saved script.

**FR-18 Fix the script with an AI agent (M13; both buttons removed from Script in M17).** What is left is the prompt and reply parsing that FR-19 uses; nothing copies to or pastes from the clipboard any more. The rest of this section is the design they share.** For text the lyrics service lacks (a naat with verses from another poem), the user takes the script to any AI chat that can search the web and brings the corrected text back. Two buttons on Script, next to "Real lyrics", both off while a script is still being written.
- **Copy for AI:** copies one block to the clipboard: a ready prompt (video title, rules; in M23 the `https://youtu.be/<id>` link was dropped) followed by the lines as `<number> | <mm:ss.xx> | <mm:ss.xx> | <text>`. Row numbers are the line's index in the whole script + 1. The user pastes it into the chat unchanged. Snackbar: "Copied <n> lines. Paste them into ChatGPT (or any AI that can search the web), copy its reply, then tap Paste AI reply."
  - **Which lines:** the lines inside the clip (M23: nothing is picked; on Script, before any trim, that is the whole script). More than **30** lines gives the §8 message instead: trim the clip on Fine-tune, then come back. Why: a chat refuses or skims a long script (a 225-row script made ChatGPT ask for it in sections, and no rows came back), and only the clip's lines matter.
- **The prompt asks the agent to:** search for the real lyrics and never invent words; keep numbers and times and change only the text; correct rows that belong to a different poem from that poem; keep the script (no Roman, no translation); mark rows with no source by ` [?]`; never ask for fewer rows or for sections; never move a line from another part of the poem into a row (M15); reply with the rows in one code block, then list changed rows with source links.
- **Paste AI reply:** reads the clipboard and takes every row that matches the format, from anywhere in the reply (code fences, links and chatter are ignored). Citation marks such as `【1†L10-L12】` are removed from the text (M15). FR-19 does the same through Groq, with no copying.
  - **Matched by row number, text only.** Times always stay as they were, so an agent that changes a time can't move a line. Rows missing from the reply, empty, or with unknown numbers keep their text or are ignored.
  - **`[?]`:** the mark is removed from the text; the snackbar names those lines: "Updated 12 lines. The AI found no source for line 3, 7: read it before you use it."
  - **No rows found:** the §8 message, and the script is unchanged.
- **After:** the clip stays; the caption is refilled from the corrected lines only while it is still the lines' own text, so a caption the user typed or translated stays. The script is saved as the newest script (source `edited`, FR-14), so the video reopens corrected.
- **Privacy:** nothing is sent by the app. The user chooses what to paste into which chat.

**FR-19 Fix the script with Groq (M15; the §10 spike #6 said go; changed in M23).** The one fixing button on Script (since M17), **Fix with Groq**, does what Copy for AI plus Paste AI reply did, with the key from FR-12a and no clipboard. It sits alone on the row above the lines. Real lyrics, Copy for AI and Paste AI reply were removed in M17.
- **Same rules as FR-18:** the same prompt, without a link (M23), and the same lines (the clip's, or the whole script up to the row cap), the same reply handling (matched by row number, text only, times unchanged, `[?]` marks named in the snackbar) and the same result (the lines keep the range and clip, the caption is refilled only while it is still the lines' own text, the script is saved as the newest script with source `edited`).
- **Model and row cap:** `openai/gpt-oss-120b` with Groq's `browser_search` tool. At most **30** lines (the clip's, or the whole script); more gives the same §8 message, which now says to shorten the clip on the next step first. Why 30: at 54 rows the model moved lines of the poem into the wrong rows (§10 #6).
- **While it runs:** the button shows progress and a Cancel. Cancel stops waiting: the reply is ignored and nothing is saved (a request already sent still counts against the plan).
- **No key:** the button is shown, and tapping it gives the §8 "needs a free Groq key" message with Settings.
- **Privacy:** the clip's lines and the video's name go to Groq, only when the user taps this button. No link is sent (changed in M23). Say so in the FR-12a help text: the key is also used for this.
- **Limits:** a call counts against the same free plan as writing scripts. A 429 is handled as in FR-12a.

**FR-13 Offline.** Saved scripts, translation (once its ML Kit pack is downloaded) and export work without a network. Writing a new script needs one (Groq). Once a video is kept, nothing else needs a network.

**FR-14 Saved scripts (changed in M23).**
- **Key:** the video's fingerprint ID (FR-1), requested language (`auto` or a code) and source: `groq-whisper-large-v3-turbo`. (The `captions` source went with YouTube in M23.) The entry holds the transcript (with the inferred language), the source and the save date.
- **Files:** `transcripts/<videoId>/<requested>-<source>.json` in the app support directory. The video's folder also keeps `video.json` (name, length) for Recent. The video itself is kept at `sources/<videoId>/source.<ext>` (§4).
- **Same video again:** skips Processing. Script shows "Using the saved script from <d MMM> · Write it again".
- **Write it again:** runs speech to text with Groq and replaces the saved script.
- **Resume:** progress is saved after each 90-second piece in `<requested>-<source>.partial.json` and deleted when the run completes. An interrupted run resumes from the next piece. Cleaned pieces are cached per video (FR-26), so a retry doesn't clean again.
- **Retention:** 90 days after last use, at most 200 videos, least recently used dropped first. The kept video (`sources/<videoId>/`) goes with the transcripts folder it belongs to, in the same prune. A `sources/<videoId>/` folder with no `transcripts/<videoId>/` folder at all (imported, never scripted) is deleted when nothing in it has changed for 7 days. A source whose script or fine-tune draft is kept is never deleted by age.
- **Old folders:** IDs that don't start with `v_` (YouTube-keyed scripts and sources) are deleted at every start, first and alone, before the other housekeeping lists those folders.

**FR-15 Clip-only download (removed in M23).** Nothing is downloaded any more: the clip is cut from the kept local video (FR-1), and the player opens that file. The sidx index, range requests, windows, stream choice and expired-link handling all went with YouTube. The number stays so code and history keep their references. Git history before M23 has the design.

**FR-16 Background work.** Writing a script and exporting keep running when the user leaves the app or locks the phone.
- **How:** while either runs, a foreground service (type `dataSync`, from `flutter_foreground_task`) holds a partial wake lock and a Wi-Fi lock, and shows an ongoing notification. Doze and battery saving leave such a service running, network included. The work stays in the app; the service only keeps the process alive.
- **Ongoing notification:**
  - It appears from the moment work starts, so the user can leave at once.
  - It starts as "Getting the script" or "Rendering your reel" at 0 %, then shows the running step as the title and `45 % · <video title>` as the text.
  - Script steps: "Cleaning the voice" (called "Preparing the audio" in M23), "Detecting the language", "Writing the script", "Waiting for Groq", "Lining up timestamps". Export step: "Rendering your reel".
  - With both running, it shows the one that started last. The service stops when the last job ends.
- **Result notification:** posted only when the app isn't on screen; tapping it opens the app where the work left off. Cancel posts nothing.
  - Script done: "Script ready" · video title. Failed: "Script stopped" · the §8 message.
  - Export done: "Reel ready" · "Tap to save or share it." Failed: "Export stopped" · the §8 message.
- **Asking once:** the first time work starts, the app asks for notifications (Android 13+), then for exemption from battery optimisation. It never asks again on its own. M27 task 2 drops the battery-optimisation request and its Settings row.
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
- **Lines:** only the clip's lines are listed (those inside the nudged range). Lines around the clip are not shown. Every listed line reacts to a tap.
- **Player:** the reel as it will look: the video cut to the output frame (FR-6) with the crop where FR-22 puts it at that moment, and the line due on it, laid out as FR-7 says (caption position and size). Play and pause, and a seek bar over the clip only: it starts at the clip start, stops at the clip end (playing again from the end starts at the start), and has no "Play clip" button. Nothing outside the clip can be seen or reached.
- **Tap a line:**
  - **While paused:** seeks to the line's start.
  - **While playing (tap to time):** the line's start becomes the playhead. The line that was highlighted at that moment ends there, so the new highlight replaces it. The tapped line keeps its length (at least 1 s), cut at the next line's start.
  - **Ignored:** a tap earlier than the previous line's start, or on a line earlier than the one playing, so lines stay in time order.
- **Highlight:** the line whose start ≤ playhead < end is highlighted, only while it lasts; between lines nothing is, and the video shows no lyrics.
- **Edit:** a pencil opens a text field with the line's text. Saving an empty text keeps the old one. A line break becomes a space, so a line stays one caption line.
- **Reorder:** a drag handle moves a line's text to another place. Times stay where they are, so lines stay in time order: reordering swaps which text sits at which time.
- **Add:** "Add line" asks for text and inserts a line at the playhead, 2 s long (cut at the next line's start; the line it lands in ends there). When a line starts exactly at the playhead (right after tapping it while paused), that line's time is shared: the new line takes the first half, at most 2 s. The playhead must be inside the clip; Add line is off outside it.
- **Delete:** removes a line. The last line can't be deleted.
- **After an edit:** the clip stays (M23: it no longer follows the lines), and the lines inside it are the listed ones again, also after an added line. The caption is refilled from them, and the script is saved as the newest script (source `edited`, FR-14) after 1 s without edits and when the screen closes.
- **Script still being written:** once any line is edited, lines that arrive later are not added to this reel (the edited lines win).

**FR-22 Moving crop (M19).** Where the crop window sits can change while the clip plays, for Crop to fill and Free crop. Blur background and 16:9 keep the whole frame, so nothing moves.
- **What moves:** the window's position only. Its size is fixed for the clip: the preset's largest rectangle, or the free crop's width and height. It moves only along an axis where it has room (a 9:16 window in a 16:9 frame moves left and right; a 4:5 window in a 9:16 video moves up and down). With room on neither axis, the switch is hidden.
- **Anchor:** a position is an anchor `(x, y)`, each from 0 to 1 across the room the window has to move (0 = left or top, 1 = right or bottom). The frame keeps a base anchor (default 0.5, 0.5). Keep in view's Left, Center and Right set its x to 0, 0.5 and 1. A free crop's anchor is `left / (1 − width)` and `top / (1 − height)`, and its base is `freeCrop.left` and `top` themselves.
- **Keyframes:** a keyframe is a time in video time, an anchor and how it is reached: **Glide** or **Cut**.
  - **Glide:** the anchor moves in a straight line from the previous keyframe's anchor to this one, arriving at this keyframe's time.
  - **Cut:** the anchor holds the previous keyframe's value until this keyframe's time, then jumps. At exactly that time it has jumped (Dart and Kotlin agree).
  - Before the first keyframe the anchor is the first keyframe's; after the last it holds. The first keyframe's way of arriving has no effect, so its Glide and Cut choice is hidden.
  - Keyframes are kept in video time, so nudging the clip does not move them. A new keyframe's time is inside the clip, with the clip's ends rounded inwards to 0.1 s first so a snapped time never falls outside; it snaps to 0.1 s, and one within 0.25 s of another replaces it.
  - A keyframe outside the clip (after a nudge or a line edit) has no effect on the reel except as the position the crop starts from or holds. Its chip is dimmed, and it can still be deleted.
- **New script:** getting a new script (Write it again, or another language) leaves the clip, its nudges and the keyframes alone, since the clip is the whole video plus the nudges; it only replaces the lines. Nudging a clip so that a keyframe falls outside it dims that keyframe, as above. (Changed in M23: picking other lines no longer exists.)
- **Off by default:** "Move the crop during the clip" is a switch on step 1. Off, the crop is as FR-6 says. Turning it on creates a first keyframe at the clip start from the current crop. Turning it off removes the keyframes and keeps the crop where it was at the clip start: Crop to fill stores it as the base anchor, Free crop writes it into its rectangle.
- **Editing (on):**
  - **Drag:** dragging the crop window over the player moves it with the finger and writes one keyframe, at the playhead where the drag started, when the finger lifts: it replaces the one there or adds one that glides in. Keep in view is hidden while the switch is on.
  - **Chips:** a row under the player, in the pinned part, shows each keyframe's time. Tap one to jump to it. The selected keyframe offers Glide or Cut (not on the first) and Delete. Any keyframe can be deleted except the only one left.
  - **Touch:** the window can be dragged from anywhere inside it, and from a margin around its outline. A cancelled drag (a system gesture, a call) writes nothing and the window goes back to following the playhead.
  - **Free crop editor:** while the crop moves, its drag changes only the rectangle's size; keyframes place the window.
  - **Only while it can move:** the window outline and the chips show only while the crop can move (not for Blur or 16:9, or a source with no room). The switch stays while keyframes exist, so they can be turned off.
- **Changing the size or fill:** keyframes stay but have no effect while Blur or 16:9 is chosen, and come back when a crop is chosen again. Changing the free crop's size keeps them.
- **Rounding:** each keyframe's pixel rectangle is rounded as §6.3 says. The preview moves in whole pixels; the render moves in fractions of one.
- **Render:** the keyframes go to Kotlin as rectangles (§6.3.1) with their times counted from the clip start; the crop between them is computed per frame (§6.3.2). A reel with the switch off renders exactly as before.
- **Previews:**
  - Both Fine-tune steps follow the playhead frame by frame while playing (the player reports its position every 100 ms or so, so a ticker adds the time since the last report).
  - Fine-tune · Lyrics shows the moving crop and the lyric line due (FR-21), by extending `reel_preview.dart`. Style shows the crop at the clip start.
- **One decoder at a time:** when Lyrics opens, the Video step's player is released first (Lyrics opens after the frame that disposes it), and it is made again once Lyrics has slid away.
- **Height:** every player on Fine-tune is at most 260 dp high, so a vertical video leaves room for the controls; the crop outline stays on the video.
- **Frame rate:** Lyrics lays out the caption again only when the line due, the look or the size changes, not every frame.

**FR-23 Follow the person (M20; the automatic pick and "Choose for me" are replaced by FR-27 in M25).** Until M25 this section is how the app works. From M25 the face tracks, frames, smoothing and keyframe rules below are still used, but the user chooses what to follow at every scene (FR-27) and the app never picks. On Fine-tune · Video, with "Move the crop during the clip" on and the crop able to move (FR-22), a button makes the crop follow a person in the clip by writing its keyframes. Nothing is uploaded and no key is needed.
- **Button:** "Follow the person" under the switch, with the hint "Runs on your phone; nothing is uploaded."
- **Detector:** ML Kit face detection, on the phone, with the bundled model (fast mode, small faces allowed, no landmarks or contours). Pose detection is only a fallback if the spike (§10 item 7) shows faces are missed too often. Other detectors were rejected: selfie segmentation (made for close-ups) and ML Kit's object detection (it has no person class).
- **Frames:** sampled by FFmpeg from the kept video file, clip range only: 4 per second, or fewer for a long clip so there are at most 240 (never below 2 per second), as JPEG scaled to fit 640 × 640. Frame k is at video time `clip.start + k / rate`. The same run lists scene cuts (`scdet`) with their times; a build without that filter fails the run, so it is run again without it and the jump rule below covers the cuts. The frames are in a cache folder that is deleted when the run ends (after the choice, FR-25), is cancelled or fails.
- **Which face:** one person per scene, chosen once and followed to its end, not picked again in every frame. Faces in neighbouring frames (and up to 2 s apart, for a missed detection) are joined into one person when they are about the same size (area within 0.4×–2.5×) and no more than two face-widths and two face-heights apart; distance rather than overlap, because a quick mover leaves no overlap at 4 frames a second. Among the people seen in at least 90 % as many frames as the one seen longest, the one with the largest total face area is followed. So a bigger face that only passes through, or a small one always in the background, is not followed. In frames where the followed person is not seen the crop holds (Gaps). This is the pick when only one person is on screen at a time, for "Choose for me", and for scenes FR-25's choice can't reach.
- **Where the window goes:** its x centres the window on the face; its y puts the face a third of the way down the window. The anchor is the window's left over `1 − window width`, clamped to 0..1. An axis with under 1 % room keeps the base anchor.
- **Gaps:** a frame with no face holds the last anchor. Before the first face, that face's anchor is used; in a scene with no face at all, the base anchor.
- **No person:** with faces in fewer than 20 % of the frames, or in fewer than 3 frames, nothing changes and the §8 message shows.
- **Smoothing:** a centred median over 5 samples (1.25 s), restarted at each scene cut; then a dead zone: the anchor holds until the target is 0.08 of the room away.
- **Keyframes:** Ramer–Douglas–Peucker with a tolerance of 0.03 of the room. A scene cut is a Cut keyframe at the cut time. A jump of more than 0.3 of the room between neighbouring samples is a cut too, but only when no face of the frame before continues into the new frame and none comes back (or was there) within 2 s, so a bystander, or a person missed for a moment, is not a cut; and not when a detected cut is within half a second of it (so a soft cut the detector missed still cuts). A cut within half a second of the clip start gives the first keyframe the new shot's anchor. Everything else glides. Times snap to 0.1 s and stay inside the clip (FR-22); the first keyframe is at the clip start, rounded inwards to 0.1 s; keyframes are at least 0.5 s apart; at most **12**: above that the tolerance grows by 1.5× until it fits, and if many scenes still leave more, the keyframes that change the crop least are dropped (never the first), so the end of the clip is not cut off.
- **Replacing:** the result replaces the keyframes. When more than one exists, the app asks first: "Replace your crop keyframes?" with Replace and Keep.
- **After:** a snackbar "The crop follows the person (6 keyframes). Drag or tap a chip to adjust." The first chip is selected and the player seeks to the clip start. Everything stays editable as FR-22 says.
- **While it runs:** a bar, "Finding the person… 45 %", with Cancel. Sampling the frames has no progress to show, so until the first frame is looked at the bar is indeterminate and has no percent. The detector is made for the run and closed when it ends, fails or is cancelled. Cancel, leaving the step, opening Lyrics, turning "Move the crop" off, or any change of the clip, size, fill or the free crop's size stops it and changes nothing. If the user moves the crop by hand meanwhile, that wins and the result is dropped. It doesn't use the player, and takes no foreground service (about 20 s at most).
- **Several people:** when two or more are on screen at once, the user chooses (FR-25); otherwise it follows the one seen longest (the biggest among those about as long), and does not switch to another person. Replaced by FR-27 in M25: from then on every scene is asked.

**FR-25 Choose the person (M22; replaced by FR-27 in M25).** The single chooser below, its "Choose for me" button and the look-alike carry-over to other scenes are replaced by the per-scene choice of FR-27 in M25. The text stays as the history of M22. When Follow the person (FR-23) finds two or more people on screen at once, it asks whom to follow before writing keyframes.
- **People:** a person is an FR-23 face track seen in at least 3 frames and in at least 20 % of its scene's frames, so a one-frame false face is never offered.
- **Picture:** the sampled frame with the most people at once. Ties go to the largest total face area, then the earliest. It shows at most 6 people, the biggest. With fewer than 2 there is no question and FR-23 runs as before.
- **Chooser:** a bottom sheet titled "Who should the crop follow?" with the hint "Tap a face." It shows the frame at the clip's aspect ratio (at most 360 dp and 45 % of the screen's height; the sheet scrolls if it is still too tall), with an accent outline and a number on each face, numbered left to right. A tap inside a face, or within 24 dp of it, chooses the nearest face, so even a small face has a 48 dp target. A tap far from every face does nothing. Screen readers hear "Person 1", "Person 2" and so on, and can activate each. The buttons are "Choose for me" (the FR-23 pick) and "Cancel".
- **Following:** in the scene of the picture, the chosen face's track is followed even if it is not the longest. A person missed for longer than 2 s comes back as a new track; the tracks of the scene that are never seen in the same frame as the chosen one and are about the same size and place are the same person, so they are followed too. Every other scene follows the person (among those seen often enough, as above, so a one-frame false face never stands in) whose face is about the same size and place as the chosen one (FR-23's same-face test, on the track's average box), the nearest if there are several, and likewise joins that person's later or earlier stretches. With none, it uses the FR-23 pick. People can't be recognised across cuts; place and size are a guess that holds for repeated camera angles. Where the chosen person is not seen, the crop holds (FR-23 Gaps). Cuts are found exactly as in FR-23; the choice never adds or removes one.
- **Frames:** they stay in the cache folder while the sheet is open. They are deleted when the user chooses, taps Cancel, dismisses the sheet, leaves the step, or changes the clip, size, fill or free crop size.
- **Cancel or dismiss:** nothing changes, and the button comes back. A hand edit made while frames were being looked at still wins: no question is asked and nothing changes.
- **After:** the same snackbar as FR-23.

**FR-24 Continue a fine-tune later (M21; changed in M23).** Work on Fine-tune is kept on the phone as it changes, so the user can leave and carry on from Recent, hours or days later. There is no Save button.
- **What is kept:** the clip's start and end (FR-5; the picked lines of FR-4 went in M23), the frame (size, fill, base anchor, free crop and the moving crop's keyframes, FR-6 and FR-22), the caption settings (FR-7) and whether lines were edited (FR-21).
  - Neither the script nor the video is copied. The kept fine-tune names its saved script by video and requested language (FR-14), and its video by the fingerprint ID; the video is the kept `sources/<videoId>/source.<ext>` (FR-1). The source is `edited` when lines were edited; otherwise it is the newest script, the one FR-14 reopens.
  - It also keeps a fingerprint of the script's lines from the first line through the last line of the clip (a 32-bit FNV-1a hash of each line's start, end and text, stable across runs). That tells a changed script apart, and lines added later (a script still being written) don't count.
- **When:** 1 s after the last change while Fine-tune · Video is open or under a later step (Lyrics, Style, Export). Also at once when Fine-tune · Video closes (Back included) or the app goes to the background.
  - A change is anything that changes the reel: a nudge, an edge set to the playhead, size, fill, crop, a keyframe, a line edit, a caption setting.
  - A fine-tune equal to the last one written is not written again, unless its file was deleted since. Continuing a fine-tune counts as writing it, so leaving Fine-tune without a change keeps its date.
  - A failed write, whatever its cause, is ignored and never stops later saves, because the work is still in the app.
- **One per video and language:** a new fine-tune of the same video and requested language replaces the kept one. Back to Script leaves it as it was.
- **File:** `transcripts/<videoId>/draft-<requested>.json` in app support, beside the scripts. It is written as `.part` and renamed, and carries `version` 1.
  - A file that can't be read, or has a newer version, is ignored and stays on disk. Its video's script row shows instead.
  - Saving counts as a use of the video. The file goes with the video's folder under FR-14's retention (90 days after last use, at most 200 videos).
- **Recent (FR-11):** a kept fine-tune has a row with a tune icon, the video's name, `Fine-tune · <clip length> · <d MMM>` (e.g. `18.5 s`, the date of the last save) and "Continue" on the right.
  - It replaces the script row of the same video and language, so the video shows once. It sorts by its last save among the reels and scripts.
  - **Tap, script found and still fitting:** opens Fine-tune · Video with everything as it was, and Back shows Script. Nothing is downloaded; the player opens the kept file.
  - **Tap, kept video missing** (the folder was cleaned or the file deleted): the §8 message "Video not found, choose it again" shows, and Choose a video opens. The script and the draft stay.
  - **Tap, script still being written:** the lines Groq had written so far count as the script when they hold the clip's lines (the same fingerprint check). It opens as the first case, and the run carries on and adds the rest.
  - **Tap, script gone** (no saved script for the video and language, and no unfinished progress that holds the clip's lines): opens Processing, which writes or resumes the script (FR-3, FR-14), then Script with the snackbar "This fine-tune's script had to be written again. Check the clip's start and end; the size and caption style are kept."
  - **Tap, script changed** (the fingerprint differs, the clip's lines run past the script's end, or the clip runs past the video's end; e.g. after Write it again): opens Script with the current script and the snackbar "The script changed since this fine-tune was saved. Check the clip's start and end; the size and caption style are kept."
  - In both of those cases the kept fine-tune is deleted. What carries over: size, fill, the crop stopped where it was at the old clip start, and the caption's position and size. The clip's nudges and the caption text do not.
  - **Long-press:** offers "Delete progress". It deletes only the kept fine-tune, and the video's script row shows again.
- **Export:** a finished export (the reel is in Recent, FR-9) deletes the kept fine-tune. Going back from Done and changing something keeps a new one.
- **Not kept:** the per-scene choices of FR-27 are written into the crop's keyframes, so the keyframes are kept; the scene questions themselves are not. Also anything before Fine-tune opens, the playhead, and the selected keyframe chip.

**FR-26 Clean the voice (M24).** Before Groq hears the audio, FFmpeg cleans it, so the lyrics are more accurate. Nothing is uploaded for this and no key is needed.
- **Filters:** the bundled FFmpeg's built-in filters only, all present in `ffmpeg-kit-min` 1.0.3. The defaults are `highpass=f=80,lowpass=f=7500,afftdn=nr=12:nf=-30:tn=1,dynaudnorm=f=200:g=11:p=0.9`: cut rumble below 80 Hz, cut hiss above 7.5 kHz, reduce steady noise (hum, hiss, hall noise), then even out the loudness. The values are defaults until §10 item 8 tunes them.
- **What it can't do:** filters cannot separate a voice from a harmonium or a daf. They share the voice's band, so they stay in the audio. Say so plainly in the help text, and never promise that instruments are removed.
- **Where:** `-af <chain>` in the piece run of FR-3, before the FLAC encode: the same command cuts, cleans and writes the 90 s pieces. The clip's own audio in the render is never changed; only what Groq hears is cleaned.
- **Progress:** Processing shows "Cleaning the voice" (also the notification step, FR-16).
- **Reuse:** cleaned pieces are kept in the video's folder, in `pieces_<seconds>_<8 hex of the filter chain's SHA-256>`, so a retry or another language doesn't clean again and a changed chain never reuses old pieces. A `finished` marker, written after FFmpeg returns, makes a cut reusable (FFmpeg appends to `pieces.csv` as it goes, so the list alone can't tell). Other `pieces_*` folders and unfinished cuts are deleted. They go with the video's folder.

**FR-27 Choose what to follow in each scene (M25).** Replaces FR-23's automatic pick and FR-25's single chooser. With "Move the crop during the clip" on and the crop able to move (FR-22), "Follow the person" becomes a walk through the clip's scenes. The app never assumes: at every scene the user picks what to keep in frame. Nothing is uploaded and no key is needed.
- **Scenes:** the clip's scenes are found as in FR-23 (scene cuts, plus the jump rule). Each scene is asked once, in order, even with one face on screen, and even with none.
- **Choices:** at each scene the user picks one of three:
  - a **face** (FR-23's face tracks and the ML Kit detector);
  - a **body** (a person box; offered only if the §10 item 7 spike chose a body detector);
  - a **fixed spot**, a point the user taps, held for the whole scene.
- **Never chosen for the user:** there is no "Choose for me", no automatic pick, and no carry-over of a choice to another scene by look-alike.
- **Picture:** each scene shows its fullest frame (the one with the most faces, then the biggest), at the clip's aspect ratio.
- **Sheet:** a bottom sheet per scene.
  - Title "Scene 2 of 5 · 0:07–0:12". Hint "Tap a face, a body, or the spot to keep in frame."
  - A tap within 24 dp of a face picks that face (the nearest). A tap inside a body box picks that body. A tap anywhere else picks that spot, and a pin shows where before the next scene. A pick moves on to the next scene; the last pick ends the walk.
  - Buttons: "Back" (returns to the earlier scene to change its answer; the choices already given are kept) and "Cancel" (stops; nothing changes).
  - **Screen readers:** "Person 1", "Body 1", and a "Keep the centre" action that picks the centre spot.
  - The sheet pops with its result and the controller acts after the await, so a double pop can't happen.
- **Keyframes:** a face or a body is followed as in FR-23 (anchor, smoothing, dead zone, simplification) within its scene only. A body's anchor is its box's centre, in its upper third. A spot is a constant anchor with a **Cut** keyframe at the scene start. A scene's start is a Cut either way. The 12-keyframe cap and the 0.5 s spacing of FR-23 still apply. The cap keeps every scene's Cut keyframe first (the user chose each one); other keyframes are dropped before any Cut. If the clip has more than 12 scenes, the first 12 are kept and the rest hold the last anchor, and the sheet warns before asking: "This clip has more than 12 scenes. The crop follows the first 12."
- **Frames:** they stay in the cache folder while the sheet is open, and are deleted when the user finishes, taps Cancel, dismisses the sheet, leaves the step, or changes the clip, size, fill or free crop size.
- **Cancel or dismiss:** nothing changes. A hand edit made while frames were being looked at still wins.
- **After:** the snackbar "The crop follows your choices (6 keyframes). Drag or tap a chip to adjust." Everything stays editable as FR-22 says.
- **Replacing:** as FR-23: when more than one keyframe exists, "Replace your crop keyframes?" with Replace and Keep, asked before the first scene.

## 4. Non-functional requirements

- **Platforms:** Android (minSdk 24) and iOS (deployment target 15.5, needed by ML Kit translation). iOS is built in M26. Store builds become possible (§9, M27).
- **Responsiveness:** transcription, FFmpeg, waveform peaks and file I/O never block the UI isolate. Every long step shows progress and can be cancelled.
- **Storage (changed in M23):**
  - Kept videos: `sources/<videoId>/source.<ext>` in app support, the file the user shared or picked, kept once (FR-1). It stays while its script or fine-tune is kept (FR-14 retention) and is deleted with them; imported but never scripted, it is deleted after 7 days. Saving a video's title counts as a use, so a video just imported isn't pruned. Cleaned audio pieces (FR-26) are cached beside it.
  - Saved scripts: `transcripts/` in app support (FR-14).
  - Unfinished fine-tunes: `draft-<requested>.json` beside the scripts in `transcripts/<videoId>/` (FR-24); they go with the folder.
  - Exports: `reels/` in app documents.
  - Copies and other files are written to `.part` files and renamed when complete.
  - Every start deletes folders whose name isn't a fingerprint ID (`v_` and 16 hex digits): old YouTube data.
- **Data use:** nothing is downloaded. The only uploads are the cleaned script audio pieces (about 16 kHz mono FLAC) and the Fix with Groq lines, both to Groq.
- **Privacy:** nothing leaves the device except language-pack downloads and, to write a script (FR-12a), audio pieces sent to Groq with the user's key, and, when the user taps Fix with Groq (FR-19), the clip's lines and the video's name. The video itself never leaves the phone.

## 5. Architecture

- **Folders:** feature-first, `lib/src/features/<feature>/{domain,data,application,presentation}`, with a layer only when it has code.
- **State:** Riverpod 3 (`Notifier`/`NotifierProvider`). The reel in progress is one immutable `ReelDraft` in `reelDraftProvider`. Changing the transcript replaces the lines and clears per-line caption edits (FR-21); the clip, its nudges and the crop keyframes stay.
- **Services:** small interfaces exposed as providers, so fakes can replace them in tests: `VideoSource` (from M23 the `LocalVideoImporter`, with `IncomingVideoSource` for shares), `Transcriber`, `CaptionTranslator`, `Renderer`, `RecentReelsRepository`, `BackgroundWorkPlatform`.
- **Speech to text:** `GroqTranscriber` (FR-12a) sends the pieces one by one and emits per-piece progress and lines.
- **Navigation:** `go_router`, with route paths in `AppRoutes`.
- **Rendering (Android):** Media3 Transformer behind the Kotlin channels `status_studio/render` (`start`, `cancel`) and `status_studio/render/events`.
  - Input: the clip file plus one transparent PNG, exactly the output size, holding caption and branding drawn by Flutter. It is applied last.
  - Media3 trims, crops or blurs, scales, overlays and encodes on the phone's hardware.
  - Preview and export share `cropRectFor` and `layoutOverlay`.
  - iOS (from M26): AVFoundation behind the same channels and the same spec map, with a custom `AVVideoCompositing` that crops each frame from the same `MovingCrop.ndcRectAt` maths.
- **FFmpeg (changed in M23):** audio cleaning and splitting for Groq (FR-26), thumbnails, probing (FFprobe: duration, size, rotation, audio track) and sampling small JPEG frames for Follow the person (FR-23, FR-27). The mjpeg encoder is there; the PNG encoder is not (`--disable-zlib`). The bundled build can't encode H.264 or read https (§10 Q1).

### Package map

| Need | Package | Notes |
|---|---|---|
| Video in (M23) | our own `status_studio/video_in` channel on Android (`receive_sharing_intent` is for M26 to reconsider on iOS), `image_picker` | Share-in; `pickVideo` uses the Android Photo Picker and PHPicker, no permission. Replaced yt-dlp (removed in M23) |
| Speech to text (cloud) | `dart:io` `HttpClient` | Hand-built multipart to `api.groq.com`; `GET /openai/v1/models` checks a key |
| Secret storage | `flutter_secure_storage` | The Groq key only |
| FFmpeg | `ffmpeg_kit_flutter_new_min` ^2.x | The only FFmpeg (LGPL); no mediacodec, no TLS, no libx264 |
| Final render (Android; iOS from M26) | Media3 `transformer`, `effect`, `common` 1.11.1 | `Transformer`, `ClippingConfiguration`, `Crop`, `Presentation`, `GaussianBlurWithFrameOverlaid`, `OverlayEffect` + `BitmapOverlay`. iOS: AVFoundation, `AVAssetWriter` and Core Image |
| Downloads (removed in M23) | | Nothing is downloaded any more. `HttpClient` stays only for Groq and the key check |
| Translation | `google_mlkit_translation` | `OnDeviceTranslator`, `OnDeviceTranslatorModelManager` |
| Preview / gallery / share | `video_player` / `gal` / `share_plus` | |
| Key-value storage | `shared_preferences` | `recentReels` (JSON) |
| Background work | `flutter_foreground_task`, `flutter_local_notifications` | No TaskHandler: the work stays in the app's isolate. Notifications need core library desugaring |

### Engineering rules

- **No code generation:** `copyWith`, `==` and `hashCode` are written by hand.
- **Copy:** literal from this document and the canvas. The app is general-purpose: never name a content type (naat, bayan…) in UI or code.
- **Import boundaries:**
  - Only `LocalVideoImporter` reads shared or picked files and copies them into app storage (M23). No yt-dlp or YouTube code remains.
  - Only `lib/src/core/ffmpeg/` imports FFmpeg Kit.
  - Only the Kotlin `render/` package imports Media3, and only the Swift render folder imports AVFoundation (M26).
  - The background plugins are reached only through `BackgroundWorkPlatform`.
- **Errors are typed:** `VideoUnreadableException` (no audio track, or unreadable, M23), `KeptVideoMissingException` (M23), `OfflineException`, `InsufficientStorageException`, `NoGroqKeyException`, `NoSpeechFoundException`, and so on. Screens map them to §8. A failing background-platform call is reported with `FlutterError.reportError` and never stops the work.
- **New dependencies:** maintained and widely downloaded on pub.dev. Add them with `fvm flutter pub add`.
- **Tests never touch the network or platform:**
  - Fake the incoming-video source, the picker, Groq and FFmpeg. Groq requests run against a loopback `HttpServer`.
  - Override `backgroundWorkPlatformProvider` with `FakeBackgroundWorkPlatform`.

## 6. Domain model and rules

### 6.1 Types (Dart)

```dart
class SourceVideo { String videoId; String title; Duration duration; } // M23: videoId is the fingerprint v_<16 hex>; title is the display name; no channel
enum ScriptLanguage { auto, urdu, arabic, punjabi, persian, hindi, bengali, english } // whisperCode ('auto','ur',…) and label
class TranscriptLine { int index; String text; Duration start; Duration end; }
class Transcript { String languageCode; List<TranscriptLine> lines; }
sealed class LineSelection { NoSelection, StartSelected(int start), RangeSelected(int start, int end) } // M23: always the whole script (FR-4 removed)
class ClipRange { Duration start; Duration end; } // M23: defaults to 0..duration
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
class SavedTranscript { Transcript transcript; String source; DateTime savedAt; } // groq-whisper-large-v3-turbo (captions removed in M23) 
class SavedScript { SourceVideo video; ScriptLanguage language; SavedTranscript saved; } // a Recent row
class FineTuneDraft { TranscriptKey script; RangeSelected selection; ClipRange clip; FrameSettings frame; CaptionSettings caption; bool linesEdited; int scriptFingerprint; DateTime savedAt; } // FR-24; the script itself is not copied
class SavedFineTune { SourceVideo video; FineTuneDraft draft; } // a Recent row (FR-24)
enum SpeechEngine { onDevice, groq }
class CloudTranscriptionSettings { bool enabled; bool keyChecked; } // the key itself lives only in secure storage
class ClipWindow { Duration start; Duration end; }                  // M23: the whole video (FR-15 removed)
class ClipSource { File file; Duration offset; ClipWindow window; } // M23: the kept file, offset 0
sealed class SceneChoice { FollowFace(track), FollowBody(track), HoldSpot(anchor) } // FR-27, M25
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
| Invalid link (removed in M23: no links) | Source | That doesn't look like a YouTube link. | Edit |
| Video unavailable, private, age-restricted or live (removed in M23) | Processing | This video can't be downloaded. | Back |
| No network during download (removed in M23: nothing is downloaded; offline errors remain for Groq) | Processing | You're offline. Connect and try again. | Retry, Back |
| yt-dlp can't read the video, even after updating (removed in M23) | Source / Processing | Couldn't read this video from YouTube. Try again later. | Retry, Back |
| The video has no audio track, or can't be read (M23) | Source / Processing | Can't read this video. | Choose another video, Back |
| The kept source file is missing (M23) | Recent / Continue | Video not found, choose it again. | Choose a video, Back |
| No Groq key saved | Processing | Writing a script needs a free Groq key. | Settings, Back |
| Groq rejected the key (401/403) | Processing / Script | Groq didn't accept your API key. | Settings, Back |
| Groq limit (429, wait over 60 s) | Processing / Script | Groq's free limit is used up for now. Try again in <n> min. | Back |
| Groq failed (other error, or 5xx/498 twice) | Processing | Groq couldn't write this script. | Retry, Back |
| Network lost while Groq writes | Processing / Script | You're offline. Connect and try again. | Retry, Back |
| Key check failed | Settings | Groq didn't accept this key. | Edit |
| No speech found | Processing | No speech found in this video. | Try another language, Back |
| Translation pack missing and offline | Style | English needs a one-time download. | Retry |
| Gallery access refused | Done | Allow Photos access in Settings to save reels. | Open settings |
| Render failed | Export | Couldn't make the reel. | Retry, Back |
| More than 30 lines for Fix with Groq (the 60-line copy path went in M17) | Script | Too many lines for an AI to check. Shorten the clip on the next step first. | (snackbar) |
| No Groq key, Fix with Groq | Script | Fixing a script needs a free Groq key. | Settings (snackbar action) |
| Groq failed while fixing (other error, or 5xx/498 twice) | Script | Groq couldn't fix this script. | (snackbar) |
| Groq's reply to Fix with Groq has no script rows | Script | Groq's reply had no script lines. Try again. | (snackbar) |
| No person found in the clip (until M25; FR-27 asks at every scene and has no such error) | Fine-tune · Video | No person found in this clip. The crop stays where it is. | (snackbar) |
| A kept fine-tune's script is gone | Script | This fine-tune's script had to be written again. Check the clip's start and end; the size and caption style are kept. | (snackbar) |
| A kept fine-tune's script changed | Script | The script changed since this fine-tune was saved. Check the clip's start and end; the size and caption style are kept. | (snackbar) |
| Following the person failed (frames, decoding or detector) | Fine-tune · Video | Couldn't follow the person. Try again. | (snackbar) |
| Not enough storage | copying a video, cleaning audio or export | Not enough space on your phone. | Back |

Each error is a typed exception from the data layer. Screens map them to these messages, and nothing returns `null` or a sentinel.

## 9. Decisions

| Decision | Choice and why |
|---|---|
| Scope | General-purpose: any video, any language. Since 2026-11-05 (M23) the input is a local video the user already trimmed, shared in or picked from the gallery. No content-type picker, no automatic segment finding |
| Distribution (changed in M23) | YouTube access is gone, and with it the "keeps the app off the stores" note. Nothing downloads third-party media or runs code fetched at runtime (yt-dlp updated itself weekly), so Play Store and App Store builds become possible. The policy work is listed in M27 (§12): consent before the first Groq upload, dropping the battery-optimisation request, privacy policy, store answers, listing rules and release builds |
| YouTube access (removed in M23) | Was yt-dlp on the phone plus Dart downloads (§10 Q4). Removed with the pivot; the history stays in §10 |
| Speech to text | Groq `whisper-large-v3-turbo` only. On-device Whisper (`whisper_ggml`) was dropped in M10: medium q5_0 ran at 0.2× real time on a Redmi Note 11 (Snapdragon 680), and small was only 1.5× on a Pixel 6a (§10 Q2) |
| Cloud transcription | Groq `whisper-large-v3-turbo` with the user's own key (FR-12a), because the phone is too slow (§10 Q2). A key shipped in the APK could be extracted, and the app has no server. Groq is fast, multilingual and cheap ($0.04 per audio hour, with a free plan). Pieces go as 16 kHz mono FLAC (M23; they were stream-copied `.m4a` before), cleaned first (FR-26). Groq's `url` input isn't used: the audio is a local file |
| FFmpeg | `ffmpeg_kit_flutter_new_min` only (LGPL). The full GPL build would duplicate native libraries and make the app GPL |
| Renderer | Media3 Transformer on Android (hardware H.264), because the bundled FFmpeg can't encode H.264; AVFoundation on iOS from M26, the same spec over the same channel |
| Captions and branding | Drawn by Flutter to one PNG and overlaid by Media3 (AVFoundation on iOS). Other text engines break Nastaliq letter joining |
| Data saving (changed in M23) | No media downloads. The only uploads are the cleaned 16 kHz mono script audio and the Fix with Groq lines |
| Reuse | Scripts saved per video fingerprint, language and source for 90 days; resume per 90-second piece; cleaned pieces cached per video |
| Background work | One foreground service kept by Dart. The work already runs in the app process, so keeping the process alive is enough. Packages rather than hand-written Kotlin, so the notification shows the percent as text, not a bar |
| Name, logo, IDs | Status Studio; Trim; `com.hotmail.arehmananis.statusstudio` |
| Fonts | Inter (UI), Noto Nastaliq Urdu, Noto Naskh Arabic (OFL) |
| Signing | Upload keystore and `key.properties` committed, because the repo is private |
| Crop subject (M25) | The user chooses a face, a body or a fixed spot at every scene (FR-27). The app never assumes, so automatic follow and look-alike carry-over are dropped |

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
7. **Person detection on the phone (M20 task 1; extended to bodies in M25 task 1; device only, not yet run).** Question: can ML Kit face detection find the person in a clip fast enough and often enough on a Redmi Note 11 (profile build) to make Follow the person (FR-23) worth shipping? Clips: three of 30 s, a naat singer facing the camera, a wide shot with two people, and calligraphy only. Sampled at 4 fps, long side 640.
   - **Measure:** frame extraction time, detector ms per frame, recall against a hand count, false-positive frames, arm64 APK growth.
   - **Go** if all hold: ≤ 15 s in total per 30 s clip, recall ≥ 80 %, false positives ≤ 5 % (the calligraphy clip gives no keyframes), APK growth ≤ 8 MB. If recall is under 80 %, try face plus pose; if that still misses, no-go.
   - **Bodies (M25 task 1, added 2026-11-05):** FR-27 may offer a body as well as a face. ML Kit pose detection finds only one person per frame, so it can't offer several bodies. A COCO person detector, such as EfficientDet-Lite0 via `tflite_flutter` (about 4.4 MB), finds several. Measure the same things on the Redmi Note 11 (time per frame, recall, false positives, APK growth) for faces plus bodies, and record which detector to use, or no-go for bodies. Faces and spots don't wait for this: only body choices (M25 task 5) do.
   - **Not checked yet:** which face-detection plugin version resolves against `google_mlkit_commons` ^0.13.0, whether AV1 clips decode in software, whether `scdet` with `metadata=file=` behaves as FR-23 assumes (if the build lacks the filter the run is repeated without it; the jump rule applies either way).
8. **Voice cleaning (M24 task 3, desktop plus device; tool built, run pending).** Question: do the FFmpeg filters of FR-26 make Groq's lyrics more accurate? The defaults in FR-26 stand until this check tunes them.
   - **Clip:** `assets/videos/Wasif Attari qadri - Arshe Haq He … FAISALABAD.mp4` (69 s, 1080p H.264, AAC stereo 44.1 kHz). `assets/videos/` is in `.gitignore` and the file is never declared in `pubspec.yaml`, so it stays out of the repo and the app.
   - **Expected lyrics:** 10 lines, committed as `tool/voice_check/arshe-haq-expected.txt`. They start with "دیکھ لے دامن خیرات کیا ان سے ملا" and end with "بٹتی ہے کونین میں نعمت رسول اللہ کی", written twice.
   - **Tool:** `tool/voice_check.dart`, run with `fvm dart run tool/voice_check.dart <video> <expected.txt>`. It builds the FFmpeg arguments with the app's own `audio_arguments.dart`, runs them with the Mac's Homebrew `ffmpeg` (its version is recorded next to the bundled 7.1), sends the pieces to Groq `whisper-large-v3-turbo`, and reads the key from `GROQ_API_KEY`. The key is never written to a file or printed. Network access stays in `tool/`; app tests never touch it.
   - **Variants:** raw audio with automatic language; cleaned audio with automatic language; cleaned audio with language `ur`; plus any filter values being tuned.
   - **Score:** character error rate (CER) against the expected text, after normalising both: lower case; remove harakat (U+064B–065F, U+0670), tatweel and ZWNJ; map ي ى ی to ی, ك ک to ک, ہ ه ة to ه, and أ إ آ ٱ to ا; collapse whitespace; join the lines. Lines missing compared with the expected text (a repeat Whisper dropped) are listed separately.
   - **Pass:** cleaned CER below raw CER, and at most 15 %. If 15 % is out of reach with filters alone, record the best result and stop. Don't tune against this one clip until it overfits: spot-check the chosen values on one more clip.
   - **Result:** pending: `GROQ_API_KEY` was not set when M24 was built (task 3). Normalising also drops punctuation and symbols (Whisper adds `،` and `.`), and spaces count as characters. A line is "missing" when no stretch of the text after the previous line's match is within 40 % edit distance of it. The table and the chosen values go here. Filters can't separate the voice from harmonium or daf (FR-26), so a mehfil with instruments may not reach 15 %.
9. **First iOS build (M26 task 1, not yet run).** Question: does the app and every plugin build for iOS? Deployment target 15.5 (ML Kit), bundle ID `com.hotmail.arehmananis.statusstudio`; `pod install`, then `fvm flutter build ios --no-codesign`. Check that these resolve: ffmpeg_kit min, both ML Kit packages, `tflite_flutter` (if M25 chose it), gal, flutter_secure_storage, flutter_local_notifications, image_picker and the share package. Record the IPA size and any plugin that fails. ML Kit has no arm64 simulator support, so face detection can only be checked on a device (§14). The ffmpeg_kit iOS podspec also excludes arm64 from simulator builds, so simulator runs need x86_64 (Rosetta); device builds are unaffected.


## 11. Out of scope for v1

- iOS release and Play Store or App Store builds were out of scope for v1. Since 2026-11-05 they are planned: iOS in M26, store readiness in M27.
- Local-file or share-into-app input was out of scope; it is now the only input (M23).
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
| M19 Fine-tune steps | Fine-tune in two steps: Video (nudges, size, crop that can move) and Lyrics (the clip's lines, timing, video with the lyrics on it) (FR-5, FR-21, FR-22) | Done, branch `m19-fine-tune-steps` (stacked on M18); device check pending |
| M20 Follow the person | A button that makes the moving crop follow a person, by on-device face detection (FR-23) | Built, branch `m20-follow-subject` (stacked on M19); the spike (§10 item 7) and the device checks are pending, so whether to ship it is undecided |
| M21 Continue later | Fine-tune is kept as it changes and continued from Recent (FR-24) | Built, branch `m21-fine-tune-drafts` (stacked on M20); device checks pending (§14) |
| M22 Choose the person | Tap a face to choose whom Follow the person follows (FR-25) | Built, branch `m22-choose-person` (stacked on M20); device check pending |
| M23 Local video in | Share or pick a trimmed video instead of a YouTube link; whole-video clip; YouTube removed (FR-1, FR-3, FR-4, FR-5, FR-14, FR-15) | Built and reviewed, branch `m23-local-video` (from `dev`), pushed, not merged; tests not run (the user tests from task 5, stale ones listed in §12); device checks pending (§14) |
| M24 Clean voice | FFmpeg filters clean the audio before Groq (FR-26, §10 item 8) | Built and reviewed, branch `m24-clean-voice` (stacked on M23), pushed, not merged; the lyrics check (§10 item 8) is built but not run: it waits for `GROQ_API_KEY`; tests not run |
| M25 Choose per scene | At every scene the user picks a face, a body or a fixed spot (FR-27) | Planned, branch `m25-choose-per-scene` (stacked on M24) |
| M26 iOS | iOS build, Share Extension, AVFoundation renderer (§10 item 9) | Planned, branch `m26-ios` (stacked on M25) |
| M27 Store readiness | Consent, privacy policy, store answers and release builds for Play and the App Store (§9) | Planned, branch `m27-store-readiness` (stacked on M26) |

**Pending ideas (2026-11-05):** "Share from YouTube" and "Follow automatically" are dropped (automatic follow contradicts "do not assume", FR-27). "Search the script" is a later idea (FR-28 reserved, not planned).

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
- [x] **5. Two steps.** Routes, step labels for all screens ("of 5") and buttons; the Video step keeps the player, nudges and warnings and takes size, fill and crop from Style; the Lyrics step takes the lines (only the clip's); Style keeps the caption.
- [x] **6. Moving crop on Video.** The crop window over the player, with the switch (hidden without room); drag writes one keyframe on release; chips in the pinned part with Glide, Cut and Delete; a ticker for the playhead.
- [x] **7. Lyrics preview.** `ReelPreview` follows the playhead (moving crop and the due cue); the Video step's player is released while Lyrics is open.
- [x] **9. Set an edge to the playhead (request 2026-11-04).** Tapping Start or End sets it to the playhead under the nudge rules.
- [x] **8. Docs and review.** §13, §14, §15; reviewer pass (Opus; eight findings, all fixed except a test for a cancelled drag); push.

### M20 tasks (branch `m20-follow-subject`)

Request, 2026-11-04: move the crop by object detection; the subject is a person or body. The plan was written by an Opus subagent first (its choices are in FR-23). Each task: test first, tick it, commit. Task 1 needs the phone and cannot run here.

- [ ] **1. Spike (device).** §10 item 7, on a scratch branch that is never merged. Pending: the phone is not available in this session.
- [x] **2. Frame arguments.** `lib/src/core/ffmpeg/frame_arguments.dart`: the sampling arguments (file time = video time minus the clip file's offset) and the scene-cut parser.
- [x] **3. Subject path (domain).** `followSubject`: boxes to anchors, smoothing, dead zone, simplification, cuts, the 12-keyframe cap, `NoSubjectFoundException`; with the cases in §13.
- [x] **4. Apply.** `ReelDraft.withFollowedCrop` and the controller method.
- [x] **5. Extractor and detector.** `FrameExtractor` (FFmpeg) and `SubjectDetector` (ML Kit) behind interfaces; the dependency; cancel the FFmpeg run by its own session, not all sessions.
- [x] **6. Controller.** `FollowSubjectController`: progress, cancel, cancel on change, clean-up, errors, with fakes.
- [x] **7. UI.** The button, progress, Cancel, the replace question and the snackbars.
- [x] **8. Docs and review.** §13, §14, §12 status; reviewer pass (Opus; six findings, all fixed); push. CLAUDE.md's FFmpeg line still needs "and frame sampling" (left for the user to approve).

### M21 tasks (branch `m21-fine-tune-drafts`)

Request, 2026-11-04: save Fine-tune progress and continue later. The plan was written by an Opus subagent (its choices are in FR-24). Each task: test first, tick it, commit.

- [x] **1. Spec.** FR-24 and the edits it needs in §2, FR-5, FR-9, FR-11, §4, §6.1, §8, §12.
- [x] **2. Draft type and JSON (domain).** `FineTuneDraft`, `SavedFineTune`; `fineTuneDraftToJson` and `fineTuneDraftFromJson` (version 1; a damaged or newer file throws `FormatException`).
- [x] **3. Draft rules (domain).** `canKeep`, `FineTuneDraft.of`, `fits`, `restoredOnto`, `startOver`, and the stable script fingerprint.
- [x] **4. Shared JSON files and script-store additions.** `core/json_files.dart` (atomic write) moved out of `TranscriptStore`; `loadFromSource`, `loadVideo`, `markUsed`.
- [x] **5. Draft store (data).** `FineTuneDraftStore`: save, list (skips unreadable), delete; provider.
- [x] **6. Saver and list (application).** `FineTuneDraftSaver` (serial, no repeat writes, discard after export) and `fineTuneDraftsProvider`.
- [x] **7. Wiring the saves.** Fine-tune screen (1 s debounce, close, background), Lyrics background flush, Export discards; test helpers and default overrides.
- [x] **8. Resumer (application).** `FineTuneResumer`: Ready, ScriptGone, ScriptChanged; `ReelDraftController.restore`.
- [x] **9. Recent merge (domain).** `recentEntries`: a fine-tune replaces its script row.
- [x] **10. Home rows.** Continue row, long-press Delete progress.
- [x] **11. Continue and the Script notice.** Tap paths and the snackbar on Script.
- [x] **12. Docs and review.** §13, §14, §12 status; reviewer pass (Opus; eight findings, all fixed: unfinished scripts continue, saver survives errors and outside deletes, export reads its saver before awaiting, Continue ignores a second tap, edited-lines shield resets on a new script); push. CLAUDE.md's "Reuse earlier work" bullet could gain "Fine-tune progress is kept per video and language (FR-24)" (left for the user to approve).

### M22 tasks (branch `m22-choose-person`)

Request, 2026-11-04: the followed person is sometimes the wrong one; "Tap to choose person". The plan was written by an Opus subagent first (its choices are in FR-25). Each task: test first, tick it, commit.

- [x] **1. Docs.** FR-25; the FR-23, §8 and §11 edits; the §12 row; §13; §14.
- [x] **2. Face tracks out (refactor, no behaviour change).** `lib/src/features/style/domain/face_tracks.dart`: `FaceTrack`, `trackFaces` and `mostProminent` moved from `subject_path.dart` and made public; `FaceTrack.typicalFace` added. `subject_path.dart`: a public `SubjectScene` (with `firstIndex`) and `scenesOf`. The existing `subject_path_test.dart` passes unchanged.
- [x] **3. Choosable people (domain).** `lib/src/features/style/domain/person_choice.dart`: `PersonChoice`, `choosablePeople`.
- [x] **4. Follow the chosen person (domain).** `followPerson` in `subject_path.dart`, with the same-place rule.
- [x] **5. Controller.** `FollowChoosing`, `choose`, `chooseForMe`, who owns the frames, and how cancel, reset, dispose and changes behave while choosing.
- [x] **6. Chooser sheet.** `lib/src/features/clip/presentation/person_chooser_sheet.dart`; `FollowSubjectSection` keeps the button off while choosing.
- [x] **7. Wire into Fine-tune.** `fine_tune_screen.dart` opens the sheet on `FollowChoosing`, and a dismissal cancels.
- [x] **8. Docs and review.** Tick the tasks, set the §12 status, reviewer pass, push. The Opus review found four things, all fixed test first: a one-frame false face could stand for the person in another scene; a person missed for over 2 s was followed only until then (and fixing that showed that a big move right after a hold was dropped by the half-second keyframe spacing, so the crop never left the old place; such a move is now kept, half a second after the hold); the sheet overflowed on short screens; the picture gave screen readers a tap at (0, 0). Left as is, as unconfirmed and probably harmless: a double tap during the sheet's closing animation.

### M23 tasks (branch `m23-local-video`)

Request, 2026-11-05: the user now trims the video in another app and brings the clip into Status Studio, so YouTube is dropped entirely and the script covers the whole clip. Execution model: for tasks 0–4 Sonnet wrote each task, Opus reviewed each commit's diff against the spec and CLAUDE.md, and Sonnet fixed confirmed findings. From task 5 one agent writes and fixes the code itself (changed 2026-11-05: a fresh agent per step cost too much), and one Opus review follows every commit, fixes included, before the next task; Opus also reviews the whole branch before the push. From task 5 the user writes and runs the tests (changed 2026-11-05): the agent changes no tests and does not run `tool/check.sh`; it runs `flutter analyze` only, and says in each commit message that tests were not run. Tests that a task makes stale are listed in its tick below. Tasks 0–4: test first, `tool/check.sh` once, one commit, tick it.

- [x] **0. Docs.** This commit: the pivot in §1–§14, FR-26 and FR-27, §10 items 8 and 9, M23–M27 here, and CLAUDE.md.
- [x] **1. Fingerprint and `SourceVideo`.** `videoFingerprint(file)`: the file size plus the SHA-256 of the first and last 1 MiB; the ID is `v_<16 hex>`. `SourceVideo{videoId, title, duration}`, no `channel`. The name `videoId` stays, to avoid touching every call site. Also add `assets/videos/` to `.gitignore` (the reference clip is 63 MB; never declare it in `pubspec.yaml`).
- [x] **2. Media probe.** FFprobe in `lib/src/core/ffmpeg/`: duration, size, rotation, and whether there is an audio track. No audio, or unreadable, gives "Can't read this video." (§8). Rotation is read now because the chooser's aspect ratio on rotated portrait videos (an open §14 check) depends on it.
- [x] **3. Share in (Android).** Our own `status_studio/video_in` channel (`videoin/VideoInChannel.kt`), not `receive_sharing_intent`: its 1.9.0 copies the whole video on the main thread into the cache under the sender's name, makes a thumbnail there too, and the importer would then copy it a second time. It also needs AGP 9.2.1 and, on iOS, SPM-only plus a `SceneDelegate`. The channel streams the content URI into `files/incoming/` on a worker thread (the importer in task 4 moves that file into `sources/<videoId>/`; copies older than a day are deleted), hands the launch share to Dart once, and forwards later shares from `onNewIntent`. `SEND` and `VIEW` `video/*` intent filters on MainActivity, which is `singleTask` (without `taskAffinity=""`, which would have left the system no task to find) so a share while the app runs reaches `onNewIntent` instead of starting a second window. A share's intent is emptied once taken, and one reopened from Recents is ignored. Review fixes: the copy is guarded against any exception, checks free space first, truncates the sender's file name to 255 bytes, and the Dart stream is a broadcast stream. Dart: `IncomingVideoSource` and `incomingVideoSourceProvider` (`incoming_video_source.dart`) drop non-video and repeated shares. The iOS Share Extension and App Group come in M26, where the share package question is asked again (§10 item 9).
- [x] **4. Picker and importer.** `image_picker` `pickVideo`. `LocalVideoImporter` moves either source into `sources/<videoId>/source.<ext>` and returns `SourceVideo`. It replaces `VideoSource`; `videoSourceProvider` stays for test overrides. Done: `VideoPicker` (`GalleryVideoPicker`, a cancel is `VideoPickCancelled`, not null; a `PlatformException` is `VideoPickFailedException`; `retrieveLostVideo()` answers `LostVideoFound` or `NoLostVideo`, and **task 5 must call it when Source starts**) and `LocalVideoImporter.importVideo(path, displayName)` in `lib/src/features/source/data/`. A file in `files/incoming/` or the picker's copy in the cache folder is renamed into place (copied and deleted when the volumes differ) and always deleted afterwards; any other is stream-copied through `SourceCache.write` after a free-space check (size plus 50 MiB, asked of Kotlin through `freeBytes` on the `video_in` channel; an unknown answer, `StorageUnknownException`, skips the check). A video already kept under the same ID and of the same length is reused (otherwise replaced), concurrent imports of one ID are single-flight, and an owned duplicate is deleted. `video.json` is written by `TranscriptStore.saveVideo`, which now also marks the video used. Startup cleanup keeps a source while its transcripts folder exists and deletes an orphan after 7 days; `TranscriptStore.prune` deletes the source folder with the transcripts folder. `sourceCacheProvider` now points at app support, not the temporary folder, as §4 says. The importer has its own provider (`localVideoImporterProvider`); `videoSourceProvider` and the YouTube classes stay until task 9, and Source is rewired in task 5.
- [x] **5. Source screen and routing.** "Choose a video", then a card with thumbnail, name and length, then Get script. A shared video opens Source with the card and starts the script. With a reel in progress: "Start a new reel from this video? The one you're making will close." with Start and Keep; the FR-24 draft is kept either way. Built: `SourceScreen` (picker button, card, lost-pick recovery at start, Get script off until a video is chosen; a `sharedVideo` passed through the route's `extra` is imported and its script starts at once); `videoThumbnailProvider` (first frame, kept as `thumbnail.jpg` beside the video; the card shows its icon when there is none); `SharedVideoListener` around the router (a share on Home, Source, Done or Settings opens Source directly (the draft is reset after Home has replaced the old reel's screens, so they never read an empty draft); on any other screen with a video in the draft it asks first, reading the top route's path (`router.state`), and one question at a time, and Keep drops the share); "Can't read this video." in `errorMessageFor`. Tests not run. **Stale for the user to fix:** the old link tests in `test/src/features/source/presentation/source_screen_test.dart` (they type a link and use `FakeVideoSource.fetchVideo`); `startProcessing` in `test/src/features/transcript/presentation/processing_screen_test.dart` (~:32-39, types into the removed link `TextField`, so every test using it fails); `test/src/features/home/presentation/home_screen_test.dart` (~:33, expects 'YouTube link'); new cases to write are in §13 (picker, card, errors, lost pick, share opens Source, share asks when a reel is in progress). Test helpers already carry `videoPicker`, `importer` and `incomingVideos` in `TestSetup`, with `FakeLocalVideoImporter`.
- [x] **6. Script audio from the file.** One FFmpeg run replaces the download and stream-copy split: `-vn -map 0:a:0 -ac 1 -ar 16000 -sample_fmt s16 -c:a flac -f segment -segment_time 90 -reset_timestamps 1 -segment_list pieces.csv -segment_list_type csv chunk_%03d.flac`. Remove the captions path from `real_script_pipeline.dart`, with `caption_track_choice.dart` and `json3_captions.dart`. Resume per piece is unchanged. New Processing copy. Built: `scriptPiecesArguments` (with `-reset_timestamps 1`), `AudioPreparer.cutScriptPieces` (reads FFmpeg's CSV segment list into `AudioPiece{file, start}`; Groq's lines are offset by each piece's real start, not a multiple of 90 s), the Groq upload as `audio/flac`, the pipeline reading the kept video (`KeptVideoMissingException` → "Video not found, choose it again." when it is gone) and no captions step; the first stage is "Preparing the audio" with FFmpeg's read position as its amount. `caption_track_choice.dart`, `json3_captions.dart` and `VideoSource.fetchCaptions` are no longer used but stay until task 9 deletes the YouTube source they hang off. Review fixes: 16-bit FLAC (`-sample_fmt s16`, about 40 % smaller uploads), FFmpeg is stopped when the user leaves Preparing the audio early, and the pieces folder is kept, not deleted, so a retry or another language can reuse it (M24 task 2 caches the cleaned pieces there); a new cut empties it first. Tests not run. **Stale for the user to fix:** `test/src/core/ffmpeg/audio_arguments_test.dart` (`chunkArguments`), `test/src/features/transcript/data/audio_preparer_test.dart` (`splitAudioCopy`), `groq_transcriber_test.dart` (pieces are `AudioPiece`, offsets from `start`), `groq_client_test.dart` (the upload is `piece.flac` / `audio/flac`), `application/real_script_pipeline_test.dart` (no captions path, `sources` instead of `videos`, the stage name; `FakeAudioPreparer` must also override `stopRunning`, which would otherwise call the real `FFmpegKit.cancel`, and returns `AudioPiece`s), `presentation/processing_screen_test.dart` (`ScriptStage.preparingAudio`, new detail copy).
- [x] **7. Clip source is the file.** `clipSourceProvider` returns `ClipSource(file, offset: 0)`; `ClipWindow` is the whole video; the download states and "Downloading clip…" go; the seek bar spans the whole video (add the pending seek-bar width test here). Built: `ClipSourceController.open(video)` (replaces `prepareFor`) returns `ClipSource(kept file, offset: 0, window: 0..duration)` at once, or `KeptVideoMissingException`; the progress provider and "Downloading clip…" are gone (the player says "Opening the video…"); the export reads the same source. The player's seek bar already spans the file it plays, which is now the whole video; the waveform covers the whole video up to 10 minutes and, for a longer one, 5 minutes from the clip's start (its WAV is about 1.9 MB a minute and is read into memory). `clipSourcePreparerProvider`, `ClipSourcePreparer` and `clipWindowFor` stay until task 9 (the waveform uses `clipWindowFor`). Tests not run. **Stale for the user to fix:** `test/src/features/source/application/clip_source_controller_test.dart` (`prepareFor`, progress), the tests that feed the player a `FakeClipSourcePreparer` through `TestSetup.clipPreparer` (`test/helpers/pump_app.dart`, `test/helpers/fake_clip_preparer.dart`, `fine_tune_pump.dart`, `fine_tune_screen_test.dart` including its 'Downloading clip… 40 %' check, `follow_subject_controller_test.dart`, `reel_preview_test.dart`): the controller now reads the kept file from `sourceCacheProvider`, so those tests should override `clipSourceProvider` or put a file where `keptLocalVideos` finds it. The seek-bar width test is still to be written.
- [x] **8. Script without line picking.** `ClipRange` defaults to 0..duration and the selection is all lines. Script's tap selection goes; Script becomes a review screen (language, Fix with Groq, Next). Step labels: Source 1/5, Script 2/5, Fine-tune · Video 3/5, Fine-tune · Lyrics 4/5, Style 5/5 (unchanged), as FR-5 says. Recent and Continue reopen from the kept `source.<ext>`; when it is missing the row says "Choose or share the video again" and the §8 "Video not found, choose it again" message shows. Built: `ReelDraft.withVideo` makes the clip the whole video; the selected lines are the ones inside the clip and follow it on every nudge (`ReelDraft.withClip`, review fix); a new, growing or corrected transcript reselects them and keeps the clip, its nudges and the crop keyframes; the caption is refilled only while it is still the lines' own text, so a caption the user typed or translated survives Continue; editing lines no longer moves the clip; choosing another video starts a fresh draft; `tapLine` is gone and Script ("Check the script", Step 2 of 5) lists the lines without taps, with Next enabled once there is a line. Fix with Groq sends the lines inside the clip (`linesInClip`), so trimming the clip on Fine-tune is how a long script gets under 30 lines. Home: a script row or a Continue row whose kept video is gone (`isVideoKeptProvider`) reads "Choose or share the video again"; a tap shows "Video not found, choose it again." and opens Source, with the script and the draft kept; a video chosen again finds them (same fingerprint). Tests not run. **Stale for the user to fix:** `test/src/features/transcript/presentation/script_screen_test.dart` (tapping lines, "Pick the lines", "Pick a start and an end", badges), `test/src/features/reel/domain/reel_draft_test.dart` and `reel_draft_controller_test.dart` (`withTranscript` used to clear selection and clip; `tapLine`; edits moving the clip), `home_screen_test.dart`, `script_progress_controller_test.dart`, `processing_screen_test.dart`, `test/helpers/fixtures.dart` (`pickedDraft` still uses `withSelection`, which now only the helpers call), `lyrics_screen_test.dart`, `fine_tune_draft_test.dart` and `fine_tune_draft_saver_test.dart` (they use `withSelection` or `NoSelection`), and any test asserting the old "Tap the start and end lines of your clip first." text. `withSelection`, `ClipRange.fromLines`, `StartSelected` and `LineSelection.tap` are dead in `lib` now; they stay only because those tests use them.
- [x] **9. Remove YouTube.** Dart: `youtube_video_source.dart`, `yt_dlp*.dart`, `yt_dlp_updater.dart` and its hook in `main.dart`, the Settings "YouTube support" section, `clip_source_preparer.dart`, `ranged_downloader.dart`, `segment_index.dart`, `stream_choice.dart`, the YouTube errors in `source_errors.dart`, `youtube_link.dart`. Android: `YtDlpChannel.kt`, `YtDlpCommands.kt`, the youtubedl-android Gradle dependency, and the legacy jniLibs packaging if only yt-dlp needed it. Test helpers: `fake_yt_dlp.dart`, `yt_dlp_json.dart`, `counting_video_source.dart`. FR-19's prompt drops the youtu.be link. A one-off cleanup deletes old `transcripts/` and `sources/` folders whose ID doesn't start with `v_`. Record the APK size change. Afterwards grep shows no `yt_dlp`, `youtube` or `youtubedl` in `lib/` and `android/` apart from that cleanup. Built: all the Dart, Kotlin and Gradle items above are gone (`SourceCache` keeps only the kept video, its thumbnail and the `.part` writer; `OfflineException` and `IncompleteDownloadException` stay for the Groq calls and local copies); the Android `packaging` block (legacy JNI packaging, libpython) and the `youtubedl-android` dependency are removed; Settings has only the Groq key and background work; `deleteFoldersWithoutFingerprint` runs at start-up on `sources/` and `transcripts/` and removes the folders whose name doesn't start with `v_`; `VideoSource`, `FakeVideoSource`, `ClipSourcePreparer` and the caption parsers are deleted with their tests and helpers (`fake_yt_dlp.dart`, `yt_dlp_json.dart`, `counting_video_source.dart`, `fake_clip_preparer.dart`). `grep -rniE "youtube|yt-?dlp|youtu.be" lib android` finds nothing. **APK size (2026-11-05, release, per ABI):** arm64 67.1 MB, armeabi-v7a 70.4 MB, x86_64 72.2 MB, against 45.4 MB (arm64) on 2 Nov. The APK grew because the native libraries are now stored uncompressed (no legacy packaging), which makes the install smaller and starts faster, and M20 added face detection; there is no Python, QuickJS or yt-dlp in it any more. Tests not run. **Stale for the user to fix:** `test/src/features/settings/presentation/settings_screen_test.dart` (the yt-dlp row), `source_screen_test.dart`, `clip_source_controller_test.dart`, `fine_tune_screen_test.dart`, `follow_subject_controller_test.dart`, `real_script_pipeline_test.dart` and `processing_screen_test.dart` (they use `videoSource:`, `ytDlp:`, `clipPreparer:` or the removed fakes; `TestSetup` no longer has those fields), `test/src/core/ffmpeg/audio_arguments_test.dart` (`chunkArguments`), `test/src/features/source/data/source_cache_test.dart` and `test/src/core/cache_cleanup_test.dart` (the removed accessors and the new cleanup), `script_exchange_test.dart` (`videoUrl`), `groq_script_fix_service_test.dart` (the link in the prompt), and `recent_entries_test.dart`, `fine_tune_drafts_controller_test.dart`, `fine_tune_resumer_test.dart` and `fine_tune_draft_store_test.dart` (they use `captionsSource`).
- [x] **10. Docs and review.** §13, §14 and the §12 status; Opus reviews of tasks 8–9 and of the whole branch, with their findings fixed (b51d266 and the commit after it); pushed to `origin/m23-local-video`, not merged. §13 and §14 hold the M23 cases and device checks. The whole-branch review's fixes: the probe's size is the displayed one (width and height swap at 90° or 270°); a share saves a fine-tune only from Fine-tune, Lyrics or Style; Continue reselects the lines inside the clip; a share answered "Keep" deletes its staged copy; Get the script after changing the language forgets edited lines; a slow import no longer starts a script for a video replaced meanwhile. **Stale for the user to fix:** tests of `MediaProbe.videoSize` (now throws `VideoUnreadableException` and reads displayed size), `fine_tune_draft_test.dart` (`restoredOnto` recomputes the selection), `reel_draft_test.dart` (same video keeps the draft). Tests not run.

### M24 tasks (branch `m24-clean-voice`)

Request, 2026-11-05: clean the voice before Groq hears it, so the lyrics are more accurate (FR-26). Stacked on M23. Same execution model as M23. Each task: test first, `tool/check.sh` once, one commit, tick it.

- [x] **1. `cleanVoiceFilter`.** In `audio_arguments.dart`: `highpass=f=80,lowpass=f=7500,afftdn=nr=12:nf=-30:tn=1,dynaudnorm=f=200:g=11:p=0.9`; test the argument list. It removes rumble, hiss, hum and hall noise and evens out loudness; it cannot separate the voice from harmonium or daf (FR-26). Built: `cleanVoiceFilter` is a public constant, and `scriptPiecesArguments` passes it as `-af` after `-map 0:a:0` and before `-ac`/`-c:a flac`. Tests not run. **Stale for the user to fix:** `test/src/core/ffmpeg/audio_arguments_test.dart` (the piece arguments now hold `-af <chain>`; it also still tests the removed `chunkArguments`).
- [x] **2. Use it in the piece run.** `-af <chain>` before the FLAC encode in M23's piece run. Processing shows "Cleaning the voice". Cleaned pieces are cached per video, so a retry doesn't clean again. Built: the first stage's label is "Cleaning the voice" (`ScriptStage.preparingAudio`; Processing and the notification both read `stage.label`). `AudioPreparer.cutScriptPieces` writes to `pieces_<seconds>_<8 hex of SHA-256 of the filter chain>` and reuses that folder when its `finished` marker, `pieces.csv` and every listed piece exist; the marker is written after FFmpeg returns, because FFmpeg appends to the CSV as it goes and a cut that was cut short would otherwise look complete. Every other `pieces_*` folder beside the video (an older chain, an unfinished cut, M23's `pieces_90`) is deleted first, and an incomplete current folder is emptied and re-cut. A reused cut reports no FFmpeg progress. Tests not run. **Stale for the user to fix:** `test/src/features/transcript/data/audio_preparer_test.dart` (the folder name, reuse and cleanup cases are new), `application/real_script_pipeline_test.dart` and `presentation/processing_screen_test.dart` (the stage label "Preparing the audio"), `FakeAudioPreparer` in the test helpers (if it writes to `pieces_90`).
- [ ] **3. Lyrics check against the reference clip (§10 item 8).** *(Built; the run and the recorded result are pending: `GROQ_API_KEY` was not set in the shell.)* The reference clip stays out of the repo and the app (`.gitignore` and `pubspec.yaml` rule: M23 task 1). Commit `tool/voice_check/arshe-haq-expected.txt`; write `tool/voice_check.dart`; compare raw, cleaned and cleaned with `ur`; score by CER; pass is cleaned below raw and at most 15 %; record the table and the chosen values in §10 item 8, and update FR-26 if they change. Add a §14 check: the same clip in the app on the Redmi gives a transcript within 2 points of the Mac CER. Built: `tool/voice_check.dart` and `tool/voice_check/lyrics_score.dart` (normalising, CER, missing lines), run with `GROQ_API_KEY=… fvm dart run tool/voice_check.dart <video> <expected.txt>`. Without the variable it stops with exit code 2 and "waiting for it"; it checks the lyrics file and the key before cutting anything. It builds the arguments with `scriptPiecesArguments` (the raw baseline is the same list without `-af`), runs the Mac's `ffmpeg`, uses the app's own `GroqClient`, scores four variants (raw and cleaned, each automatic and `ur`), prints the table, the ffmpeg version, a PASS or FAIL per language and what Groq heard. To make `audio_arguments.dart` load in plain Dart, it now imports `package:meta/meta.dart` instead of `package:flutter/foundation.dart` (`meta` is a direct dependency now; it was already resolved). Checked offline: the arguments run on the reference clip (one cleaned piece, `pieces.csv`) and the scorer gives CER 0 for identical text, 0.59 for a clipped one and finds a missing line. The expected-lyrics file holds the 10 lines (the owner filled them in; the tool stops if a line starts with `TODO`). With a dummy key the run goes through both FFmpeg cuts and reaches Groq, which answers 401 (`GroqKeyRejectedException`). **Still open:** (a) run it with the real key, then paste the table and the chosen values into §10 item 8 and change FR-26 if they differ from the defaults; (b) spot-check on one more clip. Tests not run (none written for the tool).
- [x] **4. Docs and review.** §13, §14, §12 status; Opus reviews of the commits and of the whole branch with their findings fixed; pushed to `origin/m24-clean-voice`, not merged. Review fixes: a cancel during the folder work no longer starts FFmpeg, deleting a `pieces_*` folder that is already gone is ignored, and the cut-and-mark step is its own function. **Not changed on purpose:** the review feared `lowpass=7500` fails on audio sampled below 15 kHz because the chain runs before `-ar 16000`; on an 8 kHz test tone FFmpeg 8 ran the chain without error (the filter turns itself off), so the chain stays exactly as FR-26 says. The review also noted that the chain runs on the source's full-rate stereo audio, which is about six times the samples of 16 kHz mono; §14 asks for a timing on the Redmi, and if it is slow the fix is `aresample=16000,aformat=channel_layouts=mono,` in front of the chain (the chain's hash changes the folder name, so old caches are dropped). **Stale for the user to fix:** see tasks 1 and 2.

### M25 tasks (branch `m25-choose-per-scene`)

Request, 2026-11-05: when cropping, ask the user at every scene what to keep in frame: a face, a body or a fixed spot, never assumed (FR-27). Stacked on M24. Same execution model as M23. Each task: test first, `tool/check.sh` once, one commit, tick it.

- [ ] **1. Spike (device), §10 item 7 extended.** Faces plus bodies on the Redmi Note 11: ML Kit pose finds one person per frame, a COCO detector (EfficientDet-Lite0 via `tflite_flutter`, about 4.4 MB) finds several. Measure time, recall and APK growth; record which to use. Task 5 depends on it; faces and spots don't.
- [ ] **2. Domain: `SceneChoice`.** The sealed type `FollowFace(track)`, `FollowBody(track)`, `HoldSpot(anchor)`, and `pathForChoices(scenes, geometry, choices)` in `subject_path.dart`. Faces reuse `_pathOfScenes` (one track per scene) and `_withTheirOtherSightings` within the scene. A spot is a constant anchor with a Cut keyframe at the scene start. There is no automatic pick and no look-alike carry-over: `followSubject`, "Choose for me" and `_followedInAnotherScene` stop writing keyframes and are removed.
- [ ] **3. Controller.** `follow_subject_controller.dart` keeps `FollowRunning`, then `FollowChoosing{sceneIndex, sceneCount, picture, faces, bodies}`. Each scene's picture is its fullest frame (`_fuller` from `person_choice.dart`, per scene). Every scene is asked, even with one face or none. Choosing moves to the next scene; Back and Cancel exist. Frames are deleted at the end or on cancel. A hand edit still wins.
- [ ] **4. Sheet.** Evolve `person_chooser_sheet.dart`: title "Scene 2 of 5 · 0:07–0:12", hint "Tap a face, a body, or the spot to keep in frame."; a tap within 24 dp of a face picks it, inside a body box picks the body, elsewhere picks that spot with a pin shown before the next scene; TalkBack reads "Person 1", "Body 1" and offers "Keep the centre". The sheet pops with a result and `_askWhom` acts after the await (this fixes the pending double-pop item). The pending `onPanCancel` test for `CropWindowOverlay` goes into this commit, since the same screen is touched.
- [ ] **5. Bodies (only if the spike says go).** A detector behind `SubjectDetector` returning body boxes; body tracks use the same `couldBeSameFaceAs` distance rule on body boxes; the anchor is the box centre, upper third.
- [ ] **6. Docs and review.** §13 cases, §14 checks, §12 status; an Opus whole-branch review; fix findings; push (not merge).

### M26 tasks (branch `m26-ios`)

Request, 2026-11-05: the app must also build for iOS. Stacked on M25. Xcode and CocoaPods are on the Mac, so builds run there; signing and device runs need the Apple Developer account and an iPhone. ML Kit doesn't run on the arm64 simulator, so face detection is checked on a device only (§14). Same execution model as M23. Each task: test first where code allows, one commit, tick it.

- [ ] **1. First build (spike, §10 item 9).** Deployment target 15.5, bundle ID `com.hotmail.arehmananis.statusstudio`; `pod install`; `fvm flutter build ios --no-codesign`; check every plugin resolves; record the IPA size and any failure.
- [ ] **2. Info.plist and permissions.** `NSPhotoLibraryAddUsageDescription` for `gal` (saving the reel); PHPicker needs no library permission; bundle the Nastaliq and Naskh fonts; set the display name.
- [ ] **3. Share Extension.** A Share Extension target that accepts movies, plus the App Group `receive_sharing_intent` needs. A shared video opens the app on Source, as on Android.
- [ ] **4. AVFoundation renderer (Swift).** The same `status_studio/render` method channel and `status_studio/render/events` event channel, taking the same spec map from `render_spec.dart`; the Dart `Renderer` interface gets an iOS twin chosen by platform. A custom `AVVideoCompositing` with Core Image crops each frame, with the rect from the ported `MovingCrop.ndcRectAt` (glide and cut keyframes). It overlays each caption-line PNG and the logo when due, deleting the PNGs when the render ends, and encodes hardware H.264 and AAC through `AVAssetWriter`. Progress and cancel work as on Android. XCTest ports of `MovingCropTest.kt`.
- [ ] **5. System channel.** `openAppSettings` in Swift (`UIApplication.openSettingsURLString`).
- [ ] **6. Background work.** iOS has no foreground service: Groq work runs while the app is open and uses `beginBackgroundTask` for the short grace period. Script progress is saved per 90 s piece, so it resumes when the user comes back; the notification copy says so. `flutter_foreground_task` stays Android-only behind the existing background provider.
- [ ] **7. Docs and review.** §13, §14, §12 status, the CLAUDE.md iOS note; an Opus whole-branch review; fix findings; push (not merge).

### M27 tasks (branch `m27-store-readiness`)

Request, 2026-11-05: meet Google Play and App Store policy. With YouTube gone nothing downloads third-party media or runs code fetched at runtime, which was the blocker in both stores; what remains is policy hygiene. Stacked on M26. Same execution model as M23. Each task: test first where code allows, one commit, tick it.

- [ ] **1. Consent before the first Groq upload.** A one-time screen says the audio is sent to Groq, a third-party AI service, with the user's key, to write the lyrics; the user agrees or cancels. The answer is kept and Settings can withdraw it. (App Store guideline 5.1.2(i); Play User Data policy.)
- [ ] **2. Drop `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`** and its prompt (`background_work_platform.dart`); Play allows it only for listed uses. Keep `FOREGROUND_SERVICE_DATA_SYNC` (uploading to Groq) and write its Play Console justification in §9. Update FR-16 and the Settings rows.
- [ ] **3. Privacy policy text in §9.** What is stored on the phone, that audio and the Fix with Groq lines go to Groq, the key in secure storage, no analytics. It needs a public URL; the repo is private, so the user chooses where to host it.
- [ ] **4. Store answers in §9.** Play Data safety (audio shared with a third party for app functionality, not collected by us, no account); the Apple App Privacy label; export compliance (HTTPS only, exempt); content rating.
- [ ] **5. Listing rules in §9.** No "YouTube" or "WhatsApp" in the name, description or screenshots, and neither brand's logo; screenshots use the user's own footage; "Status" alone is fine.
- [ ] **6. Release builds.** A signed Play App Bundle (`fvm flutter build appbundle`) and an iOS archive for TestFlight.

## 13. Behaviour that must stay covered by tests

- **Links (removed in M23):** the YouTube link tests went with the links.
- **Selection and nudges:**
  - (The tap-selection cases went in M23: there is no line picking.)
  - Nudges past either end of the video are ignored. A nudge that improves an invalid clip is applied.
  - A free-crop drag stays inside the frame.
  - A new transcript replaces the lines and clears per-line caption edits; the clip, its nudges and the crop keyframes stay.
- **Downloads and captions (removed in M23):** nothing is downloaded and there are no caption tracks, so their tests went.
- **Local video in (M23):**
  - The fingerprint is the same for the same bytes (a copy, or a rename) and different for different files, including files that differ only after the first MiB or before the last.
  - A shared video and a picked video both import: each is copied to `sources/<videoId>/source.<ext>` and gives the same `SourceVideo` for the same bytes.
  - A video with no audio track, or one that can't be read, gives "Can't read this video."
  - The probe reads duration, size and rotation.
  - A new video's clip defaults to the whole video; nudges still work from both ends and respect 3 s and the video's ends.
  - Recent reopens a script from the kept file; with the file missing it shows "Choose or share the video again" and the "Video not found, choose it again" message.
  - Folders whose name isn't `v_` and 16 hex digits are deleted; fingerprint folders are kept.
  - A reel in progress asks "Start a new reel from this video?" before a shared video replaces it, and Keep leaves everything as it was.
  - Source (M23 task 5): "Choose a video" imports the picked file and shows its name (without extension) and length; a cancelled pick shows nothing and imports nothing; "Choose another video" shows once one is chosen; Get the script is off until a video is chosen and does nothing after a failed import; "Can't read this video." and "Not enough space on your phone." show on the card; a pick lost while the app was closed is imported when Source opens; a picker failure shows the general error.
  - A shared video opens Source from Home, Source or Done without a question, imports and starts its script with automatic language; on any other screen with a video in the draft it asks first, and Start closes the reel while Keep drops the share. A share that fails to copy shows its message as a snackbar.
  - The card's thumbnail is cut once from the kept video (`thumbnail.jpg`), reused afterwards, and replaced by the icon when the video isn't kept.
  - The piece arguments are 16 kHz mono FLAC, 90 s segments, audio stream 0 only, no video.
  - Share in (Android): the Kotlin helpers in `videoin/` have JVM tests (`SharedVideoTest`, `ShareDeliveriesTest`): intent filtering, the Recents and restored-activity rules, staged file names (Urdu, 300 characters, no extension, separators and `..`, two shares with one name), the free-space check, refusing the app's own folder, and keeping shares while Dart isn't listening. `tool/check.sh` doesn't run them; run them with `cd android && ./gradlew testDebugUnitTest`.
  - The Dart share stream is a broadcast stream: the launch share is delivered once, a second listener doesn't throw, and the last listener leaving tells the platform to keep shares.
- **Transcription:**
  - Non-speech tokens never become lines.
  - Lines keep absolute times across piece boundaries.
  - A killed run resumes from the next piece.
  - A saved script opens without Processing.
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
- **Clean the voice (FR-26, M24):**
  - The piece arguments hold `-af` with exactly the filter chain, before the FLAC encode.
  - The chain is the one in §10 item 8's chosen values.
  - Cleaned pieces are reused by a retry and by another language; a piece is never cleaned twice.
  - The pieces folder is named by the chain (a changed chain starts a new folder and deletes the old one); a folder with no `finished` marker, no `pieces.csv` or a missing listed piece is deleted and cut again; a cancel before FFmpeg starts leaves nothing running.
  - The label of `ScriptStage.preparingAudio` is "Cleaning the voice" on Processing and in the notification.
- **Choose per scene (FR-27, M25):**
  - A scene with one face still asks; a scene with no face offers a spot, never a "no person" error.
  - Every scene is asked, in order; nothing is chosen for the user, and there is no "Choose for me".
  - A spot gives a constant anchor with a Cut at the scene start; the crop holds through the scene.
  - A face or body is followed within its scene only; another scene's choice is not carried over.
  - Back changes an earlier answer and keeps the others; Cancel changes nothing and deletes the frames.
  - A tap within 24 dp of a face picks that face; a tap inside a body box picks the body; a tap elsewhere picks that spot.
  - The sheet pops once with its result (no double pop). A hand edit made meanwhile still wins.
- **Clip edges (FR-5):** tapping Start or End sets it to the playhead rounded to 0.1 s; a time that leaves under 3 s or passes the video's ends changes nothing.
- **Follow the person (FR-23):**
  - A steady face gives one keyframe. A face drifting left to right gives at most four keyframes, all glides, and ends near the right. Jitter of ±0.03 of the room gives one keyframe.
  - Two faces: the larger is followed, and a larger one appearing beside the followed one doesn't take over.
  - A scene cut gives a Cut at the cut time; a jump of more than 0.3 of the room that the detector missed gives a Cut too, but not a second one beside a detected cut. A cut right after the clip start moves the first keyframe.
  - Sixty seconds with a cut every three seconds gives at most 12 keyframes and still reaches past 40 s.
  - A gap of one second holds the last anchor. With room on x only, y keeps the base anchor.
  - A clip of 90 s of busy movement gives at most 12 keyframes, at least 0.5 s apart, all inside the clip; a clip starting at 12.34 s gets its first keyframe at 12.4 s.
  - Faces in fewer than 20 % of the frames change nothing and give "No person found".
  - **Choose the person (FR-25):** two people together are offered, numbered left to right, at most 6; a face seen in under 3 frames or 20 % of its scene is not; the picture has the most people and then the biggest faces. The chosen smaller face is followed; another scene follows the face in the same place, or the FR-23 pick without one; the cuts are the same as without a choice. A tap within 24 dp chooses the nearest face; a far tap does nothing. Choose, Cancel, dismissing, leaving and a clip change all delete the frames; Cancel and dismissing change nothing; one person asks nothing.
  - The frame arguments use file time (the offset subtracted), the sampling rate falls for long clips and never below 2, and the cut parser reads FFmpeg's times.
  - Replace is asked only when more than one keyframe exists. Cancel, leaving, turning the move off, and a clip or size change stop the run, delete the frames and change nothing; a hand edit during the run wins. The detector is closed after every run.
  - A build without the scene filter is run again without it. The cuts file path is escaped for the filter graph. Until the first frame is looked at the bar is indeterminate.
- **Moving crop (FR-22):**
  - A glide moves in a straight line and arrives at its keyframe's time; a cut holds the earlier anchor until then and has jumped at exactly that time. Dart and Kotlin share their boundary cases.
  - Before the first keyframe the first anchor holds, and after the last the last.
  - A new keyframe snaps to 0.1 s, replaces one within 0.25 s (keeping how it arrives) and is moved into the clip.
  - Any keyframe can be removed except the only one. Turning the switch off keeps the crop where it was at the clip start (the base anchor for Crop to fill, the rectangle for Free crop).
  - Keyframes go to the render spec as NDC rectangles with times from the clip start, in place of the fixed crop; Blur and 16:9 send none.
  - The switch is hidden without room to move. A drag writes one keyframe, at the playhead where it began. The first keyframe has no Glide or Cut. Keep in view is hidden while the crop moves.
  - The Video step's player is released while Lyrics is open and made again on Back.
  - Snapping never puts a keyframe outside the clip. A new script leaves the moving crop, the clip and its nudges alone.
  - A vertical video's player is at most 260 dp high. Chips and the crop outline show only while the crop can move, and the switch stays while keyframes exist. The free crop editor changes only the size while the crop moves.
- **Fine-tune lyrics (FR-21):**
  - Only the clip's lines are listed. The line due shows on the video, and nothing shows between lines. Add line is off outside the clip.
  - The player covers only the clip: it starts at its start, stops at its end, and its seek bar spans just the clip.
- **Fine-tune lines (FR-21):**
  - A tap while playing sets the line's start to the playhead and ends the highlighted line there.
  - A tap earlier than the previous line's start changes nothing.
  - Reorder moves text only; times stay in place.
  - A new line lands at the playhead; the line it lands in ends there.
  - Delete refuses the clip's last line, and the clip keeps the same lines.
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
  - The prompt holds the title and each row with its time and its row number in the whole script; no link (changes in M23 task 9).
  - Only the clip's lines are sent, and the row cap is 30 (changes in M23 task 8: the clip is the whole video until nudged; the 60-line copy path went in M17).
  - A reply's text replaces lines by row number; its times are never used.
  - Fences and chatter around rows are ignored; rows with bars in the text stay whole.
  - Missing rows keep their text; `[?]` rows are kept and named; a reply with no rows is rejected and changes nothing.
  - Corrected lines keep the clip, and the corrected script is the one that reopens.
- **Groq script fix (M15):**
  - The request goes to `/chat/completions` with the web-search model and the key only in the Authorization header; a 429 waits and resends; a 401 is "key rejected".
  - Only the clip's lines are sent (the whole video's, unless nudged); more than 30 are refused before anything is sent.
  - Citation marks `【…】` never end up in a line's text.
  - Cancel ignores the reply and saves nothing; the other fix buttons are off while it runs.
  - No key gives the §8 message with a Settings action; a Groq failure says "Groq couldn't fix this script."
- **Groq (M9):**
  - The key never appears in logs, files or errors.
  - A 429 under 60 s waits and resends.
  - A script without a key stops before any audio is cut.

- **Launch animation (M16):**
  - The first frame is the logo's rest pose, the same as the native splash.
  - Outer bars stay under y 31 and the brackets move in at most 7 units, so nothing overlaps.
  - The splash covers Home, blocks taps, and goes when the animation ends; reduce motion skips it.

- **Continue a fine-tune later (FR-24):**
  - It round-trips through JSON to the millisecond.
  - A newer version, an unknown name, a reversed range, keyframes out of order or an anchor outside 0..1 make the file unreadable; an unreadable file is skipped and its script row stays.
  - The fingerprint is stable across runs. Lines added after the range still fit; a changed line up to the last line of the clip, a range past the end or a clip past the video don't.
  - It is saved 1 s after the last change and at once on close or when the app is hidden. A run of changes is one write, and an unchanged draft isn't written again.
  - There is one per video and language. A save marks the video used, the draft goes when its folder is pruned, and a `.part` file is never listed.
  - A finished export deletes it, and a later save of the same draft writes nothing. A delete waits for a save in progress.
  - Edited lines reopen from the `edited` script even when a newer one exists.
  - A script still being written, whose lines so far hold the clip's lines, continues as Ready; one that doesn't is script gone.
  - A kept fine-tune deleted elsewhere (Delete progress) is written again by the next save of the same work.
  - A second tap on Continue while the first is reading the script does nothing. Writing a script again or choosing another language drops the line-edit shield, so the new script replaces the lines.
  - The Continue row replaces the script row, and Delete progress brings the script row back.
  - Continue opens Fine-tune and Back shows Script. With the script gone it opens Processing; with the script changed it opens Script with the snackbar. Both delete the draft and keep the frame (crop at the old start) and the caption's position and size.

## 14. Device checks

Run on a **release** build (or profile; debug builds are slow). Phones: Pixel 6a (Tensor, 6 GB, Android 17) and Redmi Note 11 (Snapdragon 680, 5.5 GB, Android 13).

**Pivot note (2026-11-05):** the YouTube-specific checks below (Video source, the yt-dlp ones, clip-only download, captions, tapping lines) no longer apply after M23; they stay as history, unticked checks are void. The new checks follow the Library group.

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
  - [ ] Play, pause and the seek bar work over the window; playback runs past the clip end; the bar and its time move without jerks or width changes.
  - [ ] Tapping lines while a naat plays times them, and the highlight follows without lag.
  - [ ] Editing, reordering, adding and deleting lines with Urdu text; the edited script reopens for the same video.
  - [ ] Moving crop, on a phone: the window drags under a thumb (the play button sits in the corner), the keyframe chips are usable above the scrolling frame controls, and the preview glides smoothly.
  - [ ] Moving crop, render: a Cut lines up with a caption line that starts at the same time (both read the clip's clock); a Glide is smooth; the picture is no softer or stretched compared with a fixed crop of the same size; the render matches the Lyrics preview.
  - [ ] Follow the person: a 30 s naat on the Redmi takes at most 15 s; a calligraphy-only clip says "No person found"; the crop follows a singer who sways without jitter; a cut in the video lines up in the render; Cancel responds within 1 s; 12 chips stay usable.
  - [ ] Choose the person (M22): a two-person wide shot opens the chooser; a small face in the background can be tapped; the chosen person is followed through the render; a repeated camera angle after a cut still follows them; TalkBack reads "Person 1"; a portrait phone video shows the picture at the right aspect (rotation).
  - [ ] Opening Lyrics releases the Video step's player with no stutter, and Back brings it back.
  - [ ] Lyrics on a small phone: the reel-shaped player (at most 260 dp high) leaves enough lines to tap.
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

**Local video in (M23), reference clip: a 1080p mehfil:**
- [ ] Share the video from the trimming app with Status Studio closed: it opens on Source with the card and starts the script.
- [ ] Share a video while the app is open: no second app window, the "Start a new reel from this video?" question appears.
- [ ] Share a video, then reopen the app from Recents: the share is not replayed (no second copy, no second question).
- [ ] Share a video with the phone almost full: "Not enough space on your phone." instead of a crash.
- [ ] The same with the app already open on Fine-tune: it asks "Start a new reel from this video?"; Keep leaves the work as it was.
- [ ] Choose a video from the gallery picker (no permission prompt).
- [ ] A rotated portrait phone recording: the preview, the crop and the render are the right way up.
- [ ] A 4K HEVC source renders through Media3.
- [ ] Recent reopens a script after a restart with no copy; delete the kept file and it says "Video not found, choose it again".
- [ ] The first start after M23 deletes old YouTube folders and keeps scripts of `v_` videos.
- [x] Record the APK size change from removing yt-dlp. (Done 2026-11-05: arm64 67.1 MB, see M23 task 9.)

**Clean the voice (M24):**
- [ ] The reference clip, cleaned against raw, in the app on the Redmi: the transcript is within 2 points of the Mac CER (§10 item 8).
- [ ] A mehfil with harmonium or daf: note how much of the lyrics the instruments still spoil.
- [ ] "Cleaning the voice" shows on Processing and in the notification.
- [ ] Time the cleaning of a 60 s video on the Redmi. The chain runs on the source's full-rate stereo audio; if it takes more than the Groq upload and transcription together, put `aresample=16000,aformat=channel_layouts=mono,` in front of the chain (and rerun §10 item 8).
- [ ] Write the script twice for the same video (another language the second time): the second run skips "Cleaning the voice" at once.

**Choose per scene (M25):**
- [ ] A mehfil with cut-aways: every scene is asked, including the cut-aways and a scene with one face.
- [ ] A scene with no face offers a spot, and the crop holds there with a Cut at the scene start.
- [ ] Back changes an earlier answer; Cancel changes nothing.
- [ ] TalkBack on the scene sheet reads "Person 1", "Body 1" and offers "Keep the centre".
- [ ] A portrait phone video shows each scene's picture at the right aspect (rotation).
- [ ] Bodies (if the spike chose a detector): two people side by side give two bodies to pick.

**iOS (M26), on an iPhone:**
- [ ] Share from Photos and from the trimming app opens Source.
- [ ] The render with a moving crop and Urdu captions matches the Android output frame by frame.
- [ ] Leaving the app mid-script and coming back resumes from the last saved piece.
- [ ] Face detection finds faces (ML Kit has no arm64 simulator support, so devices only).
- [ ] Save to Photos asks once, and Share works.

**Store readiness (M27):**
- [ ] The consent screen shows before the first Groq upload, and Settings can withdraw it.
- [ ] No battery-optimisation prompt is left; the service still runs a long script.

**Launch animation (M16), on both phones:**
- [ ] Cold start from the launcher: dark background with the logo from the first moment, no white flash.
- [ ] The native logo hands over to Flutter's without a jump in size or position (Android 13 splash API on the Redmi, and with three-button navigation if possible).
- [ ] The animation plays once and Home is usable straight after; with "Remove animations" on, Home shows at once.
- [ ] Returning to the app from Recents doesn't replay it.

**Continue later (M21):**
- [ ] Swipe the app away 2 s after a nudge on a moving-crop clip; Continue restores the clip, keyframes and caption, with no download while cached.
- [ ] Lock within 1 s of an Urdu line edit, kill the process (`adb shell am kill`); Continue brings back the edited lines and the range.
- [ ] After the media cache is cleared, Continue downloads only the clip window; in airplane mode Fine-tune shows the offline error.
- [ ] Export, then Home: the Continue row is gone and the reel row is there.
- [ ] Write it again, then Continue: Script opens with the "script changed" snackbar.
- [ ] A long Urdu title in the Continue row on a small phone.

## 15. Known issues (found on the phone, not fixed)

- (Removed in M23: there is no download; Processing's first step is "Preparing the audio".)
- The language list shows both "English (detected)" and "English".
- **Fine-tune lines (M18):** (a) dragging a line's handle does not scroll the screen, so text can only be dragged to rows in view; fixing it means a sliver reorderable list. (b) (Gone in M23: the player holds the whole video, so timing a line anywhere needs no new file.) (c) A script that finishes writing after the user edited lines saves itself as a newer script than the `edited` one, so the video reopens without the edits.
- **Moving crop (M19):** (a) Style's preview shows the first caption line whatever the time. (b) (Gone in M23: the player holds the whole video, so a keyframe outside the clip can be shown.)
- **Clip over silence (M23):** when a trim leaves the clip over a stretch with no sung line, `linesInClip` selects every line (so Fix with Groq and Lyrics still have a script), which refills the caption with the whole script. The better rule is to select nothing and let Lyrics offer an empty list with "add a line"; not done because `PickedScript` needs a range.
