import SwiftUI
import Combine

enum RecFunction: String, CaseIterable, Identifiable, Codable {
    case safe = "SAFE"
    case buss = "BUSS L–R"
    case direct = "DIRECT"
    var id: String { rawValue }
}

struct Channel: Identifiable, Codable {
    let id: UUID = UUID()
    var index: Int
    var name: String
    var isStereo: Bool

    var trim: Double = 0.5
    var hiEQ: Double = 0.5
    var midEQ: Double = 0.5
    var loEQ: Double = 0.5
    var aux1: Double = 0.0
    var aux2: Double = 0.0
    var tapeCue: Double = 0.0
    var pan: Double = 0.5
    var fader: Double = 0.75
    var mute: Bool = false
    var solo: Bool = false
    var assignL: Bool = true
    var assignR: Bool = true

    var recFunction: RecFunction = .safe
    var recArmed: Bool = false

    var meter: Double = 0.0
}

struct MasterSection: Codable {
    var stereoFader: Double = 0.8
    var effectReturn1: Double = 0.0
    var effectReturn2: Double = 0.0
    var phonesLevel: Double = 0.5
    var pitch: Double = 0.5
}

struct Transport: Codable {
    var counterSeconds: Double = 0
    var isPlaying: Bool = false
    var isRecording: Bool = false
    var isPaused: Bool = false
    var ffwd: Bool = false
    var rew: Bool = false
}

@MainActor
final class Porta424ViewModel: ObservableObject {
    @Published var channels: [Channel]
    @Published var master: MasterSection
    @Published var transport: Transport
    @Published var meters: [Double] = [0, 0, 0, 0]

    fileprivate var timerCancellable: AnyCancellable?
    fileprivate var engineCancellables: Set<AnyCancellable> = []

    init() {
        channels = [
            Channel(index: 1, name: "1", isStereo: false),
            Channel(index: 2, name: "2", isStereo: false),
            Channel(index: 3, name: "3", isStereo: false),
            Channel(index: 4, name: "4", isStereo: false),
            Channel(index: 5, name: "5/6", isStereo: true),
            Channel(index: 7, name: "7/8", isStereo: true)
        ]
        master = MasterSection()
        transport = Transport()
        beginTransportTimer()
    }

    func beginTransportTimer() {
        timerCancellable = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard transport.isPlaying && !transport.isPaused else { return }
        let speedFactor = (master.pitch - 0.5) * 0.24 + 1.0
        let direction: Double = transport.rew ? -1 : 1
        transport.counterSeconds += (1.0 / 30.0) * speedFactor * direction

        for i in 0..<meters.count {
            if transport.isPlaying {
                meters[i] = max(0, min(1, meters[i] * 0.92 + Double.random(in: 0...0.08)))
            } else {
                meters[i] = max(0, meters[i] * 0.9 - 0.01)
            }
        }
    }

    func togglePlay() {
        if transport.isPlaying && !transport.isPaused {
            transport.isPaused = true
        } else {
            transport.isPlaying = true
            transport.isPaused = false
            transport.ffwd = false
            transport.rew = false
        }
    }

    func stop() {
        transport.isPlaying = false
        transport.isPaused = false
        transport.ffwd = false
        transport.rew = false
    }

    func rewind(held: Bool = false) {
        transport.rew = true
        transport.ffwd = false
        transport.isPlaying = true
        transport.isPaused = false
        if !held {
            transport.counterSeconds = max(0, transport.counterSeconds - 2.5)
            transport.rew = false
        }
    }

    func fastForward(held: Bool = false) {
        transport.ffwd = true
        transport.rew = false
        transport.isPlaying = true
        transport.isPaused = false
        if !held {
            transport.counterSeconds += 2.5
            transport.ffwd = false
        }
    }

    func record() {
        transport.isRecording.toggle()
        if transport.isRecording {
            transport.isPlaying = true
            transport.isPaused = false
        }
    }

    func zeroCounter() {
        transport.counterSeconds = 0
    }

    func toggleRecordArm(track: Int) {
        guard (1...4).contains(track), let index = channels.firstIndex(where: { $0.index == track }) else { return }
        channels[index].recArmed.toggle()
    }

    func setRecFunction(track: Int, to recFunction: RecFunction) {
        guard (1...4).contains(track), let index = channels.firstIndex(where: { $0.index == track }) else { return }
        channels[index].recFunction = recFunction
    }

    var counterString: String {
        let time = max(0, transport.counterSeconds)
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
