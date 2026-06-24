/*
 * Porta424 — built-in polyphonic synth
 *
 * A small subtractive voice (two detuned saws + a sine sub through a lowpass with
 * an ADSR amp envelope). Its output is a single GainNode bus that the audio
 * engine routes into mixer channels. Driven by Web MIDI and the on-screen /
 * computer keyboard.
 */

export class Synth {
  constructor(ctx) {
    this.ctx = ctx;
    this.out = ctx.createGain();
    this.out.gain.value = 0.5;
    this.voices = new Map();   // midiNote -> voice
    this.params = { attack: 0.005, decay: 0.12, sustain: 0.7, release: 0.25, cutoff: 4000, wave: 'sawtooth' };
  }

  get output() { return this.out; }

  static mtof(note) { return 440 * Math.pow(2, (note - 69) / 12); }

  noteOn(note, velocity = 100) {
    if (this.voices.has(note)) this._kill(note, true);
    const ctx = this.ctx, now = ctx.currentTime;
    const freq = Synth.mtof(note);
    const vel = Math.max(0.05, velocity / 127);

    const oscA = ctx.createOscillator(); oscA.type = this.params.wave; oscA.frequency.value = freq; oscA.detune.value = -6;
    const oscB = ctx.createOscillator(); oscB.type = this.params.wave; oscB.frequency.value = freq; oscB.detune.value = +6;
    const sub  = ctx.createOscillator(); sub.type = 'sine'; sub.frequency.value = freq / 2;

    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = this.params.cutoff;
    filter.Q.value = 0.8;

    const amp = ctx.createGain();
    amp.gain.value = 0;

    oscA.connect(filter); oscB.connect(filter); sub.connect(filter);
    filter.connect(amp).connect(this.out);

    // ADSR (attack -> decay -> sustain).
    const peak = 0.32 * vel;
    amp.gain.cancelScheduledValues(now);
    amp.gain.setValueAtTime(0, now);
    amp.gain.linearRampToValueAtTime(peak, now + this.params.attack);
    amp.gain.linearRampToValueAtTime(peak * this.params.sustain, now + this.params.attack + this.params.decay);

    oscA.start(now); oscB.start(now); sub.start(now);
    this.voices.set(note, { oscA, oscB, sub, amp, filter });
  }

  noteOff(note) {
    const v = this.voices.get(note);
    if (!v) return;
    const now = this.ctx.currentTime, r = this.params.release;
    v.amp.gain.cancelScheduledValues(now);
    v.amp.gain.setValueAtTime(v.amp.gain.value, now);
    v.amp.gain.linearRampToValueAtTime(0, now + r);
    const stopAt = now + r + 0.02;
    v.oscA.stop(stopAt); v.oscB.stop(stopAt); v.sub.stop(stopAt);
    this.voices.delete(note);
  }

  _kill(note, immediate) {
    const v = this.voices.get(note);
    if (!v) return;
    const t = this.ctx.currentTime + (immediate ? 0.005 : 0);
    try { v.oscA.stop(t); v.oscB.stop(t); v.sub.stop(t); } catch (e) {}
    this.voices.delete(note);
  }

  allNotesOff() { for (const n of [...this.voices.keys()]) this.noteOff(n); }

  setWave(wave) { this.params.wave = wave; }
  setCutoff(hz) { this.params.cutoff = hz; }
}
