defmodule ExamplesWeb.AnimationsDemo do
  @moduledoc """
  The interaction page's animations (spec/14 §3.11, #677, D-176, work item #786): one tile
  per animation a style can run while it holds — the four built-ins, `:pulse`, `:blink`,
  `:shake` and `:spin`, each with its own `duration`, `easing`, `iterations` and `delay`,
  and `"wiggle"`, keyframes the page itself defines (`keyframes/0`), named by a string.

  Each tile's row names its style (`style: {:field, "motion"}`, spec/14 §3.6), so the
  animation is the data's choice, as a state's would be. A reader who asks for less motion
  sees none of them: the frame's `<style>` turns every animation off under
  `prefers-reduced-motion: reduce`, and a design cannot override it.
  """

  import Visualize.Color, only: [color: 1]

  alias Visualize.Chart

  # Each tile: its style's name, the animation it runs, and what the tile says of it.
  @motions [
    {"pulse", %{name: :pulse, duration: 1200}, "infinite"},
    {"blink", %{name: :blink, duration: 800, iterations: 3, delay: 400}, "3 times, after 400 ms"},
    {"shake", %{name: :shake, duration: 700, easing: :cubic_in_out, iterations: 4, delay: 200},
     "4 times, cubic in-out"},
    {"spin", %{name: :spin, duration: 3000, easing: :linear}, "infinite, linear"},
    {"wiggle", %{name: "wiggle", duration: 900, easing: :cubic_in_out}, "the page's keyframes"}
  ]

  @fills [:series_1, :series_2, :series_3, :series_4, :series_5]

  @doc "The animations the tiles run: `{style name, animation, note}`."
  @spec motions() :: [{String.t(), map(), String.t()}]
  def motions, do: @motions

  @doc "The design: a tile per row, styled by the row's `motion`."
  @spec design() :: map()
  def design do
    styles =
      Map.new(Enum.zip(@motions, @fills), fn {{name, animation, _note}, fill} ->
        {name, %{fill: color(fill), animation: animation}}
      end)

    %{
      version: 3,
      sources: %{"tiles" => %{fields: ["motion", "note"]}},
      styles: styles,
      frames: %{
        "main" => %{
          kind: :cartesian,
          margin: %{top: 30, right: 20, bottom: 40, left: 20},
          scales: %{
            "x" => %{kind: :band, padding: 0.35},
            "y" => %{kind: :linear, domain: [0, 1]}
          },
          axes: [%{scale: "x", side: :bottom}]
        }
      },
      marks: [
        %{
          type: :rect,
          data: "tiles",
          channels: %{x0: "motion", x1: "motion", y0: 0.2, y1: 0.8},
          style: {:field, "motion"},
          tooltip: %{fields: ["motion", "note"], template: "{motion}: {note}"}
        }
      ],
      labels: [%{anchor: :title, text: ["animation: a motion the style runs while it holds"]}]
    }
  end

  @doc "The tiles' rows."
  @spec rows() :: [map()]
  def rows, do: for({name, _animation, note} <- @motions, do: %{"motion" => name, "note" => note})

  @doc """
  The host's own keyframes, which the page's stylesheet holds: a string `name` is written
  as it is, so the page must define it (spec/14 §3.11, *Host keyframes*).
  """
  @spec keyframes() :: String.t()
  def keyframes do
    "@keyframes wiggle { 0%, 100% { rotate: 0deg; } 25% { rotate: -12deg; } " <>
      "75% { rotate: 12deg; } }"
  end

  @doc "The chart at `size`, applied for `Visualize.Components.Chart`."
  @spec applied({pos_integer(), pos_integer()}) :: Chart.Applied.t()
  def applied(size) do
    {:ok, applied} = Chart.apply(design(), sources: %{"tiles" => rows()}, size: size)
    applied
  end

  @doc "The design's styles as a reader writes them, for the page's code panel."
  @spec code() :: String.t()
  def code do
    ~S'''
    styles: %{
      "pulse" => %{fill: color(:series_1), animation: %{name: :pulse, duration: 1200}},
      "blink" => %{fill: color(:series_2),
        animation: %{name: :blink, duration: 800, iterations: 3, delay: 400}},
      "shake" => %{fill: color(:series_3),
        animation: %{name: :shake, duration: 700, easing: :cubic_in_out, iterations: 4, delay: 200}},
      "spin" => %{fill: color(:series_4), animation: %{name: :spin, duration: 3000, easing: :linear}},
      # A string names the host's own keyframes, which the page's stylesheet defines:
      #   @keyframes wiggle { 0%, 100% { rotate: 0deg; } 25% { rotate: -12deg; } 75% { rotate: 12deg; } }
      # On a canvas, register the same motion with the hooks:
      #   VisualizeMotion.register("wiggle", [[0, {rotate: 0}], [0.25, {rotate: -12}], [0.75, {rotate: 12}], [1, {rotate: 0}]])
      "wiggle" => %{fill: color(:series_5), animation: %{name: "wiggle", duration: 900, easing: :cubic_in_out}}
    }
    '''
  end
end
