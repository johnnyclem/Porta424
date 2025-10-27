//
//  AudioEngine.swift
//  porta424_UI
//
//  Created by John Clem on 10/22/25.
//

import AVFoundation
import Combine
import SwiftUI

// MARK: - Global Audio Engine
class TimecodeAudioEngine: ObservableObject {
    static let shared = TimecodeAudioEngine()
    
    // MARK: Public State
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var trackLevels: [Float] = [0, 0, 0, 0]   // 0.0 – 1.2
    @Published var dolbyBEnabled: [Bool] = [false, false, false, false]
    @Published var trackGains: [Float] = [1.0, 1.0, 1.0, 1.0]
    @Published var controlKnobs: [Double] = [0.6, 0.4, 0.5, 0.3]
    
    // I/O device selection and routing
    @Published var availableInputs: [AVAudioSessionPortDescription] = []
    @Published var availableOutputs: [AVAudioSessionPortDescription] = []
    @Published var selectedInput: AVAudioSessionPortDescription?
    @Published var selectedOutput: AVAudioSessionPortDescription?

    // Record-arming per track (REC ACTIVE)
    @Published var recArmed: [Bool] = [false, false, false, false]

    // Map: input channel index -> track index (0..3)
    @Published var inputRouting: [Int: Int] = [:]
    
    enum RecordSource { case auto, input, bounce }
    @Published var recordSource: RecordSource = .auto
    @Published var inputMonitoringEnabled: Bool = true
    
    // Timecode / Tape
    @Published var elapsedSeconds: Int = 0 // 0...tapeLengthSeconds
    @Published var rtzEnabled: Bool = true
    @Published var highSpeed: Bool = false // false = 14 min, true = 7 min
    @Published var displayTimecode: String = "000" // formatted 3 digits
    private var timecodeTimer: Timer?
    private var lastTick: Date?
    
    enum TransportState {
        case stopped
        case playing
        case recording
        case fastForward
        case rewinding
        case pausedRecording
        case pausedPlayback
    }
    
    @Published var transportState: TransportState = .stopped
    
    var tapeLengthSeconds: Int {
        return (highSpeed ? 7 * 60 : 14 * 60)
    }
    
    // MARK: Private
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    
    // Routing/bounce nodes
    private let inputMixer = AVAudioMixerNode()   // mixes all hardware input channels
    private let bounceMixer = AVAudioMixerNode()  // mixes existing track playback for bounce
    
    private var trackNodes: [AVAudioPlayerNode] = []
    private var trackBuffers: [AVAudioPCMBuffer] = []
    private var trackTaps: [AVAudioNodeTapBlock] = []
    private var cancellables = Set<AnyCancellable>()
    private let bufferSize: AVAudioFrameCount = 1024

    private var trackFormat: AVAudioFormat?
    
    init() {
        setupAudioSession()
        setupGraph()
        
        refreshAvailableIO()
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshAvailableIO()
        }

        $selectedInput
            .sink { [weak self] _ in self?.applySelectedIO() }
            .store(in: &cancellables)
        $selectedOutput
            .sink { [weak self] _ in self?.applySelectedIO() }
            .store(in: &cancellables)
        
        $inputMonitoringEnabled
            .sink { [weak self] _ in self?.applyMonitoringConnection() }
            .store(in: &cancellables)
        
        // Set initial mixer input volumes from trackGains
        for _ in 0..<4 {
            mixer.outputVolume = 1.0
            mixer.volume = 1.0
        }
        // Apply gains to trackNodes when trackGains changes
        $trackGains
            .receive(on: DispatchQueue.main)
            .sink { [weak self] gains in
                guard let self = self else { return }
                for (i, g) in gains.enumerated() where i < self.trackNodes.count {
                    self.trackNodes[i].volume = g
                }
            }
            .store(in: &cancellables)
        
        startMetering()
        
