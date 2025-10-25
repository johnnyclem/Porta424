import SwiftUI

struct CassetteDeckView: View {
    @Binding var isPlaying: Bool
    @Binding var progress: Double

    @State private var spinLeft: Double = 0
    @State private var spinRight: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10)
                .fill(PortaTheme.wood)
                .frame(height: 22)
                .overlay(alignment: .trailing) {
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .padding(.trailing, 8)
                }

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.black, Color(white: 0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black.opacity(0.8), lineWidth: 2)
                    )
                    .overlay(ScrewCorners())

                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color(white: 0.93))
                        .frame(height: 28)
                        .overlay(
                            HStack {
                                Text("V.N")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
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
                    Capsule()
                        .fill(Color(white: 0.25))
                        .frame(height: 6)
                        .overlay(
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(PortaTheme.green)
                                    .frame(width: max(6, proxy.size.width * progress))
                            }
                        )
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
        }
        .onChange(of: isPlaying) { _, playing in
            updateSpins(isPlaying: playing)
        }
        .onAppear {
            updateSpins(isPlaying: isPlaying)
        }
    }

    private func updateSpins(isPlaying: Bool) {
        if isPlaying {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                spinLeft += 360
            }
            withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) {
                spinRight -= 360
            }
        } else {
            spinLeft = 0
            spinRight = 0
        }
    }
}

private struct ScrewCorners: View {
    var body: some View {
        GeometryReader { geometry in
            let radius: CGFloat = 6
            Group {
                corner(radius: radius)
                    .position(x: 10, y: 10)
                corner(radius: radius)
                    .position(x: geometry.size.width - 10, y: 10)
                corner(radius: radius)
                    .position(x: 10, y: geometry.size.height - 10)
                corner(radius: radius)
                    .position(
                        x: geometry.size.width - 10,
                        y: geometry.size.height - 10
                    )
            }
        }
    }

    private func corner(radius: CGFloat) -> some View {
        Circle()
            .fill(Color(white: 0.12))
            .frame(width: radius, height: radius)
    }
}

private struct Reel: View {
    var rotation: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.85), Color(white: 0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.5), lineWidth: 1)
                )
                .shadow(radius: 1, x: 0, y: 1)

            Circle()
                .fill(Color.black)
                .frame(width: 22, height: 22)

            Circle()
                .stroke(Color.black.opacity(0.35), lineWidth: 2)
                .overlay(
                    ForEach(0..<6) { index in
                        Rectangle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 2, height: 22)
                            .rotationEffect(.degrees(Double(index) * 60))
                    }
                )
        }
        .frame(width: 44, height: 44)
        .rotationEffect(.degrees(rotation))
        .animation(nil, value: rotation)
    }
}
