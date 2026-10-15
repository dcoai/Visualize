defmodule Visualize.Hooks.Motion do
  @moduledoc """
  The frame loop the canvas hooks move a style's motion in (spec/10 §4.5, spec/14 §3.10,
  D-176).

  A canvas has no CSS, so the hook that draws it runs a style's `transition`: each element
  of a moving mark is drawn inside a motion span (spec/09 §3.3.5) naming its identity and
  its transition, and `VisualizeMotion` keeps, per identity, draw and context property, the
  value the canvas last showed. When a new stream draws an identity with another target,
  the value moves from what is shown to the target along the span's samples — colors in
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
        return {
          shown: new Map(), now: 0, seen: new Set(), ids: new Set(), span: null, active: false,
          reduced: false, exits: new Map(), ghosts: []
        };
      },

      // Before a replay: the clock, the reader's preference, nothing running yet.
      begin(state, now) {
        state.now = now;
        state.seen = new Set();
        state.ids = new Set();
        state.span = null;
        state.active = false;
        state.reduced = typeof window !== 'undefined' && typeof window.matchMedia === 'function' &&
          window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      },

      // A span from the motion command's arguments, [id, box, [[property, duration, samples]],
      // animation, enter, exit]: the context saved, and a running animation's and entrance's
      // motion applied about the element's box (#677, #678). What a span with an exit opened
      // with is kept, so the element can be drawn again once it is gone.
      open(state, ctx, args) {
        const [id, box, list, animation, enter, exit] = args;
        const transitions = {};
        (list || []).forEach(([property, duration, samples]) => { transitions[property] = [duration, samples]; });
        state.span = { id, box, transitions, alpha: 1, exit: null };
        state.ids.add(id);
        ctx.save();
        if (exit && !state.reduced) {
          state.span.exit = {
            exit, box, m: ctx.getTransform(), fillStyle: ctx.fillStyle, strokeStyle: ctx.strokeStyle,
            lineWidth: ctx.lineWidth, globalAlpha: ctx.globalAlpha
          };
        }
        const values = [];
        if (animation && !state.reduced) values.push(this.animate(state, id, animation));
        if (enter) values.push(this.enter(state, id, enter));
        const v = this.compose(values.filter((x) => x));
        if (v) this.place(ctx, v, box, state.span);
      },

      // Values composed: opacities and scales multiplied, translations and turns added.
      compose(list) {
        if (list.length === 0) return null;
        return list.reduce((a, b) => ({
          opacity: a.opacity * b.opacity, x: a.x + b.x, y: a.y + b.y,
          rotate: a.rotate + b.rotate, scale: a.scale * b.scale
        }));
      },

      // A motion's values on the context: translated, turned and scaled about the box's
      // center; the opacity a factor of every draw's alpha.
      place(ctx, v, box, span) {
        if (v.x || v.y) ctx.translate(v.x, v.y);
        if (box && (v.rotate || v.scale !== 1)) {
          const cx = box[0] + box[2] / 2, cy = box[1] + box[3] / 2;
          ctx.translate(cx, cy);
          if (v.rotate) ctx.rotate(v.rotate * Math.PI / 180);
          if (v.scale !== 1) ctx.scale(v.scale, v.scale);
          ctx.translate(-cx, -cy);
        }
        span.alpha = v.opacity;
      },

      // The span ends: the context restored. `again` makes the function that draws the span's
      // commands again, asked for only when the span has an exit (#678).
      close(state, ctx, again) {
        const span = state.span;
        if (span) {
          ctx.restore();
          if (span.exit && again) state.exits.set(span.id, { ...span.exit, draw: again() });
        }
        state.span = null;
      },

      // An entrance's values now, [name, duration, samples, keyframes], started the first
      // time the identity was drawn; null once it is done or for a reader who prefers less
      // motion (#678).
      enter(state, id, [name, duration, samples, own]) {
        const key = id + '\u0000enter';
        state.seen.add(key);
        let run = state.shown.get(key);
        if (!run) {
          run = { start: state.now };
          state.shown.set(key, run);
        }
        const frames = own || this.registered.get(name);
        if (state.reduced || !frames || !(duration > 0)) return null;
        const p = (state.now - run.start) / duration;
        if (p >= 1) return null;
        state.active = true;
        return this.keyframed(frames, Math.max(0, p), samples);
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

      // After a replay: forget what was not drawn, turn each identity with an exit that the
      // replay did not draw into a ghost, draw every ghost over the stream (#678); whether
      // anything still moves.
      end(state, ctx) {
        for (const key of [...state.shown.keys()]) if (!state.seen.has(key)) state.shown.delete(key);
        state.span = null;
        for (const [id, kept] of [...state.exits]) {
          if (state.ids.has(id)) continue;
          state.exits.delete(id);
          if (!state.reduced) state.ghosts.push({ ...kept, start: state.now });
        }
        if (ctx) state.ghosts = state.ghosts.filter((ghost) => this.ghost(state, ctx, ghost));
        else state.ghosts = [];
        if (state.ghosts.length > 0) state.active = true;
        return state.active;
      },

      // One frame of a gone element's exit, drawn as the span opened it; false once it ends.
      ghost(state, ctx, g) {
        const [name, duration, samples, own] = g.exit;
        const p = (state.now - g.start) / duration;
        if (!(duration > 0) || p >= 1 || state.reduced) return false;
        const t = Math.max(0, p);
        const again = (alpha, place) => {
          ctx.save();
          ctx.setTransform(g.m);
          ctx.fillStyle = g.fillStyle;
          ctx.strokeStyle = g.strokeStyle;
          ctx.lineWidth = g.lineWidth;
          ctx.globalAlpha = g.globalAlpha;
          place();
          const motion = this.create();
          this.begin(motion, state.now);
          motion.reduced = true;
          motion.span = { id: '\u0000ghost', box: g.box, transitions: {}, alpha, exit: null };
          g.draw(ctx, motion);
          ctx.restore();
        };
        if (name === 'explode') {
          this.pieces(g.box, this.ease(samples, t)).forEach((piece) => again(piece.alpha, () => {
            ctx.translate(piece.dx, piece.dy);
            ctx.translate(piece.cx, piece.cy);
            ctx.rotate(piece.rotate * Math.PI / 180);
            ctx.translate(-piece.cx, -piece.cy);
            ctx.beginPath();
            ctx.rect(...piece.cell);
            ctx.clip();
          }));
          return true;
        }
        const frames = own || this.registered.get(name);
        if (!frames) return false;
        const v = this.keyframed(frames, t, samples);
        const span = { alpha: 1 };
        again(v.opacity, () => this.place(ctx, v, g.box, span));
        return true;
      },

      // An explosion's sixteen pieces at the eased fraction e (spec/14 §3.12): each cell of a
      // 4 × 4 grid over the box, flown outward from the box's center through its own center,
      // turned about it and faded, on fixed paths.
      pieces(box, e) {
        if (!box) return [];
        const [x, y, w, h] = box;
        const [bx, by] = [x + w / 2, y + h / 2];
        const spread = 1.5 * Math.max(w, h) + 20;
        const out = [];
        for (let i = 0; i < 16; i++) {
          const [col, row] = [i % 4, Math.floor(i / 4)];
          const cell = [x + col * w / 4, y + row * h / 4, w / 4, h / 4];
          const [cx, cy] = [cell[0] + cell[2] / 2, cell[1] + cell[3] / 2];
          const length = Math.hypot(cx - bx, cy - by) || 1;
          const jitter = ((7 * i) % 16) / 15;
          const distance = (0.6 + 0.4 * jitter) * spread * e;
          out.push({
            cell, cx, cy, alpha: 1 - e,
            dx: (cx - bx) / length * distance, dy: (cy - by) / length * distance,
            rotate: (((37 * i) % 90) - 45) * e
          });
        }
        return out;
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

      // Numbers linearly, colors in OKLab.
      mix(a, b, t) {
        if (typeof a === 'number') return a + (b - a) * t;
        const p = this.parse(a), q = this.parse(b);
        return this.format(p.map((v, i) => v + (q[i] - v) * t));
      },

      // A color as [L, a, b, alpha] in OKLab, from the forms a context answers; null otherwise.
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

      // An OKLab color as rgba(), each channel clipped to sRGB.
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

  @doc """
  Returns the JavaScript source of `MotionHook` (spec/10 §20, spec/14 §3.12, #678): the
  hook around a chart that plays each exit — a copy of a gone element, recorded before the
  patch that removed it, played in an overlay over the chart — and restarts each enter a
  positional patch handed to another identity.
  """
  @spec js_hook() :: String.t()
  def js_hook do
    ~S"""
    export const MotionHook = {
      mounted() {
        this.before = null;
        this.exits = [];
        this.overlay = null;
        this.defs = null;
        this.motionFrame = null;
        this.seq = 0;
      },

      reduced() {
        return typeof window !== 'undefined' && typeof window.matchMedia === 'function' &&
          window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      },

      chart() { return this.el.querySelector('svg'); },

      // Before a patch: who each element is, and a copy of each that may leave.
      beforeUpdate() {
        const svg = this.chart();
        if (!svg || this.reduced()) { this.before = null; return; }
        const nodes = new Map();
        const exits = new Map();
        svg.querySelectorAll('[data-vis-id]').forEach((node) => {
          const id = node.getAttribute('data-vis-id');
          nodes.set(node, id);
          const exit = node.getAttribute('data-vis-exit');
          if (exit) exits.set(id, { exit: JSON.parse(exit), copy: this.lift(node, svg) });
        });
        this.before = { nodes, exits, rect: svg.getBoundingClientRect(), viewBox: svg.getAttribute('viewBox') };
      },

      // The element copied deeply, and each ancestor up to the chart's <svg> shallowly, so
      // its transforms and inherited paint come with it; no wrapper's motion class.
      lift(node, svg) {
        const shells = [];
        for (let p = node.parentNode; p && p !== svg; p = p.parentNode) {
          const shell = p.cloneNode(false);
          const cls = (shell.getAttribute('class') || '').split(/\s+/)
            .filter((c) => c && !c.startsWith('vis-enter-') && !c.startsWith('vis-animation-'));
          if (cls.length > 0) shell.setAttribute('class', cls.join(' '));
          else shell.removeAttribute('class');
          shells.push(shell);
        }
        return { leaf: node.cloneNode(true), shells };
      },

      // After a patch: each gone identity's exit played, each changed hand's enter restarted.
      updated() {
        const before = this.before;
        this.before = null;
        const svg = this.chart();
        if (!before || !svg) return;
        const now = new Map();
        svg.querySelectorAll('[data-vis-id]').forEach((n) => now.set(n.getAttribute('data-vis-id'), n));
        for (const [id, gone] of before.exits) if (!now.has(id)) this.play(gone, before);
        for (const [id, node] of now) {
          const was = before.nodes.get(node);
          if (was !== undefined && was !== id) this.restart(node, svg);
        }
        if (this.exits.length > 0) this.loop();
      },

      // An enter runs again: its wrapper's class off and on around a layout read.
      restart(node, svg) {
        for (let p = node.parentNode; p && p !== svg; p = p.parentNode) {
          const cls = [...p.classList].find((c) => c.startsWith('vis-enter-'));
          if (!cls) continue;
          p.classList.remove(cls);
          void p.getBoundingClientRect();
          p.classList.add(cls);
          return;
        }
      },

      svgNode(tag) { return document.createElementNS('http://www.w3.org/2000/svg', tag); },

      // The overlay over the chart, of its viewBox, outside the patched subtree (D-75).
      place(before) {
        if (!this.overlay) {
          this.overlay = this.svgNode('svg');
          this.overlay.setAttribute('class', 'vis-motion-overlay');
          this.overlay.style.position = 'absolute';
          this.overlay.style.pointerEvents = 'none';
          this.overlay.style.overflow = 'visible';
          this.defs = this.svgNode('defs');
          this.overlay.appendChild(this.defs);
          document.body.appendChild(this.overlay);
        }
        const r = before.rect;
        this.overlay.setAttribute('viewBox', before.viewBox || `0 0 ${r.width} ${r.height}`);
        this.overlay.style.left = (r.left + window.scrollX) + 'px';
        this.overlay.style.top = (r.top + window.scrollY) + 'px';
        this.overlay.style.width = r.width + 'px';
        this.overlay.style.height = r.height + 'px';
        this.overlay.style.display = 'block';
      },

      // A gone element's copy placed under a wrapper inside its ancestors' copies; an
      // explosion's pieces each a moving group over a clipped copy (spec/14 §3.12).
      play(gone, before) {
        this.place(before);
        const [name, duration, samples, box, frames] = gone.exit;
        const wrap = this.svgNode('g');
        const pieces = [];
        const clips = [];
        if (name === 'explode') {
          VisualizeMotion.pieces(box, 0).forEach((piece, i) => {
            const id = `vis-explode-${this.el.getAttribute('id')}-${++this.seq}-${i}`;
            const clip = this.svgNode('clipPath');
            clip.setAttribute('id', id);
            clip.setAttribute('clipPathUnits', 'userSpaceOnUse');
            const rect = this.svgNode('rect');
            ['x', 'y', 'width', 'height'].forEach((k, j) => rect.setAttribute(k, piece.cell[j]));
            clip.appendChild(rect);
            this.defs.appendChild(clip);
            clips.push(clip);
            const moving = this.svgNode('g');
            const clipped = this.svgNode('g');
            clipped.setAttribute('clip-path', `url(#${id})`);
            clipped.appendChild(gone.copy.leaf.cloneNode(true));
            moving.appendChild(clipped);
            wrap.appendChild(moving);
            pieces.push(moving);
          });
        } else {
          wrap.appendChild(gone.copy.leaf);
          // A host's keyframes run as CSS on the wrapper (spec/14 §3.12).
          if (!frames && !VisualizeMotion.registered.has(name)) {
            wrap.style.animation = `${name} ${duration}ms linear(${samples.join(', ')}) forwards`;
          }
        }
        let top = wrap;
        for (const shell of gone.copy.shells) { shell.appendChild(top); top = shell; }
        this.overlay.appendChild(top);
        const exit = { name, duration, samples, box, frames: frames || VisualizeMotion.registered.get(name) || null,
                       wrap, top, pieces, clips, start: performance.now() };
        this.exits.push(exit);
        this.step(exit, exit.start);
      },

      // One frame of an exit at `now`; false once it has ended and is removed.
      step(exit, now) {
        const p = (now - exit.start) / exit.duration;
        if (!(exit.duration > 0) || p >= 1) {
          exit.top.remove();
          exit.clips.forEach((clip) => clip.remove());
          return false;
        }
        const t = Math.max(0, p);
        if (exit.name === 'explode') {
          VisualizeMotion.pieces(exit.box, VisualizeMotion.ease(exit.samples, t)).forEach((piece, i) => {
            const g = exit.pieces[i];
            g.setAttribute('transform', `translate(${piece.dx},${piece.dy}) rotate(${piece.rotate},${piece.cx},${piece.cy})`);
            g.setAttribute('opacity', piece.alpha);
          });
        } else if (exit.frames) {
          const v = VisualizeMotion.keyframed(exit.frames, t, exit.samples);
          const [x, y, w, h] = exit.box || [0, 0, 0, 0];
          const [cx, cy] = [x + w / 2, y + h / 2];
          exit.wrap.setAttribute('opacity', v.opacity);
          exit.wrap.setAttribute('transform',
            `translate(${v.x},${v.y}) translate(${cx},${cy}) rotate(${v.rotate}) scale(${v.scale}) translate(${-cx},${-cy})`);
        }
        return true;
      },

      loop() {
        if (this.motionFrame !== null) return;
        this.motionFrame = requestAnimationFrame(() => {
          this.motionFrame = null;
          const now = performance.now();
          this.exits = this.exits.filter((exit) => this.step(exit, now));
          if (this.exits.length > 0) this.loop();
          else if (this.overlay) this.overlay.style.display = 'none';
        });
      },

      destroyed() {
        if (this.motionFrame !== null) cancelAnimationFrame(this.motionFrame);
        if (this.overlay && this.overlay.parentNode) this.overlay.parentNode.removeChild(this.overlay);
      }
    };
    """
  end
end
