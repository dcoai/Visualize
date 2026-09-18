defmodule Visualize.Chart.Transform do
  @moduledoc """
  The data pipeline of a mark (spec/14 §5.4, D-62): filtering, binning, stacking,
  aggregation, the layouts of `Visualize.Layout` and the geo algorithms as `%{op: …}`
  steps over rows.

  `apply/3` runs the steps of a mark's `data.transforms` in order over its source's rows,
  each a pure function of the rows before it and its node, and yields the rows the mark
  draws. Its only context is the plot area (`size:`, the extent every layout defaults
  to) and, in a `:geo` frame, the projection (`projection:`) — never a scale, which is
  what lets `Visualize.Chart.Frame.new/2` run the pipeline before its scales exist and
  infer their domains from the transformed columns. A layout's rows carry their shape as
  a `Visualize.IR.Path` under `path`, which the `:path` mark draws as it is.

  ## Examples

      iex> rows = [%{v: 1}, %{v: 2}, %{v: 2}, %{v: 9}]
      iex> Visualize.Chart.Transform.apply([%{op: :bin, field: :v, thresholds: [5]}], rows)
      [%{x0: 1, x1: 5, y0: 0, count: 3, values: [1, 2, 2]}, %{x0: 5, x1: 9, y0: 0, count: 1, values: [9]}]

  """

  alias Visualize.Chart.Schema
  alias Visualize.Chart.Transform.{Data, Geo, Layout}
  alias Visualize.Data.Table
  alias Visualize.Geo.Projection

  @typedoc "What a step sees of the frame: the plot area, in a `:geo` frame its projection, and the bound sources for a graph's node table."
  @type context :: %{size: [number()], projection: Projection.t() | nil, sources: map()}

  @data_ops [:filter, :bin, :stack, :fold, :sum, :sort]
  @layout_ops [:tree, :cluster, :pack, :partition, :treemap, :chord, :sankey, :force]
  @geo_ops [:delaunay, :voronoi, :contour, :density, :projection]

  @doc """
  The rows after every transform node, in order (spec/14 §5.4).

  ## Options

    * `:size` - the `[width, height]` the layouts and the geo algorithms default to
      (default `[1, 1]`)
    * `:projection` - the `%Visualize.Geo.Projection{}` a `:projection` step maps through
      (default `nil`)
    * `:sources` - the bound sources by name, for a graph step's `nodes` (default `%{}`)

  Raises `ArgumentError` for an op that is not one of spec/14 §5.4, a key an op requires
  and the node lacks, or a `:projection` step without a projection.
  """
  @spec apply([map()], Table.source(), keyword()) :: [map()]
  def apply(transforms, rows, opts \\ []) when is_list(transforms) do
    ctx = context(opts)
    Enum.reduce(transforms, Table.rows(rows), &run(&1, &2, ctx))
  end

  @doc "One step of `apply/3`: the rows after the transform node."
  @spec step(map(), Table.source(), keyword()) :: [map()]
  def step(transform, rows, opts), do: run(transform, Table.rows(rows), context(opts))

  defp context(opts) do
    %{
      size: Keyword.get(opts, :size, [1, 1]),
      projection: Keyword.get(opts, :projection),
      sources: Keyword.get(opts, :sources, %{})
    }
  end

  defp run(%{op: op} = node, rows, ctx) do
    op in Schema.transform_ops() ||
      raise ArgumentError, "#{inspect(op)} is not a transform op (spec/14 §5.4)"

    required!(node, op)

    cond do
      op in @data_ops -> Data.run(op, node, rows)
      op in @layout_ops -> Layout.run(op, node, rows, ctx)
      op in @geo_ops -> Geo.run(op, node, rows, ctx)
    end
  end

  defp run(node, _rows, _ctx) do
    raise ArgumentError, "a transform node needs an op: #{inspect(node)}"
  end

  defp required!(node, op) do
    for key <- Schema.transform_keys(op).required, not Map.has_key?(node, key) do
      raise ArgumentError, "transform #{inspect(op)} needs #{inspect(key)} (spec/14 §5.4)"
    end
  end
end
