defmodule Visualize.Chart.Validator.Held do
  @moduledoc false
  # What a node's keys owe each other, beside each key's own type (spec/14 §10): a source's
  # names, a theme's contracts, a layout's weights, a frame's place, a scale's sweep, zone,
  # colour map and polarity, a basemap's provider, an axis's measure, a motion part's times.

  alias Visualize.Chart.{Fact, Schema, Urls, Var}
  alias Visualize.Chart.Validator.{Colors, Frames, Types}
  alias Visualize.Theme

  # The motion parts' node kinds, whose times and names Validator.Motion checks (spec/14 §3.10).
  @motion_kinds Visualize.Chart.Validator.Motion.kinds()

  @doc false
  # What a node's keys owe each other: a source's `types` and `requires` name only its
  # `fields` (§2.3, §7.4).
  @spec held(atom(), map(), list(), map()) :: [{list(), term()}]
  def held(:source, %{fields: fields} = source, path, _ctx) when is_list(fields) do
    for key <- [:types, :requires],
        names = Map.get(source, key),
        is_map(names) and not is_struct(names),
        {name, _value} <- names,
        Types.name?(name),
        name not in fields,
        do: {path ++ [key, name], {:undeclared, :field, name}}
  end

  # An inline theme's ramps, colors and palette entries hold their contracts (spec/08 §7.5,
  # §7.7, D-135, D-171): measured once the keys they are read with are well typed, so a
  # type fault is not reported twice, and only the first breach, as construction refuses
  # at the first.
  def held(:theme, map, path, _ctx) do
    with ramps when is_map(ramps) <- Map.get(map, :ramps, %{}),
         colors when is_map(colors) <- Map.get(map, :colors, %{}),
         styles when is_map(styles) and not is_struct(styles) <- Map.get(map, :styles, %{}),
         true <- Enum.all?(ramps, fn {_, v} -> is_list(v) and Enum.all?(v, &Colors.anchor?/1) end),
         true <-
           Enum.all?(colors, fn {_, v} ->
             is_binary(v) or is_map(v) or Visualize.Color.value?(v)
           end),
         true <- Enum.all?(styles, fn {_, v} -> is_map(v) and not is_struct(v) end),
         theme = Theme.build(Theme.default(), Colors.measured(map)),
         {:error, {kind, name}, message} <- Theme.check(theme) do
      [{path ++ [Types.plural(kind), name], {:contract, message}}]
    else
      _ -> []
    end
  end

  # A layout's weights are positive: a cell of no width is not a cell (spec/14 §2.8, #384).
  def held(:layout, map, path, _ctx) do
    for key <- [:columns, :rows],
        weights = Map.get(map, key),
        is_list(weights),
        not Enum.all?(weights, &(is_number(&1) and &1 > 0)),
        do: {path ++ [key], {:weight, key}}
  end

  # A sync group and the design's brush read a linear or a time x of a cartesian frame
  # (spec/14 §2.9, D-116, D-143): the hooks map a value by linear interpolation, which is
  # that scale and no other.
  def held(:interaction, map, path, ctx) do
    for {key, given?} <- [sync: is_binary(Map.get(map, :sync)), brush: Map.get(map, :brush) == :x],
        given?,
        fault <- Frames.linear_x(Map.get(map, :frame), ctx.frame_nodes),
        do: {path ++ [key], Tuple.insert_at(fault, 0, key)}
  end

  # A frame says where it goes once (spec/14 §4.2, §2.8, #384): its box, or its cell on
  # the design's grid, and a cell stays inside that grid.
  def held(:frame, %{box: _box, cell: _cell}, path, _ctx), do: [{path, :both}]

  def held(:frame, %{cell: cell} = frame, path, ctx) when is_list(cell) do
    if inside?(cell, Map.get(frame, :span), ctx.layout),
      do: [],
      else: [{path ++ [:cell], :outside}]
  end

  # A needle is a polar frame's mark (spec/14 §5.2, #392): elsewhere its type is invalid.
  def held(:mark, %{type: :needle}, path, %{frame_kind: kind})
      when kind not in [:polar, :unknown],
      do: [{path ++ [:type], {:invalid_for, :needle}}]

  # A basemap lies under a tile-aligned Mercator projection only (spec/14 §5.2, spec/07
  # §8.1), and its provider's node belongs to it alone.
  def held(:mark, %{type: :tiles}, path, ctx),
    do: Frames.tiles_frame(ctx.frame_node, path ++ [:type])

  def held(:mark, %{type: type, tiles: _}, path, _ctx) when is_atom(type),
    do: [{path ++ [:tiles], {:invalid_for, type}}]

  def held(:tiles, map, path, ctx) do
    attribution =
      case Map.get(map, :attribution) do
        text when is_binary(text) ->
          if String.trim(text) == "",
            do: [{path ++ [:attribution], {:tiles, :attribution}}],
            else: []

        _other ->
          []
      end

    url =
      case Map.get(map, :url) do
        url when is_binary(url) ->
          missing? = not Enum.all?(["{z}", "{x}", "{y}"], &String.contains?(url, &1))
          empty? = String.contains?(url, "{s}") and Map.get(map, :subdomains) == []

          if(missing?, do: [{path ++ [:url], {:tiles, :url}}], else: []) ++
            if(empty?, do: [{path ++ [:subdomains], {:tiles, :subdomains}}], else: [])

        _other ->
          []
      end

    attribution ++ url ++ policy(map, path, ctx)
  end

  def held(:scale, map, path, _ctx) do
    sweep(map, path) ++ zone(map, path) ++ colour_map(map, path) ++ polarity(map, path)
  end

  def held(:axis, %{radius: radius}, path, _ctx) when is_number(radius) and radius <= 0,
    do: [{path ++ [:radius], :radius}]

  # An axis's measure is a UCUM code Visualize.Unit reads and a quantity of its dimension
  # (spec/14 §4.4, §10.1, D-138). Only values of the right type are checked: a wrong type
  # or quantity is the type check's fault, and a variable is checked once it is bound.
  def held(:measure, measure, path, _ctx) do
    typed =
      Map.filter(measure, fn
        {:unit, unit} -> is_binary(unit)
        {:quantity, quantity} -> quantity in Visualize.Quantity.all()
        _other -> false
      end)

    case Visualize.Quantity.resolve(typed) do
      {:ok, _resolved} -> []
      {:error, {:unit, code, reason}} -> [{path ++ [:unit], {:unit, code, reason}}]
      {:error, {:quantity, _quantity, _code} = reason} -> [{path ++ [:quantity], reason}]
    end
  end

  def held(kind, map, path, _ctx) when kind in @motion_kinds,
    do: Visualize.Chart.Validator.Motion.check(map, path)

  # A color generator draws a solid paint: a gradient's colors are its stops, which the frame
  # holds in its `defs` before it draws (spec/14 §3.13).
  def held(kind, %{type: type, color: {:generate, _, _}}, path, _ctx)
      when kind in [:paint, :stroke] and type != :solid,
      do: [{path ++ [:color], {:invalid_for, type}}]

  def held(_kind, _map, _path, _ctx), do: []

  # The angle scale's sweep is a turn at most and never nothing; an axis's radius is
  # positive (spec/14 §4.3, §4.4, #390).
  defp sweep(%{sweep: sweep}, path) when is_number(sweep) and (sweep == 0 or abs(sweep) > 360),
    do: [{path ++ [:sweep], :sweep}]

  defp sweep(_scale, _path), do: []

  # A time scale's zone is one the host's time zone database can show (spec/14 §4.3, §10.1,
  # #447): a host without a database, or a name it does not know, is refused by name
  # rather than drawn in UTC (D-115).
  defp zone(%{kind: :time, zone: zone}, path) when is_binary(zone) do
    case Visualize.Scale.Time.check_zone(zone) do
      :ok -> []
      {:error, reason} -> [{path ++ [:zone], {:zone, zone, reason}}]
    end
  end

  defp zone(_scale, _path), do: []

  # A map of colours is an ordinal scale's range (spec/14 §4.3, D-143): it pins categories,
  # and a continuous scale has none.
  defp colour_map(%{kind: kind, range: %{} = range}, path)
       when is_atom(kind) and kind != :ordinal and not is_struct(range),
       do: [{path ++ [:range], {:colour_map, kind}}]

  defp colour_map(_scale, _path), do: []

  # Polarity orders a ramp (spec/14 §4.3, D-143) — a `{:ramp, name}` range, or the `:auto`
  # range of a sequential or a diverging scale, which is its theme ramp; a list or a map
  # already says each colour.
  defp polarity(%{polarity: polarity} = scale, path) when is_atom(polarity) and polarity != nil do
    case {Map.get(scale, :kind), Map.get(scale, :range, :auto)} do
      {_kind, {:ramp, _name}} -> []
      {kind, :auto} when kind in [:sequential, :diverging] -> []
      {_kind, %Var{}} -> []
      {_kind, %Fact{}} -> []
      _other -> [{path ++ [:polarity], {:polarity, :range}}]
    end
  end

  defp polarity(_scale, _path), do: []

  # Whether a cell, with its span, lies inside the grid the design declares. A design
  # with no `layout` has one cell, which is the default grid (spec/14 §2.8).
  defp inside?(cell, span, layout) do
    layout = layout || %{}
    columns = length(sizes(layout, :columns))
    rows = length(sizes(layout, :rows))

    with [c, r] when is_integer(c) and is_integer(r) <- cell,
         [dc, dr] <- span || [1, 1],
         true <- is_integer(dc) and is_integer(dr) and dc > 0 and dr > 0 do
      c >= 0 and r >= 0 and c + dc <= columns and r + dr <= rows
    else
      _other -> false
    end
  end

  defp sizes(layout, key) do
    case Map.get(layout, key, [1]) do
      weights when is_list(weights) and weights != [] -> weights
      _other -> [1]
    end
  end

  # The URL policy of §10.3 (#660): the fault names the field and the reason, never the URL.
  defp policy(%{url: url} = map, path, ctx) when is_binary(url) do
    subdomains = Map.get(map, :subdomains, Schema.default(:tiles, :subdomains))
    subdomains = if is_list(subdomains), do: Enum.filter(subdomains, &is_binary/1), else: []

    case Urls.check(url, Map.get(ctx, :urls) || Urls.policy(), subdomains) do
      :ok -> []
      {:error, reason} -> [{path ++ [:url], {:url, reason}}]
    end
  end

  defp policy(_map, _path, _ctx), do: []
end
