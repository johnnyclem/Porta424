import SwiftUI

// Simple cassette reel that spins when `isSpinning` is true
private struct CassetteReel: View {
    let size: CGFloat
    let isSpinning: Bool
    let direction: TransportDirection
    let speedMultiplier: Double
    @State private var rotation: Angle = .degrees(0)

    var body: some View {
        ZStack {
            Circle()
                .fill(.gray.opacity(0.15))
            Circle()
                .strokeBorder(.gray.opacity(0.35), lineWidth: size * 0.06)
            Circle()
                .fill(.secondary)
                .frame(width: size * 0.18)
            // spokes
            ForEach(0..<6) { i in
                Rectangle()
                    .fill(.secondary)
                    .frame(width: size * 0.06, height: size * 0.28)
                    .offset(y: -size * 0.22)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(rotation)
        .onChange(of: isSpinning) { _, spinning in
            if spinning {
                startSpinning()
            } else {
                stopSpinning()
            }
        }
        .onChange(of: direction) { _, _ in
            if isSpinning { startSpinning() }
        }
        .onChange(of: speedMultiplier) { _, _ in
            if isSpinning { startSpinning() }
        }
        .task { if isSpinning { startSpinning() } }
    }

    private func startSpinning() {
        let baseDuration = 1.2 / max(0.1, speedMultiplier)
        let delta: Angle = (direction == .down) ? .degrees(-360) : .degrees(360)
        withAnimation(.linear(duration: baseDuration).repeatForever(autoreverses: false)) {
            rotation = rotation + delta
        }
    }

    private func stopSpinning() {
        rotation = rotation // keep last angle; animation stops automatically
    }
}

private enum TransportDirection { case up, down, stopped }

struct TimecodeReadoutView: View {
    @ObservedObject var engine: TimecodeAudioEngine = .shared

    private var transportActive: Bool {
        switch engine.transportState {
        case .playing, .recording, .fastForward, .rewinding: return true
        default: return false
        }
    }

    private var direction: TransportDirection {
        switch engine.transportState {
        case .rewinding: return .down
        case .playing, .recording, .fastForward: return .up
        default: return .stopped
        }
    }

    private var reelSpeed: Double {
        switch engine.transportState {
        case .fastForward, .rewinding: return 2.2
        case .playing, .recording: return 1.0
        default: return 0.0
        }
    }

    // Display number that rolls over when rewinding
    private var rollingDisplay: String {
        if direction != .down {
            // Count up: pure 3-digit wrap using elapsedSeconds % 1000
            let up = max(0, engine.elapsedSeconds) % 1000
            return String(format: "%03d", up)
        } else {
            // Pure 3-digit wrap on rewind: (elapsedSeconds - 1) mod 1000, wrapping to 999
            let current = max(0, engine.elapsedSeconds)
            let down = (current == 0) ? 999 : (current - 1) % 1000
            return String(format: "%03d", down)
        }
    }

    private var numericRolling: Int {
        Int(rollingDisplay) ?? engine.elapsedSeconds
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor.opacity(0.25))
                    .overlay(Circle().fill(statusColor).blur(radius: 6).opacity(0.6))
                    .frame(width: 10, height: 10)
                    .animation(.easeInOut(duration: 0.25), value: statusColor)
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Cassette window with reels
            HStack(spacing: 22) {
                CassetteReel(size: 28, isSpinning: transportActive, direction: direction, speedMultiplier: reelSpeed)
                CassetteReel(size: 28, isSpinning: transportActive, direction: direction, speedMultiplier: reelSpeed)
            }
            .padding(.vertical, 4)

            // Time label and counter
            HStack(spacing: 12) {
                Text("TIME")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospaced()

                Text(rollingDisplay)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(numericRolling)))
                    .animation(.easeOut(duration: 0.2), value: rollingDisplay)

                Spacer(minLength: 0)

                // Tape length context
                Text("/ \(engine.tapeLengthSeconds)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let progress = min(1.0, max(0.0, Double(engine.elapsedSeconds) / Double(max(1, engine.tapeLengthSeconds))))
                ZStack(alignment: .leading) {
                    Capsule().fill(.gray.opacity(0.15))
                    Capsule().fill(statusColor).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.25), value: engine.elapsedSeconds)
        }
        .padding(.horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timecode")
        .accessibilityValue(accessibilityDescription)
    }

    private var statusText: String {
        switch engine.transportState {
        case .recording: return "REC"
        case .playing: return "PLAY"
        case .fastForward: return "FF"
        case .rewinding: return "REW"
        case .pausedPlayback, .pausedRecording: return "PAUSE"
        case .stopped: return "STOP"
        }
    }

    private var statusSymbol: String {
        switch engine.transportState {
        case .recording: return "record.circle.fill"
        case .playing: return "play.fill"
        case .fastForward: return "goforward"
        case .rewinding: return "gobackward"
        case .pausedPlayback, .pausedRecording: return "pause.fill"
        case .stopped: return "stop.fill"
        }
    }

    private var statusColor: Color {
        switch engine.transportState {
        case .recording: return .red
        case .playing: return .green
        case .fastForward, .rewinding: return .yellow
        case .pausedPlayback, .pausedRecording: return .orange
        case .stopped: return .secondary
        }
    }

    private var accessibilityDescription: String {
        switch direction {
        case .up: return "\(engine.elapsedSeconds) seconds, counting up"
        case .down: return "\(engine.elapsedSeconds) seconds, counting down"
        case .stopped: return "\(engine.elapsedSeconds) seconds, stopped"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        TimecodeReadoutView()
        HStack {
            Button("Stop") { TimecodeAudioEngine.shared.stop() }
            Button("Play") { TimecodeAudioEngine.shared.play() }
            Button("Pause") { TimecodeAudioEngine.shared.pause() }
            Button("FF") { TimecodeAudioEngine.shared.fastForward() }
            Button("RW") { TimecodeAudioEngine.shared.rewind() }
            Button("Rec") { TimecodeAudioEngine.shared.record() }
        }
        .buttonStyle(.bordered)
    }
}
