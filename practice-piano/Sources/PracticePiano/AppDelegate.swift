import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var session: PianoSession?
    private var inputs: MIDIInputs?
    private var soundName = "Loading piano…"
    private var errorText: String?
    private var recording = false
    private var playing = false
    private var keyboardVolume: Int?
    private var lastRecording: URL?
    private var busy = false {
        didSet { session?.setTransportEnabled(!busy) }
    }
    private var pendingRecording: URL?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var terminating = false
    private var quitRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pianokeys", accessibilityDescription: "Practice Piano")
        statusItem.button?.toolTip = "Practice Piano"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        do {
            let session = try PianoSession()
            self.session = session
            session.onSoundChanged = { [weak self] text in self?.soundName = text; self?.rebuildMenu() }
            session.onError = { [weak self] text in self?.errorText = text; self?.rebuildMenu() }
            session.onRecordingChanged = { [weak self] active in self?.recording = active; self?.rebuildMenu() }
            session.onRecordingSaved = { [weak self] url in
                self?.lastRecording = url
                self?.pendingRecording = url
                self?.rebuildMenu()
            }
            session.onPlaybackChanged = { [weak self] active in self?.playing = active; self?.rebuildMenu() }
            session.onKeyboardVolumeChanged = { [weak self] percentage in self?.keyboardVolume = percentage; self?.rebuildMenu() }
            inputs = try MIDIInputs(session: session)
            inputs?.onChanged = { [weak self] in
                self?.rebuildMenu()
                self?.quitIfNoKeyboard()
            }
            // Avoid loading the sample library if launched without a keyboard.
            guard inputs?.hasKeyboard == true else {
                quitIfNoKeyboard()
                return
            }
            session.start()
            pendingRecording = try FileManager.default.contentsOfDirectory(at: session.recordingsDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "mid" }.sorted { $0.lastPathComponent > $1.lastPathComponent }.first
            lastRecording = pendingRecording
            for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
                workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    guard let self, !self.terminating, !self.quitRequested else { return }
                    self.inputs?.refresh()
                    guard !self.terminating, !self.quitRequested else { return }
                    self.session?.resetAudio()
                })
            }
        } catch { errorText = error.localizedDescription }
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func quitIfNoKeyboard() {
        guard !terminating, !quitRequested, let inputs, !inputs.hasKeyboard else { return }
        quitRequested = true
        // AppKit may spin a nested event loop for terminateLater. Leaving the
        // dispatch callback first lets the main-queue save completion run.
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            guard let self, !self.terminating else { return }
            guard self.inputs?.hasKeyboard == false else {
                self.quitRequested = false
                return
            }
            NSApp.terminate(nil)
        }
    }

    private func item(_ title: String, action: Selector? = nil, key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        result.isEnabled = action != nil
        return result
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(item(inputs?.status ?? "MIDI unavailable"))
        menu.addItem(item(soundName))
        if errorText != nil { menu.addItem(item("Show last error…", action: #selector(showError))) }
        menu.addItem(.separator())
        let record = item(recording ? "Stop Recording & Save…" : "Start Recording", action: #selector(toggleRecording), key: "r")
        record.isEnabled = session != nil && !busy
        menu.addItem(record)
        let play = item("Play Latest Recording", action: #selector(playRecording), key: "p")
        play.isEnabled = lastRecording != nil && !recording && !busy
        menu.addItem(play)
        let stop = item("Stop", action: #selector(stop), key: "s")
        stop.isEnabled = (playing || recording) && !busy
        menu.addItem(stop)
        if pendingRecording != nil {
            menu.addItem(item("Save Recording…", action: #selector(saveRecording)))
            menu.addItem(item("Keep Recording in Local Folder", action: #selector(keepRecording)))
        }
        menu.addItem(item("Show Local Recordings", action: #selector(showRecordings)))
        menu.addItem(.separator())
        let input = item("MIDI Input")
        let inputMenu = NSMenu()
        inputMenu.autoenablesItems = false
        let automatic = item("All Connected Keyboards", action: #selector(selectInput))
        automatic.state = inputs?.selectedID == nil ? .on : .off
        inputMenu.addItem(automatic)
        for source in (inputs?.sources ?? []).filter({ $0.role != .transport }) {
            let choice = item(source.name, action: #selector(selectInput))
            choice.representedObject = NSNumber(value: source.id)
            choice.state = inputs?.selectedID == source.id ? .on : .off
            inputMenu.addItem(choice)
        }
        input.submenu = inputMenu
        input.isEnabled = inputs != nil
        menu.addItem(input)
        let volume = item("Volume")
        let volumeMenu = NSMenu()
        volumeMenu.autoenablesItems = false
        if let keyboardVolume { volumeMenu.addItem(item("Keyboard Slider: \(keyboardVolume)%")); volumeMenu.addItem(.separator()) }
        let selectedVolume = UserDefaults.standard.object(forKey: "volume") as? Int ?? 80
        for percentage in [0, 25, 50, 65, 80, 100] {
            let choice = item(percentage == 0 ? "Mute" : "\(percentage)%", action: #selector(selectVolume))
            choice.tag = percentage
            choice.state = selectedVolume == percentage ? .on : .off
            volumeMenu.addItem(choice)
        }
        volume.submenu = volumeMenu
        volume.isEnabled = session != nil
        menu.addItem(volume)
        let sustain = item("Force Sustain", action: #selector(toggleSustain))
        sustain.state = UserDefaults.standard.bool(forKey: "forceSustain") ? .on : .off
        sustain.isEnabled = session != nil
        menu.addItem(sustain)
        let instrument = item("Piano Sound")
        let instrumentMenu = NSMenu()
        instrumentMenu.autoenablesItems = false
        instrumentMenu.addItem(item("Automatic (Steinway Preferred)", action: #selector(automaticSound)))
        instrumentMenu.addItem(item("macOS Grand Piano (Less Memory)", action: #selector(systemSound)))
        instrumentMenu.addItem(item("Choose Instrument File…", action: #selector(chooseSound)))
        instrument.submenu = instrumentMenu
        instrument.isEnabled = session != nil && !recording
        menu.addItem(instrument)
        let test = item("Test Sound (Middle C)", action: #selector(testSound))
        test.isEnabled = session != nil && !recording
        menu.addItem(test)
        menu.addItem(item("All Notes Off", action: #selector(panic), key: "."))
        menu.addItem(.separator())
        menu.addItem(item("Quit Practice Piano", action: #selector(quit), key: "q"))
        if recording {
            statusItem.button?.title = " ●"
            statusItem.button?.toolTip = "Practice Piano — recording MIDI"
        } else if playing {
            statusItem.button?.title = " ▶"
            statusItem.button?.toolTip = "Practice Piano — playing recording"
        } else {
            statusItem.button?.title = ""
            statusItem.button?.toolTip = "Practice Piano — \(soundName)"
        }
    }

    @objc private func toggleRecording() {
        guard let session, !busy else { return }
        busy = true
        rebuildMenu()
        if recording {
            session.stopRecording { [weak self] result in
                guard let self else { return }
                self.busy = false
                self.recording = false
                switch result {
                case .success(let url): self.pendingRecording = url; self.saveRecording()
                case .failure(let error): self.alert("Recording could not be finalized", "The draft is preserved in Local Recordings. \(error.localizedDescription)")
                }
                self.rebuildMenu()
            }
        } else {
            session.startRecording { [weak self] result in
                guard let self else { return }
                self.busy = false
                switch result {
                case .success: self.recording = true
                case .failure(let error): self.alert("Could not start recording", error.localizedDescription)
                }
                self.rebuildMenu()
            }
        }
    }

    @objc private func saveRecording() {
        guard let source = pendingRecording, !busy else { return }
        let panel = NSSavePanel()
        panel.title = "Save MIDI Recording"
        panel.allowedContentTypes = [UTType(filenameExtension: "mid") ?? .data]
        panel.nameFieldStringValue = source.lastPathComponent
        panel.directoryURL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        busy = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            self.busy = false
            if response == .OK, let destination = panel.url {
                do {
                    if source.standardizedFileURL != destination.standardizedFileURL {
                        // Atomic write preserves an existing destination if the copy fails.
                        try Data(contentsOf: source, options: .mappedIfSafe).write(to: destination, options: .atomic)
                        try FileManager.default.removeItem(at: source)
                    }
                    self.lastRecording = destination
                    self.session?.setLatestRecording(destination)
                    self.pendingRecording = nil
                } catch { self.alert("Could not save recording", "The local recording is preserved. \(error.localizedDescription)") }
            }
            self.rebuildMenu()
        }
    }

    @objc private func keepRecording() { pendingRecording = nil; rebuildMenu() }
    @objc private func playRecording() { session?.playLatest() }
    @objc private func stop() { session?.stop() }
    @objc private func toggleSustain() {
        session?.setForceSustain(!UserDefaults.standard.bool(forKey: "forceSustain"))
        rebuildMenu()
    }
    @objc private func showRecordings() {
        if let directory = session?.recordingsDirectory { NSWorkspace.shared.open(directory) }
    }
    @objc private func selectInput(_ sender: NSMenuItem) { inputs?.selectedID = (sender.representedObject as? NSNumber)?.int32Value }
    @objc private func selectVolume(_ sender: NSMenuItem) { session?.setVolume(sender.tag); rebuildMenu() }
    @objc private func automaticSound() { errorText = nil; session?.setInstrument(nil) }
    @objc private func systemSound() {
        errorText = nil
        session?.setInstrument(URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"))
    }
    @objc private func chooseSound() {
        let panel = NSOpenPanel()
        panel.title = "Choose Piano Instrument"
        panel.message = "Choose EXS, AU preset, SoundFont (.sf2), or DLS. Sound banks use their first piano preset."
        panel.allowedContentTypes = ["exs", "aupreset", "sf2", "dls"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] result in
            if result == .OK, let url = panel.url { self?.errorText = nil; self?.session?.setInstrument(url) }
        }
    }
    @objc private func testSound() { session?.testSound() }
    @objc private func panic() { session?.panic() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showError() { if let text = errorText { alert("Practice Piano", text) } }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        guard let session else { return .terminateNow }
        inputs?.shutdown()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        session.shutdown { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
