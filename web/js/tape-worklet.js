/*
 * Porta424 — Tape character AudioWorkletProcessor
 *
 * A faithful, real-time port of the C++ DSPCore modules that native Web Audio
 * nodes can't express:
 *   - WowFlutter  (DSPCore/include/modules/wow_flutter.h)  modulated fractional delay
 *   - Saturation  (DSPCore/include/modules/saturation.h)   tanh soft clipper
 *   - Hiss        (DSPCore/include/modules/hiss.h)          additive colored noise
 *   - Dropouts    (DSPCore/include/modules/dropouts.h)      random amplitude dips
 *
 * Head-bump (peaking biquad) and bandwidth roll-off (lowpass) are handled by
 * native BiquadFilterNodes in audio-engine.js, exactly as the native build
 * splits them out.
 *
 * Parameters arrive over the message port as {type:'params', values:{...}} so we
 * can pass normalized 0..1 UI values and convert them here, mirroring
 * App/Sources/Models/DSPState.swift.
 */

const TWO_PI = Math.PI * 2;

// One independent tape path per channel (so stereo gets its own delay state,
// giving a subtle, realistic azimuth-style decorrelation).
class TapeVoice {
  constructor(sampleRate) {
    this.sr = sampleRate;
    // Delay line large enough for max wow+flutter excursion plus margin.
    this.bufLen = Math.max(64, Math.floor(sampleRate * 0.05));
    this.buffer = new Float32Array(this.bufLen);
    this.writeIndex = 0;
    this.wowPhase = Math.random() * TWO_PI;
    this.flutterPhase = Math.random() * TWO_PI;
    this.wowDrift = 0;
    this.driftCounter = 0;
    this.driftInterval = Math.max(1, Math.floor(sampleRate * 0.5));
    // Dropout envelope state.
    this.dropoutGain = 1;
    this.dropoutTarget = 1;
    this.dropoutSamplesLeft = 0;
    // One-pole state for gently colored hiss.
    this.hissLP = 0;
  }

  // depthSamples are already the peak excursion in samples for wow / flutter.
  process(input, wowRate, flutterRate, wowSamples, flutterSamples,
          driveLinear, outGain, hissAmp, dropoutProb) {
    // ---- Wow & flutter: modulated fractional delay line ----
    if (--this.driftCounter <= 0) {
      this.wowDrift = (Math.random() * 2 - 1) * 0.002;
      this.driftCounter = this.driftInterval;
    }
    this.wowPhase += (TWO_PI * wowRate) / this.sr + this.wowDrift;
    this.flutterPhase += (TWO_PI * flutterRate) / this.sr;
    if (this.wowPhase >= TWO_PI) this.wowPhase -= TWO_PI;
    if (this.flutterPhase >= TWO_PI) this.flutterPhase -= TWO_PI;

    const mod = Math.sin(this.wowPhase) * wowSamples +
                Math.sin(this.flutterPhase) * flutterSamples;

    // Center the read tap so modulation can swing both directions.
    const baseDelay = this.bufLen * 0.5;
    let readDelay = baseDelay + mod;
    if (readDelay < 1) readDelay = 1;
    if (readDelay > this.bufLen - 2) readDelay = this.bufLen - 2;

    this.buffer[this.writeIndex] = input;

    let readIndex = this.writeIndex - readDelay;
    while (readIndex < 0) readIndex += this.bufLen;
    const i0 = Math.floor(readIndex);
    const i1 = (i0 + 1) % this.bufLen;
    const frac = readIndex - i0;
    let x = this.buffer[i0] + (this.buffer[i1] - this.buffer[i0]) * frac;

    this.writeIndex = (this.writeIndex + 1) % this.bufLen;

    // ---- Saturation: tanh soft clip (saturation.h) ----
    x = Math.tanh(x * driveLinear) * outGain;

    // ---- Dropouts: random short amplitude dips (dropouts.h) ----
    if (this.dropoutSamplesLeft <= 0 && Math.random() < dropoutProb) {
      // Begin a dip 15–70 ms long, attenuating to 0.15–0.5.
      this.dropoutSamplesLeft = Math.floor((0.015 + Math.random() * 0.055) * this.sr);
      this.dropoutTarget = 0.15 + Math.random() * 0.35;
    }
    if (this.dropoutSamplesLeft > 0) {
      this.dropoutSamplesLeft--;
      if (this.dropoutSamplesLeft === 0) this.dropoutTarget = 1;
    }
    // Smooth toward target so dips fade in/out rather than click.
    this.dropoutGain += (this.dropoutTarget - this.dropoutGain) * 0.002;
    x *= this.dropoutGain;

    // ---- Hiss: additive, gently low-passed white noise (hiss.h) ----
    if (hissAmp > 0) {
      const white = Math.random() * 2 - 1;
      this.hissLP += 0.35 * (white - this.hissLP); // soften the very top end
      x += (white * 0.6 + this.hissLP * 0.4) * hissAmp;
    }

    return x;
  }
}

class TapeProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.sr = sampleRate;
    this.voices = [new TapeVoice(sampleRate), new TapeVoice(sampleRate)];

    // Smoothed, converted parameters.
    this.driveLinear = 1;
    this.outGain = 1;
    this.hissAmp = 0;
    this.wowSamples = 0;
    this.flutterSamples = 0;
    this.dropoutProb = 0;
    this.bypass = false;

    // Targets (set from messages), smoothed per-block toward these.
    this._targets = {
      driveLinear: 1, outGain: 1, hissAmp: 0,
      wowSamples: 0, flutterSamples: 0, dropoutProb: 0,
    };

    this.wowRate = 0.4;      // Hz, matches WowFlutter default
    this.flutterRate = 5.0;  // Hz, matches WowFlutter default

    this.port.onmessage = (e) => this._onMessage(e.data);
  }

  _onMessage(msg) {
    if (!msg) return;
    if (msg.type === 'params') this._applyParams(msg.values);
    else if (msg.type === 'bypass') this.bypass = !!msg.value;
  }

  // values are normalized 0..1 UI knobs; convert with DSPState.swift math.
  _applyParams(v) {
    const t = this._targets;
    if (typeof v.saturation === 'number') {
      const satDriveDb = v.saturation * 48 - 24;          // -24..+24 dB
      t.driveLinear = Math.pow(10, satDriveDb / 20);
      // Light makeup so heavy drive doesn't blow up perceived level.
      t.outGain = 1 / Math.sqrt(Math.max(1, t.driveLinear * 0.5));
    }
    if (typeof v.wow === 'number') {
      // Exaggerated vs. native (samples, not the sub-sample native amount) so
      // the wobble is clearly audible/visible in a browser demo.
      t.wowSamples = v.wow * (this.sr * 0.00035); // up to ~15 samples @44.1k
    }
    if (typeof v.flutter === 'number') {
      t.flutterSamples = v.flutter * (this.sr * 0.00012);
    }
    if (typeof v.noise === 'number') {
      const hissDbFS = v.noise * 100 - 120;               // -120..-20 dBFS
      t.hissAmp = v.noise <= 0.001 ? 0 : Math.pow(10, hissDbFS / 20);
    }
    if (typeof v.dropouts === 'number') {
      // dropouts 0..1 -> ~0..40 dips/min, converted to per-sample probability.
      const perMin = v.dropouts * 40;
      t.dropoutProb = (perMin / 60) / this.sr;
    }
  }

  process(inputs, outputs) {
    const input = inputs[0];
    const output = outputs[0];
    if (!output || output.length === 0) return true;

    // Smooth params once per block (k-rate) to avoid zipper noise.
    const t = this._targets, a = 0.25;
    this.driveLinear += (t.driveLinear - this.driveLinear) * a;
    this.outGain     += (t.outGain - this.outGain) * a;
    this.hissAmp     += (t.hissAmp - this.hissAmp) * a;
    this.wowSamples  += (t.wowSamples - this.wowSamples) * a;
    this.flutterSamples += (t.flutterSamples - this.flutterSamples) * a;
    this.dropoutProb += (t.dropoutProb - this.dropoutProb) * a;

    const frames = output[0].length;
    for (let ch = 0; ch < output.length; ch++) {
      const out = output[ch];
      const inp = input && input[ch] ? input[ch] : null;
      const voice = this.voices[ch] || this.voices[0];
      if (this.bypass) {
        if (inp) out.set(inp);
        else out.fill(0);
        continue;
      }
      for (let i = 0; i < frames; i++) {
        const dry = inp ? inp[i] : 0;
        out[i] = voice.process(
          dry, this.wowRate, this.flutterRate,
          this.wowSamples, this.flutterSamples,
          this.driveLinear, this.outGain, this.hissAmp, this.dropoutProb
        );
      }
    }
    return true;
  }
}

registerProcessor('tape-processor', TapeProcessor);
