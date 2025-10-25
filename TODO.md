import SwiftUI

// MARK: - App Entrypoint

@main
struct Porta424DemoApp: App {
    var body: some Scene {
        WindowGroup {
            Porta424RootView()
        }
    }
}

// MARK: - Root / Adaptive Layout

struct Porta424RootView: View {
    @Environment(\.horizontalSizeClass) private var hClass
    @Environment(\.verticalSizeClass) private var vClass

    @State private var isPlaying = false
    @State private var tapeProgress: Double = 0.25

    // Mixer state
    @State private var knob1: Double = 0.6
    @State private var knob2: Double = 0.4
    @State private var knob3: Double = 0.5
    @State private var knob4: Double = 0.3

    @State private var faderInput: Double = 0.7
    @State private var faderTraut: Double = 0.45
    @State private var faderTrack: Double = 0.55
    @State private var faderArmin: Double = 0.35

    var body: some View {
        GeometryReader { geo in
            let isCompactPhoneLandscape =
                hClass == .compact && vClass == .compact && geo.size.width > geo.size.height

            let isWide = hClass == .regular || geo.size.width >= 768

            ZStack {
                BackgroundView()

                if isWide || isCompactPhoneLandscape {
                    // iPad or phone landscape: two-column
                    HStack(spacing: 16) {
                        LeftColumn
                            .frame(maxWidth: isWide ? min(520, geo.size.width * 0.45) : geo.size.width * 0.48)

                        MixerColumn
                    }
                    .padding(16)
                } else {
                    // iPhone portrait: stacked
                    VStack(spacing: 16) {
                        TapeDeckCard
                        TransportRow
                        KnobRow
                        MixerColumn
                            .frame(maxHeight: .infinity)
                    }
                    .padding(16)
                }
            }
            .onChange(of: isPlaying) { _, now in
                if !now { tapeProgress = min(1, tapeProgress) }
            }
        }
    }

    // MARK: - Sections

    private var LeftColumn: some View {
        VStack(spacing: 16) {
            TapeDeckCard
            TransportRow
            KnobRow
        }
    }

    private var TapeDeckCard: some View {
        Card {
            VStack(spacing: 14) {
                // Wood trim + cassette
                TapeDeckView(isPlaying: $isPlaying, progress: $tapeProgress)
                    .frame(minHeight: 140, maxHeight: 210)
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tape Deck")
    }

    private var TransportRow: some View {
        Card {
            HStack(spacing: 14) {
                TransportButton(icon: "backward.fill", label: "REW") { isPlaying = false }
                TransportButton(icon: "stop.fill", label: "STOP") { isPlaying = false }
                TransportButton(icon: "play.fill", label: "PLAY", tint: PortaTheme.green) { isPlaying = true }
                TransportButton(icon: "record.circle.fill", label: "REC", tint: PortaTheme.red, prominent: true) { }
            }
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transport Controls")
    }

    private var KnobRow: some View {
        Card {
            ResponsiveGrid(min: 90, spacing: 12) {
                Knob(label: "ATAL", value: $knob1)
                Knob(label: "RECONDN", value: $knob2)
                Knob(label: "RECORD", value: $knob3)
                Knob(label: "STOP", value: $knob4)
            }
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Control Knobs")
    }

    private var MixerColumn: some View {
        Card {
            VStack(spacing: 12) {
                ResponsiveGrid(min: 90, spacing: 12) {
                    MixerStrip(title: "INPUT", value: $faderInput)
                    MixerStrip(title: "TRAUT", value: $faderTraut)
                    MixerStrip(title: "TRACK", value: $faderTrack)
                    MixerStrip(title: "ARMIN", value: $faderArmin)
                }
                .frame(maxHeight: .infinity)

                // Bottom colored buttons
                HStack(spacing: 10) {
                    PillKey(label: "PA", tint: PortaTheme.ivory, textColor: .black)
                    PillKey(label: "TRACK", tint: PortaTheme.red)
                    PillKey(label: "PALS", tint: PortaTheme.green)
                    PillKey(label: "PAN", tint: PortaTheme.blue)
                }
                .padding(.top, 4)
            }
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mixer")
    }
}

// MARK: - Theme & Building Blocks

enum PortaTheme {
    static let wood = Color(red: 0.33, green: 0.22, blue: 0.15)
    static let panel = Color(red: 0.85, green: 0.84, blue: 0.82)
    static let metal = Color(red: 0.72, green: 0.72, blue: 0.70)
    static let shadow = Color.black.opacity(0.25)

    static let green = Color(hue: 0.35, saturation: 0.6, brightness: 0.78)
    static let red   = Color(hue: 0.0,  saturation: 0.75, brightness: 0.80)
    static let blue  = Color(hue: 0.58, saturation: 0.55, brightness: 0.80)
    static let ivory = Color(red: 0.97, green: 0.97, blue: 0.94)
}

struct BackgroundView: View {
    var body: some View {
        LinearGradient(gradient: Gradient(colors: [
            Color(white: 0.12),
            Color(white: 0.10)
        ]), startPoint: .topLeading, endPoint: .bottomTrailing)
        .ignoresSafeArea()
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(PortaTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PortaTheme.metal.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: PortaTheme.shadow, radius: 10, x: 0, y: 6)
            .overlay(content.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
    }
}

struct ResponsiveGrid<Content: View>: View {
    var min: CGFloat
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: min), spacing: spacing, alignment: .center)],
                  alignment: .center,
                  spacing: spacing) {
            content
        }
    }
}

// MARK: - Tape Deck

struct TapeDeckView: View {
    @Binding var isPlaying: Bool
    @Binding var progress: Double

