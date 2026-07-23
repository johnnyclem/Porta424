import Foundation
import Porta424AudioEngine
import PortaDSPKit

/// Main-actor façade over `Porta424Engine`: real mixer, transport, record/play, and tape DSP.
@MainActor
final class AudioEngineActor {

    private let deck = Porta424Engine()
    private var isRunning = false
    private var meterPollTask: Task<Void, Never>?
    private var onMeters: (@Sendable ([Float]) -> Void)?

    // MARK: - Lifecycle

    func start(onMeters: @escaping @Sendable ([Float]) -> Void) async throws {
        guard !isRunning else { return }
        self.onMeters = onMeters
        try await deck.start()
        isRunning = true
        startMeterPolling()
    }

    func stop() {
        meterPollTask?.cancel()
        meterPollTask = nil
        deck.stopEngine()
        isRunning = false
    }

    var running: Bool { isRunning }

    // MARK: - Tape DSP

    func updateDSP(_ state: DSPState) {
        deck.setTapeParams(state.toParams())
    }

    func applyPreset(_ params: PortaDSP.Params) {
        deck.setTapeParams(params)
    }

    // MARK: - Mixer

    func setChannels(_ board: [ChannelState]) {
        deck.setChannels(MixerMapping.engineChannels(from: board))
    }

    func setMaster(volume: Double, pitch: Double) {
        deck.setMaster(MixerMapping.engineMaster(volume: volume, pitch: pitch))
    }

    // MARK: - Transport

    func transportPlayPause() {
        deck.transportPlayPause()
    }

    func transportStop() {
        deck.transportStop()
    }

    func transportRecordToggle() {
        deck.transportRecordToggle()
    }

    func rewind(seconds: TimeInterval = 2.5) {
        deck.rewind(seconds: seconds)
    }

    func fastForward(seconds: TimeInterval = 2.5) {
        deck.fastForward(seconds: seconds)
    }

    func zeroCounter() {
        deck.zeroCounter()
    }

    // MARK: - Snapshot for UI

    struct Snapshot: Sendable {
        var position: TimeInterval
        var isPlaying: Bool
        var isPaused: Bool
        var isRecording: Bool
        var counterString: String
        var trackMeters: [Float]
        var tapeMetersDbFS: [Float]
    }

    func snapshot() -> Snapshot {
        let t = deck.transport
        return Snapshot(
            position: t.position,
            isPlaying: t.isPlaying,
            isPaused: t.isPaused,
            isRecording: t.isRecording,
            counterString: deck.counterString,
            trackMeters: deck.meters,
            tapeMetersDbFS: deck.readTapeMeters()
        )
    }

    // MARK: - Metering

    private func startMeterPolling() {
        meterPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self else { return }
                self.pollMeters()
            }
        }
    }

    private func pollMeters() {
        let levels = deck.readTapeMeters()
        onMeters?(levels)
    }
}
