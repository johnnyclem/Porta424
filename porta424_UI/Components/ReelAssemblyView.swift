//
//  ReelAssemblyView.swift
//  porta424_UI
//
//  Created by John Clem on 10/22/25.
//

import SwiftUI

struct ReelAssemblyView: View {
    let rotation: Double
    
    var body: some View {
        GeometryReader { geo in
            let reelSize = geo.size.width * 0.34
            ZStack {
                TapeStrip()
                    .frame(width: geo.size.width * 0.92, height: 52)
                    .overlay(
                        Capsule()
                            .fill(PortaColor.accentTeal.opacity(0.15))
                            .blur(radius: 6)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

                ReelView(size: reelSize)
                    .rotationEffect(.degrees(-rotation))
                    .position(x: geo.size.width * 0.25, y: geo.size.height / 2)

                ReelView(size: reelSize)
                    .rotationEffect(.degrees(rotation))
                    .position(x: geo.size.width * 0.75, y: geo.size.height / 2)
            }
        }
    }
}

struct ReelView: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(PortaColor.surface)
            Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 3)
            // inner ring
            Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 10).padding(6)
            // motion spokes
            Spokes(count: 6)
                .stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 4)
                .padding(size * 0.22)
                .blur(radius: 0.5)
                .opacity(0.9)
            // center hub
            Circle().fill(Color.black.opacity(0.5)).padding(10)
            Circle().fill(PortaColor.accentOrange).frame(width: size * 0.28)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
    }
}

struct TapeStrip: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                let midY = h / 2
                let curve = h * 0.4
                
                path.move(to: CGPoint(x: 0, y: midY))
                path.addCurve(
                    to: CGPoint(x: w, y: midY),
                    control1: CGPoint(x: w * 0.33, y: midY - curve),
                    control2: CGPoint(x: w * 0.66, y: midY + curve)
                )
            }
            .stroke(PortaColor.accentTeal, lineWidth: 6)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
    }
}

struct Spokes: Shape {
    let count: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for i in 0..<max(3, count) {
            let angle = Double(i) * (360.0 / Double(max(3, count))) * Double.pi / 180.0
            let dx = CGFloat(cos(angle))
            let dy = CGFloat(sin(angle))
            let inner = CGPoint(x: center.x + dx * radius * 0.2, y: center.y + dy * radius * 0.2)
            let outer = CGPoint(x: center.x + dx * radius * 0.95, y: center.y + dy * radius * 0.95)
            path.move(to: inner)
            path.addLine(to: outer)
        }
        return path
    }
}
