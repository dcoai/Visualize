defmodule Visualize.Hooks.Sync do
  @moduledoc """
  The bus a sync group's tooltips and crosshairs share hover over (spec/10 §4.3, D-116).

  A design joins a group with `interaction: %{sync: "<group>"}` (spec/14 §2.9), and its
  markup carries `data-vis-sync` and `data-vis-sync-x` — the group, and `d0,d1,x0,x1,width`:
  the x domain, the chart pixels of its ends and the chart's width, from
  `Visualize.Chart.Frame.sync_attrs/1`. `VisualizeSync` reads them and carries a hover
  between members as a `CustomEvent` named `vis:sync:<group>` on `document`, whose
  `detail` is `{x, source}`: the pointer's x in **domain** units (milliseconds since the
  Unix epoch for a time x), `null` to clear, and the hook element that published it.
  Each member maps the value through its own five numbers, so members may differ in
  width, margin and domain; one whose domain does not hold the value draws nothing.

  The object is not exported: `TooltipHook` and `CrosshairHook` use it, and a host joins a
  group through the design key, never through it.
  """

  @doc "Returns the JavaScript source of `VisualizeSync`, the bus of spec/10 §4.3."
  def js_bus do
    """
    const VisualizeSync = {
      // The group of a hook element and its x mapping: from the element when it carries
      // data-vis-sync, else from its first descendant that does; null for none, or for a
      // data-vis-sync-x that is not five numbers.
      read(el) {
        const node = el.hasAttribute('data-vis-sync') ? el : el.querySelector('[data-vis-sync]');
        if (!node) return null;
        const x = (node.getAttribute('data-vis-sync-x') || '').split(',').map(parseFloat);
        if (x.length !== 5 || x.some((n) => Number.isNaN(n))) return null;
        return { group: node.getAttribute('data-vis-sync'), d0: x[0], d1: x[1], x0: x[2], x1: x[3], width: x[4] };
      },

      eventName(group) {
        return 'vis:sync:' + group;
      },

      // The domain value at a chart x: the inverse of the linear or time scale.
      toDomain(sync, chartX) {
        return sync.d0 + (chartX - sync.x0) / (sync.x1 - sync.x0) * (sync.d1 - sync.d0);
      },

      // The chart x of a domain value; null for a clear or a value outside the domain, and
      // the middle of the range for a collapsed domain, as the scale draws one.
      toChart(sync, x) {
        if (x === null || x === undefined) return null;
        if (x < Math.min(sync.d0, sync.d1) || x > Math.max(sync.d0, sync.d1)) return null;
        if (sync.d1 === sync.d0) return (sync.x0 + sync.x1) / 2;
        return sync.x0 + (x - sync.d0) / (sync.d1 - sync.d0) * (sync.x1 - sync.x0);
      },

      publish(sync, source, x) {
        document.dispatchEvent(new CustomEvent(this.eventName(sync.group), { detail: { x, source } }));
      },

      // Reads the hook's element and keeps the result as hook.sync; moves the hook's one
      // listener, hook.onSync, to the group's event when the group changed, and removes it
      // when the element left its group.
      attach(hook) {
        const sync = this.read(hook.el);
        const name = sync ? this.eventName(sync.group) : null;
        if (hook.syncEvent !== name) {
          if (hook.syncEvent) document.removeEventListener(hook.syncEvent, hook.onSync);
          if (name) document.addEventListener(name, hook.onSync);
          hook.syncEvent = name;
        }
        hook.sync = sync;
      },

      detach(hook) {
        if (hook.syncEvent) document.removeEventListener(hook.syncEvent, hook.onSync);
        hook.syncEvent = null;
        hook.sync = null;
      },

      // An event from the element itself, an ancestor or a descendant is the chart's own
      // echo: it has already drawn from its own pointer.
      own(el, source) {
        return source === el || el.contains(source) || source.contains(el);
      }
    };
    """
  end
end
