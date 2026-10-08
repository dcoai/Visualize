// A recording DOM for executing the Visualize hooks under node (spec/12 §6, #458).
// Dependency-free by design: an element, a canvas whose 2D context records every call
// and assignment, the LiveView hook contract, and a manual clock. Visualize.JsHooks
// concatenates this, Visualize.Hooks.js_code() and one scenario into one ES module.
const Stub = (() => {
  const log = [];
  let ids = 0, now = 0, timerIds = 0;
  const timers = new Map();

  // Every context method is a recorder; every assignment is recorded and kept.
  function context(canvas) {
    const props = {};
    return new Proxy(props, {
      get: (_t, name) => name in props ? props[name] :
        (...args) => { log.push({on: canvas.id, kind: 'call', name, args}); },
      set: (_t, name, value) => {
        props[name] = value;
        log.push({on: canvas.id, kind: 'set', name, value});
        return true;
      }
    });
  }

  class Element {
    constructor(tagName, dataset = {}) {
      this.tagName = tagName.toUpperCase();
      this.dataset = {...dataset};
      this.attributes = {};
      this.children = [];
      this.style = {};
      this.parentNode = null;
    }
    querySelector(selector) {
      const match = selector.startsWith('.')
        ? (c) => c.className === selector.slice(1)
        : (c) => c.tagName === selector.toUpperCase();
      return this.children.find(match) || null;
    }
    appendChild(child) { child.parentNode = this; this.children.push(child); return child; }
    remove() {
      if (this.parentNode) this.parentNode.children = this.parentNode.children.filter((c) => c !== this);
    }
    setAttribute(name, value) { this.attributes[name] = String(value); }
    getAttribute(name) { return name in this.attributes ? this.attributes[name] : null; }
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

  globalThis.document = {
    createElement: (tag) => tag === 'canvas' ? new Canvas() : new Element(tag),
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
    // A hook instance as LiveView builds one: el, pushEvent and handleEvent, then mounted().
    mount(hook, el) {
      const handlers = {};
      const instance = Object.assign(Object.create(hook), {
        el,
        handlers,
        pushEvent: (name, payload) => log.push({on: 'live', kind: 'push', name, payload}),
        handleEvent: (name, fn) => { handlers[name] = fn; },
      });
      instance.mounted();
      return instance;
    },
    deliver(instance, name, payload) { instance.handlers[name](payload); },
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

