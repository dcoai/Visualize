defmodule Visualize.Hooks.Legend do
  @moduledoc """
  Phoenix LiveView hook that hides and shows a series from its legend entry (spec/10 §14).

  A frame's legend entries and every element and label a series draws — a line's path,
  the points of a `:circle` or `:symbol` mark with the same `series` channel, an end label
  — carry the same `data-series` string (spec/14 §4.5, §5.6, D-126), so `LegendHook`
  joins them without a lookup and hides the series whole: a click on an entry
  sets `display="none"` on every `.mark [data-series]` element of that series under the
  hook element and dims the entry, and a second click shows it again. `display` is an
  SVG presentation attribute; the HTML `hidden` attribute would not hide an SVG group
  (D-77). The hidden set is re-applied after every LiveView patch, so a server re-render
  does not show a hidden series again. Nothing is pushed unless `data-legend-event`
  names an event.

  ## Usage

      <div id="chart" phx-hook="LegendHook" data-legend-event="legend_toggle">
        {Phoenix.HTML.raw(@svg)}
      </div>

      def handle_event("legend_toggle", %{"series" => series, "hidden" => hidden?}, socket) do
        {:noreply, update(socket, :hidden, &Map.put(&1, series, hidden?))}
      end

  ## Configuration

  Data attributes on the hook element:
  - `data-legend-event` - the event pushed with `{series, hidden}` on every toggle;
    unset, nothing is pushed

  Written by the frame (spec/10 §14.2):
  - `data-series` on every `legend-item` group and on every element and label of a mark
    with a `series` channel
  """

  @doc """
  Returns the JavaScript source of `LegendHook`.
  """
  def js_hook do
    """
    export const LegendHook = {
      mounted() {
        this.eventName = this.el.dataset.legendEvent || null;
        this.hidden = new Set();
        this.onClick = this.handleClick.bind(this);
        this.el.addEventListener('click', this.onClick);
        this.decorate();
      },

      entries() {
        return Array.from(this.el.querySelectorAll('.legend-item[data-series]'));
      },

      // Every entry that names a series is clickable.
      decorate() {
        this.entries().forEach((entry) => entry.setAttribute('cursor', 'pointer'));
      },

      handleClick(e) {
        if (!e.target || !e.target.closest) return;
        const entry = e.target.closest('.legend-item[data-series]');
        if (!entry || !this.el.contains(entry)) return;
        const series = entry.getAttribute('data-series');
        const hidden = !this.hidden.has(series);
        if (hidden) this.hidden.add(series); else this.hidden.delete(series);
        this.apply();
        if (this.eventName) this.pushEvent(this.eventName, { series, hidden });
      },

      // The hidden set onto the DOM: display="none" on every series element of a hidden
      // series and the entry dimmed; everything else shown.
      apply() {
        this.entries().forEach((entry) => {
          const hidden = this.hidden.has(entry.getAttribute('data-series'));
          entry.setAttribute('class', hidden ? 'legend-item legend-item-hidden' : 'legend-item');
          if (hidden) entry.setAttribute('opacity', '0.35'); else entry.removeAttribute('opacity');
        });
        this.el.querySelectorAll('.mark [data-series]').forEach((node) => {
          if (this.hidden.has(node.getAttribute('data-series'))) node.setAttribute('display', 'none');
          else node.removeAttribute('display');
        });
      },

      // A patch re-rendered the chart without the client's hidden set: apply it again.
      updated() {
        this.decorate();
        this.apply();
      },

      destroyed() {
        this.el.removeEventListener('click', this.onClick);
      }
    };
    """
  end
end
