# Practice Piano

A small native macOS menu bar app for practicing on a MIDI keyboard. No main window or Dock icon. Requires macOS 13 or newer. The build script targets the host Mac architecture.

## Run

Connect your USB MIDI keyboard, then open `/Applications/Practice Piano.app` (or `dist/Practice Piano.app` for a development build). Click the piano keys icon in the menu bar for controls. It uses the system's current audio output; wired speakers/headphones work best for low latency.

- **Start Recording** captures MIDI notes, velocity, sustain and other channel controllers.
- **Stop Recording & Save…** opens a save panel for a standard `.mid` file.
- Canceling the panel keeps the recording available under **Save Recording…**. **Keep Recording in Local Folder** dismisses the save reminder; each new take has its own file.
- **MIDI Input** selects one keyboard or all connected keyboards, and reconnects when devices appear.
- **Volume**, **Piano Sound**, **Test Sound**, and **All Notes Off** are in the same menu. The macOS piano option uses less memory.
- The app automatically quits when no hardware MIDI keyboard is connected, including at launch. The Keystation Transport port and virtual app endpoints do not keep it open. Reconnect the keyboard and reopen the app to practice again.
- Quitting during recording, including an automatic quit after unplugging the keyboard, finalizes the take in the local recordings folder.

## M-Audio Keystation 61 MK3

The app detects its **USB MIDI** and **Transport** ports. Selecting the keyboard in MIDI Input automatically includes its matching Transport port. The transport port is kept separate from piano notes.

- **Slider:** controls keyboard volume/expression and shows its current percentage under Volume. The menu's volume presets remain the overall output level. Its default Expression (CC 11) and reassigned Volume (CC 7) messages are supported and preserved in recordings.
- **Record:** starts a new take; pressing it again while recording leaves the current take running.
- **Stop:** finalizes the take in Local Recordings and stops playback/sounding notes, without opening a save dialog.
- **Play:** plays the latest take through the selected piano. If recording, it finalizes that take first. New keyboard notes stop playback so you can resume practicing. The menu also provides Play Latest Recording and Stop.
- **Force Sustain:** checked means sustain stays on without holding a pedal, even if the physical pedal sends a release. Unchecking restores the physical pedal's current state. This preference persists, and effective sustain events are saved in MIDI recordings. Playback follows the saved recording's sustain; changing the checkbox stops playback and applies the new setting to live practice. All Notes Off silences held sounds while preserving the checkbox setting for subsequent notes.

Supports the Keystation mapping of CC 11 on USB MIDI and Mackie note messages 95/94/93 on Transport. The buttons must use Mackie mode.

## Piano sound

The app first tries GarageBand/Logic's installed Steinway instrument. If Apple's standalone sampler rejects the supported consolidated EXS preset, Practice Piano converts the locally installed samples once into a cached mono SoundFont. It retains four velocity layers, mapped sample pitches, and sustain loops. Mono reduces sample memory; GarageBand's effects, stereo image, pedal resonance samples, and exact envelope behavior are not reproduced.

The original Apple sound library stays in place. No samples are bundled or downloaded. If no compatible Steinway library is installed, the app uses the macOS General MIDI grand piano. You can also choose an `.exs`, `.aupreset`, `.sf2`, or `.dls` instrument file; sound banks use program 0, bank 0. Keyboard program/bank changes do not change the live piano.

MIDI files contain performance data, not recorded audio or the Steinway samples. Playback sound depends on the app that opens them.

## Resource use and storage

Native AppKit, Core MIDI and AVAudioEngine; no external dependencies, network access, visualizer, or polling. Audio pauses 15 seconds after the last released note/pedal, and resumes on the next note. The first note after idle may have a small engine-start delay. Resource use varies with the loaded instrument, macOS, memory pressure, and audio hardware. Held notes or sustain keep rendering active. Recording uses a 4 KB disk buffer rather than retaining a growing MIDI event array.

- Local recordings: `~/Library/Application Support/PracticePiano/Recordings/`
- Converted Steinway bank: `~/Library/Caches/PracticePiano/Steinway-mono-v2.sf2`
- Preferences: macOS defaults domain `local.practice-piano`

A crash can leave a `.mid.draft` file. The last buffered events (at most about 4 KB) can be lost. Recover the complete events with `python3 scripts/recover-midi.py '/path/to/file.mid.draft'`; the script preserves the draft and writes a `.mid` beside it.

## Build and validate

Requires Xcode or the Swift tools for macOS:

```sh
./scripts/build-app.sh
./scripts/test.sh
'dist/Practice Piano.app/Contents/MacOS/PracticePiano' --audio-check
'dist/Practice Piano.app/Contents/MacOS/PracticePiano' --control-check
```

The build produces a locally ad-hoc signed app, with no provisioning or third-party packages. Open `Package.swift` in Xcode to inspect or develop the code. The offline audio check requires the installed consolidated Steinway library and renders low/high notes at all four velocity layers without audible output. It also verifies forced sustain beyond the attack sample despite a physical pedal release, then checks that disabling it silences the note. The control check runs the supported Record/Stop/Play messages through the real session, saves a temporary MIDI file, and verifies silent playback and cleanup.

Automated checks cover MIDI parsing, timing, streaming export and sampler output. A physical keyboard check is still needed to judge playing latency and pedal behavior on your hardware. Bluetooth audio adds latency independently of the app.

## Repository contents

Source code, tests, build scripts, documentation, and the app icon are included. Build products, local preferences, MIDI recordings, developer caches, and instrument/sample files are excluded from version control. Apple instrument libraries must already be installed separately; they are not distributed with this project.
