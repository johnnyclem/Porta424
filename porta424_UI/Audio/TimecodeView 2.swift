import SwiftUI

struct TimecodeView: View {
    @ObservedObject var engine: TimecodeAudioEngine = .shared

    var body: some View {
        HStack(spacing: 12) {
            // Label
            Text("TIME")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospaced()
            // Elapsed seconds (000-999 style already provided by engine.displayTimecode)
            Text(engine.displayTimecode)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(engine.elapsedSeconds)))
                .animation(.easeOut(duration: 0.2), value: engine.elapsedSeconds)
            Spacer(minLength: 0)
            // Tape length for context
            Text("/ \(engine.tapeLengthSeconds)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timecode")
        .accessibilityValue("\(engine.elapsedSeconds) seconds")
    }
}

#Preview {
    VStack(spacing: 20) {
        TimecodeView()
        HStack {
            Button("Play") { TimecodeAudioEngine.shared.play() }
            Button("Pause") { TimecodeAudioEngine.shared.pause() }
            Button("FF") { TimecodeAudioEngine.shared.fastForward() }
            Button("RW") { TimecodeAudioEngine.shared.rewind() }
            Button("Rec") { TimecodeAudioEngine.shared.record() }
        }
        .buttonStyle(.bordered)
    }
}
