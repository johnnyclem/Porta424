import Foundation
import AVFoundation
import Combine
import Darwin
import PortaDSPKit

// MARK: - Public API

public enum RecFunction: String, Codable, Sendable {
    case safe, buss, direct
}

public struct ChannelState: Codable, Equatable, Sendable {
    public var index: Int
    public var isStereo: Bool
    public var trim: Float = 0.5
    public var hiEQ: Float = 0.5
    public var midEQ: Float = 0.5
    public var loEQ: Float = 0.5
    public var aux1: Float = 0.0
    public var aux2: Float = 0.0
    public var tapeCue: Float = 0.0
    public var pan: Float = 0.5
    public var fader: Float = 0.75
    public var mute: Bool = false
    public var assignL: Bool = true
    public var assignR: Bool = true
    public var recFunction: RecFunction = .safe
    public var recArmed: Bool = false
    /// When true, strip input is muted (LINE with no alternate source in MVP).
    public var inputMuted: Bool = false

    public init(index: Int, isStereo: Bool) {
        self.index = index
        self.isStereo = isStereo
    }
}

public struct MasterState: Codable, Equatable, Sendable {
    public var stereoFader: Float = 0.8
    public var effectReturn1: Float = 0.0
    public var effectReturn2: Float = 0.0
    public var phonesLevel: Float = 0.5
    /// 0...1, 0.5 = unity playback rate.
    public var pitch: Float = 0.5

    public init() {}
}

public struct TransportState: Codable, Equatable, Sendable {
    public var position: TimeInterval = 0
    public var isPlaying: Bool = false
    public var isRecording: Bool = false
    public var isPaused: Bool = false

    public init() {}
}

public struct TrackSegment: Codable, Equatable, Sendable {
    public var url: URL
    public var start: TimeInterval
    public var duration: TimeInterval

    public init(url: URL, start: TimeInterval, duration: TimeInterval) {
        self.url = url
        self.start = start
        self.duration = duration
    }
}

/// Multitrack mixer + transport host with optional PortaDSP tape insert on the stereo bus.
@MainActor
public final class Porta424Engine: ObservableObject {
    @Published public private(set) var meters: [Float] = [0, 0, 0, 0]
    @Published public private(set) var tapeMetersDbFS: [Float] = [-120, -120]
    @Published public private(set) var transport: TransportState = .init()
    @Published public private(set) var counterString: String = "00:00"
    @Published public private(set) var isRunning: Bool = false

    public static let shared = Porta424Engine()

    public init() {}

    public var channels: [ChannelState] = [
        .init(index: 1, isStereo: false),
        .init(index: 2, isStereo: false),
        .init(index: 3, isStereo: false),
        .init(index: 4, isStereo: false),
        .init(index: 5, isStereo: true),
        .init(index: 7, isStereo: true)
    ]

    public var master: MasterState = .init()

    public private(set) var trackSegments: [[TrackSegment]] = [[], [], [], []]

    private let engine = AVAudioEngine()
    private let varispeed = AVAudioUnitVarispeed()

    private let groupL = AVAudioMixerNode()
    private let groupR = AVAudioMixerNode()
    private let groupStereo = AVAudioMixerNode()

    private let masterMix = AVAudioMixerNode()
    private let phonesMix = AVAudioMixerNode()

    private let fx1SendMix = AVAudioMixerNode()
    private let fx2SendMix = AVAudioMixerNode()
    private let fx1 = AVAudioUnitReverb()
    private let fx2 = AVAudioUnitDelay()
    private let fxReturnMix = AVAudioMixerNode()

    private let cueMix = AVAudioMixerNode()

    /// Dedicated meter nodes so record taps never clobber metering.
    private let meterBusses: [AVAudioMixerNode] = (0..<4).map { _ in AVAudioMixerNode() }

    private let trackPlayers: [AVAudioPlayerNode] = (0..<4).map { _ in AVAudioPlayerNode() }
    private let trackRecordBusses: [AVAudioMixerNode] = (0..<4).map { _ in AVAudioMixerNode() }

    private var stripNodes: [ChannelStripNode] = []
    private var meterTaps: [MeterTap] = []

    private var placeholderSources: [Int: AVAudioNode] = [:]
    private var inputGains: [AVAudioMixerNode] = []

