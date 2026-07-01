/*
 * Porta424 — demo orchestration
 *
 * Boots the audio engine on a user gesture, builds the skeuomorphic 4-track
 * deck (6 mixer strips + tape character panel + transport + keyboard), and
 * wires every control to live Web Audio. Web MIDI drives the synth and the
 * tape knobs.
 */
import { AudioEngine, NUM_CHANNELS } from './audio-engine.js';
import { Synth } from './synth.js';
import { MidiController } from './midi.js';
import { Knob, Fader } from './ui-controls.js';
import { FACTORY_PRESETS, presetToUI } from './presets.js';

const ACCENT = {
  saturation: '#e68026', wow: '#40b372', flutter: '#408cd8',
  noise: '#8d4dc0', bandwidth: '#408cd8', input: '#e68026', master: '#40b372',
};
const $ = (sel, root = document) => root.querySelector(sel);

const engine = new AudioEngine();
let synth = null;
let midi = null;
const tapeKnobs = {};       // name -> Knob
let booted = false;
let transport = 'stopped';  // stopped|playing|recording
let tapePosition = 0;       // seconds-ish counter
let reelAngle = 0;
const channelUI = [];       // per-channel {meterFill, els}

// ---------- DOM helpers ----------
function el(tag, cls, parent) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (parent) parent.appendChild(n);
  return n;
}

function makeKnob(parent, { label, accent, value, def, onChange, small }) {
  const wrap = el('div', 'knob-wrap' + (small ? ' small' : ''), parent);
  const knobEl = el('div', 'knob', wrap);
  const lab = el('span', 'knob-label', wrap);
  lab.textContent = label;
  return new Knob(knobEl, { value, defaultValue: def ?? value, accent, label, onChange });
}

// ---------- Boot ----------
async function boot() {
  if (booted) { await engine.start(); return; }
  await engine.start();
  synth = new Synth(engine.ctx);
  engine.registerSource('synth', synth.output);

  buildTapePanel();
  buildChannels();
  buildPresets();
  buildKeyboard();
  bindTransport();

  // Default routing: synth into channel 1.
  setChannelSource(0, 'synth');

  // Reflect whether the real worklet DSP is active.
  const badge = $('#dsp-badge');
  if (badge) {
    badge.textContent = engine.usingWorklet ? 'AudioWorklet DSP active' : 'Fallback DSP (no AudioWorklet)';
    badge.classList.toggle('warn', !engine.usingWorklet);
  }

  booted = true;
  $('#power-btn').classList.add('on');
  $('#power-btn').setAttribute('aria-pressed', 'true');
  $('.demo-deck').classList.add('powered');
  requestAnimationFrame(loop);
}

// ---------- Tape character panel ----------
function buildTapePanel() {
  const host = $('#tape-knobs');
  host.innerHTML = '';
  const defs = [
    ['saturation', 'SATURATION', 0.35, ACCENT.saturation],
    ['wow', 'WOW', 0.3, ACCENT.wow],
    ['flutter', 'FLUTTER', 0.25, ACCENT.flutter],
    ['noise', 'NOISE', 0.2, ACCENT.noise],
    ['bandwidth', 'BANDWIDTH', 0.7, ACCENT.bandwidth],
  ];
  for (const [name, label, val, accent] of defs) {
    tapeKnobs[name] = makeKnob(host, {
      label, accent, value: val,
      onChange: (v) => applyTapeKnob(name, v),
    });
  }
  // Input / master live on the master strip.
  tapeKnobs.input = makeKnob($('#io-knobs'), {
    label: 'INPUT', accent: ACCENT.input, value: 0.65,
    onChange: (v) => engine.setInputGain(v),
  });
  tapeKnobs.master = makeKnob($('#io-knobs'), {
    label: 'MASTER', accent: ACCENT.master, value: 0.75,
    onChange: (v) => engine.setMasterVolume(v),
  });
}

