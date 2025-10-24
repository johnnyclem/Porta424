//
//  SlidingBandFilter.swift
//  porta424_UI
//
//  Created by John Clem on 10/22/25.
//

import Foundation

class SlidingBandFilter {
    private var y1: Float = 0
    let cutoff: Float
    
    init(cutoff: Float) { self.cutoff = cutoff }
    
    func process(_ x: Float) -> Float {
        let rc: Float = 1.0 / (2.0 * Float.pi * cutoff)
        let dt: Float = 1.0 / 44100.0
        let alpha: Float = dt / (rc + dt)
        let y: Float = alpha * x + (1 - alpha) * y1
        y1 = y
        return abs(y)
    }
}
