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

/// Multitrack mixer + transport host with optional PortaDSP tape insert on the stereo bus.
@MainActor
public final class Porta424Engine: ObservableObject {
    @Published public private(set) var meters: [Float] = [0, 0, 0, 0]
    @Published public private(set) var tapeMetersDbFS: [Float] = [-120, -120]
    @Published public private(set) var transport: TransportState = .init()
    @Published public private(set) var counterString: String = "00:00"
    @Published public private(set) var isRunning: Bool = false
    /// Per-track region summary for UI (count / has tape).
    @Published public private(set) var tapeTracks: [TapeTrackState] = TapeTimeline.trackStates(from: [[], [], [], []])

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

    /// Four tape tracks of non-overlapping regions (after punch commits).
    public private(set) var trackRegions: [[TapeRegion]] = [[], [], [], []]

    /// Legacy view of regions (url/start/duration only).
    public var trackSegments: [[TrackSegment]] {
        trackRegions.map { $0.map(TrackSegment.init) }
    }

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

    private let trackPlayers: [AVAudioPlayerNode] = (0..<4).map { _ in AVAudioPlayerNode() }
    private let trackRecordBusses: [AVAudioMixerNode] = (0..<4).map { _ in AVAudioMixerNode() }

    private var stripNodes: [ChannelStripNode] = []
    private var meterTaps: [MeterTap] = []

    private var placeholderSources: [Int: AVAudioNode] = [:]
    /// Live mic (or silent) gain into each of strips 1–4.
    private var inputGains: [AVAudioMixerNode] = []
    /// Tape repro gain into each of strips 1–4 (muted while that track is recording).
    private var tapeReturnGains: [AVAudioMixerNode] = []
    /// Sums live + tape before each strip's preGain.
    private var stripSourceSums: [AVAudioMixerNode] = []

    private var portaNode: AVAudioUnit?
    private var portaDSP: PortaDSPAudioUnit?
    private var lastTapeParams = PortaDSP.Params()
    private var liveInputSplit: AVAudioMixerNode?

    /// Per-track record-source selectors (volume 0/1) — permanent graph wires.
    /// Avoids disconnect/reconnect on arm/REC which triggers isInputConnToConverter.
    private var recordSafeFeed: [AVAudioMixerNode] = []
    private var recordBussFeed: [AVAudioMixerNode] = []
    private var recordDirectFeed: [AVAudioMixerNode] = []
    private var recordSum: [AVAudioMixerNode] = []

    private var displayTimer: Timer?
    private var playAnchorHostTime: UInt64?
    private var playAnchorPosition: TimeInterval = 0

    private var activeWriters: [AVAudioFile?] = [nil, nil, nil, nil]
    private var recordStartPosition: TimeInterval = 0
    private var graphBuilt = false
    private var processingFormat: AVAudioFormat?
    /// Host time when the current play schedule was built (for timed region starts).
    private var playScheduleHostTime: UInt64?

    // MARK: - Lifecycle

