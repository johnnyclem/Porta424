import XCTest
@testable import PortaDSPKit

final class PortaDSPFuzzTests: XCTestCase {
    private static let iterationCount = 10_000

    func testRandomizedParameterUpdatesAndProcessingStayFinite() throws {
        let environment = ProcessInfo.processInfo.environment
        let seed = environment["PORTADSP_FUZZ_SEED"].flatMap(UInt64.init) ?? 0xA5EED1234BEEF00D

        var globalRNG = SeededGenerator(seed: seed)
        let dsp = PortaDSP(sampleRate: 48_000.0, maxBlock: 1_024, tracks: 4)

        for iteration in 0..<Self.iterationCount {
            let iterationSeed = globalRNG.next()
            var iterationRNG = SeededGenerator(seed: iterationSeed)

            var params = PortaDSP.Params()
            params.wowDepth = Float.random(in: 0.0...0.01, using: &iterationRNG)
            params.flutterDepth = Float.random(in: 0.0...0.01, using: &iterationRNG)
            params.headBumpGainDb = Float.random(in: (-12.0)...12.0, using: &iterationRNG)
            params.headBumpFreqHz = Float.random(in: 10.0...2_000.0, using: &iterationRNG)
            params.satDriveDb = Float.random(in: (-70.0)...50.0, using: &iterationRNG)
            params.hissLevelDbFS = Float.random(in: (-140.0)...(-10.0), using: &iterationRNG)
            params.lpfCutoffHz = Float.random(in: 200.0...22_000.0, using: &iterationRNG)
            params.azimuthJitterMs = Float.random(in: 0.0...5.0, using: &iterationRNG)
            params.crosstalkDb = Float.random(in: (-140.0)...0.0, using: &iterationRNG)
            params.dropoutRatePerMin = Float.random(in: 0.0...60.0, using: &iterationRNG)
            params.nrTrack4Bypass = Bool.random(using: &iterationRNG)

            dsp.update(params)

            let frames = Int.random(in: 1...1_024, using: &iterationRNG)
            let channels = Int.random(in: 1...4, using: &iterationRNG)
            var buffer = (0..<(frames * channels)).map { _ in
                Float.random(in: -2.0...2.0, using: &iterationRNG)
            }

            dsp.processInterleaved(buffer: &buffer, frames: frames, channels: channels)

            if let problematicIndex = buffer.firstIndex(where: { !$0.isFinite }) {
                let message = "Non-finite sample detected (seed=\(seed), iterationSeed=\(iterationSeed), iteration=\(iteration), sampleIndex=\(problematicIndex))"
                XCTFail(message)
                return
            }

            let meters = dsp.readMeters()
            if let problematicMeterIndex = meters.firstIndex(where: { !$0.isFinite }) {
                let message = "Non-finite meter detected (seed=\(seed), iterationSeed=\(iterationSeed), iteration=\(iteration), meterIndex=\(problematicMeterIndex))"
                XCTFail(message)
                return
            }
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed != 0 ? seed : 0x123456789ABCDEF
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