    private var portaNode: AVAudioUnit?
    private var portaDSP: PortaDSPAudioUnit?
    private var lastTapeParams = PortaDSP.Params()
    private var liveInputSplit: AVAudioMixerNode?
    private var hardwareInputConnected = false

    private var displayTimer: Timer?
    private var playAnchorHostTime: UInt64?
    private var playAnchorPosition: TimeInterval = 0

    private var activeWriters: [AVAudioFile?] = [nil, nil, nil, nil]
    private var recordStartPosition: TimeInterval = 0
    private var graphBuilt = false
    private var processingFormat: AVAudioFormat?

    // MARK: - Lifecycle

    /// Async start: installs PortaDSP AU, builds graph, starts engine.
    public func start() async throws {
        guard !isRunning else { return }
        try configureAudioSession()
        try await buildGraphAsync()
        engine.prepare()
        try engine.start()
        isRunning = true
        #if !targetEnvironment(simulator)
        // Device only: Simulator's inputNode often reports sampleRate=0 / invalid HW
        // format, and `connect` then aborts with an uncatchable NSException
        // ("Input HW format is invalid"). Keep silent live path on Simulator.
        await ensureHardwareInputConnected(retries: 10)
        #else
        print("Porta424: Simulator — skipping hardware mic attach (use device for live input)")
        #endif
        startClock()
    }

    /// Device-only retries until the inputNode exposes a valid sample rate.
    private func ensureHardwareInputConnected(retries: Int) async {
        #if targetEnvironment(simulator)
        return
        #else
        for attempt in 0..<retries {
            if hardwareInputConnected { return }
            if connectHardwareInputIfPossible() { return }
            try? await Task.sleep(for: .milliseconds(200 + attempt * 50))
            if !engine.isRunning {
                try? engine.start()
            }
        }
        print("Porta424: hardware input still unavailable after retries — live path stays silent")
        #endif
    }

    /// Best-effort mic attach after the graph is already running.
    /// Never call this on Simulator — invalid HW formats crash in AVFAudio.
    @discardableResult
    private func connectHardwareInputIfPossible() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard !hardwareInputConnected, let split = liveInputSplit else {
            return hardwareInputConnected
        }
        let processing = processingFormat
            ?? AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let input = engine.inputNode

        // Strict validity: sampleRate MUST be > 0 or connect: aborts the process.
        let hw = input.inputFormat(forBus: 0)
        guard hw.sampleRate >= 8000, hw.channelCount >= 1, hw.channelCount <= 8 else {
            print("Porta424: waiting for mic format (sr=\(hw.sampleRate) ch=\(hw.channelCount))")
            return false
        }

