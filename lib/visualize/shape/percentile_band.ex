defmodule Visualize.Shape.PercentileBand do
  @moduledoc """
  Percentile-band generator: a median line with an inner and an outer band around it
  (spec/04 §14, D-28).

  A composition of `Visualize.Shape.Area` and `Visualize.Shape.Line` with a fixed output
  shape: `generate/2` returns `%{outer: d, inner: d, median: d}`, each path exactly what the
  standalone generator would produce, or `nil` for a band that is not set.

  ## Examples

      band =
        Visualize.Shape.PercentileBand.new()
        |> Visualize.Shape.PercentileBand.x(fn d -> Visualize.Scale.apply(x_scale, d.t) end)
        |> Visualize.Shape.PercentileBand.median(fn d -> Visualize.Scale.apply(y_scale, d.p50) end)
        |> Visualize.Shape.PercentileBand.inner({&y.(&1.p25), &y.(&1.p75)})
        |> Visualize.Shape.PercentileBand.outer({&y.(&1.p5), &y.(&1.p95)})
        |> Visualize.Shape.PercentileBand.curve(:monotone_x)

      %{outer: outer, inner: inner, median: median} =
        Visualize.Shape.PercentileBand.generate(band, samples)

  """

  alias Visualize.IR.Path
  alias Visualize.Shape.{Area, Curve, Line}

  defstruct x: nil,
            median: nil,
            inner: nil,
            outer: nil,
            defined: nil,
            curve: :linear,
            curve_opts: []

  @type accessor :: Line.accessor()
  @typedoc "The lower and upper percentile of a band."
  @type pair :: {accessor(), accessor()}
  @type t :: %__MODULE__{
          x: accessor() | nil,
          median: (any() -> number()) | nil,
          inner: {(any() -> number()), (any() -> number())} | nil,
          outer: {(any() -> number()), (any() -> number())} | nil,
          defined: (any() -> boolean()) | nil,
          curve: Curve.curve_type(),
          curve_opts: keyword()
        }

  @typedoc "The output: one entry per path, `nil` where the band or median is unset."
  @type output(path) :: %{outer: path | nil, inner: path | nil, median: path | nil}

  @doc "Creates a generator reading tuple element 0 as `x`, with no median and no bands"
  @spec new() :: t()
  def new, do: %__MODULE__{x: fn d -> elem(d, 0) end}

  @doc "Sets the x accessor: 1-arity function, atom field, or numeric constant"
  @spec x(t(), accessor()) :: t()
  def x(%__MODULE__{} = band, accessor), do: %{band | x: Line.normalize_accessor(accessor)}

  @doc "Sets the median accessor; `nil` clears it"
  @spec median(t(), accessor() | nil) :: t()
  def median(%__MODULE__{} = band, nil), do: %{band | median: nil}

  def median(%__MODULE__{} = band, accessor) do
    %{band | median: Line.normalize_accessor(accessor)}
  end

  @doc "Sets the inner band as a `{lo, hi}` pair of accessors; `nil` clears it"
  @spec inner(t(), pair() | nil) :: t()
  def inner(%__MODULE__{} = band, nil), do: %{band | inner: nil}
  def inner(%__MODULE__{} = band, {lo, hi}), do: %{band | inner: normalize_pair(lo, hi)}

  @doc "Sets the outer band as a `{lo, hi}` pair of accessors; `nil` clears it"
  @spec outer(t(), pair() | nil) :: t()
  def outer(%__MODULE__{} = band, nil), do: %{band | outer: nil}
  def outer(%__MODULE__{} = band, {lo, hi}), do: %{band | outer: normalize_pair(lo, hi)}

  @doc "Sets the defined predicate, applied to every path (spec/04 §1.2)"
  @spec defined(t(), (any() -> boolean())) :: t()
  def defined(%__MODULE__{} = band, predicate) when is_function(predicate, 1) do
    %{band | defined: predicate}
  end

  @doc "Sets the curve type and options, applied to every path"
  @spec curve(t(), Curve.curve_type(), keyword()) :: t()
  def curve(%__MODULE__{} = band, curve_type, opts \\ []) do
    %{band | curve: curve_type, curve_opts: opts}
  end

  @doc "Returns `%{outer:, inner:, median:}` of SVG path-data strings, `nil` where unset"
  @spec generate(t(), Visualize.Data.Table.source()) :: output(String.t())
  def generate(%__MODULE__{} = band, data) do
    band
    |> generate_path(data)
    |> Map.new(fn
      {key, nil} -> {key, nil}
      {key, path} -> {key, Visualize.Backend.SVG.path_data(path)}
    end)
  end

  @doc "Returns `%{outer:, inner:, median:}` of `IR.Path`, `nil` where unset"
  @spec generate_path(t(), Visualize.Data.Table.source()) :: output(Path.t())
  def generate_path(%__MODULE__{} = band, data) do
    data = Visualize.Data.Table.rows(data)

    %{
      outer: area_path(band, band.outer, data),
      inner: area_path(band, band.inner, data),
      median: line_path(band, data)
    }
  end

  defp area_path(_band, nil, _data), do: nil

  defp area_path(band, {lo, hi}, data) do
    Area.new()
    |> Area.x(band.x)
    |> Area.y0(lo)
    |> Area.y1(hi)
    |> with_defined(band.defined)
    |> Area.curve(band.curve, band.curve_opts)
    |> Area.generate_path(data)
  end

  defp line_path(%{median: nil}, _data), do: nil

  defp line_path(band, data) do
    Line.new()
    |> Line.x(band.x)
    |> Line.y(band.median)
    |> with_defined(band.defined)
    |> Line.curve(band.curve, band.curve_opts)
    |> Line.generate_path(data)
  end

  defp with_defined(shape, nil), do: shape
  defp with_defined(%Area{} = shape, predicate), do: Area.defined(shape, predicate)
  defp with_defined(%Line{} = shape, predicate), do: Line.defined(shape, predicate)

  defp normalize_pair(lo, hi), do: {Line.normalize_accessor(lo), Line.normalize_accessor(hi)}
end
