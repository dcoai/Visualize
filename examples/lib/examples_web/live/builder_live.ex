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
      :persistent_term.get(@key, %{
        "dark" => %{theme: :dark},
        "grid" => %{frame: %{axes: [%{scale: :y, side: :left, grid: true}]}}
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
        {:ok, _applied} -> "saved: the design applies"
        {:error, errors} -> "not saved: " <> Enum.map_join(errors, "; ", &Chart.Validator.format/1)
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
