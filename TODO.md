Awesome — here’s a clean Swift Package called **PortaUI** with a lightweight MVVM layer and components that mirror your mock and scale across iPhone/iPad, portrait/landscape. Drop this alongside your app, add it via SPM (local or git), then wire the `Porta424View` with the `Porta424ViewModel`.

---

# Package layout

```
PortaUI/
├─ Package.swift
└─ Sources/
   └─ PortaUI/
      ├─ PortaUI.swift                  // Umbrella + public re-exports
      ├─ Theme.swift                    // Colors, sizing, shadows
      ├─ Layout/Adaptive.swift          // ResponsiveGrid + helpers
      ├─ Components/
      │  ├─ BackgroundView.swift
      │  ├─ Card.swift
      │  ├─ TapeDeckView.swift
      │  ├─ TransportControls.swift
      │  ├─ Knob.swift
      │  ├─ Fader.swift
      │  ├─ MixerStrip.swift
      │  └─ PillKey.swift
      ├─ ViewModel/Porta424ViewModel.swift
      └─ Screens/Porta424View.swift     // Composes everything
```

---

## Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortaUI",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "PortaUI", targets: ["PortaUI"])
    ],
    targets: [
        .target(name: "PortaUI", path: "Sources/PortaUI")
    ]
)
```

---

## Sources/PortaUI/PortaUI.swift

```swift
import SwiftUI

/// Export key types for convenience
@_exported import SwiftUI
```

---

## Sources/PortaUI/Theme.swift

```swift
import SwiftUI

public enum PortaTheme {
    public struct Palette {
        public static let wood = Color(red: 0.33, green: 0.22, blue: 0.15)
        public static let panel = Color(red: 0.86, green: 0.85, blue: 0.83)
        public static let metal = Color(red: 0.72, green: 0.72, blue: 0.70)
        public static let backdropTop = Color(white: 0.13)
        public static let backdropBottom = Color(white: 0.10)

        public static let green = Color(hue: 0.35, saturation: 0.60, brightness: 0.78)
        public static let red   = Color(hue: 0.00, saturation: 0.75, brightness: 0.80)
        public static let blue  = Color(hue: 0.58, saturation: 0.55, brightness: 0.80)
        public static let ivory = Color(red: 0.97, green: 0.97, blue: 0.94)

        public static let darkAccent = Color(white: 0.12)
    }

    public struct Metrics {
        public static let cardRadius: CGFloat = 18
        public static let cardStroke: CGFloat = 1
        public static let contentSpacing: CGFloat = 12
        public static let knobSize: CGFloat = 64
        public static let faderWidth: CGFloat = 68
        public static let faderHeight: CGFloat = 150
        public static let transportMinButton = CGSize(width: 64, height: 58)
    }

    public struct Shadow {
        public static let card = Color.black.opacity(0.25)
        public static let small = Color.black.opacity(0.18)
    }

    /// Tune these to match the mock 1:1 as you tweak colors/contrasts.
    public struct Typography {
        public static func label(_ size: CGFloat = 11) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
        public static func transportIcon() -> Font {
            .system(size: 22, weight: .bold)
        }
    }
}
```

---

## Sources/PortaUI/Layout/Adaptive.swift

```swift
import SwiftUI

public struct ResponsiveGrid<Content: View>: View {
    let min: CGFloat
    let spacing: CGFloat
    let content: () -> Content

    public init(min: CGFloat, spacing: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.min = min
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: min), spacing: spacing, alignment: .center)],
            alignment: .center,
            spacing: spacing,
            content: content
        )
    }
}

public extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
```

---

## Sources/PortaUI/Components/BackgroundView.swift

```swift
import SwiftUI

