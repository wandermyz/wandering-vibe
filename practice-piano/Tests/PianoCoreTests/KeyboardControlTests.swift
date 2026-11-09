import XCTest
@testable import PianoCore

final class KeyboardControlTests: XCTestCase {
    func testKeystationTransportPressesAndReleases() {
        let messages: [(UInt8, TransportCommand)] = [(0x5f, .record), (0x5e, .play), (0x5d, .stop)]
        for (note, command) in messages {
            XCTAssertEqual(KeyboardControls.decode(MIDIMessage(0x90, note, 127), role: .transport), .transport(command))
            XCTAssertNil(KeyboardControls.decode(MIDIMessage(0x90, note, 0), role: .transport))
            XCTAssertNil(KeyboardControls.decode(MIDIMessage(0x80, note, 127), role: .transport))
            XCTAssertNil(KeyboardControls.decode(MIDIMessage(0x90, note, 127), role: .keystationKeyboard))
            XCTAssertNil(KeyboardControls.decode(MIDIMessage(0x90, note, 127), role: .keyboard))
        }
        XCTAssertNil(KeyboardControls.decode(MIDIMessage(0x90, 60, 127), role: .transport))
    }

    func testExpressionSliderAndReassignedVolumeSlider() {
        for controller: UInt8 in [7, 11] {
            XCTAssertEqual(KeyboardControls.decode(MIDIMessage(0xb0, controller, 0), role: .keystationKeyboard), .volume(0))
            XCTAssertEqual(KeyboardControls.decode(MIDIMessage(0xb0, controller, 64), role: .keystationKeyboard), .volume(50))
            XCTAssertEqual(KeyboardControls.decode(MIDIMessage(0xb2, controller, 127), role: .keystationKeyboard), .volume(100))
            XCTAssertNil(KeyboardControls.decode(MIDIMessage(0xb0, controller, 64), role: .transport))
        }
        XCTAssertNil(KeyboardControls.decode(MIDIMessage(0xb0, 64, 127), role: .keystationKeyboard))
    }

    func testForcedSustainSurvivesPedalReleaseAndRestoresPhysicalPedal() {
        var override = SustainOverride()
        XCTAssertEqual(override.process(MIDIMessage(0xb0, 64, 127)), [MIDIMessage(0xb0, 64, 127)])
        XCTAssertEqual(override.setEnabled(true).count, 16)
        XCTAssertEqual(override.process(MIDIMessage(0xb0, 64, 0)), [MIDIMessage(0xb0, 64, 127)])
        _ = override.process(MIDIMessage(0xb2, 64, 100))
        let restored = override.setEnabled(false)
        XCTAssertEqual(restored[0], MIDIMessage(0xb0, 64, 0))
        XCTAssertEqual(restored[2], MIDIMessage(0xb2, 64, 100))
        XCTAssertEqual(override.process(MIDIMessage(0xb2, 64, 0)), [MIDIMessage(0xb2, 64, 0)])
    }

    func testControllerResetCannotDisableForcedSustain() {
        var override = SustainOverride(enabled: true)
        XCTAssertEqual(override.process(MIDIMessage(0xb3, 121, 0)), [MIDIMessage(0xb3, 121, 0), MIDIMessage(0xb3, 64, 127)])
        XCTAssertEqual(override.process(MIDIMessage(0x83, 60, 0)), [MIDIMessage(0x83, 60, 0)])
        _ = override.setEnabled(false)
        _ = override.process(MIDIMessage(0xb1, 64, 127))
        override.resetPhysicalPedals()
        XCTAssertTrue(override.pedalMessages.allSatisfy { $0.data2 == 0 })
    }
}
