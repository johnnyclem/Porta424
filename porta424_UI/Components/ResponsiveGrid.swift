import SwiftUI

struct ResponsiveGrid<Content: View>: View {
    var minimum: CGFloat
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: minimum),
                    spacing: spacing,
                    alignment: .center
                )
            ],
            alignment: .center,
            spacing: spacing
        ) {
            content
        }
    }
}
