import Foundation

/// Compatibility adapter for Apple's consolidated, 16-bit stereo Steinway library.
/// Streams a mono SoundFont to disk; never loads the CAF into memory.
enum SteinwayBank {
    struct Zone {
        let root: UInt8
        let low: UInt8
        let high: UInt8
        let velocityLow: UInt8
        let velocityHigh: UInt8
        let start: UInt32
        let loopStart: UInt32
        let loopEnd: UInt32
        let end: UInt32
    }

    static func cachedBank(instrument: URL, cacheDirectory: URL) throws -> URL {
        let caf = URL(fileURLWithPath: "/Library/Application Support/Logic/EXS Factory Samples/01 Acoustic Pianos/Steinway Piano_consolidated.caf")
        let manager = FileManager.default
        let sources = try [instrument, caf].map { url -> String in
            let attributes = try manager.attributesOfItem(atPath: url.path)
            return "\(attributes[.size]!)\(attributes[.modificationDate]!)"
        }.joined()
        let bank = cacheDirectory.appendingPathComponent("Steinway-mono-v2.sf2")
        let stamp = cacheDirectory.appendingPathComponent("Steinway-mono-v2.source")
        if manager.fileExists(atPath: bank.path), (try? String(contentsOf: stamp)) == sources { return bank }
        try manager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let temporary = cacheDirectory.appendingPathComponent(UUID().uuidString + ".sf2")
        defer { try? manager.removeItem(at: temporary) }
        try convert(instrument: instrument, caf: caf, destination: temporary)
        if manager.fileExists(atPath: bank.path) { try manager.removeItem(at: bank) }
        try manager.moveItem(at: temporary, to: bank)
        try sources.write(to: stamp, atomically: true, encoding: .utf8)
        return bank
    }

    static func convert(instrument: URL, caf: URL, destination: URL) throws {
        let zones = try readZones(instrument)
        let input = try FileHandle(forReadingFrom: caf)
        defer { try? input.close() }
        let (audioOffset, frameCount) = try readCAF(input)
        guard zones.allSatisfy({ $0.start < $0.end && $0.end <= frameCount && $0.loopStart < $0.loopEnd && $0.loopEnd <= frameCount && $0.low <= $0.high && $0.velocityLow <= $0.velocityHigh }) else {
            throw failure("Unrecognized Steinway sample boundaries")
        }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let output = try FileHandle(forUpdating: destination)
        defer { try? output.close() }
        try output.write(contentsOf: Data("RIFF".utf8) + le32(0) + Data("sfbk".utf8))
        let info = chunk("ifil", le16(2) + le16(1))
            + chunk("isng", Data("EMU8000\0".utf8))
            + chunk("INAM", Data("Local Steinway Mono\0".utf8))
        try output.write(contentsOf: chunk("LIST", Data("INFO".utf8) + info))
        let sdtaOffset = try output.offset()
        try output.write(contentsOf: Data("LIST".utf8) + le32(0) + Data("sdtasmpl".utf8) + le32(0))

        var headers = Data()
        var generators = Data()
        var bags = Data()
        var sampleOffset: UInt32 = 0
        var generatorIndex: UInt16 = 0
        for (index, zone) in zones.enumerated() {
            bags += le16(generatorIndex) + le16(0)
            // Key and velocity ranges must precede other SF2 generators; sample ID is last.
            generators += generator(43, UInt16(zone.low) | UInt16(zone.high) << 8)
            generators += generator(44, UInt16(zone.velocityLow) | UInt16(zone.velocityHigh) << 8)
            generators += generator(38, UInt16(bitPattern: -1800)) // ~350 ms release.
            generators += generator(54, 3) // Loop only while held / sustain pedal down.
            generators += generator(58, UInt16(zone.root))
            generators += generator(53, UInt16(index))
            generatorIndex += 6

            let attackLength = zone.end - zone.start
            let length = attackLength + zone.loopEnd - zone.loopStart
            headers += name("Piano \(index)") + le32(sampleOffset) + le32(sampleOffset + length)
                + le32(sampleOffset + attackLength)
                + le32(sampleOffset + length)
                + le32(44100) + Data([zone.root, 0]) + le16(0) + le16(1)
            // Consolidated EXS stores attack and sustain-loop ranges separately.
            // Copy only those ranges, rather than unrelated CAF samples in between.
            for (start, end) in [(zone.start, zone.end), (zone.loopStart, zone.loopEnd)] {
                try input.seek(toOffset: audioOffset + UInt64(start) * 4)
                var remaining = Int(end - start)
                while remaining > 0 {
                    let frames = min(8192, remaining)
                    guard let stereo = try input.read(upToCount: frames * 4), stereo.count == frames * 4 else { throw failure("Truncated Steinway samples") }
                    var mono = Data(count: frames * 2)
                    stereo.withUnsafeBytes { source in
                        mono.withUnsafeMutableBytes { target in
                            let bytes = source.bindMemory(to: UInt8.self)
                            let result = target.bindMemory(to: UInt8.self)
                            for frame in 0..<frames {
                                let position = frame * 4
                                let left = Int16(bitPattern: UInt16(bytes[position]) << 8 | UInt16(bytes[position + 1]))
                                let right = Int16(bitPattern: UInt16(bytes[position + 2]) << 8 | UInt16(bytes[position + 3]))
                                let value = UInt16(bitPattern: Int16((Int32(left) + Int32(right)) / 2))
                                result[frame * 2] = UInt8(truncatingIfNeeded: value)
                                result[frame * 2 + 1] = UInt8(value >> 8)
                            }
                        }
                    }
                    try output.write(contentsOf: mono)
                    remaining -= frames
                }
            }
            try output.write(contentsOf: Data(count: 92)) // SF2 requires 46 guard samples.
            sampleOffset += length + 46
        }
        let sampleBytes = sampleOffset * 2
        bags += le16(generatorIndex) + le16(0)
        generators += Data(count: 4)
        headers += name("EOS") + Data(count: 26)
        let phdr = name("Steinway") + le16(0) + le16(0) + le16(0) + Data(count: 12)
            + name("EOP") + le16(0) + le16(0) + le16(1) + Data(count: 12)
        let pdta = chunk("phdr", phdr)
            + chunk("pbag", le16(0) + le16(0) + le16(1) + le16(0))
            + chunk("pmod", Data(count: 10))
            + chunk("pgen", generator(41, 0) + Data(count: 4))
            + chunk("inst", name("Steinway") + le16(0) + name("EOI") + le16(UInt16(zones.count)))
            + chunk("ibag", bags) + chunk("imod", Data(count: 10))
            + chunk("igen", generators) + chunk("shdr", headers)
        try output.write(contentsOf: chunk("LIST", Data("pdta".utf8) + pdta))
        let endOffset = try output.offset()
        guard endOffset < UInt32.max else { throw CocoaError(.fileWriteOutOfSpace) }
        try output.seek(toOffset: 4)
        try output.write(contentsOf: le32(UInt32(endOffset - 8)))
        try output.seek(toOffset: sdtaOffset + 4)
        try output.write(contentsOf: le32(sampleBytes + 12))
        try output.seek(toOffset: sdtaOffset + 16)
        try output.write(contentsOf: le32(sampleBytes))
        try output.synchronize()
    }

