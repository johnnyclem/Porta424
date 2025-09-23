
import AVFoundation
// import PortaDSPKit // Once added as a local package

final class PortaHost {
    let engine = AVAudioEngine()
    // let dsp = PortaDSP()

    func start() throws {
        // let mixer = AVAudioMixerNode()
        // engine.attach(mixer)
        // engine.connect(engine.inputNode, to: mixer, format: engine.inputNode.inputFormat(forBus: 0))
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
        try engine.start()
    }
}
