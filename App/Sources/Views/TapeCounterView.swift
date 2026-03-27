import SwiftUI

/// A retro LED tape counter display with green segmented digits on a dark background.
/// Shows elapsed time in HH:MM:SS format, matching classic portastudio counters.
struct TapeCounterView: View {
    var counterText: String
    var isRunning: Bool = false
    var onReset: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            // "TAPE COUNTER" label
            VStack(alignment: .leading, spacing: 1) {
                Text("TAPE")
                    .font(.system(size: 7, weight: .heavy, design: .rounded))
                Text("COUNTER")
                    .font(.system(size: 7, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Porta.label)

            // Reset button (small cassette icon)
            Button {
                HapticEngine.buttonPress()
                onReset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Porta.label.opacity(0.6))
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(Porta.chassis)
                            .shadow(color: Porta.softShadow, radius: 1)
                    )
            }
            .buttonStyle(.plain)

            // LED counter display
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Porta.ledBackground)
                    .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color(white: 0.25), lineWidth: 1)
                    )

                // Ghost digits (all segments dimly lit)
                Text("88:88:88")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Porta.ledGreen.opacity(0.08))

                // Active digits
                Text(counterText)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Porta.ledGreen)
                    .shadow(color: Porta.ledGreen.opacity(0.6), radius: 4)
                    .shadow(color: Porta.ledGreen.opacity(0.3), radius: 8)

                // Colon blink when running
                if isRunning {
                    ColonBlink()
                }
            }
            .frame(width: 120, height: 32)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .portaPanel(cornerRadius: 6)
    }
}

/// Subtle colon blink overlay for running counter.
private struct ColonBlink: View {
    @State private var visible = true

    var body: some View {
        EmptyView()
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible.toggle()
                }
            }
    }
}
