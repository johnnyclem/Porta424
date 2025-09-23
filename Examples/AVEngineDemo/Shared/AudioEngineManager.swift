import AVFoundation
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
    @Published private(set) var meters: [Float] = Array(repeating: AudioEngineManager.meterFloor, count: 2)

    private let engine = AVAudioEngine()
    private var dspUnit: PortaDSPAudioUnit?
    private var avUnit: AVAudioUnit?
    private var channelCount = 0
    private var smoothedMeters: [Float] = Array(repeating: AudioEngineManager.meterFloor, count: 2)
#if os(iOS)
    private var displayLink: CADisplayLink?
#else
    private var meterTimer: Timer?
#endif

    static let meterFloor: Float = -120.0
    private static let smoothingFactor: Float = 0.25

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
        let format = engine.inputNode.inputFormat(forBus: 0)
        channelCount = Int(format.channelCount)
        prepareMeterBuffers()
        engine.connect(engine.inputNode, to: node, format: format)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        engine.prepare()
        try engine.start()
        state = .running
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
}
