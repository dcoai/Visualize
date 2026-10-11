defmodule Visualize.Chart.Frame.Scales do
  @moduledoc false
  # Scale realisation and inference for a frame (spec/14 §4.3): one struct per `:scale`
  # node through the constructors of `Visualize.Scale`, `:auto` domains from the whole
  # bound column of every mark channel naming the scale, `:auto` ranges from the plot
  # area by the scale's name, and the unit domain when nothing is bound (D-60).

  alias Visualize.Chart.{Schema, Style, Transform, Var}
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
    inner_lo: :y,
    inner_hi: :y,
    outer_lo: :y,
    outer_hi: :y,
    value: :color,
    series: :color
  }
  # In a polar frame the cartesian channels are the polar ones (spec/14 §4.3, #391): x
  # names angle and y names r, so every mark is laid out in (angle, r) and bent (§5.2).
  @polar %{
    angle: :angle,
    x: :angle,
    x0: :angle,
    x1: :angle,
    start: :angle,
    end: :angle,
    value: :r,
    inner: :r,
    outer: :r,
    y: :r,
    y0: :r,
    y1: :r,
    median: :r,
    inner_lo: :r,
    inner_hi: :r,
    outer_lo: :r,
    outer_hi: :r,
    series: :color
  }
  @geo %{value: :color, series: :color}

  # The mark types whose `value` is a size or a share and names no scale (spec/14 §5.2).
  @unscaled_value [:symbol, :circle, :arc]

  @doc false
  # Every scale of the frame node realised: `%{name => struct}`.
  @spec realise(
          map(),
          map(),
          [map()],
          atom(),
          map(),
          Theme.t(),
          map(),
          %{atom() => map()},
          map(),
          map()
        ) ::
          %{atom() => struct()}
  def realise(design, frame, marks, kind, plot, theme, sources, styles, ctx, given \\ %{}) do
    axes = Map.get(frame, :axes, [])
    # A scale adopted from another frame is that frame's node, read here (spec/14 §4.3,
    # #384): the node is said once and its domain is shared, while the range below is
    # this frame's own, since a range is pixels and each frame has its own plot.
    nodes =
      Map.new(Map.get(frame, :scales, %{}), fn {name, node} -> {name, node(node, design)} end)

    # Only a scale that infers its domain reads a column (spec/14 §4.3, #409), and a
    # domain the caller gives stands in for the inference.
    inferring =
      for {name, node} <- nodes,
          not Map.has_key?(given, name),
          infers?(Map.get(node, :domain, Schema.default(:scale, :domain))),
          into: MapSet.new(),
          do: name

    columns = columns(marks, kind, sources, styles, ctx, inferring)

    scales =
      Map.new(nodes, fn {name, node} ->
        node = if extent = Map.get(given, name), do: Map.put(node, :domain, extent), else: node
        {name, build(name, node, Map.get(columns, name, []), plot, theme, axes)}
      end)

    # An offset scale's :auto range is the bandwidth of the scale its family maps to,
    # so it is built again once the outer one exists (spec/14 §4.3, D-109).
    Enum.reduce(offsets(design, kind), scales, fn {name, outer}, scales ->
      with %{} = node <- Map.get(nodes, name),
           :auto <- get(node, :range),
           %Band{} = outer <- Map.get(scales, outer) do
        range = [0, Band.bandwidth(outer)]

        Map.put(
          scales,
          name,
          build(name, Map.put(node, :range, range), Map.get(columns, name, []), plot, theme, axes)
        )
      else
        _ -> scales
      end
    end)
  end

  @doc false
  # The node a scale entry stands for: its own, or the one at the end of its chain of
  # adoptions (spec/14 §4.3). The validator refuses a chain that does not end at a node,
  # so one that reaches nothing here is a chart built past it.
  @spec node(map() | tuple(), map()) :: map()
  def node({:frame, frame, scale} = adoption, design) do
    case design |> Map.get(:frames, %{}) |> Map.get(frame, %{}) |> nested_scales() do
      %{^scale => next} ->
        node(next, design)

      _absent ->
        raise ArgumentError,
              "#{inspect(adoption)} adopts a scale no frame declares (spec/14 §4.3)"
    end
  end

  def node(node, _design) when is_map(node), do: node

  defp nested_scales(frame) when is_map(frame), do: Map.get(frame, :scales, %{})
  defp nested_scales(_frame), do: %{}

  @doc false
  # Every adoption group of a design (spec/14 §4.3, #384): the declared scale a chain
  # ends at, and every `{frame, name}` that reads it — the owner's own entry included.
  # Only a group whose node infers its domain is here: a fixed domain is already shared
  # by every frame that adopts the node, there being one node.
  @spec adoptions(map()) :: %{{atom(), atom()} => [{atom(), atom()}]}
  def adoptions(design) do
    frames = Map.get(design, :frames, %{})

    groups =
      for {frame, node} <- frames,
          {name, entry} <- Map.get(node, :scales, %{}),
          match?({:frame, _f, _s}, entry),
          owner = owner(entry, frames),
          owner != nil,
          reduce: %{} do
        acc -> Map.update(acc, owner, [{frame, name}], &[{frame, name} | &1])
      end

    for {{frame, name} = owner, adopters} <- groups,
        node =
          get_in(frames, [Access.key(frame, %{}), Access.key(:scales, %{}), Access.key(name)]),
        is_map(node),
        infers?(Map.get(node, :domain, Schema.default(:scale, :domain))),
        into: %{},
        do: {owner, Enum.sort([owner | adopters])}
  end

  # The declared scale a chain of adoptions ends at, or `nil` for a chain that ends
  # nowhere — which the validator has already reported.
  defp owner({:frame, frame, name}, frames) do
    case frames |> Map.get(frame, %{}) |> nested_scales() |> Map.get(name) do
      {:frame, _f, _s} = next -> owner(next, frames)
      node when is_map(node) -> {frame, name}
      _absent -> nil
    end
  end

  @doc false
  # One domain over the realised scales of an adoption group (spec/14 §4.3): the extent
  # of a continuous scale's, and the categories of a discrete one's in order of first
  # appearance. A group whose scales disagree in shape keeps the first, which cannot
  # happen for scales built from one node.
  @spec unite([term()]) :: term()
  def unite([first | _] = domains) do
    if Enum.all?(domains, &extent?/1), do: extent(domains), else: categories(domains, first)
  end

  defp extent?([lo, hi]), do: comparable?(lo) and comparable?(hi)
  defp extent?(_domain), do: false

  defp comparable?(value) when is_number(value), do: true
  defp comparable?(%DateTime{}), do: true
  defp comparable?(%NaiveDateTime{}), do: true
  defp comparable?(%Date{}), do: true
  defp comparable?(_value), do: false

  defp extent(domains) do
    [
      domains |> Enum.map(&Enum.at(&1, 0)) |> Enum.reduce(&lower/2),
      domains |> Enum.map(&Enum.at(&1, 1)) |> Enum.reduce(&higher/2)
    ]
  end

  defp lower(a, b), do: if(before?(a, b), do: a, else: b)
  defp higher(a, b), do: if(before?(a, b), do: b, else: a)

  defp before?(%module{} = a, %module{} = b) when module in [DateTime, NaiveDateTime, Date],
    do: module.compare(a, b) == :lt

  defp before?(a, b), do: a < b

  defp categories(domains, first) when is_list(first) do
    domains |> Enum.filter(&is_list/1) |> Enum.concat() |> Enum.uniq()
  end

  defp categories(_domains, first), do: first

  # The offset scales the marks name, each with the scale its family maps to: `{name, outer}`.
  defp offsets(design, kind) do
    for mark <- design.marks,
        {family, _field} <- Map.get(mark, :offset, %{}),
        name = offset_scale(mark, family),
        outer = scale_for(kind, mark, family),
        outer != nil,
        uniq: true,
        do: {name, outer}
  end

  @doc false
  # The offset scale of a family for a mark: `x_offset`/`y_offset`, renamed by the mark's
  # `scales` node (spec/14 §5.1).
  @spec offset_scale(map(), :x | :y) :: atom()
  def offset_scale(mark, family) do
    name = :"#{family}_offset"
    Map.get(Map.get(mark, :scales, %{}), name, name)
  end

  @doc false
  # The channel-to-scale table of a frame kind.
  @spec channel_scales(atom()) :: %{atom() => atom()}
  def channel_scales(:polar), do: @polar
  def channel_scales(:geo), do: @geo
  def channel_scales(_cartesian_or_facet), do: @cartesian

  @doc false
  # The scale a channel of a mark names in a frame kind — the kind's table, renamed by
  # the mark's `scales` node — or `nil` when it names none (spec/14 §4.3, §5.1, §5.2).
  @spec scale_for(atom(), map(), atom()) :: atom() | nil
  def scale_for(_kind, %{type: type}, :value) when type in @unscaled_value, do: nil

  # A rect's `value` reaches the colour scale in every frame (spec/14 §4.3): in a polar
  # frame `value` is the rose's radius, not the rect's.
  def scale_for(:polar, %{type: :rect} = mark, :value), do: colour_scale(mark)

  def scale_for(kind, mark, channel) do
    case Map.get(channel_scales(kind), channel) do
      nil -> nil
      name -> Map.get(Map.get(mark, :scales, %{}), name, name)
    end
  end

  @doc false
  # A mark's colour scale: `color`, or what its `scales` node renames `color` to — the one
  # scale its series' paint, its style's colour bindings and its labels read (spec/14
  # §4.3, D-143).
  @spec colour_scale(map()) :: atom()
  def colour_scale(mark) do
    case Map.get(mark, :scales, %{}) do
      %{color: name} when is_atom(name) and name not in [nil, true, false] -> name
      _none -> :color
    end
  end

  @doc false
  # The rows a mark draws: its source's rows through its transforms with the plot area
  # and the projection as the pipeline's context (spec/14 §5.4), `[]` when the source is
  # not bound; only map rows carry names a channel can read.
  @spec mark_rows(map(), map(), map()) :: [map()]
  # A mark without `data` — a `:tiles` mark (spec/14 §5.2) — draws no rows.
  def mark_rows(mark, _sources, _ctx) when not is_map_key(mark, :data), do: []

  def mark_rows(mark, sources, ctx) do
    case Map.fetch(sources, source_name(mark.data)) do
      {:ok, source} ->
        rows = source |> Table.rows() |> Enum.filter(&is_map/1)

        Transform.apply(transforms(mark.data), rows,
          size: ctx.size,
          centre: ctx.centre,
          projection: ctx.projection,
          sources: sources,
          now: Map.get(ctx, :now),
          forces: Map.get(ctx, :forces, %{})
        )

      :error ->
        []
    end
  end

  defp source_name(%Var{name: name}), do: Style.unresolved!(name)
  defp source_name(name) when is_atom(name), do: name
  defp source_name(%{source: name}), do: name

  defp transforms(%{transforms: steps}) when is_list(steps), do: steps
  defp transforms(_data), do: []

  # -- the bound columns per scale --------------------------------------------------

  # Only the frame's *own* marks infer its scales (spec/14 §5.1, #383).
  defp columns(marks, kind, sources, styles, ctx, inferring) do
    if Enum.empty?(inferring) do
      %{}
    else
      marks
      |> Enum.flat_map(fn mark -> mark_columns(mark, kind, sources, styles, ctx, inferring) end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {scale, columns} -> {scale, List.flatten(columns)} end)
    end
  end

  # Whether a domain is inferred: `:auto`, or an extent with `:auto` at an end.
  defp infers?(:auto), do: true
  defp infers?([lo, hi]), do: lo == :auto or hi == :auto
  defp infers?(_extent), do: false

  defp mark_columns(mark, kind, sources, styles, ctx, inferring) do
    rows = mark_rows(mark, sources, ctx)

    channels =
      for {channel, value} <- Map.get(mark, :channels, %{}),
          scale = scale_for(kind, mark, channel),
          scale in inferring,
          do: {scale, values(value, rows)}

    colour = colour_scale(mark)

    colours =
      for key <- [:fill, :stroke],
          colour in inferring,
          {:field, field} <- [Map.get(Style.node(styles, Map.get(mark, :style)), key)],
          do: {colour, column(rows, field)}

    # An offset field's values are its offset scale's domain (spec/14 §4.3).
    offsets =
      for {family, field} <- Map.get(mark, :offset, %{}),
          offset_scale(mark, family) in inferring,
          do: {offset_scale(mark, family), column(rows, field)}

    channels ++ colours ++ offsets
  end

  defp values(%Var{name: name}, _rows), do: Style.unresolved!(name)
  # A constant contributes its number once the mark has a row to draw it on; with none it
  # contributes nothing, so an empty source leaves the unit domain (spec/14 §4.3).
  defp values(_n, []), do: []
  defp values(n, _rows) when is_number(n), do: [n]
  defp values({:field, field}, rows), do: column(rows, field)

  # A channel naming its scale's own end contributes nothing to that scale's domain
  # (spec/14 §5.2, #420): it is read *from* the domain, so it cannot be an input to it.
  defp values({:scale, _end}, _rows), do: []

  defp values(field, rows) when is_atom(field), do: column(rows, field)

  defp column(rows, field), do: rows |> Enum.map(&Table.get(&1, field)) |> Enum.reject(&is_nil/1)

  # -- one scale ------------------------------------------------------------------------

  defp build(name, node, values, plot, theme, axes) do
    kind = get(node, :kind)
    domain = domain(kind, name, get(node, :domain), values)
    worth = worth(get(node, :polarity))

    {domain, range} =
      case get(node, :range) do
        {:ramp, ramp} ->
          {domain, over_ramp(kind, name, ramp, domain, theme, worth)}

        %{} = colours when not is_struct(colours) ->
          pinned(kind, name, colours, domain)

        given ->
          {domain,
           range(kind, name, sweep(name, node, given), plot, theme, axes, worth)
           |> ring(kind, name, domain)}
      end

    kind
    |> construct(unknown(kind, name, node), range)
    |> with_domain(kind, domain)
    |> with_range(kind, range)
    |> flag(:nice, get(node, :nice))
    |> flag(:clamp, get(node, :clamp))
  end

  defp get(node, key), do: Map.get(node, key, Schema.default(:scale, key))

  # The colour scale draws a value outside its domain in a visible neutral, the theme's
  # `:axis` slot, unless the node says otherwise (spec/14 §4.3, D-122): a colour that
  # vanished would hide the mismatch, and the backends disagree about a missing fill.
  defp unknown(:ordinal, :color, node), do: neutral_unknown(node)

  # A map of colours is a colour scale whatever its name (§4.3, D-143).
  defp unknown(:ordinal, _name, %{range: %{} = colours} = node) when not is_struct(colours),
    do: neutral_unknown(node)

  defp unknown(_kind, _name, node), do: node

  defp neutral_unknown(node) do
    if get(node, :unknown) == nil, do: Map.put(node, :unknown, :axis), else: node
  end

  # A range given as a map of colours pins each category by name (spec/14 §4.3, D-143): the
  # domain keeps the members the map names, each mapped to its colour, so any other value is
  # outside it and draws `unknown`. It is an ordinal scale's; a scale of any other kind has
  # no categories to pin.
  defp pinned(:ordinal, _name, colours, domain) do
    members = Enum.filter(domain, &Map.has_key?(colours, &1))
    {members, Enum.map(members, &Map.fetch!(colours, &1))}
  end

  defp pinned(kind, name, _colours, _domain) do
    raise ArgumentError,
          "scale #{inspect(name)} (#{kind}) cannot range over a map of colours: a map pins " <>
            "categories, which an :ordinal scale has; list the colours instead"
  end

  # Where a ramp position is read, by polarity (spec/14 §4.3, D-143): as it is when lower is
  # better or nothing is said, reversed when higher is, folded about the middle when either
  # way from it is worse.
  defp worth(:higher_is_better), do: fn t -> 1 - t end
  defp worth(:neutral), do: fn t -> abs(2 * t - 1) end
  defp worth(_lower_or_nil), do: fn t -> t end

  # An `angle` scale with a start or a sweep has its range said in degrees (§4.3, #390);
  # a list range wins, and any other scale's start and sweep say nothing.
  defp sweep(:angle, node, :auto) do
    start = get(node, :start)
    sweep = get(node, :sweep)

    if start == 0 and sweep == 360,
      do: :auto,
      else: [start * :math.pi() / 180, (start + sweep) * :math.pi() / 180]
  end

  defp sweep(_name, _node, range), do: range

  # A categorical angle (spec/14 §4.3, #393): the range widened by half a step at each
  # end so the band centres span the sweep — on a full turn the step is `sweep / n` and
  # the ring closes with the last category one step before the first; on a partial
  # sweep `sweep / (n − 1)`, the categories ends-inclusive.
  defp ring([a0, a1], :band, :angle, domain) when is_list(domain) and domain != [] do
    n = length(domain)
    sweep = a1 - a0

    if abs(sweep) >= 2 * :math.pi() - 1.0e-9 do
      step = sweep / n
      [a0 - step / 2, a1 - step / 2]
    else
      step = sweep / max(1, n - 1)
      [a0 - step / 2, a1 + step / 2]
    end
  end

  defp ring(range, _kind, _name, _domain), do: range

  defp construct(:linear, _node, _range), do: Scale.linear()
  defp construct(:log, node, _range), do: Scale.log(get(node, :base))
  defp construct(:power, node, _range), do: Power.exponent(Scale.power(), get(node, :exponent))
  defp construct(:sqrt, _node, _range), do: Scale.sqrt()
  defp construct(:symlog, node, _range), do: Symlog.constant(Scale.symlog(), get(node, :constant))
  defp construct(:time, node, _range), do: Scale.zone(Scale.time(), get(node, :zone))
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
  # colour, the plot area has nothing to offer it, and the theme's ramp of that meaning is
  # the colour that promises "more" or "either side of the middle" (spec/14 §4.3, D-135).
  defp range(kind, name, :auto, _plot, theme, _axes, worth) when kind in @colour,
    do: over_ramp(kind, name, kind, [], theme, worth)

  defp range(kind, name, range, plot, theme, axes, _worth),
    do: range(kind, name, range, plot, theme, axes)

  defp range(_kind, :x, :auto, plot, _theme, _axes), do: [0, plot.width]
  defp range(_kind, :y, :auto, plot, _theme, _axes), do: [plot.height, 0]
  # The angle scale's range is its sweep from its start, degrees to radians (§4.3, #390).
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

  defp range(_kind, name, [], _plot, _theme, _axes) do
    raise ArgumentError, "scale #{inspect(name)}: an empty range has no value to map to"
  end

  defp range(_kind, _name, list, _plot, _theme, _axes) when is_list(list), do: list

  # A range over one of the theme's ramps (spec/14 §4.3, #533). A colour scale interpolates
  # it, Lab-interpolated by the theme; an ordinal scale spreads its domain end to end and a
  # threshold scale its buckets, each to a ramp position the theme resolves in the render
  # target's mode like any slot. A scale whose range length is its bucket count has no count
  # to take from a ramp, and a position scale has no use for a colour.
  defp over_ramp(kind, name, ramp, _domain, theme, worth) when kind in @colour do
    known_ramp!(name, ramp)
    fn t -> Theme.ramp(theme, ramp, worth.(t)) end
  end

  defp over_ramp(:ordinal, name, ramp, domain, _theme, worth),
    do: name |> spread(ramp, length(domain)) |> Enum.map(&placed(&1, worth))

  defp over_ramp(:threshold, name, ramp, domain, _theme, worth),
    do: name |> spread(ramp, length(domain) + 1) |> Enum.map(&placed(&1, worth))

  defp over_ramp(kind, name, ramp, _domain, _theme, _worth) do
    raise ArgumentError,
          "scale #{inspect(name)} (#{kind}) cannot range over {:ramp, #{inspect(ramp)}}: a ramp " <>
            "is a colour scale's range, on an :ordinal, :threshold, :sequential or :diverging " <>
            "scale; list the colours instead"
  end

  defp placed({:ramp, ramp, t}, worth), do: {:ramp, ramp, worth.(t)}

  defp spread(name, ramp, n) do
    known_ramp!(name, ramp)

    case n do
      n when n <= 1 -> [{:ramp, ramp, 0}]
      n -> Enum.map(0..(n - 1)//1, &{:ramp, ramp, &1 / (n - 1)})
    end
  end

  defp known_ramp!(name, ramp) do
    ramp in Theme.ramp_names() ||
      raise ArgumentError,
            "scale #{inspect(name)}: #{inspect(ramp)} is not a ramp of the theme; the ramps are " <>
              inspect(Theme.ramp_names())
  end
end