    /// Async start: installs PortaDSP AU, builds graph, starts engine.
    public func start() async throws {
        guard !isRunning else { return }
        try configureAudioSession()
        try await buildGraphAsync()
        engine.prepare()
        try engine.start()
        isRunning = true
        // Do NOT rewire engine.inputNode after the graph is live.
        // Reconnecting the hardware input (even with a “valid” format) throws an
        // uncatchable NSException: isInputConnToConverter / Input HW format invalid
        // on Simulator and often on device during session flips. Live path stays
        // on the silent fan-out built in buildGraphAsync; device mic can be added
        // later via a source node / manual render path without graph reconfig.
        print("Porta424: engine running (live input uses graph silent source; no HW rewire)")
        startClock()
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
        tapeReturnGains = (0..<4).map { _ in
            let g = AVAudioMixerNode()
            engine.attach(g)
            return g
        }
        stripSourceSums = (0..<4).map { _ in
            let s = AVAudioMixerNode()
            engine.attach(s)
            return s
        }

        // One consistent stereo format for the whole graph.
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        processingFormat = format

        // Install PortaDSP on stereo bus: groupStereo → tape color → masterMix
        let (node, unit) = try await installPortaNode()
        portaNode = node
        portaDSP = unit
        unit.updateParameters(lastTapeParams)
        engine.attach(node)

        // Live input fan-out (silent on Simulator; device may attach HW later).
        let inputSplit = AVAudioMixerNode()
        engine.attach(inputSplit)
        let liveSilent = AVAudioMixerNode()
        liveSilent.outputVolume = 0
        engine.attach(liveSilent)
        engine.connect(liveSilent, to: inputSplit, format: format)
        self.liveInputSplit = inputSplit

        // Tracks 1–4: live + tape repro → strip (Portastudio tape return through mixer).
        for i in 0..<4 {
            engine.connect(inputSplit, to: inputGains[i], format: format)
            engine.connect(inputGains[i], to: stripSourceSums[i], format: format)

            engine.connect(trackPlayers[i], to: tapeReturnGains[i], format: format)
            engine.connect(tapeReturnGains[i], to: stripSourceSums[i], format: format)
            // Headphones tape cue still available from strip cue send (after EQ).

            stripNodes[i].connectSource(stripSourceSums[i], format: format, to: engine)
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

        // Permanent record routing graph (SAFE / BUSS / DIRECT via volumes only).
        recordSafeFeed = (0..<4).map { _ in AVAudioMixerNode() }
        recordBussFeed = (0..<4).map { _ in AVAudioMixerNode() }
        recordDirectFeed = (0..<4).map { _ in AVAudioMixerNode() }
        recordSum = (0..<4).map { _ in AVAudioMixerNode() }
        (recordSafeFeed + recordBussFeed + recordDirectFeed + recordSum).forEach { engine.attach($0) }

        for i in 0..<4 {
            // Silent SAFE source
            let silent = AVAudioMixerNode()
            silent.outputVolume = 0
            engine.attach(silent)
            safeSinks[i] = silent
            engine.connect(silent, to: recordSafeFeed[i], format: format)
            engine.connect(recordSafeFeed[i], to: recordSum[i], format: format)

            // BUSS: tracks 1&3 (i even) ← groupL, 2&4 (i odd) ← groupR
            if i % 2 == 0 {
                engine.connect(groupL, to: recordBussFeed[i], format: format)
            } else {
                engine.connect(groupR, to: recordBussFeed[i], format: format)
            }
            engine.connect(recordBussFeed[i], to: recordSum[i], format: format)

            // DIRECT: strip post-EQ
            engine.connect(stripNodes[i].postEQ, to: recordDirectFeed[i], format: format)
            engine.connect(recordDirectFeed[i], to: recordSum[i], format: format)

            engine.connect(recordSum[i], to: trackRecordBusses[i], format: format)
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
        // Per-track meters from strip post-fader (main), not the stereo bus.
        meterTaps = (0..<4).map { i in
            MeterTap(node: stripNodes[i].main) { [weak self] level in
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
        applyTapeReturnMutes()
        applyMaster()
        rewireRecordBusses()
    }

    /// Portastudio overdub hygiene: while recording, mute tape return on any track
    /// that is not SAFE so it cannot reprint into the buss / direct path.
    private func applyTapeReturnMutes() {
        for i in 0..<min(4, tapeReturnGains.count) {
            let ch = channels[i]
            // recFunction != .safe is the arm switch on a real 424.
            let shouldMuteReturn = transport.isRecording && ch.recFunction != .safe
            tapeReturnGains[i].outputVolume = shouldMuteReturn ? 0 : 1
        }
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

    /// Select SAFE / BUSS / DIRECT by gain only — never disconnect while running.
    private func rewireRecordBusses() {
        guard recordSum.count == 4 else { return }
        for i in 0..<4 {
            let mode = channels[i].recFunction
            recordSafeFeed[i].outputVolume = (mode == .safe) ? 1 : 0
            recordBussFeed[i].outputVolume = (mode == .buss) ? 1 : 0
            recordDirectFeed[i].outputVolume = (mode == .direct) ? 1 : 0
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
        applyTapeReturnMutes()
        stopPlayers(keepTime: false)
        updateCounterString()
    }

    public func transportRecordToggle() {
        if transport.isRecording {
            stopRecordingIfNeeded()
            transport.isRecording = false
            applyTapeReturnMutes()
        } else {
            transport.isRecording = true
            transport.isPlaying = true
            transport.isPaused = false
            applyTapeReturnMutes()
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
            // Arm = non-SAFE rec function (424 RECORD FUNCTION switch) and/or recArmed flag.
            let armed = channels[i].recFunction != .safe || channels[i].recArmed
            guard armed, channels[i].recFunction != .safe else { continue }
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
            if duration > 0.0005 {
                let region = TapeRegion(
                    url: file.url,
                    start: recordStartPosition,
                    duration: duration
                )
                commitRegion(region, toTrack: i)
            }
            activeWriters[i] = nil
        }
        publishTapeTracks()
    }

    /// Punch-commit a new take onto a track timeline.
    private func commitRegion(_ region: TapeRegion, toTrack index: Int) {
        guard index >= 0, index < 4 else { return }
        TapeTimeline.commit(region, into: &trackRegions[index])
        publishTapeTracks()
        if transport.isPlaying && !transport.isPaused {
            if scheduleTrack(index, from: transport.position) {
                safePlay(trackPlayers[index])
            }
        }
    }

    private func publishTapeTracks() {
        tapeTracks = TapeTimeline.trackStates(from: trackRegions)
    }

    /// Clear all tape on every track (new cassette).
    public func clearAllTape() {
        trackRegions = [[], [], [], []]
        publishTapeTracks()
        if transport.isPlaying {
            startPlayersFromCurrentPosition()
        }
    }

    /// Clear a single track's regions.
    public func clearTrack(_ trackIndex: Int) {
        guard trackIndex >= 0, trackIndex < 4 else { return }
        trackRegions[trackIndex] = []
        publishTapeTracks()
        if transport.isPlaying && !transport.isPaused {
            if scheduleTrack(trackIndex, from: transport.position) {
                safePlay(trackPlayers[trackIndex])
            }
        }
    }

    /// Ensure AVAudioEngine is actually running (I/O overload can pause it silently).
    @discardableResult
    private func ensureEngineRunning() -> Bool {
        if engine.isRunning { return true }
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            print("Porta424: engine restarted after pause/stop")
            return true
        } catch {
            print("Porta424: engine restart failed: \(error)")
            isRunning = false
            return false
        }
    }

    /// `AVAudioPlayerNode.play()` throws if the engine isn't running or the node
    /// isn't in the graph — never let that NSException kill the app.
    private func safePlay(_ player: AVAudioPlayerNode) {
        guard ensureEngineRunning() else { return }
        guard engine.attachedNodes.contains(where: { $0 === player }) else {
            print("Porta424: skip play — player not attached")
            return
        }
        // engine.attachedNodes is available; connection is established in buildGraph.
        if !player.isPlaying {
            player.play()
        }
    }

    private func startPlayersFromCurrentPosition() {
        // Stop without tearing the play anchor twice: stopPlayers clears anchors
        // when keepTime is true after reading them.
        stopPlayers(keepTime: true)

        guard ensureEngineRunning() else {
            print("Porta424: cannot start players — engine not running")
            return
        }

        playAnchorHostTime = mach_absolute_time()
        playScheduleHostTime = playAnchorHostTime
        playAnchorPosition = transport.position

        applyMaster()
        for i in 0..<4 {
            // Only start a player if it has scheduled audio. Calling play() on an
            // idle/disconnected player after I/O pause throws NSException.
            if scheduleTrack(i, from: transport.position) {
                safePlay(trackPlayers[i])
            }
        }
        startClock()
    }

    private func stopPlayers(keepTime: Bool) {
        for player in trackPlayers {
            if player.isPlaying {
                player.stop()
            }
        }
        if let anchor = playAnchorHostTime, keepTime {
            let elapsed = hostSecondsSince(anchor)
            transport.position = max(0, playAnchorPosition + elapsed * Double(varispeed.rate))
        }
        playAnchorHostTime = nil
        playScheduleHostTime = nil
        playAnchorPosition = transport.position
        updateCounterString()
    }

    /// Schedule every region on a track that still has audio after `position`,
    /// using host-time starts so timeline gaps are preserved.
    /// - Returns: `true` if at least one segment was scheduled.
    @discardableResult
    private func scheduleTrack(_ index: Int, from position: TimeInterval) -> Bool {
        let player = trackPlayers[index]
        if player.isPlaying {
            player.stop()
        }
        // Prefer stop over reset: reset() can leave the node unusable when the
        // engine has been paused by I/O overload.

        let regions = TapeTimeline.playable(from: trackRegions[index], at: position)
        guard !regions.isEmpty else { return false }

        let anchorHost = playScheduleHostTime ?? mach_absolute_time()
        let rate = max(0.25, Double(varispeed.rate))
        var scheduled = 0

        for region in regions {
            let playFrom = max(position, region.start)
            guard playFrom < region.end - 0.0005 else { continue }

            let delaySec = (playFrom - position) / rate
            let fileOffsetSec = region.fileOffset + (playFrom - region.start)
            let playDuration = region.end - playFrom

            do {
                let file = try AVAudioFile(forReading: region.url)
                let sampleRate = file.processingFormat.sampleRate
                let startFrame = AVAudioFramePosition(max(0, fileOffsetSec) * sampleRate)
                var frames = AVAudioFrameCount(playDuration * sampleRate)
                if startFrame >= file.length { continue }
                let maxFrames = AVAudioFrameCount(file.length - startFrame)
                frames = min(frames, maxFrames)
                guard frames > 0 else { continue }

                let when: AVAudioTime?
                if delaySec <= 0.001 {
                    when = nil
                } else {
                    let hostTime = anchorHost &+ AVAudioTime.hostTime(forSeconds: delaySec)
                    when = AVAudioTime(hostTime: hostTime)
                }

                player.scheduleSegment(
                    file,
                    startingFrame: startFrame,
                    frameCount: frames,
                    at: when,
                    completionHandler: nil
                )
                scheduled += 1
            } catch {
                print("Porta424: schedule error track \(index + 1): \(error)")
            }
        }
        return scheduled > 0
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
