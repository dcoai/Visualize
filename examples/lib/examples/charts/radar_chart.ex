defmodule Examples.Charts.RadarChart do
  @moduledoc """
  A radar as a design (#389, #393): a polar frame whose `angle` scale is a `:band` over
  six categories — spaced 60° apart, the first at the top, the ring closed (spec/14 §4.3)
  — and `r` the score from the center. Three series read through one `:area` and one
  `:line`: over a categorical angle a straight segment is a chord and the loop closes on
  the full turn (§5.2), so each series is a polygon with its volume filled at a third of
  its opacity, drawn on top of one another so every volume shows through — the scope
  view. The angle axis ticks the categories at their spokes, and the `r` axis's grid arcs
  give the web. Animated, the scores drift.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 30, right: 90, bottom: 30, left: 40}
  @categories ~w(speed power range agility armor stealth)
  @series [
    %{name: "scout", scores: [9, 3, 7, 9, 2, 8]},
    %{name: "tank", scores: [3, 9, 4, 2, 9, 1]},
    %{name: "ranger", scores: [6, 5, 9, 6, 4, 6]}
  ]

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {420, 420}

  def title, do: "Radar"
  def description, do: "Three units over six attributes, layered on a closed ring"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:scores, [:attribute, :score, :unit],
          types: %{attribute: :category, score: :number, unit: :category}
        ),
        style(:volume, fill_opacity: 0.3, stroke: :none),
        style(:edge, stroke_width: 2),
        style(:spoke, extends: :axis, font_size: 11),
        polar(margin: @margin),
        band_scale(:angle, domain: @categories),
        linear_scale(:r, domain: [0, 10]),
        ordinal_scale(:color, domain: Enum.map(@series, & &1.name)),
        axis(:angle, :bottom, grid: true, style: :spoke),
        axis(:r, :top, ticks: 5, grid: true),
        legend(:color, position: :top_right, inside: false),
        area(:scores, %{x: :attribute, y: :score, series: :unit}, style: :volume),
        line(:scores, %{x: :attribute, y: :score, series: :unit}, style: :edge)
      ])

    {design, %{scores: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    tick = opts[:animation_tick]

    for %{name: name, scores: scores} <- @series,
        {attribute, i} <- Enum.with_index(@categories) do
      base = Enum.at(scores, i)
      score = if tick, do: drift(base, tick, name, i), else: base
      %{attribute: attribute, score: score, unit: name}
    end
  end

  # Animation: every score sways within a point and a half of its value, each on its own
  # phase, so the polygons breathe against one another.
  defp drift(base, tick, name, i) do
    phase = String.length(name) * 0.7 + i * 1.1
    Float.round(max(0.5, min(10.0, base + 1.5 * :math.sin(tick * 0.09 + phase))), 2)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Radar"}),
        source(:scores, [:attribute, :score, :unit]),
        style(:volume, fill_opacity: 0.3, stroke: :none),
        style(:edge, stroke_width: 2),
        polar(margin: %{top: 30, right: 90, bottom: 30, left: 40}),
        # A band on angle: six categories 60° apart, the first at the top, the ring closed
        # (spec/14 §4.3).
        band_scale(:angle, domain: ~w(speed power range agility armor stealth)),
        linear_scale(:r, domain: [0, 10]),
        ordinal_scale(:color, domain: ["scout", "tank", "ranger"]),
        axis(:angle, :bottom, grid: true),
        axis(:r, :top, ticks: 5, grid: true),
        # Over a categorical angle a segment is a chord and the loop closes on the full
        # turn (spec/14 §5.2): each series is a polygon, its volume translucent, layered.
        area(:scores, %{x: :attribute, y: :score, series: :unit}, style: :volume),
        line(:scores, %{x: :attribute, y: :score, series: :unit}, style: :edge)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{scores: scores})
    Visualize.Chart.render(applied)
    """
  end
end
