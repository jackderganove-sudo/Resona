//
//  ShazamSignature.swift
//  Resona
//
//  Music recognition on the iPad (round 11 C): the audio signature, a direct
//  port of the Android app's ShazamSignatureGenerator, so both send the same
//  bytes. Apple's ShazamKit needs an app service tied to the bundle id, which
//  a sideloaded, re-signed app can't count on. The golden test checks this
//  against the same reference value as the Android test.
//

import Foundation

struct ShazamSignature: Equatable, Sendable {
    let bytes: Data
    let sampleDurationMs: Int

    var uri: String { "data:audio/vnd.shazam.sig;base64," + bytes.base64EncodedString() }
}

enum ShazamSignatureGenerator {
    static let sampleRate = 16_000
    private static let maxTimeSeconds = 3.1
    private static let maxPeaks = 255
    private static let size = 2048
    private static let bins = 1025
    private static let history = 256
    private static let minEnergy = 1.0 / 64.0
    private static let neighbourOffsets = [-10, -7, -4, -3, 1, 2, 5, 8]
    private static let timeOffsets = [-53, -45, 165, 172, 179, 186, 193, 200, 214, 221, 228, 235, 242, 249]

    private struct Peak {
        let pass: Int
        let magnitude: Int
        let bin: Int
    }

