<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/C++-17-00599C?logo=cplusplus&logoColor=white" alt="C++17">
  <img src="https://img.shields.io/badge/iOS-17+-000000?logo=apple&logoColor=white" alt="iOS 17+">
  <img src="https://img.shields.io/badge/macOS-14+-000000?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Linux-supported-FCC624?logo=linux&logoColor=black" alt="Linux">
  <a href="https://github.com/johnnyclem/Porta424/actions/workflows/ci.yml"><img src="https://github.com/johnnyclem/Porta424/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

# PortaDSPKit

**Tape emulation DSP for Swift.** PortaDSPKit is a real-time audio effects library that faithfully recreates the warm, imperfect character of analog cassette tape. It ships as a Swift package with a C++17 DSP core, a high-level Swift API, and a ready-to-use `AUAudioUnit` subclass for `AVAudioEngine` hosts.

The companion **Porta424** app is a full reference implementation -- a retro 4-track tape deck built with SwiftUI, complete with transport controls, VU meters, and a skeuomorphic cassette visualization.

---

## Highlights

- **13 DSP modules** -- wow & flutter, tape hiss, saturation, head bump EQ, dropouts, crosstalk, azimuth jitter, high-frequency loss, compander, biquad filters, and metering
- **Zero external dependencies** -- built entirely on Apple SDKs (Foundation, AVFoundation, AudioToolbox)
- **Audio Unit ready** -- full `AUAudioUnit` subclass with DAW-exposed parameters, factory presets, and real-time metering
- **Thread-safe** -- atomic parameter updates from the C++ core, safe for real-time audio threads
- **Cross-platform** -- macOS, iOS, and Linux (core DSP only)
- **5 factory presets** -- from subtle tape warmth to crushed lo-fi textures
- **Preset system** -- JSON-based `.portapreset` format with versioning and compatibility checks

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Porta424 App (SwiftUI)                                 │
│  Views  ·  ViewModels  ·  Transport  ·  Haptics         │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│  Porta424AudioEngine                                    │
│  Engine orchestration  ·  Channel strips  ·  Meter taps │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│  PortaDSPKit (Swift)                                    │
│  PortaDSP wrapper  ·  PortaDSPAudioUnit  ·  Presets     │
└────────────────────┬────────────────────────────────────┘
                     │  Swift ↔ C bridge
┌────────────────────▼────────────────────────────────────┐
│  PortaDSPBridge (C)                                     │
│  porta_create  ·  porta_update_params  ·  porta_process │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│  DSPCore (C++17)                                        │
│  wow_flutter · hiss · saturation · head_bump · dropouts │
│  crosstalk · azimuth · eq · hf_loss · compander · biquad│
└─────────────────────────────────────────────────────────┘
```

---

## Installation

### Requirements

| Requirement | Version |
|---|---|
| Swift | 5.9+ |
| Xcode | 15.0+ (macOS) |
| iOS | 17+ |
| macOS | 14+ |
| Linux | Swift 5.9 toolchain |

No Homebrew packages, CocoaPods, or Carthage needed.

### Swift Package Manager

Add PortaDSPKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/johnnyclem/Porta424.git", from: "1.0.0")
]
```

Then add `"PortaDSPKit"` to your target's dependencies.

Or in Xcode: **File > Add Packages...** and enter the repository URL.

### Build from source

```bash
git clone https://github.com/johnnyclem/Porta424.git
cd Porta424
swift build --build-tests
```

---

## Quick start

### Embedding in AVAudioEngine

```swift
import AVFoundation
import PortaDSPKit

let engine = AVAudioEngine()

PortaDSPAudioUnit.makeEngineNode(engine: engine) { unit, audioUnit, error in
    guard let unit, let audioUnit else {
        fatalError("Failed to create Porta node: \(error?.localizedDescription ?? "unknown")")
    }

    engine.attach(unit)
    let format = engine.inputNode.inputFormat(forBus: 0)
    engine.connect(engine.inputNode, to: unit, format: format)
    engine.connect(unit, to: engine.mainMixerNode, format: format)

    try? engine.start()
}
```

### Adjusting parameters

```swift
var params = PortaDSP.Params()
params.satDriveDb = -2.0        // Push the saturation
params.headBumpGainDb = 4.0     // Warm low-end boost
params.hissLevelDbFS = -54.0    // Audible tape hiss

let porta = PortaDSP()
porta.update(params)
```

### Offline processing

```swift
let dsp = PortaDSP(sampleRate: 44100.0, maxBlock: 1024, tracks: 2)
dsp.update(PortaDSP.Params())

var buffer = [Float](repeating: 0, count: 1024 * 2)
// ... fill buffer with audio data ...
dsp.processInterleaved(buffer: &buffer, frames: 1024, channels: 2)
```

