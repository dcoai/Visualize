defmodule Examples.Charts.RidgelinePlot do
  @moduledoc """
  Ridgeline plot as a design (#128): one `:area` mark and one `:line` mark, each split by a
  `series` channel into one path per ridge.

  A ridge is an area drawn from its own baseline, and the baselines step up the plot with
  the ridges overlapping by half their height. That offset is a modelling question the
  layer answers in the data rather than the mark: the `y` scale runs over *ridge heights*
  — the plot's height is `(n − 1) × (1 − overlap) + 1` of them — and every row carries its
  ridge's `base` and its density's `top` in that unit, so the `:area` reads `y0: :base,
  y1: :top` through the one linear scale and nothing is translated by hand. The rows are
  listed back to front, so the ridge at the top of the plot is drawn last and lies over the
  one beneath it, as the hand-written version layered them; the `color` scale's domain is
  the ridge index, so the colours still run top to bottom. The basis curve is the style's.
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
        ordinal_scale(:color, domain: ridges),
        area(:ridges, %{x: :x, y: :top, y0: :base, series: :ridge}, style: :ridge),
        line(:ridges, %{x: :x, y: :top, series: :ridge}, style: :crest)
      ])

    {design, %{ridges: rows(opts[:animation_tick])}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # One row per point per ridge, the last ridge first so the first is drawn over it; each
  # ridge's baseline is its distance from the bottom in ridge heights, and its top the
  # density above that in the same unit.
  defp rows(tick) do
    phase = if tick, do: tick * 0.08, else: 0

    for ridge <- (@ridges - 1)..0//-1, i <- 0..(@points - 1)//1 do
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
        ordinal_scale(:color, domain: [0, 1, 2, 3, 4, 5, 6, 7]),
        area(:ridges, %{x: :x, y: :top, y0: :base, series: :ridge}, style: :ridge),
        line(:ridges, %{x: :x, y: :top, series: :ridge}, style: :crest)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{ridges: ridges})
    Visualize.Chart.render(applied)
    """
  end
end
