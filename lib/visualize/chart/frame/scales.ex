defmodule Visualize.Chart.Frame.Scales do
  @moduledoc false
  # Scale realisation and inference for a frame (spec/14 §4.3): one struct per `:scale`
  # node through the constructors of `Visualize.Scale`, `:auto` domains from the whole
  # bound column of every mark channel naming the scale, `:auto` ranges from the plot
  # area by the scale's name, and the unit domain when nothing is bound (D-60).

  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.{Data, Scale, Theme}
  alias Visualize.Data.Table
  alias Visualize.Scale.{Band, Color, Ordinal, Power, Symlog}

  @discrete [:ordinal, :band, :quantize, :quantile, :threshold]
  @continuous [:linear, :log, :power, :sqrt, :symlog, :radial, :quantize, :threshold]
  @colour [:sequential, :diverging]
  @epoch ~U[1970-01-01 00:00:00Z]

  # The scale each channel names, by frame kind (spec/14 §4.3).
  @cartesian %{
    x: :x,
    x0: :x,
    x1: :x,
    y: :y,
    y0: :y,
    y1: :y,
    median: :y,
    inner: :y,
    outer: :y,
    value: :color
  }
  @polar %{angle: :angle, value: :r, inner: :r, outer: :r}
  @geo %{value: :color}

  @doc false
  # Every scale of the frame node realised: `%{name => struct}`.
  @spec realise(map(), atom(), map(), Theme.t(), map(), %{atom() => map()}) ::
          %{atom() => struct()}
  def realise(design, kind, plot, theme, sources, styles) do
    frame = design.frame
    columns = columns(design, kind, sources, styles)
    axes = Map.get(frame, :axes, [])

    Map.new(Map.get(frame, :scales, %{}), fn {name, node} ->
      {name, build(name, node, Map.get(columns, name, []), plot, theme, axes)}
    end)
  end

  @doc false
  # The channel-to-scale table of a frame kind.
  @spec channel_scales(atom()) :: %{atom() => atom()}
  def channel_scales(:polar), do: @polar
  def channel_scales(:geo), do: @geo
  def channel_scales(_cartesian_or_facet), do: @cartesian

  @doc false
  # The rows of a mark's source when it is bound, `[]` otherwise; only map rows carry
  # names a channel can read.
  @spec mark_rows(map(), map()) :: [map()]
  def mark_rows(mark, sources) do
    case Map.fetch(sources, source_name(mark.data)) do
      {:ok, source} -> source |> Table.rows() |> Enum.filter(&is_map/1)
      :error -> []
    end
  end

  defp source_name(%Var{name: name}), do: Style.unresolved!(name)
  defp source_name(name) when is_atom(name), do: name
  defp source_name(%{source: name}), do: name

  # -- the bound columns per scale --------------------------------------------------

  defp columns(design, kind, sources, styles) do
    table = channel_scales(kind)

    design.marks
    |> Enum.flat_map(fn mark -> mark_columns(mark, table, sources, styles) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {scale, columns} -> {scale, List.flatten(columns)} end)
  end

  defp mark_columns(mark, table, sources, styles) do
    rows = mark_rows(mark, sources)

    channels =
      for {channel, value} <- Map.get(mark, :channels, %{}),
          scale = Map.get(table, channel),
          scale != nil,
          do: {scale, values(value, rows)}

    colours =
      for key <- [:fill, :stroke],
          {:field, field} <- [Map.get(Style.node(styles, Map.get(mark, :style)), key)],
          do: {:color, column(rows, field)}

    channels ++ colours
  end

  defp values(%Var{name: name}, _rows), do: Style.unresolved!(name)
  defp values(n, _rows) when is_number(n), do: [n]
  defp values({:field, field}, rows), do: column(rows, field)
  defp values(field, rows) when is_atom(field), do: column(rows, field)

  defp column(rows, field), do: rows |> Enum.map(&Table.get(&1, field)) |> Enum.reject(&is_nil/1)

  # -- one scale ------------------------------------------------------------------------

  defp build(name, node, values, plot, theme, axes) do
    kind = get(node, :kind)
    domain = domain(kind, name, get(node, :domain), values)
    range = range(kind, name, get(node, :range), plot, theme, axes)

    kind
    |> construct(node, range)
    |> with_domain(kind, domain)
    |> with_range(kind, range)
    |> flag(:nice, get(node, :nice))
    |> flag(:clamp, get(node, :clamp))
  end

  defp get(node, key), do: Map.get(node, key, Schema.default(:scale, key))

  defp construct(:linear, _node, _range), do: Scale.linear()
  defp construct(:log, node, _range), do: Scale.log(get(node, :base))
  defp construct(:power, node, _range), do: Power.exponent(Scale.power(), get(node, :exponent))
  defp construct(:sqrt, _node, _range), do: Scale.sqrt()
  defp construct(:symlog, node, _range), do: Symlog.constant(Scale.symlog(), get(node, :constant))
  defp construct(:time, _node, _range), do: Scale.time()
  defp construct(:radial, _node, _range), do: Scale.radial()

  defp construct(:ordinal, node, _range),
    do: Ordinal.unknown(Scale.ordinal(), get(node, :unknown))

  defp construct(:band, node, _range), do: band(node)
  defp construct(:quantize, _node, _range), do: Scale.quantize()
  defp construct(:quantile, _node, _range), do: Scale.quantile()
  defp construct(:threshold, _node, _range), do: Scale.threshold()
  defp construct(:sequential, _node, range), do: Scale.sequential(range)
  defp construct(:diverging, _node, range), do: Scale.diverging(range)

  defp band(node) do
    inner = Map.get(node, :padding_inner)
    outer = Map.get(node, :padding_outer)

    scale =
      if inner == nil and outer == nil do
        Band.padding(Scale.band(), get(node, :padding))
      else
        Scale.band()
        |> Band.padding_inner(inner || get(node, :padding))
        |> Band.padding_outer(outer || get(node, :padding))
      end

    scale |> Band.align(get(node, :align)) |> Band.round(get(node, :round))
  end

  defp with_domain(scale, :diverging, [lo, hi]), do: Scale.domain(scale, [lo, (lo + hi) / 2, hi])
  defp with_domain(scale, _kind, domain), do: Scale.domain(scale, domain)

  # A colour scale's range is the interpolator it was constructed over.
  defp with_range(scale, kind, _range) when kind in @colour, do: scale
  defp with_range(scale, _kind, range), do: Scale.range(scale, range)

  defp flag(scale, :nice, true), do: Scale.nice(scale)
  defp flag(scale, :clamp, true), do: Scale.clamp(scale, true)
  defp flag(scale, _flag, _false), do: scale

  # -- domain ---------------------------------------------------------------------------

  defp domain(kind, name, :auto, values), do: infer(kind, name, values)

  defp domain(kind, name, [lo, hi], values) when lo == :auto or hi == :auto do
    case infer(kind, name, values) do
      [ilo, ihi] -> [fixed(lo, ilo), fixed(hi, ihi)]
      inferred -> inferred
    end
  end

  defp domain(_kind, _name, extent, _values), do: extent

  defp fixed(:auto, inferred), do: inferred
  defp fixed(given, _inferred), do: given

  defp infer(kind, _name, values) when kind in [:ordinal, :band], do: Enum.uniq(values)
  defp infer(:quantile, _name, values), do: values
  defp infer(:time, name, values), do: time_extent(name, Enum.map(values, &temporal(&1, name)))

  defp infer(kind, name, values) when kind in @continuous or kind in @colour do
    Enum.each(values, fn v ->
      is_number(v) or
        raise ArgumentError,
              "scale #{inspect(name)} (#{kind}) cannot take #{inspect(v)}: a number is needed"
    end)

    extent(kind, name, values)
  end

  defp extent(:log, _name, []), do: [1, 10]
  defp extent(_kind, _name, []), do: [0, 1]

  defp extent(:log, name, values) do
    {lo, hi} = Data.extent(values)

    if lo > 0 do
      [lo, hi]
    else
      raise ArgumentError,
            "scale #{inspect(name)} (log) cannot take #{lo}: a log domain is positive"
    end
  end

  defp extent(_kind, _name, values) do
    {lo, hi} = Data.extent(values)
    [lo, hi]
  end

  defp time_extent(_name, []), do: [@epoch, DateTime.add(@epoch, 86_400, :second)]

  defp time_extent(_name, values) do
    {lo, hi} = Enum.min_max_by(values, &time_key/1)
    [lo, hi]
  end

  defp time_key(%DateTime{} = t), do: DateTime.to_unix(t, :microsecond)

  defp time_key(%NaiveDateTime{} = t),
    do: NaiveDateTime.diff(t, ~N[1970-01-01 00:00:00], :microsecond)

  defp time_key(%Date{} = d), do: Date.diff(d, ~D[1970-01-01]) * 86_400_000_000

  defp temporal(%mod{} = value, _name) when mod in [DateTime, NaiveDateTime, Date], do: value

  defp temporal(value, name) when is_binary(value) do
    with {:error, _} <- iso(DateTime.from_iso8601(value)),
         {:error, _} <- NaiveDateTime.from_iso8601(value),
         {:error, _} <- Date.from_iso8601(value) do
      not_temporal!(value, name)
    else
      {:ok, parsed} -> parsed
    end
  end

  defp temporal(value, name), do: not_temporal!(value, name)

  defp iso({:ok, dt, _offset}), do: {:ok, dt}
  defp iso(error), do: error

  defp not_temporal!(value, name) do
    raise ArgumentError,
          "scale #{inspect(name)} (time) cannot take #{inspect(value)}: a DateTime, Date, " <>
            "NaiveDateTime or ISO 8601 string is needed"
  end

  # -- range ----------------------------------------------------------------------------

  # A colour scale's `:auto` range is theme-derived whatever its name: its output is a
  # colour, and the plot area has nothing to offer it.
  defp range(:sequential, _name, :auto, _plot, theme, _axes) do
    [theme.background, hd(theme.series)]
  end

  defp range(:diverging, _name, :auto, _plot, theme, _axes) do
    [Enum.at(theme.series, 1, hd(theme.series)), theme.background, hd(theme.series)]
  end

  defp range(_kind, :x, :auto, plot, _theme, _axes), do: [0, plot.width]
  defp range(_kind, :y, :auto, plot, _theme, _axes), do: [plot.height, 0]
  defp range(_kind, :angle, :auto, _plot, _theme, _axes), do: [0, 2 * :math.pi()]
  defp range(_kind, :r, :auto, plot, _theme, _axes), do: [0, min(plot.width, plot.height) / 2]

  defp range(kind, :color, :auto, _plot, theme, _axes) when kind in @discrete do
    Enum.map(1..length(theme.series)//1, &Theme.series_slot(theme, &1))
  end

  defp range(kind, name, :auto, plot, theme, axes) do
    case Enum.find(axes, &(&1.scale == name)) do
      %{side: side} when side in [:top, :bottom] -> range(kind, :x, :auto, plot, theme, [])
      %{side: side} when side in [:left, :right] -> range(kind, :y, :auto, plot, theme, [])
      nil -> [0, 1]
    end
  end

  defp range(_kind, name, scheme, _plot, _theme, _axes) when is_atom(scheme) do
    Color.scheme(scheme) ||
      raise ArgumentError,
            "scale #{inspect(name)}: #{inspect(scheme)} is not a scheme of " <>
              "Visualize.Scale.Color.schemes/0"
  end

  defp range(_kind, _name, list, _plot, _theme, _axes) when is_list(list), do: list
end
