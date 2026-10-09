defmodule Examples.Charts.RidgelinePlot do
  @moduledoc """
  Ridgeline plot as a design (#128): per ridge, an `:area` mark (its fill) and then a
  `:line` mark (its crest), each over that ridge's rows through a `:filter` step.

  A ridge is an area drawn from its own baseline, and the baselines step up the plot with
  the ridges overlapping by half their height. That offset is a modelling question the
  layer answers in the data rather than the mark: the `y` scale runs over *ridge heights*
  — the plot's height is `(n − 1) × (1 − overlap) + 1` of them — and every row carries its
  ridge's `base` and its density's `top` in that unit, so the `:area` reads `y0: :base,
  y1: :top` through the one linear scale and nothing is translated by hand.

  A ridgeline reads front to back (#491): the ridge at the top of the plot is the farthest
  and is drawn first, and each ridge below it is nearer and drawn after it, covering it.
  A ridge's crest belongs to its fill, so the marks go fill, crest, fill, crest down the
  plot; one `:area` and one `:line` over every ridge would draw every fill before any
  crest, and a hidden ridge's crest would then show through the fill in front of it. The
  `color` scale's domain is the ridge index, so the colours run top to bottom. The basis
  curve is the style's.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 20, bottom: 30, left: 50}
  @ridges 8
  @points 50
  @overlap 0.5
  # The density's own range, which one ridge height spans.
  @peak 80

  def title, do: "Ridgeline Plot"
  def description, do: "Overlapping density distributions"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    ridges = Enum.to_list(0..(@ridges - 1)//1)

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:ridges, [:ridge, :x, :base, :top]),
        style(:ridge, fill_opacity: 0.85, curve: :basis),
        style(:crest, stroke_width: 1.5, curve: :basis),
        cartesian(margin: @margin),
        linear_scale(:x, domain: [0, 100]),
        # Ridge heights: the last ridge's baseline is 0, the first ridge's top is the plot's.
        linear_scale(:y, domain: [0, (@ridges - 1) * (1 - @overlap) + 1]),
        ordinal_scale(:color, domain: ridges)
        | ridges(ridges)
      ])

    {design, %{ridges: rows(opts[:animation_tick])}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # Far to near, the top ridge first: each ridge's fill and then its own crest (#491).
  defp ridges(ridges) do
    Enum.flat_map(ridges, fn ridge ->
      rows = filter(:ridges, :ridge, test: :eq, value: ridge)

      [
        area(rows, %{x: :x, y: :top, y0: :base, series: :ridge}, style: :ridge),
        line(rows, %{x: :x, y: :top, series: :ridge}, style: :crest)
      ]
    end)
  end

  # One row per point per ridge, the top ridge first; each ridge's baseline is its distance
  # from the bottom in ridge heights, and its top the density above that in the same unit.
  defp rows(tick) do
    phase = if tick, do: tick * 0.08, else: 0

    for ridge <- 0..(@ridges - 1)//1, i <- 0..(@points - 1)//1 do
      x = i / (@points - 1) * 100
      base = (@ridges - 1 - ridge) * (1 - @overlap)
      %{ridge: ridge, x: x, base: base, top: base + density(x, ridge, phase, tick) / @peak}
    end
  end

  # A wave-like density with several peaks; animated, the peaks travel.
  defp density(x, ridge, phase, tick) do
    ridge_phase = if tick, do: phase + ridge * 0.3, else: ridge * 0.4

    y =
      :math.sin(x / 15 + ridge_phase) * 20 +
        :math.cos(x / 10 + ridge_phase * 1.3) * 15 +
        :math.sin(x / 5 + ridge_phase * 0.7) * 10 + 40

    max(0, y)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Ridgeline Plot"}),
        # One row per point per ridge: the ridge's baseline and the density's top, both in
        # ridge heights, so the offset is in the data and the y scale is one linear scale.
        source(:ridges, [:ridge, :x, :base, :top]),
        style(:ridge, fill_opacity: 0.85, curve: :basis),
        style(:crest, stroke_width: 1.5, curve: :basis),
        cartesian(margin: %{top: 20, right: 20, bottom: 30, left: 50}),
        linear_scale(:x, domain: [0, 100]),
        # Eight ridges overlapping by half: the plot is 4.5 ridge heights tall.
        linear_scale(:y, domain: [0, 4.5]),
        ordinal_scale(:color, domain: [0, 1, 2, 3, 4, 5, 6, 7])
        # Far to near, the top ridge first: each ridge's fill and then its own crest, so a
        # nearer ridge covers the one behind it, crest and all.
        | Enum.flat_map(0..7, fn ridge ->
            rows = filter(:ridges, :ridge, test: :eq, value: ridge)

            [
              area(rows, %{x: :x, y: :top, y0: :base, series: :ridge}, style: :ridge),
              line(rows, %{x: :x, y: :top, series: :ridge}, style: :crest)
            ]
          end)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{ridges: ridges})
    Visualize.Chart.render(applied)
    """
  end
end