function applyTapeKnob(name, v) {
  if (name === 'bandwidth') engine.setBandwidth(v);
  else engine.setTapeParams({ [name]: v });
}

// ---------- Mixer channels ----------
function buildChannels() {
  const host = $('#mixer-strips');
  host.innerHTML = '';
  for (let i = 0; i < NUM_CHANNELS; i++) {
    const strip = el('div', 'strip', host);
    el('div', 'strip-num', strip).textContent = i + 1;

    // Source selector.
    const sel = el('select', 'src-select', strip);
    for (const [val, txt] of [['none', '—'], ['synth', 'SYN'], ['mic', 'MIC'], ['file', 'FILE']]) {
      const o = el('option', null, sel); o.value = val; o.textContent = txt;
    }
    sel.value = i === 0 ? 'synth' : 'none';
    sel.addEventListener('change', () => setChannelSource(i, sel.value));

    // EQ knobs.
    const eq = el('div', 'eq-stack', strip);
    makeKnob(eq, { label: 'HI', small: true, value: 0.5, def: 0.5, onChange: (v) => engine.setChannelEq(i, 'high', v) });
    makeKnob(eq, { label: 'MID', small: true, value: 0.5, def: 0.5, onChange: (v) => engine.setChannelEq(i, 'mid', v) });
    makeKnob(eq, { label: 'LO', small: true, value: 0.5, def: 0.5, onChange: (v) => engine.setChannelEq(i, 'low', v) });
    makeKnob(eq, { label: 'PAN', small: true, value: 0.5, def: 0.5, onChange: (v) => engine.setChannelPan(i, v) });
    makeKnob(eq, { label: 'TRIM', small: true, value: 0.6, onChange: (v) => engine.setChannelTrim(i, v) });

    // Meter + fader row.
    const row = el('div', 'fader-row', strip);
    const meter = el('div', 'vu', row);
    const fill = el('div', 'vu-fill', meter);
    const faderEl = el('div', 'fader', row);
    new Fader(faderEl, { value: 0.65, accent: i % 2 ? '#e6952c' : '#5ab85f', label: `Channel ${i + 1} level`,
      onChange: (v) => engine.setChannelLevel(i, v) });

    // Arm button.
    const arm = el('button', 'arm-btn', strip);
    arm.textContent = 'REC';
    arm.setAttribute('aria-pressed', 'false');
    arm.addEventListener('click', () => {
      const on = arm.classList.toggle('armed');
      arm.setAttribute('aria-pressed', String(on));
    });

    channelUI.push({ fill, sel });
  }
}

let micRequested = false, fileRequested = false;
async function setChannelSource(i, name) {
  if (name === 'mic' && !engine.sources.mic) { await enableMic(); }
  if (name === 'file' && !engine.sources.file) { $('#file-input').click(); }
  engine.routeSource(i, name === 'none' ? null : name);
}

// ---------- Presets ----------
function buildPresets() {
  const host = $('#preset-row');
  host.innerHTML = '';
  for (const preset of FACTORY_PRESETS) {
    const b = el('button', 'preset-btn', host);
    el('span', 'preset-name', b).textContent = preset.name;
    el('span', 'preset-blurb', b).textContent = preset.blurb;
    b.addEventListener('click', () => applyPreset(preset, b));
  }
}

function applyPreset(preset, btn) {
  const ui = presetToUI(preset);
  // Move the knobs (which emit to the engine).
  tapeKnobs.saturation.set(ui.saturation);
  tapeKnobs.wow.set(ui.wow);
  tapeKnobs.flutter.set(ui.flutter);
  tapeKnobs.noise.set(ui.noise);
  tapeKnobs.bandwidth.set(ui.bandwidth);
  engine.setTapeParams({ dropouts: ui.dropouts });
  engine.setHeadBump(ui.headBumpGainDb, ui.headBumpFreqHz);
  document.querySelectorAll('.preset-btn').forEach((x) => x.classList.remove('active'));
  if (btn) btn.classList.add('active');
}