public struct BackgroundView: View {
    public init() {}
    public var body: some View {
        LinearGradient(
            colors: [PortaTheme.Palette.backdropTop, PortaTheme.Palette.backdropBottom],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
```

---

## Sources/PortaUI/Components/Card.swift

```swift
import SwiftUI

public struct Card<Content: View>: View {
    let content: () -> Content
    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    public var body: some View {
        RoundedRectangle(cornerRadius: PortaTheme.Metrics.cardRadius, style: .continuous)
            .fill(PortaTheme.Palette.panel)
            .overlay(
                RoundedRectangle(cornerRadius: PortaTheme.Metrics.cardRadius, style: .continuous)
                    .stroke(PortaTheme.Palette.metal.opacity(0.6), lineWidth: PortaTheme.Metrics.cardStroke)
            )
            .shadow(color: PortaTheme.Shadow.card, radius: 10, x: 0, y: 6)
            .overlay(
                content().clipShape(RoundedRectangle(cornerRadius: PortaTheme.Metrics.cardRadius, style: .continuous))
            )
    }
}
```

---

## Sources/PortaUI/Components/TapeDeckView.swift

```swift
import SwiftUI

public struct TapeDeckView: View {
    @Binding var isPlaying: Bool
    @Binding var progress: Double

    @State private var spinLeft: Double = 0
    @State private var spinRight: Double = 0

    public init(isPlaying: Binding<Bool>, progress: Binding<Double>) {
        _isPlaying = isPlaying
        _progress = progress
    }

    public var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(PortaTheme.Palette.wood)
                .frame(height: 22)
                .overlay(alignment: .trailing) {
                    Circle().fill(.black.opacity(0.3)).frame(width: 6, height: 6).padding(.trailing, 8)
                }

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [.black, Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.8), lineWidth: 2))
                    .overlay(ScrewCorners())

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
                                    .foregroundStyle(PortaTheme.Palette.red)
                            }
                            .padding(.horizontal, 10)
                        )
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

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

                VStack {
                    Spacer()
                    Capsule().fill(Color(white: 0.25))
                        .frame(height: 6)
                        .overlay(
                            GeometryReader { g in
                                Capsule().fill(PortaTheme.Palette.green)
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
            animateSpools(now)
        }
        .onAppear { animateSpools(isPlaying) }
    }

    private func animateSpools(_ playing: Bool) {
        if playing {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { spinLeft += 360 }
            withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) { spinRight -= 360 }
        } else {
            spinLeft = 0; spinRight = 0
        }
    }
}

private struct ScrewCorners: View {
    var body: some View {
        GeometryReader { geo in
            let r: CGFloat = 6
            Group {
                Circle().fill(Color(white: 0.12)).frame(width: r, height: r).position(x: 10, y: 10)
                Circle().fill(Color(white: 0.12)).frame(width: r, height: r).position(x: geo.size.width - 10, y: 10)
                Circle().fill(Color(white: 0.12)).frame(width: r, height: r).position(x: 10, y: geo.size.height - 10)
                Circle().fill(Color(white: 0.12)).frame(width: r, height: r).position(x: geo.size.width - 10, y: geo.size.height - 10)
            }
        }
    }
}

private struct Reel: View {
    var rotation: Double
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.65)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
            Circle().fill(Color.black).frame(width: 22, height: 22)
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
```

---

## Sources/PortaUI/Components/TransportControls.swift

```swift
import SwiftUI

public struct TransportControls: View {
    public var onRew: () -> Void
    public var onStop: () -> Void
    public var onPlay: () -> Void
    public var onRec: () -> Void

    public init(onRew: @escaping () -> Void,
                onStop: @escaping () -> Void,
                onPlay: @escaping () -> Void,
                onRec: @escaping () -> Void) {
        self.onRew = onRew; self.onStop = onStop; self.onPlay = onPlay; self.onRec = onRec
    }

