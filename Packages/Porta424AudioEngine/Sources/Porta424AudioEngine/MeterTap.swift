import AVFoundation
import Accelerate

final class MeterTap {
    private weak var node: AVAudioNode?
    private let handler: (Float) -> Void
    private var installed = false

    init(node: AVAudioNode, handler: @escaping (Float) -> Void) {
        self.node = node
        self.handler = handler
    }

    func install(format: AVAudioFormat) {
        guard let node, !installed else { return }
        installed = true
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let level = self.analyze(buffer: buffer)
            self.handler(level)
        }
    }

    func uninstall() {
        node?.removeTap(onBus: 0)
        installed = false
    }

    private func analyze(buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        var peak: Float = 0
        for channelIndex in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channelIndex]
            var sum: Float = 0
            vDSP_dotpr(samples, 1, samples, 1, &sum, vDSP_Length(frameCount))
            let rms = sqrtf(sum / Float(frameCount))
            peak = max(peak, rms)
        }
        let db = 20 * log10(max(1e-6, peak))
        let normalized = max(0, min(1, (db + 60) / 60))
        return normalized
    }
}