// ---------- Transport ----------
function bindTransport() {
  $('#t-play').addEventListener('click', () => setTransport(transport === 'playing' ? 'stopped' : 'playing'));
  $('#t-stop').addEventListener('click', () => setTransport('stopped'));
  $('#t-rec').addEventListener('click', () => setTransport(transport === 'recording' ? 'stopped' : 'recording'));
}

function setTransport(mode) {
  transport = mode;
  $('.demo-deck').dataset.transport = mode;
  $('#t-play').classList.toggle('active', mode === 'playing');
  $('#t-rec').classList.toggle('active', mode === 'recording');
}

// ---------- Keyboard (on-screen + computer) ----------
const KEY_ROW = ['a', 'w', 's', 'e', 'd', 'f', 't', 'g', 'y', 'h', 'u', 'j', 'k', 'o', 'l', 'p', ';'];
function buildKeyboard() {
  const host = $('#keyboard');
  host.innerHTML = '';
  const startNote = 60; // C4
  const blackOffsets = new Set([1, 3, 6, 8, 10]);
  for (let n = startNote; n < startNote + 17; n++) {
    const isBlack = blackOffsets.has((n - startNote) % 12);
    const key = el('div', 'key' + (isBlack ? ' black' : ' white'), host);
    key.dataset.note = n;
    const press = (e) => { e.preventDefault(); pressKey(n, key); };
    const release = (e) => { e.preventDefault(); releaseKey(n, key); };
    key.addEventListener('pointerdown', press);
    key.addEventListener('pointerup', release);
    key.addEventListener('pointerleave', (e) => { if (e.buttons) releaseKey(n, key); });
  }

  const pressedComputer = new Set();
  window.addEventListener('keydown', (e) => {
    if (e.repeat || !booted) return;
    const idx = KEY_ROW.indexOf(e.key.toLowerCase());
    if (idx < 0) return;
    const note = 60 + idx;
    if (pressedComputer.has(note)) return;
    pressedComputer.add(note);
    const keyEl = host.querySelector(`[data-note="${note}"]`);
    pressKey(note, keyEl);
  });
  window.addEventListener('keyup', (e) => {
    const idx = KEY_ROW.indexOf(e.key.toLowerCase());
    if (idx < 0) return;
    const note = 60 + idx;
    pressedComputer.delete(note);
    const keyEl = host.querySelector(`[data-note="${note}"]`);
    releaseKey(note, keyEl);
  });
}

function pressKey(note, keyEl) { if (synth) synth.noteOn(note, 100); if (keyEl) keyEl.classList.add('down'); }
function releaseKey(note, keyEl) { if (synth) synth.noteOff(note); if (keyEl) keyEl.classList.remove('down'); }

// ---------- MIDI ----------
async function initMidi() {
  await boot();
  midi = new MidiController({
    onNoteOn: (n, v) => { synth.noteOn(n, v); flashKey(n, true); },
    onNoteOff: (n) => { synth.noteOff(n); flashKey(n, false); },
    onControl: (name, v) => { if (tapeKnobs[name]) tapeKnobs[name].set(v); },
    onDevices: (names) => { $('#midi-status').textContent = names.length ? `MIDI: ${names.join(', ')}` : 'MIDI: ready (no devices)'; },
    onStatus: (s) => {
      const map = { unsupported: 'Web MIDI not supported in this browser', denied: 'MIDI access denied', ready: 'MIDI: ready', connected: 'MIDI: connected' };
      if (s === 'unsupported' || s === 'denied') $('#midi-status').textContent = map[s];
    },
  });
  const ok = await midi.init();
  $('#midi-btn').classList.toggle('on', ok);
}

function flashKey(note, on) {
  const k = document.querySelector(`#keyboard [data-note="${note}"]`);
  if (k) k.classList.toggle('down', on);
}

