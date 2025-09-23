# Parameters bridge and render flow

This document provides deeper notes on how PortaDSPKit moves parameter data between Swift and the C++ core, and how the real-time render loop is structured inside the Audio Unit implementation.

## Swift ↔︎ C parameter bridge

`PortaDSP.Params` is the Swift-facing container for end-user controls such as wow/flutter depth, head-bump settings, and hiss. When it is time to cross the module boundary, the `makeCParams()` helper converts every Swift property into the C-compatible `porta_params_t` struct that the DSP core expects.

```swift
func makeCParams() -> porta_params_t {
    porta_params_t(
        wowDepth: wowDepth,
        flutterDepth: flutterDepth,
        headBumpGainDb: headBumpGainDb,
        headBumpFreqHz: headBumpFreqHz,
        satDriveDb: satDriveDb,
        hissLevelDbFS: hissLevelDbFS,
        lpfCutoffHz: lpfCutoffHz,
        azimuthJitterMs: azimuthJitterMs,
        crosstalkDb: crosstalkDb,
        dropoutRatePerMin: dropoutRatePerMin,
        nrTrack4Bypass: nrTrack4Bypass ? 1 : 0
    )
}
```

Because booleans are represented as `Bool` in Swift and `int` in C, the bridge performs the necessary conversion (`true` → `1`, `false` → `0`). Floating-point values are passed through unchanged, letting the DSP leverage its native parameter smoothing.

The bridge function is used in two critical locations:

- `PortaDSP.update(_:)`, which forwards new parameter snapshots to the standalone DSP wrapper for offline processing or meter reads.
- `PortaDSPAudioUnit.updateParameters(_:)`, which keeps the Audio Unit's live render pipeline in sync with UI changes.

## Audio Unit render lifecycle

When an Audio Unit instance is allocated, PortaDSPKit pre-creates a scratch buffer and initializes a `porta_dsp_handle` with the session's sample rate, channel count, and maximum block size. This work happens inside `allocateRenderResources()` after verifying that input and output formats are compatible.

During each render callback the `internalRenderBlock` performs the following sequence:

1. Pull the upstream audio by invoking the provided `pullInputBlock`.
2. Copy the AudioToolbox planar or interleaved buffers into the module's interleaved scratch space.
3. Invoke `porta_process_interleaved` on the scratch buffer.
4. If the unit is not bypassed, write the processed samples back to the outgoing `AudioBufferList` in either interleaved or planar form.

The helper methods (`copyInterleavedBuffer`, `copyPlanarBuffer`, `writeInterleavedBuffer`, and `writePlanarBuffer`) isolate format handling and zero-filling logic. Should the platform not support AudioToolbox (such as Linux), the entire Audio Unit surface is replaced with lightweight stubs that throw `unsupportedPlatform`, signalling to host code that only the pure Swift `PortaDSP` API is currently available.
