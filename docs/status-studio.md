# Status Studio

**Updated 2026-11-12.** The one project document: product spec, engineering rules, milestones and known issues. It is the source of truth for behaviour, copy, sizes and error messages. Code cites its section (§) and FR numbers, so keep them stable and add new sections at the end. Design canvas: <https://claude.ai/artifact/HcKksQmAu8ZYBfQdbnr2RN>

## 1. Summary

Status Studio turns a video the user has already trimmed in another app, in any language, into a short clip for WhatsApp Status, Reels, TikTok or Shorts. The user shares the video into the app or picks it from the gallery. The app cleans the voice and writes out the script. The user fine-tunes the start and end by ±0.5 s and the lyrics, picks a size, and chooses what the crop follows at every scene: a face, a body or a fixed spot. Then a caption. The export is an MP4 with the Status Studio name and logo.

- **On the phone:** voice cleaning (FFmpeg), face detection (ML Kit) and rendering (Media3 Transformer on Android, AVFoundation on iOS from M26). No accounts, no servers, no analytics.
- **Groq writes scripts:** every script is written by Groq's hosted Whisper, with the user's own free API key (FR-12a), from the cleaned audio (FR-26), once the user has agreed to sending (FR-30). Script audio leaves the phone only then, and only to Groq. The app ships no key and has no server of its own. On-device Whisper was dropped (M10): on a Redmi Note 11 it ran at 0.2× real time.
- **No media downloads (until M44):** the video comes in as a local file, copied into the app's storage. Nothing is fetched from the internet except the Groq requests above. From M44 a link the user gives is the one exception: yt-dlp downloads only the parts of that video the user keeps (M43–M47 design, §12).
- **Saves work:** scripts are saved by the video's fingerprint, so the same video opens straight to its script next time.
- **Pivot (2026-11-05, M23):** until M22 the input was a YouTube link. YouTube was dropped entirely: no links, yt-dlp, stream downloads or caption tracks.
- **Off the stores (2026-11-12, M43):** the Play Store and App Store plan is dropped. The app is free software (GPL-3.0) in a public repository, released as an APK on GitHub and IzzyOnDroid, and later on F-Droid (M47). Links come back on Android in M44, to cut one topic out of a long video (M43–M47 design, §12).

## 2. Screens

| # | Screen | Route | Job |
|---|---|---|---|
| 1 | Home | `/` | Start a reel; recent reels, saved scripts and fine-tunes to continue (FR-24); open Settings; a shared video opens Source (FR-1) |
| 2 | Source | `/source` | "Choose a video" from the gallery, or the video shared into the app (FR-1);  a card with thumbnail, name and length; Next: video (changed in M30: the language, Get the script and Make it without lyrics moved to Lyrics) |
| 2a | From a link | `/link` | Android (M44, own screen since 2026-11-12): a YouTube link read into a card, then topic, length and Find the moments (FR-35, FR-36). Opened from Home's From a YouTube link or by a shared link |
| 2b | Review cuts | `/link/cuts` | Android (M45): finding the moments, then the cuts to check, the transition and Make the clip, which downloads the ticked cuts and joins them (M46) before Fine-tune opens (FR-36, FR-37) |
| 3 | Processing (removed) | — | Removed in M30: the script run (clean the voice, write with Groq, detect the language, line up timestamps) shows on Fine-tune · Lyrics (FR-21). The number stays so references keep working |
| 4 | Script (removed) | — | Removed in M25 (task 7): it was a read-only list that Fine-tune · Lyrics repeats, editable. Language, Fix with Groq and the saved-script line moved to Fine-tune · Lyrics. The number stays so references keep working |
| 5 | Fine-tune · Video | `/fine-tune` | "Step 1 of 2" (M30): plays the kept video file with Trim and Crop tabs under it. Trim: the clip's start and end, nudged by ±0.5 s, and the waveform (FR-5). Crop: size, fill and crop (FR-6), and the crop that moves at each scene, with the scene strip, New position here and Follow the person (FR-22, FR-27) |
| 5b | Fine-tune · Lyrics | `/fine-tune/lyrics` | "Step 2 of 2" (M30): everything about the lyrics. The Show lyrics switch, Get lyrics from Groq or Type them myself, the run's progress, the line list with Style and Get again, and Export reel (FR-21) |
| 6 | Style (removed) | — | Removed in M30: caption position and size are in the Style sheet on Lyrics (FR-7); the caption is always the lines, in their own language |
| 7 | Export | `/export` | Render with progress; Cancel returns to Lyrics |
| 8 | Done | `/done` | Final preview; Save to gallery; Share; Make another |
| 9 | Settings | `/settings` | A list of categories, each on its own screen since M33: Appearance `/settings/appearance` (FR-32, M35), Groq key `/settings/groq` (FR-12a), Background work `/settings/background` (FR-16), Downloader `/settings/downloader` (FR-35, M44, Android only), Support `/settings/support` and About `/settings/about` (FR-31). The YouTube reader section was removed in M23 |

- **Visual reference:** the design canvas prototype for screens 1–8. Settings follows the same visual language.
- **Progress of a script run (on Lyrics since M30):** the step under way, with its bar and percent (`45 %`) and time left (`1:24 left`) once it can be told, and Cancel. Nothing is downloaded, so there is no speed or size line (changed in M23).

## 3. Functional requirements

**FR-1 Video input (changed in M23; it was "Link input" for YouTube links).** The input is a video the user has already trimmed in another app. There are no links.
- **Share in:** the app accepts a shared video (Android `SEND` of `video/*` and `VIEW` of a `content` URI of `video/*`, received by our own `status_studio/video_in` channel; iOS Share Extension (M26), which copies the video into the App Group and opens the app; the app moves it into `Application Support/incoming/` and tells Dart over the same channel). The copy is refused when the phone has less than the file's size plus 50 MiB free ("Not enough space on your phone.", §8), and `file` URIs into the app's own data folder are never read. A shared video opens Source with its card and waits for Next: video (M30; Get the script or Make it without lyrics from M28 to M29). Nothing is uploaded from Source. If a reel is in progress, the app asks first: "Start a new reel from this video? The one you're making will close." with Start and Keep. The kept fine-tune (FR-24) stays either way.
- **Pick:** "Choose a video" opens the system gallery picker (`image_picker` `pickVideo`: the Android Photo Picker, PHPicker on iOS), which needs no permission.
- **Both ways** put the file in the app's storage, `sources/<videoId>/source.<ext>` (§4). A shared file is already staged in `files/incoming/`, and `image_picker` already copied a picked one into the app's cache folder; those files are moved into place (copied, then deleted, when the folders are on different volumes), and deleted whether or not the import succeeds, so no video is kept twice. A file outside those two folders is streamed into place and left unchanged. The free-space check (size plus 50 MiB) applies to a copy only, and is skipped when the phone can't report its free space.
- **Already kept:** a video kept under the same ID is reused only if its length equals the incoming file's; a shorter or missing one is replaced (written as `.part`, then renamed), and only one `source.<ext>` is ever kept per ID. Two imports of the same video at once keep it once.
- **Lost pick (Android):** the system may close the app while the picker is open. Source asks the picker for a lost result when it starts (`VideoPicker.retrieveLostVideo`) and imports it if there is one.
- **Video ID:** `v_<16 hex>`, a fingerprint of the file: its size and the SHA-256 of its first and last 1 MiB. The same bytes give the same ID, so the same video is recognised however it arrives. The name `videoId` is kept in code.
- **Probe:** FFprobe reads the duration, size, rotation and whether there is an audio track. A video with no audio track, or one that can't be read, gives "Can't read this video." (§8). It also reads the video codec (M31).
- **AV1 (M31).** The bundled FFmpeg can't decode AV1 (§10 item 7), so an AV1 video is not kept as it came. The native renderer (Media3 Transformer on Android, `AVAssetExportSession` on iOS, the `convert` method on `status_studio/render`) writes it once as H.264 video and AAC audio to `sources/<videoId>/converting.mp4`, which is renamed to `source.h264.mp4` when it is whole, and that copy is kept in its place. The video ID is still the fingerprint of the file that came in, so the same AV1 video arriving again reuses the copy without converting. The free-space check asks for twice the incoming size plus 50 MiB. While it converts, the Source card's bar fills and says "Converting this AV1 video so the app can edit it… 42 %" (task 5: the converter sends `{outputPath, value}` every 250 ms on `status_studio/render/conversion`). A phone that can't decode AV1 (Android 9 or older; iPhones before the A17 Pro) gives "This phone can't convert this AV1 video. Save it as H.264 (MP4) in your editor and share it again." (§8). The copy is the app's own file: the video the user shared or picked is never changed.
- **Card:** thumbnail, display name (the file's name without its extension; the file's own name when the sender gave none) and length (`SourceVideo.title`, §6.1). Under the button Source says "Trim it in another app first, or share it to Status Studio."
- **Old IDs:** folders whose ID doesn't start with `v_` belong to YouTube videos and are deleted at every start (a quick listing; once they are gone it finds nothing). A folder counts as a video's only when its name is `v_` and 16 hex digits.

**FR-2 Language.** Dropdown: Detect automatically (default), Urdu, Arabic, Punjabi, Persian, Hindi, Bengali, English. Since M30 it is only on Fine-tune · Lyrics: on the Get card, and in the Get again dialog. The same language in Get again writes the script again with Groq; another language opens its saved script or writes one, reusing the cleaned audio pieces (FR-26).

**FR-3 Script (changed in M23).** The first source that applies:
1. **Saved script** for this video and language (FR-14): open Fine-tune directly.
2. **YouTube captions (removed in M23).** There are no caption tracks any more: a local video has none. The §10 history about auto tracks stays as history.
3. **Speech to text** on the video's own audio track, by Groq with the user's key (FR-12a). Each segment becomes one line. Without a key the run stops with the §8 message before any audio is cut.
   - **Audio:** one FFmpeg run reads the kept file and writes 16 kHz mono FLAC pieces of 90 s: `-vn -map 0:a:0 -ac 1 -ar 16000 -sample_fmt s16 -c:a flac -f segment -segment_time 90 -reset_timestamps 1 -segment_list pieces.csv -segment_list_type csv chunk_%03d.flac`. 16 kHz mono FLAC is what Groq recommends. From M24 the voice-cleaning filters (FR-26) run first in the same command.
   - **Pieces:** 90 seconds each, so lines appear while the rest is still being written. Each piece's times are offset by its start, read from the `pieces.csv` segment list that FFmpeg writes.
   - **Dropped segments:** silence, music and bracketed tokens (`[BLANK_AUDIO]`, `(music)`, `♪`) never become lines.
   - **Groq** (`whisper-large-v3`; `whisper-large-v3-turbo` until M24, §10 item 8):
     - **Request:** one multipart `POST https://api.groq.com/openai/v1/audio/transcriptions` per piece, in order, with `Authorization: Bearer <key>`. Fields: `file`, `model`, `response_format=verbose_json`, `timestamp_granularities[]=segment`, `temperature=0`, and `language=<whisperCode>` unless automatic.
     - **Lines:** segments with empty text are dropped. `no_speech_prob` was 0 on turbo (§10 Q5); large-v3 reports real values (0.00 to 0.12 on the reference clip), so the 0.6 cutoff drops segments now, which a sung line might trip (§14). A piece whose segments are all known invented phrases ("Thank you.", "Thanks for watching.", "you", "bye") gives no lines; the same phrase beside real speech is kept.
     - **HTTP 429:** wait `retry-after` and resend when it's 60 s or less, showing "Waiting for Groq · 0:42 left"; otherwise the §8 error.
     - **HTTP 5xx or 498:** resend once after 2 s, then the §8 error.
     - **Cancel** stops before the next piece.
- **Automatic language** is inferred from the transcript text (§6.4) and shown, e.g. "Urdu (detected)".
- **No speech found** gives the §8 error.
- **Whole clip:** the script covers the whole video. There are no start and end lines to pick (FR-4).

**FR-4 Line selection (removed in M23).** The user no longer taps a start and an end line: the video is already the clip. `ClipRange` defaults to the whole video (FR-5), and every line counts as selected. The tap rules, the highlight and the Next-when-both-set rule went away. The number stays so code and history keep their references.

**FR-5 Fine-tune (two steps since M19; changed in M23).** Both steps keep their own player over the same kept video file (FR-1); Next on step 1 opens step 2, and Back returns.
- **Step 1, Video** (`/fine-tune`, "Step 1 of 2" since M30; "Step 2 of 4" before). The player is pinned; under it the **Trim** tab holds the range, nudges, set-to-playhead and waveform below, and the **Crop** tab holds the frame (FR-6) and the moving crop (FR-22). Trim opens first; the tab stays as last used while the reel is open:
  - **Opening:** the player opens the kept video file at once. Nothing is downloaded (changed in M23).
  - **Player:** pinned above the scrolling rest; play, pause, and a seek bar over the whole video, drawn as an outline with only the clip range filled; the time already played is not coloured, so it never hides the clip range. The bar and its time follow the interpolated playhead, so they move smoothly between the player's reports; a report that differs a little is blended in, a big one is a seek. The time has a fixed width with equal-width digits, so the bar never changes size. Play starts where the seek bar is and does not stop at the clip end. (A "Play clip" button, which sought to the clip start and played, was removed after M30: the video arrives trimmed, so it duplicated play. It came back in M41, now stopping at the clip end, because the nudges and set-to-playhead trim the clip further.)
  - **Play the clip (M41):** a second, smaller button in the video's bottom-left corner (beside Play when the crop window is drawn and Play sits there) plays the clip from its start and pauses at its end, so the user hears the status as it will be. Tooltip "Play the clip from its start". It seeks to the clip start even while playing. Pause, Play or a drag on the seek bar ends clip playing; Play after that starts where the bar is and does not stop at the end. The clip end is read as it is now, so a nudge while it plays moves where it stops. Step 2, Lyrics, doesn't show it: its bar is already the clip.
  - **Range:** the clip defaults to the whole video, from 0 to its length. The nudges narrow it.
  - **Late picture (M41):** a video trimmed elsewhere can keep its sound from 0 but start its picture later (found: an MKV whose video track starts at 3.979 s). Players and the renderer can't start before the picture, so a seek there lands where the picture starts. The probe records the picture start (the video stream's `start_time` less the file's, rounded up to 0.1 s; `SourceVideo.pictureStart`, saved as `pictureStartMs`, 0 when missing). The clip defaults to start there, nudges and set-to-playhead can't go earlier, and a kept clip that starts earlier is moved up to it when the video is set again or Continue reopens it. Under the nudges the Trim tab says "The picture starts at <time>, so the clip can't start earlier." The sound before it is left out. A video added before M41 reads as 0 until it is shared or picked again. Not covered: an MP4 whose picture starts at 0 but whose first keyframe is later.
  - **Nudges:** buttons move start or end by 0.5 s. A nudge is ignored when it would make the clip shorter than **3 s** or move it outside the video. Both ends can be nudged, so a clip over 60 s can be shortened from either side. A clip that starts out invalid still accepts nudges towards a valid range; only nudges that make a rule worse are ignored.
  - **Set to the playhead:** tapping the Start time, or the End time, sets it to where the video is now, rounded to 0.1 s. The nudge rules apply: a time that would leave the clip under **3 s**, or outside the video, changes nothing. It does nothing until the player is ready.
  - **Waveform:** 60 bars over the whole video, with the clip highlighted.
  - **Long-clip warning:** above 60.0 s, "Longer than 60 s. WhatsApp Status may cut it." It never blocks.
  - **Frame:** size, fill, keep in view and free crop (FR-6), and a crop that moves (FR-22). The crop window is drawn over the player.
- **Step 2, Lyrics** (`/fine-tune/lyrics`, "Step 2 of 2" since M30): FR-21, which since M30 holds everything about the lyrics, including the script run that Processing showed.
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
  - Edited on the player (M29): the rectangle is drawn over the video with the rest dimmed. Drag it to move, and drag its bottom-right corner to resize. Under the size choices, a hint says so, with Reset. There is no separate editor.
  - Each side is at least 12 % of the source, and the rectangle never leaves the frame.
  - Reset returns to left 30 %, top 4 %, width 40 %, height 92 %.

**FR-7 Caption.**
- **Text:** the clip's lines' text, one per line, in the script's own language. Since M30 there are no Roman or English variants (ML Kit translation and §6.6 were removed) and no separate caption text: lines are edited on Lyrics (FR-21). With Show lyrics off the caption is empty.
- **Position and size** (the Style sheet on Lyrics, M30): Top or Bottom (default). Size S, M (default) or L is a font size of 4.5 %, 5.5 % or 6.8 % of output width.
- **Font:** by script (§6.5), with line height 2.1 for Nastaliq and 1.3 otherwise.
- **Block:** centred, padding 2 % of output width, margin 6 % of output height from the edge. What is drawn in it is the look.
- **Look and colour (M37):** in the Style sheet, **Look** (Box / Shadow), then **Colour**, four swatches for the chosen look, each drawn as that look over a picture-like strip, the chosen one outlined in the accent colour.
  - **Box** (text on a box filling the block): white on black at 38 % (the default, as before M37), black on white at 85 %, yellow `#FFD84D` on black at 60 %, white on green `#0A5A3C` at 85 %.
  - **Shadow** (no box; the text casts a shadow): white, yellow `#FFD84D` and gold `#F2C879` with a black shadow, and black with a white glow. The shadow is two layers, a tight one (offset 4 % and blur 6 % of the font size, at 90 %) and a soft one (no offset, blur 18 %, at 70 %), so it scales with S, M and L.
  - Each look keeps its own colour: Box → Shadow → Box comes back to the Box colour picked before.
  - The look and both colours are kept with the fine-tune (FR-24) and carried over by a start-over; a fine-tune kept before M37 reads as the default. A new reel starts from the look and colours used last, kept in preferences (`caption.look`, `caption.boxColours`, `caption.shadowColours`).
- **Overflow:** if the block would pass 35 % of output height, the font shrinks in 5 % steps down to 60 % of the chosen size, then the text is clipped with an ellipsis.

**FR-7a Caption lines, one at a time (M11).** The exported reel shows one caption line at a time, never the whole caption at once.
- **Lines:** each non-blank line of the caption text is one cue.
- **Timing:** while the caption has one line per picked script line, each cue shows from its script line's start to its end, counted from the clip start and clamped to the clip (so a nudge moves them with the clip). A cue left with no time inside the clip is dropped.
- **Edited text:** adding or removing lines loses the pairing, so the clip is shared out in proportion to each line's length.
- **Between lines:** only the branding shows.
- **Look:** each line is laid out as in FR-7 on its own, so the font fits each line, not the longest.
- **Render:** Dart paints the branding on its own plus one transparent PNG per cue at output size. Kotlin lays the branding over the clip and swaps in the cue's PNG while it is due, opening each PNG only when its line is due. The PNGs stay until the render ends (cancel, error or done), then are deleted.
- **Preview:** the Lyrics player shows the reel as it will look (FR-21); Caption's still preview went with the screen in M30.

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
- **Cancel:** stops the render, deletes the partial file and returns to Lyrics.
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
  - Tap opens Fine-tune without Processing. It reopens from the kept `source.<ext>`. When that file is missing, the row says "Choose or share the video again" and the §8 "Video not found" message shows.
  - Long-press offers Delete, which removes that script, its unfinished progress and the kept video.
- **Fine-tunes to continue (FR-24):** a Continue row replaces the video's script row; long-press offers Delete, which removes the fine-tune and the video's script, as Delete on a script row does (changed 2026-11-06: the script row used to show again).
  - There is one row per video and requested language.

**FR-12 Settings: speech models (retired in M10, 2026-11-04).** On-device Whisper and its model downloads were removed; the number stays so code and history keep their references. The Settings screen now starts with FR-12a.

**FR-12a Settings: script writing (Groq).** The first category of Settings, on its own screen "Groq key" since M33 (FR-31). Every script needs a saved key.
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
- **Privacy note** under the heading: "Writes the script. Your video's audio (cleaned, mono, 16 kHz) is sent to Groq in pieces. Groq's terms apply." (changed in M36: the Fix with Groq sentence went with FR-19) There is no switch: a saved key turns Groq on and Remove turns it off.
- **Key storage:** `flutter_secure_storage` (Android Keystore). The key is never logged, and never written into saved files, notifications or error text. It goes only to `api.groq.com`.
- **No key:** a new script stops with "Writing a script needs a free Groq key." (§8), with Settings and Back, before any audio is cut. Saved scripts need no key.
- **Consent (M27):** the first send waits for the user's OK (FR-30); the "Sending to Groq" row under the key shows it and can withdraw it.

**FR-17 Real lyrics (M12; removed in M17).** Script had a "Real lyrics" button that replaced the script with time-synced lyrics from lrclib.net. M17 removed the button and the whole lyrics feature (`lib/src/features/lyrics`) to keep only Fix with Groq (FR-19). Git history before M17 has the design. Scripts already saved with source `lrclib` still reopen like any saved script.

**FR-18 Fix the script with an AI agent (M13; buttons removed in M17; the rest removed in M36).** Copy for AI and Paste AI reply took the script to any AI chat that could search the web and brought the corrected text back. M17 removed the buttons; the shared prompt and reply parsing (`script_exchange.dart`) went with Fix with Groq in M36. Git history before M36 has the design.

**FR-19 Fix the script with Groq (M15; removed in M36, 2026-11-10).** A button on Fine-tune · Lyrics sent the clip's lines (at most 30) and the video's name to Groq's web-search model (`openai/gpt-oss-120b` with `browser_search`, §10 #6) and replaced the lines' text with the real lyrics it found. The owner removed it in M36; the user fixes words by editing the lines (FR-21). Since then the only upload is the script audio (FR-12a). Scripts saved after a fix (source `edited`) still reopen like any saved script. Git history before M36 has the design.

**FR-13 Offline.** Saved scripts and export work without a network. Writing a new script needs one (Groq). Once a video is kept, nothing else needs a network.

**FR-14 Saved scripts (changed in M23).**
- **Key:** the video's fingerprint ID (FR-1), requested language (`auto` or a code) and source: `groq-whisper-large-v3` (`groq-whisper-large-v3-turbo` before M24: those scripts stay readable and the newest source wins, but a turbo partial run is not resumed). (The `captions` source went with YouTube in M23.) The entry holds the transcript (with the inferred language), the source and the save date.
- **Files:** `transcripts/<videoId>/<requested>-<source>.json` in the app support directory. The video's folder also keeps `video.json` (name, length) for Recent. The video itself is kept at `sources/<videoId>/source.<ext>` (§4).
- **Same video again:** Lyrics opens on the newest saved script of the video, in any language, and shows "Using the saved script from <d MMM>" (M30).
- **Write it again** (Get again in the same language since M30): runs speech to text with Groq and replaces the saved script.
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
- **iOS (M26):** there is no foreground service. While a job runs the app holds a background task (`beginBackgroundTask`, `SystemChannel.swift`), which lets it go on for tens of seconds after the user leaves; then iOS suspends the app and the native side posts "Work paused" · "Open Status Studio to carry on. A script resumes from its last saved piece." (nothing if notifications were refused). A script resumes from its last saved 90 s piece when the user comes back (FR-14). An export does not run in the background at all: iOS refuses GPU work then and Core Image would draw nothing without an error, so the renderer's frame loop waits (`ForegroundGate`) while the app is not in front, draws again a frame that was cut by the app leaving, and goes on when the user returns (if iOS ends the process meanwhile, the user exports again). The ongoing progress notification does not exist on iOS (the battery question and its Settings row went on Android too in M27); the result notification is the same local notification (`flutter_local_notifications`, permission asked the first time work starts); `flutter_foreground_task` is Android only, behind `backgroundWorkPlatformProvider` (`PluginBackgroundWorkPlatform` or `IosBackgroundWorkPlatform`). Settings shows the notification row and "Open Settings", and a hint that says iOS lets work go on for a short while only.
- **Asking once (changed in M27):** the first time work starts, the app asks for notifications (Android 13+; iOS asks once). It never asks again on its own. Until M27 it then asked for exemption from battery optimisation (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`); Google Play allows that request only for listed uses, which this app is not, so the permission is removed from the manifest (`tools:node="remove"`, in case a plugin brings it back) and the app no longer asks. The `dataSync` foreground service keeps running under Doze and battery saving without it.
- **Settings, "Background work":**
  - One row: notifications on. It shows "Allow" when they're off; a refused notification permission opens App info instead. (The battery optimisation row went in M27.)
  - A hint: "On Xiaomi and some other phones, also set Battery saver to No restrictions in App info." with "Open App info".
- **Lifetime:** the service survives Home and lock, and stops when the task is swiped away (manifest `android:stopWithTask`), because the work's Flutter engine ends with the task. The plugin's own `stopWithTask` option isn't used: it stops whenever the app leaves the screen.
- **Limits:** Android 15+ gives `dataSync` 6 hours a day. After that the service stops, and work continues only while the app is open.

**FR-20 Launch animation (M16).** Opening the app never shows a white screen.
- **Native splash:** Android's launch window is the app background `#0E1311` with the §7 logo (light variant) centred at 144 dp. Android 12+ shows the same logo through its splash API (`windowSplashScreenAnimatedIcon`, a 288 dp icon with the 144 dp logo in the middle). iOS's launch screen has the same background.
- **Light phones (M35, FR-32):** on a phone in light mode the launch window, the Android 12+ splash, the window behind Flutter and iOS's launch screen use the light page `#F5F8F6` instead, with the same logo and dark status bar icons; the animation's first frame matches them. On iOS only the background follows: its launch logo is still the §15 placeholder, which M35 doesn't fix (Claude's call). The iOS Share Extension's screen follows the phone's mode the same way, since it can't read the saved choice either (Claude's call). Flutter's animation follows the phone's mode, not the saved theme; its exit fade reveals Home in the chosen theme.
- **Animation:** Flutter's first frame matches the native splash exactly, then plays for 1.7 s over Home, which is already built underneath:
  - the five bars move like a voice waveform and settle back;
  - the brackets close in on the bars and open again, like trimming a clip;
  - "Status Studio" fades in under the logo;
  - the splash fades out while the logo grows slightly.
- **No overlap:** bars never reach the bracket arms and brackets never touch the bars.
- **Reduce motion:** when the system asks for no animations, Home shows straight away.
- **Taps:** taps don't reach Home while the splash covers it.

**FR-21 Fine-tune lyrics (M18; its own step since M19).** Step 2 of Fine-tune lists the clip's lines, editable, with the video playing with the lyrics on it.
- **One screen (M30), top to bottom under the player:**
  - **Show lyrics on the clip**, a switch, on by default. Off: the reel has no caption and the hint says "No lyrics on this reel. Nothing leaves your phone and you need no key." The lines are kept, and turning it on again brings them back. Turning it off while a script is being written stops the run.
  - **A script with no line inside the clip (M40):** a trim over a stretch with no sung line. The tools (Style, Get again) and the run's section as with lines, then "No lines in this part of the video." and **Add line**, which asks for a line and puts it into the script at the playhead in time order, 2 s long and cut at the clip end (as Type them myself places it). The caption is empty until a line is added. Before M40 the whole script was selected instead.
  - **No lines inside the clip yet:** the Get card, with the Language dropdown (FR-2), **Get lyrics from Groq** and "Sends the cleaned voice to Groq with your key. The picture never leaves your phone."; under it **Type them myself**, which asks for a first line and puts it at the playhead, 2 s long and cut at the clip end. When the reel has no lines and no run, Lyrics first opens the newest saved script of the video (FR-14).
  - **While writing:** the step under way with its bar, amount and time left, and Cancel; lines appear below as they arrive. A failure shows its §8 message and actions here, with Dismiss in place of Back.
  - **With lines:** **Style** (a bottom sheet with Position and Size, FR-7) and **Get again** (FR-2; Fix with Groq between them was removed in M36), then the line list below. Get again asks "Replace your edited lines?" (Replace, Keep) when lines were edited.
  - **Export reel** at the bottom, off while a script is being written ("Wait for the lyrics, or Cancel."). The player is released before Export opens.
- **Lines:** only the clip's lines are listed (those inside the nudged range). Lines around the clip are not shown. Every listed line reacts to a tap.
- **Player:** the reel as it will look: the video cut to the output frame (FR-6) with the crop where FR-22 puts it at that moment, and the line due on it, laid out as FR-7 says (caption position and size). Play and pause, and a seek bar over the clip only: it starts at the clip start, stops at the clip end (playing again from the end starts at the start), and has no "Play clip" button. Nothing outside the clip can be seen or reached.
- **Tap a line:**
  - **While paused:** seeks to the line's start.
  - **While playing (tap to time):** the line's start becomes the playhead. The line that was highlighted at that moment ends there, so the new highlight replaces it. The tapped line keeps its length (at least 1 s), cut at the next line's start.
  - **Ignored:** a tap earlier than the previous line's start, or on a line earlier than the one playing, so lines stay in time order.
- **Highlight:** the line whose start ≤ playhead < end is highlighted, only while it lasts; between lines nothing is, and the video shows no lyrics.
- **Edit:** a pencil opens a text field with the line's text. Saving an empty text keeps the old one. A line break becomes a space, so a line stays one caption line.
- **Reorder:** a drag handle moves a line's text to another place. The list is part of the screen's own scrolling (M40), so a drag near the top or bottom edge scrolls the screen and a line can be dropped on a row that was out of view. Times stay where they are, so lines stay in time order: reordering swaps which text sits at which time.
- **Add:** "Add line" asks for text and inserts a line at the playhead, 2 s long (cut at the next line's start; the line it lands in ends there). When a line starts exactly at the playhead (right after tapping it while paused), that line's time is shared: the new line takes the first half, at most 2 s. The playhead must be inside the clip; Add line is off outside it.
- **Delete:** removes a line. The last line can't be deleted.
- **After an edit:** the clip stays (M23: it no longer follows the lines), and the lines inside it are the listed ones again, also after an added line. The caption is refilled from them, and the script is saved as the newest script (source `edited`, FR-14) after 1 s without edits and when the screen closes.
- **Script still being written:** once any line is edited, lines that arrive later are not added to this reel (the edited lines win). When the run finishes after an edit, the edited lines are saved again right after the run's own save, so the `edited` script is the newest and the video reopens with the edits (M40). A script reopened from the saved ones (not written) saves nothing again.

**FR-22 Moving crop (M19).** Where the crop window sits can change while the clip plays, for Crop to fill and Free crop. Blur background and 16:9 keep the whole frame, so nothing moves.
- **What moves:** the window's position only. Its size is fixed for the clip: the preset's largest rectangle, or the free crop's width and height. It moves only along an axis where it has room (a 9:16 window in a 16:9 frame moves left and right; a 4:5 window in a 9:16 video moves up and down). With room on neither axis, the switch is hidden.
- **Anchor:** a position is an anchor `(x, y)`, each from 0 to 1 across the room the window has to move (0 = left or top, 1 = right or bottom). The frame keeps a base anchor (default 0.5, 0.5). Keep in view's Left, Center and Right set its x to 0, 0.5 and 1. A free crop's anchor is `left / (1 − width)` and `top / (1 − height)`, and its base is `freeCrop.left` and `top` themselves.
- **Keyframes:** a keyframe is a time in video time, an anchor and how it is reached: **Glide** or **Cut**.
  - **Glide:** the anchor moves in a straight line from the previous keyframe's anchor to this one, arriving at this keyframe's time.
  - **Cut:** the anchor holds the previous keyframe's value until this keyframe's time, then jumps. At exactly that time it has jumped (Dart and Kotlin agree).
  - Before the first keyframe the anchor is the first keyframe's; after the last it holds. The first keyframe's way of arriving has no effect, so its Glide and Cut choice is hidden.
  - Keyframes are kept in video time, so nudging the clip does not move them. A new keyframe's time is inside the clip, with the clip's ends rounded inwards to 0.1 s first so a snapped time never falls outside; it snaps to 0.1 s, and one within 0.25 s of another replaces it.
  - A keyframe outside the clip (after a nudge or a line edit) has no effect on the reel except as the position the crop starts from or holds. Its chip is dimmed, and it can still be deleted.
- **New script:** getting a new script (Get again) leaves the clip, its nudges and the keyframes alone, since the clip is the whole video plus the nudges; it only replaces the lines. Nudging a clip so that a keyframe falls outside it dims that keyframe, as above. (Changed in M23: picking other lines no longer exists.)
- **Off by default:** "Move the crop at each scene" (named "Move the crop during the clip" until M30) is a switch on the Crop tab. Off, the crop is as FR-6 says. Turning it on creates a first keyframe at the clip start from the current crop. Turning it off removes the keyframes and keeps the crop where it was at the clip start: Crop to fill stores it as the base anchor, Free crop writes it into its rectangle.
- **Editing (on):**
  - **Drag:** dragging the crop window over the player moves it with the finger and writes one keyframe, at the playhead where the drag started, when the finger lifts: it replaces the one there or adds one that glides in. Keep in view is hidden while the switch is on.
  - **Scene strip (M30; chips before):** on the Crop tab, one block per position across the clip, as wide as it lasts and labelled with its length ("5 s"; one decimal under a second). A position lasts from its keyframe to the next one, or to the clip end; the first block starts at the clip start with the keyframe in force there, and keyframes after the clip end are not drawn. A Cut is marked with scissors. A line follows the playhead. Tap a block to select it and jump to it. The strip always fits the width and never scrolls.
  - **Selected position card:** "0:04.0 – 0:09.0 · 5 s", Arrives by Glide or Cut (not on the first), and Delete. Any position can be deleted except the only one left.
  - **New position here:** beside Follow the person; adds a Glide keyframe at the playhead holding the crop where it is, and selects it to be dragged. Outside the clip it says "Play or seek inside the clip first."
  - **Touch:** the window can be dragged from anywhere inside it, and from a margin around its outline. A cancelled drag (a system gesture, a call) writes nothing and the window goes back to following the playhead.
  - **Free crop on the player:** while the crop moves, dragging the window writes a keyframe and the corner changes only the rectangle's size; keyframes place the window.
  - **Only while it can move:** the window outline and the strip show only while the crop can move (not for Blur or 16:9, or a source with no room). Free crop's outline always shows, since it is edited there (FR-6). The switch stays while keyframes exist, so they can be turned off.
- **Changing the size or fill:** keyframes stay but have no effect while Blur or 16:9 is chosen, and come back when a crop is chosen again. Changing the free crop's size keeps them.
- **Rounding:** each keyframe's pixel rectangle is rounded as §6.3 says. The preview moves in whole pixels; the render moves in fractions of one.
- **Render:** the keyframes go to Kotlin as rectangles (§6.3.1) with their times counted from the clip start; the crop between them is computed per frame (§6.3.2). A reel with the switch off renders exactly as before.
- **Previews:**
  - Both Fine-tune steps follow the playhead frame by frame while playing (the player reports its position every 100 ms or so, so a ticker adds the time since the last report).
  - Fine-tune · Lyrics shows the moving crop and the lyric line due (FR-21), by extending `reel_preview.dart`.
- **One decoder at a time:** when Lyrics opens, the Video step's player is released first (Lyrics opens after the frame that disposes it), and it is made again once Lyrics has slid away. The same holds one step on: Lyrics' player is released before Export opens and comes back once Export has slid away (until M30 Caption sat between them and did the same). Found 2026-11-06 on the Redmi Note 11: with those two players alive underneath, the export's own 1080p H.264 decoder failed at `MediaCodec.configure` with `0xfffffff4` (NO_MEMORY, the Qualcomm decoder out of memory), so the export never started.
- **Height:** every player on Fine-tune is at most 260 dp high and at most 40 % of the screen height (M30), so a vertical video leaves room for the controls; the crop outline stays on the video.
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
- **Keyframes:** Ramer–Douglas–Peucker with a tolerance of 0.03 of the room. A scene cut is a Cut keyframe at the cut time. A jump of more than 0.3 of the room between neighbouring samples is a cut too, but only when no face of the frame before continues into the new frame and none comes back (or was there) within 2 s, so a bystander, or a person missed for a moment, is not a cut; and not when a detected cut is within half a second of it (so a soft cut the detector missed still cuts). (Replaced by FR-27 in M25: such a cut is not a boundary.) A cut within half a second of the clip start gives the first keyframe the new shot's anchor. Everything else glides. Times snap to 0.1 s and stay inside the clip (FR-22); the first keyframe is at the clip start, rounded inwards to 0.1 s; keyframes are at least 0.5 s apart; at most **12**: above that the tolerance grows by 1.5× until it fits, and if many scenes still leave more, the keyframes that change the crop least are dropped (never the first), so the end of the clip is not cut off.
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

**FR-24 Continue a fine-tune later (M21; changed in M23).** Work on Fine-tune is kept on the phone as it changes, so the user can leave and carry on from Recent, hours or days later. There is no Save button. A reel without lyrics (FR-29) is not kept.
- **Since M30: one per video, with or without lyrics.** A fine-tune is kept from the moment Fine-tune · Video opens, in `transcripts/<videoId>/draft.json` (version 2): video, language, the Show lyrics switch, clip, frame, caption and whether lines were edited, and the kept lines (selection and fingerprint) only once there were lines inside the clip. Saving also writes the video's `video.json`, so Recent can title it. Version 1 files (`draft-<language>.json`) still read: the newest of a video wins and the others are deleted; the next save replaces it. Recent shows a video's fine-tune in place of all its script rows. A fine-tune without lines continues on Fine-tune · Video with no run started. When its script is gone or changed, the clip and the crop are kept too, as long as the clip still fits the video. Long-press Delete removes the script only when the fine-tune had lines. Where the bullets below differ, this paragraph wins.
- **What is kept:** the clip's start and end (FR-5; the picked lines of FR-4 went in M23), the frame (size, fill, base anchor, free crop and the moving crop's keyframes, FR-6 and FR-22), the caption settings (FR-7) and whether lines were edited (FR-21).
  - Neither the script nor the video is copied. The kept fine-tune names its saved script by video and requested language (FR-14), and its video by the fingerprint ID; the video is the kept `sources/<videoId>/source.<ext>` (FR-1). The source is `edited` when lines were edited; otherwise it is the newest script, the one FR-14 reopens.
  - It also keeps a fingerprint of the script's lines from the first line through the last line of the clip (a 32-bit FNV-1a hash of each line's start, end and text, stable across runs). That tells a changed script apart, and lines added later (a script still being written) don't count.