### Reading meters

```swift
let levels = porta.readMeters()  // Per-channel RMS in dBFS
// levels[0] = left channel, levels[1] = right channel, etc.
// Accumulators reset on each call -- poll regularly via display link or timer
```

---

## DSP Modules

Each module in the C++17 core models a distinct characteristic of analog tape:

| Module | What it does |
|---|---|
| **Wow & Flutter** | Modulated delay line simulating slow (wow) and fast (flutter) tape speed variations |
| **Tape Hiss** | Colored noise generation matching the spectral profile of cassette tape |
| **Saturation** | Nonlinear harmonic distortion -- soft clipping that adds warmth and grit |
| **Head Bump** | Resonant EQ peak at low frequencies from the playback head geometry |
| **Dropouts** | Random amplitude dips simulating oxide shedding and debris on the tape |
| **Crosstalk** | Inter-channel bleed characteristic of adjacent tracks on narrow tape |
| **Azimuth** | Timing offset between channels from imperfect head alignment |
| **High-Frequency Loss** | Progressive treble roll-off modeling tape demagnetization and wear |
| **Compander** | Compression/expansion circuit emulation (noise reduction encoding) |
| **Biquad Filter** | Flexible parametric EQ for shaping the frequency response |
| **EQ** | Equalization curve matching tape machine playback characteristics |
| **Meters** | Per-channel RMS level tracking in dBFS with automatic accumulator reset |

---

## Parameters

All parameters live in the `PortaDSP.Params` struct, which is `Codable`, `Equatable`, and `Sendable`:

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `wowDepth` | Float | 0.0006 | 0.0+ | Slow tape speed variation depth |
| `flutterDepth` | Float | 0.0003 | 0.0+ | Fast tape speed variation depth |
| `headBumpGainDb` | Float | 2.0 | -12...+12 | Head bump resonance boost (dB) |
| `headBumpFreqHz` | Float | 80.0 | 20...20k | Head bump center frequency (Hz) |
| `satDriveDb` | Float | -6.0 | -36...+12 | Saturation drive level (dB) |
| `hissLevelDbFS` | Float | -60.0 | -120...0 | Tape hiss noise floor (dBFS) |
| `lpfCutoffHz` | Float | 12000.0 | 20...20k | Low-pass filter cutoff (Hz) |
| `azimuthJitterMs` | Float | 0.2 | 0.0+ | Tape azimuth timing error (ms) |
| `crosstalkDb` | Float | -60.0 | -120...0 | Channel crosstalk bleed (dB) |
| `dropoutRatePerMin` | Float | 0.2 | 0.0+ | Tape dropout frequency (per min) |
| `nrTrack4Bypass` | Bool | false | -- | Bypass noise reduction on track 4 |

Parameters can be updated in real time via `porta.update(params)` or through the Audio Unit's parameter tree. The C++ core handles thread-safe atomic swapping internally.

---

## Factory Presets

Five curated starting points, accessible via `PortaDSPPreset.factoryPresets`:

| Preset | Character | Key settings |
|---|---|---|
| **Clean Cassette** | Gentle modulation, subtle coloration | Low wow/flutter, light saturation, quiet hiss |
| **Warm Bump** | Rich low-end lift with harmonic saturation | +4 dB head bump, forward saturation |
| **Lo-Fi Warble** | Exaggerated tape artifacts, nostalgic texture | Heavy wow/flutter, narrow bandwidth, audible hiss |
| **Crunchy Saturation** | Forward, harmonically rich mids | Pushed saturation, restrained modulation |
| **Dusty Archive** | Aged tape, narrow bandwidth | Steep HF rolloff, high dropout rate, noisy |

```swift
// Apply a preset
let preset = PortaDSPPreset.warmBump
porta.update(preset.parameters)

// Or via the Audio Unit
audioUnit.currentPreset = AUAudioUnitPreset(number: 1, name: "Warm Bump")
```

### Custom presets

Presets serialize as JSON using `PortaPreset`, which wraps a `Params` snapshot with metadata and a `formatVersion` for compatibility checking:

```swift
let preset = PortaPreset(name: "My Sound", params: myParams)
let data = try JSONEncoder().encode(preset)
// Save to .portapreset file

let loaded = try JSONDecoder().decode(PortaPreset.self, from: data)
guard loaded.isCompatible() else { /* handle version mismatch */ }
```

---

## Porta424 App

The repository includes a full-featured tape deck application built with SwiftUI:

