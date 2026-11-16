# Status Studio privacy policy

Effective 16 November 2026.

Status Studio turns a video you choose into a short clip with lyrics. It has no server and no accounts. We, the developer, receive none of your data.

**What stays on your phone.**
- The videos you share into the app or pick, copied into the app's own storage. A copy nothing uses any more is deleted: after 7 days when it has no script, fine-tune or reel, and otherwise after 90 days unused.
- The scripts (lyrics) written for your videos, kept until you delete the video in History, so another clip from the same video doesn't need its script written again.
- From a video link (Android): the parts of the video you keep, and its script. The sound downloaded to write the script is deleted once the script is saved.
- Unfinished work, so you can carry on later. The clips you export. Your settings, including whether you agreed to send to Groq, and a count of how much sound you sent to Groq in the last day, to show how much of Groq's free allowance is left.
- Finding faces and bodies for the crop, cleaning the voice and making the clip all happen on your phone.
- If you add a Groq API key, it is kept in the phone's secure storage (Android Keystore or iOS Keychain) and is sent only to Groq, to authorise your own requests.

You can delete videos, scripts and clips in the app's History, and uninstalling the app deletes all of it.

**What leaves your phone, and only when you ask.**
- *Groq.* Status Studio sends to Groq, an AI service run by Groq, Inc., using your own Groq key, and only after you agree once on its "Send to Groq?" screen:
  - to write lyrics or a linked video's script: the video's sound, cleaned to one channel, in pieces;
  - to update a moment's words, or to translate a linked clip's lyrics into the language you chose: the words of the script involved.

  The picture is never sent. Groq handles this under its own terms and privacy policy (groq.com), as the service you signed up for when you made your key. You can withdraw your agreement in Settings at any time, and nothing more is sent after that. A clip made from your own video without lyrics sends nothing.
- *Video links (Android).* When you paste or share a link, the app uses yt-dlp to read the video's details from the site that hosts it (YouTube, for example) and downloads only what it needs: the sound, to write the script, and the parts you keep. The site sees these requests as it would if you watched the video there, including your IP address, and its own privacy policy applies. Nothing else about you is sent.
- *Downloader updates (Android).* yt-dlp, which reads links, updates itself from GitHub about once a week and when you tap Update downloader in Settings (builds from F-Droid update only when you tap it). GitHub sees the request, including your IP address; nothing else is sent.
- *Saving and sharing.* Save puts the clip in your photo library. Share hands it to the app you choose in your phone's share sheet.
- *Support.* If you write to us from Settings, the app opens your own email or WhatsApp app with your message, your phone's model, system version, processor, memory, screen size and connection type (such as Wi-Fi), and the app's version filled in. You see it before you send it, and we receive only what you send. Calling us from Settings opens your phone app. Nothing is sent by Status Studio itself.

**What we don't do.** No advertising, no analytics, no tracking, no selling or sharing of your data, no accounts. The app contains no Google Play Services, Firebase or other analytics libraries.

**Permissions.** Internet, for Groq, video links and downloader updates. Network state, to name the connection type in a support message. Notifications, to tell you when work is done, and on Android a foreground service and a wake lock, so writing scripts, downloading and exporting carry on when you leave the app or the screen turns off. Adding to the photo library, to save clips (storage access on Android 10 and older). Two Android permissions come with the notification library and are not used by the app: starting at boot and vibrating.

**Children.** Status Studio is not directed at children under 13.

**Changes.** A new version of this policy will be posted at this address with a new date.

**Contact.** arehmananis@hotmail.com
