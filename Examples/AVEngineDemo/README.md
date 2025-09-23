# AVEngineDemo

A minimal SwiftUI sample that demonstrates how to insert the PortaDSP audio unit into an `AVAudioEngine` graph. The demo routes the microphone input through PortaDSP's passthrough DSP and out to the system speakers for both iOS and macOS.

## Project Structure

- `Shared/` contains cross-platform SwiftUI views and the `AudioEngineManager` that configures the engine.
- `iOS/` and `macOS/` provide platform-specific `Info.plist` files with the microphone permission string.
- `AVEngineDemo.xcodeproj` defines two app targets: **AVEngineDemo iOS** and **AVEngineDemo macOS**.

## Running the Demo

1. Open `AVEngineDemo.xcodeproj` in Xcode 15 or newer.
2. Select either the iOS or macOS target.
3. Build and run on a device or simulator with microphone access.
4. Grant microphone permission when prompted, then tap/click **Start** to begin routing audio.

The PortaDSP unit is instantiated through the new `PortaDSPAudioUnit.makeEngineNode` helper and inserted between the input node and main mixer. With the default passthrough DSP the signal is left unmodified.
