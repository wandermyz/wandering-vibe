# Meow Detector Daemon

**Date:** 2026-05-06
**Status:** Planning

## Overview

Always-on daemon running on the home Mac mini that listens to a USB/built-in microphone, detects cat meow sounds with YAMNet, and posts a notification to Slack. Intended to run **while nobody is home**, so the acoustic environment is assumed to be quiet (no human speech, no TV).

Use case: know when Siggraph is meowing/distressed while we're out.

## Goals

- Detect cat meows (and ideally hisses / caterwauls as escalation signals) from a live mic stream.
- Post Slack notifications with timestamp and confidence.
- Run as a `launchd` agent on macOS — autostart on login, auto-restart on crash.
- Low idle CPU / power footprint (24/7 service).

## Non-goals

- Interpreting meow meaning (food vs. attention vs. pain).
- Multi-cat identification.
- Storing or streaming audio (privacy; only ephemeral buffers).
- Mobile push (Slack already pushes to phone).

## Architecture

```
mic ─▶ ring buffer (device rate, mono)
         │
         ▼
   resample to 16 kHz
         │
         ▼
   VAD / RMS gate ──(silent)──▶ skip
         │
   (sound present)
         ▼
   tanh soft-clip @ +20 dB gain  (compensates for distant source)
         │
         ▼
   YAMNet inference (1 s window)
         │
         ▼
   detection logic: max(Meow, Cat, Caterwaul) >= T,
   N consecutive windows, then cooldown
         │
         ▼
   Slack chat.postMessage + audio snippet
```

### Components

1. **Audio capture** — `sounddevice` (PortAudio), capture at the device's native sample rate (PortAudio on macOS doesn't reliably resample for built-in mics), mono float32, ring buffer.
2. **Resampler** — `scipy.signal.resample_poly` to 16 kHz in the consumer thread. Kept out of the audio callback so the callback stays RT-safe.
3. **VAD gate** — RMS threshold first; optionally `webrtcvad` later. Skips inference on silence so the daemon idles near 0 % CPU.
4. **Boost (`enhance.py`)** — `tanh(wav * 10)` (≈ +20 dB with soft-clip). Necessary because real-world recordings of distant meows hit YAMNet at -50 dBFS, where Cat-class scores are < 0.05 raw. Empirically this single op recovers 5/6 test recordings from "undetectable" to Cat ≥ 0.45. Streaming-friendly (per-sample, no lookahead). See `scripts/eval_recordings.py` for the supporting evaluation.
5. **YAMNet** — TF Hub model, 521 AudioSet classes. Score the `Meow`, `Cat`, `Caterwaul`, `Hiss`, `Purr` classes; `Purr` is logged for diagnostics only.
6. **Detection logic**
   - Trigger signal: `max(Meow, Cat, Caterwaul)` per window. `Cat` is the broader and more sensitive class; bare `Meow` underfires.
   - Trigger if score >= `T_trigger` for `N` consecutive windows.
   - Cooldown after a notification so one meowing session ≠ many alerts (added with the notifier in Phase 2).
7. **Slack notifier** — `slack_sdk`: `chat_postMessage` + `files_upload_v2` for the snippet.
8. **launchd agent** — `~/Library/LaunchAgents/com.wandermyz.meow.plist`, `KeepAlive` + `RunAtLoad`.

### Tech stack

- Python 3.11–3.13 (TF has no cp314 wheels yet)
- `tensorflow` + `tensorflow_hub` (the latter still imports `pkg_resources`, so pin `setuptools<81`)
- `sounddevice`, `numpy`, `scipy` (for `resample_poly`)
- `slack_sdk`
- `tomllib` for config

### Layout

```
meow/
├── CLAUDE.md
├── README.md
├── pyproject.toml
├── docs/
│   └── plans/2026-05-06-meow-detector-daemon.md   ← this file
├── src/meow/
│   ├── __init__.py
│   ├── __main__.py        # entrypoint
│   ├── capture.py         # mic + ring buffer
│   ├── detector.py        # YAMNet wrapper + detection logic
│   ├── notifier.py        # Slack client
│   ├── config.py
│   └── daemon.py          # main loop
├── scripts/
│   └── com.wandermyz.meow.plist.template
└── tests/
    └── samples/           # short wavs for offline tuning
```

## Slack app setup

Manual one-time step before the daemon can post.

1. Go to https://api.slack.com/apps → **Create New App** → *From scratch*.
2. **App name:** `wandermyz.meow`. Pick the personal workspace.
3. **App Home → App Display Name** → `Meow` (this is the visible bot name in messages).
4. **OAuth & Permissions → Scopes → Bot Token Scopes:** add `chat:write` and `files:write` (needed for the audio snippet upload).
5. **Install App** → copy the `xoxb-…` bot token.
6. User specifies the destination **channel ID** (`C…`) in config; invite `@Meow` to that channel.
7. Store the token at `~/.yuki-conductor/workspace/meow/config.toml` (gitignored), e.g.:

   ```toml
   [slack]
   bot_token = "xoxb-..."
   channel   = "C0123456789"   # channel ID, supplied by user
   ```

## Detection tuning

Calibrated against the recordings in `~/Downloads/meow-example/` (~1.5 m to ~5 m mic distance, RMS −54 to −50 dBFS — the "distant Siggraph" case). Per-file peak `Cat` scores after the boost step:

