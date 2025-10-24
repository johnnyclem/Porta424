//
//  VUMeter.swift
//  porta424_UI
//
//  Created by John Clem on 10/22/25.
//

import SwiftUI

struct VUMeter: View {
    let level: CGFloat
    private let segments = 12
    
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                let filled = level > CGFloat(i) / CGFloat(segments)
                let color: Color = i < 8 ? PortaColor.meterGreen :
                                  i < 10 ? PortaColor.meterYellow : PortaColor.meterRed
                
                Rectangle()
                    .fill(filled ? color : Color.white.opacity(0.1))
                    .frame(height: 6)
                    .cornerRadius(1)
                    .scaleEffect(x: filled ? 1.1 : 1.0, anchor: .leading)
                    .animation(.spring(response: 0.08, dampingFraction: 0.6), value: level)
            }
        }
        .frame(width: 20)
        .padding(8)
        .background(PortaColor.surface.opacity(0.6))
        .cornerRadius(8)
        .overlay(
            Text("\(level.rounded() + 1)")
                .font(PortaFont.meterLabel())
                .foregroundColor(.white.opacity(0.7)),
            alignment: .top
        )
    }
}
