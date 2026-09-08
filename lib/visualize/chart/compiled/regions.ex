defmodule Visualize.Chart.Compiled.Regions do
  @moduledoc false
  # The regions of a compiled chart (spec/14 §12.2): the frame's drawing order as a
  # layout of named regions, each static or dynamic with a reason, and one closure per
  # region drawing it from the frame of a tick and its sources.

  alias Visualize.Chart
  alias Visualize.Chart.Frame
  alias Visualize.Chart.Frame.{Furniture, Labels, Legend, Scales}
  alias Visualize.Chart.Mark
  alias Visualize.IR.Element

  @typedoc "A region name of spec/14 §12.2."
  @type region ::
          :grid
          | {:grid, :outer}
          | {:mark, non_neg_integer()}
          | {:axis, non_neg_integer()}
          | :legend
          | :labels
          | :panels

  @typedoc "Why a region is dynamic."
  @type reason :: :data | :facet | {:inferred, [atom()]}

  @typedoc "One region: its name, its status and the closure that draws it."
  @type t :: %{
          region: region(),
          status: :static | {:dynamic, reason()},
          build: (Frame.t(), map(), atom() -> [Element.t()]),
          static: [Element.t()] | nil
        }

  @typedoc "The frame's drawing order: regions, and a centred group of regions (polar)."
  @type layout :: [region() | {:centred, [region()]}]

  @polar_scales [:angle, :r]

  @doc false
  # The layout and the regions of a chart, given the name of its viewport scale or `nil`.
  @spec build(Chart.t(), atom() | nil) :: {layout(), [t()]}
  def build(%Chart{frame: node} = chart, viewport) do
    axes = Map.get(node, :axes, [])
    layout = layout(node.kind, chart, axes)

    regions =
      for region <- List.flatten(Enum.map(layout, &unwrap/1)) do
        %{
          region: region,
          status: status(region, chart, axes, viewport),
          build: builder(region, node.kind, axes),
          static: nil
        }
      end

    {layout, regions}
  end

  @doc false
  # Whether a scale's domain moves with the data: inferred, or windowed by the viewport.
  @spec moving?(Chart.t(), atom(), atom() | nil) :: boolean()
  def moving?(_chart, name, name), do: true

  def moving?(%Chart{frame: node}, name, _viewport) do
    case get_in(node, [:scales, name]) do
      nil -> false
      scale -> inferred?(Map.get(scale, :domain, :auto))
    end
  end

  @doc false
  # The scales a mark reads, through its channels and a `{:field, f}` on a colour key of
  # its style (spec/14 §4.3).
  @spec mark_scales(Chart.t(), map()) :: [atom()]
  def mark_scales(%Chart{frame: node, styles: styles}, mark) do
    channels =
      for {channel, _value} <- Map.get(mark, :channels, %{}),
          scale = Scales.scale_for(node.kind, mark, channel),
          scale != nil,
          do: scale

    style = Map.get(styles, Map.get(mark, :style), %{})

    colours =
      for key <- [:fill, :stroke], match?({:field, _}, Map.get(style, key)), do: :color

    declared = Map.keys(Map.get(node, :scales, %{}))
    Enum.uniq(channels ++ colours) |> Enum.filter(&(&1 in declared))
  end

  # -- layout ---------------------------------------------------------------------------

  defp layout(:facet, chart, _axes), do: [:panels] ++ tail(chart)

  defp layout(:polar, chart, axes) do
    marks = mark_regions(chart)
    {polar, other} = split_axes(axes)
    inner = grid_region(polar, :grid) ++ marks ++ Enum.map(polar, &{:axis, elem(&1, 1)})

    [{:centred, inner}] ++
      grid_region(other, {:grid, :outer}) ++
      Enum.map(other, &{:axis, elem(&1, 1)}) ++ tail(chart)
  end

  defp layout(_cartesian_or_geo, chart, axes) do
    indexed = Enum.with_index(axes)

    grid_region(indexed, :grid) ++
      mark_regions(chart) ++ Enum.map(indexed, &{:axis, elem(&1, 1)}) ++ tail(chart)
  end

  defp tail(%Chart{frame: node, labels: labels}) do
    legend = if Map.get(node, :legend), do: [:legend], else: []
    labels = if labels == [], do: [], else: [:labels]
    legend ++ labels
  end

  defp mark_regions(%Chart{marks: marks}), do: Enum.with_index(marks, fn _, i -> {:mark, i} end)

  defp grid_region(indexed_axes, name) do
    if Enum.any?(indexed_axes, fn {node, _} -> Map.get(node, :grid, false) end),
      do: [name],
      else: []
  end

  defp split_axes(axes) do
    axes |> Enum.with_index() |> Enum.split_with(fn {node, _} -> node.scale in @polar_scales end)
  end

  defp unwrap({:centred, inner}), do: inner
  defp unwrap(region), do: region

  # -- status ---------------------------------------------------------------------------

  defp status({:mark, _}, _chart, _axes, _viewport), do: {:dynamic, :data}
  defp status(:panels, _chart, _axes, _viewport), do: {:dynamic, :facet}

  defp status(:grid, %{frame: %{kind: :polar}} = chart, axes, viewport) do
    {polar, _} = split_axes(axes)
    scales_status(chart, grid_scales(polar), viewport)
  end

  defp status({:grid, :outer}, chart, axes, viewport) do
    {_, other} = split_axes(axes)
    scales_status(chart, grid_scales(other), viewport)
  end

  defp status(:grid, chart, axes, viewport) do
    scales_status(chart, grid_scales(Enum.with_index(axes)), viewport)
  end

  defp status({:axis, i}, chart, axes, viewport) do
    scales_status(chart, [Enum.at(axes, i).scale], viewport)
  end

  defp status(:legend, %{frame: node} = chart, _axes, viewport) do
    scales_status(chart, [node.legend.scale], viewport)
  end

  defp status(:labels, %{frame: node, labels: labels} = chart, _axes, viewport) do
    if Enum.any?(labels, &match?({:data, _}, &1.anchor)),
      do: scales_status(chart, position_scales(node), viewport),
      else: :static
  end

  defp grid_scales(indexed_axes) do
    for {node, _} <- indexed_axes, Map.get(node, :grid, false), do: node.scale
  end

  defp position_scales(%{kind: :polar} = node), do: declared(node, @polar_scales)
  defp position_scales(%{kind: :geo}), do: []
  defp position_scales(node), do: declared(node, [:x, :y])

  defp declared(node, names),
    do: Enum.filter(names, &Map.has_key?(Map.get(node, :scales, %{}), &1))

  defp scales_status(chart, names, viewport) do
    case names |> Enum.uniq() |> Enum.filter(&moving?(chart, &1, viewport)) |> Enum.sort() do
      [] -> :static
      moving -> {:dynamic, {:inferred, moving}}
    end
  end

  defp inferred?(:auto), do: true
  defp inferred?(extent) when is_list(extent), do: :auto in extent
  defp inferred?(_), do: false

  # -- builders -------------------------------------------------------------------------

  defp builder({:mark, i}, _kind, _axes) do
    fn frame, sources, mode ->
      [
        Mark.generate(frame, Enum.at(frame.marks, i),
          sources: sources,
          resolve: mode,
          index: i + 1
        )
      ]
    end
  end

  defp builder(:panels, _kind, _axes),
    do: fn frame, sources, mode -> Frame.panels(frame, mode, sources) end

  defp builder(:grid, :polar, _axes),
    do: fn frame, _sources, mode -> Furniture.polar_grid(frame, mode) end

  defp builder(:grid, _kind, _axes),
    do: fn frame, _sources, mode -> Furniture.grid(frame, mode) end

  defp builder({:grid, :outer}, :polar, _axes) do
    fn frame, _sources, mode ->
      {_, other} = Furniture.polar_split(frame)
      Furniture.grid(%{frame | axes: other}, mode)
    end
  end

  defp builder({:axis, i}, kind, axes) do
    node = Enum.at(axes, i)

    if kind == :polar and node.scale in @polar_scales,
      do: fn frame, _sources, mode -> [Furniture.polar_axis(frame, node, mode)] end,
      else: fn frame, _sources, mode -> [Furniture.place_axis(frame, node, mode)] end
  end

  defp builder(:legend, _kind, _axes),
    do: fn frame, _sources, mode -> Legend.generate(frame, mode) end

  defp builder(:labels, _kind, _axes),
    do: fn frame, _sources, mode -> Labels.generate(frame, mode) end
end