    private static func readZones(_ url: URL) throws -> [Zone] {
        let data = try Data(contentsOf: url)
        var rawZones: [Data] = []
        var groups: [Data] = []
        var offset = 0
        while offset + 84 <= data.count {
            let type = read32(data, offset)
            let size = Int(read32(data, offset + 4))
            guard size <= data.count - offset - 84 else { throw failure("Invalid EXS chunk") }
            let body = Data(data[(offset + 84)..<(offset + 84 + size)])
            if type >> 24 == 0x41 { rawZones.append(body) }
            if type >> 24 == 0x42 { groups.append(body) }
            offset += 84 + size
        }
        // Narrow to the observed Apple library. Unknown EXS files still use the native loader.
        guard offset == data.count, rawZones.count == 224, groups.count == 20,
              data.range(of: Data("Steinway Piano_consolidated.caf".utf8)) != nil,
              groups.allSatisfy({ $0.count >= 92 }) else { throw failure("Unsupported consolidated Steinway preset") }
        return try rawZones.prefix(120).map { body in
            guard body.count >= 92 else { throw failure("Invalid Steinway zone") }
            let groupIndex = Int(body[88]) | Int(body[89]) << 8
            guard groupIndex < 16 else { throw failure("Invalid Steinway velocity group") }
            let group = groups[groupIndex]
            return Zone(root: body[1], low: max(body[6], group[88]), high: min(body[7], group[89]),
                        velocityLow: group[5], velocityHigh: group[6], start: read32(body, 12),
                        loopStart: read32(body, 20), loopEnd: read32(body, 24), end: read32(body, 16))
        }
    }

    private static func readCAF(_ input: FileHandle) throws -> (UInt64, UInt32) {
        guard let header = try input.read(upToCount: 8), header.prefix(4) == Data("caff".utf8) else { throw failure("Invalid CAF") }
        var validFormat = false
        while let header = try input.read(upToCount: 12), header.count == 12 {
            let identifier = String(decoding: header.prefix(4), as: UTF8.self)
            let size = header.suffix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let offset = try input.offset()
            if identifier == "desc" {
                guard size == 32, let format = try input.read(upToCount: 32), format.count == 32 else { throw failure("Invalid CAF format") }
                let rateBits = format.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                validFormat = Double(bitPattern: rateBits) == 44100
                    && format[8..<12] == Data("lpcm".utf8)
                    && readBE32(format, 12) == 0 && readBE32(format, 16) == 4
                    && readBE32(format, 20) == 1 && readBE32(format, 24) == 2 && readBE32(format, 28) == 16
            } else if identifier == "data" {
                guard validFormat, size >= 4, size / 4 <= UInt32.max else { throw failure("Unsupported CAF encoding") }
                return (offset + 4, UInt32((size - 4) / 4))
            }
            guard size < UInt64.max - offset else { throw failure("Invalid CAF chunk") }
            try input.seek(toOffset: offset + size)
        }
        throw failure("Missing CAF audio")
    }

    private static func failure(_ description: String) -> NSError {
        NSError(domain: "PracticePiano.Steinway", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }
    private static func read32(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
    }
    private static func readBE32(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 << 8 | UInt32(data[offset + $1]) }
    }
    private static func le16(_ value: UInt16) -> Data { Data([UInt8(truncatingIfNeeded: value), UInt8(value >> 8)]) }
    private static func le32(_ value: UInt32) -> Data { (0..<4).reduce(into: Data()) { $0.append(UInt8(truncatingIfNeeded: value >> ($1 * 8))) } }
    private static func name(_ string: String) -> Data { let bytes = Data(string.utf8.prefix(19)); return bytes + Data(count: 20 - bytes.count) }
    private static func generator(_ number: UInt16, _ value: UInt16) -> Data { le16(number) + le16(value) }
    private static func chunk(_ id: String, _ data: Data) -> Data {
        Data(id.utf8) + le32(UInt32(data.count)) + data + Data(count: data.count % 2)
    }
}
