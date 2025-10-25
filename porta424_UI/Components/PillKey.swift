import SwiftUI

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
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            .foregroundStyle(textColor)
            .accessibilityLabel(Text(label))
    }
}