    @State private var spinLeft: Double = 0
    @State private var spinRight: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            // Wood trim
            RoundedRectangle(cornerRadius: 10)
                .fill(PortaTheme.wood)
                .frame(height: 22)
                .overlay(alignment: .trailing) {
                    Circle().fill(.black.opacity(0.3)).frame(width: 6, height: 6).padding(.trailing, 8)
                }

            ZStack {
                // Cassette shell
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(colors: [Color.black, Color(white: 0.12)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.8), lineWidth: 2)
                    )
                    .overlay(ScrewCorners())

                // Label strip
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color(white: 0.93))
                        .frame(height: 28)
                        .overlay(
                            HStack {
                                Text("V.N").font(.system(size: 14, weight: .semibold, design: .rounded))
                                Spacer()
                                Image(systemName: "triangle.fill")
                                    .scaleEffect(x: 1.4, y: 0.9)
                                    .foregroundStyle(PortaTheme.red)
                            }
                            .padding(.horizontal, 10)
                        )
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Window + reels
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.15))
                    .frame(height: 60)
                    .overlay(
                        HStack(spacing: 36) {
                            Reel(rotation: spinLeft)
                            Reel(rotation: spinRight)
                        }
                    )
                    .padding(.horizontal, 28)

                // Progress bar (bottom of cassette)
                VStack {
                    Spacer()
                    Capsule().fill(Color(white: 0.25))
                        .frame(height: 6)
                        .overlay(
                            GeometryReader { g in
                                Capsule().fill(PortaTheme.green)
                                    .frame(width: max(6, g.size.width * progress))
                            }
                        )
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
        }
        .onChange(of: isPlaying) { _, now in
            if now {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { spinLeft += 360 }
                withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) { spinRight -= 360 }
            } else {
                spinLeft = 0; spinRight = 0
            }
        }
        .onAppear {
            if isPlaying {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { spinLeft += 360 }
                withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) { spinRight -= 360 }
            }
        }
    }
}

struct ScrewCorners: View {
    var body: some View {
        GeometryReader { geo in
            let r: CGFloat = 6
            Group {
                Circle().fill(Color(white: 0.12)).frame(width: r, height: r)
                    .position(x: 10, y: 10)
                Circle().fill(Color(white: 0.12)).frame(width: r, height: r)
                    .position(x: geo.size.width - 10, y: 10)
                Circle().fill(Color(white: 0.12)).frame(width: r, height: r)
                    .position(x: 10, y: geo.size.height - 10)
                Circle().fill(Color(white: 0.12)).frame(width: r, height: r)
                    .position(x: geo.size.width - 10, y: geo.size.height - 10)
            }
        }
    }
}

