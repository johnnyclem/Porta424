//
//  DolbyBProcessor.swift
//  porta424_UI
//
//  Created by John Clem on 10/22/25.
//

import AVFoundation

class DolbyBProcessor {
    private let encoder = DolbyBEncoder()
    private let decoder = DolbyBDecoder()
    var isEncoding = false
    
    func process(buffer: AVAudioPCMBuffer, isRecording: Bool) -> AVAudioPCMBuffer {
        guard let data = buffer.floatChannelData else { return buffer }
        let count = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        
        for ch in 0..<channels {
            let samples = data[ch]
            let processed = isRecording && isEncoding ?
                encoder.process(samples, count: count) :
                decoder.process(samples, count: count)
            for i in 0..<count { samples[i] = processed[i] }
        }
        return buffer
    }
}
