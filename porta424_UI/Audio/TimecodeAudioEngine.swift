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
    
    // Punch in/out controls
    @Published var punchInEnabled: Bool = false
    @Published var punchInPointSeconds: Double? = nil
    @Published var punchOutPointSeconds: Double? = nil

    // Timecode / Tape
    @Published var elapsedSeconds: Int = 0 {
        didSet {
            print("elapsed seconds: \(elapsedSeconds)")
            // Keep displayTimecode in sync with a 3-digit format
            displayTimecode = String(format: "%03d", max(0, min(999, elapsedSeconds)))
        }
    }
    @Published var rtzEnabled: Bool = true
    @Published var highSpeed: Bool = false // false = 14 min, true = 7 min
    @Published var displayTimecode: String = "000" // formatted 3 digits
    @Published var micAuthorized: Bool = false
    
    private var timecodeTimer: Timer?
    private var lastTick: Date?
    private var inputTapInstalled = false
    private var mainMixerTapFallback = false
    
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
        
    var isPaused: Bool {
        get {
            transportState == .pausedPlayback || transportState == .pausedRecording
        }
        set {
            switch previousNonPauseState {
            case .playing:
                transportState = .pausedPlayback
            case .recording:
                transportState = .pausedRecording
            default:
                transportState = previousNonPauseState
            }
        }
    }
    private var previousNonPauseState: TransportState = .stopped

    // 3-digit rolling timecode 000-999
    @Published var currentTapeTimecode: Int = 0 // 0...999
    
    var tapeLengthSeconds: Int {
        return (highSpeed ? 7 * 60 : 14 * 60)
    }
    
    // UI-facing toggle with persistence; mirrors into internal flag
    @Published var perTrackModeEnabled: Bool = UserDefaults.standard.bool(forKey: "usePerTrackFiles") {
        didSet {
            usePerTrackFiles = perTrackModeEnabled
            UserDefaults.standard.set(perTrackModeEnabled, forKey: "usePerTrackFiles")
            // Rebuild file targets without destroying existing audio by default
            stop()
            prepareProjectFile(overwrite: false)
        }
    }
    private var usePerTrackFiles: Bool = UserDefaults.standard.bool(forKey: "usePerTrackFiles")
    
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
    
    // Project recording file
    private var projectFileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("DefaultProject.caf")
    }()
    private var projectFile: AVAudioFile?
    private var fileSampleRate: Double = 44100.0
    private var fileFormat: AVAudioFormat?
    
    // Playback state
    private var playbackFile: AVAudioFile?
    private var playbackStartFrame: AVAudioFramePosition = 0

    // Per-track file mode (optional). Default: single project file.
    private var trackFileURLs: [URL] = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return (0..<4).map { docs.appendingPathComponent("Track\($0+1).caf") }
    }()
    private var trackWriteFiles: [AVAudioFile?] = Array(repeating: nil, count: 4)
    private var trackReadFiles: [AVAudioFile?] = Array(repeating: nil, count: 4)
    
    // Punch session state
    private var writeStartFrame: AVAudioFramePosition?
    private var writeEndFrame: AVAudioFramePosition?
    private var hasPositionedForPunch: Bool = false
    
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
                let clamped = max(0, min(999, v))
                self?.currentTapeTimecode = clamped
            }
            .store(in: &cancellables)

        $highSpeed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.elapsedSeconds > self.tapeLengthSeconds { self.elapsedSeconds = self.tapeLengthSeconds }
            }
            .store(in: &cancellables)
        
        // Prepare a default project file for writing
        prepareProjectFile()
        
        // Sync internal flag with published property and ensure files reflect persisted choice
        usePerTrackFiles = perTrackModeEnabled
        prepareProjectFile(overwrite: false)
    }
    
    // MARK: - Audio Session
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("Audio session error (initial): \(error)")
        }
        session.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.micAuthorized = granted
                if !granted {
                    print("Microphone permission not granted. Recording and metering will be disabled.")
                } else {
                    print("Microphone permission granted.")
                    self?.installInputTapIfNeeded()
                    do { try session.setActive(true) } catch { print("Audio session error (activate after permission): \(error)") }
                }
            }
        }
    }
    
    // MARK: - IO Enumeration / Selection
    private func refreshAvailableIO() {
        let session = AVAudioSession.sharedInstance()
        availableInputs = session.availableInputs ?? []
        let currentRoute = session.currentRoute
        availableOutputs = currentRoute.outputs
        
        let input = engine.inputNode
        let inFmt = input.inputFormat(forBus: 0)
        print("Route inputs=\(availableInputs.map{ $0.portName }), outputs=\(availableOutputs.map{ $0.portName }), input ch=\(inFmt.channelCount)")
        
        if selectedInput == nil { selectedInput = session.preferredInput ?? session.availableInputs?.first }
        if selectedOutput == nil { selectedOutput = availableOutputs.first }
        installInputTapIfNeeded()
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
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        let hasInput = format.channelCount > 0
        if inputMixer.engine == nil { engine.attach(inputMixer) }
        if mixer.engine == nil { engine.attach(mixer) }
        // Always keep input -> inputMixer
        let inputOutputs = engine.outputConnectionPoints(for: input, outputBus: 0)
        if !inputOutputs.contains(where: { $0.node === inputMixer }) {
            engine.connect(input, to: inputMixer, format: format)
        }
        // Conditionally connect monitoring to main mixer when we have input channels
        if inputMonitoringEnabled && hasInput {
            let inputMixerOutputs = engine.outputConnectionPoints(for: inputMixer, outputBus: 0)
            if !inputMixerOutputs.contains(where: { $0.node === mixer }) {
                engine.connect(inputMixer, to: mixer, fromBus: 0, toBus: 0, format: format)
            }
        } else {
            // Disconnect monitoring path if present
            engine.disconnectNodeOutput(inputMixer)
            // Ensure input remains connected to inputMixer
            let inputOutputsAfterDisconnect = engine.outputConnectionPoints(for: input, outputBus: 0)
            if !inputOutputsAfterDisconnect.contains(where: { $0.node === inputMixer }) {
                engine.connect(input, to: inputMixer, format: format)
            }
        }
        installInputTapIfNeeded()
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
//        engine.connect(mixer, to: engine.mainMixerNode, format: format)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        // Removed engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        try? engine.start()
        installInputTapIfNeeded()
    }
    
    // Ensures the engine is running and the graph is intact before starting any nodes
    private func ensureEngineRunning() {
        if !engine.isRunning {
            do { try engine.start() } catch { print("AVAudioEngine start error: \(error)") }
        }
    }

    // MARK: - Project File Handling
    private func prepareProjectFile(overwrite: Bool = true) {
        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        // Mono target format for files
        let monoFormat = AVAudioFormat(commonFormat: inFormat.commonFormat,
                                       sampleRate: inFormat.sampleRate,
                                       channels: 1,
                                       interleaved: false)
        self.fileFormat = monoFormat
        self.fileSampleRate = monoFormat?.sampleRate ?? inFormat.sampleRate

        if usePerTrackFiles {
            // Prepare per-track files
            for i in 0..<4 {
                let url = trackFileURLs[i]
                if overwrite, FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
                do {
                    if let f = monoFormat {
                        trackWriteFiles[i] = try AVAudioFile(forWriting: url, settings: f.settings)
                    } else {
                        trackWriteFiles[i] = try AVAudioFile(forWriting: url, settings: inFormat.settings)
                    }
                } catch {
                    print("Failed to create track file #\(i+1): \(error)")
                    trackWriteFiles[i] = nil
                }
            }
            // Clear single project file
            projectFile = nil
        } else {
            // Prepare single project file
            if overwrite, FileManager.default.fileExists(atPath: projectFileURL.path) {
                try? FileManager.default.removeItem(at: projectFileURL)
            }
            do {
                if let f = monoFormat {
                    self.projectFile = try AVAudioFile(forWriting: projectFileURL, settings: f.settings)
                } else {
                    self.projectFile = try AVAudioFile(forWriting: projectFileURL, settings: inFormat.settings)
                }
            } catch {
                print("Failed to create project file: \(error)")
                self.projectFile = nil
            }
            // Clear per-track files
            for i in 0..<4 { trackWriteFiles[i] = nil }
        }
    }

    private func writeToProjectFile(from buffer: AVAudioPCMBuffer) {
        guard let file = projectFile else { return }
        // Ensure mono buffer matching file's processing format
        let mono: AVAudioPCMBuffer
        let chosenFormat: AVAudioFormat = (file.processingFormat.channelCount == 1) ? file.processingFormat : file.fileFormat
        if chosenFormat.channelCount == 1 {
            mono = downmixToMono(buffer: buffer, targetFormat: chosenFormat)
        } else {
            // Fallback: derive a mono format from incoming buffer
            let targetFormat = AVAudioFormat(commonFormat: buffer.format.commonFormat,
                                             sampleRate: buffer.format.sampleRate,
                                             channels: 1,
                                             interleaved: false)!
            mono = downmixToMono(buffer: buffer, targetFormat: targetFormat)
        }
        do {
            try file.write(from: mono)
        } catch {
            print("AVAudioFile write error: \(error)")
        }
    }

    private func writePerTrack(from buffer: AVAudioPCMBuffer) {
        // For each input routing mapping, write armed track with corresponding input channel downmixed to mono
        // If no routing provided for a track, default to channel 0 when armed.
        let channels = Int(buffer.format.channelCount)
        for trackIdx in 0..<4 {
            guard recArmed[trackIdx] else { continue }
            let inputCh = inputRouting.first(where: { $0.value == trackIdx })?.key ?? 0
            guard inputCh < channels else { continue }
            guard let file = trackWriteFiles[trackIdx] else { continue }
            // Build a mono buffer for this track using the selected channel
            let targetFormat = file.processingFormat.channelCount == 1 ? file.processingFormat : file.fileFormat
            guard let mono = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: buffer.frameCapacity) else { continue }
            mono.frameLength = buffer.frameLength
            if let src = buffer.floatChannelData, let dst = mono.floatChannelData {
                let srcPtr = src[inputCh]
                let dstPtr = dst[0]
                let count = Int(buffer.frameLength)
                dstPtr.update(from: srcPtr, count: count)
            }
            do { try file.write(from: mono) } catch { print("Track #\(trackIdx+1) write error: \(error)") }
        }
    }

    private func downmixToMono(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer {
        let frameCount = buffer.frameLength
        guard let mono = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return buffer }
        mono.frameLength = frameCount
        guard let src = buffer.floatChannelData, let dst = mono.floatChannelData else { return buffer }
        let channels = Int(buffer.format.channelCount)
        let dstPtr = dst[0]
        let count = Int(frameCount)
        // Zero out destination
        for i in 0..<count { dstPtr[i] = 0 }
        // Sum channels, then average
        for ch in 0..<channels {
            let srcPtr = src[ch]
            for i in 0..<count { dstPtr[i] += srcPtr[i] }
        }
        if channels > 0 {
            let inv = 1.0 / Float(channels)
            for i in 0..<count { dstPtr[i] *= inv }
        }
        return mono
    }
    
    // MARK: - Playback from Project File
    private func startPlaybackFromCurrentPosition() {
        let startSeconds = Double(elapsedSeconds)
        if usePerTrackFiles {
            // Open read files if needed and schedule on each track node
            for i in 0..<4 {
                do {
                    if trackReadFiles[i] == nil {
                        let url = trackFileURLs[i]
                        if FileManager.default.fileExists(atPath: url.path) {
                            trackReadFiles[i] = try AVAudioFile(forReading: url)
                        }
                    }
                } catch {
                    print("Failed to open track file #\(i+1) for playback: \(error)")
                    trackReadFiles[i] = nil
                }
            }
            // Determine common sample rate (from first available file)
            let sr = trackReadFiles.compactMap { $0?.processingFormat.sampleRate }.first ?? fileSampleRate
            let startFrame = AVAudioFramePosition(startSeconds * sr)
            playbackStartFrame = startFrame
            for i in 0..<min(4, trackNodes.count) {
                guard let file = trackReadFiles[i] else { continue }
                let length = file.length
                let start = max(0, min(startFrame, length))
                let remaining = AVAudioFrameCount(max(0, length - start))
                guard remaining > 0 else { continue }
                let node = trackNodes[i]
                node.stop(); node.reset()
                node.scheduleSegment(file, startingFrame: start, frameCount: remaining, at: nil, completionHandler: nil)
                node.play()
            }
        } else {
            // Single-file playback on first node
            do {
                if playbackFile == nil {
                    playbackFile = try AVAudioFile(forReading: projectFileURL)
                }
            } catch {
                print("Failed to open project file for playback: \(error)")
                playbackFile = nil
            }
            guard let file = playbackFile else { return }
            let sr = file.processingFormat.sampleRate
            let requestedStartFrame = AVAudioFramePosition(startSeconds * sr)
            playbackStartFrame = max(0, min(requestedStartFrame, file.length))
            let remainingFrames = AVAudioFrameCount(max(0, file.length - playbackStartFrame))
            guard remainingFrames > 0 else { return }
            guard let firstNode = trackNodes.first else { return }
            firstNode.stop(); firstNode.reset()
            firstNode.scheduleSegment(file, startingFrame: playbackStartFrame, frameCount: remainingFrames, at: nil, completionHandler: { [weak self] in
                DispatchQueue.main.async { self?.pause() }
            })
            firstNode.play()
        }
    }

    // MARK: - Metering
    private func installInputTapIfNeeded() {
        guard !inputTapInstalled else { return }
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        if format.channelCount == 0 {
            // Fallback for Simulator or routes with no input: tap mainMixerNode for metering/debug
            print("Input has 0 channels; installing fallback tap on mainMixerNode for metering. bufferSize: \(bufferSize)")
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
                guard let self = self else { return }
                let levels = self.calculateRMS(buffer: buffer)
                DispatchQueue.main.async { self.trackLevels = levels }
                // No recording from fallback tap
            }
            inputTapInstalled = true
            mainMixerTapFallback = true
            return
        }
        print("Installing input tap with format: \(format) bufferSize: \(bufferSize)")
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            // Debug: indicate we received audio buffers
            print("Tap buffer received: \(buffer.frameLength) frames, ch=\(buffer.format.channelCount)")
            let levels = self.calculateRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.trackLevels = levels
            }
            if self.isRecording {
                // Ensure we are positioned for punch before the first write
                if self.punchInEnabled && !self.hasPositionedForPunch {
                    let targetStart = self.writeStartFrame ?? AVAudioFramePosition(Double(self.elapsedSeconds) * (self.fileSampleRate > 0 ? self.fileSampleRate : Double(buffer.format.sampleRate)))
                    if self.usePerTrackFiles {
                        for i in 0..<self.trackWriteFiles.count {
                            if let f = self.trackWriteFiles[i] { f.framePosition = targetStart }
                        }
                    } else if let f = self.projectFile {
                        f.framePosition = targetStart
                    }
                    self.hasPositionedForPunch = true
                }

                if self.usePerTrackFiles {
                    self.writePerTrack(from: buffer)
                } else {
                    self.writeToProjectFile(from: buffer)
                }

                // Update elapsedSeconds from file/track positions
                if self.usePerTrackFiles {
                    var maxFrames: AVAudioFramePosition = 0
                    for f in self.trackWriteFiles.compactMap({ $0 }) { maxFrames = max(maxFrames, f.framePosition) }
                    let seconds = Double(maxFrames) / (self.fileSampleRate > 0 ? self.fileSampleRate : Double(buffer.format.sampleRate))
                    DispatchQueue.main.async { self.elapsedSeconds = min(999, max(0, Int(seconds))) }
                    // Auto-stop at punch-out
                    if let end = self.writeEndFrame, maxFrames >= end {
                        DispatchQueue.main.async { self.stop() }
                    }
                } else if let file = self.projectFile {
                    let seconds = Double(file.framePosition) / (self.fileSampleRate > 0 ? self.fileSampleRate : Double(buffer.format.sampleRate))
                    DispatchQueue.main.async { self.elapsedSeconds = min(999, max(0, Int(seconds))) }
                    if let end = self.writeEndFrame, file.framePosition >= end {
                        DispatchQueue.main.async { self.stop() }
                    }
                }
            }
        }
        inputTapInstalled = true
    }
    
    private func startMetering() {
        ensureEngineRunning()
        installInputTapIfNeeded()
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
                        dstPtr.update(from: srcPtr, count: count)
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

        // Determine transport behavior
        switch transportState {
        case .recording:
            // Derive position from AVAudioFile while recording
            if usePerTrackFiles {
                var maxFrames: AVAudioFramePosition = 0
                for f in trackWriteFiles.compactMap({ $0 }) { maxFrames = max(maxFrames, f.framePosition) }
                let seconds = Double(maxFrames) / (fileSampleRate > 0 ? fileSampleRate : 44100.0)
                elapsedSeconds = min(999, max(0, Int(seconds)))
                if let end = writeEndFrame, maxFrames >= end { stop() }
            } else if let file = projectFile {
                let seconds = Double(file.framePosition) / (fileSampleRate > 0 ? fileSampleRate : 44100.0)
                elapsedSeconds = min(999, max(0, Int(seconds)))
                if let end = writeEndFrame, file.framePosition >= end { stop() }
            }
            return
        case .playing:
            if usePerTrackFiles {
                // Use maximum absolute frame among active nodes to derive time
                var maxAbsolute: AVAudioFramePosition = 0
                var sampleRate: Double = fileSampleRate > 0 ? fileSampleRate : 44100.0
                for i in 0..<min(4, trackNodes.count) {
                    let node = trackNodes[i]
                    guard node.isPlaying, let nodeTime = node.lastRenderTime, let playerTime = node.playerTime(forNodeTime: nodeTime) else { continue }
                    let sr = trackReadFiles[i]?.processingFormat.sampleRate ?? sampleRate
                    sampleRate = sr
                    let playedFrames = AVAudioFramePosition(playerTime.sampleTime)
                    let absolute = playbackStartFrame + playedFrames
                    maxAbsolute = max(maxAbsolute, absolute)
                }
                if maxAbsolute > 0 {
                    let seconds = Double(maxAbsolute) / sampleRate
                    let clamped = min(Double(tapeLengthSeconds), max(0.0, seconds))
                    elapsedSeconds = min(999, max(0, Int(clamped)))
                }
            } else if let firstNode = trackNodes.first,
                      let nodeTime = firstNode.lastRenderTime,
                      let playerTime = firstNode.playerTime(forNodeTime: nodeTime),
                      let file = playbackFile {
                let sr = file.processingFormat.sampleRate
                let playedFrames = AVAudioFramePosition(playerTime.sampleTime)
                let absoluteFrame = playbackStartFrame + playedFrames
                let seconds = Double(absoluteFrame) / sr
                let clamped = min(Double(tapeLengthSeconds), max(0.0, seconds))
                elapsedSeconds = min(999, max(0, Int(clamped)))
                if absoluteFrame >= file.length { pause() }
            }
            return
        case .fastForward, .rewinding, .stopped, .pausedPlayback, .pausedRecording:
            break
        }

        // For FF/RW, simulate transport advance
        let rate: Double
        switch transportState {
        case .fastForward:
            rate = 3.33
        case .rewinding:
            rate = -3.33
        default:
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
                newValue = 0
            }
        }
        elapsedSeconds = Int(newValue.rounded(.towardZero))
    }

    // MARK: - Transport State Machine
    private func setState(_ newState: TransportState) {
        // If pausing, remember previous non-pause state
        if newState == .pausedPlayback || newState == .pausedRecording {
            if transportState != .pausedPlayback && transportState != .pausedRecording {
                previousNonPauseState = transportState
            }
            transportState = newState
            stopTimecodeTicking()
            return
        }

        // From a paused state, only unpause to previous state
        if transportState == .pausedPlayback || transportState == .pausedRecording {
            if newState == .playing && previousNonPauseState == .playing { play(); return }
            if newState == .recording && previousNonPauseState == .recording { record(); return }
            if newState == .stopped { stop(); return }
            // ignore other transitions while paused
            return
        }

        switch transportState {
        case .playing:
            // Allowed: stop, pause, record
            if newState == .stopped { stop(); }
            else if newState == .pausedPlayback { pause() }
            else if newState == .recording { record() }
            // Disallow FF/RW from playing
        case .recording:
            // Allowed: stop, pause
            if newState == .stopped { stop() }
            else if newState == .pausedRecording { pause() }
        case .fastForward:
            // Allowed: play, stop
            if newState == .playing { play() }
            else if newState == .stopped { stop() }
        case .rewinding:
            // Allowed: play, stop
            if newState == .playing { play() }
            else if newState == .stopped { stop() }
        case .stopped:
            // Allowed: play, record, ff, rw
            if newState == .playing { play() }
            else if newState == .recording { record() }
            else if newState == .fastForward { fastForward() }
            else if newState == .rewinding { rewind() }
        case .pausedPlayback, .pausedRecording:
            break
        }
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

    // MARK: - Punch Configuration APIs
    func configurePunch(in inPoint: Double?, out outPoint: Double?) {
        punchInPointSeconds = inPoint
        punchOutPointSeconds = outPoint
    }

    func enablePunch(_ enabled: Bool) { punchInEnabled = enabled }

    // MARK: - Transport Controls
    func play() {
        if transportState == .playing { return }
        ensureEngineRunning()
        isPlaying = true
        transportState = .playing
        // Start playback from current position if we have a recorded file
        startPlaybackFromCurrentPosition()
        startTimecodeTicking()
    }
    
    func pause() {
        // Toggle pause based on current state
        switch transportState {
        case .playing:
            previousNonPauseState = .playing
            transportState = .pausedPlayback
        case .recording:
            previousNonPauseState = .recording
            transportState = .pausedRecording
        case .pausedPlayback:
            // unpause to previous
            if previousNonPauseState == .playing { play() }
            return
        case .pausedRecording:
            if previousNonPauseState == .recording { record() }
            return
        default:
            return
        }
        trackNodes.forEach { $0.pause() }
        stopTimecodeTicking()
    }
    
    func stop() {
        trackNodes.forEach { $0.stop() }
        isRecording = false
        isPlaying = false
        transportState = .stopped
        playbackStartFrame = 0
        // Clear read handles
        playbackFile = nil
        for i in 0..<trackReadFiles.count { trackReadFiles[i] = nil }
        stopTimecodeTicking()
    }
    
    func record() {
        if transportState == .recording { return }
        ensureEngineRunning()
        if usePerTrackFiles && !recArmed.contains(true) {
            print("Warning: No tracks are armed for recording in per-track mode. Nothing will be written.")
        }
        // Stop any playback
        trackNodes.forEach { $0.stop(); $0.reset() }
        isPlaying = false
        playbackStartFrame = 0

        // Compute punch frame targets
        let sr: Double
        if usePerTrackFiles {
            // Use first available track file rate or fallback
            sr = (trackWriteFiles.compactMap { $0?.processingFormat.sampleRate }.first) ?? fileSampleRate
        } else {
            sr = fileSampleRate
        }
        if punchInEnabled {
            let startSec = punchInPointSeconds ?? Double(elapsedSeconds)
            writeStartFrame = AVAudioFramePosition(startSec * sr)
            if let outSec = punchOutPointSeconds, outSec > startSec {
                writeEndFrame = AVAudioFramePosition(outSec * sr)
            } else {
                writeEndFrame = nil
            }
            hasPositionedForPunch = false
        } else {
            writeStartFrame = nil
            writeEndFrame = nil
            hasPositionedForPunch = true // append behavior
        }

        // Start fresh files for this take (project or per-track) when not punching, else open for appending/overwriting
        prepareProjectFile(overwrite: !punchInEnabled)
        isRecording = true
        transportState = .recording
        startTimecodeTicking()
    }
    
    func fastForward() {
        if transportState == .fastForward { return }
        ensureEngineRunning()
        transportState = .fastForward
        trackNodes.forEach { $0.pause() }
        startTimecodeTicking()
    }
    
    func rewind() {
        if transportState == .rewinding { return }
        ensureEngineRunning()
        transportState = .rewinding
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
    
    // Switch between single-file and per-track-file modes (UI convenience)
    func setUsePerTrackFiles(_ enabled: Bool) {
        perTrackModeEnabled = enabled
    }

    func togglePerTrackMode() {
        perTrackModeEnabled.toggle()
    }
}