    public var body: some View {
        Card {
            HStack(spacing: 14) {
                TransportButton(icon: "backward.fill", label: "REW", action: onRew)
                TransportButton(icon: "stop.fill", label: "STOP", action: onStop)
                TransportButton(icon: "play.fill", label: "PLAY", tint: PortaTheme.Palette.green, action: onPlay)
                TransportButton(icon: "record.circle.fill", label: "REC", tint: PortaTheme.Palette.red, prominent: true, action: onRec)
            }
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transport Controls")
    }
}

struct TransportButton: View {
    var icon: String
    var label: String
    var tint: Color = Color(white: 0.92)
    var prominent: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(PortaTheme.Typography.transportIcon())
                Text(label).font(PortaTheme.Typography.label())
            }
            .frame(minWidth: PortaTheme.Metrics.transportMinButton.width,
                   minHeight: PortaTheme.Metrics.transportMinButton.height)
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
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.15), lineWidth: prominent ? 2 : 1))
            .shadow(color: .black.opacity(0.25),
                    radius: configuration.isPressed ? 2 : 6,
                    x: 0, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
```

---

## Sources/PortaUI/Components/Knob.swift

```swift
import SwiftUI

public struct Knob: View {
    public let label: String
    @Binding public var value: Double        // 0...1

    private let minAngle: Angle = .degrees(-140)
    private let maxAngle: Angle = .degrees(140)
    @State private var dragStartValue: Double = 0

    public init(label: String, value: Binding<Double>) {
        self.label = label
        _value = value
    }

    public var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.78)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().stroke(Color.black.opacity(0.2), lineWidth: 1))
                Circle().stroke(Color.black.opacity(0.12), lineWidth: 6)
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 3, height: 16)
                    .offset(y: -22)
                    .rotationEffect(angleForValue(value))
            }
            .frame(width: PortaTheme.Metrics.knobSize, height: PortaTheme.Metrics.knobSize)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let delta = -g.translation.height / 150
                        value = (dragStartValue + delta).clamped(to: 0...1)
                    }
                    .onEnded { _ in dragStartValue = value }
            )
            .onAppear { dragStartValue = value }

            Text(label).font(PortaTheme.Typography.label())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)")
        .accessibilityValue("\(Int(value * 100)) percent")
    }

    private func angleForValue(_ v: Double) -> Angle {
        let span = maxAngle.degrees - minAngle.degrees
        return .degrees(minAngle.degrees + (span * v))
    }
}
```

---

## Sources/PortaUI/Components/Fader.swift

```swift
import SwiftUI

public struct Fader: View {
    @Binding var value: Double

    public init(value: Binding<Double>) { _value = value }

    public var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.92))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)

            VStack {
                Spacer(minLength: 8)
                ZStack {
                    Capsule().fill(Color(white: 0.82)).frame(width: 8)
                    VStack(spacing: 12) {
                        ForEach(0..<9) { _ in
                            Rectangle().fill(Color.black.opacity(0.25)).frame(width: 8, height: 1)
                        }
                    }
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity)

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
        .frame(width: PortaTheme.Metrics.faderWidth, height: PortaTheme.Metrics.faderHeight)
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}
```

---

## Sources/PortaUI/Components/MixerStrip.swift

```swift
import SwiftUI

public struct MixerStrip: View {
    public let title: String
    @Binding var value: Double

    public init(title: String, value: Binding<Double>) {
        self.title = title
        _value = value
    }

    public var body: some View {
        VStack(spacing: 8) {
            Fader(value: $value)
            Text(title.uppercased()).font(PortaTheme.Typography.label())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) level")
    }
}
```

---

## Sources/PortaUI/Components/PillKey.swift

```swift
import SwiftUI

public struct PillKey: View {
    public let label: String
    public let tint: Color
    public let textColor: Color

    public init(label: String, tint: Color, textColor: Color = .black) {
        self.label = label; self.tint = tint; self.textColor = textColor
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(tint))
            .overlay(Capsule().stroke(Color.black.opacity(0.15), lineWidth: 1))
            .shadow(color: PortaTheme.Shadow.small, radius: 2, x: 0, y: 1)
            .foregroundStyle(textColor)
    }
}
```

---

## Sources/PortaUI/ViewModel/Porta424ViewModel.swift

```swift
import SwiftUI
import Observation

@Observable
public final class Porta424ViewModel {
    // Transport
    public var isPlaying: Bool = false {
        didSet { if !isPlaying { tapeProgress = min(1, tapeProgress) } }
    }
    public var tapeProgress: Double = 0.25 // 0...1

    // Knobs (rename to match your real semantics)
    public var knob1: Double = 0.6
    public var knob2: Double = 0.4
    public var knob3: Double = 0.5
    public var knob4: Double = 0.3

    // Faders
    public var faderInput: Double = 0.7
    public var faderTraut: Double = 0.45
    public var faderTrack: Double = 0.55
    public var faderArmin: Double = 0.35

    public init() {}

    // Transport intents — wire these to audio engine later
    public func rewind()  { isPlaying = false /* TODO */ }
    public func stop()    { isPlaying = false }
    public func play()    { isPlaying = true  }
    public func record()  { /* Arm record etc. */ }
}
```

---

## Sources/PortaUI/Screens/Porta424View.swift

```swift
import SwiftUI

