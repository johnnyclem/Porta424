import Foundation
import AVFoundation
import Combine
import QuartzCore
import Darwin

// MARK: - Public API

public enum RecFunction: String, Codable {
    case safe, buss, direct
}

public struct ChannelState: Codable, Equatable {
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

    public init(index: Int, isStereo: Bool) {
        self.index = index
        self.isStereo = isStereo
    }
}

public struct MasterState: Codable, Equatable {
    public var stereoFader: Float = 0.8
    public var effectReturn1: Float = 0.0
    public var effectReturn2: Float = 0.0
    public var phonesLevel: Float = 0.5
    public var pitch: Float = 0.5

    public init() {}
}

public struct TransportState: Codable, Equatable {
    public var position: TimeInterval = 0
    public var isPlaying: Bool = false
    public var isRecording: Bool = false
    public var isPaused: Bool = false

    public init() {}
}

public struct TrackSegment: Codable, Equatable {
    public var url: URL
    public var start: TimeInterval
    public var duration: TimeInterval

    public init(url: URL, start: TimeInterval, duration: TimeInterval) {
        self.url = url
        self.start = start
        self.duration = duration
    }
}

public final class Porta424Engine: ObservableObject {
    @Published public private(set) var meters: [Float] = [0, 0, 0, 0]
    @Published public private(set) var transport: TransportState = .init()
    @Published public private(set) var counterString: String = "00:00"

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

    private let trackPlayers: [AVAudioPlayerNode] = (0..<4).map { _ in AVAudioPlayerNode() }
    private let trackRecordBusses: [AVAudioMixerNode] = (0..<4).map { _ in AVAudioMixerNode() }

    private var stripNodes: [ChannelStripNode] = []
    private var meterTaps: [MeterTap] = []

    private var placeholderSources: [Int: AVAudioNode] = [:]

    private var displayLink: CADisplayLink?
    private var playAnchorHostTime: UInt64?
    private var playAnchorPosition: TimeInterval = 0

    private var activeWriters: [AVAudioFile?] = [nil, nil, nil, nil]
    private var recordStartPosition: TimeInterval = 0

    public func start() throws {
        try configureAudioSession()
        buildGraph()
        try engine.start()
        startClock()
    }

    public func stopEngine() {
        displayLink?.invalidate()
        displayLink = nil
        engine.stop()
    }

