import Foundation
import XCTest
@testable import PianoCore

final class MIDITests: XCTestCase {
    func testFragmentedRunningStatusAndRealtime() {
        var parser = MIDIParser()
        var result: [MIDIMessage] = []
        parser.consume(Data([0x90, 60, 0xf8])) { result.append($0) }
        parser.consume(Data([90, 62, 0xfe, 80, 0x80, 60, 0])) { result.append($0) }
        XCTAssertEqual(result, [MIDIMessage(0x90, 60, 90), MIDIMessage(0x90, 62, 80), MIDIMessage(0x80, 60, 0)])
    }

    func testSystemMessagesCancelRunningStatus() {
        var parser = MIDIParser()
        var result: [MIDIMessage] = []
        parser.consume(Data([0x90, 60, 80, 0xf0, 1, 2, 0xf8, 3, 0xf7, 62, 80, 0xf2, 0, 0, 63, 80, 0xc0, 2, 3, 0xd0, 44])) { result.append($0) }
        XCTAssertEqual(result, [MIDIMessage(0x90, 60, 80), MIDIMessage(0xc0, 2), MIDIMessage(0xc0, 3), MIDIMessage(0xd0, 44)])
    }

    func testParsersAreIndependent() {
        var left = MIDIParser()
        var right = MIDIParser()
        var result: [MIDIMessage] = []
        left.consume(Data([0x90, 60])) { result.append($0) }
        right.consume(Data([80])) { result.append($0) }
        XCTAssertTrue(result.isEmpty)
        left.consume(Data([80])) { result.append($0) }
        XCTAssertEqual(result, [MIDIMessage(0x90, 60, 80)])
    }

    func testStateTracksSustainAndAllNotesOff() {
        var state = MIDIState()
        state.apply(MIDIMessage(0x91, 60, 90))
        state.apply(MIDIMessage(0xb1, 64, 127))
        state.apply(MIDIMessage(0x91, 60, 0))
        XCTAssertTrue(state.isHoldingSound)
        XCTAssertTrue(state.notes.isEmpty)
        state.apply(MIDIMessage(0xb1, 64, 0))
        XCTAssertFalse(state.isHoldingSound)
        state.apply(MIDIMessage(0x90, 60, 90))
        state.apply(MIDIMessage(0x91, 62, 90))
        state.apply(MIDIMessage(0xb0, 123, 0))
        XCTAssertEqual(state.notes.count, 1)
        state.apply(MIDIMessage(0xb1, 123, 0))
        XCTAssertFalse(state.isHoldingSound)
    }

    func testVariableLengthEncoding() {
        XCTAssertEqual(MIDIRecorder.variableLength(0), [0])
        XCTAssertEqual(MIDIRecorder.variableLength(127), [127])
        XCTAssertEqual(MIDIRecorder.variableLength(128), [0x81, 0])
        XCTAssertEqual(MIDIRecorder.variableLength(480), [0x83, 0x60])
        XCTAssertEqual(MIDIRecorder.variableLength(0x0fffffff), [0xff, 0xff, 0xff, 0x7f])
    }

    func testRecordedFileTimingControllersAndTermination() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mid")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = try MIDIRecorder(url: url, startTime: 10, snapshot: [MIDIMessage(0xb0, 64, 127)])
        try recorder.record(MIDIMessage(0x90, 60, 90), time: 10)
        try recorder.record(MIDIMessage(0x80, 60, 0), time: 10.5)
        try recorder.record(MIDIMessage(0xb0, 64, 0), time: 10.4) // Sources may arrive out of order.
        try recorder.finish(time: 11)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(14)), [0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 1, 0xe0])
        let length = data[18..<22].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        XCTAssertEqual(Int(length), data.count - 22)
        XCTAssertNotNil(data.range(of: Data([0x83, 0x60, 0x80, 60, 0, 0, 0xb0, 64, 0])))
        XCTAssertEqual(Array(data.suffix(4)), [0, 0xff, 0x2f, 0])
        XCTAssertNotNil(data.range(of: Data([0x83, 0x60, 0xb0, 64, 0])))
    }

    func testStreamingLargeRecordingAndLongSilence() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mid")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = try MIDIRecorder(url: url, startTime: 0)
        for i in 0..<5000 { try recorder.record(MIDIMessage(0x90, 60, UInt8(i % 127)), time: Double(i) / 1000) }
        let written = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! NSNumber
        XCTAssertGreaterThan(written.intValue, 16000)
        try recorder.record(MIDIMessage(0x80, 60, 0), time: 400000)
        try recorder.finish(time: 400000)
        let data = try Data(contentsOf: url)
        XCTAssertNotNil(data.range(of: Data([0xff, 0xff, 0xff, 0x7f, 0xff, 0x01, 0])))
    }
}
