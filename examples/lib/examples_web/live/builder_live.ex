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
    library without a database. A real host keeps its fragments wherever it keeps anything.
    """
    @behaviour Visualize.Chart.Builder.Store

    @key {__MODULE__, :fragments}

    @impl true
    def list, do: fragments() |> Map.keys() |> Enum.sort()

    @impl true
    def get(name), do: Map.fetch(fragments(), name)

    @impl true
    def put(name, fragment) do
      :persistent_term.put(@key, Map.put(fragments(), name, fragment))
      :ok
    end

    defp fragments do
      # Each fragment must name things this page's stack actually declares: `grid` used to
      # reference a scale `:y`, which nothing here declares, so adding it replaced the chart
      # with `frame.axes[2].scale: scale :y is not declared` — which reads as doing nothing.
      # An axis is identified by its `{scale, side}`, so naming `:value` merges with the left
      # axis the shared layer already declares rather than adding a third.
      # Names carry their place in the tree: <category>:<sub-category>:<name> (spec/14 §18.16).
      :persistent_term.get(@key, %{
        "Theme::dark" => %{theme: :dark},
        "Frame:axes:no grid" => %{frame: %{axes: [%{scale: :value, side: :left, grid: false}]}},
        "Frame:axes:dense ticks" => %{
          frame: %{
            axes: [
              %{scale: :hour, side: :bottom, ticks: 12},
              %{scale: :value, side: :left, ticks: 10}
            ]
          }
        },
        "Frame:size:wide" => %{frame: %{size: %{width: 900, height: 320}}},
        "Frame:margin:roomy" => %{
          frame: %{margin: %{top: 40, right: 40, bottom: 48, left: 64}}
        },
        "Styles::thick line" => %{styles: %{series: %{stroke_width: 5}}},
        "Styles::stepped" => %{styles: %{series: %{curve: :step}}}
      })
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
  def handle_info({:design_saved, _id, design}, socket) do
    result =
      case Chart.apply(design, sources: socket.assigns.sources) do
        {:ok, _applied} ->
          "saved: the design applies"

        {:error, errors} ->
          "not saved: " <> Enum.map_join(errors, "; ", &Chart.Validator.format/1)
      end

    {:noreply, assign(socket, :saved, result)}
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
          for (const name of ["dragstart", "dragover", "drop", "dragend"]) {
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
