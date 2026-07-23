import SwiftUI
import Observation
import PortaDSPKit

/// Main view model for the Porta424 tape deck interface.
/// Mixer + transport are driven by `Porta424Engine` through `AudioEngineActor`.
@MainActor
@Observable
final class TapeDeckViewModel {

    // MARK: - Published State

    var dsp = DSPState()
    /// Tape speed / varispeed (0...1, center = 1.0×). Not a DSP bandwidth control.
    var pitch: Double = 0.5

    var transportMode: TransportMode = .stopped
    var meterL: Double = 0
    var meterR: Double = 0
    /// Per-track meters 0...1 (channels 1–4).
    var trackMeters: [Double] = [0, 0, 0, 0]
    var tapePosition: Double = 0
    var counterSeconds: Double = 0

    var channels: [ChannelState] = .defaultBoard

    var factoryPresets: [PresetItem] = []
    var userPresets: [PresetItem] = []
    var activePresetId: String?

    var isEngineRunning = false
    var engineError: String?

    // MARK: - Private

    private let engine = AudioEngineActor()
    private let presets = PresetManager()
    private var transportPollTask: Task<Void, Never>?
    private var dspSyncTask: Task<Void, Never>?
    private var mixerSyncTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func boot() async {
        factoryPresets = await presets.factoryPresets()
        userPresets = await presets.loadUserPresets()

        do {
            try await engine.start { [weak self] meters in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let l = meters.count > 0 ? meters[0] : -120
                    let r = meters.count > 1 ? meters[1] : -120
                    self.meterL = MixerMapping.normalizeDbFS(l)
                    self.meterR = MixerMapping.normalizeDbFS(r)
                }
            }
            isEngineRunning = true
            engineError = nil
            engine.updateDSP(dsp)
            engine.setChannels(channels)
            engine.setMaster(volume: dsp.masterVolume, pitch: pitch)
        } catch {
            isEngineRunning = false
            engineError = error.localizedDescription
            print("Porta424: Audio engine failed to start: \(error)")
        }

        if let first = factoryPresets.first {
            loadPreset(first)
        }

        startTransportPolling()
    }

    // MARK: - DSP Parameter Sync

    func syncDSP() {
        dspSyncTask?.cancel()
        dspSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            engine.updateDSP(dsp)
            engine.setMaster(volume: dsp.masterVolume, pitch: pitch)
        }
    }

    /// Push mixer board state into the audio graph.
    func syncMixer() {
        mixerSyncTask?.cancel()
        mixerSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            engine.setChannels(channels)
            engine.setMaster(volume: dsp.masterVolume, pitch: pitch)
        }
    }

    // MARK: - Transport Controls

    func togglePlay() {
        engine.transportPlayPause()
        refreshFromEngine()
        HapticEngine.transportTap()
    }

    func stop() {
        engine.transportStop()
        refreshFromEngine()
        HapticEngine.transportTap()
    }

    func toggleRecord() {
        engine.transportRecordToggle()
        refreshFromEngine()
        if transportMode == .recording {
            HapticEngine.recordEngage()
        } else {
            HapticEngine.transportTap()
        }
    }

    func rewind() {
        engine.rewind()
        refreshFromEngine()
        HapticEngine.transportTap()
    }

    func fastForward() {
        engine.fastForward()
        refreshFromEngine()
        HapticEngine.transportTap()
    }

    func resetCounter() {
        engine.zeroCounter()
        refreshFromEngine()
        tapePosition = 0
    }

    // MARK: - Mixer Controls

    func toggleArm(channelIndex: Int) {
        guard channels.indices.contains(channelIndex) else { return }
        channels[channelIndex].isArmed.toggle()
        HapticEngine.buttonPress()
        syncMixer()
    }

    func toggleSource(channelIndex: Int) {
        guard channels.indices.contains(channelIndex) else { return }
        channels[channelIndex].source.toggle()
        HapticEngine.buttonPress()
        syncMixer()
    }

    // MARK: - Counter String

    var counterString: String {
        let total = max(0, counterSeconds)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let seconds = Int(total) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    var isTransportActive: Bool {
        switch transportMode {
        case .playing, .recording, .rewinding, .fastForwarding: return true
        case .stopped, .paused: return false
        }
    }

    // MARK: - Preset Management

    func loadPreset(_ preset: PresetItem) {
        Task {
            let params: PortaDSP.Params?
            if preset.isFactory {
                params = await presets.factoryParameters(for: preset.id)
            } else {
                params = await presets.loadUserParameters(for: preset.id)
            }
            guard let params else { return }

            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                dsp = DSPState.from(params)
                activePresetId = preset.id
            }
            engine.applyPreset(params)
            engine.setMaster(volume: dsp.masterVolume, pitch: pitch)
        }
    }

    func saveCurrentAsPreset() {
        let name = "User Preset \(userPresets.count + 1)"
        Task {
            do {
                try await presets.saveUserPreset(name: name, parameters: dsp.toParams())
                userPresets = await presets.loadUserPresets()
            } catch {
                print("Porta424: Failed to save preset: \(error)")
            }
        }
    }

    // MARK: - Engine polling

    private func startTransportPolling() {
        transportPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self else { return }
                self.refreshFromEngine()
            }
        }
    }

    private func refreshFromEngine() {
        guard isEngineRunning else {
            meterL = max(0, meterL * 0.92 - 0.005)
            meterR = max(0, meterR * 0.92 - 0.005)
            return
        }

        let snap = engine.snapshot()
        counterSeconds = snap.position
        transportMode = MixerMapping.transportMode(
            isPlaying: snap.isPlaying,
            isPaused: snap.isPaused,
            isRecording: snap.isRecording
        )

        if snap.isPlaying && !snap.isPaused {
            tapePosition = min(1, tapePosition + 0.00005)
        }

        if snap.tapeMetersDbFS.count >= 2 {
            meterL = MixerMapping.normalizeDbFS(snap.tapeMetersDbFS[0])
            meterR = MixerMapping.normalizeDbFS(snap.tapeMetersDbFS[1])
        }

        let count = min(4, snap.trackMeters.count)
        if trackMeters.count < 4 { trackMeters = [0, 0, 0, 0] }
        for i in 0..<count {
            trackMeters[i] = Double(snap.trackMeters[i])
        }
    }
}
