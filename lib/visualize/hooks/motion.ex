defmodule Visualize.Hooks.Motion do
  @moduledoc """
  The frame loop the canvas hooks move a style's motion in (spec/10 §4.5, spec/14 §3.10,
  D-176).

  A canvas has no CSS, so the hook that draws it runs a style's `transition`: each element
  of a moving mark is drawn inside a motion span (spec/09 §3.3.5) naming its identity and
  its transition, and `VisualizeMotion` keeps, per identity, draw and context property, the
  value the canvas last showed. When a new stream draws an identity with another target,
  the value moves from what is shown to the target along the span's samples — colours in
  OKLab — and the hook replays its stream in `requestAnimationFrame` until nothing moves.
  A stream without a span is drawn once and requests no frame. A reader who prefers reduced
  motion sees every target at once.

  `CanvasChart` (`Visualize.Hooks.Canvas`) and `CanvasBinaryChart`
  (`Visualize.Hooks.CanvasBinary`) use it; the bundle defines it once and does not export it.
  """

  @doc "Returns the JavaScript source of `VisualizeMotion`."
  @spec js_motion() :: String.t()
  def js_motion do
    ~S"""
    // A style's motion on a canvas (spec/10 §4.5, D-176): what each identity shows, and the
    // arithmetic that moves it. A hook keeps one state and replays its stream through it.
    const VisualizeMotion = {
      create() {
        return { shown: new Map(), now: 0, seen: new Set(), span: null, active: false, reduced: false };
      },

      // Before a replay: the clock, the reader's preference, nothing running yet.
      begin(state, now) {
        state.now = now;
        state.seen = new Set();
        state.span = null;
        state.active = false;
        state.reduced = typeof window !== 'undefined' && typeof window.matchMedia === 'function' &&
          window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      },

      // A span from the motion command's arguments, [id, box, [[property, duration, samples]],
      // animation]: the context saved, and a running animation's motion applied about the
      // element's box (#677).
      open(state, ctx, args) {
        const [id, box, list, animation] = args;
        const transitions = {};
        (list || []).forEach(([property, duration, samples]) => { transitions[property] = [duration, samples]; });
        state.span = { id, box, transitions, alpha: 1 };
        ctx.save();
        const v = animation && !state.reduced ? this.animate(state, id, animation) : null;
        if (!v) return;
        if (v.x || v.y) ctx.translate(v.x, v.y);
        if (box && (v.rotate || v.scale !== 1)) {
          const cx = box[0] + box[2] / 2, cy = box[1] + box[3] / 2;
          ctx.translate(cx, cy);
          if (v.rotate) ctx.rotate(v.rotate * Math.PI / 180);
          if (v.scale !== 1) ctx.scale(v.scale, v.scale);
          ctx.translate(-cx, -cy);
        }
        state.span.alpha = v.opacity;
      },

      close(state, ctx) {
        if (state.span) ctx.restore();
        state.span = null;
      },

      // The host's keyframes by name: [[offset, {opacity, x, y, rotate, scale}], ...] (#677).
      registered: new Map(),
      register(name, frames) {
        const props = ['opacity', 'x', 'y', 'rotate', 'scale'];
        this.registered.set(name, frames.map(([offset, values]) =>
          [offset, ...props.map((p) => (values && values[p] !== undefined ? values[p] : null))]));
      },

      // An animation's values now, or null while it waits for its delay or once it is done:
      // [name, duration, samples, iterations, delay, keyframes], started the first time the
      // identity was drawn with it.
      animate(state, id, animation) {
        const [name, duration, samples, iterations, delay, own] = animation;
        const key = id + '\u0000animation';
        const sig = name + '\u0000' + duration + '\u0000' + iterations + '\u0000' + delay;
        state.seen.add(key);
        let run = state.shown.get(key);
        if (!run || run.sig !== sig) {
          run = { sig, start: state.now };
          state.shown.set(key, run);
        }
        const frames = own || this.registered.get(name);
        if (!frames || !(duration > 0)) return null;
        const t = state.now - run.start - delay;
        if (t < 0) { state.active = true; return null; }
        const n = Math.floor(t / duration);
        if (iterations !== null && n >= iterations) return null;
        state.active = true;
        return this.keyframed(frames, (t - n * duration) / duration, samples);
      },

      // Each property between the two keyframes about p that name it, the segment eased; a
      // property no keyframe names is the element's own.
      keyframed(frames, p, samples) {
        const identity = [1, 0, 0, 0, 1];
        const out = {};
        ['opacity', 'x', 'y', 'rotate', 'scale'].forEach((name, k) => {
          const named = frames.filter((f) => f[k + 1] !== null && f[k + 1] !== undefined)
            .map((f) => [f[0], f[k + 1]]);
          if (named.length === 0) { out[name] = identity[k]; return; }
          if (named[0][0] > 0) named.unshift([0, identity[k]]);
          if (named[named.length - 1][0] < 1) named.push([1, identity[k]]);
          let i = 0;
          for (let j = 0; j < named.length - 1; j++) if (named[j][0] <= p) i = j;
          const [a, b] = [named[i], named[i + 1]];
          const local = b[0] > a[0] ? (p - a[0]) / (b[0] - a[0]) : 1;
          out[name] = a[1] + (b[1] - a[1]) * this.ease(samples, local);
        });
        return out;
      },

      // After a replay: forget what was not drawn; whether anything still moves.
      end(state) {
        for (const key of [...state.shown.keys()]) if (!state.seen.has(key)) state.shown.delete(key);
        state.span = null;
        return state.active;
      },

      // The context properties a fill and a stroke draw with, and the part that moves each.
      props: {
        fill: [['fillStyle', 'fill'], ['globalAlpha', 'opacity']],
        stroke: [['strokeStyle', 'stroke'], ['lineWidth', 'stroke'], ['globalAlpha', 'opacity']]
      },

      // A fill or a stroke inside a span: the shown values in place of the targets, then the
      // targets back, so a draw after the span is untouched.
      draw(state, ctx, op, fn) {
        const span = state.span;
        if (!span) { fn(); return; }
        const put = [];
        for (const [prop, part] of this.props[op]) {
          const target = ctx[prop];
          let shown = this.value(state, span.id + '\u0000' + op + '\u0000' + prop, target, span.transitions[part]);
          // An animation's opacity is a factor of the element's alpha (#677).
          if (prop === 'globalAlpha' && span.alpha !== 1) shown = shown * span.alpha;
          if (shown !== target) { put.push([prop, target]); ctx[prop] = shown; }
        }
        fn();
        put.forEach(([prop, target]) => { ctx[prop] = target; });
      },

      // The value shown for a key whose target is `target`: a new target starts a motion from
      // what is shown now, unless the property does not move or the reader prefers less motion.
      value(state, key, target, transition) {
        state.seen.add(key);
        const now = state.now;
        const m = state.shown.get(key);
        if (!m) {
          state.shown.set(key, { from: target, to: target, start: now, duration: 0, samples: null });
          return target;
        }
        if (m.to !== target) {
          const shown = this.at(m, now);
          if (!transition || !(transition[0] > 0) || state.reduced || !this.mixable(shown, target)) {
            Object.assign(m, { from: target, to: target, start: now, duration: 0, samples: null });
          } else {
            Object.assign(m, { from: shown, to: target, start: now, duration: transition[0], samples: transition[1] });
          }
        }
        if (state.reduced) Object.assign(m, { from: m.to, duration: 0 });
        if (m.duration > 0 && now < m.start + m.duration) state.active = true;
        return this.at(m, now);
      },

      at(m, now) {
        if (!(m.duration > 0) || now >= m.start + m.duration) return m.to;
        return this.mix(m.from, m.to, this.ease(m.samples, Math.max(0, (now - m.start) / m.duration)));
      },

      // The eased fraction: the samples read piecewise linearly, as CSS's linear() reads them.
      ease(samples, t) {
        const n = samples.length - 1;
        const x = Math.min(Math.max(t, 0), 1) * n;
        const i = Math.min(Math.floor(x), n - 1);
        return samples[i] + (samples[i + 1] - samples[i]) * (x - i);
      },

      mixable(a, b) {
        if (typeof a === 'number' && typeof b === 'number') return true;
        return typeof a === 'string' && typeof b === 'string' && this.parse(a) !== null && this.parse(b) !== null;
      },

      // Numbers linearly, colours in OKLab.
      mix(a, b, t) {
        if (typeof a === 'number') return a + (b - a) * t;
        const p = this.parse(a), q = this.parse(b);
        return this.format(p.map((v, i) => v + (q[i] - v) * t));
      },

      // A colour as [L, a, b, alpha] in OKLab, from the forms a context answers; null otherwise.
      parse(text) {
        const s = text.trim();
        let r, g, b, alpha = 1, m;
        if ((m = /^#([0-9a-f]{3,8})$/i.exec(s))) {
          let h = m[1];
          if (h.length === 3 || h.length === 4) h = h.split('').map((c) => c + c).join('');
          if (h.length !== 6 && h.length !== 8) return null;
          [r, g, b] = [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16));
          if (h.length === 8) alpha = parseInt(h.slice(6, 8), 16) / 255;
        } else if ((m = /^rgba?\(([^)]*)\)$/i.exec(s))) {
          const parts = m[1].split(/[\s,\/]+/).filter(Boolean).map(parseFloat);
          if (parts.length < 3 || parts.some((v) => Number.isNaN(v))) return null;
          [r, g, b] = parts;
          if (parts.length > 3) alpha = parts[3];
        } else {
          return null;
        }
        const lin = (c) => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
        const [lr, lg, lb] = [lin(r), lin(g), lin(b)];
        const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
        const mm = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
        const sh = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
        return [0.2104542553 * l + 0.7936177850 * mm - 0.0040720468 * sh,
                1.9779984951 * l - 2.4285922050 * mm + 0.4505937099 * sh,
                0.0259040371 * l + 0.7827717662 * mm - 0.8086757660 * sh, alpha];
      },

      // An OKLab colour as rgba(), each channel clipped to sRGB.
      format([L, A, B, alpha]) {
        const l = Math.pow(L + 0.3963377774 * A + 0.2158037573 * B, 3);
        const m = Math.pow(L - 0.1055613458 * A - 0.0638541728 * B, 3);
        const s = Math.pow(L - 0.0894841775 * A - 1.2914855480 * B, 3);
        const enc = (c) => {
          c = c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
          return Math.round(Math.min(1, Math.max(0, c)) * 255);
        };
        const [r, g, b] = [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                           -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                           -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s].map(enc);
        return `rgba(${r}, ${g}, ${b}, ${Math.round(alpha * 1000) / 1000})`;
      },

      // A binary motion record's JSON, parsed once per distinct text (spec/09 §4.3.15).
      cache: new Map(),
      parseSpan(text) {
        let args = this.cache.get(text);
        if (args === undefined) {
          if (this.cache.size > 4096) this.cache.clear();
          args = JSON.parse(text);
          this.cache.set(text, args);
        }
        return args;
      }
    };
    """
  end
end
