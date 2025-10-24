//
//  DolbyBDecoder.swift
//  porta424_UI
//
//  Created by John Clem on 10/22/25.
//

import Foundation

class DolbyBDecoder {
    private var filter = SlidingBandFilter(cutoff: 3000)
    
    func process(_ input: UnsafeMutablePointer<Float>, count: Int) -> [Float] {
        var output = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let hf = filter.process(input[i])
            let atten = pow(10.0, -hf * 0.1)
            output[i] = input[i] * atten
        }
        return output
    }
}
