//
//  CtcEmissions.swift
//  Resona
//
//  Per-frame log probabilities from the CTC model with ONNX Runtime (CPU,
//  4 threads, like Android): 30 s windows, zero mean / unit variance input.
//

import Foundation
import OnnxRuntimeBindings

enum CtcEmissions {
    static let window = 30 * 16_000

    static func compute(modelPath: String, audio: [Float], threads: Int, onWindow: (Int, Int) -> Void = { _, _ in }) throws -> [[Float]] {
        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(Int32(threads))
        let session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
        guard let input = try session.inputNames().first, let output = try session.outputNames().first else {
            throw NSError(domain: "CtcEmissions", code: 1)
        }
        let windows = (audio.count + window - 1) / window
        var frames: [[Float]] = []
        frames.reserveCapacity(audio.count / 320 + 1)
        var offset = 0
        var index = 0
        while offset < audio.count {
            try Task.checkCancellation()
            let piece = normalized(audio, from: offset, to: min(audio.count, offset + window))
            let data = piece.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Float>.size) }
            let tensor = try ORTValue(tensorData: data, elementType: .float, shape: [1, NSNumber(value: piece.count)])
            let result = try session.run(withInputs: [input: tensor], outputNames: [output], runOptions: nil)
            guard let logits = result[output] else { throw NSError(domain: "CtcEmissions", code: 2) }
            let shape = try logits.tensorTypeAndShapeInfo().shape.map(\.intValue)
            let raw = try logits.tensorData() as Data
            let count = shape[1], vocabulary = shape[2]
            raw.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                let values = buffer.bindMemory(to: Float.self)
                for t in 0..<count {
                    frames.append(logSoftmax(Array(values[(t * vocabulary)..<((t + 1) * vocabulary)])))
                }
            }
            offset += window
            index += 1
            onWindow(index, windows)
        }
        return frames
    }

    /// Zero mean, unit variance, as the model's feature extractor does.
    static func normalized(_ audio: [Float], from: Int, to: Int) -> [Float] {
        let count = max(1, to - from)
        var mean = 0.0
        for i in from..<to { mean += Double(audio[i]) }
        mean /= Double(count)
        var variance = 0.0
        for i in from..<to { let d = Double(audio[i]) - mean; variance += d * d }
        let scale = sqrt(variance / Double(count) + 1e-7)
        return (from..<to).map { Float((Double(audio[$0]) - mean) / scale) }
    }

    static func logSoftmax(_ row: [Float]) -> [Float] {
        let top = row.max() ?? 0
        let sum = row.reduce(0.0) { $0 + exp(Double($1 - top)) }
        let log = Float(Foundation.log(sum))
        return row.map { $0 - top - log }
    }
}
