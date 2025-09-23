#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation
import PortaDSPBridge

public final class PortaDSP {
    private var handle: porta_dsp_handle?

    public struct Params: Sendable {
        public var wowDepth: Float = 0.0006
        public var flutterDepth: Float = 0.0003
        public var headBumpGainDb: Float = 2.0
        public var headBumpFreqHz: Float = 80.0
        public var satDriveDb: Float = -6.0
        public var hissLevelDbFS: Float = -60.0
        public var lpfCutoffHz: Float = 12000.0
        public var azimuthJitterMs: Float = 0.2
        public var crosstalkDb: Float = -60.0
        public var dropoutRatePerMin: Float = 0.2
        public var nrTrack4Bypass: Bool = false
        public init() {}
    }

    public init(sampleRate: Double = 48000.0, maxBlock: Int = 512, tracks: Int = 4) {
        self.handle = porta_create(sampleRate, Int32(maxBlock), Int32(tracks))
    }

    deinit { if let h = handle { porta_destroy(h) } }

    public func update(_ p: Params) {
        var c = p.makeCParams()
        if let h = handle { porta_update_params(h, &c) }
    }

    // MARK: - Simple processing helper (offline or tap-based demo)
    public func processInterleaved(buffer: inout [Float], frames: Int, channels: Int) {
        guard let h = handle else { return }
        buffer.withUnsafeMutableBufferPointer { bp in
            porta_process_interleaved(h, bp.baseAddress, Int32(frames), Int32(channels))
        }
    }

    public func readMeters() -> [Float] {
        var out = [Float](repeating: -120.0, count: 8)
        if let h = handle {
            _ = porta_get_meters_dbfs(h, &out, Int32(out.count))
        }
        return out
    }

    // MARK: - Standalone helpers

    public static func passthrough(input: [Float], frames: Int, channels: Int) -> [Float] {
        let sampleCount = frames * channels
        guard sampleCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: sampleCount)
        guard input.count >= sampleCount else { return output }

        input.withUnsafeBufferPointer { inBuffer in
            guard let inPtr = inBuffer.baseAddress else { return }
            output.withUnsafeMutableBufferPointer { outBuffer in
                guard let outPtr = outBuffer.baseAddress else { return }
                porta_dsp_passthrough(inPtr, outPtr, Int32(frames), Int32(channels))
            }
        }

        return output
    }
}
