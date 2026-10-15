defmodule ExamplesWeb.MotionDemo do
  @moduledoc """
  The interaction page's motion demo (spec/14 §3.10–§3.12, #653): a bar per service, its
  state choosing its style by data. A change of state fades the bar from one color to the
  next in OKLab, a service in error pulses while it is, and a click on a bar deletes its
  row, which explodes before it is gone. The bars are named by their service through the
  `series` channel, so each keeps its identity when another is deleted.
  """

  alias Visualize.Chart

  @services ~w(api auth billing cache db queue search web)
  @states [:ok, :warning, :error]

  @design %{
    version: 3,
    sources: %{services: %{fields: [:name, :load, :state]}},
    styles: %{
      ok: %{fill: {:color, :good}},
      warning: %{fill: {:color, :warning}},
      error: %{fill: {:color, :bad}, animation: %{name: :pulse, duration: 1200}}
    },
    frames: %{
      main: %{
        kind: :cartesian,
        margin: %{top: 30, right: 20, bottom: 40, left: 50},
        scales: %{
          x: %{kind: :band, padding: 0.2},
          y: %{kind: :linear, domain: [0, 100]}
        },
        axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left, ticks: 5, grid: true}]
      }
    },
    marks: [
      %{
        type: :rect,
        data: :services,
        channels: %{x0: :name, x1: :name, y0: 0, y1: :load, series: :name},
        # The motion every bar has, then the state's look over it (spec/14 §3.6).
        style: [
          %{
            transition: %{fill: %{duration: 600}},
            enter: %{name: :grow, duration: 400},
            exit: %{name: :explode, duration: 800}
          },
          {:field, :state}
        ],
        tooltip: %{
          fields: [:name, :state, :load],
          template: "{name}: {state}, load {load}\nclick to delete",
          event: :delete
        }
      }
    ],
    labels: [%{anchor: :title, text: ["Click a bar to delete its row"]}]
  }

  @doc "The services as the demo starts: every one up, each at its own load."
  @spec rows() :: [map()]
  def rows do
    for {name, i} <- Enum.with_index(@services),
        do: %{name: name, load: 30 + rem(i * 37, 60), state: :ok}
  end

  @doc "The rows with the `n`th service still drawn moved on to its next state."
  @spec next_state([map()], non_neg_integer()) :: [map()]
  def next_state([], _n), do: []

  def next_state(rows, n) do
    i = rem(n, length(rows))

    List.update_at(rows, i, fn row ->
      at = Enum.find_index(@states, &(&1 == row.state))
      %{row | state: Enum.at(@states, rem(at + 1, length(@states)))}
    end)
  end

  @doc "The rows without the named service."
  @spec delete([map()], String.t()) :: [map()]
  def delete(rows, name), do: Enum.reject(rows, &(&1.name == name))

  @doc "The chart over the rows at `size`, applied for `Visualize.Components.Chart`."
  @spec applied([map()], {pos_integer(), pos_integer()}) :: Chart.Applied.t()
  def applied(rows, size) do
    {:ok, applied} = Chart.apply(Chart.from_map!(@design), sources: %{services: rows}, size: size)
    applied
  end
end