        // Keep displayTimecode in sync
        $elapsedSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in
                self?.displayTimecode = String(format: "%03d", max(0, min(999, v)))
            }
            .store(in: &cancellables)

        $highSpeed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.elapsedSeconds > self.tapeLengthSeconds { self.elapsedSeconds = self.tapeLengthSeconds }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Audio Session
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [AVAudioSession.CategoryOptions.allowBluetoothHFP, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }
    
    // MARK: - IO Enumeration / Selection
    private func refreshAvailableIO() {
        let session = AVAudioSession.sharedInstance()
        availableInputs = session.availableInputs ?? []
        let currentRoute = session.currentRoute
        availableOutputs = currentRoute.outputs
        if selectedInput == nil { selectedInput = session.preferredInput ?? session.availableInputs?.first }
        if selectedOutput == nil { selectedOutput = availableOutputs.first }
    }

    private func applySelectedIO() {
        let session = AVAudioSession.sharedInstance()
        do {
            if let input = selectedInput {
                try session.setPreferredInput(input)
            }
            // Output selection is system-managed on iOS; we keep selectedOutput for UI but cannot force it in most cases.
            try session.setActive(true)
        } catch {
            print("Failed to apply selected IO: \(error)")
        }
    }
    
    private func applyMonitoringConnection() {
        // Reconnect input monitoring depending on toggle
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        // First disconnect inputMixer from mixer bus 0 if connected
        engine.disconnectNodeOutput(inputMixer)
        // Always keep input -> inputMixer
        if inputMixer.engine == nil { engine.attach(inputMixer) }
        engine.connect(input, to: inputMixer, format: format)
        if inputMonitoringEnabled {
            engine.connect(inputMixer, to: mixer, fromBus: 0, toBus: 0, format: format)
        }
        if !engine.isRunning { try? engine.start() }
    }
    
    // MARK: - Graph Setup
    private func setupGraph() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        
        // Main mixer (4 input busses)
        engine.attach(mixer)
        // Removed engine.attach(playerNode)
        engine.attach(inputMixer)
        engine.attach(bounceMixer)
        
        // Input path: input -> inputMixer (sums all input channels)
        engine.connect(input, to: inputMixer, format: format)
        
        // Create a mono format for track playback/recording to keep channel counts consistent
        let trackFormat = AVAudioFormat(commonFormat: format.commonFormat,
                                        sampleRate: format.sampleRate,
                                        channels: 1,
                                        interleaved: false)
        self.trackFormat = trackFormat

        // Create 4 track players, each connected to a dedicated mixer input bus with mono format
        for i in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player,
                           to: mixer,
                           fromBus: 0,
                           toBus: AVAudioNodeBus(UInt32(i + 1)),
                           format: trackFormat)
            trackNodes.append(player)
        }
        
        // Bounce path: all track players mix into bounceMixer (already implicit via connections), then bounceMixer -> mixer bus 0
        engine.connect(bounceMixer, to: mixer, fromBus: 0, toBus: 0, format: format)

        // Also feed inputMixer -> mixer bus 0 so live input is audible when monitoring
        applyMonitoringConnection()
        
        // Output
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        // Removed engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        try? engine.start()
    }
    
    // Ensures the engine is running and the graph is intact before starting any nodes
    private func ensureEngineRunning() {
        if !engine.isRunning {
            do { try engine.start() } catch { print("AVAudioEngine start error: \(error)") }
        }
    }

    // MARK: - Metering
    private func startMetering() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let levels = self.calculateRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.trackLevels = levels
            }
            if self.isRecording {
                self.captureRecordingSource(from: buffer)
            }
        }
    }
    
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [0,0,0,0] }
        let frameCount = Int(buffer.frameLength)
        var rms: [Float] = [0, 0, 0, 0]
        
        for channel in 0..<min(4, buffer.format.channelCount) {
            let samples = channelData[Int(channel)]
            var sum: Float = 0
            for i in 0..<frameCount {
                let s = samples[i]
                sum += s * s
            }
            let mean = sum / Float(frameCount)
            rms[Int(channel)] = sqrt(mean) * 2.0  // scale to ~1.2
        }
        return rms
    }
    
    // MARK: - Recording Source Selection
    private func captureRecordingSource(from buffer: AVAudioPCMBuffer) {
        let useInput: Bool
        switch recordSource {
        case .input:
            useInput = true
        case .bounce:
            useInput = false
        case .auto:
            useInput = buffer.format.channelCount > 0
        }
        if useInput {
            // Hardware input path: map input channels to armed tracks
            let channels = Int(buffer.format.channelCount)
            guard let trackFormat = self.trackFormat else { return }
            for (inputCh, trackIdx) in inputRouting {
                guard trackIdx >= 0 && trackIdx < 4 && recArmed[trackIdx] else { continue }
                if inputCh < channels {
                    guard let mono = AVAudioPCMBuffer(pcmFormat: trackFormat, frameCapacity: buffer.frameCapacity) else { continue }
                    mono.frameLength = buffer.frameLength
                    if let src = buffer.floatChannelData, let dst = mono.floatChannelData {
                        let srcPtr = src[inputCh]
                        let dstPtr = dst[0]
                        let count = Int(buffer.frameLength)
                        dstPtr.assign(from: srcPtr, count: count)
                    }
                    if self.trackBuffers.count <= trackIdx {
                        // pad up to trackIdx
                        while self.trackBuffers.count < trackIdx { self.trackBuffers.append(AVAudioPCMBuffer(pcmFormat: trackFormat, frameCapacity: 1)!) }
                        self.trackBuffers.append(mono)
                    } else {
                        self.trackBuffers[trackIdx] = mono
                    }
                }
            }
        } else {
            // Bounce path: if no input, mix audible trackNodes into a mono buffer and route to first armed track
            guard let trackFormat = self.trackFormat else { return }
            guard let firstArmed = recArmed.firstIndex(of: true) else { return }
            // Simple bounce: sum trackBuffers into one mono buffer
            // If no trackBuffers yet, nothing to bounce
            guard !trackBuffers.isEmpty else { return }
            let capacity = trackBuffers.map { Int($0.frameLength) }.max() ?? 0
            guard capacity > 0, let mono = AVAudioPCMBuffer(pcmFormat: trackFormat, frameCapacity: AVAudioFrameCount(capacity)) else { return }
            mono.frameLength = AVAudioFrameCount(capacity)
            if let dst = mono.floatChannelData {
                let dstPtr = dst[0]
                // zero
                for i in 0..<capacity { dstPtr[i] = 0 }
                // sum
                for buf in trackBuffers {
                    guard let src = buf.floatChannelData else { continue }
                    let srcPtr = src[0]
                    let count = min(Int(buf.frameLength), capacity)
                    for i in 0..<count { dstPtr[i] += srcPtr[i] }
                }
            }
            if self.trackBuffers.count <= firstArmed {
                while self.trackBuffers.count < firstArmed { self.trackBuffers.append(AVAudioPCMBuffer(pcmFormat: trackFormat, frameCapacity: 1)!) }
                self.trackBuffers.append(mono)
            } else {
                self.trackBuffers[firstArmed] = mono
            }
        }
    }
    
    // MARK: - Timecode / Playhead
    private func startTimecodeTicking() {
        stopTimecodeTicking()
        lastTick = Date()
        timecodeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.current.add(timecodeTimer!, forMode: .common)
    }

    private func stopTimecodeTicking() {
        timecodeTimer?.invalidate()
        timecodeTimer = nil
        lastTick = nil
    }

    private func tick() {
        guard let last = lastTick else { lastTick = Date(); return }
        let now = Date()
        let dt = now.timeIntervalSince(last)
        lastTick = now

        // Determine transport rate in seconds per second
        let rate: Double
        switch transportState {
        case .playing, .recording:
            rate = 1.0
        case .fastForward:
            rate = 3.33 // arbitrary faster rate
        case .rewinding:
            rate = -3.33
        case .stopped:
            rate = 0.0
        case .pausedPlayback:
            rate = 0.0
        case .pausedRecording:
            rate = 0.0
        }

        if rate == 0 { return }

        // Advance playhead by scaled amount
        var newValue = Double(elapsedSeconds) + rate * dt

        // Clamp to tape bounds
        let maxLen = Double(tapeLengthSeconds)
        if newValue >= maxLen {
            newValue = maxLen
            pause() // auto-stop at end
        } else if newValue < 0 {
            if rtzEnabled {
                newValue = 0
                pause() // auto-stop at zero when RTZ
            } else {
                // rollover behavior: 0 -> 999 countdown visual, but enforce tape bounds
                // We emulate wrap within 0...999 for display, but keep elapsed clamped at 0
                newValue = 0
            }
        }

        elapsedSeconds = Int(newValue.rounded(.towardZero))
    }

    func resetToZero() {
        elapsedSeconds = 0
    }
    
    // Start a node only if it has something scheduled; avoids disconnected-state exceptions
    private func startIfScheduled(_ node: AVAudioPlayerNode) {
        // AVAudioPlayerNode has no direct API to query schedule state, so we rely on our own scheduling path.
        // This helper is here for future extension and documentation purposes.
        node.play()
    }

    // MARK: - Transport Controls
    func play() {
        if transportState == .playing { return }
        // Start playback; ensure engine is running
        ensureEngineRunning()
        // Schedule recorded buffers on trackNodes to loop
        for i in 0..<min(self.trackNodes.count, self.trackBuffers.count) {
            let node = self.trackNodes[i]
            guard let buf = (self.trackBuffers[i].copy() as? AVAudioPCMBuffer),
                  buf.frameLength > 0 else { continue }
            let nodeFormat = node.outputFormat(forBus: 0)
            guard nodeFormat.channelCount == buf.format.channelCount else { continue }
            node.stop()
            node.reset()
            node.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
        }
        // If resuming from pause, keep existing schedules; otherwise we just scheduled fresh

        isRecording = false
        let anyScheduled = (0..<min(self.trackNodes.count, self.trackBuffers.count)).contains { idx in
            let buf = self.trackBuffers[idx]
            return buf.frameLength > 0
        }
        if anyScheduled {
            isPlaying = true
            trackNodes.forEach { node in
                startIfScheduled(node)
            }
            transportState = .playing
            startTimecodeTicking()
        } else {
            // Nothing to play; remain stopped
            isPlaying = false
            transportState = .stopped
        }
    }
    
    func pause() {
        // Pause playback/recording without clearing state permanently
        trackNodes.forEach { $0.pause() }
        stopTimecodeTicking()

        switch transportState {
        case .playing:
            transportState = .pausedPlayback
            isPlaying = false
            isRecording = false
        case .recording:
            transportState = .pausedRecording
            isPlaying = false
            isRecording = false
        case .pausedPlayback, .pausedRecording, .fastForward, .rewinding, .stopped:
            // Remain paused; no state flip-flop
            isPlaying = false
            isRecording = false
        }
    }
    
    func stop() {
        // Stop everything and reset flags
        isPlaying = false
        isRecording = false
        trackNodes.forEach { $0.stop() }
        transportState = .stopped
        stopTimecodeTicking()
        // Do not auto-reset timecode here; leave position for user feedback
    }
    
    func record() {
        // Begin recording; implies transport running, but we do not start playback nodes.
        ensureEngineRunning()
        self.trackBuffers.removeAll()
        // Ensure playback nodes are not running while we record; we capture from input tap.
        trackNodes.forEach { $0.stop(); $0.reset() }
        isRecording = true
        isPlaying = false
        transportState = .recording
        startTimecodeTicking()
    }
    
    func fastForward() {
        // Simulate fast forward transport without starting audio nodes
        ensureEngineRunning()
        isRecording = false
        isPlaying = true
        transportState = .fastForward
        // Keep audio nodes paused to avoid disconnected-state crashes
        trackNodes.forEach { $0.pause() }
        startTimecodeTicking()
    }
    
    func rewind() {
        // Simulate rewind transport without starting audio nodes
        ensureEngineRunning()
        isRecording = false
        isPlaying = true
        transportState = .rewinding
        // Keep audio nodes paused to avoid disconnected-state crashes
        trackNodes.forEach { $0.pause() }
        startTimecodeTicking()
    }
    
    func toggleDolbyB(track: Int) {
        dolbyBEnabled[track].toggle()
        // In real app: insert DolbyBProcessor node
    }

    // MARK: - Routing APIs
    func setRecArmed(track: Int, armed: Bool) {
        guard (0..<4).contains(track) else { return }
        recArmed[track] = armed
    }

    func routeInputChannel(_ inputChannel: Int, toTrack track: Int) {
        guard inputChannel >= 0, (0..<4).contains(track) else { return }
        inputRouting[inputChannel] = track
    }

    func clearRouting() { inputRouting.removeAll() }
    
    func setRecordSource(_ source: RecordSource) { self.recordSource = source }
}

