import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
import PortaDSPKit

/// Thread-safe audio engine actor managing the PortaDSP processing pipeline.
/// Handles audio session setup, real-time DSP processing, and meter reading.
actor AudioEngineActor {

    // MARK: - State
    #if canImport(AVFoundation)
    private var engine: AVAudioEngine?
    private var portaUnit: AVAudioUnit?
    #endif
    private var dsp: PortaDSP?
    private var isRunning = false
    private var meterPollTask: Task<Void, Never>?

    // Callback for meter updates
    private var onMeters: (@Sendable ([Float]) -> Void)?

    // MARK: - Lifecycle

    func start(onMeters: @escaping @Sendable ([Float]) -> Void) async throws {
        guard !isRunning else { return }

        self.onMeters = onMeters

        #if canImport(AVFoundation)
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(48_000)
        try session.setActive(true)
        #endif

        let engine = AVAudioEngine()
        self.engine = engine

        // Create DSP instance
        let dsp = PortaDSP(sampleRate: 48_000, maxBlock: 512, tracks: 2)
        self.dsp = dsp
        dsp.update(PortaDSP.Params())

        // Create PortaDSP Audio Unit node via async wrapper
        let node: AVAudioUnit = try await withCheckedThrowingContinuation { continuation in
            PortaDSPAudioUnit.makeEngineNode(engine: engine) { unit, _, error in
                if let unit {
                    continuation.resume(returning: unit)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "Porta424", code: -1))
                }
            }
        }

        engine.attach(node)
        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        engine.connect(engine.inputNode, to: node, format: inputFormat)
        engine.connect(node, to: engine.mainMixerNode, format: inputFormat)
        self.portaUnit = node

        try engine.start()
        isRunning = true

        // Start meter polling at ~30Hz
        startMeterPolling()
        #endif
    }

    func stop() {
        meterPollTask?.cancel()
        meterPollTask = nil
        #if canImport(AVFoundation)
        engine?.stop()
        engine = nil
        portaUnit = nil
        #endif
        dsp = nil
        isRunning = false
    }

    // MARK: - Parameter Updates

    func updateDSP(_ state: DSPState) {
        let params = state.toParams()
        #if canImport(AudioToolbox)
        if let unit = portaUnit as? PortaDSPAudioUnit {
            unit.updateParameters(params)
            return
        }
        #endif
        dsp?.update(params)
    }

    func applyPreset(_ params: PortaDSP.Params) {
        #if canImport(AudioToolbox)
        if let unit = portaUnit as? PortaDSPAudioUnit {
            unit.updateParameters(params)
            return
        }
        #endif
        dsp?.update(params)
    }

    // MARK: - Volume Control

    func setMasterVolume(_ volume: Float) {
        #if canImport(AVFoundation)
        engine?.mainMixerNode.outputVolume = volume
        #endif
    }

    func setInputGain(_ gain: Float) {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setInputGain(gain)
        #endif
    }

    // MARK: - Metering

    private func startMeterPolling() {
        meterPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33)) // ~30Hz
                guard let self else { return }
                await self.pollMeters()
            }
        }
    }

    private func pollMeters() {
        #if canImport(AudioToolbox)
        guard let unit = portaUnit as? PortaDSPAudioUnit else { return }
        let levels = unit.readMeters()
        onMeters?(levels)
        #endif
    }

    // MARK: - State

    var running: Bool { isRunning }
}
