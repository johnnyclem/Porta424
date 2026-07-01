/*
 * Porta424 — factory presets
 *
 * Ported verbatim from
 * Packages/PortaDSPKit/Sources/PortaDSPKit/PortaDSPFactoryPresets.swift.
 * Raw values are real DSP units (dB / Hz / ms); toUI() converts them to the
 * normalized 0..1 knob values using the same math as
 * App/Sources/Models/DSPState.swift (DSPState.from / toParams).
 */

export const FACTORY_PRESETS = [
  { id: 'clean-cassette', name: 'Clean Cassette', blurb: 'Balanced, lightly coloured tape.',
    p: { wowDepth: 0.0005, flutterDepth: 0.00025, headBumpGainDb: 1.5, headBumpFreqHz: 85, satDriveDb: -5,  hissLevelDbFS: -65, lpfCutoffHz: 13500, dropoutRatePerMin: 0.15 } },
  { id: 'warm-bump', name: 'Warm Bump', blurb: 'Extra head bump for a low-end lift.',
    p: { wowDepth: 0.0007, flutterDepth: 0.00035, headBumpGainDb: 4.0, headBumpFreqHz: 78, satDriveDb: -3,  hissLevelDbFS: -60, lpfCutoffHz: 12000, dropoutRatePerMin: 0.25 } },
  { id: 'lo-fi-warble', name: 'Lo-Fi Warble', blurb: 'Heavy modulation and hiss.',
    p: { wowDepth: 0.0014, flutterDepth: 0.0008,  headBumpGainDb: 2.0, headBumpFreqHz: 75, satDriveDb: -1,  hissLevelDbFS: -54, lpfCutoffHz: 9800,  dropoutRatePerMin: 0.45 } },
  { id: 'crunchy-saturation', name: 'Crunchy Saturation', blurb: 'Saturated mids, restrained wobble.',
    p: { wowDepth: 0.00055, flutterDepth: 0.00038, headBumpGainDb: 3.0, headBumpFreqHz: 90, satDriveDb: -2, hissLevelDbFS: -62, lpfCutoffHz: 11200, dropoutRatePerMin: 0.28 } },
  { id: 'dusty-archive', name: 'Dusty Archive', blurb: 'Narrow bandwidth, audible noise.',
    p: { wowDepth: 0.0011, flutterDepth: 0.0007,  headBumpGainDb: 1.2, headBumpFreqHz: 68, satDriveDb: -0.5, hissLevelDbFS: -50, lpfCutoffHz: 8000, dropoutRatePerMin: 0.55 } },
];

// Convert stored DSP units to normalized 0..1 UI knob values (DSPState.from).
export function presetToUI(preset) {
  const p = preset.p;
  return {
    saturation: (p.satDriveDb + 24) / 48,
    wow: clamp01(p.wowDepth / 0.005),
    flutter: clamp01(p.flutterDepth / 0.003),
    noise: (p.hissLevelDbFS + 120) / 100,
    bandwidth: (p.lpfCutoffHz - 1000) / 19000,
    dropouts: clamp01(p.dropoutRatePerMin / 0.6),
    headBumpGainDb: p.headBumpGainDb,
    headBumpFreqHz: p.headBumpFreqHz,
  };
}

function clamp01(v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