        // Prefer the engine's current output format of the input node when valid.
        let outFmt = input.outputFormat(forBus: 0)
        let connectFormat: AVAudioFormat
        if outFmt.sampleRate >= 8000, outFmt.channelCount >= 1 {
            connectFormat = outFmt
        } else if abs(hw.sampleRate - processing.sampleRate) < 1,
                  hw.channelCount == processing.channelCount {
            connectFormat = hw
        } else if let forced = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hw.sampleRate,
            channels: min(2, hw.channelCount),
            interleaved: false
        ) {
            connectFormat = forced
        } else {
            print("Porta424: could not build safe mic format; left silent")
            return false
        }

        // Swap silent placeholder → hardware. Re-attach silent if anything looks wrong.
        engine.disconnectNodeInput(split)
        engine.connect(input, to: split, format: connectFormat)
        hardwareInputConnected = true
        print("Porta424: hardware input connected \(connectFormat.sampleRate)Hz/\(connectFormat.channelCount)ch")

        if !engine.isRunning {
            try? engine.start()
        }
        return true
        #endif
    }



    public func stopEngine() {
        if transport.isRecording {
            stopRecordingIfNeeded()
            transport.isRecording = false
        }
        stopPlayers(keepTime: false)
        stopClock()
        engine.stop()
        isRunning = false
    }

    // MARK: - Tape DSP

    public func setTapeParams(_ params: PortaDSP.Params) {
        lastTapeParams = params
        portaDSP?.updateParameters(params)
    }

    public func readTapeMeters() -> [Float] {
        guard let portaDSP else { return tapeMetersDbFS }
        let levels = portaDSP.readMeters()
        tapeMetersDbFS = Array(levels.prefix(2))
        return tapeMetersDbFS
    }

    // MARK: - Graph

    private func buildGraphAsync() async throws {
        if graphBuilt {
            // Already wired (restart after stop).
            return
        }

        engine.attach(varispeed)
        [groupL, groupR, groupStereo, masterMix, phonesMix, fx1SendMix, fx2SendMix, fxReturnMix, cueMix].forEach {
            engine.attach($0)
        }
        meterBusses.forEach { engine.attach($0) }
        engine.attach(fx1)
        engine.attach(fx2)
        trackPlayers.forEach { engine.attach($0) }
        trackRecordBusses.forEach { engine.attach($0) }

        stripNodes = [
            ChannelStripNode(index: 1, isStereo: false),
            ChannelStripNode(index: 2, isStereo: false),
            ChannelStripNode(index: 3, isStereo: false),
            ChannelStripNode(index: 4, isStereo: false),
            ChannelStripNode(index: 5, isStereo: true),
            ChannelStripNode(index: 7, isStereo: true)
        ]
        stripNodes.forEach { $0.attach(to: engine) }

        inputGains = (0..<4).map { _ in
            let g = AVAudioMixerNode()
            engine.attach(g)
            return g
        }

        // One consistent stereo format for the whole graph. Mixing sample rates /
        // channel counts is what triggers AVAudioEngine's isInputConnToConverter crash.
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        processingFormat = format

        // Install PortaDSP on stereo bus: groupStereo → tape → masterMix
        let (node, unit) = try await installPortaNode()
        portaNode = node
        portaDSP = unit
        unit.updateParameters(lastTapeParams)
        engine.attach(node)

        // Live input fan-out. Hardware mic is attached *after* the engine starts
        // (connecting inputNode before initialize frequently trips
        // isInputConnToConverter on Simulator / mismatched HW formats).
        let inputSplit = AVAudioMixerNode()
        engine.attach(inputSplit)
        let liveSilent = AVAudioMixerNode()
        liveSilent.outputVolume = 0
        engine.attach(liveSilent)
        engine.connect(liveSilent, to: inputSplit, format: format)
        self.liveInputSplit = inputSplit

        for i in 0..<4 {
            engine.connect(inputSplit, to: inputGains[i], format: format)
            stripNodes[i].connectSource(inputGains[i], format: format, to: engine)
        }

        let silentSource5 = AVAudioMixerNode()
        let silentSource7 = AVAudioMixerNode()
        [silentSource5, silentSource7].forEach { source in
            engine.attach(source)
            source.outputVolume = 0
        }
        placeholderSources[5] = silentSource5
        placeholderSources[7] = silentSource7
        stripNodes[4].connectSource(silentSource5, format: format, to: engine)
        stripNodes[5].connectSource(silentSource7, format: format, to: engine)

        for strip in stripNodes {
            engine.connect(strip.toGroupL, to: groupL, format: format)
            engine.connect(strip.toGroupR, to: groupR, format: format)
            engine.connect(strip.toFX1, to: fx1SendMix, format: format)
            engine.connect(strip.toFX2, to: fx2SendMix, format: format)
            engine.connect(strip.toCue, to: cueMix, format: format)
        }

        // Sum L/R group busses into stereo (hard-pan each group mixer).
        groupL.pan = -1
        groupR.pan = 1
        engine.connect(groupL, to: groupStereo, format: format)
        engine.connect(groupR, to: groupStereo, format: format)

        for player in trackPlayers {
            engine.connect(player, to: groupStereo, format: format)
            engine.connect(player, to: cueMix, format: format)
        }

        fx1.loadFactoryPreset(.mediumHall)
        fx1.wetDryMix = 100
        fx2.delayTime = 0.35
        fx2.feedback = 30

        engine.connect(fx1SendMix, to: fx1, format: format)
        engine.connect(fx1, to: fxReturnMix, format: format)
        engine.connect(fx2SendMix, to: fx2, format: format)
        engine.connect(fx2, to: fxReturnMix, format: format)

        // Dry stereo bus through tape DSP; FX return joins master after tape.
        engine.connect(groupStereo, to: node, format: format)
        engine.connect(node, to: masterMix, format: format)
        engine.connect(fxReturnMix, to: masterMix, format: format)

        engine.connect(masterMix, to: phonesMix, format: format)
        engine.connect(cueMix, to: phonesMix, format: format)

        engine.connect(phonesMix, to: varispeed, format: format)
        engine.connect(varispeed, to: engine.outputNode, format: format)

        for i in 0..<4 {
            engine.connect(groupStereo, to: trackRecordBusses[i], format: format)
            engine.connect(groupStereo, to: meterBusses[i], format: format)
        }

        installMeterTaps(format: format)
        applyAllParameters()
        graphBuilt = true
    }

    private func installPortaNode() async throws -> (AVAudioUnit, PortaDSPAudioUnit) {
        try await withCheckedThrowingContinuation { continuation in
            PortaDSPAudioUnit.makeEngineNode(engine: engine) { avUnit, dspUnit, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let avUnit, let dspUnit else {
                    continuation.resume(throwing: PortaDSPAudioUnitError.failedToCreateEngineNode)
                    return
                }
                continuation.resume(returning: (avUnit, dspUnit))
            }
        }
    }

    private func resolveProcessingFormat() -> AVAudioFormat {
        let out = engine.outputNode.inputFormat(forBus: 0)
        if out.sampleRate > 0, out.channelCount > 0 {
            return out
        }
        return AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    }

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)

        // Request mic permission so Simulator/host can expose a real input format.
        // ensureHardwareInputConnected retries until the format becomes valid.
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { _ in }
        } else {
            session.requestRecordPermission { _ in }
        }
        #endif
    }

    private func installMeterTaps(format: AVAudioFormat) {
        meterTaps.forEach { $0.uninstall() }
        meterTaps = (0..<4).map { i in
            MeterTap(node: meterBusses[i]) { [weak self] level in
                DispatchQueue.main.async {
                    self?.meters[i] = level
                }
            }
        }
        meterTaps.forEach { $0.install(format: format) }
    }

    // MARK: - Parameter application

    public func setChannels(_ newValue: [ChannelState]) {
        channels = newValue
        applyAllParameters()
    }

    public func setMaster(_ newValue: MasterState) {
        master = newValue
        applyMaster()
    }

    private func applyAllParameters() {
        for (index, channel) in channels.enumerated() {
            updateStrip(index, channel)
        }
        applyMaster()
        rewireRecordBusses()
    }

    private func applyMaster() {
        masterMix.outputVolume = master.stereoFader
        fxReturnMix.outputVolume = 1.0
        fx1SendMix.outputVolume = 1.0
        fx2SendMix.outputVolume = 1.0
        fx1.wetDryMix = min(max(master.effectReturn1 * 100, 0), 100)
        fx2.wetDryMix = min(max(master.effectReturn2 * 100, 0), 100)
        phonesMix.outputVolume = master.phonesLevel
        let rate = 1.0 + Double((master.pitch - 0.5) * 0.24)
        varispeed.rate = Float(rate)
    }

    private func updateStrip(_ index: Int, _ channel: ChannelState) {
        guard index < stripNodes.count else { return }
        let node = stripNodes[index]

        if index < inputGains.count {
            inputGains[index].outputVolume = channel.inputMuted ? 0 : 1
        }

        node.preGain.outputVolume = gain(from: channel.trim)

        node.eq.bands[0].filterType = .lowShelf
        node.eq.bands[0].frequency = 100
        node.eq.bands[0].gain = (channel.loEQ - 0.5) * 24
        node.eq.bands[0].bypass = false

        node.eq.bands[1].filterType = .parametric
        node.eq.bands[1].frequency = 1_000
        node.eq.bands[1].bandwidth = 1.0
        node.eq.bands[1].gain = (channel.midEQ - 0.5) * 18
        node.eq.bands[1].bypass = false

        node.eq.bands[2].filterType = .highShelf
        node.eq.bands[2].frequency = 10_000
        node.eq.bands[2].gain = (channel.hiEQ - 0.5) * 24
        node.eq.bands[2].bypass = false

        node.toFX1.outputVolume = channel.aux1
        node.toFX2.outputVolume = channel.aux2
        node.toCue.outputVolume = channel.tapeCue

        node.main.outputVolume = channel.mute ? 0.0 : channel.fader
        node.main.pan = (channel.pan - 0.5) * 2

        node.toGroupL.outputVolume = channel.assignL ? 1.0 : 0.0
        node.toGroupR.outputVolume = channel.assignR ? 1.0 : 0.0
    }

    private var safeSinks: [Int: AVAudioMixerNode] = [:]

    private func rewireRecordBusses() {
        let format = processingFormat ?? resolveProcessingFormat()
        for i in 0..<4 {
            engine.disconnectNodeInput(trackRecordBusses[i])
            switch channels[i].recFunction {
            case .safe:
                let sink: AVAudioMixerNode
                if let existing = safeSinks[i] {
                    sink = existing
                } else {
                    let silent = AVAudioMixerNode()
                    silent.outputVolume = 0
                    engine.attach(silent)
                    safeSinks[i] = silent
                    sink = silent
                }
                engine.connect(sink, to: trackRecordBusses[i], format: format)
            case .buss:
                if i % 2 == 0 {
                    engine.connect(groupL, to: trackRecordBusses[i], format: format)
                } else {
                    engine.connect(groupR, to: trackRecordBusses[i], format: format)
                }
            case .direct:
                engine.connect(stripNodes[i].postEQ, to: trackRecordBusses[i], format: format)
            }
        }
    }

    private func gain(from normalized: Float) -> Float {
        let minDb: Float = -60
        let db = minDb * (1 - normalized)
        return pow(10, db / 20)
    }

    // MARK: - Transport

    public func transportPlayPause() {
        if transport.isPlaying && !transport.isPaused {
            transport.isPaused = true
            stopPlayers(keepTime: true)
        } else {
            transport.isPlaying = true
            transport.isPaused = false
            startPlayersFromCurrentPosition()
        }
    }

    public func transportStop() {
        if transport.isRecording {
            stopRecordingIfNeeded()
            transport.isRecording = false
        }
        transport.isPlaying = false
        transport.isPaused = false
        stopPlayers(keepTime: false)
        updateCounterString()
    }

    public func transportRecordToggle() {
        if transport.isRecording {
            stopRecordingIfNeeded()
            transport.isRecording = false
        } else {
            transport.isRecording = true
            transport.isPlaying = true
            transport.isPaused = false
            startPlayersFromCurrentPosition()
            startRecordingIfArmed()
        }
    }

    public func fastForward(seconds: TimeInterval = 2.5) {
        seek(by: seconds)
    }

    public func rewind(seconds: TimeInterval = 2.5) {
        seek(by: -seconds)
    }

    public func zeroCounter() {
        seek(to: 0)
    }

    public func seek(to position: TimeInterval) {
        transport.position = max(0, position)
        playAnchorPosition = transport.position
        if transport.isPlaying && !transport.isPaused {
            startPlayersFromCurrentPosition()
        } else {
            playAnchorHostTime = nil
            updateCounterString()
        }
    }

    private func seek(by delta: TimeInterval) {
        seek(to: max(0, transport.position + delta))
    }

    // MARK: - Record / Playback

    private var stereoSources: [Int: AVAudioPlayerNode] = [:]

    public func setStereoFileSource(forChannelStartingAt index: Int, url: URL) throws {
        guard index == 5 || index == 7 else { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let file = try AVAudioFile(forReading: url)
        stripNodes[index == 5 ? 4 : 5].connectSource(player, format: file.processingFormat, to: engine)
        stereoSources[index] = player
        player.scheduleFile(file, at: nil, completionHandler: nil)
        if !engine.isRunning {
            try engine.start()
            isRunning = true
        }
        player.play()
    }

    private func startRecordingIfArmed() {
        recordStartPosition = transport.position
        let format = processingFormat ?? resolveProcessingFormat()

        for i in 0..<4 {
            guard channels[i].recArmed, channels[i].recFunction != .safe else { continue }
            let url = tapeFileURL(track: i, stamp: Date().timeIntervalSince1970)
            do {
                let writer = try AVAudioFile(
                    forWriting: url,
                    settings: format.settings,
                    commonFormat: format.commonFormat,
                    interleaved: format.isInterleaved
                )
                activeWriters[i] = writer
            } catch {
                activeWriters[i] = nil
                print("Porta424: record open error: \(error)")
            }
        }

        for i in 0..<4 {
            guard activeWriters[i] != nil else { continue }
            // Record taps live on trackRecordBusses; meter taps stay on meterBusses.
            trackRecordBusses[i].removeTap(onBus: 0)
            trackRecordBusses[i].installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                guard let self, self.transport.isRecording else { return }
                try? self.activeWriters[i]?.write(from: buffer)
            }
        }
    }

    private func stopRecordingIfNeeded() {
        let format = processingFormat ?? resolveProcessingFormat()
        for i in 0..<4 {
            trackRecordBusses[i].removeTap(onBus: 0)
            guard let file = activeWriters[i] else { continue }
            let duration = format.sampleRate > 0 ? Double(file.length) / format.sampleRate : 0
            let segment = TrackSegment(url: file.url, start: recordStartPosition, duration: duration)
            commitSegment(segment, toTrack: i)
            activeWriters[i] = nil
        }
    }

    private func commitSegment(_ segment: TrackSegment, toTrack index: Int) {
        trackSegments[index].removeAll { $0.start >= segment.start }
        trackSegments[index].append(segment)
        if transport.isPlaying && !transport.isPaused {
            scheduleNextSegment(forTrack: index, from: transport.position)
            trackPlayers[index].play()
        }
    }

    private func startPlayersFromCurrentPosition() {
        stopPlayers(keepTime: true)
        playAnchorHostTime = mach_absolute_time()
        playAnchorPosition = transport.position

        for i in 0..<4 {
            scheduleNextSegment(forTrack: i, from: transport.position)
        }

        applyMaster()
        trackPlayers.forEach { $0.play() }
        startClock()
    }

    private func stopPlayers(keepTime: Bool) {
        trackPlayers.forEach { $0.stop() }
        if let anchor = playAnchorHostTime, keepTime {
            let elapsed = hostSecondsSince(anchor)
            transport.position = max(0, playAnchorPosition + elapsed * Double(varispeed.rate))
        }
        playAnchorHostTime = nil
        playAnchorPosition = transport.position
        updateCounterString()
    }

    private func scheduleNextSegment(forTrack index: Int, from position: TimeInterval) {
        let player = trackPlayers[index]
        player.reset()
        guard let segment = trackSegments[index]
            .sorted(by: { $0.start < $1.start })
            .first(where: { $0.start + $0.duration > position }) else { return }

        do {
            let file = try AVAudioFile(forReading: segment.url)
            let sampleRate = file.processingFormat.sampleRate
            let startOffsetSeconds = max(0, position - segment.start)
            let startFrame = AVAudioFramePosition(startOffsetSeconds * sampleRate)
            let remaining = max(0, segment.duration - startOffsetSeconds)
            let frames = AVAudioFrameCount(remaining * sampleRate)
            guard frames > 0 else { return }
            player.scheduleSegment(file, startingFrame: startFrame, frameCount: frames, at: nil, completionHandler: nil)
        } catch {
            print("Porta424: schedule error: \(error)")
        }
    }

    // MARK: - Clock

    private func startClock() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopClock()
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.tick()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.displayTimer = timer
        }
    }

    private func stopClock() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func tick() {
        if transport.isPlaying, !transport.isPaused, let anchor = playAnchorHostTime {
            let elapsed = hostSecondsSince(anchor)
            transport.position = max(0, playAnchorPosition + elapsed * Double(varispeed.rate))
            updateCounterString()
        }
        // Keep tape meters fresh for UI polls.
        _ = readTapeMeters()
    }

    private func updateCounterString() {
        let time = max(0, transport.position)
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        counterString = String(format: "%02d:%02d", minutes, seconds)
    }

    private func hostSecondsSince(_ start: UInt64) -> TimeInterval {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let now = mach_absolute_time()
        let elapsed = now &- start
        let nanos = Double(elapsed) * Double(info.numer) / Double(info.denom)
        return nanos / 1_000_000_000.0
    }

    private func tapeFileURL(track: Int, stamp: TimeInterval) -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("Track\(track + 1)_\(Int(stamp)).caf")
    }
}
