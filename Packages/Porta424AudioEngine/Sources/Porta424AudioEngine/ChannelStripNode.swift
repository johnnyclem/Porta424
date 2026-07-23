import AVFoundation

/// One Portastudio-style channel strip.
///
/// Source is expected to already be a sum of **live** + **tape return**
/// (engine owns those mixers). Flow:
/// `source → preGain → EQ → postEQ → main (fader/pan) → group L/R`
/// with postEQ also feeding FX1/FX2/cue and DIRECT record.
final class ChannelStripNode {
    let index: Int
    let isStereo: Bool

    let preGain = AVAudioMixerNode()
    let eq = AVAudioUnitEQ(numberOfBands: 3)
    let postEQ = AVAudioMixerNode()

    let main = AVAudioMixerNode()
    let toGroupL = AVAudioMixerNode()
    let toGroupR = AVAudioMixerNode()
    let toFX1 = AVAudioMixerNode()
    let toFX2 = AVAudioMixerNode()
    let toCue = AVAudioMixerNode()

    init(index: Int, isStereo: Bool) {
        self.index = index
        self.isStereo = isStereo
    }

    func attach(to engine: AVAudioEngine) {
        [preGain, eq, postEQ, main, toGroupL, toGroupR, toFX1, toFX2, toCue].forEach { engine.attach($0) }
    }

    func connectSource(_ source: AVAudioNode, format: AVAudioFormat, to engine: AVAudioEngine) {
        engine.connect(source, to: preGain, format: format)
        engine.connect(preGain, to: eq, format: format)
        engine.connect(eq, to: postEQ, format: format)

        engine.connect(postEQ, to: main, format: format)
        engine.connect(postEQ, to: toFX1, format: format)
        engine.connect(postEQ, to: toFX2, format: format)
        engine.connect(postEQ, to: toCue, format: format)

        engine.connect(main, to: toGroupL, format: format)
        engine.connect(main, to: toGroupR, format: format)
    }
}