- **Retro cassette UI** with animated reels and realistic tape deck controls
- **4-track mixing** with per-channel VU meters
- **Real-time parameter control** via the `@Observable` TapeDeckViewModel
- **Haptic feedback** on transport controls (iOS)
- **iPad-optimized layout** with a dedicated tape deck view
- **Preset management** -- browse factory presets and save your own

### Running the app

Open the app package in Xcode:

```bash
open App/
```

Select the iOS or macOS target, build, and run. Grant microphone permission when prompted.

---

## Examples

### AVEngine Demo

A minimal sample app that wires PortaDSPKit into an `AVAudioEngine` session with live metering:

```bash
open Examples/AVEngineDemo/AVEngineDemo.xcodeproj
```

Run the macOS or iOS target, select a microphone input, and hear the tape effect applied in real time. See [`Examples/AVEngineDemo/README.md`](Examples/AVEngineDemo/README.md) for details.

### Host Snippet

A minimal integration example lives in `Samples/HostSnippet/` showing how to embed the DSP in a custom audio host.

---

## Testing

### Run the full test suite

```bash
swift test
```

Or in Xcode: select the **PortaDSPKit** scheme and press **Cmd+U**.

### Test coverage

| Suite | What it verifies |
|---|---|
| `PassthroughTests` | Signal integrity in bypass mode |
| `HeadBumpTests` | Head bump EQ resonance behavior |
| `HissDSPTests` | Tape hiss noise generation |
| `SaturationTests` | Nonlinear distortion characteristics |
| `DropoutsTests` | Dropout simulation timing and depth |
| `ModuleDSPTests` | Individual DSP module processing |
| `MeterTests` | RMS metering accuracy and accumulator reset |
| `PresetCodableTests` | JSON serialization round-trips |
| `PortaDSPAudioUnitParameterTests` | Audio Unit parameter tree and ranges |
| `PortaDSPAudioUnitRenderTests` | Render callback correctness |
| `PortaDSPWrapperTests` | High-level Swift wrapper API |
| `PortaDSPFuzzTests` | Fuzz testing with randomized inputs |
| `RealtimeBenchmarkTests` | Performance benchmarks for real-time safety |

---

## Project Structure

```
Porta424/
├── App/                        Porta424 tape deck app (SwiftUI)
│   └── Sources/
│       ├── Models/             DSPState, data models
│       ├── ViewModels/         TapeDeckViewModel
│       ├── Views/              TapeDeckView, CassetteView, VUMeterView
│       ├── Controls/           Custom UI controls
│       ├── Theme/              Visual styling
│       ├── Haptics/            Haptic feedback engine
│       └── Audio/              Audio session integration
├── DSPCore/                    C++17 DSP implementation
│   ├── dsp_context.h           Main DSP context orchestrator
│   └── include/modules/        Individual effect modules
├── Packages/
│   ├── PortaDSPKit/            Core Swift package
│   │   ├── Sources/
│   │   │   ├── PortaDSPBridge/ C ↔ Swift bridge layer
│   │   │   └── PortaDSPKit/    Public Swift API
│   │   ├── Tests/              Unit & integration tests
│   │   └── PerformanceTests/   Real-time benchmarks
│   └── Porta424AudioEngine/    High-level engine wrapper
│       └── Sources/            Engine, channel strips, meter taps
├── Examples/
│   └── AVEngineDemo/           Sample app with live metering
├── Samples/
│   └── HostSnippet/            Minimal integration example
├── Docs/                       Technical documentation
├── .github/
│   └── workflows/ci.yml        GitHub Actions CI
└── Package.swift               Root SPM manifest
```

---

## Linux Support

Linux builds compile the DSP bridge and Swift wrapper, but Audio Unit integration is stubbed out. `PortaDSPAudioUnit` throws `unsupportedPlatform` on Linux -- use the `PortaDSP` API directly for offline or server-side processing:

```swift
let dsp = PortaDSP(sampleRate: 48000.0, maxBlock: 512, tracks: 2)
dsp.update(PortaDSP.Params())

var buffer: [Float] = // ... your audio data
dsp.processInterleaved(buffer: &buffer, frames: frameCount, channels: 2)
```

---

## CI

Continuous integration runs on every push to `main` and on all pull requests via GitHub Actions:

- **macOS** -- full build and test suite on `macos-latest`
- **Linux** -- build and test on `ubuntu-latest` with Swift 5.9

---

## Further Reading

- [Parameter Bridge & Render Flow](Docs/params-bridge-and-render.md) -- deep dive into the Swift-C bridging layer and Audio Unit render lifecycle
- [AVEngine Demo README](Examples/AVEngineDemo/README.md) -- sample app walkthrough
