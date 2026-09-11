defmodule ExamplesWeb.BuilderLive do
  @moduledoc """
  The chart builder page (#54): `Visualize.Chart.Builder` embedded in a host LiveView over a
  fixed stack of three fragments (spec/14 §18).

  The page is the host of the contract: it owns the route, the layers the builder starts
  with, the pool of sample sources the preview binds to, and the library — a tiny in-memory
  `Visualize.Chart.Builder.Store` — and it handles the one message the builder sends,
  `{:design_saved, id, design}`, by applying the design it is handed. Nothing else crosses
  the boundary.
  """
  use Phoenix.LiveView

  alias Visualize.Chart

  defmodule Library do
    @moduledoc """
    A `Visualize.Chart.Builder.Store` over `:persistent_term`, so the page can offer a
    library without a database (spec/14 §19.7). A real host keeps its entries wherever it
    keeps anything; this one keeps a map of id to entry and one counter per kind, and
    ignores the context because a demo page has nobody to attribute a save to.

    Ids are `{kind, n}`, issued here and never reused (§19.2, D-100): the counter only ever
    goes up, so a deleted entry's id stays vacant and a reference to it is a mask.
    """
    @behaviour Visualize.Chart.Builder.Store

    alias Visualize.Chart.Builder.Store
    alias Visualize.Chart.Fragment

    @key {__MODULE__, :library}

    @impl true
    def list(_context) do
      for {id, entry} <- entries(), do: %{id: id, name: entry.name, kind: entry.kind}
    end

    @impl true
    def get(id, _context) do
      case Map.fetch(entries(), id) do
        {:ok, entry} -> {:ok, Map.put(entry, :id, id)}
        :error -> :error
      end
    end

    @impl true
    def put(%{id: nil} = entry, context) do
      kind = Fragment.kind(entry.fragment)
      id = {kind, next(kind)}
      put(%{entry | id: id, kind: kind}, context)
    end

    def put(%{id: id} = entry, _context) do
      %{entries: entries, counters: counters} = state()

      stored = %{name: entry.name, kind: Fragment.kind(entry.fragment), fragment: entry.fragment}
      :persistent_term.put(@key, %{entries: Map.put(entries, id, stored), counters: counters})
      {:ok, id}
    end

    @impl true
    def delete(id, _context) do
      %{entries: entries, counters: counters} = state()
      :persistent_term.put(@key, %{entries: Map.delete(entries, id), counters: counters})
      :ok
    end

    @impl true
    def import(bundle, context), do: Store.relocate(bundle, context, &put/2)

    # A per-kind sequence that only goes up.
    defp next(kind) do
      %{entries: entries, counters: counters} = state()
      n = Map.get(counters, kind, 0) + 1
      :persistent_term.put(@key, %{entries: entries, counters: Map.put(counters, kind, n)})
      n
    end

    defp entries, do: state().entries

    # The seeded library on first use. Names carry their place in the tree
    # (spec/14 §18.16); every fragment names what this page's stack declares, so adding
    # any of them changes something visible.
    defp state do
      case :persistent_term.get(@key, nil) do
        nil ->
          :persistent_term.put(@key, %{entries: %{}, counters: %{}})

          Enum.each(seeds(), fn {name, fragment} ->
            put(%{id: nil, name: name, kind: nil, fragment: fragment}, nil)
          end)

          :persistent_term.get(@key)

        state ->
          state
      end
    end

    defp seeds do
      [
        {"Theme::dark", %{theme: :dark}},
        {"Frame:axes:no grid", %{frame: %{axes: [%{scale: :value, side: :left, grid: false}]}}},
        {"Frame:axes:dense ticks",
         %{
           frame: %{
             axes: [
               %{scale: :hour, side: :bottom, ticks: 12},
               %{scale: :value, side: :left, ticks: 10}
             ]
           }
         }},
        {"Frame:size:wide", %{frame: %{size: %{width: 900, height: 320}}}},
        {"Frame:margin:roomy", %{frame: %{margin: %{top: 40, right: 40, bottom: 48, left: 64}}}},
        {"Styles::thick line", %{styles: %{series: %{stroke_width: 5}}}},
        {"Styles::stepped", %{styles: %{series: %{curve: :step}}}}
      ]
    end
  end

  @house %{
    version: 1,
    meta: %{name: "Uptime"},
    theme: :default,
    styles: %{series: %{stroke: :series_1, stroke_width: 2, curve: :monotone_x}},
    frame: %{
      kind: :cartesian,
      size: %{width: 640, height: 320},
      margin: %{top: 24, right: 24, bottom: 32, left: 48}
    }
  }

  @shared %{
    sources: %{primary: %{fields: [:hour, :value]}},
    frame: %{
      scales: %{
        hour: %{kind: :linear, domain: :auto},
        value: %{kind: :linear, domain: [0, :auto], nice: true}
      },
      axes: [
        %{scale: :hour, side: :bottom, ticks: 6},
        %{scale: :value, side: :left, ticks: 5, grid: true}
      ]
    }
  }

  @panel %{
    vars: %{unit: %{default: "%"}},
    marks: [
      %{
        id: :series,
        type: :line,
        data: :primary,
        channels: %{x: :hour, y: :value},
        scales: %{x: :hour, y: :value},
        style: :series
      }
    ],
    labels: [%{id: :title, anchor: :title, text: ["Uptime — ", Chart.var(:unit)]}]
  }

  defp rows do
    for hour <- 0..23,
        do: %{hour: hour, value: Float.round(92 + 6 * :math.sin(hour / 3.5), 2)}
  end

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       layers: [{:house, @house}, {:shared, @shared}, {:panel, @panel}],
       sources: %{primary: rows()},
       saved: nil
     )}
  end

  # The builder's one output: the design it produced. The host decides what saving means —
  # here, applying it and reporting whether it drew.
  # What the builder sends is the structure — the stack of sites — and the deployment
  # phase is where it becomes a design: flattened through the library (spec/14 §19.6).
  def handle_info({:design_saved, _id, structure}, socket) do
    result =
      with {:ok, design, %{missing: missing}} <- Chart.flatten(structure, &fetch/1),
           {:ok, _applied} <- Chart.apply(design, sources: socket.assigns.sources) do
        case missing do
          [] -> "saved: the design applies"
          _ -> "saved: the design applies, with #{length(missing)} reference(s) showing through"
        end
      else
        {:error, {:cycle, chain}} ->
          "not saved: the stack refers to itself through #{inspect(chain)}"

        {:error, errors} ->
          "not saved: " <> Enum.map_join(errors, "; ", &Chart.Validator.format/1)
      end

    {:noreply, assign(socket, :saved, result)}
  end

  defp fetch(id) do
    case Library.get(id, %{}) do
      {:ok, entry} -> {:ok, entry.fragment}
      :error -> :error
    end
  end

  def render(assigns) do
    ~H"""
    <header>
      <h1>Chart builder</h1>
      <p>
        <code>Visualize.Chart.Builder</code>
        over three fragments: a house layer, a shared frame and a panel. Edit a node, reorder
        or disable a layer, set the parameters, and press Save.
      </p>
      <p :if={@saved} class="builder-saved">{@saved}</p>
      <p><a href="/">← back to the gallery</a></p>
      <!--
        Drag diagnostics. Drag and drop is four steps and any one of them failing looks the
        same from outside: the module loads, the hook registers, the browser fires the
        events, and the server changes the order. This says which step you got to.
      -->
      <div id="drag-diagnostics" class="builder-diagnostics" phx-update="ignore">
        <strong>drag diagnostics</strong>
        <span id="diag-module">module: …</span>
        <span id="diag-mounted">hook mounted: …</span>
        <span id="diag-events">events: none yet</span>
      </div>
      <script>
        (() => {
          const seen = [];
          const show = () => {
            const el = document.getElementById("diag-events");
            if (el) el.textContent = "events: " + (seen.length ? seen.join(" → ") : "none yet");
          };

          // The browser's own events, watched in the capture phase so nothing can stop them
          // reaching here. If `drop` never appears, the problem is before the hook.
          for (const name of ["click", "dragstart", "dragover", "drop", "dragend"]) {
            document.addEventListener(name, (e) => {
              const at = e.target.closest && e.target.closest("[data-builder-layer], [data-builder-fragment]");
              let what = "(gap)";
              if (at && at.hasAttribute("data-builder-fragment")) what = "(library)";
              else if (at) what = "(layer " + at.getAttribute("data-builder-layer") + ")";
              const tag = name + what;
              if (seen[seen.length - 1] !== tag) { seen.push(tag); if (seen.length > 10) seen.shift(); show(); }
            }, true);
          }

          const report = () => {
            const hooks = window.VisualizeHooks || {};
            const names = Object.keys(hooks);
            const module = document.getElementById("diag-module");
            if (module) {
              module.textContent = names.length
                ? "module: " + names.length + " hooks, BuilderHook " + (hooks.BuilderHook ? "present" : "MISSING")
                : "module: DID NOT LOAD";
            }

            const all = document.querySelectorAll("[phx-hook='BuilderHook']");
            const up = document.querySelectorAll("[phx-hook='BuilderHook'][data-builder-mounted]");
            const mounted = document.getElementById("diag-mounted");
            if (mounted) mounted.textContent = "hook mounted: " + up.length + " of " + all.length;
          };

          window.addEventListener("DOMContentLoaded", () => setTimeout(report, 400));
          setTimeout(report, 1500);
        })();
      </script>
    </header>
    <main>
      <.live_component
        module={Visualize.Chart.Builder}
        id="builder"
        layers={@layers}
        sources={@sources}
        store={Library}
        on_save={:design_saved}
      />
    </main>
    """
  end
end