struct Reel: View {
    var rotation: Double
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.65)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                .shadow(radius: 1, x: 0, y: 1)
            Circle().fill(Color.black).frame(width: 22, height: 22)
            // Spokes
            Circle().stroke(Color.black.opacity(0.35), lineWidth: 2)
                .overlay(
                    ForEach(0..<6) { i in
                        Rectangle().fill(Color.black.opacity(0.45))
                            .frame(width: 2, height: 22)
                            .rotationEffect(.degrees(Double(i) * 60))
                    }
                )
        }
        .frame(width: 44, height: 44)
        .rotationEffect(.degrees(rotation))
        .animation(nil, value: rotation)
    }
}

// MARK: - Transport

struct TransportButton: View {
    var icon: String
    var label: String
    var tint: Color = Color(white: 0.92)
    var prominent: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .frame(minWidth: 64, minHeight: 58)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(TransportButtonStyle(tint: tint, prominent: prominent))
        .accessibilityLabel(Text(label))
    }
}

struct TransportButtonStyle: ButtonStyle {
    var tint: Color
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.15), lineWidth: prominent ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.25),
                    radius: configuration.isPressed ? 2 : 6,
                    x: 0, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Knob

struct Knob: View {
    var label: String
    @Binding var value: Double        // 0...1
    private let minAngle: Angle = .degrees(-140)
    private let maxAngle: Angle = .degrees(140)

    @State private var dragStartValue: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.76)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                    .shadow(radius: 2, x: 0, y: 1)

                // ticks
                Circle().stroke(Color.black.opacity(0.12), lineWidth: 6)
                // indicator
                Capsule()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: 3, height: 16)
                    .offset(y: -22)
                    .rotationEffect(angleForValue(value))
            }
            .frame(width: 64, height: 64)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        // vertical drag sensitivity
                        let delta = -g.translation.height / 150
                        value = (dragStartValue + delta).clamped(to: 0...1)
                    }
                    .onEnded { _ in
                        dragStartValue = value
                    }
            )
            .onAppear { dragStartValue = value }

            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }

    private func angleForValue(_ v: Double) -> Angle {
        let span = maxAngle.degrees - minAngle.degrees
        return .degrees(minAngle.degrees + (span * v))
    }
}

// MARK: - Mixer Strip

struct MixerStrip: View {
    var title: String
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 8) {
            // fader (vertical)
            Fader(value: $value)
                .frame(width: 68, height: 150)

            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) level")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

struct Fader: View {
    @Binding var value: Double

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.92))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)

            // Slot with marks
            VStack {
                Spacer(minLength: 8)
                ZStack {
                    Capsule().fill(Color(white: 0.82)).frame(width: 8)
                    // tick marks
                    VStack(spacing: 12) {
                        ForEach(0..<9) { _ in
                            Rectangle().fill(Color.black.opacity(0.25)).frame(width: 8, height: 1)
                        }
                    }
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity)

            // Thumb
            GeometryReader { g in
                let h = g.size.height
                let y = (1 - value).clamped(to: 0...1) * (h - 24)

                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.8)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.2), lineWidth: 1))
                    .frame(width: 36, height: 24)
                    .position(x: g.size.width / 2, y: y + 12)
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
                    .gesture(
                        DragGesture()
                            .onChanged { drag in
                                let p = (drag.location.y - 12) / (h - 24)
                                value = (1 - p).clamped(to: 0...1)
                            }
                    )
            }
        }
    }
}

// MARK: - Keys / Pills

struct PillKey: View {
    var label: String
    var tint: Color
    var textColor: Color = .black

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(tint)
            )
            .overlay(Capsule().stroke(Color.black.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            .foregroundStyle(textColor)
            .accessibilityLabel(Text(label))
    }
}

// MARK: - Utilities

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Previews

struct Porta424RootView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            Porta424RootView()
                .previewDisplayName("iPhone 15 Pro — Portrait")

            Porta424RootView()
                .previewInterfaceOrientation(.landscapeLeft)
                .previewDisplayName("iPhone 15 Pro — Landscape")

            Porta424RootView()
                .previewDevice("iPad Pro (11-inch) (4th generation)")
                .previewDisplayName("iPad Pro 11”")
        }
    }
}

