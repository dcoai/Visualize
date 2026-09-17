defmodule Examples.Charts.ChordDiagram do
  @moduledoc """
  Chord diagram as a design (#126, #137): the `:chord` transform over the flows — the
  transform the layer grew for exactly this figure — under two marks: the ribbons as a
  `:path` mark over `output: :chords`, and the group arcs as an `:arc` mark over the
  groups' own `start_angle` and `end_angle` (spec/14 §5.6, D-69), which is what lets the
  region names sit outside the ring on each group's spoke — the `:outward` anchor with
  `rotate: :radial` (§5.5). That annotation kept the chart imperative until #137.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @zero_margin %{top: 0, right: 0, bottom: 0, left: 0}
  @groups ["Asia", "Europe", "Americas", "Africa", "Oceania"]

  # Migration flow matrix (rows = from, columns = to)
  @matrix [
    [11975, 5871, 8916, 2868, 1200],
    [1951, 10048, 2060, 6171, 950],
    [8010, 16145, 8090, 8045, 1500],
    [1013, 990, 940, 6907, 800],
    [500, 800, 600, 400, 2000]
  ]

  def title, do: "Chord Diagram"
  def description, do: "Inter-regional migration flows"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    width = opts[:width] || 500
    height = opts[:height] || 500
    radius = min(width, height) / 2 - 40
    size = [2 * radius, 2 * radius]

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:flows, [:from, :to, :value]),
        style(:group, fill: {:field, :id}, stroke: :background, stroke_width: 1),
        style(:ribbon, fill: {:field, :source}, fill_opacity: 0.6, stroke: {:field, :source}, stroke_width: 0.5),
        style(:region, extends: :label, font_size: 11),
        cartesian(width, height, margin: @zero_margin),
        ordinal_scale(:color),
        path(chord(:flows, [:from, :to], :value, padding: 0.05, output: :chords, size: size), %{path: :path},
          style: :ribbon
        ),
        arc(chord(:flows, [:from, :to], :value, padding: 0.05, size: size),
          %{value: :value, start: :start_angle, end: :end_angle},
          options: %{inner_radius: radius - 20, outer_radius: radius},
          label: %{text: [{:field, :id}], anchor: :outward, dr: 6, rotate: :radial, style: :region},
          style: :group
        )
      ])

    {design, %{flows: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # The matrix as flows: one row per from → to cell.
  defp rows(opts) do
    matrix =
      case opts[:animation_tick] do
        nil -> opts[:matrix] || @matrix
        tick -> animated(tick)
      end

    for {row, i} <- Enum.with_index(matrix), {value, j} <- Enum.with_index(row) do
      %{from: Enum.at(@groups, i), to: Enum.at(@groups, j), value: value}
    end
  end

  # Animation: each flow breathes about its value.
  defp animated(tick) do
    phase = tick * 0.05

    for {row, i} <- Enum.with_index(@matrix) do
      for {base, j} <- Enum.with_index(row) do
        k = i * 5 + j
        trunc(max(100, base + :math.sin(phase + k * 0.5) * base / 6))
      end
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Chord Diagram"}),
        source(:flows, [:from, :to, :value]),
        style(:group, fill: {:field, :id}, stroke: :background),
        style(:ribbon, fill: {:field, :source}, fill_opacity: 0.6),
        style(:region, extends: :label, font_size: 11),
        cartesian(500, 500, margin: %{top: 0, right: 0, bottom: 0, left: 0}),
        ordinal_scale(:color),
        # The ribbons: the :chord transform's chords, each a ready path.
        path(chord(:flows, [:from, :to], :value, padding: 0.05, output: :chords, size: [420, 420]),
          %{path: :path}, style: :ribbon),
        # The group arcs from the groups' own angles, and the region names outside the
        # ring on each group's spoke (spec/14 §5.5).
        arc(chord(:flows, [:from, :to], :value, padding: 0.05, size: [420, 420]),
          %{value: :value, start: :start_angle, end: :end_angle},
          options: %{inner_radius: 190, outer_radius: 210},
          label: %{text: [{:field, :id}], anchor: :outward, dr: 6, rotate: :radial, style: :region},
          style: :group
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{flows: flows})
    Visualize.Chart.render(applied)
    """
  end
end
