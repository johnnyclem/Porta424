//
//  WaveformView.swift
//  porta424_UI
//
//  Created by John Clem on 10/22/25.
//

import SwiftUI

struct WaveformView: View {
    let data: [Float]
    let color: Color
    
    init(data: [Float], color: Color = .white.opacity(0.7)) {
        self.data = data
        self.color = color
    }
    
    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width / CGFloat(data.count)
            let maxHeight = geo.size.height
            
            Path { path in
                for (i, value) in data.enumerated() {
                    let x = CGFloat(i) * barWidth
                    let height = maxHeight * CGFloat(abs(value))
                    let y = maxHeight / 2 - height / 2
                    path.addRect(CGRect(x: x, y: y, width: barWidth * 0.8, height: height))
                }
            }
            .fill(color)
        }
    }
}
