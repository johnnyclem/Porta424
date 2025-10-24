# PortaDSPKit

![CI](https://github.com/PortaAudio/Porta424/actions/workflows/ci.yml/badge.svg)

PortaDSPKit brings Porta's tape emulation DSP core to Swift. It exposes a high-level API for creating and controlling the engine, plus an `AUAudioUnit` subclass ready for use inside `AVAudioEngine`-backed hosts.

## Installation & requirements

- **Swift toolchain:** Swift 5.9 or newer. macOS developers can use Xcode 15.0+; Linux developers need the matching Swift 5.9 toolchain installed separately.
- **Platforms:** The package currently targets iOS 17 and macOS 14, as configured in `Package.swift`. Linux builds compile the core bridge but stub out audio-unit functionality.
- **Dependencies:** Only Foundation, AVFoundation, and AudioToolbox from Apple's SDK are used on Apple platforms. No Homebrew packages are required.

### Add as a Swift Package dependency

1. Add the repository URL to your project (`File → Add Packages…` in Xcode, or add it to your `Package.swift`).
2. Select the `PortaDSPKit` library product.
3. On macOS, the default module brings in the Audio Unit implementation; on Linux only the pure Swift interface is available.

### Building from source

```bash
git clone https://github.com/PortaAudio/Porta424.git
cd Porta424
swift build --build-tests
```

## Quick-start: embedding in AVAudioEngine

```swift
import AVFoundation
import PortaDSPKit

let engine = AVAudioEngine()
let porta = PortaDSP()
porta.update(PortaDSP.Params())

PortaDSPAudioUnit.makeEngineNode(engine: engine) { unit, audioUnit, error in
    guard let unit, let audioUnit else {
        fatalError("Failed to create Porta node: \(String(describing: error))")
    }

    engine.attach(unit)
    engine.connect(engine.inputNode, to: unit, format: engine.inputNode.inputFormat(forBus: 0))
    engine.connect(unit, to: engine.mainMixerNode, format: engine.mainMixerNode.outputFormat(forBus: 0))

    try? engine.start()
}
```

The snippet wires the Porta DSP node between the input and output mix. Customize the `Params` struct before calling `update(_:)` to shape the tape processing.

## Factory presets

For quick starting points, PortaDSPKit bundles five curated presets exposed through `PortaDSPPreset.factoryPresets`:

- **Clean Cassette** – gentle modulation and reduced noise for subtle coloration.
- **Warm Bump** – emphasises the head bump and saturation for a low-end lift.
- **Lo-Fi Warble** – exaggerated wow/flutter with higher hiss for nostalgic textures.
- **Crunchy Saturation** – restrained modulation with forward, harmonically rich mids.
- **Dusty Archive** – narrow bandwidth and audible noise reminiscent of an aged tape.

Apply a preset by passing its parameters into either `PortaDSP` or `PortaDSPAudioUnit`:

```swift
let preset = PortaDSPPreset.warmBump
porta.update(preset.parameters)
```

## Running the AVEngine demo

The repository contains a simple sample app that boots an `AVAudioEngine` session with Porta inserted:

```bash
open Examples/AVEngineDemo/AVEngineDemo.xcodeproj
```

Run the macOS target from Xcode, select a microphone input, and you should hear the effected output routed through the default device.

## Preset format & compatibility

`PortaDSPKit` ships with a codable `PortaPreset` struct that captures a full `PortaDSP.Params` snapshot together with light metadata. Presets are encoded as JSON and tagged with a `formatVersion` field; the current schema version is `1`, and presets report compatibility via `isCompatible()`. Factory content is bundled inside the library and exposed to hosts through `AUAudioUnitPreset`, covering "Clean Cassette", "Warm Bump", "Crunchy Saturation", "Wobbly Lo-Fi", and "Noisy VHS" styles.

The AVEngine demo app persists user presets by serializing `PortaPreset` instances to `.portapreset` files under the user's Application Support directory (falling back to Documents or temporary storage on platforms where Application Support is unavailable). Saved presets load across launches and can be re-applied alongside the factory set.

## Running tests on macOS

From the repository root:

```bash
swift test
```

Xcode users can also run the "PortaDSPKit" scheme's test action. Tests verify Swift↔︎C parameter bridging and simple passthrough processing.

## Linux support & limitations

Linux builds compile the DSP bridge and high-level Swift wrapper, but audio unit integration is stubbed. `PortaDSPAudioUnit` throws `unsupportedPlatform`, so Linux hosts should stick to the `PortaDSP` helper APIs (e.g. `processInterleaved`).

## Further reading

Dive deeper into the Swift↔︎C bridging layer and render loop in [`Docs/params-bridge-and-render.md`](Docs/params-bridge-and-render.md).

## Continuous integration

Continuous integration builds and tests on both macOS and Linux through GitHub Actions. See the workflow runs by clicking the CI badge above.

