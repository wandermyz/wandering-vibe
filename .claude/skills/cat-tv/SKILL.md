---
name: cat-tv
description: Opens a YouTube cat video in fullscreen for ambient viewing — like cat TV for your pet or a cozy background. Trigger this skill when the user invokes /cat-tv, asks to "put on cat TV", wants to play cat videos, or wants a relaxing YouTube video playing in the background. Keep the browser open and the video playing until the user explicitly asks to close or stop.
allowed-tools: Bash(playwright-cli:*), Bash(sleep:*), Bash(echo:*), Read
---

# Cat TV

Open YouTube, find a good cat TV video, go fullscreen, and keep it running until the user says stop.

## Step-by-step

### 1. Open Chrome in headed mode

```bash
playwright-cli open --headed --browser=chrome https://www.youtube.com
playwright-cli resize 1920 1080
```

### 2. Search for "cat tv"

```bash
playwright-cli snapshot
playwright-cli click <search-box-ref>
playwright-cli type "cat tv"
playwright-cli press Enter
```

### 3. Pick a non-sponsored video

After search results load, take a snapshot and find the first result that is NOT sponsored. Sponsored videos are marked with "Sponsored" label. Look for a video with a natural title like "Cat TV for Cats", "8 Hours of Cat TV", "Birds and Squirrels for Cats" etc. Click it.

```bash
playwright-cli snapshot
playwright-cli click <first-non-sponsored-video-ref>
```

### 4. Handle ads — wait and skip

Wait for the page to load, then check for ads:

```bash
sleep 3
playwright-cli eval "document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button') ? 'skip available' : (document.querySelector('.ytp-ad-player-overlay') ? 'ad playing - not skippable yet' : 'no ad')"
```

- If an ad is playing but not yet skippable, wait a few seconds and check again with a snapshot.
- When the skip button appears in the snapshot, click it by ref.
- Repeat until no more ads.

### 5. Close the Live Chat sidebar (if present)

Live streams often show a chat panel overlaying the video. Check and close it:

```bash
playwright-cli eval "document.querySelector('ytd-live-chat-frame, #chat-container') ? 'chat visible' : 'no chat'"
```

If visible, take a snapshot and find the "Close" button inside the chat iframe (ref like `f11eXX`) and click it.

### 6. Enter fullscreen

Use AppleScript to make the Chrome window go OS-level fullscreen (requires iTerm to have Accessibility access in System Settings → Privacy & Security → Accessibility), then press `f` to make the YouTube player fill it:

```bash
osascript -e 'tell application "System Events" to tell process "Google Chrome" to set value of attribute "AXFullScreen" of window 1 to true'
sleep 1
playwright-cli eval "document.querySelector('.html5-video-player')?.click()"
playwright-cli press f
```

Verify YouTube fullscreen:
```bash
playwright-cli eval "document.fullscreenElement ? 'youtube-fullscreen: yes' : 'youtube-fullscreen: no'"
```

### 7. Verify video is playing

```bash
playwright-cli eval "document.querySelector('video').paused ? 'paused' : 'playing'"
```

If paused, press `k` to play:
```bash
playwright-cli press k
```

### 8. Take a screenshot and share video URL

Once playing, take a screenshot and save it as an attachment:

```bash
playwright-cli screenshot --filename=~/.yuki-conductor/workspace/attachments/YYYY-MM-DD-cat-tv.png
```

(Replace `YYYY-MM-DD` with today's date.)

Get the video URL:
```bash
playwright-cli eval "window.location.href"
```

In your response to the user, include:
1. The attachment tag on its own line (not in a code block):

<attachment>YYYY-MM-DD-cat-tv.png</attachment>

2. The video URL as a markdown link, e.g.: [Watch on YouTube](https://www.youtube.com/watch?v=...)

### 9. Wait for user to say stop

Tell the user cat TV is playing, show the screenshot and link, and wait. Do NOT close the browser until the user explicitly asks.

### 10. When user asks to stop

```bash
playwright-cli close
```

## Notes

- Always use `--headed --browser=chrome` — never headless
- Use AppleScript (`AXFullScreen`) for OS-level Chrome fullscreen, then `f` for YouTube player fullscreen — both are needed. Requires iTerm to have Accessibility access granted in System Settings → Privacy & Security → Accessibility
- The snapshot is the most reliable way to find the Skip button ref — don't guess the selector
- Live streams (24/7 cat TV channels) usually have pre-roll ads but no mid-roll ads
- Close the Live Chat sidebar on live streams — it covers part of the video
- Screenshot goes to `~/.yuki-conductor/workspace/attachments/` — make sure that directory exists (`mkdir -p ~/.yuki-conductor/workspace/attachments`)
