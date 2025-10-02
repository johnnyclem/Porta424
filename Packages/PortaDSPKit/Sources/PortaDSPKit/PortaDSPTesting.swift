import PortaDSPBridge

enum PortaDSPTesting {
    static func applyDropouts(
        buffer: inout [Float],
        frames: Int,
        channels: Int,
        sampleRate: Float,
        dropoutRatePerMinute: Float,
        dropoutLengthSamples: Int,
        seed: UInt32
    ) {
        guard frames > 0, channels > 0, dropoutLengthSamples > 0 else { return }
        guard buffer.count >= frames * channels else { return }

        buffer.withUnsafeMutableBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            porta_test_apply_dropouts(
                baseAddress,
                Int32(frames),
                Int32(channels),
                sampleRate,
                dropoutRatePerMinute,
                Int32(dropoutLengthSamples),
                seed
            )
        }
    }
}
