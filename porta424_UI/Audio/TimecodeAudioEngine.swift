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
    private let playerNode = AVAudioPlayerNode()
    private let mixer = AVAudioMixerNode()
    private var trackNodes: [AVAudioPlayerNode] = []
    private var trackBuffers: [AVAudioPCMBuffer] = []
    private var trackTaps: [AVAudioNodeTapBlock] = []
    private var cancellables = Set<AnyCancellable>()
    private let bufferSize: AVAudioFrameCount = 1024
    
    init() {
        setupAudioSession()
        setupGraph()
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
    
    // MARK: - Graph Setup
    private func setupGraph() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        
        // Main mixer (4 input busses)
        engine.attach(mixer)
        engine.attach(playerNode)
        
        // Connect input → mixer (bus 0)
        engine.connect(input, to: mixer, format: format)
        
        // Create 4 track players
        for i in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, fromBus: 0, toBus: AVAudioNodeBus(UInt32(i + 1)), format: format)
            trackNodes.append(player)
        }
        
        // Output
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        try? engine.start()
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
                // Duplicate input into up to 4 mono buffers and append to trackBuffers
                let channels = Int(min(4, buffer.format.channelCount))
                for ch in 0..<channels {
                    if let mono = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(commonFormat: buffer.format.commonFormat, sampleRate: buffer.format.sampleRate, channels: 1, interleaved: false)!, frameCapacity: buffer.frameCapacity) {
                        mono.frameLength = buffer.frameLength
                        if let src = buffer.floatChannelData, let dst = mono.floatChannelData {
                            let srcPtr = src[ch]
                            let dstPtr = dst[0]
                            let count = Int(buffer.frameLength)
                            dstPtr.initialize(from: srcPtr, count: count)
                        }
                        if self.trackBuffers.count <= ch { self.trackBuffers.append(mono) } else { self.trackBuffers[ch] = mono }
                    }
                }
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
    
    // MARK: - Transport Controls
    func play() {
        // Start playback; ensure engine is running
        if !engine.isRunning {
            try? engine.start()
        }
        // Schedule recorded buffers on trackNodes to loop
        for i in 0..<min(self.trackNodes.count, self.trackBuffers.count) {
            let node = self.trackNodes[i]
            if let format = node.outputFormat(forBus: 0) as AVAudioFormat?, let buf = self.trackBuffers[i].copy() as? AVAudioPCMBuffer {
                node.stop()
                node.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
            }
        }
        isRecording = false
        isPlaying = true
        playerNode.play()
        trackNodes.forEach { $0.play() }
        transportState = .playing
        startTimecodeTicking()
    }
    
    func pause() {
        // Pause playback/recording without clearing state permanently
        isPlaying = false
        isRecording = false
        playerNode.pause()
        trackNodes.forEach { $0.pause() }
        stopTimecodeTicking()
        if transportState == .pausedPlayback {
            transportState = .playing
            isPlaying = true
        } else if transportState == .pausedRecording {
            transportState = .recording
            isRecording = true
        } else if transportState == .playing {
            transportState = .pausedPlayback
        } else if transportState == .recording {
            transportState = .pausedRecording
        }
    }
    
    func stop() {
        // Stop everything and reset flags
        isPlaying = false
        isRecording = false
        playerNode.stop()
        trackNodes.forEach { $0.stop() }
        transportState = .stopped
        stopTimecodeTicking()
        resetToZero()
    }
    
    func record() {
        // Begin recording; implies playing
        if !engine.isRunning {
            try? engine.start()
        }
        self.trackBuffers.removeAll()
        isRecording = true
        isPlaying = true
        // Start transport nodes as needed when recording
        playerNode.play()
        trackNodes.forEach { $0.play() }
        transportState = .recording
        startTimecodeTicking()
    }
    
    func fastForward() {
        // Simulate fast forward transport
        if !engine.isRunning { try? engine.start() }
        isRecording = false
        isPlaying = true
        transportState = .fastForward
        playerNode.play()
        trackNodes.forEach { $0.play() }
        startTimecodeTicking()
    }
    
    func rewind() {
        // Simulate rewind transport
        if !engine.isRunning { try? engine.start() }
        isRecording = false
        isPlaying = true
        transportState = .rewinding
        playerNode.play()
        trackNodes.forEach { $0.play() }
        startTimecodeTicking()
    }
    
    func toggleDolbyB(track: Int) {
        dolbyBEnabled[track].toggle()
        // In real app: insert DolbyBProcessor node
    }
}
