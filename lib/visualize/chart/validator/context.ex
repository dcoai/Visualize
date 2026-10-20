defmodule Visualize.Chart.Validator.Context do
  @moduledoc false

  import Visualize.Chart.Names, only: [is_name: 1]
  # The context a validator walk runs in (spec/14 §10): what the design declares — frames,
  # scales, styles, paints, sources and their fields, variables, theme slots and colors — and
  # how a node narrows it as the walk enters it.

  alias Visualize.Chart.{Schema, Var}
  alias Visualize.Chart.Validator
  alias Visualize.Chart.Validator.{Palette, Types}
  alias Visualize.Theme

  @not_names [nil, true, false]

  @doc false
  # The context of a design's walk: what it declares, its theme's slots and colors, and the
  # node-local keys `enter/3` narrows.
  @spec context(map()) :: map()
  def context(map) do
    frames = if is_map(map[:frames]), do: map[:frames], else: %{}
    one = if map_size(frames) == 1, do: frames |> Map.values() |> hd()
    theme = known_theme(Map.get(map, :theme, Schema.default(:design, :theme)))

    %{
      # A scale name resolves inside a mark's *own* frame (spec/14 §5.1, #383): the
      # design-level context is the single frame's where there is one, and `enter(:mark)`
      # narrows it to the frame the mark names where there are several.
      layout: if(is_map(map[:layout]), do: map[:layout], else: nil),
      frames: declared(map[:frames]),
      frame_nodes: frames,
      scales: declared(one && nested(one, [:scales])),
      frame_kind: one && nested(one, [:kind]),
      frame_node: one,
      # A style reference reaches the design's styles, then the theme's palette (spec/14
      # §3.3, #637): a theme the validator cannot see says how many style series it has.
      styles: union(declared(map[:styles]), Palette.names(theme)),
      # The design's styles themselves, for the bindings a reference reaches (D-196).
      style_nodes: if(is_map(map[:styles]), do: map[:styles], else: %{}),
      open_series: theme == :unknown,
      paints: declared(map[:defs] || %{}),
      sources: source_fields(map[:sources]),
      vars: declared(map[:vars]),
      slots: theme_slots(theme),
      colors: theme_colors(theme),
      mark_type: nil,
      choice?: false,
      legend_values?: false,
      op: nil,
      transform_keys: [],
      fields: :unknown,
      datum?: false,
      channel_keys: [],
      partial?: false,
      # The registry generator names are checked against (spec/14 §3.13): a design's is
      # given, a fragment's is not known, and where no generator goes it is `:refused`.
      generators: :unknown
    }
  end

  @doc false
  # The value under `keys` of nested maps, `nil` where one of them is not a map.
  @spec nested(term(), [atom()]) :: term()
  def nested(map, []), do: map
  def nested(map, [k | rest]) when is_map(map) and not is_struct(map), do: nested(map[k], rest)
  def nested(_, _), do: nil

  # What a design declares under a key: the names of the map, the empty set when the key is
  # absent (D-113) — a reference into it is then undeclared, never unchecked — and unknown
  # only for a value that is not a map, which is a type fault of its own.
  defp declared(map) when is_map(map) and not is_struct(map) do
    map |> Map.keys() |> Enum.filter(&Types.name?/1) |> MapSet.new()
  end

  defp declared(nil), do: MapSet.new()
  defp declared(_), do: :unknown

  defp union(:unknown, _), do: :unknown
  defp union(set, more), do: MapSet.union(set, MapSet.new(more))

  defp source_fields(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn
      {name, %{fields: fields}} when is_list(fields) -> {name, fields}
      {name, _} -> {name, :unknown}
    end)
  end

  defp source_fields(nil), do: %{}
  defp source_fields(_), do: :unknown

  # The theme the validator can see: a built-in one, or an inline one that is whole and
  # valid — a variable in it is resolved at application, and an invalid one is already
  # reported on its keys. Its slots and its palette names are what references are checked
  # against (spec/14 §2.5, §3.2, §3.3); any other theme is `:unknown`.
  defp known_theme(name) when is_binary(name) or (is_atom(name) and name not in @not_names),
    do: Theme.builtin(name) || :unknown

  defp known_theme(map) when is_map(map) and not is_struct(map) do
    variable? = Enum.any?(map, fn {_, v} -> is_struct(v, Var) end)

    case Validator.node(:theme, map, [], %{open() | vars: :unknown}) do
      [] when not variable? -> Theme.new(map)
      _ -> :unknown
    end
  end

  defp known_theme(_), do: :unknown

  defp theme_slots(:unknown), do: :unknown
  defp theme_slots(theme), do: MapSet.new(Theme.slots(theme))

  defp theme_colors(:unknown), do: :unknown
  defp theme_colors(theme), do: MapSet.new(Theme.color_names(theme))

  @doc false
  # A fragment's context (spec/14 §19.8): nothing it refers to is known, and no key is
  # required of it.
  @spec open() :: map()
  def open do
    %{
      context(%{})
      | scales: :unknown,
        frame_kind: :unknown,
        styles: :unknown,
        paints: :unknown,
        sources: :unknown,
        vars: :unknown,
        slots: :unknown,
        colors: :unknown,
        partial?: true
    }
  end

  @doc false
  # The context a node of `kind` is walked in, narrowed from its parent's.
  @spec enter(atom(), map(), map()) :: map()
  def enter(:mark, map, ctx) do
    type = map[:type]

    ctx
    |> in_frame(map[:frame])
    |> Map.merge(%{
      mark_type: if(type in Schema.mark_types(), do: type),
      fields: mark_fields(map[:data], ctx),
      datum?: true
    })
  end

  def enter(:label, map, ctx), do: %{in_frame(ctx, map[:frame]) | datum?: false}

  # A `:choose` mark's child is read as a mark of its own type over the mark's data
  # (spec/14 §5.2, D-194).
  def enter(:choice, map, ctx) do
    type = map[:type]
    %{ctx | mark_type: if(type in Schema.mark_types(), do: type), choice?: true}
  end

  def enter(:legend, map, ctx), do: %{ctx | legend_values?: Map.has_key?(map, :values)}

  # A generator is a site's and its styles' (spec/14 §3.13): a theme and a defaults node are
  # laid without a frame to call it.
  def enter(kind, _map, ctx) when kind in [:theme, :defaults, :kind_defaults],
    do: %{ctx | generators: :refused}

  def enter(:channels, map, ctx), do: %{ctx | channel_keys: Map.keys(map)}

  def enter(:transform, map, ctx) do
    op = map[:op]
    %{ctx | op: if(op in Schema.transform_ops(), do: op), transform_keys: Map.keys(map)}
  end

  # Inside a frame, a scale name is that frame's (spec/14 §4.3, #383): its axes and its
  # legend read the scales it declares, whatever the design's other frames declare.
  def enter(:frame, map, ctx) do
    %{ctx | scales: declared(map[:scales]), frame_kind: map[:kind]}
  end

  def enter(:fit, map, ctx),
    do: %{ctx | transform_keys: Map.keys(map), fields: fields_of(map[:data], ctx)}

  def enter(_kind, _map, ctx), do: ctx

  # The scales and the kind a node's scale references resolve against: its own frame's
  # where it names one, the design-level context's otherwise (spec/14 §5.1, §6.1).
  defp in_frame(ctx, nil), do: ctx

  defp in_frame(%{frame_nodes: frames} = ctx, name) when is_map_key(frames, name) do
    node = Map.fetch!(frames, name)

    %{
      ctx
      | scales: declared(nested(node, [:scales])),
        frame_kind: nested(node, [:kind]),
        frame_node: node
    }
  end

  defp in_frame(ctx, _name), do: ctx

  defp mark_fields(name, ctx) when is_name(name), do: fields_of(name, ctx)

  defp mark_fields(%{source: name} = data, ctx) when is_map(data) do
    case Map.get(data, :transforms, []) do
      [] -> fields_of(name, ctx)
      _ -> :unknown
    end
  end

  defp mark_fields(_, _), do: :unknown

  defp fields_of(_, %{sources: :unknown}), do: :unknown
  defp fields_of(name, %{sources: sources}), do: Map.get(sources, name, :unknown)
end
