import SwiftUI

struct TransportPadButton: View {
    var icon: String
    var label: String
    var tint: Color = Color(white: 0.92)
    var prominent: Bool = false
    var isActive: Bool = false
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
        .buttonStyle(
            TransportPadButtonStyle(
                tint: tint,
                prominent: prominent,
                isActive: isActive
            )
        )
        .accessibilityLabel(Text(label))
    }
}

struct TransportPadButtonStyle: ButtonStyle {
    var tint: Color
    var prominent: Bool
    var isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fillColor = isActive ? tint.opacity(0.95) : tint
        let strokeOpacity = isActive ? 0.25 : 0.15
        let baseScale: CGFloat = isActive ? 1.02 : 1.0
        let shadowRadius: CGFloat = isActive ? 7 : 6
        let shadowY: CGFloat = configuration.isPressed ? 1 : (isActive ? 5 : 4)

        configuration.label
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(strokeOpacity), lineWidth: prominent ? 2 : 1)
            )
            .shadow(
                color: .black.opacity(0.25),
                radius: configuration.isPressed ? 2 : shadowRadius,
                x: 0,
                y: shadowY
            )
            .scaleEffect(configuration.isPressed ? 0.98 : baseScale)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
