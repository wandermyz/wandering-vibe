# Architecture

Practice Piano uses AppKit for a menu bar interface, Core MIDI for keyboard input, and AVAudioEngine with AVAudioUnitSampler for sound. One serial queue owns MIDI parsing, controller state, audio commands, and the disk recorder. Core MIDI callbacks copy incoming packets and enqueue them; file writes and instrument loading do not run in those callbacks.

## Instruments

The sampler tries supported locally installed Steinway EXS instruments, then a compatibility conversion of the recognized consolidated library, and finally the system General MIDI piano. The compatibility adapter streams separate attack and sustain-loop ranges into a cached mono SoundFont while retaining pitch mapping and four velocity layers. No instrument or sample data is bundled. The app can also load user-selected EXS, AU preset, SoundFont, or DLS files.

The audio engine pauses 15 seconds after notes and pedals are released. Held notes or sustain keep it active. A new note resumes rendering. Audio route changes and wake notifications refresh the graph when a keyboard remains connected.

## MIDI input and controls

Each source has an independent parser for fragmented packets, running status, and interleaved system messages. Sources have keyboard or transport roles. Keystation keyboard and transport endpoints are grouped by their Core MIDI device so selecting the keyboard includes its transport endpoint.

| Control | Port | MIDI message | Behavior |
| --- | --- | --- | --- |
| Slider | USB MIDI | CC 11, or reassigned CC 7 | Volume/expression; coalesced menu percentage |
| Record | Transport | Note 95 with nonzero velocity | Start a take |
| Play | Transport | Note 94 with nonzero velocity | Finalize an active take and replay the latest |
| Stop | Transport | Note 93 with nonzero velocity | Finalize a take and stop playback/sounding notes |

Transport release messages are ignored. These pitches remain normal piano notes on the keyboard endpoint. Transport actions run immediately on the serial MIDI queue, while menu changes are dispatched to the main queue.

Force Sustain retains physical pedal values by channel and emits effective CC 64 events. Enabling forces sustain on; disabling restores physical pedal control. Effective pedal state is included in recording snapshots and events. Panic releases voices while preserving the preference for subsequent notes.

## Recording and playback

Recording streams MIDI format 0 with 480 ticks per quarter note and an explicit 120 BPM tempo into a temporary draft with a 4 KB buffer. Start captures held notes and controller state. Stop appends pedal release and all-notes-off messages, finalizes the track length, and renames the draft. Hardware Stop saves locally; the menu's Stop Recording & Save action additionally opens a save panel. Canceling a save preserves the local take. The recovery script can recover complete events from a crash draft.

AVAudioSequencer is allocated only during playback and uses one completion timer. It routes tracks to the selected sampler, honors recorded sustain, and restores live controller settings afterward. New keyboard notes, Stop, route changes, or completion end playback and release the sequencer.

## Automatic quit

Online sources are checked at launch and on Core MIDI notifications. Without a keyboard source belonging to a device, the app quits. A Keystation transport endpoint or virtual app endpoint alone does not keep it open. Startup checks occur before sample loading; disconnect checks do not poll.

Quit requests are coalesced and scheduled with `RunLoop.main.perform(inModes: [.common])`. This avoids blocking AppKit's asynchronous termination loop inside a main dispatch callback. Shutdown finalizes any active take, stops playback and audio, and disposes MIDI ports. Reconnecting a keyboard requires reopening the app.

## Validation

Unit tests cover MIDI parsing and timing, bounded recording writes, transport isolation and release handling, slider mapping, forced sustain, and physical pedal restoration. The audio check renders note/velocity combinations, verifies volume controllers, and checks forced sustain and release. The muted control integration check exercises recording, playback, and finalizing an active take during shutdown. Playing latency and physical pedal behavior require hardware validation.