public struct Porta424View: View {
    @Environment(\.horizontalSizeClass) private var hClass
    @Environment(\.verticalSizeClass) private var vClass

    @State private var vm: Porta424ViewModel

    public init(viewModel: Porta424ViewModel = .init()) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        GeometryReader { geo in
            let isCompactPhoneLandscape =
                hClass == .compact && vClass == .compact && geo.size.width > geo.size.height
            let isWide = hClass == .regular || geo.size.width >= 768

            ZStack {
                BackgroundView()

                if isWide || isCompactPhoneLandscape {
                    HStack(spacing: 16) {
                        LeftColumn
                            .frame(maxWidth: isWide ? min(520, geo.size.width * 0.45) : geo.size.width * 0.48)
                        MixerColumn
                    }
                    .padding(16)
                } else {
                    VStack(spacing: 16) {
                        TapeDeckCard
                        TransportRow
                        KnobRow
                        MixerColumn.frame(maxHeight: .infinity)
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: Sections

    private var LeftColumn: some View {
        VStack(spacing: 16) { TapeDeckCard; TransportRow; KnobRow }
    }

    private var TapeDeckCard: some View {
        Card {
            VStack(spacing: 14) {
                TapeDeckView(isPlaying: $vm.isPlaying, progress: $vm.tapeProgress)
                    .frame(minHeight: 140, maxHeight: 210)
            }
            .padding(16)
        }
        .accessibilityLabel("Tape Deck")
    }

    private var TransportRow: some View {
        TransportControls(
            onRew:  { vm.rewind() },
            onStop: { vm.stop()   },
            onPlay: { vm.play()   },
            onRec:  { vm.record() }
        )
    }

    private var KnobRow: some View {
        Card {
            ResponsiveGrid(min: 90, spacing: 12) {
                Knob(label: "ATAL",    value: $vm.knob1)
                Knob(label: "RECONDN", value: $vm.knob2)
                Knob(label: "RECORD",  value: $vm.knob3)
                Knob(label: "STOP",    value: $vm.knob4)
            }
            .padding(12)
        }
        .accessibilityLabel("Control Knobs")
    }

    private var MixerColumn: some View {
        Card {
            VStack(spacing: 12) {
                ResponsiveGrid(min: 90, spacing: 12) {
                    MixerStrip(title: "INPUT", value: $vm.faderInput)
                    MixerStrip(title: "TRAUT", value: $vm.faderTraut)
                    MixerStrip(title: "TRACK", value: $vm.faderTrack)
                    MixerStrip(title: "ARMIN", value: $vm.faderArmin)
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 10) {
                    PillKey(label: "PA",     tint: PortaTheme.Palette.ivory, textColor: .black)
                    PillKey(label: "TRACK",  tint: PortaTheme.Palette.red,   textColor: .white)
                    PillKey(label: "PALS",   tint: PortaTheme.Palette.green, textColor: .white)
                    PillKey(label: "PAN",    tint: PortaTheme.Palette.blue,  textColor: .white)
                }
                .padding(.top, 4)
            }
            .padding(12)
        }
        .accessibilityLabel("Mixer")
    }
}
```

---

## Using the package in your app

**App target (example):**

```swift
import SwiftUI
import PortaUI

@main
struct Porta424App: App {
    var body: some Scene {
        WindowGroup {
            Porta424View(viewModel: Porta424ViewModel())
        }
    }
}
```

**Previews:**

```swift
#Preview("iPhone Portrait") { Porta424View() }
#Preview("iPhone Landscape") { Porta424View().previewInterfaceOrientation(.landscapeLeft) }
#Preview("iPad Pro 11\"") {
    Porta424View().previewDevice("iPad Pro (11-inch) (4th generation)")
}
```

---

## Skinning closer to the mock (quick knobs to turn)

* Tweak **`PortaTheme.Palette`** colors to exact hex/HSB from your mock.
* Adjust control sizes in **`PortaTheme.Metrics`** to match proportions.
* Swap **label text** (e.g., “RECONDN”, “ARMIN”) to your final track/control names.
* If you have brand fonts, replace `Typography` helpers to use them.

---

If you want, I can also:

* add a `PortaParameters` struct to centralize all labels and default values,
* expose callbacks for value-changed events,
* drop in a simple **audio-engine stub** so play/rec change states you can observe.