- **When:** 1 s after the last change while Fine-tune · Video is open or under a later step (Lyrics, Export). Also at once when Fine-tune · Video closes (Back included) or the app goes to the background.
  - A change is anything that changes the reel: a nudge, an edge set to the playhead, size, fill, crop, a keyframe, a line edit, a caption setting.
  - A fine-tune equal to the last one written is not written again, unless its file was deleted since. Continuing a fine-tune counts as writing it, so leaving Fine-tune without a change keeps its date.
  - A failed write, whatever its cause, is ignored and never stops later saves, because the work is still in the app.
- **One per video and language:** a new fine-tune of the same video and requested language replaces the kept one. Back to Source leaves it as it was.
- **File:** `transcripts/<videoId>/draft-<requested>.json` in app support, beside the scripts. It is written as `.part` and renamed, and carries `version` 1.
  - A file that can't be read, or has a newer version, is ignored and stays on disk. Its video's script row shows instead.
  - Saving counts as a use of the video. The file goes with the video's folder under FR-14's retention (90 days after last use, at most 200 videos).
- **Recent (FR-11):** a kept fine-tune has a row with a tune icon, the video's name, `Fine-tune · <clip length> · <d MMM>` (e.g. `18.5 s`, the date of the last save) and "Continue" on the right.
  - It replaces the script row of the same video and language, so the video shows once. It sorts by its last save among the reels and scripts.
  - **Tap, script found and still fitting:** opens Fine-tune · Video with everything as it was, and Back shows Script. Nothing is downloaded; the player opens the kept file.
  - **Tap, kept video missing** (the folder was cleaned or the file deleted): the §8 message "Video not found, choose it again" shows, and Choose a video opens. The script and the draft stay.
  - **Tap, script still being written:** the lines Groq had written so far count as the script when they hold the clip's lines (the same fingerprint check). It opens as the first case, and the run carries on and adds the rest.
  - **Tap, script gone** (no saved script for the video and language, and no unfinished progress that holds the clip's lines): opens Fine-tune · Video without starting a run (M30), with the snackbar "This fine-tune's script is gone. Get the lyrics again on the Lyrics step; the clip's size and caption style are kept."
  - **Tap, script changed** (the fingerprint differs, the clip's lines run past the script's end, or the clip runs past the video's end; e.g. after Write it again): opens Fine-tune with the current script and the snackbar "The script changed since this fine-tune was saved. Check the clip's start and end; the size and caption style are kept."
  - In both of those cases the kept fine-tune is deleted. What carries over: size, fill, the crop stopped where it was at the old clip start, and the caption's position and size. The clip's nudges and the caption text do not.
  - **Long-press:** offers "Delete". It deletes the kept fine-tune and the video's script for its language (changed 2026-11-06: it used to delete only the fine-tune, and the script row showed again).
- **Export:** a finished export (the reel is in Recent, FR-9) deletes the kept fine-tune. Going back from Done and changing something keeps a new one.
- **Not kept:** the per-scene choices of FR-27 are written into the crop's keyframes, so the keyframes are kept; the scene questions themselves are not. Also anything before Fine-tune opens, the playhead, and the selected keyframe chip.

**FR-26 Clean the voice (M24).** Before Groq hears the audio, FFmpeg cleans it, so the lyrics are more accurate. Nothing is uploaded for this and no key is needed.
- **Filters:** the bundled FFmpeg's built-in filters only, all present in `ffmpeg-kit-min` 1.0.3. The defaults are `highpass=f=80,lowpass=f=7500,afftdn=nr=12:nf=-30:tn=1,dynaudnorm=f=200:g=11:p=0.9`: cut rumble below 80 Hz, cut hiss above 7.5 kHz, reduce steady noise (hum, hiss, hall noise), then even out the loudness. The values are defaults until §10 item 8 tunes them. **Check result (2026-11-06):** on the one reference clip cleaning did not beat raw (43.2 % against 42.3 % CER; most errors are lines Groq dropped, not noise), so the filters are unproven; the values were not changed.
- **What it can't do:** filters cannot separate a voice from a harmonium or a daf. They share the voice's band, so they stay in the audio. Say so plainly in the help text, and never promise that instruments are removed.
- **Where:** `-af <chain>` in the piece run of FR-3, before the FLAC encode: the same command cuts, cleans and writes the 90 s pieces. The clip's own audio in the render is never changed; only what Groq hears is cleaned.
- **Progress:** Lyrics shows "Cleaning the voice" while the run is in that step (Processing did until M30), and so does the notification (FR-16).
- **Reuse:** cleaned pieces are kept in the video's folder, in `pieces_<seconds>_<8 hex of the FFmpeg command's SHA-256>`, so a retry or another language doesn't clean again and a changed chain, rate or format never reuses old pieces. A `finished` marker, written after FFmpeg returns, makes a cut reusable (FFmpeg appends to `pieces.csv` as it goes, so the list alone can't tell). Other `pieces_*` folders and unfinished cuts are deleted. They go with the video's folder.

**FR-27 Choose what to follow in each scene (M25).** Replaces FR-23's automatic pick and FR-25's single chooser. With "Move the crop during the clip" on and the crop able to move (FR-22), "Follow the person" becomes a walk through the clip's scenes. The app never assumes: at every scene the user picks what to keep in frame. Nothing is uploaded and no key is needed.
- **Scenes:** the clip's scenes are found as in FR-23 (scene cuts, plus the jump rule), except that a cut within half a second of the scene before it, or of the clip's end, is not a boundary (the keyframe spacing would drop that scene's Cut, so its answer would count for nothing; the short stretch joins its neighbour). Each scene is asked once, in order, even with one face on screen, and even with none.
- **Choices:** at each scene the user picks one of three:
  - a **face** (FR-23's face tracks and the ML Kit detector);
  - a **body** (a person box from EfficientDet-Lite0 on TensorFlow Lite, on the phone: §10 item 7);
  - a **fixed spot**, a point the user taps, held for the whole scene.
- **Never chosen for the user:** there is no "Choose for me", no automatic pick, and no carry-over of a choice to another scene by look-alike.
- **Picture:** each scene shows its fullest frame (the one with the most faces, then the biggest), at the clip's aspect ratio.
- **Markers (changed in M32):** each face and body box is drawn as its four corners only (2 dp, at most 12 dp long; faces in the accent colour, bodies in white), and its number ("1", "B1") is in a small tag just outside the box: above it, or below it when the box touches the top. Tapping the tag picks its face or body too. Until M32 the outline was whole and the number sat inside the box's top-left corner, covering small faces and the head of a body.
- **Sheet:** a bottom sheet per scene.
  - Title "Scene 2 of 5 · 0:07–0:12". Hint "Tap a face, a body, or the spot to keep in frame."
  - A tap within 24 dp of a face picks that face (the nearest). A tap inside a body box picks that body. A tap anywhere else picks that spot, and a pin shows where before the next scene. A pick moves on to the next scene; the last pick ends the walk.
  - Buttons: "Back" (returns to the earlier scene to change its answer; the choices already given are kept) and "Cancel" (stops; nothing changes).
  - **Screen readers:** "Person 1", "Body 1", and a "Keep the centre" action that picks the centre spot.
  - The sheet pops with its result and the controller acts after the await, so a double pop can't happen.
- **Keyframes:** a face or a body is followed as in FR-23 (anchor, smoothing, dead zone, simplification) within its scene only. A body's anchor is its box's centre, in its upper third. A spot is a constant anchor with a **Cut** keyframe at the scene start. A scene's start is a Cut either way, and its keyframe is not snapped to 0.1 s like the others: it sits 10 ms before the cut's own time (below 100 fps; a faster source needs a smaller lead), so the renderer's whole-millisecond frame times never show the new shot's first frame with the old crop (a snapped time was up to 50 ms off, one or two frames of the wrong crop: a visible jerk). A cut the detector missed and the jump rule found is only as exact as the 4 frames a second it was found in. The 12-keyframe cap and the 0.5 s spacing of FR-23 still apply. The cap keeps every scene's Cut keyframe first (the user chose each one); other keyframes are dropped before any Cut. If the clip has more than 12 scenes, the first 12 are asked and the rest hold the last anchor (the 12th scene's end shown is the clip's end), and every sheet warns: "This clip has more than 12 scenes. The crop follows the first 12."
- **Bodies:** the detector looks at each asked scene's picture frame before the first question (the "Finding the person…" bar covers it), so the bodies offered there are its boxes with a score of at least 0.4, the biggest 6, numbered left to right. A body is tracked only once chosen: after the last answer, the detector looks at every other frame of each scene answered with a body (the bar shows again), and the same distance rule as faces joins its boxes, and its other stretches in that scene. If the body model can't load or run, no bodies are offered and faces and spots work as before. It runs in its own isolate, so the screen stays responsive.
- **Frames:** they stay in the cache folder while the sheet is open, and are deleted when the user finishes, taps Cancel, dismisses the sheet, leaves the step, or changes the clip, size, fill or free crop size.
- **Cancel or dismiss:** nothing changes. A hand edit made while frames were being looked at still wins.
- **After:** the snackbar "The crop follows your choices (6 keyframes). Drag the crop or tap a position to adjust." Everything stays editable as FR-22 says.
- **Replacing:** as FR-23: when more than one keyframe exists, "Replace your crop keyframes?" with Replace and Keep, asked before the first scene.

**FR-29 Without lyrics (M28; changed in M30).** Lyrics are optional. A reel can be made with no script: no Groq key is needed and nothing is uploaded.
- **Since M30** the choice is the Show lyrics switch on Fine-tune · Lyrics (FR-21), not a button on Source. Off: the caption is empty, the reel carries only the branding, and Export's summary says "No caption". The lines are kept, so turning it on brings them back. A script still being written is stopped.
- **M28–M29 (history):** Source had "Make it without lyrics" under "Get the script", which skipped Processing and Lyrics and opened Caption, where the user could type a caption. Typed lyrics are now Type them myself on Lyrics.
- **Continue later (FR-24):** since M30 a reel without lyrics is kept like any other.
- **File name (FR-9):** with an empty caption it is the `<kalam>` part only, or `reel` when the title has no words.

**FR-30 Consent before sending to Groq (M27).** Nothing of the user's goes to Groq until they agree, once, on a consent screen (App Store guideline 5.1.2(i); Google Play User Data policy, prominent disclosure and consent).
- **When:** right before the first send: a script that Groq must write after a tap on Get lyrics from Groq or Get again (not a saved one, FR-14). (A tap on Fix with Groq asked too, until M36.) The key is checked first, so a user without one gets the §8 "needs a free Groq key" message and no consent screen. A reel without lyrics (FR-29) never asks.
- **Screen** (full screen, `groq_consent_screen.dart`), title "Send to Groq?" ("Send audio to Groq?" until M45):
  - "To write the lyrics, and to find a topic in a linked video, Status Studio sends to Groq, a third-party AI service, using your own Groq key."
  - "What is sent: the video's sound, cleaned to one channel, in pieces; and, to find a topic, the video's transcript and the topic you type." (M36 dropped the Fix with Groq sentence; M45 added the transcript and topic, FR-36.)
  - "What is not sent: the picture. Nothing goes to us: Status Studio has no server and no account."
  - "Groq's terms and privacy policy apply (groq.com). You can withdraw this any time in Settings."
  - Hint: "Without lyrics or a link, nothing leaves your phone and you need no key." ("Without lyrics," until M45.) Buttons: Not now, Agree.
- **Answer:** Agree is kept (`groq.uploadConsent.m45` in shared preferences since M45; an agreement kept under `groq.uploadConsent` before it no longer counts, so the user is asked once more, and Withdraw removes both) and the work carries on: the script run starts again. Not now keeps nothing and sends nothing: Lyrics shows the §8 message with Continue (the screen again) and Dismiss. The user is asked again the next time.
- **Enforced at the send:** `GroqClient` takes a required `beforeUpload`, which the app sets to the consent check (`GroqConsentStore.requireGiven`); it runs before every audio piece and every Fix request and throws `NoGroqConsentException`. The key check (`GET /models`) sends nothing of the user's and doesn't call it. The script pipeline also checks right after the key, before any audio is cleaned, so the user isn't made to wait for nothing.
- **Settings:** under the Groq key, "Sending to Groq": "Allowed" with Withdraw, or "Not allowed: you will be asked before anything is sent". Consent is given only on the consent screen. Withdrawing while a script is being written stops it before its next piece; the pieces already written stay saved (FR-14), and the Lyrics footer's Retry asks again. Removing the key doesn't withdraw consent.
- **Privacy:** the answer is never logged and, like the key, never written into saved files, notifications or error text.

**FR-31 Settings categories, Support and About (M33).** Until M33 the app version was shown nowhere.
- **Settings is a list** (task 4): one row per category, each with an icon, a subtitle and a chevron, opening its own screen with the category as its title. Groq key ("Writes the lyrics, and what is sent to Groq"), Background work ("Notifications when work is done"), Support ("Feedback or a complaint, by email, WhatsApp or a call"), About ("Version <version> (<build>) and licences"). The screens drop their own section heading, since the title says it. The §8 "needs a free Groq key" Settings actions open the Groq key screen directly. A shared video arriving on any Settings screen opens Source without asking, as on the list (FR-1).
- **Support** (`support_section.dart`): hint "Tell us what you like or what went wrong. Details of your phone (model, system, processor, memory, screen, network) and the app version are added to the message, so you can see them before you send." Then a Feedback | Complaint choice (Feedback first and selected), a message box ("Your message", 3 to 6 lines), and three buttons: **Email**, **WhatsApp**, **Call**.
  - Email and WhatsApp are off until the box has text. Each opens the user's own app with the message filled in; the user sends it there, and the app sends nothing itself. The text stays in the box afterwards, because the app can't know whether it was sent.
  - **Email:** `mailto:arehmananis@hotmail.com`, subject "Status Studio feedback" or "Status Studio complaint", body = the message.
  - **WhatsApp:** `https://wa.me/923478330955?text=…`, text = the subject line, a blank line, then the message. Without WhatsApp the phone opens wa.me in the browser, which offers to install it.
  - **Call:** `tel:+923478330955`, the dialer with the number; nothing else is carried. Always on.
  - **The message:** the typed text, a blank line, a `—` line, then "Feedback" or "Complaint" · "Status Studio <version> (<build>)" and one line each (M33 task 3 added the last four):
    - "Phone: <maker> <model>" (Android) or "<model name>" (iOS); "System: Android <release> (SDK <n>)" or "iOS <version>".
    - "Processor:" on Android 12 and later the chip's maker and model (`Build.SOC_MANUFACTURER`, `SOC_MODEL`, e.g. "QTI SM6225"), before that or when unknown `Build.HARDWARE`, then " · " and the first ABI; read through `status_studio/system`'s `processorName`. On iOS the model code (`utsname.machine`, e.g. "iPhone15,4"), because iOS doesn't name the chip.
    - "RAM: <total> GB, <free> GB free", one decimal, from `device_info_plus`.
    - "Screen: <width> × <height> px at <ratio>×", the display's physical pixels from Flutter.
    - "Network:" the connection types from `connectivity_plus`, joined by commas: Wi-Fi, Mobile data, Ethernet, VPN, Bluetooth, Satellite, Other or None. It is the connection type only: it can't tell whether the internet is reachable, so it isn't called "Internet".
    - Read fresh for every message (free memory and the network change), on the phone only. The version comes from `package_info_plus`.
  - **No app for it** (no mail app, a tablet that can't call): a snack bar "No email app found. Write to arehmananis@hotmail.com.", "Couldn't open WhatsApp. Message +92 347 8330955.", or "This device can't make calls. Call +92 347 8330955."
- **About** (`about_section.dart`): the Trim logo (§7) at 48 dp, "Status Studio", "Version <version> (<build>)" (from `package_info_plus`, so it follows `pubspec.yaml`), and "Turns a video you have trimmed into a short status clip, with its lyrics in any language." Then (M43) "Free software under the GNU GPL, version 3. Source code: github.com/abdul-rehman-ghazi/status-studio". Then "Open-source licences", Flutter's licence page with the same name, version and logo.
- **Not in M33:** a privacy policy row (§9.1, waits for hosting).
- **Calls made by Claude, not the owner:** the category names, icons and subtitles; Email and WhatsApp stay off until there's text; the message layout above.

**FR-32 Theme choice (M35).** Until M35 the app was dark only. Asked by the owner (2026-11-10); the owner chose the light colours, the place in Settings, the default and the launch behaviour from mockups the same day.
- **Choices:** Light, Dark and System. **System is the default**, for new installs and for people updating alike, so after the update a phone in light mode shows the app light. System follows the phone's dark mode and changes with it while the app is open.
- **Where:** a new Settings category, **Appearance**, the first row of the list (FR-31), icon `Icons.contrast`, subtitle "Theme: Light", "Theme: Dark" or "Theme: System". It opens `/settings/appearance` titled "Appearance": a "Theme" section label, then three radio rows, Light, Dark, and System with the subtitle "Follows the phone's dark mode". Tapping a row applies it at once, with no Save button and no restart.
- **Saved:** in shared preferences under `appearance.theme` (`light`, `dark` or `system`), read before the first Flutter frame, so the app never draws a frame in the wrong theme. Nothing saved, or a value the app doesn't know, means System.
- **Light colours** (owner's choice C: one deeper green on a soft mint page; the bright green fails as text on white, 1.9:1):

  | Role | Dark (unchanged) | Light |
  |---|---|---|
  | Page background | `#0E1311` | `#F5F8F6` |
  | Cards and panels (surface) | `#18201C` | `#FFFFFF` |
  | Accent: buttons, switches, tabs, links, selection | `#3DD68C` | `#0F7D4C` (5.2:1 on white) |
  | Text and icons on the accent | `#06140D` | `#FFFFFF` |
  | Text | `#EEF3F0` | `#0E1311` |
  | Muted text, hints, subtitles | `#A3AFA8` | `#5B6862` (5.5:1 on the page) |

  The two themes differ in colour only: fonts, sizes, the list-row hierarchy and the text cap (§4) are the same.
- **Everything goes light** (owner's decision): every screen and sheet, the video areas included (the players' backgrounds and letterboxing, the crop editor's panels, the scene strip, the person chooser, the waveform, Done's player bar).
- **What never follows the theme:**
  - **The exported reel.** Caption text, its backing, the branding pill and logo in the overlay PNG (`overlay_painter.dart`) and the same parts of the reel preview (`reel_preview.dart`) keep their colours, so a reel looks the same whichever theme made it.
  - **The logo:** the green tile `#3DD68C` with ink `#06140D` (§7), in both themes, as on the launcher icon.
  - **Marks drawn on the video picture** (Claude's call): the dimming outside the crop window, the crop frame and its handles, the face and body corners and their number tags, and the dark scrims under player controls keep their dark-theme colours, because the picture, not the page, is behind them.
- **Launch (FR-20, owner's choice B):** the native launch screen follows the phone's dark mode, not the saved choice, because it shows before the app can read it. Flutter's launch animation matches the native screen (the phone's mode), then its exit fade reveals Home in the chosen theme; when the two differ, that fade is the only change.

**FR-33 Fade at the ends (M38).** Asked by the owner (2026-11-11): a clip trimmed elsewhere starts and stops on a hard cut.
- **Switch:** "Fade in and out" on Fine-tune · Video's Trim tab, under the nudge cards, with the hint "The picture fades in from black and out to black. The sound doesn't change." Off by default; a new reel starts with it off, whatever the last reel had.
- **On:** the picture fades in from black over the clip's first 0.5 s and out to black over its last 0.5 s; a clip under 2 s fades over a quarter of its length at each end. The brightness at clip time *t* of a clip *L* long with fade *f* is min(1, *t* / *f*, (*L* − *t*) / *f*), at least 0. The sound is not faded.
- **Captions and branding fade with the picture:** the fade is applied after the overlay.
- **Render:** the render spec carries `fadeMs` (0, or absent, when off). Android adds a Media3 `RgbMatrix` after the `OverlayEffect` that scales red, green and blue by the brightness at each frame's clip time (`clipTimeMs`, §6.3.2). iOS scales them with `CIColorMatrix` in `FrameComposer` after the overlay is composited, at the frame's own time.
- **Preview:** the Lyrics player shows the fade, as a black layer over the reel whose opacity is 1 − brightness at the playhead. The Trim tab's player plays the raw video and doesn't.
- **Kept:** with the fine-tune (FR-24, `fadeEnds`; a file without it reads as off), and through a start-over.

**FR-34 Undo on Lyrics (M39).** Asked by the owner (2026-11-11): every change to the lines can be taken back.
- **Where:** Undo and Redo icon buttons (compact) on the right of Lyrics' app bar, greyed when there is nothing to undo or redo. Found by the owner on the phone (2026-11-11): beside the step label they squeezed the one-line title smaller, so on both Fine-tune steps the step label ("Step 1 of 2", "Step 2 of 2") now sits under the title in small muted text, and the title keeps its size.
- **Steps:** one per change to the lines: a saved text edit (not each letter), Add line, Delete, a drag, and each tap-to-time. An edit that changes no line (an ignored tap) is not a step. At most 50 steps; the oldest go first. A change after an undo clears Redo.
- **Quick message:** after a Delete, "Line deleted", and after a tap-to-time, "Line timed", each with **Undo**, for 4 s. The next change hides it.
- **A step back is a change:** the caption refills and the script is saved as `edited` after 1 s (FR-21), and the kept fine-tune follows (FR-24).
- **Back to before the first edit:** the lines become unedited, so they follow the written script as it is now: lines a run wrote meanwhile appear, and a run still writing keeps adding them.
- **Lifetime:** while Lyrics is open, Export and Cancel back included. Leaving Lyrics (back to Video, or Fine-tune closing) clears it; it is not kept for Continue later.
- **Not steps:** the Show lyrics switch, the Style sheet, Type them myself and Get again. Get again (Get, or Replace) clears the history.

**FR-35 Link in (M44, Android only).** Asked by the owner (2026-11-12, M43–M47 design): a long video from a link, to cut one topic out of (FR-36, FR-37). iOS shows none of this.
- **Home:** the New reel card becomes two cards side by side, **From my videos** ("Choose or share a trimmed video", opens Source) and **From a YouTube link** ("Find a topic in a long video", opens From a link). iOS keeps the one New reel card. (Asked by the owner, 2026-11-12: until then the link was a section on Source.)
- **From a link screen** (`/link`, title "From a link"): **YouTube link**, a text field "Paste a YouTube link" with a Paste button inside it, and **Read link**. Reading shows a card like the video card: YouTube's thumbnail, the title (two lines), the channel and the length, or the §8 message. Topic, length and Find the moments follow (FR-36).
- **Links:** YouTube watch, `youtu.be`, Shorts and live links (the M7 parser, `youtube_link.dart`). Other sites are not accepted in M44 (*Claude's call*; the design allowed them unpromised).
- **Reading:** yt-dlp's `-J` (no download) without JavaScript first, then with QuickJS when the quick run fails or finds no formats (§10 item 4). The facts kept: video ID, title, channel, length, thumbnail URL. The thumbnail is fetched by Flutter's image loader from YouTube's image server, the only network use outside Groq and yt-dlp.
- **Share in:** a `text/plain` share holding a YouTube link (from the YouTube app's Share, or a browser) opens From a link with the link filled in and read, asking first when it would close a reel, as FR-1 does for a video: "Start a new reel from this link? The one you're making will close." Text without a YouTube link is ignored.
- **Downloader in Settings** (`/settings/downloader`, FR-31's list, between Background work and Support): "Downloader", subtitle "yt-dlp <version>, reads video links". The screen shows the yt-dlp version, "Last checked <date>", and **Update downloader** (a spinner while it runs, then "Updated to <version>" or "Already up to date", or the §8 offline message). A hint: "YouTube changes often, so the downloader checks for a new yt-dlp once a week."
- **Weekly check:** at start-up on Android, when the last successful check is 7 days old or there never was one, yt-dlp updates itself quietly (about 3 MB). A failed check isn't recorded, so the next start tries again. It is the only code fetched at runtime (§9).
- **APK:** youtubedl-android brings Python, QuickJS and its native libraries, stored uncompressed (legacy JNI packaging) because it unpacks Python from the installed library folder.

**FR-36 Find the topic (M45, Android only).** Asked by the owner (2026-11-12, M43–M47 design): type a topic and a length, and the app finds the moments of a linked video (FR-35) about it, for the user to review before anything big is downloaded.
- **On From a link, under the link card** (once a link is read): **Topic** (a text field, any language: "What should the clip be about?"), **Length** (chips 15 s, 30 s, 60 s (default), 90 s, Custom; Custom asks for seconds from 5 to 300), **Output language** (a drop-down of Urdu (default), Arabic, Punjabi, Persian, Hindi, Bengali, English; asked by the owner, 2026-11-12) and **Find the moments**, which opens Review cuts (`/link/cuts`).
- **Transcript, cheapest first:**
  1. YouTube's captions: an uploaded track first (in the video's language when YouTube names one, else any), else the auto-generated track in the spoken language (`<code>-orig`), never a machine translation. Fetched as `json3` from the URL yt-dlp gives. Urdu talks usually come as Hindi in Devanagari (§10 item 10); that is fine for finding moments.
  2. Otherwise the audio only (`bestaudio[ext=m4a]`) is downloaded by yt-dlp into `sources/v_yt_<YouTube ID>/source.m4a` and written by the script pipeline as a video with that ID (FR-26, FR-12a, FR-14): cleaned, sent in pieces, resumed per piece, saved.
  - **Length caps:** up to 3 hours with captions, 2 hours without (§8 "too long"). Without captions and over 1 hour, Review cuts asks first: "This video has no captions, so Groq writes its script first. That takes a while and uses much of Groq's free daily audio." with Continue and Back.
- **Blocks:** transcript lines are merged into blocks of at least 5 s (a block ends at the first line end after 5 s), numbered. Cuts are runs of whole blocks, so a cut never starts or stops mid-line.
- **Reading in parts:** blocks go to Groq's chat model (`openai/gpt-oss-120b`, low reasoning, JSON reply; §10 item 11) in parts of at most 20,000 UTF-8 bytes (4,000–5,000 tokens), with the topic; moments are asked to last 8–30 s (about a paragraph). Each part replies with candidate moments: first and last block, a score from 0 to 1, a one-line reason and the moment's words, both in the output language (Urdu asked for in Nastaliq script, not Hindi script; Punjabi in Shahmukhi), translated when spoken in another language. One moment adds about 500 reply tokens (§10 item 11). Progress: "Reading the transcript, part 3 of 6".
- **Every moment is shown, none ticked (changed with the owner, 2026-11-12):** Review cuts lists every candidate in video order; of two that overlap the higher score stays, and those under 2 s are dropped. Nothing is ticked: the user ticks the moments the clip should have. There is no picking call (until then a second call ordered the candidates and the app fitted the best to 90–110 % of the length, which silently dropped good moments when they added up to more).
- **Saved:** the transcript of a linked video and each topic's candidates (per topic and output language) are saved per YouTube ID (`topics/<YouTube ID>/`), so Find again or the same topic later sends nothing. Saved for 90 days like scripts (FR-14).
- **Groq's limits:** a 429 within a minute is waited out by the client as today. A longer one shows "Groq's free limit reached, continuing at 3:40" with Cancel and resumes on its own; a wait over 15 minutes is taken as the daily limit (§8), and the saved candidates stay.
- **Review cuts screen** (`/link/cuts`, title "Review cuts"):
  - While finding: the step ("Getting the captions", "Writing the script" with the script pipeline's progress, "Reading the transcript, part 3 of 6", "Picking the best moments"), a bar, and Cancel.
  - One card per moment: a checkbox, `1:02:13–1:02:31 · 18 s`, its words in the output language (three lines, tap to expand; a moment added from the transcript keeps the transcript's words), the reason in small text, each in its script's font and direction (`ScriptText`); start and end each with − and + (0.5 s; never under 2 s or outside the video, and a ticked cut never into another ticked one). Ticking a moment that overlaps a ticked one does nothing. Cards can be dragged to reorder; the clip takes the ticked ones in the list's order.
  - **Add a moment:** a sheet with the transcript blocks and a search field; tapping a block adds it, ticked, in video order (not when it overlaps a ticked one).
  - **Footer** (kept short so the moments have the screen; changed after the phone check, 2026-11-12): the ticked total against the length ("58 s of 60 s"; over it, "74 s of 60 s · 14 s over" in the error colour: going over is allowed, the length is a target), a **Transition** button naming the chosen one (it opens a sheet with the four previews, two by two), and **Make the clip** (FR-37, M46).
  - **Transition picker:** Cut, Crossfade (default), Fade through black, Slide, as four tiles each looping a small preview (two coloured panels changing in that way). One transition for every join, 0.3 s.
  - **Find again** in the app bar: reads the transcript again with the same topic, asking "Replace your edited cuts?" first when cuts were changed. Since the topic's candidates are saved, it sends nothing and starts again from the list with nothing ticked.
  - **Play** on a card (M46, FR-37) downloads that stretch at up to 480p and plays it.
- **Consent (FR-30):** finding sends the transcript text and the topic to Groq, so the consent screen says so, and a user who agreed before M45 is asked once more.

**FR-37 Download and join (M46, Android only).** Asked by the owner (2026-11-12, M43–M47 design): only the ticked moments download, and they are joined with the chosen transition into one video that goes on to Fine-tune.
- **Make the clip** (Review cuts' footer, on once a moment is ticked): the list gives way to the making view: "Downloading cut 2 of 4", "3.1 MB of 7.8 MB · 1.2 MB/s" and a bar, then "Joining the cuts" with its bar, and Cancel. Cancel stops and returns to the list; finished cuts are kept, so Make the clip again downloads only the rest. A failure shows its §8 message with Try again and Back.
- **Streams:** read again with yt-dlp each time (quick, then QuickJS, as FR-35 reads), since stream links expire after some hours. Video: H.264 MP4 at the best height up to 1080p; otherwise another MP4 (AV1) at the best height up to 1080p; failing both, the lowest MP4 above 1080p. Audio: the original track's `m4a` with the highest bitrate, a regular one before a "DRC" one. WebM streams (VP9, Opus) have no segment index and are not used; without an MP4 stream, §8 "can't be downloaded in parts". (Checked from the Mac, 2026-11-12: `UTHXU2dOO6Y` lists H.264, AV1 and VP9 at each height up to 1080p; its segments are 5 s of video, 10 s of audio.)
- **Only the cuts:** each ticked cut with a margin of the transition's length (0.3 s; none for Cut) on both sides, clamped to the video. From each stream's segment index (`sidx`, in its first bytes) the app fetches the header and the run of segments from the one holding the margin's start, which begins on a keyframe, to the one holding its end, by HTTP range requests (Dart `HttpClient`). A 403 (an expired link) reads the streams once more. The phone's yt-dlp has no FFmpeg, so `--download-sections` is not used (§10 item 10).
- **One file per cut:** `ffmpeg_kit` stream-copies the two downloads into one MP4, each stream delayed so they line up (M7's clip mux); the file's time zero is the earlier stream's first segment start. Cut files stay in the cache (`cuts/<YouTube ID>/`) with a small JSON beside each (the streams, the window, the file's start, what it covers) and are reused while the cache lasts.
- **Join (Media3):** one H.264/AAC MP4 at the downloaded size and a high bitrate (5 bits a pixel a second, about 10 Mbit/s at 1080p), in the list's order, each cut clipped from its own file at exact times.
  - **Timeline:** a transition sits in the margins: the outgoing cut plays on past its end while the incoming one starts before its start, the two overlapping for 0.3 s, so no word inside a cut is faded and the clip is the cuts' total plus 0.3 s a join (Cut adds nothing). A join whose margin is shortened by the video's start or end gets a shorter transition.
  - **Transitions:** Crossfade blends picture and sound across the 0.3 s. Fade through black fades the outgoing picture and sound out over the first half and the incoming in over the second. Slide pushes the incoming cut in from the right as the outgoing leaves to the left, with the sound crossfading. Cut joins back to back.
  - **How** (*Claude's call*): two layers in one Media3 composition, both without gaps: the upper plays each cut with its tail, the lower each cut with its lead. The upper's opacity and position, and both layers' volume, follow the transition; elsewhere the upper covers the lower and the lower is silent.
  - **AV1:** the join decodes it as M31's convert does (Android 10 and later), so the joined file is H.264 either way and needs no separate convert; a phone that can't shows the §8 AV1 row's message.
- **Kept:** the joined file is imported like a shared video (FR-1): fingerprinted and kept as `sources/<videoId>/source.mp4`, named after the topic. Beside it, `link.json` keeps the YouTube ID, title, channel, topic, output language, transition and the join times. Fine-tune · Video then opens on it with the clip the whole video.
- **Join points are scenes** (FR-27): the join times (the middle of each transition) are scene edges for the crop, with what `scdet` finds. A detected cut within 0.5 s of a join gives way to it; the 0.5 s rule never removes a join, except one within 0.5 s of the clip's ends after a trim (that scene would be a blink). The crop's Cut keyframe sits at the join time, less `cutKeyframeLead` as for any cut.
- **Recent:** like any video (FR-24): named after the topic, reopening Fine-tune on the joined file.
- **Play on a card:** a play button on each card downloads that stretch (no margin) at up to 480p (H.264 first) into the cache as a cut is, then plays it in a sheet (play, pause, a seek bar). While it downloads, the button shows a spinner. A played stretch is reused.
- **Lyrics in the output language:** see the M46 design in §12: Groq writes the joined clip's script, then its chat model translates the lines into the output language keeping their times, and only the translated lines exist from then on, edited as any lines (FR-21), drawn in the font for their script (§6.5).
  - **On Lyrics:** the Get card says "Lyrics in Urdu, chosen on From a link" in place of the Language dropdown. The run's steps gain "Translating into Urdu" ("Groq, in the cloud; only the translation is kept") before Lining up timestamps, and its language step reads as automatic. No line shows until the translation is in.
  - **Saved:** under the output language with source `groq-translated` (FR-14); the spoken script (`auto`) is deleted once translated, so the video reopens in one language. Edits save under the output language as `edited`, as for any script.
  - **Get again** (*Claude's call*): its language dialog stays. On a link clip another language translates into that one; Automatic gives the lines as spoken. When the written script's inferred language (§6.4) already is the one asked for, nothing is sent for translation.
  - **Failure:** a reply without every line, non-empty, is §8 "Groq couldn't translate the lyrics."; the spoken script stays saved, so Retry only translates again.

## 4. Non-functional requirements

- **Platforms:** Android (minSdk 24) and iOS (deployment target 15.5, needed by ML Kit 9 face detection; translation, which first needed it, went in M30). iOS is built in M26. Store builds become possible (§9, M27).
- **Responsiveness:** transcription, FFmpeg, waveform peaks and file I/O never block the UI isolate. Every long step shows progress and can be cancelled.
- **Storage (changed in M23):**
  - Kept videos: `sources/<videoId>/source.<ext>` in app support, the file the user shared or picked, kept once (FR-1); for an AV1 video, its H.264 copy `source.h264.mp4` instead (M31). It stays while its script or fine-tune is kept (FR-14 retention) and is deleted with them; imported but never scripted, it is deleted after 7 days. Saving a video's title counts as a use, so a video just imported isn't pruned. Cleaned audio pieces (FR-26) are cached beside it.
  - Saved scripts: `transcripts/` in app support (FR-14).
  - Unfinished fine-tunes: `draft-<requested>.json` beside the scripts in `transcripts/<videoId>/` (FR-24); they go with the folder.
  - Exports: `reels/` in app documents.
  - Copies and other files are written to `.part` files and renamed when complete.
  - Every start deletes folders whose name isn't a fingerprint ID (`v_` and 16 hex digits): old YouTube data.
- **Data use:** nothing is downloaded. The only upload is the cleaned script audio pieces (about 16 kHz mono FLAC), to Groq (the Fix with Groq lines went in M36).
- **Privacy:** nothing leaves the device except language-pack downloads and, to write a script (FR-12a), audio pieces sent to Groq with the user's key. The video itself never leaves the phone. The SDKs send their own usage metrics: Google ML Kit's anonymous usage, performance and per-installation ID (§9.2, found in M27; the policy in §9.1 says so).
- **Large text (M34):** the phone's text size is followed up to **1.3×** and no further (`maxTextScale` in `app.dart`, `MediaQuery.withClampedTextScaling`). The owner chose a cap over unlimited growth (2026-11-10), so every screen keeps its layout; users at the largest system sizes get less than they asked for. The reel preview and the export draw captions at a fixed size with no text scaling at all (`reel_preview.dart`).
  - **App bar titles** stay on one line and shrink to the room left (`ScreenTitle`), next to the back button and the step label.
  - **Type hierarchy:** section labels 16 sp semi-bold (`SectionLabel`, also "Recent" on Home and "Groq API key"), body text 14 sp, list rows 14 sp with 12 sp muted subtitles (the theme's `listTileTheme`), hints 12 sp muted (`HintText`). A section label is never smaller than what it holds. Android 14 and later scale small text more than large text (12 sp and 14 sp both end near 24 at 200%), which is why labels and body are two steps apart.

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
  - iOS (M26): AVFoundation behind the same channels and the same spec map: the clip is cut out of the video into an `AVMutableComposition`, `AVAssetReader` decodes it, Core Image draws each frame with the rectangle from the same `ndcRectAt` maths (ported to Swift), and `AVAssetWriter` encodes hardware H.264 and AAC. Not a custom `AVVideoCompositing` (see M26 task 4).
- **FFmpeg (changed in M23):** audio cleaning and splitting for Groq (FR-26), thumbnails, probing (FFprobe: duration, size, rotation, audio track) and sampling small JPEG frames for Follow the person (FR-23, FR-27). The mjpeg encoder is there; the PNG encoder is not (`--disable-zlib`). The bundled build can't encode H.264 or read https (§10 Q1).

### Package map

| Need | Package | Notes |
|---|---|---|
| Video in (M23) | our own `status_studio/video_in` channel on Android (Kotlin) and iOS (Swift, fed by our Share Extension; `receive_sharing_intent` rejected on both, §10 item 9), `image_picker` | Share-in; `pickVideo` uses the Android Photo Picker and PHPicker, no permission. Replaced yt-dlp (removed in M23) |
| Speech to text (cloud) | `dart:io` `HttpClient` | Hand-built multipart to `api.groq.com`; `GET /openai/v1/models` checks a key |
| Secret storage | `flutter_secure_storage` | The Groq key only |
| FFmpeg | `ffmpeg_kit_flutter_new_min` ^2.x | The only FFmpeg (LGPL); no mediacodec, no TLS, no libx264 |
| Final render (Android; iOS M26) | Media3 `transformer`, `effect`, `common` 1.11.1 | `Transformer`, `ClippingConfiguration`, `Crop`, `Presentation`, `GaussianBlurWithFrameOverlaid`, `OverlayEffect` + `BitmapOverlay`. iOS: AVFoundation, `AVAssetWriter` and Core Image |
| Downloads (removed in M23) | | Nothing is downloaded any more. `HttpClient` stays only for Groq and the key check |
| Faces (M20) | `google_mlkit_face_detection` | Fast mode, small faces allowed; bundled model |
| Bodies (M25) | `tflite_flutter` 0.12.1 and `assets/models/efficientdet_lite0.tflite` (4.4 MB, Apache 2.0, TF Hub, the build with NMS) | In an `IsolateInterpreter`, 4 threads, 320 × 320 input; about 100–250 ms a frame on the Redmi (§10 item 7). `android/gradle.properties` sets `kotlin.jvm.target.validation.mode=warning` because the plugin's Kotlin and Java targets differ under this JDK. +11.4 MB of APK, accepted. iOS in M26. |
| Translation (removed in M30) | — | — |
| Preview / gallery / share | `video_player` / `gal` / `share_plus` | |
| Key-value storage | `shared_preferences`, with `shared_preferences_android` overridden to 2.4.26 | `recentReels` (JSON). 2.5.x unregisters its one shared `data_store` instance whenever any Flutter engine detaches, and the foreground service's engine does when a script or export ends, so every later read threw; 2.4.x unregisters per engine. The override and its comment in `pubspec.yaml` go when the plugin stops sharing it. |
| Saved models (M42) | `freezed`, `json_serializable`, `build_runner` (dev); `freezed_annotation`, `json_annotation` | Code generation at build time only; nothing ships that collects data, so §9.2 is unchanged. `build.yaml` sets `checked: true` |
| Background work | `flutter_foreground_task`, `flutter_local_notifications` | No TaskHandler: the work stays in the app's isolate. Notifications need core library desugaring |

### Engineering rules

- **Code generation for saved models (M42):** the four classes saved as JSON (`SourceVideo`, `SavedTranscript`, `PartialTranscript`, `RecentReel`) use `freezed` and `json_serializable`; run `fvm dart run build_runner build -d` after changing one, and commit the generated `*.freezed.dart` and `*.g.dart` files. The saved JSON keeps its pre-M42 shape, so files and preferences written before still read: durations as whole milliseconds under `…Ms` keys, and a script's `languageCode` and `lines` and a reel's `width` and `height` at the top level (these two models write `toJson` by hand, because `json_serializable` can't flatten a field). `json_serializable` runs `checked`, so a malformed file throws `CheckedFromJsonException` (an `Exception`), never a `TypeError`. Every other class writes `copyWith`, `==` and `hashCode` by hand.
- **Copy:** literal from this document and the canvas. The app is general-purpose: never name a content type (naat, bayan…) in UI or code.
- **Import boundaries:**
  - Only `LocalVideoImporter` reads shared or picked files and copies them into app storage (M23). No yt-dlp or YouTube code remains.
  - Only `lib/src/core/ffmpeg/` imports FFmpeg Kit.
  - Only the Kotlin `render/` package imports Media3, and only the Swift `ios/Runner/Render/` folder imports AVFoundation and Core Image (M26).
  - The background plugins are reached only through `BackgroundWorkPlatform`.
  - Only `lib/src/features/style/data/` imports ML Kit face detection and `tflite_flutter` (`OnDeviceDetector`, `BodyModel`).
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
enum CaptionPosition { top, bottom }  enum CaptionSize { small, medium, large }   // CaptionVariant went in M30
enum CaptionLook { box, shadow }  enum BoxColours { whiteOnBlack, blackOnWhite, yellowOnBlack, whiteOnGreen }  enum ShadowColours { white, yellow, blackGlow, gold }   // M37
class CaptionAppearance { CaptionLook look; BoxColours boxColours; ShadowColours shadowColours; }   // M37
class CaptionSettings { String text; CaptionPosition position; CaptionSize size; CaptionAppearance appearance; }
// ReelDraft and FineTuneDraft also carry bool fadeEnds (FR-33, M38).
class ReelDraft { SourceVideo? video; ScriptLanguage language; Transcript? transcript; LineSelection selection; ClipRange? clip; FrameSettings frame; CaptionSettings caption; }
class RecentReel { String id; String title; String videoPath; String thumbnailPath; Duration duration; OutputSize size; DateTime createdAt; } // title: first caption line
class SavedTranscript { Transcript transcript; String source; DateTime savedAt; } // groq-whisper-large-v3 (captions removed in M23) 
class SavedScript { SourceVideo video; ScriptLanguage language; SavedTranscript saved; } // a Recent row
class FineTuneDraft { TranscriptKey script; RangeSelected selection; ClipRange clip; FrameSettings frame; CaptionSettings caption; bool linesEdited; int scriptFingerprint; DateTime savedAt; } // FR-24; the script itself is not copied
class SavedFineTune { SourceVideo video; FineTuneDraft draft; } // a Recent row (FR-24)
enum SpeechEngine { onDevice, groq }
class CloudTranscriptionSettings { bool enabled; bool keyChecked; } // the key itself lives only in secure storage
class ClipWindow { Duration start; Duration end; }                  // M23: the whole video (FR-15 removed)
class ClipSource { File file; Duration offset; ClipWindow window; } // M23: the kept file, offset 0
sealed class SceneChoice { FollowFace(track), FollowBody(track), HoldSpot(anchor) } // FR-27, M25; a transient answer (identity equality, holds a FaceTrack), never saved
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
  - If it looks wrong on a phone, switch to a two-sequence `Composition`.
- **16:9:** `Presentation` only.

### 6.3.2 Moving crop for Media3 (M19)

With keyframes, `Crop` is replaced by a `MatrixTransformation` whose matrix is computed for each frame from the keyframes. The time is the frame's presentation time counted from the clip start, from one helper (`clipTimeMs`) that the caption overlay uses too, so the crop and the caption lines can't drift apart.
- **Rectangle at a time:** a pure function `ndcRectAt(keyframes, timeMs)` (unit-tested without Android): before the first keyframe the first rectangle; after the last the last; between two a Glide interpolates each edge linearly and a Cut holds the earlier until the later's time, and from that time on is the later. This is the same rule as `CropPath.anchorAt` in Dart.
- **Matrix:** the rectangle in NDC (§6.3.1) scaled to fill the frame (`scale = 2/(right−left)`, `2/(top−bottom)`, translated by `−(right+left)/(right−left)`, `−(top+bottom)/(top−bottom)`), built as a plain 4 × 4 array (no `android.graphics.Matrix`, which unit tests can't use).
- **Size:** `configure` returns the window's pixel size, as `Crop` does, so the `Presentation.createForWidthAndHeight(outW, outH, LAYOUT_STRETCH_TO_FIT)` after it is the same near-1:1 step as the fixed crop's.
- **Unchanged:** the overlay still comes last, and Blur and 16:9 never send keyframes.
- **iOS (M26):** the same rule in Swift (`ios/Runner/Render/MovingCrop.swift`: `ndcRectAt`, `clipTimeMs`). The time is each decoded frame's own presentation time in the clip's composition, which starts at zero, floored to whole milliseconds like Android's `presentationTimeUs / 1000`, so a Cut (the keyframe 10 ms before the cut, FR-27) lands on the same frame as the picture. The window is a Core Image rectangle (`pixelRect`) taken from the whole, already upright frame, scaled to the output and stretched (the same near-1:1 stretch), not a GL matrix, so `glMatrixFor` has no Swift twin. There is no fade at cuts.

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
| Arabic script (Urdu, Arabic, Persian and the like) | Noto Nastaliq Urdu |
| Everything else | Inter; glyphs it lacks fall back to system fonts |

Urdu, Arabic and Persian text is right to left.

### 6.6 Roman Urdu (removed in M30)

Removed with the caption variants (FR-7). It was a rule-based, letter-by-letter transliteration with a short list of common-word overrides.

## 7. Logo

"Trim": trim brackets around a five-bar waveform on a rounded tile, in a 100-unit viewBox. One `LogoPainter` serves the UI, the export overlay and the launcher icon.

| Part | Spec |
|---|---|
| Tile | rx 24 |
| Brackets | `M33 24 H24 V76 H33` and `M67 24 H76 V76 H67`, stroke 6, round caps and joins |
| Bars | x = 38, 44, 50, 56, 62 spanning y 42–58, 35–65, 30–70, 37–63, 43–57, stroke 4.5, round caps |
| Colours | tile `#3DD68C`, ink `#06140D`; dark variant tile `#18201C`, ink `#3DD68C`. The green tile is used in both app themes (FR-32); the logo never follows the theme |

The Android launch screen (FR-20) draws the same shapes as vector drawables (`launch_logo.xml`, `splash_icon.xml`), since it shows before Flutter starts; keep them in step with `LogoPainter`. `LogoPainter` also takes a `LogoPose` (bracket inset, bar half-lengths) for the launch animation; the rest pose is the table above.

## 8. Error states

| Condition | Where | Message | Actions |
|---|---|---|---|
| Invalid link (removed in M23, back in M44) | Source | That doesn't look like a YouTube link. | Edit |
| Video unavailable, private, age-restricted or live (removed in M23, back in M44) | Source (link card) | This video can't be downloaded. | Edit |
| No network while reading a link (M44) | Source (link card) | You're offline. Connect and try again. | Read link |
| A link over the length cap (M45, FR-36) | Review cuts | This video is too long. Links can be up to 3 hours with captions, or 2 hours without. | Back |
| No moments about the topic (M45, FR-36) | Review cuts | Couldn't find this topic in the video. Try other words or a longer video. | Find again, Back |
| Groq's daily limit used up (M45, FR-36) | Review cuts | Groq's free daily limit is used up. Try again tomorrow, or use a key on Groq's paid plan. | Back |
| Groq's chat reply isn't the JSON asked for (M45, FR-36) | Review cuts | Groq's answer couldn't be read. Try again. | Find again, Back |
| No MP4 stream to download in parts (M46, FR-37) | Review cuts | This video can't be downloaded in parts. | Back |
| No network while downloading the cuts (M46, FR-37) | Review cuts | You're offline. Connect and try again. Finished cuts are kept. | Try again, Back |
| yt-dlp can't read the streams, or their links keep expiring (M46, FR-37) | Review cuts | Couldn't read this video from YouTube. Update the downloader in Settings, or try again later. | Try again, Back |
| The join failed (M46, FR-37) | Review cuts | Couldn't join the cuts. | Try again, Back |
| An AV1 video this phone can't decode (M46, FR-37) | Review cuts | This phone can't convert this AV1 video. | Back |
| A cut couldn't be played (M46, FR-37) | Review cuts (snackbar) | Couldn't play this moment. | — |
| Groq's translation can't be read (M46, FR-37) | Lyrics | Groq couldn't translate the lyrics. | Retry, Back |
| No network during download (removed in M23: nothing is downloaded; offline errors remain for Groq) | Lyrics (Processing until M30) | You're offline. Connect and try again. | Retry, Back |
| yt-dlp can't read the video (removed in M23, back in M44) | Source (link card) | Couldn't read this video from YouTube. Update the downloader in Settings, or try again later. | Read link |
| The video has no audio track, or can't be read (M23) | Source / Processing | Can't read this video. | Choose another video, Back |
| An AV1 video can't be converted to H.264 on this phone (M31, FR-1) | Source | This phone can't convert this AV1 video. Save it as H.264 (MP4) in your editor and share it again. | Choose another video, Back |
| The kept source file is missing (M23) | Recent / Continue | Video not found, choose it again. | Choose a video, Back |
| No Groq key saved | Lyrics (Processing until M30) | Writing a script needs a free Groq key. | Settings, Back |
| The user hasn't agreed to sending to Groq, or said Not now (M27, FR-30) | Lyrics (Processing until M30) | Writing a script needs your OK to send the audio to Groq. | Continue (opens the consent screen), Back; Retry on the footer opens it too |
| Groq rejected the key (401/403) | Lyrics (Processing until M30) | Groq didn't accept your API key. | Settings, Back |
| Groq limit (429, wait over 60 s) | Lyrics (Processing until M30) | Groq's free limit is used up for now. Try again in <n> min. | Back |
| Groq failed (other error, or 5xx/498 twice) | Lyrics (Processing until M30) | Groq couldn't write this script. | Retry, Back |
| Network lost while Groq writes | Lyrics (Processing until M30) | You're offline. Connect and try again. | Retry, Back |
| Key check failed | Settings | Groq didn't accept this key. | Edit |
| No speech found | Lyrics (Processing until M30) | No speech found in this video. | Try another language, Back |
| Translation pack missing and offline (removed in M30) | — | — | — |
| Gallery access refused | Done | Allow Photos access in Settings to save reels. | Open settings |
| Render failed | Export | Couldn't make the reel. | Retry, Back |
| Saving the finished reel to Recent failed (any error, M25) | Export | Something went wrong. Try again. | Retry (saves the finished file again, no second render), Back |
| (Removed in M25: FR-27 asks at every scene, so there is no "no person" error; the row stays for the history) No person found in the clip | Fine-tune · Video | No person found in this clip. The crop stays where it is. | (snackbar) |
| A kept fine-tune's script is gone | Script | This fine-tune's script had to be written again. Check the clip's start and end; the size and caption style are kept. | (snackbar) |
| A kept fine-tune's script changed | Script | The script changed since this fine-tune was saved. Check the clip's start and end; the size and caption style are kept. | (snackbar) |
| Following the person failed (frames, decoding or detector) | Fine-tune · Video | Couldn't follow the person. Try again. | (snackbar) |
| Not enough storage | copying a video, cleaning audio or export | Not enough space on your phone. | Back |

Each error is a typed exception from the data layer. Screens map them to these messages, and nothing returns `null` or a sentinel.

## 9. Decisions

| Decision | Choice and why |
|---|---|
| Scope | General-purpose: any video, any language. Since 2026-11-05 (M23) the input is a local video the user already trimmed, shared in or picked from the gallery. No content-type picker. From M45 a link and a topic find the moments in a long video (FR-36); the user reviews them before anything big is downloaded |
| Distribution (changed in M43) | No Play Store or App Store (dropped 2026-11-12). Android: a signed APK on GitHub releases and IzzyOnDroid now, F-Droid's main repository after M47 (which needs ML Kit replaced, since F-Droid rejects non-free code). iOS stays buildable but is not distributed. From M2 to M22 the app was off the stores because of yt-dlp; M23–M27 made store builds possible; M43 goes back to link downloads by choice. M27's consent (FR-30) stays; its store-only work (§9.2, §9.3) is history |
| YouTube access (removed in M23, back in M44) | Was yt-dlp on the phone plus Dart downloads (§10 Q4). Removed with the pivot; it comes back on Android in M44 (FR-35), restored from git history, with yt-dlp updating itself (the only code fetched at runtime) |
| Speech to text | Groq `whisper-large-v3` only (turbo until M24: it dropped the opening lines of the reference clip, §10 item 8). On-device Whisper (`whisper_ggml`) was dropped in M10: medium q5_0 ran at 0.2× real time on a Redmi Note 11 (Snapdragon 680), and small was only 1.5× on a Pixel 6a (§10 Q2) |
| Cloud transcription | Groq `whisper-large-v3` with the user's own key (FR-12a), because the phone is too slow (§10 Q2). A key shipped in the APK could be extracted, and the app has no server. Groq is fast, multilingual and cheap (the $0.04 per audio hour was turbo's price; large-v3 costs more, so check Groq's pricing page; free plan). Pieces go as 16 kHz mono FLAC (M23; they were stream-copied `.m4a` before), cleaned first (FR-26). Groq's `url` input isn't used: the audio is a local file |
| FFmpeg | `ffmpeg_kit_flutter_new_min` only (LGPL). The full GPL build would duplicate native libraries and make the app GPL |
| Renderer | Media3 Transformer on Android (hardware H.264), because the bundled FFmpeg can't encode H.264; AVFoundation on iOS (M26), the same spec over the same channel |
| Captions and branding | Drawn by Flutter to one PNG and overlaid by Media3 (AVFoundation on iOS). Other text engines break Nastaliq letter joining |
| Data saving (changed in M23 and M43) | No media downloads, except, from M44, the parts of a linked video the user keeps (never the whole video). Uploads go only to Groq: the cleaned 16 kHz mono script audio and, from M45, the transcript text and topic (FR-36) |
| Reuse | Scripts saved per video fingerprint, language and source for 90 days; resume per 90-second piece; cleaned pieces cached per video |
| Background work | One foreground service kept by Dart. The work already runs in the app process, so keeping the process alive is enough. Packages rather than hand-written Kotlin, so the notification shows the percent as text, not a bar |
| Name, logo, IDs | Status Studio; Trim; `com.hotmail.arehmananis.statusstudio` |
| Fonts | Inter (UI), Noto Nastaliq Urdu, Noto Naskh Arabic (OFL) |
| Signing (changed in M43) | The keystore and `key.properties` live outside the repo (`~/.status-studio/` or `STATUS_STUDIO_KEY_PROPERTIES`), since the repo is public. Without them a release build is unsigned, never debug-signed; F-Droid signs its own builds |
| Licence (M43) | GPL-3.0, required by youtubedl-android (M44) and by F-Droid's free-software rule. `LICENSE` at the root; About names it (FR-31) |
| Battery optimisation (M27) | Not requested. `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is removed from the merged manifest: Play allows it only for listed uses (an app whose core function breaks under Doze, such as a companion device or a task automation app), and the foreground service keeps the work running without it. Settings still points to App info on phones (Xiaomi and others) that need "No restrictions" |
| Foreground service type (M27) | `FOREGROUND_SERVICE_DATA_SYNC`, kept. The Play Console declaration (App content → Foreground service permissions), ready to paste: **Type:** Data sync. **What the user does and sees:** "The user picks a video and taps Get the script. The app uploads the video's sound, in pieces, to a speech-to-text service (Groq) with the user's own API key and receives the timed lyrics. When the user taps Export, the app encodes the finished video into a file on the phone. Each job starts only when the user taps its button, shows an ongoing notification with the step and percent, and stops as soon as it finishes or the user cancels." **Why it must run now and not be paused:** "A long video takes several minutes to upload and transcribe, and an export several minutes to encode. Users lock the phone or switch apps while waiting. If the system paused the work, the upload would break between pieces and the export would be lost, and the user would have to start again. The result is wanted right away, so deferring it with WorkManager would break the feature." **Impact if interrupted:** user-noticeable (the lyrics or the reel are not ready, work is lost). Play also asks for a link to a short screen recording: pick a video, tap Get the script, press Home, show the notification's progress, come back to the finished lyrics. Recording and hosting it are the owner's. Note: Android 15 added the `mediaProcessing` type, which fits the export better than `dataSync` (Android's guide lists "local file processing" under `dataSync`, so this is allowed today); `dataSync` is also the type Android says it will restrict further, so move the export to `mediaProcessing` on API 35+ if Play's review asks |
| Crop subject (M25) | The user chooses a face, a body or a fixed spot at every scene (FR-27). The app never assumes, so automatic follow and look-alike carry-over are dropped |

### 9.1 Privacy policy (M27 task 3)

**Hosting (changed in M43):** the stores are gone, so no store needs the URL. Once the repo is public (M43 task 6) the policy can live in it as `PRIVACY.md`, linked from the release page and the IzzyOnDroid and F-Droid listings. Fill the `<date>` field before publishing (the contact email was filled in M33). M44 adds the link downloads to the text and M45 the transcript and topic sent to Groq, each when built. The "Google ML Kit" paragraph goes in M47 if the open face model replaces it.

> **Status Studio privacy policy**
>
> Effective `<date it is published>`.
>
> Status Studio turns a video you choose into a short clip with lyrics. It has no server and no accounts. We, the developer, receive none of your data.
>
> **What stays on your phone.** The videos you share into the app or pick, copied into the app's own storage. The lyrics written for them, kept for 90 days. Unfinished work, so you can carry on later. The clips you export. Your settings, including whether you agreed to send audio to Groq. If you add a Groq API key, it is kept in the phone's secure storage (Android Keystore or iOS Keychain) and is sent only to Groq, to authorise your own requests. You can delete videos, lyrics and clips in the app, and uninstalling the app deletes all of it.
>
> **What leaves your phone, and only when you ask.**
> - *Groq.* When you tap Get lyrics from Groq and agree, the app sends your video's sound (cleaned, one channel, in pieces) to Groq, an AI service run by Groq, Inc., using your own Groq key, to write the lyrics. The picture is never sent. Groq handles this under its own terms and privacy policy (groq.com), as the service you signed up for when you made your key. You can withdraw your agreement in Settings at any time, and nothing more is sent after that. A clip made without lyrics sends nothing.
> - *Google ML Kit.* Face detection runs on your phone. ML Kit sends Google usage and performance information to keep it working: device and app details, a per-installation identifier that does not identify you, performance measures, sizes of what was processed, and error codes. Google describes this at developers.google.com/ml-kit.
> - *Saving and sharing.* Save puts the clip in your photo library. Share hands it to the app you choose in your phone's share sheet.
> - *Support.* If you write to us from Settings, the app opens your own email or WhatsApp app with your message, your phone's model, system version, processor, memory, screen size and connection type (such as Wi-Fi), and the app's version filled in. You see it before you send it, and we receive only what you send. Nothing is sent by Status Studio itself.
>
> **What we don't do.** No advertising, no analytics of our own, no tracking, no selling or sharing of your data, no accounts.
>
> **Permissions.** Photo library (add only), to save clips. Notifications, to tell you when work is done. Internet, for Groq and the language packs, and network state, to name the connection type in a support message. On Android, a foreground service, so writing lyrics and exporting continue when you leave the app.
>
> **Children.** Status Studio is not directed at children under 13.
>
> **Changes.** A new version of this policy will be posted at this address with a new date.
>
> **Contact.** arehmananis@hotmail.com

### 9.2 Store answers (M27 task 4)

**History (M43):** the Play Store and App Store plan was dropped on 2026-11-12. These answers are kept for reference and not maintained.

**What the answers rest on (checked 2026-11-10):** our code sends data only to Groq (FR-12a, after FR-30's consent; FR-19's lines until M36). The SDKs in the app send more: Google ML Kit (face detection; translation until M30) declares in its iOS privacy manifests, all not linked to the user and not used for tracking: device ID, product interaction, performance data and other data types (analytics and app functionality), other diagnostic data (analytics), and other user content (analytics and app functionality). Google's Android disclosure (developers.google.com/ml-kit/android-data-disclosure) lists device and app information, per-installation identifiers, performance metrics, API configuration, input and output sizes, event types, error codes and, for Translate, the chosen languages; HTTPS; not transferred to third parties. GoogleDataTransport (pulled in by ML Kit) declares other diagnostic data. FFmpeg Kit, `tflite_flutter` and the other plugins send nothing. `device_info_plus`, `package_info_plus`, `url_launcher` and `connectivity_plus` (M33) send nothing either (`connectivity_plus` uses `ACCESS_NETWORK_STATE`, a normal permission Media3 already brought in): Support (FR-31) hands a message to the user's own email or WhatsApp app, which the user sends, like the share sheet. Play doesn't count data the user sends through another app as collected, so the forms below are unchanged; Apple counts only data the app itself transmits, so the label is unchanged too (Claude's reading of the stores' rules, M33; not checked against their latest text. Recheck before submitting, and again if Support ever sends anything in the app). The answers below are cautious where it was unclear: Groq's retention is Groq's, so nothing is called ephemeral.

**Google Play, Data safety:**
- Collects or shares required user data: **Yes**. All data encrypted in transit: **Yes** (HTTPS). Account creation: **none**. Deletion: data lives on the phone and is deleted in the app (Recent → Delete) or by uninstalling; the developer holds no copy. Groq data sits in the user's own Groq account.
- Independent security review: no.

| Data type (Play's names) | Collected | Shared | Processed ephemerally | Required or optional | Purposes | Why |
|---|---|---|---|---|---|---|
| Audio → Other audio files | Yes | No (sent to a service the user chose, by their own action) | No | Optional (FR-29: lyrics are optional) | App functionality | Script audio to Groq |
| App info and performance → Diagnostics | Yes | No | No | Required | Analytics | ML Kit |
| App info and performance → Other app performance data | Yes | No | No | Required | Analytics | ML Kit |
| Device or other IDs | Yes | No | No | Required | Analytics | ML Kit's per-installation ID |

Not collected: photos and videos (the video never leaves the phone), personal info, location, contacts, messages, financial info, health, web history, files and docs, calendar, app interactions beyond ML Kit's.

**Google Play, other App content forms:** Ads: **no ads**. App access: **some functionality is restricted**: "A clip without lyrics (the Show lyrics switch off) needs nothing. Writing lyrics needs a free Groq API key, which the reviewer can create at console.groq.com/keys and paste in Settings." If the owner chooses to give reviewers a key, it goes into Play Console's App access field only, never into the repo, the app or this document. Government, financial, health, news, COVID: no. Foreground service: the `dataSync` text in §9's table. Photo and video permissions: none requested (the picker needs none; `WRITE_EXTERNAL_STORAGE` only up to Android 10, task 6 checks the merged manifest). Target audience: **13 and over**, not designed for children; choosing under 13 would bring the Families policy and its SDK rules.

**Apple, App Privacy label:**
- Data used to track you: **none**. Data linked to you: **none**.
- Data not linked to you:
  - **User Content → Audio Data:** App Functionality (Groq).
  - **User Content → Other User Content:** Analytics (ML Kit). (App Functionality, for Fix with Groq's lines and the video's name, was dropped in M36.)
  - **Identifiers → Device ID:** Analytics, App Functionality (ML Kit).
  - **Usage Data → Product Interaction:** Analytics, App Functionality (ML Kit).
  - **Diagnostics → Performance Data:** Analytics, App Functionality; **Other Diagnostic Data:** Analytics (ML Kit, GoogleDataTransport).
  - **Other Data → Other Data Types:** Analytics, App Functionality (ML Kit).
- Before submitting, compare with Xcode's privacy report (Organizer → the archive → Generate Privacy Report), which merges every manifest; the label must cover it.
- Our own manifest is `ios/Runner/PrivacyInfo.xcprivacy` (added in this task, in the Runner target): no tracking; audio data and other user content for app functionality; required-reason APIs used by `ShareInbox.swift`: disk space (`E174.1`, room to copy a share) and file timestamps (`C617.1`, staged shares older than a day in the app's and the App Group's containers). Without it App Store Connect rejects the upload (ITMS-91053). The Share Extension uses neither API, so it has no manifest.
- Guideline 5.1.2(i): FR-30. Guideline 5.1.1(v) (account deletion): no accounts.

**Export compliance:** the only encryption is HTTPS (TLS from the OS and Dart's `HttpClient`) and the platform's own key storage; the app implements no cryptography. That is exempt, so `ios/Runner/Info.plist` has `ITSAppUsesNonExemptEncryption` = NO (added in this task) and App Store Connect won't ask per build; no documentation is uploaded. Play asks nothing; the same exemption applies.

**Content rating:**
- Play (IARC questionnaire): category "All other app types". Violence, fear, sexuality, language, controlled substances, gambling, crude humour: no. Users interact or exchange content: no (no in-app communication; sharing goes through the system share sheet). Shares location: no. Digital purchases: no. Unrestricted internet: no (only Groq's API). Expected: Everyone, PEGI 3, USK 0.
- Apple: every content question "None" or "No"; no unrestricted web access, no user-generated content shown to other users, no messaging, no ads. Expected 4+. The user's own videos are not rated: the app doesn't publish them.

### 9.3 Listing rules (M27 task 5)

**History (M43):** written for the stores, dropped on 2026-11-12. The no-brands and own-footage rules are still good practice for the IzzyOnDroid and F-Droid listings, but are not required by them.

- **No other brands:** "YouTube", "WhatsApp" and also Instagram, TikTok, Snapchat, Facebook stay out of the app name, subtitle, short and full description, keywords, promotional text, screenshots and preview video, and so do their logos (Play's metadata and impersonation rules; Apple guideline 2.3.7 and 5.2). "Status" alone is a generic word and is fine. Don't say "for WhatsApp Status".
- **Screenshots and preview:** the owner's own footage, with lyrics the owner may show (own words, or text in the public domain); no third-party video, music video or TV clip. The Size step's preset hints name Reels, TikTok, Shorts, Instagram and Facebook (`frame_controls.dart`), so that screen stays out of screenshots unless the hints are changed (the owner's call; the dead "WhatsApp Status may cut it" warning in `fine_tune_screen.dart` is never shown).
- **Claims:** no "best", "#1", rankings or prices in the name or icon; describe only what the app does. Say that writing lyrics needs a free Groq key and sends the audio to Groq, and that clips without lyrics need nothing.
- **Drafts (no brands):**
  - Name: Status Studio. Apple subtitle (30): "Lyric clips for your status". Play short description (80): "Turn your own videos into short lyric clips for your status, in any language."
  - Apple keywords (100): `status,lyrics,captions,video,clip,urdu,arabic,naat,subtitles,story,reel,editor`.
  - Full description: "Status Studio turns a video you have already trimmed into a short, captioned clip. Share a video in or pick one from your gallery. Get the lyrics written for you by Groq's speech-to-text with your own free Groq key, in Urdu, Arabic, Punjabi, Persian, Hindi, Bengali or English, or make the clip without lyrics. Fine-tune each line to half a second, choose who stays in frame in every scene, pick a size (9:16, 4:5, 1:1, 16:9 or your own crop), style the caption, including Nastaliq for Urdu, and export. Save the clip to your gallery or share it. Your video stays on your phone: only the sound goes to Groq, and only after you agree. Use videos you have the right to share."
- **Icon and graphics:** the Trim logo (§7); Play's feature graphic without other brands.

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
3. **WhatsApp Status limit (2026-11-02).** 60 s is the general limit, and 90 s has been seen only in beta. The 60 s warning stays; confirm on a phone.
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
   - **Speed:** about 1.4–2.2 s per piece (0.55 MB up), roughly 45× real time. Mobile data and the phone are still to measure.
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
7. **Person detection on the phone (M20 task 1; extended to bodies in M25 task 1; run on the Redmi Note 11 on 2026-11-06, result below).** Question: can ML Kit face detection find the person in a clip fast enough and often enough on a Redmi Note 11 (profile build) to make Follow the person (FR-23) worth shipping? Clips: three of 30 s, a naat singer facing the camera, a wide shot with two people, and calligraphy only. Sampled at 4 fps, long side 640.
   - **Measure:** frame extraction time, detector ms per frame, recall against a hand count, false-positive frames, arm64 APK growth.
   - **Go** if all hold: ≤ 15 s in total per 30 s clip, recall ≥ 80 %, false positives ≤ 5 % (the calligraphy clip gives no keyframes), APK growth ≤ 8 MB. If recall is under 80 %, try face plus pose; if that still misses, no-go.
   - **Bodies (M25 task 1, added 2026-11-05):** FR-27 may offer a body as well as a face. ML Kit pose detection finds only one person per frame, so it can't offer several bodies. A COCO person detector, such as EfficientDet-Lite0 via `tflite_flutter` (about 4.4 MB), finds several. Measure the same things on the Redmi Note 11 (time per frame, recall, false positives, APK growth) for faces plus bodies, and record which detector to use, or no-go for bodies. Faces and spots don't wait for this: only body choices (M25 task 5) do.
   - **Result (2026-11-06, M25 task 1, run on the Redmi Note 11: Snapdragon 680, 5.8 GB, Android 13).** Scratch branch `spike-bodies` (local, never merged; `lib/spike_main.dart`, a debug build under the application ID `…statusstudio.spike`, so the installed app was untouched). Input: the 69 s reference clip (1080p, 25 fps, 11 scenes) sampled at 4 fps, 640 px JPEGs as the app makes them, 276 frames; 4 CPU threads; debug build, so Dart-side times are inflated and native inference is not.

     | Detector | ms per frame (mean, p95) | Frames with a result | What it found |
     |---|---|---|---|
     | ML Kit face detection (the app's) | 102, 120 | 276 / 276 | 4–8 faces in the stage and close-up scenes, 41–54 tiny faces in the two crowd shots; misses turned-away heads |
     | ML Kit pose detection (base, single) | 57, 78 | 220 / 276 | always one person, whose box was often on the wrong one: **no-go for choosing among several** |
     | EfficientDet-Lite0, TF Hub build with NMS (4.4 MB), person ≥ 0.4 | 255 inference, 329 with decoding (p95 287 / 362) | 276 / 276 | 6.1 people per frame on average, at most 9; in the 11 frames checked by eye (one per scene) every clearly visible person had a box, give or take one, and the crowd shots gave only the 3 foreground people |

     - **Time:** faces and bodies on every frame at 4 fps would take about 51 s for a 30 s clip (120 × (0.10 + 0.33)), over the 15 s limit above. So bodies are not looked for in every frame (task 5): only in each scene's picture frame, and, for a scene whose answer is a body, in that scene's frames at 2 fps, after the last answer.
     - **Recall and false positives:** recall is above 80 % on the clip, but by eye on 11 frames, not a full hand count. False positives could not be measured: the reference clip has people in every frame, and there was no person-free clip. Of 1,687 detections at 0.4 or more, 15 were not a person and are ignored.
     - **APK growth (release, per ABI, measured by building with and without `tflite_flutter` and the model):** arm64 66.9 MB → 78.3 MB, **+11.4 MB** (armeabi-v7a +9.0 MB, x86_64 +13.2 MB). That is over the 8 MB limit above. The model is 4.4 MB; the rest is TensorFlow Lite's native library. `tflite_flutter` 0.12.1 also failed to build under this project's JDK (inconsistent Kotlin and Java targets) until `kotlin.jvm.target.validation.mode=warning` was set in `android/gradle.properties`.
     - **The body's anchor** (`_bodyAnchorFor`: the box's horizontal centre, and the point a third of the way down its box placed a third of the way down the window) is one reading of FR-27's "centre, in its upper third" and is still provisional: check it on the phone with a body chosen.
     - **Not measured:** a release build's times, the GPU or NNAPI delegates (which could cut the 255 ms), a person-free clip, a second device, and whether the plugin's native library is 16 KB page aligned (a Play Store rule for newer targets; M27).
     - **Verdict:** pose: no-go. EfficientDet-Lite0: recall good, time fine only on demand, **size over the limit by 3.4 MB**. M25 task 5 was built because the owner asked for it ("do task 1 and 5", 2026-11-06), and the owner accepted the size ("no issue for apk size", same day), so the 8 MB limit is waived for the body detector. Its commits are separate, so the 11.4 MB could still be taken back later.
   - **AV1 (answered 2026-11-10, on the phone):** the bundled FFmpeg can't decode AV1. Its build has no external libraries (no dav1d or libaom), `--disable-mediacodec` and `--disable-autodetect`, and FFmpeg's own `av1` decoder only works through a hardware decoder, so every frame-decoding run fails with "Your platform doesn't support hardware accelerated AV1 decoding … Function not implemented". Runs that drop the video (`-vn`, audio only) are not affected. M31 converts AV1 videos to H.264 on import.
   - **Not checked yet:** which face-detection plugin version resolves against `google_mlkit_commons` ^0.13.0, whether `scdet` with `metadata=file=` behaves as FR-23 assumes (if the build lacks the filter the run is repeated without it; the jump rule applies either way).
8. **Voice cleaning (M24 task 3, desktop plus device; tool built, run pending).** Question: do the FFmpeg filters of FR-26 make Groq's lyrics more accurate? The defaults in FR-26 stand until this check tunes them.
   - **Clip:** `assets/videos/Wasif Attari qadri - Arshe Haq He … FAISALABAD.mp4` (69 s, 1080p H.264, AAC stereo 44.1 kHz). `assets/videos/` is in `.gitignore` and the file is never declared in `pubspec.yaml`, so it stays out of the repo and the app.
   - **Expected lyrics:** 10 lines, committed as `tool/voice_check/arshe-haq-expected.txt`. They start with "دیکھ لے دامن خیرات کیا ان سے ملا" and end with "بٹتی ہے کونین میں نعمت رسول اللہ کی", written twice.
   - **Tool:** `tool/voice_check.dart`, run with `fvm dart run tool/voice_check.dart <video> <expected.txt>`. It builds the FFmpeg arguments with the app's own `audio_arguments.dart`, runs them with the Mac's Homebrew `ffmpeg` (its version is recorded next to the bundled 7.1), sends the pieces to Groq `whisper-large-v3-turbo`, and reads the key from `GROQ_API_KEY`. The key is never written to a file or printed. Network access stays in `tool/`; app tests never touch it.
   - **Variants:** from the follow-up below, `whisper-large-v3-turbo` and `whisper-large-v3`, each with no prompt and with a short Urdu hint ("This is a naat sharif in Urdu", no lyrics in it), each on raw and cleaned audio, language automatic (eight runs); the first run used turbo only, raw and cleaned, automatic and `ur`, plus any filter values being tuned. The text is kept as the app keeps it: segments above `groqNoSpeechCutoff` are dropped.
   - **Score:** character error rate (CER) against the expected text, after normalising both: lower case; remove harakat (U+064B–065F, U+0670), tatweel and ZWNJ; map ي ى ی to ی, ك ک to ک, ہ ه ة to ه, and أ إ آ ٱ to ا; collapse whitespace; join the lines. Lines missing compared with the expected text (a repeat Whisper dropped) are listed separately.
   - **Pass:** cleaned CER below raw CER, and at most 15 %. If 15 % is out of reach with filters alone, record the best result and stop. Don't tune against this one clip until it overfits: spot-check the chosen values on one more clip.
   - **Result (2026-11-06, Mac ffmpeg 8.0.1 Homebrew, Groq `whisper-large-v3-turbo`, one 90 s piece, `temperature` 0):** **FAIL**. Cleaning did not help on this clip.

     | Audio | Language | CER | Lines missing |
     |---|---|---|---|
     | raw | auto | 42.3 % | 5 |
     | cleaned | auto | 43.2 % | 5 |
     | raw | `ur` | 42.3 % | 5 |
     | cleaned | `ur` | 43.2 % | 5 |

     - **Chosen values:** none changed. The defaults of FR-26 stay, and the pass mark (cleaned below raw and at most 15 %) is not met in either language mode. 0.9 points is within what one different word costs; it is not evidence that the filters hurt.
     - **Language:** automatic detection already picks Urdu, so `ur` gives the same text. Forcing the language is no help here.
     - **Where the errors are:** not noise. Groq wrote nothing for the first four sung lines and only the tail of the fifth ("دیکھ لے دامن خیرات…", half of the 10 lines) in all four runs, and heard `قومین` for `کونین` in the closing lines. (An earlier scoring pass counted six lines missing: its best-match rule let a misheard line swallow the next; it now takes the first match, and the CER never changed.) Raw and cleaned lose the same lines, so filters on this clip can't win them back; something else (the long, instrument-led opening, or Whisper skipping what it takes for music) is dropping them.
     - **Per spec:** 15 % is out of reach with filters alone on this clip, so the best result is recorded and tuning stops here (no tuning against one clip). The spot check on a second clip is still open. Whether to keep the filters, since they cost time on the phone and bought nothing here, is the owner's call (§14 asks for the timing).
     - **Follow-up, same day (the owner corrected lyrics lines 5 and 8 first, so turbo's numbers moved by about a point):** two free ideas on the same key, tried on the one clip.

       | Model | Prompt | Raw CER | Cleaned CER | Lines missing |
       |---|---|---|---|---|
       | turbo | none | 43.4 % | 44.3 % | 5 and 5 |
       | turbo | Urdu hint | 52.5 % | 22.2 % | 6 and 1 |
       | **large-v3** | none | **22.4 %** | 25.1 % | 1 and 1 |
       | large-v3 | Urdu hint | 23.3 % | 22.4 % | 1 and 1 |

     - **Reading it:** `whisper-large-v3` (not turbo) hears the opening lines turbo drops: about half the error (22 to 25 %), whatever the prompt or filter. It still drops one of the two repeated closing lines, and mishears a few words ("قومین" for "کونین", "کتایاں نے" for "گدایان"). Turbo with the hint swings from 52.5 % to 22.2 % between raw and cleaned, so the hint is not reliable. Cleaning does nothing consistent: it is worse for large-v3 without a prompt (25.1 against 22.4) and better with the hint (22.4 against 23.3). Both are one clip and about one word each, so neither is evidence. Nothing is at 15 % yet.
     - **Decision (2026-11-06, the owner):** the app moves to `whisper-large-v3`, no prompt, with the cleaning filters left in place (FR-26 stays unproven, and nothing here says they hurt). `scriptModel` and `groqSource` changed; FR-3, FR-12a, FR-14, §9 and CLAUDE.md say so. **Risks to check on the phone (§14):** price and free-plan limits (`whisper-large-v3` costs more per audio hour than turbo and may count differently against the free plan), speed on a long video, and the live no-speech cutoff dropping a sung line. The spot check on a second clip is still open.
9. **First iOS build (M26 task 1, run 2026-11-10 on the Mac; the share package question is answered in M26 task 3: our own channel).** Question: does the app and every plugin build for iOS? Deployment target 15.5 (ML Kit), bundle ID `com.hotmail.arehmananis.statusstudio`; `pod install`, then `fvm flutter build ios --no-codesign`. Check that these resolve: ffmpeg_kit min, both ML Kit packages, `tflite_flutter` (if M25 chose it), gal, flutter_secure_storage, flutter_local_notifications, image_picker and the share package. Record the IPA size and any plugin that fails. ML Kit has no arm64 simulator support, so face detection can only be checked on a device (§14). The ffmpeg_kit iOS podspec also excludes arm64 from simulator builds, so simulator runs need x86_64 (Rosetta); device builds are unaffected.
   - **Result (2026-11-10; Xcode 27.2, CocoaPods 1.16.2, Flutter 3.47.8 through FVM):** the app and every plugin build for a device. `pod install` first needed `fvm flutter precache --ios` (without `Flutter.xcframework` the Podfile's post-install hook stops). Deployment target 15.5 is set in the Podfile (`platform :ios, '15.5'`) and in the project. `fvm flutter build ios --no-codesign` (release) ended with no error: `Runner.app` is **132.5 MB** unsigned (arm64 only; `Runner` binary 76.8 MB, `App.framework` 15 MB, `Flutter.framework` 10 MB, FFmpeg's libav frameworks about 13 MB), and zipped as an unsigned `Payload/Runner.app` it is **53.8 MB** (51.3 MiB); a signed IPA needs the Apple Developer account and was not made (compare the arm64 release APK, 78.3 MB). The bundle ID is `com.hotmail.arehmananis.statusstudio`, `MinimumOSVersion` 15.5, display name "Status Studio".
   - **Plugins, each resolved and linked:** `ffmpeg_kit_flutter_new_min` (7.1.1: `ffmpegkit` and the `libav*` frameworks), `google_mlkit_face_detection` and `google_mlkit_translation` with `google_mlkit_commons` (ML Kit pods plus `GoogleMVFaceDetectorResources.bundle` and `MLKitTranslate_resource.bundle`), `tflite_flutter` (TensorFlowLiteC 2.12.0 linked statically; `TfLiteModelCreate`, `TfLiteInterpreterCreate` and the rest are exported by `Runner`, which is where `DynamicLibrary.process()` looks; the 4.4 MB `assets/models/efficientdet_lite0.tflite` is in `flutter_assets`), `gal`, `flutter_secure_storage` (darwin), `flutter_local_notifications`, `image_picker` (PHPicker), `share_plus`, `video_player` (AVFoundation), `shared_preferences`, `path_provider` and `flutter_foreground_task`. No plugin failed.
   - **Notes, none of which stopped the build:** (a) five plugins have no Swift Package Manager support (`ffmpeg_kit_flutter_new_min`, `google_mlkit_commons`, `google_mlkit_face_detection`, `google_mlkit_translation` and `tflite_flutter`); Flutter says this "will become an error in a future version", so a Flutter upgrade can break the iOS build until they ship it. (b) `ffmpeg_kit_flutter_new_min` and the ML Kit pods have no arm64 simulator slice, as the item above says; simulator runs need x86_64 (Rosetta) and ML Kit's face detection still has to be tried on a device. (c) CocoaPods prints "Can't merge user_target_xcconfig … `EXCLUDED_ARCHS[sdk=iphonesimulator*]` has different values" and "did not set the base configuration" for the Profile configuration (it reuses `Release.xcconfig`); neither affects a device build.
   - **Not checked here (needs an iPhone or the Apple Developer account):** signing, a run on a device, whether `tflite_flutter`'s `Interpreter.fromAsset` and the `IsolateInterpreter` run on iOS, ML Kit face detection, the Share Extension on a device, FFmpeg's speed on the phone's CPU, and the render matching Android.

10. **Links and sections on the desktop (M44 task 7, run 2026-11-12 on the Mac, yt-dlp 2026.10.26, Homebrew FFmpeg).** Question for M45 and M46: how often is H.264 at or under 1080p offered, can a section be downloaded at exact times, and what captions do Urdu talks have? Five Urdu talks from a YouTube search (26–126 min: `UTHXU2dOO6Y`, `SFfQJtCP6Ok`, `GfN-uVDPYnU`, `SKnEJ9QXWE8`, `mdFmE1FNO20`).
   - **Reading (`-J`, with JavaScript, desktop):** 1.7–3.6 s each.
   - **H.264:** offered on all five, at the best height up to 1080p (three at 1080p, two whose best is 720p). AV1, VP9 and H.264 are all listed. So M46 can pick `bv*[vcodec^=avc1][height<=1080]+ba[ext=m4a]` and almost never need M31's convert.
   - **No combined stream:** none of the five lists a format with both picture and sound (not even the old 360p format 18). Review cuts' Play must download its piece (M45 design: confirmed).
   - **Captions:** no uploaded captions on any. Four have YouTube's auto captions, all as **Hindi** (`hi-orig`, Devanagari script) because YouTube hears Urdu as Hindi; one has none. YouTube's `ur` track is a machine translation of that Hindi. For M45: the topic search reads Devanagari transcripts with a topic typed in Urdu, English or Roman Urdu, so the model must match across scripts (add to the M45 spike); a fifth of videos may need Groq Whisper.
   - **Sections:** `--download-sections "*600-615"` took 13–16 s for 15 s of 1080p and lands on the exact times: frames of the stream copy match a re-encoded `--force-keyframes-at-cuts` copy at 0.5, 5 and 10 s (PSNR 46–48 dB at the same time, 15–27 dB half a second off). The stream copy does it with an MP4 **edit list**: it keeps the 2.3 s back to the previous keyframe and hides them (video `elst` media time 29440 at 1/12800). The re-encoded copy needs libx264, which the phone's FFmpeg may lack.
   - **Decision for M46:** stream-copy sections with the margin, then the join (Media3) clips each cut at its exact times in its own timeline.
   - **On the Redmi Note 11 (2026-11-12, debug build of M45):** a link shared as text opens Source and reads by itself (FR-35). The card shows 36.7 s after the share on the first run (Python unpacking), 12.9–13.9 s on later runs, app start included. The APK carries Python (`libpython.zip.so`, 14.3 MB) and QuickJS but **no FFmpeg for yt-dlp** (`libffmpegkit` is ours and yt-dlp can't run it), so `--download-sections` can't work on the phone as built. **Revised for M46:** download each cut's byte ranges from the DASH segment index (M7's ranged downloader, restored), which start at a keyframe, mux them with `ffmpeg_kit` (stream copy of local files, which the min build can do), and let Media3 clip from that known start. No edit list is involved, so the edit-list question above no longer matters. The alternative, youtubedl-android's `ffmpeg` module, would add a second FFmpeg build to the APK. **Phone checks (the owner's):** that Media3 respects the edit list (the first frame shown is at the asked time, not up to a GOP earlier), that youtubedl-android's FFmpeg handles `--download-sections`, reading time on the Redmi, and the APK size with Python back.

11. **Topic search with Groq (M45, run 2026-11-12 from the Mac with the owner's key, the app's prompts ported to Python).** Video `UTHXU2dOO6Y` (26 min, Urdu talk on shukr), YouTube's Hindi (Devanagari) auto captions: 508 lines, 442 blocks, 49,944 bytes.
   - **Tokens:** about 5 UTF-8 bytes a token for Devanagari (2,606 prompt tokens for a 13.5 KB part), not 3 as estimated; parts were raised to 20,000 bytes (three parts for this talk). A whole search cost about 12,000 tokens, so the free plan's 200,000 a day allow about 17 searches on a talk this long. Parts hit the 8,000 tokens-a-minute limit; Groq asked for waits of 2–19 s, which the client waits out.
   - **Matching across scripts works:** topics typed in Urdu ("شکر کیسے ادا کریں"), English ("how to be grateful to Allah") and Roman Urdu ("shukr ki ahmiyat") all found the gratitude passages in the Hindi-script text, at scores 0.9–0.96, with sensible English reasons.
   - **Models:** `openai/gpt-oss-120b` kept. `openai/gpt-oss-20b` found a similar moment on part 1 and could read the parts later (a separate rate limit); `llama-3.1-8b-instant` no longer exists on Groq.
   - **Length:** the model returned moments of 33–109 s, so a 60 s clip first came out at 45 s (no two fitted). The prompt was changed to ask for shorter moments and the fit trimmed to the room left (60.8 s of 60 s). Then the owner chose to see every moment and tick them, none ticked at first, over length allowed (task 10), so the fit and the picking call went; the prompt asks for 8–30 s.

## 11. Out of scope for v1

- iOS release and Play Store or App Store builds were out of scope for v1. Since 2026-11-05 they were planned (iOS in M26, store readiness in M27); on 2026-11-12 the stores were dropped (M43). iOS stays buildable, not distributed.
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
- Device testing is the owner's, outside this document (§14).

| Milestone | Delivered | Status |
|---|---|---|
| M1 App shell | Every screen with fakes; selection, clip, crop maths, link parsing | Done, in `dev` |
| M2 Video source | Metadata, downloads, cache, preview | Done, in `dev` |
| M2b Data saver | Low-bitrate script audio, clip-only download (FR-15) | Done, in `dev` |
| M3 Transcription | Model manager, chunked Whisper (both removed in M10), captions, language inference, saved scripts, resume | Done, in `dev` |
| M4 Fine-tune | Waveform, long-clip warning, language re-run | Done, in `dev` |
| M5 Render | Overlay PNG, Roman Urdu, translation, Media3 export | Done, in `dev` |
| M6 Library and settings | Save/share, Recent, Settings, launcher icon, cache cleanup, §8 errors | Done, in `dev` |
| M7 yt-dlp | yt-dlp source, self-updating; percent, sizes and speed per step | Done, in `dev` |
| M8 Background work | Foreground service, result notifications, battery access (FR-16) | Done, in `dev` |
| Speech models | Quantised files for all models, with pros and cons | Done, in `dev` |
| Saved scripts in Recent | Script rows in Recent (FR-11) | Done, branch `saved-scripts-in-recent` |
| Model download controls | Pause, resume, cancel (FR-12) | Done, branch `model-download-controls` |
| M9 Groq | Optional cloud transcription (FR-12a, §8) | Spec done; tasks to write, branch `m9-groq-transcription` |
| M10 Groq only | Remove on-device Whisper; Groq writes every script that has no captions | Tasks 1–7 done, branch `m10-groq-only` (stacked on M9) |
| M11 Timed captions | One caption line at a time (FR-7a) | Done, branch `m11-timed-captions` (stacked on M10) |
| M12 Real lyrics | Lyrics from lrclib.net replace the script (FR-17) | Done, branch `m12-online-lyrics` (stacked on M11); removed in M17 |
| M13 AI script fix | Copy the script with a prompt for an AI agent; paste its corrected reply (FR-18) | Done, branch `m13-ai-script-fix` (stacked on M12) |
| M14 Preview and file name | Done plays the reel; the file is named `<kalam>-<start>-<end>` (FR-9, FR-10) | Done, branch `m14-reel-preview` (stacked on M13) |
| M15 Fix with Groq | Script button that fixes the lines with a Groq web-search model and the existing key (FR-19) | Done, branch `m15-groq-script-fix` (stacked on M14) |
| M16 Launch animation | Dark native splash with the logo; Flutter animates the logo, then shows Home (FR-20) | Done, merged into `main` |
| M17 Fix with Groq only | Script keeps only the Fix with Groq button; Real lyrics, Copy for AI and Paste AI reply and the lyrics feature are removed | Done, branch `m17-groq-fix-only` |
| M18 Fine-tune lines | Play, pause and seek; edit, reorder, add and delete lines; tap a line while playing to time it (FR-5, FR-21) | Done, branch `m18-fine-tune-lines` (stacked on M17) |
| M19 Fine-tune steps | Fine-tune in two steps: Video (nudges, size, crop that can move) and Lyrics (the clip's lines, timing, video with the lyrics on it) (FR-5, FR-21, FR-22) | Done, branch `m19-fine-tune-steps` (stacked on M18) |
| M20 Follow the person | A button that makes the moving crop follow a person, by on-device face detection (FR-23) | Built, branch `m20-follow-subject` (stacked on M19); its automatic pick is replaced by FR-27 (M25); the face half of the spike ran in M25 (§10 item 7: 102 ms a frame) |
| M21 Continue later | Fine-tune is kept as it changes and continued from Recent (FR-24) | Built, branch `m21-fine-tune-drafts` (stacked on M20) |
| M22 Choose the person | Tap a face to choose whom Follow the person follows (FR-25) | Built, branch `m22-choose-person` (stacked on M20); replaced by FR-27 (M25) |
| M23 Local video in | Share or pick a trimmed video instead of a YouTube link; whole-video clip; YouTube removed (FR-1, FR-3, FR-4, FR-5, FR-14, FR-15) | Built and reviewed, branch `m23-local-video` (from `dev`), pushed, not merged; tests not run (the user tests from task 5, stale ones listed in §12) |
| M24 Clean voice | FFmpeg filters clean the audio before Groq (FR-26, §10 item 8) | Built and reviewed, branch `m24-clean-voice` (stacked on M23), pushed, not merged; the lyrics check (§10 item 8) ran and failed: cleaned 43.2 % against raw 42.3 % on the reference clip, so the filters are unproven; tests not run |
| M25 Choose per scene | At every scene the user picks a face, a body or a fixed spot (FR-27) | Built and reviewed (Opus, several passes), branch `m25-choose-per-scene` (stacked on M24), pushed, not merged. The spike ran on the Redmi (§10 item 7: ML Kit pose no-go, EfficientDet-Lite0 used; APK +11.4 MB accepted by the owner). The owner confirmed on the phone (2026-11-06) that the faces, bodies and spots walk works. Fixed on the way, from phone logs: exact Cut keyframe timing, the preview players released before Caption and Export (decoder error -12), preferences lost after a service ends (§5), Export's Retry after a failed save. Tests not run (the user tests; stale ones in §12) |
| M26 iOS | iOS build, Share Extension, AVFoundation renderer, background work (§10 item 9) | Built, branch `m26-ios` (stacked on M25), pushed, merged into `dev` (2026-11-10). `fvm flutter build ios --no-codesign` succeeds (§10 item 9). The Share Extension, the AVFoundation renderer and the iOS background work were **never run**: they need an iPhone and the Apple Developer account (signing, the App Group). Opus reviewed tasks 1–4; tasks 5–7 and the whole branch were not reviewed at the owner's request. Tests not run (the owner tests; stale and new ones in §12) |
| M27 Store readiness | Consent, privacy policy, store answers and release builds for Play and the App Store (§9) | Built, branch `m27-store-readiness` (from `dev`, which holds M26 and M28), pushed, merged into `dev` (2026-11-10). Consent before Groq (FR-30), no battery-optimisation request, §9.1–9.3, a privacy manifest, a signed Play bundle and an unsigned iOS archive. Pending the owner: policy hosting, the store forms, and the Apple account for signing and TestFlight (§14). Tests not run |
| M28 Lyrics optional | Make a reel without a script: no Groq, no Lyrics step, a caption the user may type (FR-29) | Built, branch `m28-lyrics-optional` (from `dev`), merged into `dev`; tests not run |
| M29 Free crop on the player | Edit the free crop over the video on Fine-tune · Video instead of a separate editor (FR-6) | Built, branch `m29-free-crop-on-player` (from `dev`), merged into `dev` with M30 (2026-11-10); tests not run |
| M30 Crop and lyrics flow | Trim and Crop tabs with a scene strip; one Lyrics screen (switch, Get from Groq, edit, Style sheet); Processing and Caption removed; original captions only (M30 design below) | Built, branch `m30-crop-and-lyrics-flow` (stacked on M29), merged into `dev` (2026-11-10); tests not run |
| M31 AV1 to H.264 | An AV1 video is converted once to H.264 when it comes in, since the bundled FFmpeg can't decode AV1 (FR-1, §10 item 7) | Built, branch `m31-av1-to-h264` (from `dev`), merged into `dev` (2026-11-10); tests not run |
| M32 Clear scene markers | Face and body boxes on the scene picture no longer cover the person: corners only, number tag outside (FR-27) | Built, branch `m32-clear-scene-markers` (stacked on M31), merged into `dev` (2026-11-10); tests not run |
| M33 Support and About | Settings becomes a list with one screen per category; Support (feedback or complaint by email or WhatsApp, with device details; call) and About (version, licences) (FR-31) | Built, branch `m33-about-support` (from `dev`), merged into `dev` with M35 (2026-11-10); tests not run |
| M34 Large text | Text size capped at 1.3×, one-line app bar titles, section labels above body text (§4) | Built, branch `m34-large-text` (stacked on M33), merged into `dev` with M35 (2026-11-10); tests not run |
| M35 Theme choice | Light, dark or system theme in Settings (FR-32) | Built, branch `m35-theme-choice` (stacked on M34), merged into `dev` (2026-11-10); designed with the owner from mockups (2026-11-10); tests not run |
| M36 Remove Fix with Groq | The Fix with Groq button and everything behind it go; lyrics are fixed by editing the lines (FR-19) | Asked by the owner (2026-11-10); branch `m36-remove-groq-fix` (from `dev`), merged into `dev` (2026-11-10); tests not run |
| M37 Caption looks | Box or Shadow caption, each in four colours, remembered for the next reel (FR-7) | Built, branch `m37-caption-looks` (from `dev`), merged into `dev` with M40 (2026-11-11); tests not run |
| M38 Fade at the ends | A switch on the Trim tab fades the picture, caption and branding in from black and out to black, 0.5 s each end (FR-33) | Built, branch `m38-fade-ends` (stacked on M37), merged into `dev` with M40 (2026-11-11); APK and unsigned iOS build succeed; tests not run |
| M39 Undo on Lyrics | Undo and Redo in Lyrics' app bar for every line change, with a quick Undo after a delete or a tap-to-time (FR-34) | Built, branch `m39-lyrics-undo` (stacked on M38), merged into `dev` with M40 (2026-11-11); the step label moved under the title after the owner's phone check; tests not run |
| M40 Lyrics fixes | A clip over silence selects no lines (Add line puts one in); dragging a line scrolls the screen; edits stay the newest script when a run finishes late (FR-21, §15) | Built, branch `m40-lyrics-fixes` (stacked on M39), merged into `dev` (2026-11-11); tests not run |
| M41 Play the clip | A second button on Fine-tune · Video's player plays the clip from its start and pauses at its end; Play still starts at the seek bar; a clip can't start before a late picture (FR-5) | Built, branch `m41-play-clip` (from `dev`), merged into `dev` (2026-11-12); tests not run |
| M42 Freezed models | `SourceVideo`, `SavedTranscript`, `PartialTranscript` and `RecentReel` use `freezed` and `json_serializable`; saved JSON unchanged (§11) | Built, branch `m42-freezed-models` (from `dev`), merged into `dev` (2026-11-12); analyze clean apart from two older unused-widget warnings in `fine_tune_trim_tab.dart`; tests not run |
| M43 Off the stores | Stores dropped; GPL-3.0 and a public repo; keystore out of history; IzzyOnDroid (M43–M47 design) | Tasks 1–5 built, branch `m43-off-the-stores` (from `dev`), pushed, not merged. Task 6 (backing up the key, scrubbing history, going public, first release) is the owner's. A history scan found no other secrets (only the keystore and `key.properties`). Tests not run |
| M44 Link in | Paste or share a link (Android); yt-dlp back, self-updating (FR-35) | Built, branch `m44-link-in` (stacked on `m43-off-the-stores`), pushed, not merged. Debug APK builds with youtubedl-android back. Desktop spike done (§10 item 10: H.264 on 5 of 5, no combined streams, Urdu auto captions come as Hindi, stream-copy sections exact through an edit list); the phone half is the owner's. Tests not run |
| M45 Find the topic | Topic and length; transcript from captions or Groq; a Groq chat model picks the moments; Review cuts with the transition picker (FR-36) | Built, branch `m45-find-the-topic` (stacked on `m44-link-in`), pushed, not merged. Debug APK builds. Make the clip and Play on a card wait for M46. The model spike (§10, needs a Groq key) is the owner's; the model is `topicModel`. Tests not run |
| M46 Download and join | Only the cuts download; joined with the transition into one video that opens Fine-tune, a scene per cut (FR-37) | In progress, branch `m46-download-and-join` (stacked on `m45-find-the-topic`) |
| M47 F-Droid | ML Kit face detection replaced by an open model; built from source for F-Droid's main repository | Designed (2026-11-12), not started |

**Pending ideas (2026-11-05):** "Share from YouTube" is back in M44 (FR-35, 2026-11-12). "Follow automatically" is dropped (automatic follow contradicts "do not assume", FR-27). "Search the script" is a later idea (FR-28 reserved, not planned).

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
- [ ] **9. Docs.** §13 tests list, milestone status.

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
- [x] **2. Use it in the piece run.** `-af <chain>` before the FLAC encode in M23's piece run. Processing shows "Cleaning the voice". Cleaned pieces are cached per video, so a retry doesn't clean again. Built: the first stage's label is "Cleaning the voice" (`ScriptStage.preparingAudio`; Processing and the notification both read `stage.label`). `AudioPreparer.cutScriptPieces` writes to `pieces_<seconds>_<8 hex of SHA-256 of the whole FFmpeg command>` and reuses that folder when its `finished` marker, `pieces.csv` and every listed piece exist; the marker is written after FFmpeg returns, because FFmpeg appends to the CSV as it goes and a cut that was cut short would otherwise look complete. Every other `pieces_*` folder beside the video (an older chain, an unfinished cut, M23's `pieces_90`) is deleted first, and an incomplete current folder is emptied and re-cut. A reused cut reports no FFmpeg progress. Tests not run. **Stale for the user to fix:** `test/src/features/transcript/data/audio_preparer_test.dart` (the folder name, reuse and cleanup cases are new), `application/real_script_pipeline_test.dart` and `presentation/processing_screen_test.dart` (the stage label "Preparing the audio"), `FakeAudioPreparer` in the test helpers (if it writes to `pieces_90`).
- [x] **3. Lyrics check against the reference clip (§10 item 8).** *(Run on 2026-11-06: FAIL, cleaned 43.2 % against raw 42.3 %; see §10 item 8.)* The reference clip stays out of the repo and the app (`.gitignore` and `pubspec.yaml` rule: M23 task 1). Commit `tool/voice_check/arshe-haq-expected.txt`; write `tool/voice_check.dart`; compare raw, cleaned and cleaned with `ur`; score by CER; pass is cleaned below raw and at most 15 %; record the table and the chosen values in §10 item 8, and update FR-26 if they change. Add a §14 check: the same clip in the app on the Redmi gives a transcript within 2 points of the Mac CER. Built: `tool/voice_check.dart` and `tool/voice_check/lyrics_score.dart` (normalising, CER, missing lines), run with `read -rs GROQ_API_KEY && export GROQ_API_KEY`, then `fvm dart run tool/voice_check.dart <video> <expected.txt>` (`read` keeps the key out of the shell history). Without the variable it stops with exit code 2 and "waiting for it"; it checks the lyrics file and the key before cutting anything. It builds the arguments with `scriptPiecesArguments` (the raw baseline is the same list without `-af`), runs the Mac's `ffmpeg`, uses the app's own `GroqClient`, scores four variants (raw and cleaned, each automatic and `ur`), prints the table, the ffmpeg version, a PASS or FAIL per language and what Groq heard. To make `audio_arguments.dart` load in plain Dart, it now imports `package:meta/meta.dart` instead of `package:flutter/foundation.dart` (`meta` is a direct dependency now; it was already resolved). Checked offline: the arguments run on the reference clip (one cleaned piece, `pieces.csv`) and the scorer gives CER 0 for identical text, 0.59 for a clipped one and finds a missing line. The expected-lyrics file holds the 10 lines (the owner filled them in; the tool stops if a line starts with `TODO`). The run itself is in §10 item 8. **Still open:** a spot check on one more clip, and the owner's call on keeping the filters. Tests not run (none written for the tool).
- [x] **5. Move to `whisper-large-v3` (added 2026-11-06 after §10 item 8's follow-up).** `scriptModel` is `whisper-large-v3`, `groqSource` is `groq-whisper-large-v3`, `GroqClient` takes a model and an optional prompt (the app sends no prompt). No other copy named the model. Tests not run. **Stale for the user to fix:** `groq_client_test.dart` (the `model` field is `whisper-large-v3`), `transcript_store_test.dart` and `real_script_pipeline_test.dart` and `fine_tune_resumer_test.dart` (anything that spells `groq-whisper-large-v3-turbo`).
- [x] **4. Docs and review.** §13, §14, §12 status; Opus reviews of the commits and of the whole branch with their findings fixed; pushed to `origin/m24-clean-voice`, not merged. Review fixes: the whole-branch review's findings are in: the tool applies the app's no-speech cutoff (`groqNoSpeechCutoff` moved to `groq_client.dart`), the missing-line rule takes the first match, empty lyric lines are dropped after normalising, a missing ffmpeg gets its own message, no boolean flag or fourth parameter in the tool, the documented command no longer puts the key in the shell history, and the pieces folder is named by the whole command. A cancel during the folder work no longer starts FFmpeg, deleting a `pieces_*` folder that is already gone is ignored, and the cut-and-mark step is its own function. **Not changed on purpose:** the review feared `lowpass=7500` fails on audio sampled below 15 kHz because the chain runs before `-ar 16000`; on an 8 kHz test tone FFmpeg 8 ran the chain without error (the filter turns itself off), so the chain stays exactly as FR-26 says. The review also noted that the chain runs on the source's full-rate stereo audio, which is about six times the samples of 16 kHz mono; §14 asks for a timing on the Redmi, and if it is slow the fix is `aresample=16000,aformat=channel_layouts=mono,` in front of the chain (the chain's hash changes the folder name, so old caches are dropped). **Stale for the user to fix:** see tasks 1 and 2.

### M25 tasks (branch `m25-choose-per-scene`)

Request, 2026-11-05: when cropping, ask the user at every scene what to keep in frame: a face, a body or a fixed spot, never assumed (FR-27). Stacked on M24. Same execution model as M23. Each task: test first, `tool/check.sh` once, one commit, tick it.

- [x] **1. Spike (device), §10 item 7 extended.** Faces plus bodies on the Redmi Note 11: ML Kit pose finds one person per frame, a COCO detector (EfficientDet-Lite0 via `tflite_flutter`, about 4.4 MB) finds several. Measure time, recall and APK growth; record which to use. Task 5 depends on it; faces and spots don't. **Run 2026-11-06 on the Redmi Note 11** (scratch branch `spike-bodies`, local only): ML Kit pose is no-go (one person, often the wrong one); EfficientDet-Lite0 finds the people (255 ms a frame, +11.4 MB of APK, over the 8 MB limit); numbers and verdict in §10 item 7.
- [x] **2. Domain: `SceneChoice`.** The sealed type `FollowFace(track)`, `FollowBody(track)`, `HoldSpot(anchor)`, and `pathForChoices(scenes, geometry, choices)` in `subject_path.dart`. Faces reuse `_pathOfScenes` (one track per scene) and `_withTheirOtherSightings` within the scene. A spot is a constant anchor with a Cut keyframe at the scene start. There is no automatic pick and no look-alike carry-over: `followSubject`, "Choose for me" and `_followedInAnotherScene` stop writing keyframes and are removed. Built: `scene_choice.dart` holds the sealed type (`FollowBody` reuses `FaceTrack`, since body boxes are tracked by the same rule); `pathForChoices` takes fewer choices than scenes (the clip's first `mostScenesFollowed` = 12 are asked, and the crop holds the last answer after them) and `anchorForSpot` turns a tapped point into an anchor with the point in the middle of the window (so "Keep the centre" is anchor (0.5, 0.5)). A spot is one Cut keyframe at the scene start. The cap now drops glides before any Cut. `withTheirOtherSightings` moved to `face_tracks.dart` as public. Removed: `followSubject`, `followPerson`, `_followedInAnotherScene`, `mostProminent`, `requireEnoughFaces`, `PersonChoice`, `choosablePeople` (replaced by `pictureOfScene` in `person_choice.dart`: the scene's fullest frame, and who can be chosen in it), `NoSubjectFoundException`, `FollowNoSubject` and the "No person found" message. Tests not run (tasks 2–4 are one commit, because the three layers cannot compile apart). **Stale for the user to fix:** `test/src/features/style/domain/subject_path_test.dart` (`followSubject`, `followPerson`; new `pathForChoices` cases from §13), `person_choice_test.dart` (`choosablePeople`; new `pictureOfScene` cases), `test/src/core/error_messages_test.dart` (~:98, `NoSubjectFoundException`).
- [x] **3. Controller.** `follow_subject_controller.dart` keeps `FollowRunning`, then `FollowChoosing{sceneIndex, sceneCount, picture, faces, bodies}`. Each scene's picture is its fullest frame (`_fuller` from `person_choice.dart`, per scene). Every scene is asked, even with one face or none. Choosing moves to the next scene; Back and Cancel exist. Frames are deleted at the end or on cancel. A hand edit still wins. Built: `FollowChoosing{sceneIndex, sceneCount, sceneStart, sceneEnd, picture, pictureSize, faces, bodies, skippedSceneCount}`; `answer(question, SceneAnswer)` (an answer to a question that is no longer current is ignored) with `PickedFace(index)`, `PickedBody(index)`, `PickedSpot(x, y)`, `WentBack` and `Cancelled` replaces `choose` and `chooseForMe`. After a Back, answering moves on to the first scene still unanswered, so the answers given are kept. `bodies` was empty until task 5 filled it. Tests not run. **Stale for the user to fix:** `test/src/features/style/application/follow_subject_controller_test.dart` (`choose`, `chooseForMe`, `FollowNoSubject`, the old `FollowChoosing` fields, the automatic path for one face), `test/src/features/clip/presentation/follow_subject_section_test.dart` (builds a `FollowChoosing`); new cases are in §13.
- [x] **4. Sheet.** Evolve `person_chooser_sheet.dart`: title "Scene 2 of 5 · 0:07–0:12", hint "Tap a face, a body, or the spot to keep in frame."; a tap within 24 dp of a face picks it, inside a body box picks the body, elsewhere picks that spot with a pin shown before the next scene; TalkBack reads "Person 1", "Body 1" and offers "Keep the centre". The sheet pops with a result and `_askWhom` acts after the await (this fixes the pending double-pop item). The pending `onPanCancel` test for `CropWindowOverlay` goes into this commit, since the same screen is touched. Built: the sheet is stateful (one answer only; the pin shows for 450 ms before a spot's answer; "Back" from scene 2 on; the "more than 12 scenes" warning), and `fine_tune_screen.dart` shows one sheet per `FollowChoosing` state, awaits its `SceneAnswer` (a dismissal is `Cancelled`) and only then calls `answer`; the snackbar says "The crop follows your choices (N keyframes). Drag or tap a chip to adjust.". Tests not run. **Stale for the user to fix:** `test/src/features/clip/presentation/person_chooser_sheet_test.dart` (`onChosen`, `onChooseForMe`, `onCancel`, the title and hint, "Choose for me"), `fine_tune_screen_test.dart` (~:625, :655, :734, :761: the old snackbar, "No person found", and any flow that taps a face once and expects keyframes; it is now a walk through every scene). **New tests to write:** the sheet's face tap within 24 dp, body tap, spot tap with the pin, a second tap ignored, "Keep the centre" action, Back hidden on scene 1; and the pending `CropWindowOverlay` `onPanCancel` test (`crop_window_overlay.dart:137`: start a drag on the `crop-window` key, cancel the gesture, and expect no anchor change and the drag cleared), which belongs to this commit's list because the same screen is touched.
- [x] **5. Bodies (only if the spike says go).** A detector behind `SubjectDetector` returning body boxes; body tracks use the same `couldBeSameFaceAs` distance rule on body boxes; the anchor is the box centre, upper third. Built 2026-11-06, at the owner's request, after the spike (§10 item 7). `SubjectDetector` has `bodiesIn`; `OnDeviceDetector` (ML Kit faces, set up on first use, and `BodyModel`, EfficientDet-Lite0 in its own `IsolateInterpreter`, also on first use) replaces `MlKitFaceDetector`; the model is `assets/models/efficientdet_lite0.tflite` (4.4 MB, Apache 2.0, TF Hub, the build with non-max suppression); `tflite_flutter` 0.12.1 and `kotlin.jvm.target.validation.mode=warning` in `android/gradle.properties` (its Kotlin and Java targets differ under this JDK). Bodies are looked for in each asked scene's picture before the first question (`ScenePicture.withBodies`), and, for a scene answered with a body, in every other frame after the last answer (`trackOfBody`, same distance rule as faces; the picture's own boxes stand for its frame); answers are now kept raw and resolved at the end. A failing body model leaves faces and spots working. **On the phone:** the real `BodyModel` through the isolate, on 9 frames of the reference clip, gave the spike's counts (7, 7, 8, 8, 3, 8, 6, 3, 6 people) at 96–230 ms a frame (first frame 803 ms, the model loading), with the UI isolate's 16 ms ticker at most 148 ms late (95th percentile 39 ms; debug build). **The cost:** +11.4 MB of APK, over the 8 MB limit; the owner accepted it on 2026-11-06. On the phone with the real app the owner confirmed on 2026-11-06 that bodies work (offered, tapped, followed); a release build's times were not recorded. The anchor stays provisional (§10 item 7). iOS (M26) must package the same model and check the plugin there. **Opus review fixes (second commit), re-checked on the phone (same counts, closes cleanly):** a body model that fails to open no longer fails the run through `close()` rethrowing it (FR-27: faces and spots go on); a Cancel during the body phase no longer leaves the progress bar up (the stale check comes before the state is set); a stuck inference times out after 15 s; a hand edit during the pictures' body pass is noticed at once; the model and codec are released on error paths; the body phase's progress reaches 100 %; `_peopleFrom` takes one value object. Tests not run. **Stale or new for the user:** `follow_subject_controller_test.dart` (the fake `SubjectDetector` needs `bodiesIn`; `PickedBody` now resolves after the last answer; the bar shows again), `person_choice_test.dart` (`ScenePicture.bodies` is `List<SubjectBox>`; new `trackOfBody` cases), `subject_detector` has no test (`BodyModel` needs the device).
- [x] **6. Docs and review.** §13 cases, §14 checks, §12 status; an Opus whole-branch review; fix findings; push (not merge). Done: §8, §10 item 7, §12 and §13 and §14 are updated; Opus reviews of the code commit and of the branch. Review fixes (own commit): the spot pin's timer popped a second time if the sheet had been dragged or tapped away during the pin (it would have closed Fine-tune; now it pops only while its route is current); a scene shorter than 0.5 s lost its Cut to the keyframe spacing although it was asked (such cuts now make no scene, FR-27); the frames stayed on disk if asking the first scene threw; `answer` now names its question so a stale answer is ignored; parameter counts in `subject_path.dart` and the sheet's marker were brought to three. The whole-branch review's fixes (second commit): the 0.5 s scene rule is measured to where the Cut keyframe sits (a clip starting at 12.34 s with a cut at 12.84 s still lost the scene's Cut); the 12th scene's sheet shows the clip's end when later scenes are left out; FR-23, §6.1 and §13 lines the new rules replaced are marked. Left as is: `_Picture`'s constructor has six named parameters (a widget constructor, not a function that switches behaviour), and `person_choice.dart` keeps its name though it now holds `ScenePerson` and `ScenePicture`. **Preferences lost after a service ends (2026-11-06, from the user's log):** `shared_preferences_android` 2.5.4 unregisters its one global `data_store` instance when any Flutter engine detaches; the foreground service's engine detaches when a script or export ends, so the next preferences read (Recent, after the export finished) threw `No instance named data_store has been registered`, an `Error`, which Export did not catch, so it stayed at 100 % with Done never opening. `pubspec.yaml` now overrides the plugin to 2.4.26 (unregisters per engine; comment says when to remove it), and Export's `_keepAndOpenDone` catches any `Object`, so a failed save shows the retry state. Both decoder-fix review findings are in too: Caption's preview comes back on `didPopNext` (the push future never completes when Export replaces itself with Done), and a double tap or a Back in the frame before the push opens nothing twice. Retry after a failed save saves the finished render again and does not render twice. New tests to write: Export shows its failure when `keep` throws an `Error`, and Retry then calls `keep` once more without a second render; Caption restores its preview after Done is popped. **Export decoder error (2026-11-06, from the user's logcat):** the export failed at `MediaCodec.configure` with -12/NO_MEMORY because Lyrics' and Caption's preview players still held decoders under Export; Lyrics now releases its player before opening Caption and Caption its preview before opening Export (`untilDismissed` moved to `core/presentation/route_animation.dart`, shared with Fine-tune; `ReelPreviewWithoutVideo`); new tests to write: the two screens show their placeholder while the next route is open and restore it after. **Cut fade tried and removed (2026-11-06):** a dip at scene cuts, first in the Lyrics preview (the playhead's estimate can put its crop a few milliseconds off the picture) and then in the export, was built, reviewed and then removed at the user's request: the export looks fine with exact Cut timing, and they did not want a fade. Nothing of it is left in the code or in FR-21, §6.3.2, §13 or §14; the exact Cut timing below stays. The preview's few-millisecond mismatch remains a known limit of the playhead (`ClipPlayhead` estimates the position between the platform's reports). **Cut timing (2026-11-06, from the user's report of a jerk at scene changes; Opus-reviewed):** a scene's Cut keyframe is at the cut time less 10 ms (`cutKeyframeLead`), not snapped to 0.1 s; a Cut chip seeks to `CropKeyframe.shownAt`; glides too close before a Cut are dropped; `subject_path_test.dart` cases for the Cut times (they expect tenths) are stale. Two things a device check may still show (§14): a source whose first video timestamp is not 0 can put FFmpeg's and Media3's clocks tens of milliseconds apart, and then the lead should be about half a frame. **Stale tests (adds to tasks 2–4):** see those tasks; `subject_path_test.dart` also holds cases for FR-23's "cut right after the clip start moves the first keyframe" and "sixty seconds, a cut every three seconds, reaches past 40 s", which FR-27 replaces; new `scenesOf` and `pathForChoices` cases for the 0.5 s scene rule, including a clip starting at 12.34 s. Pushed to `origin/m25-choose-per-scene`, not merged.
- [ ] **7. Drop the Script screen (request, 2026-11-06, same branch).** Script was a read-only copy of Lyrics. Processing opens Fine-tune when the script is done (or on "Start picking lines", now "Open fine-tune" while lines are still coming); Home's Continue and "script changed" open Fine-tune. Lyrics gets the script tools (FR-5): `ScriptTools` (language, Fix with Groq, saved-script line) and the writing footer, both moved out of `script_screen.dart` into `script_tools.dart` and `script_writing_footer.dart`; the opening notice shows on Fine-tune · Video and its text no longer says "Pick the lines". Step labels become 1 to 4 of 4. `ScriptScreen` and `AppRoutes.script` go. **Stale for the user to fix:** `script_screen_test.dart` (move its Fix with Groq, language and banner cases to a Lyrics test), `processing_screen_test.dart`, `home_screen_test.dart`, `lyrics_screen_test.dart`, `fine_tune_screen_test.dart`, `app_router` tests and any test asserting "Step N of 5" or "Next: fine-tune". Tests not run.

### M26 tasks (branch `m26-ios`)

Request, 2026-11-05: the app must also build for iOS. Stacked on M25. Xcode and CocoaPods are on the Mac, so builds run there; signing and device runs need the Apple Developer account and an iPhone. ML Kit doesn't run on the arm64 simulator, so face detection is checked on a device only (§14). Same execution model as M23. Each task: test first where code allows, one commit, tick it.

- [x] **1. First build (spike, §10 item 9).** Deployment target 15.5, bundle ID `com.hotmail.arehmananis.statusstudio`; `pod install`; `fvm flutter build ios --no-codesign`; check every plugin resolves; record the IPA size and any failure. Done 2026-11-10: it builds, no plugin fails, `Runner.app` 132.5 MB (unsigned IPA 53.8 MB); the target moved from 15.0 to 15.5 in the Podfile and the project, `ios/Podfile.lock` is now committed, and the results and what needs a device are in §10 item 9. Tests not run.
- [x] **2. Info.plist and permissions.** `NSPhotoLibraryAddUsageDescription` for `gal` (saving the reel); PHPicker needs no library permission; bundle the Nastaliq and Naskh fonts; set the display name. Done: the key is added (`gal` 2.3.3 needs only it, since saving without an album asks for add-only access and the app's minimum is iOS 15.5, so `NSPhotoLibraryUsageDescription` is not needed); `image_picker`'s PHPicker needs nothing; the display name was already "Status Studio"; the two fonts need no native step, because Flutter's text engine draws the captions from the font assets in `pubspec.yaml` (CLAUDE.md: captions and branding are drawn by Flutter), and both are in `flutter_assets`. Nothing else to declare for the plugins that were built. Tests not run.
- [x] **3. Share Extension.** A Share Extension target that accepts movies, plus an App Group. A shared video opens the app on Source, as on Android. **Decision: our own channel, not `receive_sharing_intent`** (the reasons of M23 task 3 hold on iOS too, and the plugin also wants the SPM-only integration and a `SceneDelegate` that forwards to it): the iOS side speaks the same `status_studio/video_in` protocol as Android (`listen`, `stopListening`, `freeBytes`, pushed `incomingVideo` and `incomingVideoFailed`), so `IncomingVideoSource`, the importer and Source did not change. Built: target `ShareExtension` (`ios/ShareExtension/`, bundle ID `…statusstudio.ShareExtension`, deployment target 15.5, activation rule `NSExtensionActivationSupportsMovieWithMaxCount` = 1, so it appears for one movie and no other kind) and App Group `group.com.hotmail.arehmananis.statusstudio` in both entitlement files (`Runner/Runner.entitlements`, `ShareExtension/ShareExtension.entitlements`). `ShareViewController` loads the movie's file, copies it (a clone on the same volume, no memory) into the group's `incoming/<id>.part/`, renames that folder to `<id>` when whole (so the app never reads half a video), asks the system to open `statusstudio://shared` (the app's `openURL:options:completionHandler:` is found along the responder chain, because an extension can't call `UIApplication.shared` and `extensionContext.open` works only in Today widgets) and ends. A copy that fails leaves `<id>.failed`, a JSON `{code, message}` (`no_space` for a full phone), which the app reports as `incomingVideoFailed`. In the app, `VideoInChannel.swift` collects the finished shares when it starts and every time the app becomes active, moves each file into `Application Support/incoming/<id>-<name>` (the importer's staging folder, so it is renamed into place and deleted afterwards, as on Android), and hands it over through `ShareDeliveries.swift` (a port of Kotlin's `ShareDeliveries`: pushed while Dart listens, kept otherwise, so the share that launched the app is not lost). So **a share is never lost even when the system refuses to open the app**: it appears on Source the next time the app is opened. Staged copies older than a day are deleted in both containers. `freeBytes` answers the available capacity for important usage. Info.plist: URL scheme `statusstudio` (only to bring the app forward) and `FlutterDeepLinkingEnabled` = NO, so Flutter doesn't push that URL into go_router as a route. File names are cut to 200 bytes (never inside a character, keeping the extension) so `<id>-<name>` fits in 255. The project file was edited with the `xcodeproj` gem (the embed phase sits before "Thin Binary", which avoids a build cycle); `fvm flutter build ios --no-codesign` builds the appex into `Runner.app/PlugIns`. Also fixed for iOS: `image_picker` leaves a picked video in `tmp/` (`NSTemporaryDirectory()`), not in `Library/Caches` where `path_provider`'s temporary folder is, so the importer's ownership check (rename, then delete) now looks in `Directory.systemTemp` on iOS; before, the picked file would have been copied and its original left behind. **Review fixes (Opus):** the extension carries the app's version (`CFBundleVersion`, `CFBundleShortVersionString`, from `ios/Flutter/ShareExtension.xcconfig`, which includes `Generated.xcconfig`; a signed install or upload needs both); a failure's message is shown on the sheet for 2 s before it closes ("This isn't a video.", "Status Studio isn't set up to receive videos.", the full-phone message), and the app is opened afterwards only when a `.failed` report was left for it; the report is written atomically; a staged copy's modification time is set to now, because a moved or cloned video keeps the date it was recorded and the one-day cleanup would otherwise delete a fresh share. **Pending, needs an iPhone and signing (§14):** the App Group needs the Apple Developer account (without it `containerURL` is nil and the extension reports "isn't set up to receive videos"); whether iOS lets the responder-chain call open the app (it did through iOS 17; later versions are why the fallback exists); sharing from Photos, Files and a trimming app. Tests not run. **New tests to write:** `ShareInbox`, `SharedIncoming.fileName` and `ShareDeliveries` (XCTest in `ios/RunnerTests/`, not written: the owner tests), and a Dart test that the importer treats `Directory.systemTemp` as owned on iOS only if the platform can be faked.
- [x] **4. AVFoundation renderer (Swift).** The same `status_studio/render` method channel and `status_studio/render/events` event channel, taking the same spec map from `render_spec.dart`; the Dart `Renderer` interface gets an iOS twin chosen by platform. A custom `AVVideoCompositing` with Core Image crops each frame, with the rect from the ported `MovingCrop.ndcRectAt` (glide and cut keyframes). It overlays each caption-line PNG and the logo when due, deleting the PNGs when the render ends, and encodes hardware H.264 and AAC through `AVAssetWriter`. Progress and cancel work as on Android. XCTest ports of `MovingCropTest.kt`. **Built (written and compiled, never run: no iPhone here and no tests by the owner's rule), with two departures from the text above, decided here: (1) no custom `AVVideoCompositing`.** The app already owns the read and write loop, so a plain `AVAssetReader` frame loop draws each frame with Core Image itself; a compositor would add a request and instruction lifecycle for nothing and its time would be the same frame time. The doc text in §5, §6.3.2 and here is corrected. **(2) No Dart twin class:** the two renderers speak one protocol, so `Media3Renderer` (its comment now says so) serves both; the platform choice is the native side's. Pipeline (`ios/Runner/Render/`): `RenderSpec.swift` parses the map as `RenderSpec.kt` does (same keys; `bad_spec` is answered at once for a bad map; an unreadable branding image or a video that can't be opened comes as an `error` event, where Android answers `bad_spec` for the branding image, and Dart handles both); `RenderJob.swift` cuts `clipStartMs…clipEndMs` into an `AVMutableComposition` (so every frame's time starts at zero and audio is trimmed exactly), reads the picture as 4:2:0 and the sound as 16-bit PCM at the source's rate (at most two channels), draws each frame with `FrameComposer`, and writes with `AVAssetWriter`: `.mp4`, H.264 High (rate: 0.12 bits a pixel at up to 30 frames a second, about 7.5 Mbit/s at 1080 × 1920), tagged Rec. 709, and AAC (64 kbit/s a channel); frames and audio run on their own queues; progress is sent at most every 250 ms from the frame time over the clip's length; a failure or cancel stops the reader and writer and deletes the partial file, and a cancel reports nothing (as on Android); `FrameComposer.swift` turns each decoded frame upright with the track's preferred transform (crops are measured on the displayed picture), then Crop and Moving crop scale the whole frame so the window fills the output and cut it to the output (edge pixels keep their real neighbours), Blur is a Gaussian blur at σ in source pixels stretched over the output with the sharp frame at the given share in the middle, and 16:9 fits the frame in the middle over black; the overlay is the line due at the frame's time or the branding, opened one image at a time (CLAUDE.md: Kotlin and Swift open each PNG when due, so Dart deletes them only when the render ends, which `Media3Renderer` already does). `MovingCrop.swift` is the port of `ndcRectAt` and `clipTimeMs` (and `pixelRect`, which replaces `glMatrixFor`). `RenderChannel.swift` is hooked in `AppDelegate`. `RunnerTests/MovingCropTests.swift` ports `MovingCropTest.kt` (the three matrix cases become `pixelRect` cases; added: the clip clock floors, and a cue's end is exclusive); it was type-checked with `swiftc`, **not run**. **Review fixes (Opus, before the last review was dropped at the owner's request):** a reader that fails (for example when iOS interrupts decoding) is no longer taken for the end of the clip, which would have delivered a truncated reel as done; the end of a job is decided once and every call into the reader and writer that could meet a cancelled one runs while holding the lock the ending needs (AVFoundation raises an Objective-C exception, which Swift can't catch, on a cancelled writer); the writer's blocks no longer hold the writer, and a finished job releases everything; each frame runs in an `autoreleasepool`; the AAC input is clamped to 16–48 kHz and one or two channels and takes its own bit rate below 32 kHz; a late report of a cancelled job no longer ends its successor; a frame drawn while the app was sent to the background is drawn again (Core Image would otherwise append black). These fixes were not reviewed again. **Not checked (needs an iPhone, §14):** everything about running it: that the writer accepts the composition's frames and audio, the encoder's settings, colour (a 10-bit HDR or HLG source is decoded to 8-bit 4:2:0 and is likely to look flat, §15), speed (Blur's blur runs on the full-size frame), the memory use with the previews' decoders still alive (FR-22), and that a Cut lands on the same frame as Android's. **Stale or new tests for the owner:** new XCTest for `RenderSpec(map:)` against the same maps as `RenderSpecTest.kt`. Tests not run.
- [x] **5. System channel.** `openAppSettings` in Swift (`UIApplication.openSettingsURLString`). Done: `ios/Runner/System/SystemChannel.swift` on `status_studio/system` answers `openAppSettings` (Settings' "Open Settings" and the reel actions' refused-gallery path already call it) and, for task 6, `beginBackgroundTask` and `endBackgroundTask`. Tests not run.
- [x] **6. Background work.** iOS has no foreground service: Groq work runs while the app is open and uses `beginBackgroundTask` for the short grace period. Script progress is saved per 90 s piece, so it resumes when the user comes back; the notification copy says so. `flutter_foreground_task` stays Android-only behind the existing background provider. Done as FR-16's iOS paragraph says: `IosBackgroundWorkPlatform` (`ios_background_work_platform.dart`; `show` and `stop` begin and end the background task, `postResult` and the permission calls use `flutter_local_notifications` with Darwin settings and no permission request at start-up, `runsUnrestricted` is true and `askToRunUnrestricted` does nothing), `SystemChannel.swift` (the expiration handler posts the native "Work paused" notification and ends the task), `ForegroundGate.swift` for the renderer, and the Settings section without the battery row on iOS. Not found in the code: a path that needed changes for resuming, because scripts already save per piece. Tests not run. **Stale or new tests for the owner:** `background_work_section` tests that expect both rows or "Open App info" under an iOS `defaultTargetPlatform` (the rows are the notification row only, the button reads "Open Settings"); new tests that `backgroundWorkPlatformProvider` can be overridden (it is chosen by `Platform.isIOS`, so a test overrides it).
- [x] **7. Docs and review.** §13, §14, §12 status, the CLAUDE.md iOS note; an Opus whole-branch review; fix findings; push (not merge). Done: §13 and §14 hold the M26 cases and checks, §15 the iOS render and background limits, §10 item 9 the build results and the M25 lessons below, CLAUDE.md the iOS note. Opus reviewed the commits of tasks 1–4 and their fixes' findings are in; at the owner's request (2026-11-10, "no review agent need from now on") tasks 5–7 and the whole branch were not reviewed. Pushed to `origin/m26-ios`, not merged. **Lessons from M25 on iOS:** (1) *The previews' decoders (FR-22):* the rule that Lyrics releases its player before Caption opens and Caption its preview before Export opens is platform-independent Dart and stays on for iOS; iOS also limits the hardware decoders a process may hold, and the export now needs one for the reader plus the encoder, so the same release is wanted. Not measured: §14. (2) *The body model:* `BodyModel` loads on first use and runs in its own `IsolateInterpreter`, all in Dart; on iOS `tflite_flutter` finds its library with `DynamicLibrary.process()` and the build exports `TfLiteModelCreate` and the rest from `Runner` (§10 item 9), so no change was made, and whether it loads and how long a frame takes on an iPhone is a §14 check. ML Kit faces on iOS take the same `InputImage.fromFilePath` of the JPEG frames. (3) *Preferences lost after a service ends:* the `shared_preferences_android` override is Android's own bug; iOS has no foreground-service engine, so it doesn't apply. (4) *Cut timing:* the 10 ms lead (`cutKeyframeLead`) is used as it is; a source whose first video timestamp is not 0 is not a problem for the iOS composition, which counts from the clip start.

### M27 tasks (branch `m27-store-readiness`)

Request, 2026-11-05: meet Google Play and App Store policy. With YouTube gone nothing downloads third-party media or runs code fetched at runtime, which was the blocker in both stores; what remains is policy hygiene. Branched from `dev` on 2026-11-10 (the owner's choice: `dev` already holds M26 and M28, so consent covers FR-29's path too), not stacked on `m26-ios`. Tests are the owner's; `fvm flutter analyze lib tool` only (plus the Kotlin compile and the iOS build where native code changes). One commit per task.

- [x] **1. Consent before the first Groq upload.** A one-time screen says the audio is sent to Groq, a third-party AI service, with the user's key, to write the lyrics; the user agrees or cancels. The answer is kept and Settings can withdraw it. (App Store guideline 5.1.2(i); Play User Data policy.) Done as FR-30: `GroqConsentStore` (shared preferences, only an agreement is kept) and `groqConsentProvider`; `GroqClient` takes a required `beforeUpload` that the app sets to the consent check, so no audio piece and no Fix request is sent without it; the pipeline checks it after the key and before cleaning; Processing opens the consent screen by itself and offers Continue, Fix with Groq and the Lyrics footer's Retry open it; Settings has the "Sending to Groq" row with Withdraw; §8 has the message. Also corrected in Settings: the Groq hint still said "when a video has no captions" and "the link", so it now reads as FR-12a's privacy note. `tool/voice_check.dart` passes a no-op `beforeUpload` (the owner's own audio). Tests not run. **New tests for the owner:** the "Store readiness (M27)" cases in §13; any test that builds a `GroqClient` now passes `beforeUpload`.
- [x] **2. Drop `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`** and its prompt (`background_work_platform.dart`); Play allows it only for listed uses. Keep `FOREGROUND_SERVICE_DATA_SYNC` (uploading to Groq) and write its Play Console justification in §9. Update FR-16 and the Settings rows. Done: the manifest removes the permission with `tools:node="remove"` (no plugin declares it today; this keeps it out if one starts to); `runsUnrestricted` and `askToRunUnrestricted` are gone from `BackgroundWorkPlatform` and both platforms (iOS's class keeps the rest unchanged); `BackgroundAccess.askOnce` asks for notifications only and `status()` became `notificationsEnabled()`; Settings shows the notification row, the Xiaomi hint and Open App info. FR-16 and §9 (two rows: battery optimisation, and the `dataSync` declaration text) updated. Tests not run. **Tests for the owner:** the new §13 background access case; any fake `BackgroundWorkPlatform` drops the two methods, and Settings tests that looked for "Battery optimisation" go.
- [x] **3. Privacy policy text in §9.** What is stored on the phone, that audio and the Fix with Groq lines go to Groq, the key in secure storage, no analytics. It needs a public URL; the repo is private, so the user chooses where to host it. Done: §9.1. Found on the way: "no analytics" is true of our code but not of the SDKs, because Google ML Kit sends anonymous usage and performance metrics with a per-installation ID; the policy says so and §4's privacy line is corrected. **Pending, the owner's:** where to host it, the effective date and the contact address, and then a Settings row that copies the URL (Play wants the policy reachable in the app).
- [x] **4. Store answers in §9.** Play Data safety (audio shared with a third party for app functionality, not collected by us, no account); the Apple App Privacy label; export compliance (HTTPS only, exempt); content rating. Done: §9.2. Two departures from the text above: by Play's definitions the audio is *collected* (it leaves the phone through the app), not shared (the user sends it, by their own action, to a service they chose), and ML Kit's metrics add Diagnostics, performance data and Device IDs to both forms. Added to the iOS project: `ios/Runner/PrivacyInfo.xcprivacy` in the Runner target (with the `xcodeproj` gem), which declares the disk-space and file-timestamp APIs `ShareInbox.swift` uses (App Store Connect rejects an upload without it), and `ITSAppUsesNonExemptEncryption` = NO in `ios/Runner/Info.plist`. `fvm flutter build ios --no-codesign` builds (`Runner.app` 132.9 MB) with the manifest in the bundle and the key in its Info.plist. Tests not run.
- [x] **5. Listing rules in §9.** No "YouTube" or "WhatsApp" in the name, description or screenshots, and neither brand's logo; screenshots use the user's own footage; "Status" alone is fine. Done: §9.3, with drafts of the subtitle, short and full description and keywords. Found: the Size step's preset hints name Reels, TikTok, Shorts, Instagram and Facebook; not changed (product copy, the owner's call), so that screen stays out of screenshots. `README.md` still describes the YouTube app; it is not a listing and was left.
- [x] **6. Release builds.** A signed Play App Bundle (`fvm flutter build appbundle`) and an iOS archive for TestFlight. Done here (2026-11-10), as far as this Mac allows:
  - **Play:** `fvm flutter build appbundle --release` builds `app-release.aab` (164.9 MB with all three ABIs; each phone downloads one), signed with the upload key from `android/key.properties` (verified, and not the debug key), version 0.1.0 (1), targetSdk 36. Every arm64 native library has 16 KB-aligned LOAD segments (`libflutter.so` and `libapp.so` 64 KB, the rest 16 KB, `libtensorflowlite_*` included), which settles §15's open question. **Merged-manifest permissions:** `INTERNET`, `ACCESS_NETWORK_STATE` (Media3), `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `WAKE_LOCK`, `POST_NOTIFICATIONS`, `VIBRATE` (notifications), `RECEIVE_BOOT_COMPLETED` (`flutter_foreground_task`'s boot receiver; it starts nothing, because auto-run on boot is off), `WRITE_EXTERNAL_STORAGE` up to Android 10, and the AndroidX dynamic-receiver permission. **Fixed:** `litert-gpu-api` (from `tflite_flutter`) declares no targetSdk, so the merger added `READ_PHONE_STATE` and `READ_EXTERNAL_STORAGE`, which Play treats as sensitive; the manifest now removes both (`tools:node="remove"`). `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` is gone (task 2).
  - **iOS:** `fvm flutter build ipa --no-codesign` builds `build/ios/archive/Runner.xcarchive` (289 MB). `ShareExtension.appex` is in `Runner.app/PlugIns`, bundle ID `com.hotmail.arehmananis.statusstudio.ShareExtension` (the app's ID plus a suffix, as required), with the app's version 0.1.0 (1); both entitlement files hold the same App Group `group.com.hotmail.arehmananis.statusstudio`, which `SharedIncoming.groupIdentifier` matches; deployment target 15.5 on both; the privacy manifest and `ITSAppUsesNonExemptEncryption` are in the app. **Fixed:** the ShareExtension target had no `DEVELOPMENT_TEAM` while Runner has one, so automatic signing would have stopped the archive ("requires a development team"); the extension now uses Runner's team (set with the `xcodeproj` gem).
  - **Not done, needs the Apple Developer account (§14):** the signed archive, the App ID and App Group registration, the provisioning profiles for both targets, and the TestFlight upload. Not attempted here and no credentials were asked for.
  - Each later upload needs a higher build number (`version:` in `pubspec.yaml`). Tests not run.

### M28 tasks (branch `m28-lyrics-optional`)

Request, 2026-11-10: "Make lyrics optional". The owner chose to skip lyrics entirely: no Groq, no Processing, no Lyrics step (FR-29). From `dev` (M25 merged). Tests are the owner's; `fvm flutter analyze` only.

- [x] **1. Without lyrics (FR-29).** `ReelDraft.lyricsSkipped` with `withoutLyrics()` and `withLyrics()`; a script run's lines are ignored while it is set. Source's "Make it without lyrics" (cancels a running script) and the shared video waiting for a choice; Fine-tune's "Next: caption" and step labels; Caption without the variant chips and with its own hint; Export's caption summary. Commit 2524fc7.
- [x] **2. Docs.** FR-29, FR-1, FR-24, §2, §12, §13, §14.
- [ ] **3. Tests (owner).** The §13 cases under "Without lyrics (M28)".

### M29 tasks (branch `m29-free-crop-on-player`)

Request, 2026-11-10: "Free crop size should be on video preview rather than separate section for fine-tune video screen." From `dev`. Tests are the owner's; `fvm flutter analyze lib` only.

- [x] **1. Free crop on the player (FR-6, FR-22).** `CropWindowOverlay` shows for Free crop even without room to move, is draggable while there are no keyframes, and gets a resize corner (`onResized`, key `free-crop-corner`). Fine-tune · Video turns a drag with no keyframes into the rectangle's left and top, keeps only the size while keyframes exist, and shows a hint with Reset under the size choices. `FreeCropEditor` (`free_crop_editor.dart`) is removed.
- [x] **2. Docs.** FR-6, FR-22, §12, §13, §14.
- [ ] **3. Tests (owner).** Stale: any test of `FreeCropEditor` or the `free-crop-area` key (the widget is gone; drag the `crop-window` key and the `free-crop-corner` key on the player instead). New: the §13 case "Free crop on the player (M29)".

### M30 design: the flow built around the moving crop and the lyrics (2026-11-10)

Request, 2026-11-10: "improve UI/UX. Move crop during scene change is [a] main feature along with auto AI lyrics." Agreed with the owner over mockups (not kept). Branch `m30-crop-and-lyrics-flow`, stacked on `m29-free-crop-on-player`. Tests are the owner's; `fvm flutter analyze` only. Items marked **(Claude's call)** were not discussed with the owner; the rest were.

**Why.** The two features that make the app worth using are scattered. On Fine-tune · Video, the "Move the crop during the clip" switch and Follow the person sit at the bottom of the scrolling list, while the keyframe chips sit under the player. The chips show only a start time, so how long the crop stays at each position must be worked out by hand. The chips don't scroll well, and the pinned player plus chips leave a small scrolling area. Lyrics are spread over Source (Get the script / Make it without lyrics, language), Processing, Fine-tune · Lyrics and Caption.

**Goals.**
- Everything about the moving crop is in one place, and each position shows how long it lasts.
- Everything about lyrics is on one screen: whether there are any, getting them from Groq, editing them, and how they look.
- Fewer screens: Processing and Caption go.

**Non-goals.** No change to how the crop is computed or rendered (FR-22 keyframes, §6.3), to the scene walk (FR-27), to Groq requests, voice cleaning or saved scripts (FR-3, FR-26, FR-14), to the render (FR-7a, FR-9) or to Home, Export and Done beyond their links.

**Anti-goals.** Anything uploaded without a tap on Get lyrics from Groq or Fix with Groq, or before consent (FR-30). Two video decoders alive when Export starts (FR-22 "One decoder at a time"). The crop's subject chosen for the user (FR-27).

**New flow.** Home → Source (choose the video) → Fine-tune · Video ("Step 1 of 2") → Fine-tune · Lyrics ("Step 2 of 2") → Export → Done.
- **Source:** the card, and one button, **Next: video**, which opens Fine-tune · Video with the clip as the whole video. "Get the script", "Make it without lyrics", the language dropdown and the Groq note go. A shared video shows its card and waits for Next, as now. Nothing is uploaded from Source. **(Claude's call:** a button rather than opening Video by itself, so the user sees the right video was picked.)
- **Processing** (`/processing`, `processing_screen.dart`) is removed. Its progress moves onto Lyrics. Background work (FR-16) and its notification stay.
- **Caption** (`/style`, `style_screen.dart`) is removed. Its position and size move into the Style sheet on Lyrics. Export's Cancel returns to Lyrics.

**Fine-tune · Video: Trim and Crop tabs.**
- The player stays pinned at the top. Under it there are two tabs, **Trim** and **Crop**, and only the tab's content scrolls. The bottom button is **Next: lyrics**.
- **Trim tab:** the clip summary, the waveform, the Start and End nudge cards and their hint, as today (FR-5).
- **Crop tab**, top to bottom:
  1. Size, fill and Keep in view (FR-6). With Free crop, its hint and Reset.
  2. The switch, renamed **Move the crop at each scene**, shown under the same rules as today (FR-22).
  3. **Scene strip** (switch on). One block per crop position across the clip, as wide as it lasts, labelled with its length ("5 s"). A position lasts from its keyframe's time to the next keyframe's time, or to the clip end. The strip covers the clip only and always fits the screen width, with no sideways scrolling. A block reached by Cut is marked as a cut. A white line follows the playhead. Tapping a block selects it and seeks there. The strip replaces `CropKeyframeChips`.
  4. **Selected position card:** "0:04–0:09 · 5 s", Arrives by Glide / Cut (hidden on the first), and Delete (off when only one is left).
  5. **New position here** and **Follow the person** side by side. Follow keeps its progress, its scene walk and its "Replace your crop keyframes?" question (FR-27).
- **Dragging the crop on the player** writes a keyframe as today (FR-22) and selects the block it lands in.
- **New position here (Claude's call):** adds a Glide keyframe at the playhead holding the crop where it is at that moment, then selects it, so the user drags it next. The playhead must be inside the clip. The 0.1 s snap and the 0.25 s replace rule apply, so a tap close to an existing position selects that position instead.
- **Keyframes outside the clip (Claude's call):** the strip draws only the clip. The position in force at the clip start is the first block, even when its keyframe sits before the clip. Keyframes after the clip end are not drawn. Deleting a block deletes the keyframe it shows.
- **Tab memory (Claude's call):** Trim opens first, and the tab last used is kept while the reel is open (not saved in the kept fine-tune).
- **Player height (Claude's call):** at most 260 dp and at most 40 % of the screen height, so the tab content keeps room on small phones. This applies to both Fine-tune players.

**Fine-tune · Lyrics: one screen.**
- The player is pinned at the top and shows the reel as it will look: the crop, the line due, the caption's position and size, and the branding (FR-8). The separate Caption preview goes. Below it, top to bottom:
  1. **Show lyrics on the clip**, a switch, on by default. Off: everything under it is hidden apart from the hint "Nothing leaves your phone and you need no key". The reel has no caption, only the branding, and no script is written or uploaded. This replaces FR-29's "Make it without lyrics". Turning it off while a script is being written stops the run, as FR-29 does today.
  2. **Before any lines:** a card with the Language dropdown (FR-2, default automatic), **Get lyrics from Groq** and the note "Sends the cleaned voice to Groq with your key." Get runs FR-3 as Processing does today: key check (§8 message with Settings when there is none), then consent (FR-30), then cleaning and writing. Under the card is **Type them myself**, which starts an empty line list. Add line works on it as FR-21 says, without a key and with nothing uploaded.
  3. **While writing:** the step and its percent ("Cleaning the voice", "Writing… 55 %"), time left once known, and Cancel, with lines appearing below as they arrive. The player stays usable. Errors show here with Retry, as the writing footer does today.
  4. **With lines:** a row of tools, **Aa Style**, **Fix with Groq** (FR-19), **Get again** and **Add line**, above today's line list (FR-21: tap to jump or time, edit, reorder, delete). A saved script (FR-14) opens straight into this state with "Using the saved script from <d MMM>".
- **Get again** asks for the language (Claude's call: a dialog with the dropdown and Get). When lines were edited it asks first, "Replace your edited lines?" with Replace and Keep **(Claude's call)**. It replaces today's "Write it again" and the language change that sent the user back to Processing.
- **Aa Style** opens a half-height bottom sheet, "Caption style", with **Position** (Top / Bottom) and **Size** (S / M / L), so the player stays visible above it. It is shown only when there are lines.
- **Bottom button: Export reel.** It releases this screen's player before Export opens (FR-22, one decoder at a time).

**Caption text: original only.** The Original / Roman / English choice goes. The caption is always the clip's lines as they appear in the list, so there is no separate caption text field. FR-29's typed caption is replaced by Type them myself. Remove on-device translation: the `google_mlkit_translation` dependency, `caption_translator.dart`, the language-pack downloads, the Roman Urdu transliteration (§6.6) and the caption-variant settings. Re-check §9.2 and `PrivacyInfo.xcprivacy` for the removed SDK, and check whether the iOS deployment target 15.5 is still needed (it was set for ML Kit translation; face detection may still need it).

**Kept fine-tune (FR-24, Claude's call).** Today a reel without lyrics is not kept, and a fine-tune always names a script. Since Video now comes before any script, a fine-tune is kept from the moment Fine-tune · Video opens, with or without a script. The draft gains the lyrics switch and an optional script reference (version 2; version-1 files still read). Recent's "Continue" opens Fine-tune · Video. When the draft names a script that is gone or changed, the clip and crop are kept and Lyrics shows the Get card, instead of sending the user to Processing.

**Groq still hears the whole video (Claude's call, against what was said in the conversation).** In the conversation Claude guessed that Groq would hear only the trimmed clip. The design keeps today's behaviour: the whole kept video is cleaned and written, and Lyrics lists only the clip's lines (FR-21). The video arrives already trimmed and the nudges move its ends by half seconds, so the upload saved is small. Keeping it means saved scripts, cleaned pieces and resume (FR-14, FR-26) work unchanged, and a nudge after the lyrics never needs a new script.

**Scripts, drafts and runs (Claude's calls, after a builder's review).**
- **One draft per video.** The draft becomes `transcripts/<videoId>/draft.json` (version 2), holding the requested language once one is chosen. When several version-1 `draft-<requested>.json` files exist for a video, the newest is read as the draft and the others are deleted. Recent shows a video's draft row in place of all its script rows.
- **Which lines Lyrics opens with:** the script the draft names. Otherwise the newest saved script of the video in any language (FR-14), with "Using the saved script from <d MMM>". Otherwise the Get card. Get, or Get again, in a language that already has a saved script opens that script without uploading (FR-3 rule 1). Write it again's forced rewrite stays available as Get again's "Write it again" in the dialog when a saved script exists.
- **The run belongs to the reel, not the screen.** Back from Lyrics to Video keeps it running, and Lyrics shows it again on return. Cancel on Lyrics, or the switch turned off, stops it. **Export reel is off while a script is being written**, with the hint "Wait for the lyrics, or Cancel", so a reel never goes out with half its lines. The FR-16 notification opens the app, and opens Fine-tune · Lyrics when the reel is still open.
- **Typed lines** (Type them myself, and any edit) are saved as today's `edited` script (FR-14, FR-21) under the language in the dropdown (default automatic). Get, or Get again, over typed or edited lines asks "Replace your edited lines?" first.
- **Switch off keeps the lines.** Turning Show lyrics off hides the lines and leaves them out of the reel, but keeps them, and turning it back on shows them again. A run still writing is stopped. (Today's `withoutLyrics()` drops them; that changes.)
- **Retention:** a draft with no script still lives in `transcripts/<videoId>/`, so the video follows the 90-day / 200-video rule like any scripted one, not the 7-day rule for imported-only sources (FR-14). That is intended: the user did work on it.

**Left to the builder.** Widget structure and file split; how the tabs are built (`TabBar` or segmented buttons); the strip's exact look (colours from `AppColors`, label format below about 1 s, how a very short block shows its length); naming of new providers; how the writing state moves from the Processing controller into a Lyrics section; the order of the tasks.

**Spec sections to update when built.** §1, §2 (screens 2, 3, 5, 5b, 6, 7), FR-1, FR-2, FR-3, FR-5, FR-7, FR-7a (Translation and Roman), FR-13, FR-14, FR-16, FR-21, FR-22 (switch name, chips → strip, "One decoder at a time", Height), FR-24, FR-26, FR-29, FR-30, §6.6, §8 (messages shown on Processing), §9.2, §13 and §14. Then CLAUDE.md's opening flow sentence. Tests made stale must be listed in the task text.

### M30 tasks (branch `m30-crop-and-lyrics-flow`)

Builds the M30 design above, task by task, one commit each. The repo has no `test/` folder yet, so no test goes stale; each task names the §13 cases the owner will want. Each task ends with `fvm flutter analyze` clean and a commit that says tests were not run.

- [x] **1. Video: Trim and Crop tabs with the scene strip (FR-5, FR-22).**
  - `CropPath.spansIn(ClipRange clip) → List<CropSpan>` in `crop_path.dart`. `CropSpan` holds `keyframeIndex`, `start`, `end` (video time, inside the clip) and `arrival`. The first span starts at the clip start and shows the keyframe in force there.
  - `ReelDraft.withCropPositionAt(Duration videoTime)`, which adds a Glide keyframe holding the anchor the path gives at that time, through `withCropAnchorAt`. Controller: `addCropPosition(Duration videoTime)`.
  - `fine_tune_screen.dart` keeps the pinned player and gets the two tabs. `fine_tune_trim_tab.dart` and `fine_tune_crop_tab.dart` hold their content. `scene_strip.dart` (`SceneStrip`) and `selected_position_card.dart` replace `crop_keyframe_chips.dart`, which is deleted. Follow the person sits beside New position here. The switch is renamed.
  - `clip_player.dart`: `_framedMaxHeight` becomes the smaller of 260 dp and 40 % of the screen height.
  - §13 cases: spans of a 3-keyframe path in a nudged clip; New position here at a keyframe's time selects it.
- [x] **2. Original captions only; translation removed (FR-7).** Done: the iOS target stays 15.5, because GoogleMLKit 9 (face detection) needs it too. `ios/Podfile.lock` still lists the translation pod until the next `pod install`. `PrivacyInfo.xcprivacy` declares nothing translation-specific. The §9.1–9.2 wording goes in task 6.
  - `CaptionVariant` goes from `CaptionSettings`. Its JSON field is ignored on read and no longer written (FR-24 files stay readable).
  - Deleted: `caption_translator.dart`, `roman_urdu.dart`, `translation_errors.dart`, the variant chips on Caption, and `google_mlkit_translation` in `pubspec.yaml`. Export's summary loses the variant names. Check `ios/Podfile`, `PrivacyInfo.xcprivacy` and §9.2 for the removed SDK, and record whether the iOS target 15.5 is still needed.
  - §13 cases: a version-1 draft with `"variant": "english"` still reads.
- [x] **3. One Lyrics screen (FR-21, FR-29, FR-30).** Done, with these differences from the list below (Claude's calls):
  - Add line stays at the end of the line list, where `ClipLinesList` handles its playhead rules, rather than in the tools row.
  - `scriptProgressProvider` is now `AsyncValue<ScriptProgress?>`: `null` means no run, and Cancel returns to it.
  - Get again in the same language writes the script again with Groq (it was Write it again); another language opens its saved script or writes one.
  - `script_tools.dart` became `lyrics_tools.dart`. `script_writing_footer.dart` is gone, because the run section shows its errors with Retry.
  - `ReelDraft.lyricsSkipped` becomes `lyricsShown` (default true). `withLyricsHidden()` keeps the lines and empties the caption text. `withLyricsShown()` refills it from the lines. `withTypedFirstLine(String text, Duration at)` makes a one-line transcript, 2 s from `at` and cut at the clip end, with `linesEdited` true. Controller: `hideLyrics()`, `showLyrics()`, `startTypedLyrics(String text, Duration at)`.
  - `script_run_section.dart` (`ScriptRunSection`) takes Processing's steps, amounts, §8 failure actions and the consent prompt, as a section on Lyrics. Back on its failures becomes Dismiss.
  - On `lyrics_screen.dart`: the switch; `lyrics_get_card.dart` (language, Get lyrics from Groq, Type them myself); `lyrics_tools.dart` (Aa Style, Fix with Groq, Get again, Add line) replacing `ScriptTools`' language row and saved-script banner; the Get again dialog; "Replace your edited lines?"; and Export reel, off while writing, releasing the player before Export.
  - `caption_style_sheet.dart` (`showCaptionStyleSheet`): Position and Size.
  - Lyrics opens on the newest saved script of the video in any language when the reel has none (`TranscriptStore.list()`, filtered by video).
  - `style_screen.dart` and `AppRoutes.style` are deleted.
  - §13 cases: hiding keeps lines and gives no cues; showing again restores them; a typed first line is 2 s and cut at the clip end.
- [x] **4. Flow: Source, Processing and Recent (FR-1, FR-3, FR-11, FR-16).** Done. The notification needed no change: it has no tap target of its own, so a tap returns to the screen the user left, which is Video or Lyrics while the reel is open. Source has no step label any more. A kept fine-tune whose script is gone opens Video without starting a run.
  - Source keeps the card and one button, Next: video (`setVideo`, push `fineTune`). The language dropdown, the two buttons and the Groq note go.
  - `processing_screen.dart` and `AppRoutes.processing` are deleted. Home's script row loads the script into the reel and opens Fine-tune · Video. "Script gone" opens Fine-tune · Video too.
  - `shared_video_listener.dart` loses the removed routes. The script notification opens Lyrics while the reel is open.
- [x] **5. One kept fine-tune per video (FR-24).** Done. The kept lines are `KeptLines` (`selection` and `fingerprint`), stored as `"lines"` in version 2. Saving a draft also writes the video's `video.json`, so a reel without a script still has a title in Recent. Continuing a fine-tune that never had lines starts no run. Long-press Delete removes the video's script only when the fine-tune had lines.
  - `FineTuneDraft` version 2 in `transcripts/<videoId>/draft.json`, with `videoId`, `language`, `lyricsShown`, `clip`, `frame`, `caption` and `linesEdited`. `selection` and `scriptFingerprint` are present only when there is a script.
  - `canKeep` needs only a video and a clip. Reading version 1: the newest `draft-*.json` of a video wins, and the others are deleted.
  - `FineTuneResumer`: a draft without a script is Ready with no transcript. Gone or changed keeps the clip and the crop as well.
  - Recent: a video's draft row replaces all its script rows.
  - §13 cases: v1 migration picks the newest; a no-script draft resumes with its clip and keyframes.
- [x] **6. Docs.** §1, §2, FR-1, FR-2, FR-5, FR-7, FR-7a, FR-9, FR-13, FR-14, FR-21, FR-22, FR-24, FR-26, FR-27, FR-29, FR-30, §4, §5, §6.6, §8, §9.1–9.2, §13 ("Crop and lyrics flow (M30)"), §14 (the same) and CLAUDE.md. Older milestones' §13 and §14 entries stay as history; the M30 entries say which they replace.
- [ ] **7. Tests (owner).** The §13 cases under "Crop and lyrics flow (M30)". Every test of `ProcessingScreen`, `StyleScreen`, `CropKeyframeChips`, `ScriptTools`, `ScriptWritingFooter`, `CaptionTranslator`, `romanizeUrdu`, `CaptionVariant`, `ReelDraft.withoutLyrics` and `lyricsSkipped`, and of `draft-<language>.json` as the current file name, is stale.

### M31 tasks (branch `m31-av1-to-h264`)

The bundled FFmpeg (`ffmpeg_kit_flutter_new_min`, built with no external libraries, `--disable-mediacodec` and `--disable-autodetect`) has no AV1 decoder: its own `av1` decoder only works through a hardware decoder, and it has none. An AV1 video then fails every FFmpeg run that decodes frames (Crop's frame sampling and scene detection, the Recent thumbnail) with "Your platform doesn't support hardware accelerated AV1 decoding" (found on the phone, 2026-11-10). The owner chose to convert such a video once, when it comes in, with the native renderer, over swapping to the larger `ffmpeg_kit_flutter_new_video` build or refusing the video. No `test/` folder exists, so no test goes stale; each task names the §13 cases the owner will want. Each task ends with `fvm flutter analyze` clean and a commit that says tests were not run.

- [x] **1. Import: convert an AV1 video (FR-1, §8).** Done. `_cardContent` takes the pending widget rather than a flag.
  - `LocalVideoFacts.videoCodec` (ffprobe's `codec_name` of the first video stream) and `needsH264Copy` (`av1`).
  - `VideoConverter` (`video_converter.dart`, `videoConverterProvider`): `convertToH264(inputPath, outputPath)` over `convert` on `status_studio/render`; a failure is `VideoNotConvertibleException`.
  - `LocalVideoImporter`: a video that needs it is converted into `sources/<videoId>/converting.mp4` (deleted first and on failure), renamed to `source.h264.mp4`, and the other kept files of the ID are deleted. A kept `source.h264.mp4` is reused without converting again. The free-space check asks for twice the incoming size plus 50 MiB. `importVideo` takes `onConverting`, called when a conversion starts.
  - Source's card shows "Converting this AV1 video so the app can edit it…" under its progress bar while that import converts.
  - §8 row and `errorMessageFor`: "This phone can't convert this AV1 video. Save it as H.264 (MP4) in your editor and share it again."
  - §13 cases: an AV1 probe needs a copy and an H.264 one doesn't; an AV1 import keeps `source.h264.mp4` and deletes the incoming file; a second import reuses it without converting; a failed conversion leaves no `converting.mp4` and throws `VideoNotConvertibleException`.
- [x] **2. Native `convert` (Android and iOS).** Done: the Kotlin compiles and `fvm flutter build ios --no-codesign --debug` builds; neither has run on a phone (§14). The iOS converter is a private enum in `RenderChannel.swift`, so the Xcode project needs no new file. Android: `VideoConverter.kt` beside `ReelRenderer`, Media3 Transformer with H.264 video and AAC audio and no effects; `RenderChannel` answers `convert` when it finishes, or `convert_failed`. Android's own AV1 decoder exists from Android 10; older phones fail with the §8 message. iOS: `AVAssetExportSession` with `AVAssetExportPresetHighestQuality` to MP4 in `RenderChannel.swift`; AVFoundation decodes AV1 only on A17 Pro and M3 chips or newer, so most iPhones get the §8 message.
- [x] **3. Docs.** FR-1, §4, §8, §10 item 7 (the AV1 answer), §13, §14 and CLAUDE.md.
- [ ] **4. Tests (owner).** The §13 cases of task 1.
- [x] **5. Conversion progress (asked 2026-11-10).** Done: the Kotlin compiles and the iOS app builds; not run on a phone. Native: the converter sends `{outputPath, value}` (0 to 1) every 250 ms on a new event channel, `status_studio/render/conversion` (Media3 `getProgress`; `AVAssetExportSession.progress` on iOS). Dart: `convertToH264` takes `onProgress` and listens on one shared broadcast stream, keeping only its own `outputPath`'s events. `importVideo`'s `onConverting` becomes `onConversionProgress(double fraction)`, called with 0 when a conversion starts. The Source card's bar fills and the text reads "Converting this AV1 video so the app can edit it… 42 %". §13 case: the importer passes the converter's fractions to `onConversionProgress`, starting at 0.

### M32 tasks (branch `m32-clear-scene-markers`)

Found on the phone (2026-11-10): the face and body boxes on the scene picture hid the person. The number badge sat inside each box's top-left corner and covered most of a small face, and the head of a body. The owner chose corners only, with the number in a tag outside the box, from four mockups (the others were a thin outline with the tag outside, numbers in chips under the picture, and hold to hide the markers).

- [x] **1. Corners and outside tags (FR-27).** `person_chooser_sheet.dart`: `_CornersPainter` draws the four corners; `_Tag` holds the number above the box (below it at the top edge, kept inside the picture's width) and picks its face or body on a tap, hidden from screen readers since the marker is the button. Tags are drawn after every box. FR-27 and §14 updated. `fvm flutter analyze` clean; tests not run.
- [ ] **2. Tests (owner).** §13: a tag sits above its box, and below it when the box touches the top; tapping a tag picks its face or body; the screen reader still finds "Person 1" and "Body 1" once each.

### M33 tasks (branch `m33-about-support`)

Asked by the owner (2026-11-10): an About section, and a Support section for feedback and complaints by email, WhatsApp or a call, with device details; the app version was not visible anywhere. The owner agreed the outline in chat; the calls left to Claude are listed in FR-31.

- [x] **1. Support and About in Settings (FR-31).** New feature folder `lib/src/features/about/`: `domain/support_message.dart` (topic, device details, the message text), `data/device_details_reader.dart` (`device_info_plus`, `package_info_plus`), `data/support_launcher.dart` (`url_launcher`; throws `ContactAppMissingException` when no app opens the link), `presentation/support_section.dart` and `presentation/about_section.dart`, added after Background work in `settings_screen.dart`. Android `<queries>` for `mailto`, `tel` and `https`; iOS needs no `LSApplicationQueriesSchemes` because `canLaunchUrl` isn't used. §9.1 and §9.2 updated for the new packages. `fvm flutter analyze` clean; tests not run.
- [x] **3. More device details (FR-31).** Asked by the owner the same day: screen resolution, RAM, processor and internet state. `DeviceDetails` gets `system`, `processor`, `memory` (`MemorySize`), `screen` (`ScreenSize`) and `network`; `deviceDetailsProvider` becomes `deviceDetailsReaderProvider` (`DeviceDetailsReader.read()`, fresh each message). The processor comes from a new `processorName` method on the Android `status_studio/system` channel (`MainActivity.kt`). Network from `connectivity_plus`, which needs `ACCESS_NETWORK_STATE`, already in the merged manifest for Media3 (M27 task 6), so no new permission. §9.1 and §9.2 updated. `fvm flutter analyze` clean; tests not run.
- [x] **4. One screen per Settings category (FR-31).** Asked by the owner the same day. `settings_screen.dart` is now the list; `settings_page.dart` shows one section under an app bar; routes `AppRoutes.groqSettings`, `backgroundSettings`, `supportSettings`, `aboutSettings` nest under `/settings`. `lyrics_tools.dart` and `script_run_section.dart` push the Groq key screen; `shared_video_listener.dart` counts the four as screens without a reel. `fvm flutter analyze` clean; tests not run. **Stale tests:** any that find "Background work", "Support" or "About" as section labels on Settings, or expect the no-key action to open `/settings`.
- [ ] **2. Tests (owner).** §13 "Support and About (M33)". No existing test goes stale (there are no Settings tests). Tests that pump `SettingsScreen` must override `appVersionProvider` and `deviceDetailsReaderProvider`, which read the platform.

### M34 tasks (branch `m34-large-text`)

Found by the owner on a phone set to large text (2026-11-10): app bar titles overflowed, and descriptions looked larger than their section titles. The owner chose to cap the growth.

- [x] **1. Cap, titles and hierarchy (§4).** `app.dart` clamps text scaling to `maxTextScale` (1.3). New `ScreenTitle` (`core/presentation/screen_title.dart`) on every app bar (Settings and its pages, Source, Fine-tune and Lyrics through `FlowAppBar`, the consent screen, Export, Done). `SectionLabel` goes from `titleSmall` (14) to `titleMedium` (16) semi-bold and gains `styleOf` for the Groq key heading; Home's "Recent" uses it. `AppTheme.dark()` sets `listTileTheme` (title `bodyMedium`, subtitle `bodySmall` muted). The bottom button bar (52 dp) and Home's 48 × 64 thumbnails stay fixed: at 1.3× their text fits. `fvm flutter analyze` clean; tests not run. **Stale tests:** golden or size checks on section labels, list rows or app bar titles, if any.
- [ ] **2. Tests (owner).** §13 "Large text (M34)".

### M35 tasks (branch `m35-theme-choice`)

Asked by the owner (2026-11-10): Light, Dark and System in Settings. The owner decided from mockups: everything goes light, the video areas too; light colours "one deeper green on a soft mint page"; a new Appearance category first in the list; System by default; the launch screen follows the phone's mode (FR-32, FR-20).

- [x] **1. Spec.** FR-32; FR-20 light phones; §2 Settings row; §7 logo colours; §13 "Theme choice (M35)"; §14.
- [x] **2. Colours from the theme (FR-32).** `app_theme.dart`: one palette value object per theme (the FR-32 table), `AppTheme.light()` and `AppTheme.dark()` built from it by one shared function, mapped onto the `ColorScheme` (primary = accent, onPrimary, surface = page, surfaceContainer = cards, onSurface = text, onSurfaceVariant = muted) and `listTileTheme`. Every widget reads colours from the theme instead of `AppColors`; painters (waveform, crop overlay) get them passed in from `build`. The fixed colours FR-32 lists (exported reel, logo, marks on the picture) move to their own constants that name what they are for, used only there. Built as an `AppPalette` `ThemeExtension` (read with `context.palette`, lerped so a theme change animates) plus `LogoColors`, `ReelColors` and `PictureMarkColors`; `AppColors` is gone. `tool/export_logo_test.dart` (the launcher icon generator) uses `LogoColors`. `app.dart` still sets the dark theme only, so the app looks unchanged after this task. `fvm flutter analyze` clean; tests not run. **Stale tests:** any that compare a widget's colour with an `AppColors` constant.
- [x] **3. Appearance setting (FR-32).** New feature folder `lib/src/features/appearance/`: the choice (Light, Dark, System, mapped to `ThemeMode`), a store on `preferencesProvider` (`appearance.theme`), a Riverpod controller that loads, applies and saves it, and `appearance_section.dart`. The saved choice is read in `main` before `runApp` and handed to the provider, so the first frame is right. `MaterialApp` gets `theme: light`, `darkTheme: dark`, `themeMode` from the controller. Settings gets the Appearance row first; route `AppRoutes.appearanceSettings` under `/settings`; `shared_video_listener.dart` counts it as a screen without a reel. Built as `ThemeChoice` (domain), `ThemeChoiceStore` (data), `themeChoiceProvider` seeded by `savedThemeChoiceProvider`, which `main` overrides with the value read before `runApp` (a read failure is reported and means System), and `AppearanceSection` (a `RadioGroup` of `RadioListTile`s). `fvm flutter analyze` clean; tests not run. **Stale tests:** tests that pump `StatusStudioApp` get System unless they override `savedThemeChoiceProvider`; tests of `AppearanceSection` must override `preferencesProvider`; any that expect four Settings rows.
- [x] **4. Launch follows the phone (FR-20).** Android: light `launch_background` (`#F5F8F6`) and light parent themes with `windowLightStatusBar` in `values/` and `values-v31/`, the dark ones moved to `values-night/` and `values-night-v31/`; the vector logo is unchanged. iOS: a `LaunchBackground` colour set in `Assets.xcassets` (Any `#F5F8F6`, Dark `#0E1311`) used by `LaunchScreen.storyboard`; `ShareViewController.swift` uses a dynamic colour with the same two values instead of the fixed dark one. `LaunchSplash` picks its background and wordmark colour from the phone's brightness (`MediaQuery.platformBrightnessOf`), not from the app theme. `fvm flutter analyze` clean; tests not run. `fvm flutter build apk --debug` builds; the storyboard compiles with `ibtool` and the Swift file parses, but iOS was not built. **Stale tests:** launch splash tests that expect the dark background (they get the light one unless they set `platformBrightness` to dark).
- [ ] **5. Tests (owner).** §13 "Theme choice (M35)".

### M36 tasks (branch `m36-remove-groq-fix`)

Asked by the owner (2026-11-10), after asking why the button exists: remove Fix with Groq. Lyrics are fixed by editing the lines (FR-21); the only upload left is the script audio.

- [x] **1. Spec.** FR-18 and FR-19 collapsed to history; FR-12a privacy note, FR-21 tools, FR-30 consent text and answers, §1, §2, §4, §8 (four rows gone, the consent row's Fix note), §9 (policy text, Play row for other user-generated content gone, Apple's Other User Content keeps Analytics only), §13, §14, §15 and `CLAUDE.md`.
- [x] **2. Remove the code.** Delete `groq_script_fix_service.dart` and `script_exchange.dart` (prompt, reply parsing, `NoScriptRowsException`, `TooManyLinesForAiException`, the row caps); `GroqClient.fixScript` and its model; `_GroqFixAction` and its helpers in `lyrics_tools.dart`; the two `errorMessageFor` cases; `ReelDraftController.correctTranscript` and `ReelDraft.withCorrectedLines` (nothing else used them); `GroqClient._replyTextOf`. Copy: the Groq key hint and the consent screen's "What is sent" point lose their Fix with Groq sentence. `ios/Runner/PrivacyInfo.xcprivacy` loses the Other User Content entry. Saved scripts with source `edited` stay readable (hand edits save that source too). `fvm flutter analyze` clean; tests not run. **Stale tests:** every test of `script_exchange.dart`, `GroqScriptFixService`, `GroqClient.fixScript`, Fix with Groq on Lyrics (including its consent path), and tests that find "Fix with Groq" among Lyrics' tools.
- [ ] **3. Tests (owner).** Delete the stale tests above; §13 has no new behaviour.

### M37–M40 design: caption looks, fade at the ends, undo on Lyrics, three known issues (2026-11-11)

Request, 2026-11-11: from Claude's feature suggestions the owner picked the fade at the ends, more caption looks, undo on Lyrics, and the §15 issues that feel like features. Agreed with the owner over mockups (scratchpad, not kept). Four milestones, one branch each, stacked from `dev`: `m37-caption-looks`, `m38-fade-ends`, `m39-lyrics-undo`, `m40-lyrics-fixes`. Tests are the owner's; `fvm flutter analyze` only. Items marked *Claude's call* were not asked; the owner can overturn them.

**Why.** Captions over a busy picture need a look other than the one grey box; clips trimmed elsewhere start and stop with a hard cut; and on Lyrics a slip (a delete, a mistimed tap) can't be taken back.

**Goals.**
- The caption can be shadowed text without a box, or a box, each in four colours.
- The picture can fade in from black and out to black.
- Every change to the lines on Lyrics can be undone and redone.
- Three §15 issues go: a clip over silence, dragging a line that doesn't scroll, edits lost to a script that finishes late.

**Non-goals.** No change to the sound (no audio fade), to the branding pill (FR-8), to caption timing (FR-7a), to Groq, or to the crop. No fade at scene cuts (tried and removed in M25). No text animation (§11).

**Anti-goals.** Caption text drawn anywhere but Flutter's text engine (it would break Nastaliq joining). A reel made before M37 that looks different when re-exported unchanged. Undo that jumps between unrelated settings.

**M37 Caption looks (FR-7).**
- **Style sheet:** Position and Size as today, then **Look** (Box / Shadow, a segmented button like the others), then **Colour**, a row of four swatches for the chosen look. Each swatch shows the look itself (a short sample of text over a picture-like background), with the chosen one outlined in the accent colour.
- **Box colours** (text on box): white on black, black on white, yellow on black, white on green.
- **Shadow colours** (text, no box): white, yellow, black with a light glow, gold.
- **Default:** Box, white on black at today's 38 %, so existing and new reels look as they do now until changed.
- **Remembered per look:** each look keeps its own colour, so Box → Shadow → Box comes back to the Box colour picked before.
- **Kept:** the look and both colours are saved with the kept fine-tune (FR-24); a draft saved before M37 reads as the default. A new reel starts from the look and colours used last (kept in preferences, *Claude's call*).
- **Shadow scales with the text** (offset and blur as a fraction of the font size), so S, M and L read the same.
- **Render:** the overlay painter (FR-7a) draws the chosen look into each cue PNG; Kotlin and Swift don't change. The Lyrics preview draws the same look.
- **Starting values** (*Claude's call*, to be judged on the phone): box opacities black 38 % (today), white 85 %, black under yellow 60 %, green `#0A5A3C` 85 %; yellow `#FFD84D`, gold `#F2C879`; shadow black at 90 % with a soft second shadow; glow white, blurred. They live as tokens in `app_theme.dart` (caption colours, not UI colours).

**M38 Fade at the ends (new FR-33).**
- **Fade switch** on Fine-tune · Video's Trim tab, under the nudge cards: "Fade in and out", off by default, saved with the kept fine-tune. New reels start with it off (not remembered from the last reel).
- **On:** the picture fades in from black over the clip's first 0.5 s and out to black over its last 0.5 s. A clip under 2 s fades over a quarter of its length at each end. The sound doesn't change.
- **Captions and branding fade with the picture:** the fade is applied after the overlay.
- **Render:** the render spec gets the fade length in milliseconds (0 when off). Android: a Media3 `RgbMatrix` effect after the overlay that scales colour by the fade factor at each frame's time. iOS: the same factor applied in `FrameComposer` after compositing. Both use the frame's own time from the clip start, as the moving crop does (§6.3.2).
- **Preview:** the Lyrics preview shows the fade (a black layer over the reel, its opacity from the playhead). The Trim tab's player doesn't, since it plays the raw video for trimming.

**M39 Undo on Lyrics (new FR-34).**
- **Top bar:** Undo and Redo icon buttons in Lyrics' app bar, greyed when there is nothing to undo or redo.
- **One step per action:** a saved text edit, Add line, Delete, a drag, and each tap-to-time. Typing in the edit field is one step when saved, not per letter.
- **Quick message:** after a Delete, "Line deleted", and after a tap-to-time, "Line timed", each with **Undo**, for about 4 s. Other actions show no message.
- **Up to 50 steps.** A new change after an undo clears Redo.
- **Saving:** an undo or redo is a change like any edit: the caption refills, the script saves as `edited` after 1 s (FR-21), and the kept fine-tune follows (FR-24).
- **Lifetime:** while Lyrics stays open, including Export and Cancel back. Cleared when Lyrics is left back to Video or Fine-tune closes; not kept for Continue later.
- **Not in the history:** the Show lyrics switch, the Style sheet, and Get again (it already asks "Replace your edited lines?" and its lines arrive over time). Get again's Replace clears the history.
- **Undo back to before the first edit** (*Claude's call*): the lines become unedited again, so they follow the written script as it is now, not the snapshot. A script still being written then keeps adding its lines (FR-21 "Script still being written").

**M40 Known issues (§15).**
- **Clip over silence:** when no line of the script overlaps the clip, Lyrics shows the tools and an empty list with the hint "No lines in this part of the video." and Add line, instead of selecting the whole script. The caption is empty, so the reel has only the branding until a line is added. Get again stays. (*Claude's call* on the hint; `linesInClip` returns `NoSelection` instead of the whole range, and `PickedScript` and the caption code must accept it.)
- **Dragging a line scrolls the screen:** the line list becomes part of the screen's own scrolling (Lyrics' `ListView` becomes a `CustomScrollView` with a sliver reorderable list, instead of a shrink-wrapped `ReorderableListView` inside the `ListView`), so a drag near the top or bottom edge scrolls and a line can be dropped on a row out of view.
- **Edits survive a script that finishes late:** when a run finishes after the user edited lines, the edited lines are saved again after the run's own save, so the `edited` script is the newest and the video reopens with the edits (FR-14, FR-21). Get again's Replace still lets the new script win.

**Left to the builder.** Widget structure and file names; the swatch's sample text and background; the exact undo snapshot (the picked script, the selection and the edited flag are enough); how the fade factor reaches `RgbMatrix` and Core Image; shadow offset and blur fractions; icon choice for Undo and Redo.

**Spec sections to update when built.** §2 (screens 5 and 5b), FR-5 (fade switch), FR-7 (look and colours), FR-9 (fade in the render), FR-21 (undo, silence, drag), FR-24 (what is kept), new FR-33 and FR-34, §6.1 types, §13 (new behaviour), §15 (the three issues and M18a/c removed).

### M37 tasks (branch `m37-caption-looks`)

Tests are the owner's; `fvm flutter analyze` only, and each commit says tests were not run.

- [x] **1. Spec.** FR-7 (Block, Look and colour), §6.1 types, §13 caption looks. Shadow layer sizes and opacities are Claude's call, written into FR-7.
- [x] **2. Model and keeping.** `caption_settings.dart`: `CaptionLook`, `BoxColours`, `ShadowColours`, `CaptionAppearance` (value object with `copyWith`, `==`), `CaptionSettings.appearance` (default `CaptionAppearance()`). `fine_tune_draft_json.dart`: write `look`, `boxColours`, `shadowColours` under `caption`; read them with the default for a missing or unknown name. `FineTuneDraft.startOver` keeps the appearance. New `features/style/data/caption_appearance_store.dart` (preferences keys as FR-7, the theme store's pattern) and `features/style/application/caption_appearance_memory.dart` (`savedCaptionAppearanceProvider`, overridden in `main.dart` like the theme; `CaptionAppearanceMemory` notifier with `remember`). `ReelDraftController.startNew` starts from the remembered appearance; `updateCaption` remembers a changed appearance. **New tests to write:** §13 caption looks, all but the drawing.
- [x] **3. Drawing.** New `features/style/domain/caption_ink.dart`: `CaptionInk captionInkFor(CaptionAppearance)` giving the box colour (none for Shadow), the text colour and `List<Shadow> shadowsAt(double fontSize)`; colours as `ReelColors` tokens in `app_theme.dart`. `captionTextStyle` takes the appearance; `overlay_painter.dart` and `ReelOverlayLayer` draw the box only for Box. Kotlin and Swift unchanged. **New tests to write:** §13 "Box draws its colour…; Shadow draws no box…" on `captionInkFor`.
- [x] **4. Style sheet.** `caption_style_sheet.dart`: Look (`OptionRow`, Box / Shadow) and Colour (four swatches drawn with `captionInkFor` over a gradient strip, the chosen one outlined in `palette.accent`, each with a semantic label such as "Yellow on black"). **New tests to write:** the sheet shows the chosen look's four colours, and a tap updates the draft.
- [x] **5. Status.** §12 status row; push `m37-caption-looks`.

### M38 tasks (branch `m38-fade-ends`, stacked on `m37-caption-looks`)

Tests are the owner's; `fvm flutter analyze` only (and the Android and iOS builds for the native parts), and each commit says tests were not run.

- [x] **1. Spec.** New FR-33, §6.1 note, §13 fade cases.
- [x] **2. Dart.** New `features/clip/domain/fade.dart`: `Duration fadeLengthFor(ClipRange clip)` and `double fadeBrightnessAt(Duration clipTime, Duration clipLength, Duration fadeLength)`. `ReelDraft.fadeEnds` (default false) with `withFadeEnds()` / `withoutFadeEnds()` and controller `fadeEnds()` / `stopFadingEnds()`; `FineTuneDraft` and its JSON carry `fadeEnds`; `RenderJob.fade` (`Duration.zero` when off) and `renderSpecFor` writes `fadeMs` only when it is above zero. Trim tab: the switch and hint. `ReelStage`: the black layer. **New tests to write:** §13 fade cases.
- [x] **3. Android.** `RenderSpec.fadeMs` (0 when absent); `fadeBrightnessAt` in Kotlin beside `clipTimeMs`; an `RgbMatrix` after the overlay when `fadeMs > 0`. `fvm flutter build apk --debug`.
- [x] **4. iOS.** `RenderSpec.fadeMs`; the same brightness function in Swift; `CIColorMatrix` after the overlay in `FrameComposer.render`. `fvm flutter build ios --no-codesign`.
- [x] **5. Status.** §12 status row; push.

### M39 tasks (branch `m39-lyrics-undo`, stacked on `m38-fade-ends`)

Tests are the owner's; `fvm flutter analyze` only, and each commit says tests were not run.

- [x] **1. Spec.** New FR-34, §13 undo cases.
- [x] **2. History.** New `features/transcript/domain/lines_history.dart`: `LinesSnapshot` (transcript, linesEdited) and `LinesHistory` (`recorded`, `undone`, `redone`, `canUndo`, `canRedo`, at most 50). `ReelDraft.linesSnapshot` and `withLinesRestored`; controller `restoreLines`. New `features/clip/application/lyrics_undo_controller.dart`: an auto-disposed `lyricsUndoProvider` (`applyEdit`, `undo`, `redo`, `clear`), which after an undo to unedited lines catches up with the run's latest transcript through `growTranscript`. **New tests to write:** §13 undo cases.
- [x] **3. Lyrics.** `FlowAppBar.actions`; Undo and Redo in Lyrics' app bar (watching the provider keeps it alive while Lyrics is open); `ClipLinesList` edits through `applyEdit`, hides the quick message on every edit and shows it after Delete and tap-to-time; Get and Get again clear the history; undo and redo save like an edit. **New tests to write:** the buttons' enabled state, the quick message and its Undo.
- [x] **4. Status.** §12 status row; push.

### M40 tasks (branch `m40-lyrics-fixes`, stacked on `m39-lyrics-undo`)

Tests are the owner's; `fvm flutter analyze` only, and each commit says tests were not run.

- [x] **1. Spec.** FR-21 (a script with no line inside the clip; Reorder scrolls; a late run keeps the edits), §13, §15 (Clip over silence and Fine-tune lines removed).
- [x] **2. Clip over silence.** `linesInClip` returns `LineSelection` (`NoSelection` when no line overlaps). `ReelDraft.withTypedFirstLine` becomes `withTypedLine`, which inserts into an existing script in time order (new `withLineInserted` in `line_edits.dart`) instead of replacing it. Lyrics: a script with lines and no run shows the tools, the hint and Add line (an undo step, through `LyricsUndoController.addLineToEmptyClip`). **Stale tests:** `lines_in_clip_test.dart`'s "every line when none overlaps". **New tests to write:** §13 Lyrics fixes, first two.
- [x] **3. Drag scrolls.** `ClipLinesList` builds slivers (`SliverReorderableList` with a proxy decorator, then Add line), and Lyrics' `ListView` becomes a `CustomScrollView`. **Stale tests:** finders that expect a `ReorderableListView`.
- [x] **4. Edits survive a late run.** `ScriptProgressController` saves the edited lines again when a written run (no `savedAt`) ends while `linesEdited`. **New tests to write:** §13 Lyrics fixes, third.
- [x] **5. Status.** §12 status row; push.

### M41 tasks (branch `m41-play-clip`, from `dev`)

Request (2026-11-12): Fine-tune · Video should play from where the seek bar was dragged and also from the clip start. The owner chose a second button on the video and stopping at the clip end. Tests are the owner's; `fvm flutter analyze` only, and each commit says tests were not run.

- [x] **1. Spec.** FR-5 (Play the clip), §13 Play the clip.
- [x] **2. Play the clip.** `ClipPlayer` gets a `_PlayClipButton` (shown only without `onlyRange`) and a `_playingClip` flag: the button seeks to the clip start in file time and plays; `_reportPlayhead` pauses at the clip end while the flag is set; Play, Pause and the seek bar clear it. **New tests to write:** §13 Play the clip. **Stale tests:** finders in `fine_tune_screen_test.dart` or `clip_player_test.dart` that expect one `IconButton` on the player.
- [x] **3. Status.** §12 status row; push.
- [x] **4. Late picture (owner's phone check, 2026-11-12).** Play the clip and the seek bar both jumped to 0:04 on a clip starting at 0:00.5: the video track starts at 3.979 s. FR-5 Late picture: `LocalVideoFacts.pictureStart`, `SourceVideo.pictureStart`, `ClipRange.nudgeStart`/`nudgeEnd` take `playable:` (a `ClipRange`) instead of `videoDuration:`, `ClipRange.startingNoEarlierThan`, `ReelDraft.withVideo` and `FineTuneDraft.restoredOnto` move the start up, Trim tab hint. **Stale tests:** callers of `nudgeStart`/`nudgeEnd` with `videoDuration:`, `LocalVideoFacts(...)` without `pictureStart`, `SourceVideo.toJson` expectations without `pictureStartMs`. **New tests to write:** §13 Play the clip, last seven.

### M42 tasks (branch `m42-freezed-models`, from `dev`)

Request (2026-11-12): move the models that are saved as JSON to `freezed` with generated `fromJson` and `toJson`. The saved shape must not change, or scripts, videos and the Recent list kept on the owner's phone would stop reading. Tests are the owner's; `fvm flutter analyze` only, and each commit says tests were not run.

- [x] **1. Spec.** §11 engineering rule and stack row, §12 row and these tasks.
- [x] **2. Set-up.** `freezed_annotation`, `json_annotation`; dev `freezed`, `json_serializable`, `build_runner`. `build.yaml` with `checked: true`. `analysis_options.yaml` excludes `**/*.g.dart` and `**/*.freezed.dart` and ignores `invalid_annotation_target` (`@JsonKey` on a freezed factory's parameters). New `core/json_converters.dart`: `MillisecondsConverter` (`Duration` as whole milliseconds) and `readWholeObject` (a `readValue` that hands a field the whole object, for fields saved flat).
- [x] **3. `SourceVideo`.** Freezed, generated `fromJson`/`toJson`; `pictureStart` `@Default(Duration.zero)`. **Stale tests:** `SourceVideo.fromJson` cases that expect a `FormatException` (now `CheckedFromJsonException`), and a non-int `pictureStartMs` that read as 0 (now throws).
- [x] **4. Scripts.** `PartialTranscript` fully generated (lines through a `TranscriptLine` converter). `SavedTranscript` freezed with `equal: false` (its `==` keeps `isAtSameMomentAs`, so a local `savedAt` equals the UTC one read back), generated `fromJson` and a hand-written flat `toJson`. `lineFromJson`/`lineToJson` become the private converter. **Stale tests:** cases that expect `FormatException` from these `fromJson`s or call `lineFromJson`/`lineToJson`; `PartialTranscript.lines` is now unmodifiable.
- [x] **5. `RecentReel`.** Freezed, generated `fromJson` (size read from `width` and `height`), hand-written flat `toJson`. `RecentReelsRepository` keeps a malformed entry as unreadable on `CheckedFromJsonException` too. **Stale tests:** `RecentReel.fromJson` cases expecting `TypeError`.
- [x] **6. Status.** §12 status row; push.

### M43–M47 design: a topic clip from a link, and F-Droid (2026-11-12)

Request, 2026-11-12: paste a video link and a topic; the app finds the moments about that topic, cuts them to a set length (60 s or any length), joins the cuts with a transition, and carries on into the crop and lyrics as today. Reference: ytdlnis (GPL Android front end for yt-dlp). Agreed with the owner in chat. Five milestones, one branch each, stacked from `dev`: `m43-off-the-stores`, `m44-link-in`, `m45-find-the-topic`, `m46-download-and-join`, then `m47-fdroid`. Tests are the owner's; `fvm flutter analyze` only. Items marked *Claude's call* were not asked; the owner can overturn them.

**Why.** The owner's source videos are long (talks, interviews, podcasts, often Urdu) and a status clip wants one topic out of them. Today they must find the moments, cut and join them in another app, then share the result in. This brings that work into the app.

**Decisions taken with the owner.**
- **Off the stores, onto F-Droid.** The Play Store and App Store plan is dropped. This reverses the 2026-11-05 pivot's distribution decision (§9 Distribution) and makes link downloads allowed again.
- **Open source.** youtubedl-android is GPL-3.0, and F-Droid lists only open-source apps, so the app becomes GPL-3.0 and the repo goes public. Before that, `android/key.properties` and `android/app/upload-keystore.jks` are removed from git history and kept by the owner outside the repo; release signing reads them from a path outside the repo (or environment variables), and CLAUDE.md's "private repo" rule is replaced.
- **IzzyOnDroid first, F-Droid next.** IzzyOnDroid takes the APK the owner builds and signs, so it carries M44–M46 as soon as they are done (GitHub releases alongside). F-Droid's main repository builds from source and rejects non-free code, which ML Kit is, so it comes in M47 after ML Kit is replaced. The yt-dlp updater is allowed there with the NonFreeNet anti-feature, as Seal has.
- **yt-dlp keeps itself working.** "Update downloader" in Settings plus a quiet check about once a week fetches the latest yt-dlp, as M7 did. The rule "no code fetched at runtime" goes.
- **Android only.** iOS keeps the local-video flow (FR-1) and shows no link input. With the App Store dropped, iOS is kept buildable (`fvm flutter build ios --no-codesign`) but is not distributed; it carries no yt-dlp code or wording.
- **Transitions:** a picker, default crossfade 0.3 s, on picture and sound.
- **Content can be Urdu** (and any language the app already handles): the topic can be typed in Urdu, English or Roman Urdu, and the matching is by meaning, not by words.

**Goals.**
- Paste or share a link, type a topic, pick a length, and get a reviewed list of cuts that add up to about that length.
- Download only the picked sections, never the whole video.
- Join the cuts with the chosen transition into one video that goes straight into Fine-tune · Video, where each cut is a scene for the crop (FR-27).

**Non-goals.** No search across several videos or a channel. No playlists. No music, stickers or text animation (§11). No auto-picked crop subject (FR-27 stays). No new caption or lyrics behaviour: Lyrics works on the joined video as on any other.

**Anti-goals.** Downloading the whole video when only sections are needed. A cut that starts or stops mid-word. Sending anything to Groq before the consent (FR-30). Picking the topic moments with no chance to review them before the download. A second FFmpeg build bundled by us for our own video work.

**M43 Off the stores (spec and rule changes, little code).**
- §1, §9 (Distribution, YouTube access, Data saving), §11, CLAUDE.md: the app is distributed as an APK; link downloads and a self-updating yt-dlp are allowed on Android; "no media downloads" and "no runtime-fetched code" become "downloads only from a link the user gave, and only yt-dlp updates itself".
- §9.1 privacy policy rewritten for the new sends (the topic and transcript text to Groq, FR-36) and the link downloads; §9.2 store answers and §9.3 listing rules marked historical (kept, not renumbered). `PrivacyInfo.xcprivacy` stays for the iOS build.
- FR-30 consent stays, and its screen text gains the transcript-and-topic send (FR-36). A user who agreed before M45 is asked again once, since what is sent changed (*Claude's call*).
- "Pending ideas": "Share from YouTube" is back (FR-35).

- **Going public (owner's steps, listed as a task):** rewrite history without the keystore and `key.properties` (`git filter-repo`), force-push, add `LICENSE` (GPL-3.0), make the repo public, and publish the first release on GitHub; then submit to IzzyOnDroid. Claude prepares the commands and the release notes; the owner runs the force-push and flips the repo public.

**M44 Link in (new FR-35, Android).**
- **Bring back M7 from git history** where it still fits: youtubedl-android and its Gradle and JNI packaging, `YtDlpChannel.kt`/`YtDlpCommands.kt`, `yt_dlp.dart`, `yt_dlp_info.dart`, `yt_dlp_updater.dart`, `youtube_link.dart`, the caption choice and json3 parser (removed in `a5294bf`). Read without JavaScript first, QuickJS only when no formats are found (§10 item 4).
- **Source screen:** under "Choose a video", a second card "From a link": a link field (pasted, or filled when a link is shared into the app from the YouTube app or a browser), then **Topic** (free text, any language), then **Length**: chips 15 s, 30 s, 60 s (default), 90 s, and Custom (any length from 5 s to 5 min, *Claude's call* on the bounds). Button: **Find the moments**. Hidden on iOS.
- **Video facts:** title, channel, length and thumbnail read by yt-dlp and shown on a card, as M7 did.
- **Links:** YouTube watch, short, `youtu.be` and Shorts links for certain; other sites yt-dlp supports are allowed but not promised (*Claude's call*).
- **Settings:** a "Downloader" screen in the list (FR-31): yt-dlp version, Update downloader, last checked. The weekly check runs at start-up, quietly, on Wi-Fi or mobile (*Claude's call*).
- **Share in:** a shared `text/plain` that holds a link opens Source with the link filled; a shared video still opens Source as today (FR-1).
- **Spike first (§10, new item):** pass conditions: today's yt-dlp in youtubedl-android still reads a YouTube video on the Redmi Note 11 (time recorded); a section downloads at exact times (yt-dlp's section download through its own FFmpeg, or M7's ranged downloader from the segment index); how often H.264 at or under 1080p is offered on five test videos; and the APK size with Python back.

**M45 Find the topic (new FR-36).**
- **Transcript of the whole video, cheapest first:**
  1. YouTube's captions in the video's language, uploaded first, auto-generated second (the M7 caption choice). Text only, nothing uploaded to Groq for this.
  2. If there are none: download the audio only, then clean and send it to Groq Whisper as the script pipeline does (FR-26, FR-12a), piece by piece, with its progress and per-piece resume (FR-14).
  - **Groq's free plan** (official rate-limits page, 2026-11-12; the key's own limits are on the console's Limits page): `whisper-large-v3` 7,200 audio seconds an hour and 28,800 a day, 20 requests a minute, 2,000 a day; `gpt-oss-120b` 8,000 tokens a minute, 200,000 a day, 1,000 requests a day. Captions cost no Groq audio.
  - **Length cap by source** (agreed 2026-11-12): up to 3 hours with YouTube captions, up to 2 hours without, so the audio fits one hour's allowance. Longer links are refused (§8 row). Without captions and over 1 hour, a note before starting says it takes a while and uses much of Groq's free daily audio.
  - **Wait, don't stop** (agreed 2026-11-12): when Groq answers that a limit is reached (HTTP 429), the run shows "Groq's free limit reached, continuing at 3:40" (the time from Groq's `retry-after`) with Cancel, and resumes on its own from the next piece. Pieces done stay saved (FR-14). The foreground service keeps it alive (FR-16).
  - Saved per YouTube video ID, so the same link with another topic doesn't fetch it again.
- **Picking the moments:** the transcript lines (with their times) and the topic go to a Groq chat model with the user's key. It returns ranges in the video's time, each with a one-line reason, that best fit the topic and add up to the length. The app then:
  - snaps each range out to the nearest line edges so no cut chops a word,
  - keeps them in video order,
  - drops overlaps and ranges under 2 s (*Claude's call*),
  - shortens or adds until the cuts' total is within ±10 % of the length. The transitions don't count against it: they play in the margins outside each cut (M46), so a 60 s target with four crossfades runs about 60.9 s (*Claude's call*).
- **Long transcripts in parts** (agreed 2026-11-12): a long transcript goes in parts sized to fit the tokens-a-minute limit. Each part returns its candidate moments with a score; one last call picks among them. Calls are paced to the limit, with progress "Reading the transcript, part 3 of 6". Rough size (*Claude's estimate*, to be measured): an hour of English talk is about 12,000 tokens and Urdu two to three times that, so one search on an hour of Urdu takes about 4–5 minutes and the free daily allowance covers about six.
- **Saved candidates:** each part's candidates are saved per video ID and topic, so Find again with the same topic sends nothing; only a new topic spends tokens.
- **Two models:** a small, fast model reads the parts and a large one makes the final pick, if the spike shows the small one finds the moments well enough; otherwise the large one does both.
- **Daily limit:** when the day's tokens or requests are used up, the §8 message "Groq's free daily limit is used up. Try again tomorrow, or use a key on Groq's paid plan." with Dismiss. The saved candidates stay.
- **Spike first (§10, new item):** which Groq chat model picks well for an Urdu talk with a topic typed in Urdu, English and Roman Urdu, including from YouTube's Hindi (Devanagari) auto captions (§10 item 10); whether a small model is good enough for the parts; the tokens an hour of Urdu and English transcript really takes; and the part size that fits the free plan. Pass when a person agrees the picked moments are about the topic on three test videos.
- **Review cuts screen** (new, `/source/cuts`):
  - One card per cut: thumbnail at its start, `1:02:13–1:02:31 · 18 s`, its transcript text, and the model's reason in small text.
  - On each card: Play (on first tap downloads that range at up to 480p with sound into the cache and plays it; YouTube rarely offers a combined stream to play directly, *Claude's call*), ±0.5 s on the start and end, Remove. Drag to reorder (*Claude's call*: allowed, video order by default).
  - **Add a moment:** opens the transcript with search, and a tap on a line adds it as a cut.
  - **Footer:** the total against the length (`58 s of 60 s`), the **Transition** picker, and **Make the clip**.
  - **Find again:** keeps the transcript, sends the topic again, and asks first if cuts were edited.
- **Transition picker** (on Review cuts, one transition for every join, *Claude's call*): **Cut**, **Crossfade** (default), **Fade through black**, **Slide** (the next cut pushes in from the right), each with a small looping preview tile. Length 0.3 s, fixed for now. Crossfade and Slide overlap the sound too; Fade through black dips the sound with the picture; Cut is a hard cut.
- **Errors (§8, new rows):** Groq's daily limit (above); a link over the length cap ("This video is too long. Links can be up to 3 hours with captions, or 2 hours without."); no topic found ("Couldn't find this topic in the video. Try other words or a longer video."); the link can't be read, even after updating yt-dlp (brings back the old "Couldn't read this video" row); a private, age-restricted or members-only video; no Groq key (the existing row).

**M46 Download and join (new FR-37).**
- **Download only the cuts**, each with a margin of the transition's length on both sides, at up to 1080p: H.264 when offered, otherwise the best stream at or under 1080p in any codec, with AV1 going through M31's convert (*Claude's call*), using yt-dlp's section download or the Dart ranged downloader from M7, whichever the M44 spike shows works with the bundled tools. Progress per cut, with speed and size, as M7 showed it; Cancel keeps the finished cuts.
- **Lyrics in the output language** (asked by the owner, 2026-11-12): the joined clip's Lyrics come in the output language picked on From a link. Groq writes the joined clip's script as today; when the output language differs from what was spoken, the lines are translated by Groq's chat model with the user's key, keeping their times. This brings translation back for link clips only (removed in M30); local videos stay original-language only.
  - **One language only** (agreed with the owner from mockups, 2026-11-12, M46 task 1): "get the script in the selected language and continue with it; no two languages". Groq writes what was said, then the lines are translated, and from then on only the translated lines exist: the list shows them, the caption draws them, and every FR-21 tool (tap to time, edit, reorder, add, delete, undo) works on them as on any lines. The spoken words are not shown or kept beside them.
  - **Font** (agreed, same day): unchanged, by script (§6.5): Nastaliq for every Arabic-script language (Urdu, Arabic, Persian, Punjabi in Shahmukhi), Inter otherwise. Naskh for Arabic and Persian, and a Font choice in Style, were shown and not chosen.
  - **When** (*Claude's call*): as the last step of Get lyrics from Groq on a link clip ("Translating into Urdu"), one chat call for the clip's lines (a joined clip is at most 5 minutes). Lines appear once translated, not while being written, so the spoken language never shows. When the written script's inferred language (§6.4) already is the output language, nothing is translated; Hindi-script lines for an Urdu output are translated (in effect written in Urdu script).
  - **Saved** (*Claude's call*): the translated script is the video's saved script (FR-14) under the output language, so reopening the clip shows it; the untranslated script is not kept. Get again writes and translates again. The Get card's Language dropdown is replaced on a link clip by "Lyrics in Urdu, chosen on From a link".
  - **Consent:** the lines' text goes to Groq with the user's key, after FR-30's consent (whose text already names transcript text since M45).
- **Join** in the native renderer (Media3 on Android) into one H.264/AAC file with the transitions, kept as `sources/<videoId>/source.mp4` with a fingerprint like any shared video (FR-1). It then opens Fine-tune · Video with the clip set to the whole joined video, and each join point marked as a scene for the crop (FR-27).
- **Join points as scenes** (*Claude's call*): the join times are saved with the source video and added to what `scdet` finds (a blend won't register as a cut). A join is always a scene edge: the 0.5 s merge rule never removes one. The crop's Cut keyframe sits at the middle of the transition.
- **Where the blend sits:** in the margins. The outgoing cut plays past its snapped end into its margin while the incoming cut starts in its margin before its snapped start, so no word inside a cut is faded. From there it is the normal flow: Trim, Crop, Lyrics (Groq on the joined video's audio, FR-21), Export.
- **One encode extra:** the join re-encodes once before the final export. Accepted for simplicity: the existing flow then works on one plain file. The join uses a high bitrate to keep the loss small (*Claude's call*).
- **FFmpeg:** youtubedl-android brings its own FFmpeg for yt-dlp's use only. Our own work (cleaning, thumbnails, frame sampling) stays on `ffmpeg_kit_flutter_new_min`. The "one FFmpeg" rule is reworded to say so (M43).
- **Recent:** a joined clip appears in Recent like any reel (FR-24), with the topic as its name, and reopens Fine-tune on the joined file. The link and topic are kept with it and shown; reopening Review cuts is not in scope (*Claude's call*).

**M47 F-Droid (main repository).**
- **Spike first (§10, new item):** run ML Kit and MediaPipe's BlazeFace full-range `.tflite` (Apache 2.0) on the same sampled frames of the reference clips on the Redmi Note 11. Pass when BlazeFace finds at least 95 % of the faces ML Kit finds (a face matched when boxes overlap by IoU ≥ 0.5) and takes no longer per frame than ML Kit's 102 ms (§10 item 7). Fail: F-Droid waits and IzzyOnDroid stays the channel; M47 stops there.
- **Swap the face detector:** `SubjectDetector` runs BlazeFace through TensorFlow Lite, the way the EfficientDet-Lite0 body detector already runs; `google_mlkit_face_detection` is removed, along with any Google Play Services class it pulled in. FR-23 to FR-27 behaviour doesn't change (faces down to 5 % of the frame, boxes only). iOS uses the same model (*Claude's call*: one detector on both platforms).
- **Build from source:** an F-Droid metadata file (`com.hotmail.arehmananis.statusstudio.yml`) for `fdroiddata`, Fastlane listing text and screenshots in the repo, and a check that F-Droid's build server accepts the prebuilt FFmpeg Kit and youtubedl-android binaries (if not: a build recipe for them, or the anti-feature F-Droid asks for). Anti-features expected: NonFreeNet (Groq, YouTube).
- **Submit** the merge request to `fdroiddata` (the owner's account).

**Left to the builder.** Widget structure and file names; the prompt and JSON shape for the chat model; how the transitions are drawn in Media3 (two overlapping sequences, a custom `GlEffect`, or a per-item effect); the preview tiles; the order of restoring M7 files; the exact error text beyond the rows above.

**Spec sections to update when built.** §1, §2 (Source, new Review cuts, Settings), FR-1, FR-23 (detector), new FR-35 to FR-37, FR-30 text, FR-31 (Downloader, licence GPL-3.0 in About), §5 package map and rules, §6.1 types, §8 rows, §9, §9.1–9.3, §10 (three new spike items), §11, §13 (new behaviour), CLAUDE.md (distribution, private repo and signing, runtime code, one-FFmpeg wording).

### M43 tasks (branch `m43-off-the-stores`, from `dev`)

Request (2026-11-12): the M43–M47 design above. M43 is the spec, rule and signing work that lets the repo go public under the GPL; no feature code. Tests are the owner's; `fvm flutter analyze` only, and each commit says tests were not run.

- [x] **1. Spec.** The M43–M47 design, the §12 rows and these tasks.
- [x] **2. Off the stores in the spec.** §1 (distribution, downloads, pivot note), §9 rows (Scope, Distribution, YouTube access, Data saving, Signing; new Licence row), §9.1 (hosting in the public repo, store wording out; the link and transcript sends are added by M44 and M45 when built), §9.2 and §9.3 marked historical, §11.
- [x] **3. CLAUDE.md.** Distribution, open source and public repo, signing outside the repo, yt-dlp allowed from M44, runtime updates of yt-dlp only, the one-FFmpeg wording (youtubedl-android's own FFmpeg serves yt-dlp only).
- [x] **4. Signing outside the repo.** `android/app/build.gradle.kts` reads `key.properties` from `STATUS_STUDIO_KEY_PROPERTIES`, else `~/.status-studio/key.properties`, else `android/key.properties` (now ignored); `storeFile` is relative to the properties file. Without any, release builds come out unsigned (never debug-signed), which F-Droid needs for its own signing. `android/key.properties` and `android/app/upload-keystore.jks` are untracked and ignored; the files stay on the owner's disk.
- [x] **5. Licence.** `LICENSE` with the GPL-3.0 text; About says "Free software under the GNU GPL, version 3. Source code: github.com/abdul-rehman-ghazi/status-studio" (FR-31). **Stale tests:** About finders that count its texts.
- [ ] **6. Going public (the owner's steps, not run by Claude).** (a) Back up `upload-keystore.jks` and `key.properties` somewhere safe outside the repo, such as a password manager: losing them means no update can ever install over the released app. (b) Move them to `~/.status-studio/` and fix `storeFile` there. (c) With every branch pushed, in a fresh mirror clone: `git clone --mirror https://github.com/abdul-rehman-ghazi/status-studio.git && cd status-studio.git && git filter-repo --invert-paths --path android/key.properties --path android/app/upload-keystore.jks && git push --force --mirror origin`. (d) Delete the old local clone and clone again (old clones still hold the files). (e) On GitHub: Settings → Change visibility → Public. (f) Publish the first release with the signed APK; then ask IzzyOnDroid to add the app.
- [x] **7. Status.** §12 status row; push.

### M44 tasks (branch `m44-link-in`, stacked on `m43-off-the-stores`)

Request (2026-11-12): FR-35, from the M43–M47 design. Tests are the owner's; `fvm flutter analyze` only, and each commit says tests were not run.

- [x] **1. Spec.** FR-35, §2 rows 2 and 9, §8 rows, these tasks.
- [x] **2. yt-dlp back on Android.** From `a5294bf^`: the `youtubedl-android` library 0.18.1 and the legacy JNI packaging in `build.gradle.kts`, `youtube/YtDlpChannel.kt` and `YtDlpCommands.kt`, registered in `MainActivity`; Dart `source/data/yt_dlp.dart` (`YtDlp`, `PlatformYtDlp`, `mapYtDlpError`), `VideoUnavailableException` and `YouTubeChangedException` in `source_errors.dart` with their §8 messages. **New tests to write:** `mapYtDlpError` cases (restore from `a5294bf^`).
- [x] **3. Reading a link.** `source/domain/youtube_link.dart` (restored), `source/domain/linked_video.dart` (`LinkedVideo`: video ID, title, channel, length, thumbnail URL, read from `-J` JSON), `source/application/linked_video_reader.dart` (quick, then QuickJS when the quick run fails with `YouTubeChangedException` or has no formats). **New tests to write:** link parsing (restore), `LinkedVideo.fromYtDlpJson`, the reader's fallback.
- [x] **4. Source screen, From a link.** Android only: the section, Paste, Read link, the card and its §8 messages. **Stale tests:** `source_screen_test.dart` finders that expect one button above the card.
- [x] **5. Share a link in.** `VideoInChannel` takes `text/plain` `SEND` and delivers `incomingLink {link}` (the first YouTube link in the text); manifest filter. Dart: `IncomingVideoSource.shares` emits `IncomingShare` (sealed: `IncomingVideo`, `IncomingLink`); `SharedVideoListener` opens Source with either; `SourceScreen.share`. **Stale tests:** everything using `IncomingVideoSource.videos`, `FakeIncomingVideoSource`, or `SourceScreen(sharedVideo:)`.
- [x] **6. Downloader in Settings and the weekly check.** `yt_dlp_updater.dart` (restored, plus last-checked read), the start-up hook in `main.dart` (Android only), `/settings/downloader` and its row. **New tests to write:** `updateIfDue` (restore), the Settings row shown on Android only.
- [x] **7. Desktop spike for M46.** With yt-dlp on the Mac: exact-time section downloads and how often H.264 ≤ 1080p is offered, on five videos; recorded in §10. The phone half (time on the Redmi, APK size) is the owner's.
- [x] **8. Status.** §12 status row; push.

### M45 tasks (branch `m45-find-the-topic`, stacked on `m44-link-in`)

Request (2026-11-12): FR-36, from the M43–M47 design. Tests are the owner's; `fvm flutter analyze` only, and each commit says tests were not run. The model spike (Urdu topics over Hindi captions, small model for parts, real token counts) needs a Groq key and is the owner's; the model is one constant.

- [x] **1. Spec.** FR-36, §8 rows, these tasks.
- [x] **2. Captions of a linked video.** `CaptionCue`, `linesFromCaptions` and `captionsFromJson3` restored (`a5294bf^`) as `transcript/domain/youtube_captions.dart`; `pickTopicCaptionUrl` (uploaded track, else `-orig` auto track, `json3`); `LinkedVideo.captionsUrl`; `YouTubeCaptionsFetcher` (Dart `HttpClient`). **New tests to write:** json3 parsing and line cleaning (restore), the track pick.
- [x] **3. Audio of a linked video for Groq.** Kotlin `downloadAudio(videoId, outputPath)` with progress events; Dart `LinkedAudioDownloader` into `sources/v_yt_<id>/source.m4a`; the script pipeline runs on `SourceVideo(videoId: 'v_yt_<id>')`. `isVideoId` accepts `v_yt_<11 chars>` too, or the start-up cleanup (M23) would delete these folders. **New tests to write:** the downloader's output path and its progress mapping; `isVideoId` and the start-up cleanup keep `v_yt_` folders.
- [x] **4. Groq chat and consent.** `GroqClient.chatJson` (POST `/chat/completions`, JSON reply, `beforeUpload` first); `GroqRateLimitedException` keeps its wait; consent stored under a new key so earlier agreements ask once more; the consent screen's text. **New tests to write:** `chatJson` request shape and consent check, consent asked again after M45.
- [x] **5. Finding moments (domain).** `topic/domain/`: blocks, parts, prompts, reply parsing, the fit to the length; `topic/data/topic_store.dart` (transcripts as blocks and candidates per YouTube ID; folders older than 90 days removed at start-up). Built: `transcript_block.dart` (blocks, parts), `moment_candidate.dart` (reply parsing), `topic_prompts.dart` (the model constant and prompts), `topic_cut.dart` (`fitToLength`: candidates trimmed from their end to 110 % first, so one long moment can still make a clip). **New tests to write:** blocks, parts by size, reply parsing (bad JSON, unknown block numbers), the fit (overlaps, 2 s, 90–110 %).
- [x] **6. Finding moments (application).** `TopicFinder`: caps, transcript route, parts with waits and resume, picking, saving; progress events. **New tests to write:** captions route, Groq route, caps, long waits, daily limit, saved candidates reused.
- [x] **7. Source and Review cuts.** Topic, length, Find the moments; `/source/cuts` with progress, cards, nudges, remove, reorder, Add a moment, total, the transition picker, Find again. Built: `topic_fields.dart` (topic, length chips, Custom dialog), `review_cuts_screen.dart` (progress with the Groq wait, failure with Find again or Settings, cards, reorder, Add a moment, footer), `cut_card.dart`, `add_moment_sheet.dart`, `transition_picker.dart` (looping previews), `clip_transition.dart`, `cut_edits.dart` (nudges that keep 2 s, the video and no overlap). Debug APK builds. **Stale tests:** Source finders (new fields after a read link). **New tests to write:** `nudgeCut`, `addBlockAsCut`, Review cuts states (finding, waiting, failure, cuts, Find again asks after edits).
- [x] **8. Status.** §12 status row; push.
- [x] **9. Model test (2026-11-12, owner's key).** §10 item 11: cross-script matching works; parts raised to 20,000 bytes; the prompt asks for moments up to half the clip and the fit trims to the room left. **New tests to write:** none left from this task (task 10 removed the fit).
- [x] **13. Output language (owner, 2026-11-12).** A drop-down on From a link (Urdu default); the part prompt asks for each moment's words and reason in it, so Review cuts shows them in that script (`ScriptText`); candidates saved per topic and language. Checked from the Mac: Urdu reason and Nastaliq words for a Hindi-script transcript, about 500 reply tokens a moment. Lyrics in the output language are written into the M46 design. **New tests to write:** `MomentCandidate.fromJson` without `text`, `TopicCut.fromCandidate` falls back to block text, the store keys by language.
- [x] **12. Phone check fixes (2026-11-12).** The search ran end to end on the Redmi (link, Roman Urdu topic, consent, Groq, moments with reasons). The footer took about 40 % of the screen and the transition labels wrapped, so the footer is one line with a Transition button opening a 2×2 sheet; the consent hint names links too.
- [x] **11. Link on its own screen (owner, 2026-11-12).** Home's two start cards (Android), `LinkScreen` at `/link` with the link section, Review cuts at `/link/cuts`, a shared link opens `/link`; Source is videos only again (`SourceScreen(sharedVideo:)`). **Stale tests:** Home finders for 'New reel' on Android, Source finders for the link section (gone), the listener's route for a link.
- [x] **10. Tick the moments (owner, 2026-11-12).** Review cuts shows every moment found, none ticked, with a checkbox; the ticked total may go over the length and says so; no picking call. `ReviewCut`, `toggleCut`, `tickedCuts`, `candidatesAsCuts`; the store keeps candidates only. **New tests to write:** `candidatesAsCuts` (overlap keeps the higher score, under 2 s dropped, video order), `toggleCut` refuses an overlap, `nudgeCut` lets an unticked cut overlap, `addBlockAsCut` adds ticked, the total line over the length.

### M46 tasks (branch `m46-download-and-join`, stacked on `m45-find-the-topic`)

Request (2026-11-12): FR-37, from the M43–M47 design and §10 item 10's revision (byte ranges from the DASH segment index, muxed by `ffmpeg_kit`; the phone's yt-dlp has no FFmpeg, so no `--download-sections`). Tests are the owner's; `fvm flutter analyze` only, and each commit says tests were not run.

- [x] **1. Design: translated lines (with the owner, mockups).** How the joined clip's lines in the output language are shown and edited on Lyrics, and which caption font they use. Recorded in the M43–M47 design under M46: one language only (the translated lines, edited as any lines), font by script as today (Nastaliq for Arabic script).
- [x] **2. Spec.** FR-37 (Make the clip, the download, the join, join points as scenes, Play on a card, Recent, lyrics in the output language), §2 row 2b, §6.1 types, §8 rows, these tasks.
- [x] **3. Streams and segment index.** Restored from `a5294bf^` into `join/`: `domain/segment_index.dart` (as it was), `data/ranged_downloader.dart` (now with `DownloadCancel` and bytes received, for speed and size), `domain/stream_choice.dart` (rewritten: MP4 only, H.264 first, then the best up to 1080p, else the lowest above; audio `m4a`, original track, regular before DRC, highest bitrate; 480p for Play), `domain/linked_formats_json.dart` (from M7's `yt_dlp_info.dart`), `data/linked_streams_reader.dart` (quick, then QuickJS when the quick run fails or has no MP4). No new Kotlin command: `-J` already lists the stream URLs. Checked from the Mac with yt-dlp 2026.11: range requests on `UTHXU2dOO6Y`'s 1080p H.264 and `m4a` streams answer 206, the `sidx` is in the first 64 KiB, and a cut muxed by stream copy starts at its first segment's keyframe (§10 item 10's revision holds). **New tests to write:** sidx parsing (restore `segment_index_test.dart`), `streamsForClip` (H.264 first, 1080p cap, AV1 when no H.264, lowest above the cap, no MP4 throws), `streamsForPreview` (480p), `pickAudioStream` (DRC last, dubs last), `linkedFormatsFromYtDlpJson` (HLS and combined formats left out), the reader's QuickJS fallback, the downloader's cancel and 403/200 mapping (restore `ranged_downloader_test.dart`).
- [x] **4. Download a cut.** `join/domain/cut_window.dart` (`downloadWindowFor`: the margin, none for Cut, clamped to the video), `join/domain/cut_file.dart` (`CutFile`: the file, its streams, the video time at its zero, the stretch both streams cover; JSON beside it), `join/data/cut_downloader.dart` (each stream's index from its head, the segments covering the window, init plus one merged range each, M7's `clipMuxArguments`; a kept cut from the same streams that covers the window is reused; the JSON is written last, so a cut with one is whole). Cut files are in `<cache>/cuts/<YouTube ID>/`. **New tests to write:** `downloadWindowFor` (margin, Cut, clamping at both ends), `CutFile` JSON round trip and `positionOf`, the downloader (kept cut reused, other streams not reused, no index or HTTP 200 becomes `NotDownloadableInPartsException`, the mux delays, bytes reported across both streams, the part files deleted).
- [x] **5. Join (Media3).** Dart `join/domain/join_plan.dart` (`planJoin`: the upper layer plays each cut with its tail, the lower each cut with its lead, both without gaps; a join's blend is the margin, shortened where a cut file ends sooner; windows and join times in the clip's time; no lower layer without a blend) and `join/data/clip_joiner.dart` (`join` on `status_studio/render`, progress on the conversion event channel by output path, `cancelJoin`). Kotlin `render/`: `JoinSpec.kt`, `JoinBlend.kt` (levels and volumes, pure), `VolumeEnvelope.kt` (an audio processor per item, counting frames from its clip start), `TransitionCompositor.kt` (the first sequence is drawn on top; Slide splits its move between the two anchors, which must stay within −1 to 1), `ClipJoiner.kt` (two sequences when blending, 5 bits a pixel a second; a cancel answers the waiting call). Compiles (`compileDebugKotlin`). The phone checks are the owner's: that Media3 draws sequence 0 on top as its compositor's code reads, the overlay settings' time is the clip's, and each item's audio processor starts counting at its clip start. **New tests to write (Kotlin):** `JoinSpec.fromMap` (bad keys, unknown transition, no cuts), `outgoingLevel`/`incomingLevel` per transition, `upperVolumeAt`/`lowerVolumeAt` (full before the tail, silent after the lead, item 0 silent), `TransitionWindow.progressAt`. **(Dart):** `planJoin` (three cuts with Crossfade: items, windows, join times at the middles, total = cuts + 0.6 s; Cut: no lower layer, join times at the cut edges; a first cut at 0 s shortens that join's blend; positions are in each file's time).
- [x] **6. Make the clip.** `join/application/clip_maker.dart` (`ClipMaker.make`: fresh streams, each ticked cut in list order with its window, one fresh read on a 403 and `YouTubeChangedException` if it expires again, `planJoin`, the join into `<cache>/joins/`, then `LocalVideoImporter.importVideo` with the topic as its name, which moves the file since the cache is the importer's own; `cancel` stops the download at its next chunk or the join at once), `join/domain/making_progress.dart`, `join/domain/linked_clip.dart` and `join/data/linked_clip_store.dart` (`sources/<videoId>/link.json`: YouTube ID, title, channel, topic, output language, transition, join times; `SourceCache.linkFile`), `join/presentation/making_view.dart` (the steps, size and speed, Cancel; the failure with Try again and Back, and "Finished cuts are kept." when offline). Review cuts: Make the clip on once a moment is ticked; while making, the footer and Find again are hidden; done, it sets the reel's video and opens Fine-tune. AV1 needs no separate convert: the join decodes it as M31's convert does, and a phone that can't gets `CutsNotDecodableException` (§8). **Stale tests:** Review cuts finders for "Coming in the next update" and the disabled Make the clip. **New tests to write:** the maker (steps in order, a 403 reads the streams once more, a second 403 is `YouTubeChangedException`, Cancel during the download and during the join, an AV1 join failure, the import's name and the link file), `LinkedClip` JSON, Review cuts (Make the clip off with nothing ticked; the making view; a failure's Try again and Back; Fine-tune opens with the joined video).
- [x] **7. Join points as crop scenes.** `SubjectTrack.joinCuts` (default none); `scenesOf` drops a found cut (scdet or a jump) within 0.5 s of a join, adds the joins, and measures a join only against the clip's ends; `FollowSubjectController` reads the joins from `link.json` by the video's ID. The Cut keyframe sits at the join less `cutKeyframeLead`, as for any cut. **Stale tests:** none expected (`joinCuts` defaults to none). **New tests to write:** a scdet cut 0.3 s from a join gives way to it; a join 0.6 s after another kept cut stays; a join within 0.5 s of the clip's start or end makes no scene; a video without `link.json` splits as before.
- [x] **8. Recent.** The import names the video after the topic (`<topic>.mp4` as its display name), so its script and fine-tune rows carry the topic, and they reopen Fine-tune on the joined file like any video (FR-24). Both rows start with "From a link · " when the video has a `link.json` (`linkedClipProvider`). **Stale tests:** Home row finders that match a subtitle exactly, when their fake video has a link file (none do today). **New tests to write:** a joined clip's fine-tune row shows the topic and "From a link · "; a local video's row doesn't.
- [x] **9. Play on a card.** `join/application/cut_previewer.dart` (`streamsForPreview`, read once and kept for an hour per video in memory; the moment's own stretch, no margin, through `CutDownloader`, so a played moment is reused; a 403 reads again once), `join/presentation/cut_player_sheet.dart` (plays from the moment's start in the file, stops at its end, seek bar over the moment only). `CutCard` has Play beside the times, a spinner while its moment downloads; one moment at a time; a failure says "Couldn't play this moment." in a snackbar. **Stale tests:** `CutCard` constructions (new `onPlay` and `preparingPlay`). **New tests to write:** the previewer (480p streams, kept streams reused within the hour, a 403 reads again), Review cuts (Play shows the spinner, then the sheet; a failure's snackbar).
- [x] **10. Lyrics in the output language.** `transcript/domain/lyrics_translation.dart` (`translationModel` = `topicModel`; instructions naming the script as the topic search does, `scriptNoteFor` made public; lines sent as JSON with IDs; `translatedLines` keeps times and turns line breaks into spaces; `LyricsNotTranslatedException`), `transcript/application/translating_script_pipeline.dart` (wraps the real pipeline in `scriptPipelineProvider`: for a video with `link.json` and a language other than Automatic, reopens the saved translation, else writes as spoken with Automatic, hides the lines, translates, saves under the output language as `groq-translated` and deletes the `auto` script), `ScriptStage.translating` and `ScriptProgress.translatesTo`, the run section's translating step, `LinkedLyricsGetCard` (the shared card body split out of `LyricsGetCard`). **Stale tests:** tests that list every `ScriptStage` or count the run section's steps; tests that read `scriptPipelineProvider` without overriding it now go through the translating pipeline (it passes local videos through but reads `linkedClipStoreProvider`). **New tests to write:** `translatedLines` (a missing or empty line throws, times kept, line breaks become spaces), `translationMessage` IDs; the pipeline (local video passes through; link clip in Automatic passes through; a saved translation reopens without Groq; writes, hides lines, translates, saves under the output language and deletes `auto`; no chat call when the inferred language is the target); Lyrics shows `LinkedLyricsGetCard` for a link clip.
- [ ] **11. Status.** §12 status row; push.

## 13. Behaviour that must stay covered by tests

- **Links (removed in M23):** the YouTube link tests went with the links.
- **Selection and nudges:**
  - (The tap-selection cases went in M23: there is no line picking.)
  - Nudges past either end of the video are ignored. A nudge that improves an invalid clip is applied.
  - A free-crop drag stays inside the frame.
  - Free crop on the player (M29): a drag on the window with no keyframes moves the rectangle (left = anchor x × (1 − width), top likewise) and writes no keyframe; the same drag with keyframes writes one; the corner resizes and keeps left and top while keyframes exist; Reset returns to the FR-6 default.
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
  - **Caption looks (FR-7, M37):**
    - The default appearance is Box, white on black at 38 %.
    - Box draws its colour behind the text; Shadow draws no box and gives the text two shadow layers sized from the font size.
    - Choosing Shadow and then Box again comes back to the Box colour picked before.
    - The appearance survives a kept fine-tune's JSON round trip; a file without it reads as the default.
    - A start-over keeps the appearance.
    - A new reel starts from the appearance saved in preferences; unknown or missing names read as the default.
  - **Fade at the ends (FR-33, M38):**
    - The fade is 0.5 s for a clip of 2 s or more and a quarter of the clip below that.
    - The brightness is 0 at the clip's start and end, 1 from the fade's length in, and in between rises and falls in a straight line.
    - The render spec has `fadeMs` only when the fade is on.
    - `fadeEnds` survives a kept fine-tune's JSON round trip; a file without it reads as off; a start-over keeps it.
    - A new reel starts with the fade off.
  - **Undo on Lyrics (FR-34, M39):**
    - An edit records the lines as they were; undo restores them and redo the edit.
    - An edit that changes no line records nothing.
    - The 51st step drops the oldest.
    - A new edit after an undo clears redo.
    - Undoing to before the first edit makes the lines unedited, and a script still being written adds its lines again.
    - Get again clears the history.
  - **Lyrics fixes (M40):**
    - A clip that no line overlaps selects no lines, and its caption is empty.
    - Add line on such a clip puts the line into the script in time order, inside the clip, and selects it.
    - A run that finishes after lines were edited saves the edited lines again after its own save; one reopened from the saved scripts does not.
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
  - After Back, answering the earlier scene asks the first scene still unanswered, not the next one; the answers already given are kept.
  - "Keep the centre" and a tap on the exact middle both give the anchor (0.5, 0.5) when there is room on both axes; an axis with no room keeps the base anchor.
  - Twelve scenes give 12 keyframes (the first at the clip start, eleven Cuts); a clip with more than 12 scenes asks the first 12, warns on the sheet, and the crop holds the 12th answer to the end.
  - When the cap drops keyframes, glides go before any Cut.
  - A scene's picture is its fullest frame (most people, then biggest faces, then earliest); only faces seen in at least 3 frames and 20 % of the scene are offered, at most 6, left to right; a scene with none still shows its earliest frame.
  - A body answer is resolved after the last answer: the detector looks at every other frame of that scene (the picture's boxes stand for its frame) and the chosen box's track is followed; faces and spots in other scenes are unaffected. With a detector that throws on bodies, no body is offered and the run still ends in the face and spot choices.
  - `trackOfBody` follows the box chosen in the picture through the scene's frames (a skipped frame has none), joins its other stretches, and throws when the box is not in the picture's sample.
  - A face followed in its scene joins the same person's other stretches in that scene (not seen in the same frame, same size and place); nothing joins across scenes.
  - A cut within 0.5 s of the previous cut, the clip start or the clip end makes no new scene, measured to where the Cut keyframe will be (10 ms before the cut; the clip's ends rounded inwards to 0.1 s: a clip starting at 12.34 s has its first keyframe at 12.4 s, so a cut at 12.84 s is too close).
  - A scene's Cut keyframe is at the cut time minus 10 ms, not on a tenth of a second: a cut at 3.086 s gives a keyframe at 3.076 s; the other keyframes still snap to 0.1 s (a glide that the spacing pushes to half a second after a Cut is rounded up to a tenth). Glides of the scene before that fall within 0.5 s of the Cut are dropped, so the Cut is always 0.5 s from the keyframe before it. Tapping a Cut chip puts the playhead on the cut itself (10 ms after the keyframe), so the picture and the crop shown are the new shot's.
  - The pin shows for about half a second after a spot tap, a second tap in that time answers nothing, and dismissing the sheet during it cancels the walk without popping again. An answer to a question that is no longer the current one is ignored.
- **Clip edges (FR-5):** tapping Start or End sets it to the playhead rounded to 0.1 s; a time that leaves under 3 s or passes the video's ends changes nothing.
- **Follow the person (FR-23):**
  - A steady face gives one keyframe. A face drifting left to right gives at most four keyframes, all glides, and ends near the right. Jitter of ±0.03 of the room gives one keyframe.
  - (Replaced by FR-27 in M25: no automatic pick; the user chooses the face.) Two faces: the larger is followed, and a larger one appearing beside the followed one doesn't take over.
  - A scene cut gives a Cut at the cut time; a jump of more than 0.3 of the room that the detector missed gives a Cut too, but not a second one beside a detected cut. (Replaced by FR-27 in M25: a cut right after the clip start moves the first keyframe; now it makes no scene.)
  - (Replaced by FR-27 in M25: only the first 12 scenes are asked, and the crop holds after them; see the "more than 12 scenes" case.) Sixty seconds with a cut every three seconds gives at most 12 keyframes and still reaches past 40 s.
  - A gap of one second holds the last anchor. With room on x only, y keeps the base anchor.
  - A clip of 90 s of busy movement gives at most 12 keyframes, at least 0.5 s apart, all inside the clip; a clip starting at 12.34 s gets its first keyframe at 12.4 s.
  - (Replaced by FR-27 in M25: a scene with no face offers a spot.) Faces in fewer than 20 % of the frames change nothing and give "No person found".
  - **Choose the person (FR-25; replaced by FR-27 in M25, kept as history):** two people together are offered, numbered left to right, at most 6; a face seen in under 3 frames or 20 % of its scene is not; the picture has the most people and then the biggest faces. The chosen smaller face is followed; another scene follows the face in the same place, or the FR-23 pick without one; the cuts are the same as without a choice. A tap within 24 dp chooses the nearest face; a far tap does nothing. Choose, Cancel, dismissing, leaving and a clip change all delete the frames; Cancel and dismissing change nothing; one person asks nothing.
  - The frame arguments use file time (the offset subtracted), the sampling rate falls for long clips and never below 2, and the cut parser reads FFmpeg's times.
  - Replace is asked only when more than one keyframe exists. Cancel, leaving, turning the move off, and a clip or size change stop the run, delete the frames and change nothing; a hand edit during the run wins. The detector is closed after every run.
  - A build without the scene filter is run again without it. The cuts file path is escaped for the filter graph. Until the first frame is looked at the bar is indeterminate.
- **One decoder at a time (M25 fix):** opening Caption releases Lyrics' player, and opening Export releases Caption's preview player (`ReelPreviewWithoutVideo` in its place); each is made again once the next screen has slid away; going back from Export (or from Done, which replaces it) restores Caption's preview; popping Caption restores Lyrics' player. A double tap on Next or Export opens one screen only, and Back pressed in the frame between the tap and the push opens nothing.
- **Moving crop (FR-22):**
  - A glide moves in a straight line and arrives at its keyframe's time; a cut holds the earlier anchor until then and has jumped at exactly that time. Dart and Kotlin share their boundary cases.
  - Before the first keyframe the first anchor holds, and after the last the last.
  - A new keyframe snaps to 0.1 s, replaces one within 0.25 s (keeping how it arrives) and is moved into the clip.
  - Any keyframe can be removed except the only one. Turning the switch off keeps the crop where it was at the clip start (the base anchor for Crop to fill, the rectangle for Free crop).
  - Keyframes go to the render spec as NDC rectangles with times from the clip start, in place of the fixed crop; Blur and 16:9 send none.
  - The switch is hidden without room to move. A drag writes one keyframe, at the playhead where it began. The first keyframe has no Glide or Cut. Keep in view is hidden while the crop moves.
  - The Video step's player is released while Lyrics is open and made again on Back.
  - Snapping never puts a keyframe outside the clip. A new script leaves the moving crop, the clip and its nudges alone.
  - A vertical video's player is at most 260 dp high. Chips and the crop outline show only while the crop can move, and the switch stays while keyframes exist. Free crop's outline always shows; its corner changes only the size while the crop moves.
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
- **AI script fix (M13) and Groq script fix (M15):** removed with the feature in M36.
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
  - The Continue row replaces the script row, and Delete removes both the fine-tune and the script (no script row is left).
  - Continue opens Fine-tune and Back shows Source or Home. With the script gone it opens Processing; with the script changed it opens Script with the snackbar. Both delete the draft and keep the frame (crop at the old start) and the caption's position and size.

- **iOS (M26):**
  - `RenderSpec(map:)` reads the same maps as `RenderSpecTest.kt`: a fixed crop, `cropKeyframes` (glide and cut), blur, none; a missing or wrong-typed key throws `RenderSpecError` naming the key; an unknown fill throws; ints and doubles from the channel both read as numbers.
  - `ndcRectAt`, `clipTimeMs`, `pixelRect` and `overlayPathAt` (`MovingCropTests.swift`, written, never run): the cases of `MovingCropTest.kt`, the clock floors to whole milliseconds, a cue's end is exclusive.
  - `SharedIncoming.fileName` keeps a short name, cuts a long one to 200 bytes without splitting a character and keeps the extension, and gives an empty name a default.
  - `ShareInbox.collect`: a finished share folder becomes a file in the staging folder named `<id>-<name>` with a `video/*` type and a fresh modification date; a `.part` folder and a hidden file are left alone; a `.failed` report becomes a failure with its code (and `copy_failed` when unreadable) and is deleted; stale entries older than a day are deleted in both folders.
  - `ShareDeliveries`: pushed while Dart listens, kept otherwise, `startListening` returns what was kept once.
  - The importer treats `Directory.systemTemp` as the picker's folder on iOS only (needs a fake platform).
  - `IosBackgroundWorkPlatform`: (`runsUnrestricted` and `askToRunUnrestricted` went in M27) `show` and `stop` call `beginBackgroundTask` and `endBackgroundTask` on `status_studio/system`; permission calls answer false when the plugin is missing. Settings on iOS shows the notification row and no battery row.

**Without lyrics (M28, FR-29; superseded by the M30 cases below where they differ):**
- `ReelDraft.withoutLyrics` drops the transcript, selection and caption text, keeps the clip, frame and caption position and size, and sets the clip to the whole video when there was none.
- With lyrics skipped, `withGrowingTranscript` changes nothing; `withLyrics` then lets the next script in and fills the caption from it.
- Source: Make it without lyrics is off until a video is chosen; it opens Fine-tune without starting a script and cancels a running one. A shared video starts no script.
- Fine-tune · Video without lyrics says "Step 2 of 3" and "Next: caption", and opens Caption; with lyrics it still opens Lyrics.
- Caption without lyrics hides the variant chips and shows the optional hint; Export's summary says "No caption" for an empty caption.

**Store readiness (M27):**
- `GroqConsentStore`: not given at first; `give` makes `isGiven` true; `withdraw` makes it false; `requireGiven` throws `NoGroqConsentException` unless given.
- `GroqClient.transcribe` and `fixScript` call `beforeUpload` before sending, and send nothing (the fake `HttpClient` sees no request) when it throws; `checkKey` doesn't call it.
- `RealScriptPipeline`: no key gives `NoGroqKeyException` even without consent; a key without consent gives `NoGroqConsentException` before any audio work (the fake `AudioPreparer` is not called); a saved script opens without consent.
- Withdrawing during a run: the next piece throws `NoGroqConsentException` and the pieces already written stay saved.
- Processing: a consent failure opens the consent screen once; Agree starts the run again; Not now shows the §8 message with Continue and Back.
- Settings: "Sending to Groq" reads "Allowed" with Withdraw after agreeing, and Withdraw turns it to "Not allowed: …".

- Background access: `askOnce` asks for notifications only, once; Settings shows the notification row and no battery row on Android too.

**Crop and lyrics flow (M30):**
- `CropPath.spansIn`: three keyframes at 1 s, 4 s and 9 s in a clip from 2 s to 12 s give spans 2–4 s (keyframe 0), 4–9 s (keyframe 1) and 9–12 s (keyframe 2); a keyframe at 13 s gets no span; one keyframe gives one span over the whole clip.
- `ReelDraft.withCropPositionAt` at a keyframe's time (within 0.25 s) keeps the keyframe count and its anchor; elsewhere it adds a Glide keyframe whose anchor equals the path's anchor at that time.
- `ReelDraftController.resizeFreeCrop` with keyframes changes only the width and height; without keyframes it takes the whole rectangle.
- `ReelDraft.withLyricsHidden` keeps the transcript and selection and gives no `captionCues`; `withLyricsShown` gives the cues back.
- With lyrics hidden, `withGrowingTranscript` changes nothing.
- `ReelDraft.withTypedFirstLine` at the playhead gives one line 2 s long, cut at the clip end, with `linesEdited` true; at the clip end it starts 1 s before it.
- `ScriptProgressController` starts as `AsyncData(null)`; `cancel` returns it to `AsyncData(null)`; `isScriptBeingWritten` is true while loading and while a progress is not done, false on an error.
- `fineTuneDraftFromJson` reads a version 1 file (with `selection`, `scriptFingerprint` and a `variant` in the caption) as lyrics shown with kept lines; a version 2 file without `lines` gives `lines == null`; version 3 throws `FormatException`.
- `FineTuneDraftStore.list`: a folder with `draft-ur.json` (older) and `draft-auto.json` (newer) gives the newer one and deletes the older; `save` writes `draft.json` and deletes both.
- `FineTuneDraft.canKeep` is true for a video and a clip without a transcript; `FineTuneResumer` gives `FineTuneReady` with no transcript and the kept keyframes for a draft without lines.
- `recentEntries` hides every script row of a video that has a kept fine-tune.
- Lyrics: with no lines and no run, the Get card shows; Get starts the run in the chosen language; with lines, Style and Get again show; Export reel is off while writing.
- Source: Next: video is off until a video is chosen and opens Fine-tune · Video without starting a script.

**AV1 to H.264 (M31):**
- `parseLocalVideoFacts` reads `codec_name`; `needsH264Copy` is true for `av1` and false for `h264`.
- An AV1 import calls the converter with the incoming file and `converting.mp4`, keeps `source.h264.mp4`, and deletes an owned incoming file.
- A second import of the same AV1 video reuses `source.h264.mp4` and doesn't call the converter or `onConverting`.
- A failed conversion throws `VideoNotConvertibleException` and leaves no `converting.mp4`; `errorMessageFor` gives the §8 copy.
- An H.264 import never calls the converter.
- An AV1 import passes the converter's fractions to `onConversionProgress`, starting at 0.

**Clear scene markers (M32):**
- A face box with room above gets its tag above it; one touching the top gets it below.
- Tapping a face's tag picks that face; tapping a body's tag picks that body.
- The screen reader finds "Person 1" and "Body 1" once each (the tags are hidden from it).

**Support and About (M33):**
- The message ends with the topic, the app version and build, then Phone, System, Processor, RAM, Screen and Network lines.
- RAM shows gigabytes with one decimal ("5.5 GB, 1.8 GB free"); the screen shows "1080 × 2400 px at 2.75×" and a whole ratio without decimals ("3×").
- Several connection types are joined by commas ("Wi-Fi, VPN"); no connection reads "None".
- Email and WhatsApp are off while the box is empty or only spaces; Call is always on.
- Email opens a `mailto:` link with the subject for the chosen topic and the message as the body, spaces encoded as `%20`, not `+`.
- WhatsApp opens `https://wa.me/923478330955` with the subject line and the message as `text`.
- Call opens `tel:+923478330955`.
- When no app opens the link, the snack bar names the address or number.
- About shows "Version <version> (<build>)" from the app's package details.
- Settings lists Groq key, Background work, Support and About; tapping a row opens its screen.
- The no-key Settings action on Lyrics opens the Groq key screen.

**Large text (M34):**
- At a system text scale of 2.0, text is drawn at most 1.3× its size.
- A long app bar title shrinks onto one line instead of wrapping.
- A section label's font is larger than a list row's title in the same theme.

**Theme choice (M35):**
- With nothing saved, the app follows the phone's mode (`ThemeMode.system`).
- A stored value the app doesn't know reads as System.
- Choosing Light saves `light` and the app's theme turns light without a restart.
- A saved choice is applied on the next start.
- Settings lists Appearance first, with "Theme: <choice>" as its subtitle; tapping it opens Appearance with the saved choice selected.
- The light and dark themes have the same text styles and sizes.
- The light theme's accent and muted text reach 4.5:1 against the page and the cards.
- The overlay PNG is identical whether the app is in Light or Dark.
- The reel preview's caption and branding colours are the same in Light and Dark.
- The launch splash's first frame uses the phone's brightness, not the saved choice.

**Play the clip (M41):**
- Fine-tune · Video shows a "Play the clip from its start" button; Lyrics doesn't.
- Tapping it seeks to the clip start and plays.
- Playing it pauses once the position reaches the clip end.
- Play after a pause starts where the bar is and doesn't pause at the clip end.
- A drag on the seek bar during clip playing stops it pausing at the clip end.
- A probe whose video stream starts at 3.979 s gives a picture start of 4.0 s; one with no `start_time`, or one starting with the file, gives 0.
- A picture start of 0.3 s stays 0.3 s (no floating-point round-up).
- A new video's clip starts at its picture start.
- A start nudge or set-to-playhead before the picture start changes nothing.
- The same video set again, or a kept clip restored, starting before the picture start, starts at it.
- `SourceVideo.fromJson` without `pictureStartMs` reads 0; `toJson` writes it.
- The Trim tab shows the late-picture hint only when the picture start is above 0.

## 14. Device checks (removed)

Removed on 2026-11-10: the owner does all device testing themselves and keeps the checklist outside this document. The number stays so references keep working; new milestones add no device checks here.

## 15. Known issues (found on the phone, not fixed)

- **iOS background work (M26):** iOS gives a script tens of seconds in the background and an export none (GPU work is refused in the background), so a long export needs the app in front; there is no ongoing progress notification. `ForegroundGate` waits on a state change, so an export interrupted by a phone call or a Control Centre pull-down also waits until the app is active again.
- **iOS render (M26, from reading the code, not from a phone):** an iPhone HDR clip (10-bit HLG or Dolby Vision) is read as 8-bit Rec. 709, so its colours can look flat; no tone mapping is done. The renderer was never run, so every item under §14's iOS section is open.
- **iOS launch image (found in M27):** `flutter build ipa` warns that the iOS launch image is still Flutter's placeholder, so iOS likely doesn't show FR-20's dark screen with the logo before Flutter starts. Not a store blocker; replace `LaunchImage` in `ios/Runner/Assets.xcassets` when iOS is next worked on. Since M35 the storyboard's background is the `LaunchBackground` colour set, light or dark with the phone (FR-20).
- (Removed in M23: there is no download; Processing's first step is "Preparing the audio".)
- The language list shows both "English (detected)" and "English".
- **Moving crop (M19):** (a) Style's preview shows the first caption line whatever the time. (b) (Gone in M23: the player holds the whole video, so a keyframe outside the clip can be shown.)
- **Preview timing (M25):** the Lyrics preview reads the crop from the playhead's estimated position (the platform reports about twice a second), so at a scene cut its crop can sit a few milliseconds off the picture while playing. The export reads each frame's own time and is exact (on the reference clip the detector's cut is the first new frame; a file whose first video timestamp is not 0 could still put FFmpeg's and Media3's clocks tens of milliseconds apart, which §14's frame-by-frame check would show). A fade at cuts was tried and removed at the owner's request.
- **Bodies (M25):** the detector's output was only judged by eye on 11 frames; false positives on a clip with no person were not measured; a release build's times and the GPU or NNAPI delegates were not tried; the model loads on first use (about 0.8 s, twice per run: once for the pictures, once for the body phase); `tflite_flutter`'s native library is 16 KB page aligned (checked in M27 task 6); the body anchor is provisional (§10 item 7).
- **Crowd shots (M25):** a shot with dozens of faces offers only the 6 biggest faces and the people the body detector finds (3 foreground people on the reference clip's crowd shots); a face in the crowd can't be chosen, but a spot can.
