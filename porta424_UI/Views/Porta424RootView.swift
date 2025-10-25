import SwiftUI

struct Porta424RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ObservedObject private var audio = TimecodeAudioEngine.shared

    var body: some View {
        GeometryReader { geometry in
            let isCompactLandscape = horizontalSizeClass == .compact &&
                verticalSizeClass == .compact &&
                geometry.size.width > geometry.size.height

            let isWideLayout = horizontalSizeClass == .regular || geometry.size.width >= 768

            ZStack {
                PortaBackgroundView()

                if isWideLayout || isCompactLandscape {
                    HStack(spacing: 16) {
                        leftColumn
                            .frame(
                                maxWidth: isWideLayout ?
                                    min(520, geometry.size.width * 0.45) :
                                    geometry.size.width * 0.48
                            )

                        mixerColumn
                    }
                    .padding(16)
                } else {
                    VStack(spacing: 16) {
                        tapeDeckCard
                        transportRow
                        knobRow
                        mixerColumn
                            .frame(maxHeight: .infinity)
                    }
                    .padding(16)
                }
            }
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 16) {
            tapeDeckCard
            transportRow
            knobRow
        }
    }

    private var tapeDeckCard: some View {
        PortaCard {
            VStack(spacing: 14) {
                CassetteDeckView(isPlaying: cassetteIsMoving, progress: cassetteProgress)
                    .frame(minHeight: 140, maxHeight: 210)
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tape Deck")
    }

    private var transportRow: some View {
        PortaCard {
            HStack(spacing: 4) {
                TransportPadButton(
                    icon: "backward.fill",
                    label: "REW",
                    isActive: audio.transportState == .rewinding
                ) {
                    audio.rewind()
                }
                TransportPadButton(
                    icon: "stop.fill",
                    label: "STOP",
                    isActive: audio.transportState == .stopped
                ) {
                    audio.stop()
                }
                TransportPadButton(
                    icon: "play.fill",
                    label: "PLAY",
                    tint: PortaTheme.green,
                    isActive: audio.transportState == .playing || audio.transportState == .pausedPlayback
                ) {
                    audio.play()
                }
                TransportPadButton(
                    icon: "record.circle.fill",
                    label: "REC",
                    tint: PortaTheme.red,
                    prominent: true,
                    isActive: audio.transportState == .recording || audio.transportState == .pausedRecording
                ) {
                    audio.record()
                }
            }
            .padding(4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transport Controls")
    }

    private var knobRow: some View {
        PortaCard {
            ResponsiveGrid(minimum: 80, spacing: 4) {
                Knob(label: "L               R", value: knobBinding(index: 0))
                Knob(label: "L               R", value: knobBinding(index: 1))
                Knob(label: "L               R", value: knobBinding(index: 2))
                Knob(label: "L               R", value: knobBinding(index: 3))
            }
            .padding(4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Control Knobs")
    }

    private var mixerColumn: some View {
        PortaCard {
            VStack(spacing: 12) {
                ResponsiveGrid(minimum: 80, spacing: 4) {
                    MixerStrip(title: "1", value: faderBinding(index: 0))
                    MixerStrip(title: "2", value: faderBinding(index: 1))
                    MixerStrip(title: "3", value: faderBinding(index: 2))
                    MixerStrip(title: "4", value: faderBinding(index: 3))
                }
                .frame(maxHeight: .infinity)

            }
            .padding(4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mixer")
    }
}

struct PortaBackgroundView: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color(white: 0.12), Color(white: 0.10)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview {
    Porta424RootView()
}

// MARK: - Bindings
private extension Porta424RootView {
    var cassetteIsMoving: Binding<Bool> {
        Binding(
            get: {
                let state = audio.transportState
                switch state {
                case .playing, .recording, .fastForward, .rewinding:
                    return true
                case .stopped, .pausedRecording, .pausedPlayback:
                    return false
                }
            },
            set: { _ in }
        )
    }

    var cassetteProgress: Binding<Double> {
        Binding(
            get: {
                let length = max(1, audio.tapeLengthSeconds)
                let percent = Double(audio.elapsedSeconds) / Double(length)
                return percent.clamped(to: 0...1)
            },
            set: { _ in }
        )
    }

    func knobBinding(index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard audio.controlKnobs.indices.contains(index) else { return 0 }
                return audio.controlKnobs[index]
            },
            set: { newValue in
                guard audio.controlKnobs.indices.contains(index) else { return }
                audio.controlKnobs[index] = newValue.clamped(to: 0...1)
            }
        )
    }

    func faderBinding(index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard audio.trackGains.indices.contains(index) else { return 0 }
                let raw = Double(audio.trackGains[index])
                return (raw / 1.5).clamped(to: 0...1)
            },
            set: { newValue in
                guard audio.trackGains.indices.contains(index) else { return }
                let normalized = newValue.clamped(to: 0...1)
                audio.trackGains[index] = Float(normalized * 1.5)
            }
        )
    }
}
