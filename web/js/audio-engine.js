/*
 * Porta424 — Web Audio engine
 *
 * Graph (per channel 1..6):
 *   sourceBus --> chanInput(trim) --> eqLow --> eqMid --> eqHigh
 *             --> panner --> chanFader --> chanMeter(analyser) --> mixBus
 *
 * Master tape path:
 *   mixBus --> inputGain --> [tape-worklet: wow/flutter, sat, hiss, dropouts]
 *          --> headBump(peaking biquad) --> bandwidth(lowpass)
 *          --> masterGain --> masterMeter(analyser) --> destination
 *
 * If AudioWorklet is unavailable we degrade to a WaveShaper (tanh) plus a noise
 * buffer for hiss; wow/flutter/dropouts are skipped (reported to the UI).
 */

const NUM_CHANNELS = 6;

export class AudioEngine {
  constructor() {
    this.ctx = null;
    this.started = false;
    this.usingWorklet = false;
    this.channels = [];      // per-channel node bundles
    this.sources = {};       // named source buses: synth, mic, file
    this.tape = null;        // worklet node or fallback
    this._tapeParams = { saturation: 0.35, wow: 0.3, flutter: 0.25, noise: 0.2, dropouts: 0.2 };
    this._fallbackHiss = null;
  }

  // Must be called from a user gesture (autoplay policy).
  async start() {
    if (this.started) {
      if (this.ctx.state === 'suspended') await this.ctx.resume();
      return;
    }
    const Ctx = window.AudioContext || window.webkitAudioContext;
    this.ctx = new Ctx({ latencyHint: 'interactive' });
    const ctx = this.ctx;

    // ---- Master tape chain ----
    this.inputGain = ctx.createGain();
    this.inputGain.gain.value = 1;

    // Try the worklet; fall back gracefully.
    try {
      if (!ctx.audioWorklet) throw new Error('no audioWorklet');
      await ctx.audioWorklet.addModule('js/tape-worklet.js');
      this.tape = new AudioWorkletNode(ctx, 'tape-processor', {
        numberOfInputs: 1, numberOfOutputs: 1,
        outputChannelCount: [2],
      });
      this.usingWorklet = true;
    } catch (err) {
      console.warn('AudioWorklet unavailable, using fallback tape path:', err);
      this.tape = this._buildFallbackTape();
      this.usingWorklet = false;
    }

    // Head bump: peaking biquad (~80 Hz, Q 1.4) — mirrors head_bump.h.
    this.headBump = ctx.createBiquadFilter();
    this.headBump.type = 'peaking';
    this.headBump.frequency.value = 80;
    this.headBump.Q.value = 1.4;
    this.headBump.gain.value = 2.5;

    // Bandwidth roll-off: lowpass (1k..20k) — mirrors hf_loss / lpfCutoffHz.
    this.bandwidth = ctx.createBiquadFilter();
    this.bandwidth.type = 'lowpass';
    this.bandwidth.frequency.value = 14000;
    this.bandwidth.Q.value = 0.7;

    this.masterGain = ctx.createGain();
    this.masterGain.gain.value = 0.75;

    this.masterMeter = ctx.createAnalyser();
    this.masterMeter.fftSize = 1024;
    this.masterMeter.smoothingTimeConstant = 0.3;

    // mixBus collects all channels.
    this.mixBus = ctx.createGain();
    this.mixBus.gain.value = 1;

    this.mixBus
      .connect(this.inputGain)
      .connect(this.tape)
      .connect(this.headBump)
      .connect(this.bandwidth)
      .connect(this.masterGain);
    this.masterGain.connect(this.masterMeter);
    this.masterGain.connect(ctx.destination);

    // ---- Channel strips ----
    for (let i = 0; i < NUM_CHANNELS; i++) this.channels.push(this._buildChannel(i + 1));

    // Apply initial tape params.
    this.setTapeParams(this._tapeParams);

    this.started = true;
  }

  _buildChannel(id) {
    const ctx = this.ctx;
    const input = ctx.createGain();   input.gain.value = 0.6;   // trim
    const eqLow = ctx.createBiquadFilter();  eqLow.type = 'lowshelf';  eqLow.frequency.value = 120;
    const eqMid = ctx.createBiquadFilter();  eqMid.type = 'peaking';   eqMid.frequency.value = 1000; eqMid.Q.value = 0.8;
    const eqHigh = ctx.createBiquadFilter(); eqHigh.type = 'highshelf'; eqHigh.frequency.value = 6000;
    const panner = ctx.createStereoPanner();
    const fader = ctx.createGain();   fader.gain.value = 0.65;
    const meter = ctx.createAnalyser(); meter.fftSize = 512; meter.smoothingTimeConstant = 0.4;

    input.connect(eqLow).connect(eqMid).connect(eqHigh).connect(panner).connect(fader);
    fader.connect(meter);
    fader.connect(this.mixBus);

    return {
      id, input, eqLow, eqMid, eqHigh, panner, fader, meter,
      sourceName: null, sourceTap: null,
    };
  }

  // Route a named source bus into a channel (one source can feed many channels).
  routeSource(channelIndex, sourceName) {
    const ch = this.channels[channelIndex];
    if (!ch) return;
    if (ch.sourceTap) { try { ch.sourceTap.disconnect(); } catch (e) {} ch.sourceTap = null; }
    ch.sourceName = sourceName;
    const bus = sourceName ? this.sources[sourceName] : null;
    if (bus) {
      const tap = this.ctx.createGain();
      tap.gain.value = 1;
      bus.connect(tap).connect(ch.input);
      ch.sourceTap = tap;
    }
  }

