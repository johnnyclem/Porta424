import AVFoundation
import Foundation
import PortaDSPKit
import SwiftUI
#if os(iOS)
import QuartzCore
#endif

@MainActor
final class AudioEngineManager: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentPresetName: String
    @Published private(set) var userPresets: [PortaPreset]
    @Published private(set) var meters: [Float] = Array(repeating: AudioEngineManager.meterFloor, count: 2)
    @Published var satDriveDb: Float = -6.0 {
        didSet {
            currentParams.satDriveDb = satDriveDb
            applyParameters()
        }
    }
    @Published var headBumpGainDb: Float = 2.0 {
        didSet {
            currentParams.headBumpGainDb = headBumpGainDb
            applyParameters()
        }
    }
    @Published var wowDepth: Float = 0.0006 {
        didSet {
            currentParams.wowDepth = wowDepth
            applyParameters()
        }
    }

    let factoryPresets = PortaPreset.factoryPresets

    private let engine = AVAudioEngine()
    private var dspUnit: PortaDSPAudioUnit?
    private var avUnit: AVAudioUnit?

    // Preset management
    private let presetStore: PortaPresetStore
    private var selectedFactoryPresetIndex: Int?
    private var currentParams = PortaDSP.Params()

    // Metering state
    private var channelCount = 0
    private var smoothedMeters: [Float] = Array(repeating: AudioEngineManager.meterFloor, count: 2)
    private var currentParams = PortaDSP.Params()
    #if os(iOS)
    private var displayLink: CADisplayLink?
    #else
    private var meterTimer: Timer?
    #endif

    static let meterFloor: Float = -120.0
    private static let smoothingFactor: Float = 0.25

    init(presetStore: PortaPresetStore = PortaPresetStore()) {
        self.presetStore = presetStore
        self.userPresets = presetStore.loadPresets()
        self.currentPresetName = "Default"
    }

    var statusText: String {
        switch state {
        case .idle:
            return "Engine idle"
        case .starting:
            return "Starting…"
        case .running:
            return "Engine running"
        case let .failed(message):
            return "Error: \(message)"
        }
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    // MARK: - Presets

    func applyFactoryPreset(at index: Int) {
        guard factoryPresets.indices.contains(index) else { return }
        selectedFactoryPresetIndex = index
        let preset = factoryPresets[index]
        currentParams = preset.parameters
        currentPresetName = preset.name
        applyParametersToDSP()
    }

    func applyUserPreset(_ preset: PortaPreset) {
        selectedFactoryPresetIndex = nil
        currentParams = preset.parameters
        currentPresetName = preset.name
        applyParametersToDSP()
    }

    func saveCurrentPreset(named name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var preset = PortaPreset(name: trimmed, author: ProcessInfo.processInfo.processName, parameters: currentParams)
        if let index = selectedFactoryPresetIndex {
            preset.parameters = factoryPresets[index].parameters
        }
        try presetStore.savePreset(preset)
        userPresets = presetStore.loadPresets()
        selectedFactoryPresetIndex = nil
        currentPresetName = preset.name
        currentParams = preset.parameters
        applyParametersToDSP()
    }

    func reloadUserPresets() {
        userPresets = presetStore.loadPresets()
    }

    // MARK: - Engine lifecycle

    func start() {
        guard state != .starting else { return }
        guard !isRunning else { return }
        #if os(iOS)
        state = .starting
        requestRecordPermission { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                if granted {
                    do {
                        try configureSession()
                        try await configureEngineGraph()
                    } catch {
                        stop()
                        state = .failed(error.localizedDescription)
                    }
                } else {
                    state = .failed("Microphone permission denied")
                }
            }
        }
        #else
        state = .starting
        Task { @MainActor in
            do {
                try await configureEngineGraph()
            } catch {
                stop()
                state = .failed(error.localizedDescription)
            }
        }
        #endif
    }

    func stop() {
        engine.stop()
        if let unit = avUnit {
            engine.detach(unit)
        }
        avUnit = nil
        dspUnit = nil
        stopMeterUpdates()
        channelCount = 0
        resetMeters()
        state = .idle
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }

    private func configureEngineGraph() async throws {
        let (node, dsp) = try await installDSPNode()
        avUnit = node
        dspUnit = dsp
        currentParams.satDriveDb = satDriveDb
        currentParams.headBumpGainDb = headBumpGainDb
        currentParams.wowDepth = wowDepth
        applyParametersToDSP()
        let format = engine.inputNode.inputFormat(forBus: 0)
        channelCount = Int(format.channelCount)
        prepareMeterBuffers()
        engine.connect(engine.inputNode, to: node, format: format)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        engine.prepare()
        try engine.start()
        state = .running
        applyParameters()
        startMeterUpdates()
    }

    private func installDSPNode() async throws -> (AVAudioUnit, PortaDSPAudioUnit) {
        try await withCheckedThrowingContinuation { continuation in
            PortaDSPAudioUnit.makeEngineNode(engine: engine) { node, dsp, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let node, let dsp else {
                    continuation.resume(throwing: PortaDSPAudioUnitError.failedToCreateEngineNode)
                    return
                }
                continuation.resume(returning: (node, dsp))
            }
        }
    }

    #if os(iOS)
    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(48_000)
        try session.setActive(true, options: [])
    }

    private func requestRecordPermission(_ completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    #endif

    private func applyParametersToDSP() {
        guard let dspUnit else { return }
        if let index = selectedFactoryPresetIndex {
            dspUnit.applyFactoryPreset(at: index)
        } else {
            dspUnit.updateParameters(currentParams)
        }
    }

    // MARK: - Metering

    private func startMeterUpdates() {
        stopMeterUpdates()
        pollMeters()
        #if os(iOS)
        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        #else
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.pollMeters()
        }
        #endif
    }

    private func stopMeterUpdates() {
        #if os(iOS)
        displayLink?.invalidate()
        displayLink = nil
        #else
        meterTimer?.invalidate()
        meterTimer = nil
        #endif
    }

    @objc
    private func handleDisplayLink(_ link: CADisplayLink) {
        pollMeters()
    }

    private func pollMeters() {
        guard state == .running, let dspUnit else { return }
        let rawMeters = dspUnit.readMeters()
        let channels = max(channelCount, 1)
        if meters.count != channels { meters = Array(repeating: Self.meterFloor, count: channels) }
        if smoothedMeters.count != channels { smoothedMeters = Array(repeating: Self.meterFloor, count: channels) }
        let limit = min(channels, rawMeters.count)
        var updated = smoothedMeters
        for index in 0..<limit {
            let clamped = max(Self.meterFloor, min(0, rawMeters[index]))
            let previous = smoothedMeters[index]
            let smoothed = previous + Self.smoothingFactor * (clamped - previous)
            updated[index] = smoothed
        }
        for index in limit..<channels {
            updated[index] = Self.meterFloor
        }
        smoothedMeters = updated
        meters = updated
    }

    private func prepareMeterBuffers() {
        let channels = max(channelCount, 1)
        meters = Array(repeating: Self.meterFloor, count: channels)
        smoothedMeters = meters
    }

    private func resetMeters() {
        if !meters.isEmpty {
            meters = Array(repeating: Self.meterFloor, count: meters.count)
        }
        smoothedMeters = meters
    }

    private func applyParameters() {
        guard let dspUnit else { return }
        dspUnit.updateParameters(currentParams)
    }
}