/*
 * Porta424 — Web MIDI integration
 *
 * Requests MIDI access, wires note on/off to the synth, and maps a handful of
 * MIDI CC controllers onto the tape knobs (so a hardware controller can drive
 * the tape character live). Handles device hot-plug and graceful fallback when
 * Web MIDI is unsupported or denied.
 *
 * CC map (common defaults):
 *   CC1  (mod wheel) -> wow
 *   CC74 (filter)    -> bandwidth
 *   CC71 (resonance) -> saturation
 *   CC76 (vibrato)   -> flutter
 *   CC91 (reverb)    -> noise
 */
const CC_MAP = { 1: 'wow', 74: 'bandwidth', 71: 'saturation', 76: 'flutter', 91: 'noise' };

export class MidiController {
  constructor({ onNoteOn, onNoteOff, onControl, onDevices, onStatus }) {
    this.onNoteOn = onNoteOn;
    this.onNoteOff = onNoteOff;
    this.onControl = onControl;     // (paramName, value0to1)
    this.onDevices = onDevices;     // (array of input names)
    this.onStatus = onStatus;       // (statusString)
    this.access = null;
    this.supported = typeof navigator !== 'undefined' && !!navigator.requestMIDIAccess;
  }

  async init() {
    if (!this.supported) { this.onStatus?.('unsupported'); return false; }
    try {
      this.access = await navigator.requestMIDIAccess({ sysex: false });
      this.access.onstatechange = () => this._bindInputs();
      this._bindInputs();
      this.onStatus?.('ready');
      return true;
    } catch (err) {
      console.warn('MIDI access denied/failed:', err);
      this.onStatus?.('denied');
      return false;
    }
  }

  _bindInputs() {
    if (!this.access) return;
    const names = [];
    for (const input of this.access.inputs.values()) {
      input.onmidimessage = (e) => this._handle(e.data);
      names.push(input.name || 'MIDI device');
    }
    this.onDevices?.(names);
    this.onStatus?.(names.length ? 'connected' : 'ready');
  }

  _handle(data) {
    const status = data[0] & 0xf0;
    const d1 = data[1], d2 = data[2];
    if (status === 0x90 && d2 > 0) this.onNoteOn?.(d1, d2);
    else if (status === 0x80 || (status === 0x90 && d2 === 0)) this.onNoteOff?.(d1);
    else if (status === 0xb0) {
      const name = CC_MAP[d1];
      if (name) this.onControl?.(name, d2 / 127);
    }
  }
}