  // Register a source output node under a name (synth/mic/file).
  registerSource(name, node) { this.sources[name] = node; }

  // ---- Fallback tape (no worklet) ----
  _buildFallbackTape() {
    const ctx = this.ctx;
    const inGain = ctx.createGain();
    const shaper = ctx.createWaveShaper();
    shaper.curve = this._tanhCurve(1);
    const out = ctx.createGain();
    inGain.connect(shaper).connect(out);

    // Additive hiss via a looping noise buffer.
    const noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    const noise = ctx.createBufferSource();
    noise.buffer = noiseBuf; noise.loop = true;
    const hissGain = ctx.createGain(); hissGain.gain.value = 0;
    noise.connect(hissGain).connect(out);
    noise.start();
    this._fallbackHiss = hissGain;
    this._fallbackShaper = shaper;

    // Expose connect()/disconnect() pass-through to look like a single node.
    const proxy = inGain;
    proxy.connect = ((orig) => (...args) => { out.connect(...args); return args[0]; })(inGain.connect);
    return proxy;
  }

  _tanhCurve(drive) {
    const n = 2048, curve = new Float32Array(n);
    for (let i = 0; i < n; i++) {
      const x = (i / (n - 1)) * 2 - 1;
      curve[i] = Math.tanh(x * drive);
    }
    return curve;
  }

  // ---- Parameter setters ----
  setTapeParams(p) {
    Object.assign(this._tapeParams, p);
    if (!this.started) return;
    if (this.usingWorklet) {
      this.tape.port.postMessage({ type: 'params', values: this._tapeParams });
    } else {
      // Approximate with native nodes.
      if (p.saturation != null) {
        const drive = Math.pow(10, (p.saturation * 48 - 24) / 20);
        this._fallbackShaper.curve = this._tanhCurve(Math.max(0.5, drive));
      }
      if (p.noise != null && this._fallbackHiss) {
        const amp = p.noise <= 0.001 ? 0 : Math.pow(10, (p.noise * 100 - 120) / 20);
        this._fallbackHiss.gain.setTargetAtTime(amp, this.ctx.currentTime, 0.05);
      }
    }
  }

  setHeadBump(gainDb, freqHz) {
    if (!this.started) return;
    if (gainDb != null) this.headBump.gain.setTargetAtTime(gainDb, this.ctx.currentTime, 0.02);
    if (freqHz != null) this.headBump.frequency.setTargetAtTime(freqHz, this.ctx.currentTime, 0.02);
  }

  setBandwidth(norm) { // 0..1 -> 1k..20k
    if (!this.started) return;
    const hz = 1000 + norm * 19000;
    this.bandwidth.frequency.setTargetAtTime(hz, this.ctx.currentTime, 0.02);
  }

  setInputGain(norm) { if (this.started) this.inputGain.gain.setTargetAtTime(0.2 + norm * 1.6, this.ctx.currentTime, 0.02); }
  setMasterVolume(norm) { if (this.started) this.masterGain.gain.setTargetAtTime(norm, this.ctx.currentTime, 0.02); }
  setBypass(on) { if (this.usingWorklet && this.started) this.tape.port.postMessage({ type: 'bypass', value: on }); }

  // ---- Channel setters (all 0..1 unless noted) ----
  setChannelTrim(i, v)  { const c = this.channels[i]; if (c) c.input.gain.setTargetAtTime(0.1 + v * 1.9, this.ctx.currentTime, 0.02); }
  setChannelLevel(i, v) { const c = this.channels[i]; if (c) c.fader.gain.setTargetAtTime(v, this.ctx.currentTime, 0.02); }
  setChannelPan(i, v)   { const c = this.channels[i]; if (c) c.panner.pan.setTargetAtTime(v * 2 - 1, this.ctx.currentTime, 0.02); }
  setChannelEq(i, band, v) { // v 0..1 centered at 0.5 -> -12..+12 dB
    const c = this.channels[i]; if (!c) return;
    const db = (v - 0.5) * 24;
    const f = band === 'low' ? c.eqLow : band === 'mid' ? c.eqMid : c.eqHigh;
    f.gain.setTargetAtTime(db, this.ctx.currentTime, 0.02);
  }
  muteChannel(i, on) { const c = this.channels[i]; if (c) c.fader.gain.setTargetAtTime(on ? 0 : (c._lastLevel ?? 0.65), this.ctx.currentTime, 0.02); }

  // ---- Metering ----
  channelLevel(i) { return this._rms(this.channels[i]?.meter); }
  masterLevel() { return this._rms(this.masterMeter); }

  _rms(analyser) {
    if (!analyser) return 0;
    if (!analyser._buf) analyser._buf = new Float32Array(analyser.fftSize);
    const buf = analyser._buf;
    analyser.getFloatTimeDomainData(buf);
    let sum = 0;
    for (let i = 0; i < buf.length; i++) sum += buf[i] * buf[i];
    return Math.sqrt(sum / buf.length); // 0..~1
  }

  get sampleRate() { return this.ctx ? this.ctx.sampleRate : 44100; }
}

export { NUM_CHANNELS };