    /// 16 kHz mono PCM → signature; nil when no peak was found (silence).
    static func signature(pcm: [Int16]) -> ShazamSignature? {
        var fft = FFT(size: size)
        let window = (0..<size).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0 + 1) / 2049) }
        var ring = [Int](repeating: 0, count: size)
        var ringPos = 0
        var outputs = [[Double]](repeating: [Double](repeating: 0, count: bins), count: history)
        var outputPos = 0
        var spreads = outputs
        var spreadPos = 0
        var spreadWritten = 0
        var samples = 0
        var bands: [Int: [Peak]] = [:]
        var peakCount = 0
        var position = 0
        var real = [Double](repeating: 0, count: size)
        var imag = [Double](repeating: 0, count: size)

        func wrap(_ value: Int) -> Int { ((value % history) + history) % history }

        while pcm.count - position >= 128, Double(samples) / Double(sampleRate) < maxTimeSeconds || peakCount < maxPeaks {
            samples += 128
            for index in position..<(position + 128) {
                ring[ringPos] = Int(pcm[index])
                ringPos = ringPos + 1 == size ? 0 : ringPos + 1
            }
            position += 128

            // FFT of the last 2048 samples, windowed.
            var read = ringPos
            for index in 0..<size {
                if read == size { read = 0 }
                real[index] = Double(ring[read]) * window[index]
                imag[index] = 0
                read += 1
            }
            fft.transform(&real, &imag)
            for bin in 0..<bins {
                let value = (real[bin] * real[bin] + imag[bin] * imag[bin]) / 131_072
                outputs[outputPos][bin] = value <= 1e-10 ? 1e-10 : value
            }
            outputPos = wrap(outputPos + 1)

            // Spread each peak over neighbouring bins and past passes.
            let origin = outputs[wrap(outputPos - 1)]
            var spread = origin
            for bin in 0...1021 {
                spread[bin] = max(origin[bin], max(origin[bin + 1], origin[bin + 2]))
            }
            let first = wrap(spreadPos - 1), second = wrap(spreadPos - 3), third = wrap(spreadPos - 6)
            for bin in 0..<bins {
                let a = max(spread[bin], spreads[first][bin])
                spreads[first][bin] = a
                let b = max(a, spreads[second][bin])
                spreads[second][bin] = b
                spreads[third][bin] = max(b, spreads[third][bin])
            }
            spreads[spreadPos] = spread
            spreadPos = wrap(spreadPos + 1)
            spreadWritten += 1

            guard spreadWritten >= 46 else { continue }

            // Peaks: 46 passes back, louder than everything around them.
            let energies = outputs[wrap(outputPos - 46)]
            let past = spreads[wrap(spreadPos - 49)]
            for bin in 10...1014 {
                let energy = energies[bin]
                guard energy >= minEnergy, energy >= past[bin - 1] else { continue }
                var neighbour = 0.0
                for offset in neighbourOffsets { neighbour = max(neighbour, past[bin + offset]) }
                guard energy > neighbour else { continue }
                var around = neighbour
                for offset in timeOffsets { around = max(around, spreads[wrap(spreadPos + offset)][bin - 1]) }
                guard energy > around else { continue }

                let magnitude = log(max(minEnergy, energy)) * 1477.3 + 6144
                let before = log(max(minEnergy, energies[bin - 1])) * 1477.3 + 6144
                let after = log(max(minEnergy, energies[bin + 1])) * 1477.3 + 6144
                let curve = magnitude * 2 - before - after
                guard curve > 0 else { continue }
                let corrected = Double(bin) * 64 + (after - before) * 32 / curve
                let hertz = corrected * (Double(sampleRate) / 2 / 1024 / 64)
                guard let band = Self.band(for: hertz) else { continue }
                bands[band, default: []].append(Peak(pass: spreadWritten - 46, magnitude: Int(magnitude), bin: Int(corrected)))
                peakCount += 1
            }
        }
        guard !bands.isEmpty else { return nil }
        return ShazamSignature(bytes: encode(bands: bands, samples: samples), sampleDurationMs: samples * 1000 / sampleRate)
    }

    private static func band(for hertz: Double) -> Int? {
        switch hertz {
        case 250...520: 0
        case 520...1450: 1
        case 1450...3500: 2
        case 3500...5500: 3
        default: nil
        }
    }

    private static func encode(bands: [Int: [Peak]], samples: Int) -> Data {
        var contents = Data()
        for band in bands.keys.sorted() {
            var peaks = Data()
            var last = 0
            for peak in bands[band] ?? [] {
                var delta = peak.pass - last
                if delta >= 255 {
                    peaks.append(0xFF)
                    peaks.appendLittle(UInt32(peak.pass))
                    last = peak.pass
                    delta = 0
                }
                peaks.append(UInt8(min(max(delta, 0), 254)))
                peaks.appendLittle(UInt16(truncatingIfNeeded: peak.magnitude))
                peaks.appendLittle(UInt16(truncatingIfNeeded: peak.bin))
                last = peak.pass
            }
            contents.appendLittle(UInt32(0x6003_0040 + band))
            contents.appendLittle(UInt32(peaks.count))
            contents.append(peaks)
            contents.append(Data(count: (4 - peaks.count % 4) % 4))
        }

        let sizeMinusHeader = UInt32(contents.count + 8)
        var full = Data()
        let header: [UInt32] = [
            0xCAFE_2580, 0, sizeMinusHeader, 0x9411_9C00, 0, 0, 0, 3 << 27, 0, 0,
            UInt32(Double(samples) + Double(sampleRate) * 0.24), (15 << 19) + 0x40000
        ]
        for word in header { full.appendLittle(word) }
        full.appendLittle(UInt32(0x4000_0000))
        full.appendLittle(sizeMinusHeader)
        full.append(contents)

        let crc = CRC32.checksum(full.dropFirst(8))
        withUnsafeBytes(of: crc.littleEndian) { full.replaceSubrange(4..<8, with: $0) }
        return full
    }

    /// In-place radix-2 FFT, same order of operations as the Android port.
    private struct FFT {
        let size: Int
        let cosines: [Double]
        let sines: [Double]
        let reversed: [Int]

        init(size: Int) {
            self.size = size
            cosines = (0..<(size / 2)).map { cos(2 * Double.pi * Double($0) / Double(size)) }
            sines = (0..<(size / 2)).map { sin(2 * Double.pi * Double($0) / Double(size)) }
            let bits = size.trailingZeroBitCount
            reversed = (0..<size).map { value in
                var input = value, output = 0
                for _ in 0..<bits {
                    output = (output << 1) | (input & 1)
                    input >>= 1
                }
                return output
            }
        }

        mutating func transform(_ real: inout [Double], _ imag: inout [Double]) {
            for i in 0..<size where reversed[i] > i {
                real.swapAt(i, reversed[i])
                imag.swapAt(i, reversed[i])
            }
            var length = 2
            while length <= size {
                let half = length / 2, step = size / length
                var start = 0
                while start < size {
                    var k = 0
                    for j in 0..<half {
                        let a = start + j, b = a + half
                        let re = real[b] * cosines[k] + imag[b] * sines[k]
                        let im = -real[b] * sines[k] + imag[b] * cosines[k]
                        real[b] = real[a] - re
                        imag[b] = imag[a] - im
                        real[a] += re
                        imag[a] += im
                        k += step
                    }
                    start += length
                }
                length <<= 1
            }
        }
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        (0..<8).reduce(UInt32(value)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    static func checksum(_ data: some Sequence<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return ~crc
    }
}

private extension Data {
    mutating func appendLittle<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