| Recording          | raw   | boosted |
|--------------------|-------|---------|
| Sovereign Way      | 0.78  | 0.99    |
| Sovereign Way 2    | 0.03  | 0.90    |
| Sovereign Way 7    | 0.30  | 0.97    |
| Sovereign Way 8    | 0.24  | 0.47    |
| Sovereign Way 54   | 0.48  | 0.79    |
| 嗷嗷嗷               | 0.12  | 0.26    |

Decision: `T_trigger = 0.30` on `max(Meow, Cat, Caterwaul)` catches 5 of 6 with margin. The 嗷嗷嗷 clip is a known edge case — accepted as a miss for v1; revisit if recall is too low in deployment.

| Param                  | Value | Rationale                                                                 |
|------------------------|-------|---------------------------------------------------------------------------|
| Boost gain             | 10×   | `tanh(x*10)`; recovers distant audio without distorting close-up meows.   |
| Window / hop           | 1.0 s / 0.5 s | Overlap matches YAMNet's native cadence and gives short isolated meows two chances to land near the centre of a window. With non-overlap, 3/6 test clips failed the consecutive-frame check. |
| Trigger signal         | `max(Meow, Cat, Caterwaul)` | `Cat` is broader and more sensitive than `Meow`; `Caterwaul` covers distress. |
| `T_trigger`            | 0.30  | Catches 5/6 boosted test files end-to-end through the streaming simulator. |
| `N` consecutive frames | 2     | ~1 s of sustained signal; suppresses single-frame spikes.                  |
| Cooldown               | 60 s  | Phase 2; one alert per session.                                            |
| RMS gate               | -45 dBFS | Phase 3; skips inference on silence.                                    |

End-to-end streaming-simulator results with the parameters above (`scripts/eval_recordings.py`-style decode → `boost` → 1 s/0.5 s windows → trigger logic):

| Recording          | windows | trigger hits | result                |
|--------------------|---------|--------------|-----------------------|
| Sovereign Way      | 87      | 21           | FIRED at 9.0 s        |
| Sovereign Way 2    | 93      |  5           | FIRED at 22.5 s       |
| Sovereign Way 7    | 74      | 12           | FIRED at 14.0 s       |
| Sovereign Way 8    | 52      |  1           | no trigger (accepted) |
| Sovereign Way 54   | 61      |  7           | FIRED at 4.0 s        |
| 嗷嗷嗷               | 67      |  3           | FIRED at 7.0 s        |

`Hiss` and `Purr` are tracked for diagnostics but excluded from the trigger:
- `Purr` fires spuriously on HVAC-like noise in the test set.
- `Hiss` rarely fires on quiet ambient and we don't want a spike on white-noise transients to alert. We may revisit promoting `Hiss` to a trigger once we have empirical home-quiet false-positive data.

Because nobody is home, we can be aggressive on recall and tolerate a few false positives (HVAC, fridge compressor). False-positive triage will likely focus on these specific household sounds — collect them in `tests/samples/` for regression checks.

## launchd

- Plist at `~/Library/LaunchAgents/com.wandermyz.meow.plist`.
- `RunAtLoad=true`, `KeepAlive=true` (restart on crash).
- `StandardOutPath` / `StandardErrorPath` → `~/.yuki-conductor/workspace/logs/meow.{out,err}.log`.
- Microphone permission: macOS will prompt the first time; the agent must run as the user, not as root, so the TCC prompt actually appears. Confirm permission persists across reboots.

## Audio snippet attachment

Each alert includes a short clip for verification.

- **Window:** ~3 s ending at the trigger frame, drawn from the rolling ring buffer (no extra recording infra needed — buffer must hold at least 3 s).
- **Format:** 16 kHz mono WAV (small, no encode dependency). Optionally MP3/OGG later if size matters.
- **Delivery:** `files_upload_v2` to the same channel, with the alert message as the initial comment so message + audio land together. Stored only in Slack — no local archive.
- **Retention:** none on our side; rely on Slack's storage. Buffer is overwritten continuously.

## Audio device

- Use the system default input — whatever macOS has selected (built-in mic or any mic the user picks via System Settings → Sound).
- Log the selected device name and sample rate at startup so we can tell from logs which mic was active.
- No `--device` flag in v1; revisit if needed.

## Implementation phases

1. **CLI prototype** — `python -m meow` runs YAMNet on the system default mic and prints detections to stdout. No Slack yet.
2. **Slack integration** — wire `notifier.py`, post text alert + 3 s WAV snippet to the configured channel ID.
3. **Tuning pass** — record Siggraph; record household false-positive sounds (fridge, HVAC, doorbell, neighbor dog); pick thresholds.
4. **launchd packaging** — plist template + install script. Validate autostart and crash recovery.
5. **Health check** — daily heartbeat message ("meow daemon alive, X meows today") so we notice if it dies silently. Optional.

## Risks

- **TF on macOS** can be a setup headache, especially on Apple Silicon. Fallback: a PyTorch YAMNet port or ONNX export.
- **TCC mic permission** can reset on macOS upgrades. Document the re-grant procedure in `meow/CLAUDE.md`.
- **Slack rate limits** — non-issue at expected volume, but cooldown logic prevents accidental spam if the threshold ends up too low.
