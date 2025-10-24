import SwiftUI
import Combine

final class AudioEngine: ObservableObject {
    static let shared = AudioEngine()

    @Published var timecodeSeconds: Int = 0
    @Published var rtzEnabled: Bool = false
    @Published var highSpeed: Bool = false
    @Published var isPlaying: Bool = false

    let tapeLengthSeconds: Int = 14 * 60

    private var timer: AnyCancellable?

    func play() {
        if isPlaying { return }
        isPlaying = true
        timer = Timer.publish(every: 1 / playbackSpeed, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.timecodeSeconds < self.tapeLengthSeconds {
                    self.timecodeSeconds += 1
                } else {
                    self.stop()
                }
            }
    }

    func stop() {
        isPlaying = false
        timer?.cancel()
        timer = nil
    }

    func ff() {
        timecodeSeconds = min(timecodeSeconds + 5, tapeLengthSeconds)
    }

    func rew() {
        timecodeSeconds = max(timecodeSeconds - 5, 0)
    }

    func record() {
        // For testing purposes, just start playing and set rtzEnabled true
        rtzEnabled = true
        play()
    }

    var playbackSpeed: Double {
        highSpeed ? 2.0 : 1.0
    }
}

struct TimecodeView: View {
    @StateObject private var engine = AudioEngine.shared

    private var clampedTimecode: Int {
        min(max(engine.timecodeSeconds, 0), engine.tapeLengthSeconds)
    }

    private var digits: [Int] {
        // 3 digit timecode capped at 999 seconds
        let value = min(clampedTimecode, 999)
        let hundreds = value / 100
        let tens = (value / 10) % 10
        let ones = value % 10
        return [hundreds, tens, ones]
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 4) {
                ForEach(digits.indices, id: \.self) { i in
                    Text("\(digits[i])")
                        .font(.system(.title, design: .monospaced))
                        .frame(width: 28, height: 44)
                        .background(Color(.systemGray5))
                        .cornerRadius(5)
                }
            }

            ProgressView(value: Double(clampedTimecode), total: Double(engine.tapeLengthSeconds))
                .padding(.horizontal)

            Toggle("RTZ", isOn: $engine.rtzEnabled)
                .padding(.horizontal)

            Toggle("High Speed (7 min)", isOn: $engine.highSpeed)
                .padding(.horizontal)

            HStack(spacing: 15) {
                Button("REW") {
                    engine.rew()
                }.disabled(!engine.isPlaying && engine.timecodeSeconds == 0)

                Button("STOP") {
                    engine.stop()
                }.disabled(!engine.isPlaying)

                Button("PLAY") {
                    engine.play()
                }.disabled(engine.isPlaying)

                Button("FF") {
                    engine.ff()
                }.disabled(!engine.isPlaying && engine.timecodeSeconds == engine.tapeLengthSeconds)

                Button("REC") {
                    engine.record()
                }
            }
            .padding(.top, 10)
        }
        .padding()
    }
}

#Preview {
    TimecodeView()
}
