import SwiftUI

// MARK: - Porta424 Design System
// Warm, cream-toned retro palette inspired by vintage Tascam portastudios
// and Teenage Engineering's clean-but-playful aesthetic.

enum Porta {

    // MARK: Surface Colors
    static let chassis      = Color(red: 0.89, green: 0.86, blue: 0.80)  // warm cream body
    static let chassisDark  = Color(red: 0.82, green: 0.78, blue: 0.72)  // shadow tone
    static let panel        = Color(red: 0.93, green: 0.90, blue: 0.85)  // lighter inset panels
    static let well         = Color(red: 0.78, green: 0.75, blue: 0.69)  // recessed wells
    static let bezel        = Color(red: 0.70, green: 0.67, blue: 0.62)  // metal bezels

    // MARK: Text
    static let label        = Color(red: 0.20, green: 0.20, blue: 0.20)  // dark charcoal labels
    static let labelLight   = Color(red: 0.45, green: 0.43, blue: 0.40)  // secondary labels
    static let sectionTitle = Color(red: 0.30, green: 0.28, blue: 0.25)  // section headers

    // MARK: Accent Colors (matching concept art knob rings)
    static let saturationOrange = Color(red: 0.90, green: 0.50, blue: 0.15)
    static let wowGreen         = Color(red: 0.25, green: 0.70, blue: 0.45)
    static let flutterBlue      = Color(red: 0.25, green: 0.55, blue: 0.85)
    static let noisePurple      = Color(red: 0.55, green: 0.30, blue: 0.75)

    // MARK: Transport
    static let transportBlue   = Color(red: 0.20, green: 0.50, blue: 0.90)
    static let transportOrange = Color(red: 0.92, green: 0.60, blue: 0.20)
    static let transportGreen  = Color(red: 0.25, green: 0.75, blue: 0.35)
    static let transportRed    = Color(red: 0.88, green: 0.22, blue: 0.22)

    // MARK: Meters
    static let meterGreen  = Color(red: 0.20, green: 0.78, blue: 0.30)
    static let meterYellow = Color(red: 0.90, green: 0.82, blue: 0.15)
    static let meterRed    = Color(red: 0.90, green: 0.20, blue: 0.18)
    static let meterOff    = Color(red: 0.35, green: 0.34, blue: 0.32)

    // MARK: Counter / LED
    static let ledGreen = Color(red: 0.10, green: 0.95, blue: 0.40)
    static let ledBackground = Color(red: 0.08, green: 0.10, blue: 0.08)

    // MARK: Fader
    static let faderTrack    = Color(red: 0.30, green: 0.29, blue: 0.27)
    static let faderCapGreen = Color(red: 0.35, green: 0.72, blue: 0.38)
    static let faderCapOrange = Color(red: 0.92, green: 0.58, blue: 0.22)

    // MARK: Shadows
    static let softShadow = Color.black.opacity(0.15)
    static let deepShadow = Color.black.opacity(0.30)

    // MARK: Fonts
    static let titleFont    = Font.system(size: 28, weight: .black, design: .rounded)
    static let subtitleFont = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let labelFont    = Font.system(size: 9, weight: .bold, design: .rounded)
    static let counterFont  = Font.system(size: 22, weight: .bold, design: .monospaced)
    static let sectionFont  = Font.system(size: 11, weight: .heavy, design: .rounded)

    // MARK: Screw decorations (Teenage Engineering style)
    struct Screw: View {
        var size: CGFloat = 8
        var body: some View {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.72), Color(white: 0.55)],
                            center: .center,
                            startRadius: 0,
                            endRadius: size / 2
                        )
                    )
                Rectangle()
                    .fill(Color(white: 0.45))
                    .frame(width: size * 0.7, height: 1)
            }
            .frame(width: size, height: size)
        }
    }

    // MARK: Embossed section label
    struct SectionLabel: View {
        let text: String
        var body: some View {
            Text(text)
                .font(Porta.sectionFont)
                .tracking(1.5)
                .foregroundStyle(Porta.sectionTitle)
        }
    }

    // MARK: Inset panel modifier
    struct InsetPanel: ViewModifier {
        var cornerRadius: CGFloat = 8
        func body(content: Content) -> some View {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Porta.panel)
                        .shadow(color: Color.white.opacity(0.6), radius: 1, x: 0, y: 1)
                        .shadow(color: Porta.deepShadow, radius: 3, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Porta.bezel.opacity(0.4), lineWidth: 0.5)
                )
        }
    }
}

extension View {
    func portaPanel(cornerRadius: CGFloat = 8) -> some View {
        modifier(Porta.InsetPanel(cornerRadius: cornerRadius))
    }
}
