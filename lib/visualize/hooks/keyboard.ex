defmodule Visualize.Hooks.Keyboard do
  @moduledoc """
  Phoenix LiveView hook that reaches a chart's points from the keyboard (spec/10 §17,
  spec/14 §21.5, D-142).

  `KeyboardHook` makes the chart one tab stop. Inside it the arrow keys move between the
  points of a series and between series, Home and End jump to a series' ends, and a polite
  live region reads the point: `y, 3 of 51: x 2, y 54.3`. Like `CrosshairHook` it never
  reads the chart's DOM: `attrs/1` writes every point once on the server — its readout and
  its position in the chart's pixels — so the same attributes serve a chart drawn as SVG
  and one on a canvas. The live region and the focus marker are appended to
  `document.body`, so a LiveView patch of the chart neither removes nor sees them.

  A board adds the order across its cells one level up: each cell one stop, or, when the
  board moves between cells with arrows, Escape inside a chart hands focus back to the
  nearest element carrying `data-vis-cell`.

  ## Usage

      <div id="chart-keys" phx-hook="KeyboardHook" {Visualize.Hooks.Keyboard.attrs(applied)}>
        {Phoenix.HTML.raw(@svg)}
      </div>

  ## Configuration

  Data attributes on the container, from `attrs/1` (spec/10 §17.2):
  - `data-keyboard-name` - the chart's name
  - `data-keyboard-points` - per series, `{"name", "points": [[x, y, readout], …]}`
  - `data-size` - `width,height` of the chart
  - `data-vis-focused` - the palette's `:focused`, resolved for the chart's frame: a JSON
    object of SVG attributes laid over the focus marker's own (spec/10 §4.4); absent, the
    marker is a 2-pixel `currentColor` ring

  Set by the host:
  - `data-keyboard-event` - the event pushed with `{series, index}` when the focused point
    changes; unset, nothing is pushed
  - `data-keyboard-pick-event` - the event pushed with `{series, index}` when a point is
    picked: Enter at the reached point, or a click, which picks the point nearest to it
    (spec/10 §17.3, spec/15 §13); unset, nothing is picked
  - `data-keyboard-target` - the `phx-target` both events go to with `pushEventTo`;
    unset, they go to the LiveView
  """

  alias Visualize.Chart.{Applied, Summary}
  alias Visualize.Hooks.States
  alias Visualize.IR.Path

  @doc """
  The data attributes of spec/10 §17.2 for an applied chart, computed once: its name, its
  points by series with their readouts and positions, its size, and the focus marker's
  style, the palette's `:focused` as the chart's design and theme resolve it (§4.4).
  """
  @spec attrs(Applied.t()) :: %{String.t() => String.t()}
  def attrs(%Applied{frame: frame} = applied) do
    series =
      Enum.map_join(Summary.points(applied), ",", fn %{name: name, points: points} ->
        ~s({"name":#{string(name)},"points":[) <>
          Enum.map_join(points, ",", &"[#{number(&1.x)},#{number(&1.y)},#{string(&1.text)}]") <>
          "]}"
      end)

    %{
      "data-keyboard-name" => Summary.new(applied).name,
      "data-keyboard-points" => "[" <> series <> "]",
      "data-size" => "#{number(frame.size.width)},#{number(frame.size.height)}"
    }
    |> Map.merge(States.attrs(frame, :focused))
  end

  defp number(nil), do: "null"
  defp number(n), do: Path.format_number(n)

  # A JSON string: the two characters JSON escapes by name, and every control character.
  defp string(text) do
    escaped =
      for <<c::utf8 <- text>>, into: "" do
        case c do
          ?" -> ~S(\")
          ?\\ -> ~S(\\)
          c when c < 0x20 -> "\\u" <> String.pad_leading(Integer.to_string(c, 16), 4, "0")
          c -> <<c::utf8>>
        end
      end

    ~s(") <> escaped <> ~s(")
  end

  @doc """
  Returns the JavaScript source of `KeyboardHook`.
  """
  def js_hook do
    ~S"""
    export const KeyboardHook = {
      mounted() {
        // What the host left unset is the hook's to set, again after every patch, since a
        // patch drops an attribute the server did not render (spec/10 §17.3).
        this.own = ['tabindex', 'role', 'aria-label'].filter((name) => !this.el.hasAttribute(name));
        this.readout = document.createElement('div');
        this.readout.setAttribute('class', 'vis-keyboard-readout');
        this.readout.setAttribute('aria-live', 'polite');
        Object.assign(this.readout.style, {
          position: 'absolute', width: '1px', height: '1px', overflow: 'hidden',
          clip: 'rect(0,0,0,0)', whiteSpace: 'nowrap', border: '0', padding: '0', margin: '-1px'
        });
        document.body.appendChild(this.readout);
        this.overlay = this.svg('svg', 'vis-keyboard-focus');
        this.overlay.style.position = 'absolute';
        this.overlay.style.pointerEvents = 'none';
        this.overlay.style.display = 'none';
        this.marker = this.svg('circle', 'vis-keyboard-marker');
        this.marker.setAttribute('r', 6);
        this.overlay.appendChild(this.marker);
        document.body.appendChild(this.overlay);
        this.at = null;

        // Each handler is bound once and kept, so destroyed() removes the same references.
        this.onKeyDown = this.handleKeyDown.bind(this);
        this.onFocus = this.handleFocus.bind(this);
        this.onBlur = this.hide.bind(this);
        this.onMouseDown = this.handleMouseDown.bind(this);
        this.onClick = this.handleClick.bind(this);
        this.down = null;
        this.read();
        this.el.addEventListener('keydown', this.onKeyDown);
        this.el.addEventListener('focus', this.onFocus);
        this.el.addEventListener('blur', this.onBlur);
        this.el.addEventListener('mousedown', this.onMouseDown);
        this.el.addEventListener('click', this.onClick);
      },

      // An event to the component `data-keyboard-target` names, else to the LiveView.
      push(event, payload) {
        if (this.target) this.pushEventTo(this.target, event, payload);
        else this.pushEvent(event, payload);
      },

      svg(tag, className) {
        const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
        node.setAttribute('class', className);
        return node;
      },

      // The points and the size from the data attributes (spec/10 §17.2), read on mount and
      // after every patch; the focused point is clamped to the new points.
      read() {
        const ds = this.el.dataset;
        this.name = ds.keyboardName || 'Chart';
        this.series = JSON.parse(ds.keyboardPoints || '[]');
        this.size = ds.size ? ds.size.split(',').map(parseFloat) : null;
        this.eventName = ds.keyboardEvent || null;
        this.pickName = ds.keyboardPickEvent || null;
        this.target = ds.keyboardTarget || null;
        const own = {
          tabindex: '0',
          role: 'group',
          'aria-label': this.name + ', chart: arrow keys move between points'
        };
        this.own.forEach((name) => this.el.setAttribute(name, own[name]));
        this.focusStyle(ds.visFocused);
        if (this.at) this.at = this.clamp(this.at.series, this.at.index);
      },

      // The marker's look: a 2-pixel ring in currentColor, with the server's :focused laid
      // over it (spec/10 §4.4); set again after every patch, so a key the style no longer
      // gives returns to its default and no attribute leaves it as it always was.
      focusStyle(focused) {
        const style = Object.assign({ fill: 'none', stroke: 'currentColor', 'stroke-width': '2' },
          focused ? JSON.parse(focused) : {});
        (this.styled || []).forEach((name) => this.marker.removeAttribute(name));
        this.styled = Object.keys(style);
        this.styled.forEach((name) => this.marker.setAttribute(name, style[name]));
      },

      clamp(series, index) {
        if (this.series.length === 0) return null;
        const s = Math.max(0, Math.min(series, this.series.length - 1));
        const points = this.series[s].points;
        if (points.length === 0) return null;
        return { series: s, index: Math.max(0, Math.min(index, points.length - 1)) };
      },

      handleFocus() {
        const count = this.series.reduce((n, s) => n + s.points.length, 0);
        this.say(`${this.name}: ${this.series.length} series, ${count} points.`);
        if (this.at) this.mark();
      },

      handleKeyDown(e) {
        const at = this.at;
        let next = null;
        switch (e.key) {
          case 'ArrowRight': next = at ? this.clamp(at.series, at.index + 1) : this.clamp(0, 0); break;
          case 'ArrowLeft': next = at ? this.clamp(at.series, at.index - 1) : this.clamp(0, 0); break;
          case 'ArrowDown': next = at ? this.clamp(at.series + 1, at.index) : this.clamp(0, 0); break;
          case 'ArrowUp': next = at ? this.clamp(at.series - 1, at.index) : this.clamp(0, 0); break;
          case 'Home': next = this.clamp(at ? at.series : 0, 0); break;
          case 'End': next = this.clamp(at ? at.series : 0, Infinity); break;
          case 'Escape': this.escape(); return;
          case 'Enter': this.pick(at, e); return;
          default: return;
        }
        e.preventDefault();
        if (next === null) return;
        const moved = !at || at.series !== next.series || at.index !== next.index;
        this.at = next;
        this.mark();
        this.say(this.series[next.series].points[next.index][2]);
        if (moved && this.eventName) this.push(this.eventName, { series: next.series, index: next.index });
      },

      // The reached point picked (spec/15 §13.2); nothing before a point is reached.
      pick(at, e) {
        if (!at || !this.pickName) return;
        if (e && e.preventDefault) e.preventDefault();
        this.push(this.pickName, { series: at.series, index: at.index });
      },

      handleMouseDown(e) {
        this.down = { x: e.clientX, y: e.clientY };
      },

      // A click picks the point nearest to it, by the crosshair's snapping: the least
      // horizontal distance, then the least vertical one. A click ending a drag is a brush.
      handleClick(e) {
        if (!this.pickName) return;
        const down = this.down;
        this.down = null;
        if (down && Math.hypot(e.clientX - down.x, e.clientY - down.y) > 3) return;
        const chart = this.el.querySelector('svg, canvas') || this.el;
        const rect = chart.getBoundingClientRect();
        if (!(rect.width > 0) || e.clientX < rect.left || e.clientX > rect.left + rect.width ||
            e.clientY < rect.top || e.clientY > rect.top + rect.height) return;
        const width = this.size ? this.size[0] : rect.width;
        const height = this.size ? this.size[1] : rect.height;
        const x = (e.clientX - rect.left) * width / rect.width;
        const y = (e.clientY - rect.top) * height / rect.height;
        let best = null;
        this.series.forEach((s, si) => s.points.forEach((p, pi) => {
          if (p[0] === null || p[1] === null) return;
          const dx = Math.abs(p[0] - x), dy = Math.abs(p[1] - y);
          if (!best || dx < best.dx - 0.5 || (Math.abs(dx - best.dx) <= 0.5 && dy < best.dy)) {
            best = { series: si, index: pi, dx, dy };
          }
        }));
        if (!best) return;
        this.at = { series: best.series, index: best.index };
        this.push(this.pickName, { series: best.series, index: best.index });
      },

      // Escape forgets the point and, inside a board's cell, hands focus back to it
      // (spec/14 §21.5).
      escape() {
        this.at = null;
        this.hide();
        const parent = this.el.parentNode;
        const cell = parent && parent.closest ? parent.closest('[data-vis-cell]') : null;
        if (cell && cell.focus) cell.focus();
      },

      say(text) {
        this.readout.textContent = text;
      },

      // The marker over the chart at the focused point, through the chart's viewBox; hidden
      // for a point with no position.
      mark() {
        const [x, y] = this.series[this.at.series].points[this.at.index];
        if (x === null || y === null) {
          this.hide();
          return;
        }
        const chart = this.el.querySelector('svg, canvas') || this.el;
        const rect = chart.getBoundingClientRect();
        const width = this.size ? this.size[0] : rect.width;
        const height = this.size ? this.size[1] : rect.height;
        this.overlay.setAttribute('viewBox', `0 0 ${width} ${height}`);
        this.overlay.style.left = (rect.left + window.scrollX) + 'px';
        this.overlay.style.top = (rect.top + window.scrollY) + 'px';
        this.overlay.style.width = rect.width + 'px';
        this.overlay.style.height = rect.height + 'px';
        this.marker.setAttribute('cx', x);
        this.marker.setAttribute('cy', y);
        this.overlay.style.display = 'block';
      },

      hide() {
        this.overlay.style.display = 'none';
      },

      updated() {
        this.read();
      },

      destroyed() {
        this.el.removeEventListener('keydown', this.onKeyDown);
        this.el.removeEventListener('focus', this.onFocus);
        this.el.removeEventListener('blur', this.onBlur);
        this.el.removeEventListener('mousedown', this.onMouseDown);
        this.el.removeEventListener('click', this.onClick);
        if (this.overlay.parentNode) this.overlay.parentNode.removeChild(this.overlay);
        if (this.readout.parentNode) this.readout.parentNode.removeChild(this.readout);
      }
    };
    """
  end
end
