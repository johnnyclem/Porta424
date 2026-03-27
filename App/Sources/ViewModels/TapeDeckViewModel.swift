import SwiftUI
import Observation
import PortaDSPKit

/// Main view model for the Porta424 tape deck interface.
/// Uses Swift Observation (@Observable) for efficient SwiftUI updates
/// and actor-isolated audio engine for thread safety.
@MainActor
@Observable
final class TapeDeckViewModel {

    // MARK: - Published State

    var dsp = DSPState()
    var transportMode: TransportMode = .stopped
    var meterL: Double = 0
    var meterR: Double = 0
    var tapePosition: Double = 0     // 0...1
    var counterSeconds: Double = 0

    var factoryPresets: [PresetItem] = []
    var userPresets: [PresetItem] = []
    var activePresetId: String?

    var isEngineRunning = false

    // MARK: - Private

    private let engine = AudioEngineActor()
    private let presets = PresetManager()
    private var transportTimer: Task<Void, Never>?
    private var dspSyncTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func boot() async {
        // Load presets
        factoryPresets = await presets.factoryPresets()
        userPresets = await presets.loadUserPresets()

        // Start audio engine
        do {
            try await engine.start { [weak self] meters in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.meterL = Double(meters.count > 0 ? meters[0] : 0)
                    self.meterR = Double(meters.count > 1 ? meters[1] : 0)
                    // Normalize from dBFS (-60...0) to 0...1
                    self.meterL = max(0, min(1, (self.meterL + 60) / 60))
                    self.meterR = max(0, min(1, (self.meterR + 60) / 60))
                }
            }
            isEngineRunning = true
            await engine.updateDSP(dsp)
        } catch {
            print("Porta424: Audio engine failed to start: \(error)")
        }

        // Load default preset
        if let first = factoryPresets.first {
            loadPreset(first)
        }

        // Start transport timer
        startTransportTimer()
    }

    // MARK: - DSP Parameter Sync

    /// Called when any DSP parameter changes. Debounces updates to the audio thread.
    func syncDSP() {
        dspSyncTask?.cancel()
        dspSyncTask = Task {
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            await engine.updateDSP(dsp)
            await engine.setMasterVolume(Float(dsp.masterVolume))
            await engine.setInputGain(Float(dsp.inputGain))
        }
    }

    // MARK: - Transport Controls

    func togglePlay() {
        switch transportMode {
        case .stopped, .paused:
            transportMode = .playing
            HapticEngine.transportTap()
        case .playing:
            transportMode = .paused
            HapticEngine.transportTap()
        case .recording:
            transportMode = .playing
            HapticEngine.transportTap()
        case .rewinding, .fastForwarding:
            transportMode = .playing
            HapticEngine.transportTap()
        }
    }

    func stop() {
        transportMode = .stopped
        HapticEngine.transportTap()
    }

    func toggleRecord() {
        if transportMode == .recording {
            transportMode = .playing
        } else {
            transportMode = .recording
            HapticEngine.recordEngage()
        }
    }

    func rewind() {
        transportMode = .rewinding
        HapticEngine.transportTap()
    }

    func fastForward() {
        transportMode = .fastForwarding
        HapticEngine.transportTap()
    }

    func resetCounter() {
        counterSeconds = 0
        tapePosition = 0
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
            await engine.applyPreset(params)
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

    // MARK: - Transport Timer

    private func startTransportTimer() {
        transportTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33)) // ~30fps
                guard let self else { return }
                await self.tickTransport()
            }
        }
    }

    private func tickTransport() async {
        switch transportMode {
        case .playing, .recording:
            counterSeconds += 1.0 / 30.0
            tapePosition = min(1, tapePosition + 0.00005)
        case .rewinding:
            counterSeconds = max(0, counterSeconds - 3.0 / 30.0)
            tapePosition = max(0, tapePosition - 0.0002)
        case .fastForwarding:
            counterSeconds += 3.0 / 30.0
            tapePosition = min(1, tapePosition + 0.0002)
        case .stopped, .paused:
            break
        }

        // Simulate meter falloff when not playing
        if !isTransportActive {
            meterL = max(0, meterL * 0.92 - 0.005)
            meterR = max(0, meterR * 0.92 - 0.005)
        }

        // If engine isn't running, simulate meters
        if !isEngineRunning && isTransportActive {
            meterL = max(0.05, min(1, meterL * 0.9 + Double.random(in: 0.02...0.12)))
            meterR = max(0.05, min(1, meterR * 0.9 + Double.random(in: 0.02...0.12)))
        }
    }
}