    private func buildGraph() {
        engine.attach(varispeed)
        [groupL, groupR, groupStereo, masterMix, phonesMix, fx1SendMix, fx2SendMix, fxReturnMix, cueMix].forEach { engine.attach($0) }
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

        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        for i in 0..<4 {
            stripNodes[i].connectSource(inputNode, format: inputFormat, to: engine)
        }

        let silentSource5 = AVAudioMixerNode()
        let silentSource7 = AVAudioMixerNode()
        [silentSource5, silentSource7].forEach { source in
            engine.attach(source)
            source.outputVolume = 0
        }
        placeholderSources[5] = silentSource5
        placeholderSources[7] = silentSource7
        stripNodes[4].connectSource(silentSource5, format: outputFormat, to: engine)
        stripNodes[5].connectSource(silentSource7, format: outputFormat, to: engine)

        for strip in stripNodes {
            engine.connect(strip.toGroupL, to: groupL, format: outputFormat)
            engine.connect(strip.toGroupR, to: groupR, format: outputFormat)
            engine.connect(strip.toFX1, to: fx1SendMix, format: outputFormat)
            engine.connect(strip.toFX2, to: fx2SendMix, format: outputFormat)
            engine.connect(strip.toCue, to: cueMix, format: outputFormat)
        }

        engine.connect(groupL, to: groupStereo, fromBus: 0, toBus: 0, format: outputFormat)
        engine.connect(groupR, to: groupStereo, fromBus: 0, toBus: 1, format: outputFormat)

        for player in trackPlayers {
            engine.connect(player, to: groupStereo, format: outputFormat)
            engine.connect(player, to: cueMix, format: outputFormat)
        }

        fx1.loadFactoryPreset(.mediumHall)
        fx1.wetDryMix = 100
        fx2.delayTime = 0.35
        fx2.feedback = 30

        engine.connect(fx1SendMix, to: fx1, format: outputFormat)
        engine.connect(fx1, to: fxReturnMix, format: outputFormat)
        engine.connect(fx2SendMix, to: fx2, format: outputFormat)
        engine.connect(fx2, to: fxReturnMix, format: outputFormat)

        engine.connect(groupStereo, to: masterMix, format: outputFormat)
        engine.connect(fxReturnMix, to: masterMix, format: outputFormat)

        engine.connect(masterMix, to: phonesMix, format: outputFormat)
        engine.connect(cueMix, to: phonesMix, format: outputFormat)

        engine.connect(phonesMix, to: varispeed, format: outputFormat)
        engine.connect(varispeed, to: engine.outputNode, format: outputFormat)

        for i in 0..<4 {
            engine.connect(groupStereo, to: trackRecordBusses[i], format: outputFormat)
        }

        meterTaps = (0..<4).map { i in
            MeterTap(node: trackRecordBusses[i]) { [weak self] level in
                DispatchQueue.main.async {
                    self?.meters[i] = level
                }
            }
        }
        meterTaps.forEach { $0.install(format: outputFormat) }

        applyAllParameters()
    }

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(48_000)
        try session.setActive(true)
        #endif
    }

    public func setChannels(_ newValue: [ChannelState]) {
        channels = newValue
        applyAllParameters()
        rewireRecordBusses()
    }

    public func setMaster(_ newValue: MasterState) {
        master = newValue
        applyMaster()
    }

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
        transport.isRecording.toggle()
        if transport.isRecording {
            transport.isPlaying = true
            transport.isPaused = false
            startPlayersFromCurrentPosition()
            startRecordingIfArmed()
        } else {
            stopRecordingIfNeeded()
        }
    }

    public func fastForward(seconds: TimeInterval = 2.5) {
        seek(by: seconds)
    }

    public func rewind(seconds: TimeInterval = 2.5) {
        seek(by: -seconds)
    }

    public func zeroCounter() {
        transport.position = 0
        playAnchorPosition = 0
        playAnchorHostTime = nil
        if transport.isPlaying {
            startPlayersFromCurrentPosition()
        } else {
            updateCounterString()
        }
    }

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
        }
        player.play()
    }

    private func startRecordingIfArmed() {
        recordStartPosition = transport.position
        let format = engine.outputNode.inputFormat(forBus: 0)

        for i in 0..<4 {
            guard channels[i].recArmed, channels[i].recFunction != .safe else { continue }
            let url = tapeFileURL(track: i, stamp: Date().timeIntervalSince1970)
            do {
                let writer = try AVAudioFile(forWriting: url,
                                             settings: format.settings,
                                             commonFormat: format.commonFormat,
                                             interleaved: format.isInterleaved)
                activeWriters[i] = writer
            } catch {
                activeWriters[i] = nil
                print("Record open error: \(error)")
            }
        }

        for i in 0..<4 {
            guard activeWriters[i] != nil else { continue }
            trackRecordBusses[i].removeTap(onBus: 0)
            trackRecordBusses[i].installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                guard self.transport.isRecording else { return }
                try? self.activeWriters[i]?.write(from: buffer)
            }
        }
    }

    private func stopRecordingIfNeeded() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        for i in 0..<4 {
            trackRecordBusses[i].removeTap(onBus: 0)
            guard let file = activeWriters[i] else { continue }
            let duration = Double(file.length) / format.sampleRate
            let segment = TrackSegment(url: file.url, start: recordStartPosition, duration: duration)
            commitSegment(segment, toTrack: i)
            activeWriters[i] = nil
        }
    }

    private func commitSegment(_ segment: TrackSegment, toTrack index: Int) {
        trackSegments[index].removeAll { $0.start >= segment.start }
        trackSegments[index].append(segment)
        if transport.isPlaying {
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

        let rate = 1.0 + Double((master.pitch - 0.5) * 0.24)
        varispeed.rate = Float(rate)
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
            let frames = AVAudioFrameCount((segment.duration - startOffsetSeconds) * sampleRate)
            player.scheduleSegment(file, startingFrame: startFrame, frameCount: frames, at: nil, completionHandler: nil)
        } catch {
            print("schedule error: \(error)")
        }
    }

    private func seek(by delta: TimeInterval) {
        transport.position = max(0, transport.position + delta)
        if transport.isPlaying {
            startPlayersFromCurrentPosition()
        } else {
            updateCounterString()
        }
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
    }

    private func updateStrip(_ index: Int, _ channel: ChannelState) {
        guard index < stripNodes.count else { return }
        let node = stripNodes[index]

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
        let pan = (channel.pan - 0.5) * 2
        node.main.pan = pan

        node.toGroupL.outputVolume = channel.assignL ? 1.0 : 0.0
        node.toGroupR.outputVolume = channel.assignR ? 1.0 : 0.0
    }

    private var safeSinks: [Int: AVAudioMixerNode] = [:]

    private func rewireRecordBusses() {
        let format = engine.outputNode.inputFormat(forBus: 0)
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
                let strip = stripNodes[i]
                engine.connect(strip.postEQ, to: trackRecordBusses[i], format: format)
            }
        }
    }

    private func gain(from normalized: Float) -> Float {
        let minDb: Float = -60
        let db = minDb * (1 - normalized)
        return pow(10, db / 20)
    }

    private func startClock() {
        DispatchQueue.main.async {
            self.displayLink?.invalidate()
            let link = CADisplayLink(target: self, selector: #selector(self.tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 60, preferred: 30)
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        }
    }

    @objc private func tick() {
        guard transport.isPlaying, let anchor = playAnchorHostTime else { return }
        let elapsed = hostSecondsSince(anchor)
        transport.position = max(0, playAnchorPosition + elapsed * Double(varispeed.rate))
        updateCounterString()
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
