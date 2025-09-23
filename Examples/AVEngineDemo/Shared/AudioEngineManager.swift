import AVFoundation
import PortaDSPKit
import SwiftUI

@MainActor
final class AudioEngineManager: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var hissLevelDbFS: Float = PortaDSP.Params().hissLevelDbFS {
        didSet {
            pendingParams.hissLevelDbFS = hissLevelDbFS
            guard let dspUnit else { return }
            updateHissParameter(on: dspUnit)
        }
    }

    private let engine = AVAudioEngine()
    private var dspUnit: PortaDSPAudioUnit?
    private var avUnit: AVAudioUnit?
    private var pendingParams = PortaDSP.Params()

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
        state = .idle
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }

    private func configureEngineGraph() async throws {
        let (node, dsp) = try await installDSPNode()
        avUnit = node
        dspUnit = dsp
        applyPendingParametersToDSP()
        let format = engine.inputNode.inputFormat(forBus: 0)
        engine.connect(engine.inputNode, to: node, format: format)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        engine.prepare()
        try engine.start()
        state = .running
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

    private func applyPendingParametersToDSP() {
        guard let dspUnit else { return }
        dspUnit.updateParameters(pendingParams)
        logHissRoundTrip(on: dspUnit)
    }

    private func updateHissParameter(on dsp: PortaDSPAudioUnit) {
        dsp.parameterTree?
            .parameter(withAddress: PortaDSPAudioUnit.ParameterID.hissLevelDbFS.address)?
            .setValue(hissLevelDbFS, originator: nil)
        logHissRoundTrip(on: dsp)
    }

    private func logHissRoundTrip(on dsp: PortaDSPAudioUnit) {
        let snapshot = dsp.currentParameters()
        print(
            String(
                format: "[PortaDSPAudioUnit] hissLevelDbFS set to %.1f dBFS (cached %.1f dBFS)",
                hissLevelDbFS,
                snapshot.hissLevelDbFS
            )
        )
    }
}
