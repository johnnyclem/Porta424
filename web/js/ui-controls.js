/*
 * Porta424 — reusable skeuomorphic controls
 *
 * Knob and Fader behave like ARIA sliders: pointer drag (vertical), wheel,
 * arrow keys, Home/End, and double-click-to-default. Values are normalized
 * 0..1; callers convert to audio units.
 */

function clamp01(v) { return v < 0 ? 0 : v > 1 ? 1 : v; }

export class Knob {
  // el: a .knob element. opts: { value, defaultValue, accent, label, onChange }
  constructor(el, opts = {}) {
    this.el = el;
    this.value = opts.value ?? 0.5;
    this.defaultValue = opts.defaultValue ?? this.value;
    this.onChange = opts.onChange || (() => {});
    this.accent = opts.accent;

    this.indicator = document.createElement('div');
    this.indicator.className = 'knob-indicator';
    el.appendChild(this.indicator);
    if (this.accent) el.style.setProperty('--accent', this.accent);

    el.setAttribute('role', 'slider');
    el.setAttribute('tabindex', '0');
    el.setAttribute('aria-valuemin', '0');
    el.setAttribute('aria-valuemax', '100');
    if (opts.label) el.setAttribute('aria-label', opts.label);

    this._bind();
    this.set(this.value, false);
  }

  _bind() {
    let startY = 0, startVal = 0, dragging = false;
    const onMove = (e) => {
      if (!dragging) return;
      const y = (e.touches ? e.touches[0].clientY : e.clientY);
      const dy = startY - y;
      this.set(startVal + dy / 200);
      e.preventDefault();
    };
    const onUp = () => {
      dragging = false;
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
      this.el.classList.remove('dragging');
    };
    this.el.addEventListener('pointerdown', (e) => {
      dragging = true;
      startY = e.clientY; startVal = this.value;
      this.el.classList.add('dragging'); this.el.focus();
      window.addEventListener('pointermove', onMove);
      window.addEventListener('pointerup', onUp);
      e.preventDefault();
    });
    this.el.addEventListener('wheel', (e) => {
      this.set(this.value - Math.sign(e.deltaY) * 0.03); e.preventDefault();
    }, { passive: false });
    this.el.addEventListener('dblclick', () => this.set(this.defaultValue));
    this.el.addEventListener('keydown', (e) => {
      const step = e.shiftKey ? 0.1 : 0.02;
      if (e.key === 'ArrowUp' || e.key === 'ArrowRight') { this.set(this.value + step); e.preventDefault(); }
      else if (e.key === 'ArrowDown' || e.key === 'ArrowLeft') { this.set(this.value - step); e.preventDefault(); }
      else if (e.key === 'Home') { this.set(0); e.preventDefault(); }
      else if (e.key === 'End') { this.set(1); e.preventDefault(); }
    });
  }

  set(v, emit = true) {
    this.value = clamp01(v);
    const angle = -135 + this.value * 270;
    this.indicator.style.transform = `rotate(${angle}deg)`;
    this.el.setAttribute('aria-valuenow', Math.round(this.value * 100));
    if (emit) this.onChange(this.value);
  }
}

export class Fader {
  // el: a .fader element (track). Creates a .fader-cap child.
  constructor(el, opts = {}) {
    this.el = el;
    this.value = opts.value ?? 0.65;
    this.defaultValue = opts.defaultValue ?? this.value;
    this.onChange = opts.onChange || (() => {});

    this.cap = document.createElement('div');
    this.cap.className = 'fader-cap';
    if (opts.accent) this.cap.style.background = opts.accent;
    el.appendChild(this.cap);

    el.setAttribute('role', 'slider');
    el.setAttribute('tabindex', '0');
    el.setAttribute('aria-valuemin', '0');
    el.setAttribute('aria-valuemax', '100');
    if (opts.label) el.setAttribute('aria-label', opts.label);

    this._bind();
    this.set(this.value, false);
  }

  _bind() {
    let dragging = false;
    const fromEvent = (e) => {
      const rect = this.el.getBoundingClientRect();
      const y = (e.touches ? e.touches[0].clientY : e.clientY);
      const pad = 12;
      const usable = rect.height - pad * 2;
      const rel = (rect.bottom - pad - y) / usable;
      this.set(rel);
    };
    const onMove = (e) => { if (dragging) { fromEvent(e); e.preventDefault(); } };
    const onUp = () => {
      dragging = false;
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
    };
    this.el.addEventListener('pointerdown', (e) => {
      dragging = true; this.el.focus(); fromEvent(e);
      window.addEventListener('pointermove', onMove);
      window.addEventListener('pointerup', onUp);
      e.preventDefault();
    });
    this.el.addEventListener('dblclick', () => this.set(this.defaultValue));
    this.el.addEventListener('keydown', (e) => {
      const step = e.shiftKey ? 0.1 : 0.02;
      if (e.key === 'ArrowUp') { this.set(this.value + step); e.preventDefault(); }
      else if (e.key === 'ArrowDown') { this.set(this.value - step); e.preventDefault(); }
    });
  }

  set(v, emit = true) {
    this.value = clamp01(v);
    this.cap.style.bottom = `calc(12px + ${this.value} * (100% - 24px - var(--cap-h, 22px)))`;
    this.el.setAttribute('aria-valuenow', Math.round(this.value * 100));
    if (emit) this.onChange(this.value);
  }
}
