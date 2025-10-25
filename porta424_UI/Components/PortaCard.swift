import SwiftUI

struct PortaCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(PortaTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PortaTheme.metal.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: PortaTheme.shadow, radius: 10, x: 0, y: 6)
            .overlay(
                content
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            )
    }
}
