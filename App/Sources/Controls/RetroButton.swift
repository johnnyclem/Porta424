import SwiftUI

/// A chunky, tactile transport button styled like vintage tape deck controls.
struct RetroTransportButton: View {
    let icon: String
    let label: String
    var color: Color = Porta.transportBlue
    var isActive: Bool = false
    var action: () -> Void

    @State private var isPressed = false
    @State private var breathePhase: Double = 0

    // Is this the record button? Gets a distinctive pulse.
    private var isRecButton: Bool { label == "REC" }

    var body: some View {
        Button {
            HapticEngine.transportTap()
            action()
        } label: {
            VStack(spacing: 4) {
                Text("[\(label)]")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Porta.label.opacity(0.7))

                ZStack {
                    // Button body
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    color,
                                    color.opacity(0.8)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Porta.deepShadow, radius: isPressed ? 1 : 4, x: 0, y: isPressed ? 1 : 3)

                    // Inner highlight
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 1
                        )
                        .padding(1)

                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                }
                .frame(width: 50, height: 42)
                .offset(y: isPressed ? 2 : 0)
                .overlay(
                    // Active glow with breathing pulse
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color)
                        .opacity(isActive ? activeGlowOpacity : 0)
                        .blur(radius: isActive ? activeGlowRadius : 8)
                        .frame(width: 50, height: 42)
                )
            }
        }
        .buttonStyle(TransportButtonStyle(isPressed: $isPressed))
        .onAppear { startBreathe() }
    }

    // REC gets a more dramatic pulse; others get a gentle breathe
    private var activeGlowOpacity: Double {
        if isRecButton {
            return 0.25 + breathePhase * 0.35
        }
        return 0.25 + breathePhase * 0.1
    }

    private var activeGlowRadius: CGFloat {
        if isRecButton {
            return 6 + CGFloat(breathePhase) * 6
        }
        return 7 + CGFloat(breathePhase) * 2
    }

    private func startBreathe() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                // REC breathes faster (urgent), others are gentle
                let speed: Double = isRecButton ? 2.5 : 1.2
                breathePhase = sin(Date.timeIntervalSinceReferenceDate * speed) * 0.5 + 0.5
            }
        }
    }
}

/// Custom button style that tracks press state for visual depression.
struct TransportButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                withAnimation(.easeInOut(duration: 0.08)) {
                    isPressed = newValue
                }
            }
    }
}

/// A smaller, subtler button for non-transport actions.
struct RetroTextButton: View {
    let text: String
    var action: () -> Void

    var body: some View {
        Button {
            HapticEngine.buttonPress()
            action()
        } label: {
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Porta.label)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Porta.chassis)
                        .shadow(color: Porta.softShadow, radius: 2, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Porta.bezel.opacity(0.5), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
