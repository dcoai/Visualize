// A recording DOM for executing the Visualize hooks under node (spec/12 §6, #458).
// Dependency-free by design: an element, a canvas whose 2D context records every call
// and assignment, the LiveView hook contract, and a manual clock. Visualize.JsHooks
// concatenates this, Visualize.Hooks.js_code() and one scenario into one ES module.
const Stub = (() => {
  const log = [];
  let ids = 0, now = 0, timerIds = 0;
  const timers = new Map();

  // The 2D context's current transform, as a browser keeps it (#651): `getTransform()`
  // answers it, and the calls that change it — each still recorded — change it.
  const multiply = (m, n) => ({
    a: m.a * n.a + m.c * n.b, b: m.b * n.a + m.d * n.b,
    c: m.a * n.c + m.c * n.d, d: m.b * n.c + m.d * n.d,
    e: m.a * n.e + m.c * n.f + m.e, f: m.b * n.e + m.d * n.f + m.f,
  });
  const identity = () => ({a: 1, b: 0, c: 0, d: 1, e: 0, f: 0});

  function transforms(state, name, args) {
    const [x, y] = args;
    switch (name) {
      case 'save': state.stack.push({...state.m}); break;
      case 'restore': state.m = state.stack.pop() || state.m; break;
      case 'resetTransform': state.m = identity(); break;
      case 'setTransform':
        state.m = args.length === 1 ? {...args[0]} :
          {a: args[0], b: args[1], c: args[2], d: args[3], e: args[4], f: args[5]};
        break;
      case 'translate': state.m = multiply(state.m, {a: 1, b: 0, c: 0, d: 1, e: x, f: y}); break;
      case 'scale': state.m = multiply(state.m, {a: x, b: 0, c: 0, d: y, e: 0, f: 0}); break;
      case 'rotate': {
        const [cos, sin] = [Math.cos(x), Math.sin(x)];
        state.m = multiply(state.m, {a: cos, b: sin, c: -sin, d: cos, e: 0, f: 0});
        break;
      }
      case 'transform':
        state.m = multiply(state.m, {a: args[0], b: args[1], c: args[2], d: args[3], e: args[4], f: args[5]});
        break;
    }
  }

  // Every context method is a recorder; every assignment is recorded and kept. The
  // transform is tracked beside, and `getTransform()` reads it without being recorded.
  function context(canvas) {
    const props = {};
    const state = {m: identity(), stack: []};
    return new Proxy(props, {
      get: (_t, name) => name === 'getTransform' ? () => ({...state.m}) :
        name in props ? props[name] :
        (...args) => { transforms(state, name, args); log.push({on: canvas.id, kind: 'call', name, args}); },
      set: (_t, name, value) => {
        props[name] = value;
        log.push({on: canvas.id, kind: 'set', name, value});
        return true;
      }
    });
  }

  // `data-vis-sync-x` as the browser's dataset spells it: `visSyncX`.
  const datasetKey = (name) => name.slice(5).replace(/-([a-z])/g, (_m, c) => c.toUpperCase());

  // A listener table, for an element and for `document` (#466).
  class Target {
    constructor() { this.listeners = {}; }
    addEventListener(type, fn) { (this.listeners[type] = this.listeners[type] || []).push(fn); }
    removeEventListener(type, fn) {
      this.listeners[type] = (this.listeners[type] || []).filter((f) => f !== fn);
    }
    fire(type, event) { (this.listeners[type] || []).slice().forEach((fn) => fn(event)); }
  }

  // A selector list of compounds — `tag`, `.class`, `[attr]`, `tag[attr]` — joined by the
  // descendant combinator, a space (`.mark [data-series]`, #508), which is every form the
  // hooks query by; anything else throws rather than silently matching nothing.
  function compound(text, selector) {
    const m = text.match(/^([a-z0-9]*)((?:\.[\w-]+|\[[\w-]+\])*)$/i);
    if (!m || text === '') throw new Error('dom_stub: unsupported selector ' + selector);
    const tag = m[1].toUpperCase();
    const classes = [...m[2].matchAll(/\.([\w-]+)/g)].map((c) => c[1]);
    const attrs = [...m[2].matchAll(/\[([\w-]+)\]/g)].map((a) => a[1]);
    return (el) => (tag === '' || el.tagName === tag) &&
      classes.every((c) => el.classList.contains(c)) && attrs.every((a) => el.hasAttribute(a));
  }

  // The last compound matches the element, and the ones before it match ancestors in
  // order, nearest first — a browser's right-to-left reading of a descendant chain.
  function matcher(selector) {
    const tests = selector.split(',').map((part) => {
      const chain = part.trim().split(/\s+/).map((text) => compound(text, selector));
      return (el) => {
        if (!chain[chain.length - 1](el)) return false;
        let i = chain.length - 2;
        for (let node = el.parentNode; i >= 0 && node && node.classList; node = node.parentNode) {
          if (chain[i](node)) i--;
        }
        return i < 0;
      };
    });
    return (el) => tests.some((test) => test(el));
  }

  class Element extends Target {
    constructor(tagName, dataset = {}) {
      super();
      this.tagName = tagName.toUpperCase();
      this.dataset = {...dataset};
      this.attributes = {};
      this.children = [];
      this.style = {};
      this.parentNode = null;
      this.classList = new Set();
      this.classList.contains = this.classList.has;
      this.classList.remove = this.classList.delete;
      this.classList.toggle = (name, on) => (on ? this.classList.add(name) : this.classList.delete(name), on);
      this.rect = {left: 0, top: 0, width: 0, height: 0};
      this.offsetWidth = 0;
      this.offsetHeight = 0;
    }
    get className() { return [...this.classList].join(' '); }
    set className(value) { this.classList.clear(); String(value).split(/\s+/).filter(Boolean).forEach((c) => this.classList.add(c)); }
    // A selector list of compounds (`tag`, `.class`, `[attr]`, `tag[attr]`), by `matcher`.
    matches(selector) { return matcher(selector)(this); }
    // Every descendant in document order.
    descendants() { return this.children.flatMap((c) => [c, ...c.descendants()]); }
    querySelector(selector) { return this.descendants().find((c) => c.matches(selector)) || null; }
    querySelectorAll(selector) { return this.descendants().filter((c) => c.matches(selector)); }
    closest(selector) {
      for (let node = this; node instanceof Element; node = node.parentNode) {
        if (node.matches(selector)) return node;
      }
      return null;
    }
    contains(other) {
      for (let node = other; node; node = node.parentNode) if (node === this) return true;
      return false;
    }
    get parentElement() { return this.parentNode instanceof Element ? this.parentNode : null; }
    appendChild(child) { child.parentNode = this; this.children.push(child); return child; }
    insertBefore(child, ref) {
      child.remove();
      const at = this.children.indexOf(ref);
      child.parentNode = this;
      this.children.splice(at < 0 ? this.children.length : at, 0, child);
      return child;
    }
    // An <svg> maps a client point into its user units as a browser does: through its
    // `viewBox` onto the bounding rectangle the scenario sets, the rectangle's own size
    // without one (#467). Only an SVG has the two methods, as in a browser.
    createSVGPoint() {
      if (this.tagName !== 'SVG') throw new Error('dom_stub: createSVGPoint on a ' + this.tagName);
      return {x: 0, y: 0, matrixTransform(m) { return {x: m.a * this.x + m.e, y: m.d * this.y + m.f}; }};
    }
    getScreenCTM() {
      if (this.tagName !== 'SVG') throw new Error('dom_stub: getScreenCTM on a ' + this.tagName);
      const {left, top, width, height} = this.rect;
      const box = (this.getAttribute('viewBox') || `0 0 ${width} ${height}`).split(/[\s,]+/).map(Number);
      const m = {a: width / box[2], d: height / box[3]};
      m.e = left - box[0] * m.a;
      m.f = top - box[1] * m.d;
      m.inverse = () => ({a: 1 / m.a, d: 1 / m.d, e: -m.e / m.a, f: -m.f / m.d});
      return m;
    }
    // Focus moves to the element, as a browser's does: recorded, the document's active
    // element, and its `focus` listeners called (#558).
    focus() {
      log.push({on: this.attributes.id || this.tagName, kind: 'focus'});
      doc.activeElement = this;
      this.fire('focus', {target: this});
    }
    removeChild(child) { child.remove(); return child; }
    remove() {
      if (this.parentNode) this.parentNode.children = this.parentNode.children.filter((c) => c !== this);
      this.parentNode = null;
    }
    getBoundingClientRect() {
      const {top, left, width, height} = this.rect;
      return {top, left, width, height, bottom: top + height, right: left + width};
    }
    // `class` is reflected into classList, as a browser does, so a selector reads it.
    setAttribute(name, value) {
      this.attributes[name] = String(value);
      if (name === 'class') this.className = String(value);
    }
    // A `data-*` attribute the element was built with reads through its dataset, as in a browser.
    getAttribute(name) {
      if (name in this.attributes) return this.attributes[name];
      if (name.startsWith('data-') && datasetKey(name) in this.dataset) return this.dataset[datasetKey(name)];
      return null;
    }
    hasAttribute(name) { return this.getAttribute(name) !== null; }
    removeAttribute(name) { delete this.attributes[name]; }
  }

  // Setting width or height clears a canvas (HTML §4.12.5), so both setters record it.
  class Canvas extends Element {
    constructor(width = 300, height = 150) {
      super('canvas');
      this.id = 'canvas' + (++ids);
      this.size = {width, height};
      this.ctx = context(this);
    }
    get width() { return this.size.width; }
    set width(value) { this.resize('width', value); }
    get height() { return this.size.height; }
    set height(value) { this.resize('height', value); }
    resize(name, value) {
      this.size[name] = value;
      log.push({on: this.id, kind: 'set', name, value});
      log.push({on: this.id, kind: 'clear'});
    }
    getContext(type) { return type === '2d' ? this.ctx : null; }
    toJSON() { return this.id; }
  }

  // `document` is an event target too: the sync bus dispatches on it (spec/10 §4.3), and
  // every dispatch is recorded with its detail — a hover's x, a brush's extent — and the
  // source element's id.
  const doc = new Target();
  Object.assign(doc, {
    body: new Element('body'),
    documentElement: {clientWidth: 1280, clientHeight: 800},
    createElement: (tag) => tag === 'canvas' ? new Canvas() : new Element(tag),
    createElementNS: (_ns, tag) => new Element(tag),
    dispatchEvent(event) {
      const detail = event.detail || {};
      log.push({on: 'document', kind: 'event', name: event.type,
                payload: {...detail, source: detail.source ? detail.source.id : null}});
      doc.fire(event.type, event);
      return true;
    },
  });
  globalThis.document = doc;
  globalThis.window = {scrollX: 0, scrollY: 0};
  globalThis.CustomEvent = class CustomEvent {
    constructor(type, init = {}) { this.type = type; this.detail = init.detail; }
  };
  globalThis.setTimeout = (fn, ms) => { timers.set(++timerIds, {fn, at: now + ms}); return timerIds; };
  globalThis.clearTimeout = (id) => { timers.delete(id); };
  Object.defineProperty(globalThis, 'performance', {value: {now: () => now}, configurable: true});

  return {
    log,
    // An element holding a canvas of the given size, as a page renders it.
    element(dataset, width, height) {
      const el = new Element('div', dataset);
      if (width !== undefined) el.appendChild(new Canvas(width, height));
      return el;
    },
    // An element as a page renders it, by its HTML attribute names (#468): its attributes,
    // `class` read into classList and each `data-*` into dataset, as a browser reflects
    // them, then its children. `node/2` below builds a bare element from a dataset.
    markup(tag, attributes = {}, children = []) {
      const el = new Element(tag);
      for (const [name, value] of Object.entries(attributes)) {
        el.setAttribute(name, value);
        if (name === 'class') el.className = String(value);
        if (name.startsWith('data-')) {
          el.dataset[datasetKey(name)] = String(value);
        }
      }
      children.forEach((child) => el.appendChild(child));
      return el;
    },
    // A hook instance as LiveView builds one: el, pushEvent and handleEvent, then mounted().
    mount(hook, el) {
      const handlers = {};
      const instance = Object.assign(Object.create(hook), {
        el,
        handlers,
        pushEvent: (name, payload) => log.push({on: 'live', kind: 'push', name, payload}),
        pushEventTo: (target, name, payload) => log.push({on: 'live', kind: 'push', name, payload, target}),
        handleEvent: (name, fn) => { handlers[name] = fn; },
      });
      instance.mounted();
      return instance;
    },
    deliver(instance, name, payload) { instance.handlers[name](payload); },
    // A bare element, for a chart's markup inside a hook element.
    node(tag, dataset = {}) { return new Element(tag, dataset); },
    // A pointer event on an element: its listeners called with the event, target the element.
    fire(el, type, event = {}) { el.fire(type, {target: el, ...event}); },
    // How many listeners `document` holds for an event name.
    listeners(name) { return (doc.listeners[name] || []).length; },
    // Runs every timer due by now + ms, in time order, as the clock reaches it.
    advance(ms) {
      const until = now + ms;
      for (;;) {
        const due = [...timers].filter(([, t]) => t.at <= until).sort((a, b) => a[1].at - b[1].at)[0];
        if (!due) break;
        timers.delete(due[0]);
        now = due[1].at;
        due[1].fn();
      }
      now = until;
    },
    mark(label) { log.push({on: 'scenario', kind: 'mark', name: label}); },
    // The one line Visualize.JsHooks reads: the log and whatever the scenario reports.
    done(report = {}) { console.log('VIS-HOOKS-LOG ' + JSON.stringify({log, report})); },
  };
})();