// ---------- Mic + file sources ----------
async function enableMic() {
  if (micRequested) return;
  micRequested = true;
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false } });
    const src = engine.ctx.createMediaStreamSource(stream);
    engine.registerSource('mic', src);
    $('#mic-hint').textContent = 'Mic live — beware of feedback; use headphones.';
  } catch (err) {
    micRequested = false;
    $('#mic-hint').textContent = 'Microphone permission denied.';
  }
}

async function loadFile(file) {
  await boot();
  const buf = await file.arrayBuffer();
  const audioBuf = await engine.ctx.decodeAudioData(buf);
  if (engine._fileNode) { try { engine._fileNode.stop(); } catch (e) {} }
  const bus = engine.sources.file || engine.ctx.createGain();
  engine.registerSource('file', bus);
  const node = engine.ctx.createBufferSource();
  node.buffer = audioBuf; node.loop = true;
  node.connect(bus); node.start();
  engine._fileNode = node;
  // Auto-route to channel 2 for convenience.
  channelUI[1].sel.value = 'file';
  engine.routeSource(1, 'file');
  $('#file-hint').textContent = `Looping: ${file.name}`;
}

// ---------- Animation loop: meters, reels, counter ----------
function loop() {
  // VU meters.
  for (let i = 0; i < channelUI.length; i++) {
    const lvl = engine.channelLevel(i);
    setMeter(channelUI[i].fill, lvl);
  }
  const m = engine.masterLevel();
  const mf = $('#master-vu-fill');
  if (mf) setMeter(mf, m);

  // Reels + counter advance while playing/recording.
  if (transport !== 'stopped') {
    reelAngle = (reelAngle + 3.2) % 360;
    tapePosition += 1 / 60;
    document.querySelectorAll('.reel-core').forEach((r) => { r.style.transform = `rotate(${reelAngle}deg)`; });
    updateCounter(tapePosition);
  }
  requestAnimationFrame(loop);
}

function setMeter(fill, level) {
  // Perceptual-ish scaling; clamp.
  const db = 20 * Math.log10(level + 1e-6);
  const norm = Math.max(0, Math.min(1, (db + 48) / 48));
  fill.style.height = (norm * 100).toFixed(1) + '%';
}

function updateCounter(seconds) {
  const total = Math.floor(seconds);
  const mm = String(Math.floor(total / 60)).padStart(2, '0');
  const ss = String(total % 60).padStart(2, '0');
  const counter = $('#tape-counter');
  if (counter) counter.textContent = `${mm}:${ss}`;
}

// ---------- Bindings for top-level buttons ----------
function init() {
  $('#power-btn').addEventListener('click', boot);
  $('#midi-btn').addEventListener('click', initMidi);
  $('#mic-btn').addEventListener('click', async () => { await boot(); await enableMic(); });

  const fileInput = $('#file-input');
  $('#file-btn').addEventListener('click', () => fileInput.click());
  fileInput.addEventListener('change', (e) => { if (e.target.files[0]) loadFile(e.target.files[0]); });

  const deck = $('.demo-deck');
  ['dragover', 'drop'].forEach((t) => deck.addEventListener(t, (e) => e.preventDefault()));
  deck.addEventListener('drop', (e) => {
    const f = e.dataTransfer.files[0];
    if (f && f.type.startsWith('audio')) loadFile(f);
  });

  // CTA buttons that scroll to the demo also power it on.
  document.querySelectorAll('[data-scroll-demo]').forEach((b) =>
    b.addEventListener('click', () => $('#demo').scrollIntoView({ behavior: 'smooth' })));

  // Bypass toggle (A/B the tape character).
  const bypass = $('#bypass-btn');
  if (bypass) bypass.addEventListener('click', () => {
    const on = bypass.classList.toggle('on');
    engine.setBypass(on);
    bypass.textContent = on ? 'TAPE: BYPASSED' : 'TAPE: ENGAGED';
  });

  // Footer year.
  const y = $('#year'); if (y) y.textContent = '2026';
}

document.addEventListener('DOMContentLoaded', init);
