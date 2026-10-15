if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Scales do
    @moduledoc """
    The scales a design's bound channels need and the frame lacks (spec/14 §18.16, #370).

    A channel finds its scale by name and a scale the frame does not declare is the identity
    (§4.3) — right for a layout that emits pixels, a trap for a person binding a column. So
    whenever the builder binds a channel it asks `derive/2` for the scales to declare, each
    kind read from the column's type (§2.3, or what its rows suggest), and
    `unscaled/2` for the position channels it could not type, which are needs.

    Every function here is pure; the builder writes what `derive/2` returns.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    alias Visualize.Chart
    alias Visualize.Chart.Fragment
    alias Visualize.Chart.Frame.Scales, as: FrameScales
    alias Visualize.Data.Table

    @typedoc "The types the pool's rows suggest, by source name."
    @type pool_types :: %{atom() => %{atom() => atom()}}

    @position [:x, :y, :angle, :r]
    @sample 200

    @doc """
    The scales the design's bound channels name and the frame does not declare, as
    `%{name => node}`, each `%{kind: kind, domain: :auto}` with the kind from the channel's
    evidence: time → `:time`, number → `:linear`, a category or text → `:band` (the layer's
    one categorical position scale, spec/03); on the color scale a category → `:ordinal`,
    a number → `:sequential`. A channel with no evidence derives nothing; a scale already
    declared is never in the result.

        iex> design = %{frames: %{main: %{kind: :cartesian}},
        ...>   sources: %{s: %{fields: [:t, :v, :k], types: %{t: :time, v: :number, k: :category}}},
        ...>   marks: [%{type: :line, data: :s, channels: %{x: :t, y: :v}},
        ...>           %{type: :rect, data: :s, channels: %{x0: :k, x1: :k, y0: 0, y1: :v, value: :k}}]}
        iex> Visualize.Chart.Builder.Scales.derive(design, %{})
        %{x: %{kind: :time, domain: :auto}, y: %{kind: :linear, domain: :auto}, color: %{kind: :ordinal, domain: :auto}}
        iex> Visualize.Chart.Builder.Scales.derive(%{frames: %{main: %{kind: :cartesian}}}, %{})
        %{}
    """
    @spec derive(map(), pool_types()) :: %{atom() => map()}
    def derive(design, pool_types) when is_map(design),
      do: derive(design, pool_types, Fragment.frame_of(design, nil))

    @doc """
    `derive/2` for one frame of the design (#615): the scales the channels of the marks
    drawn in `frame` name and that frame does not declare. A design of several frames
    derives each frame's from its own marks, since a scale name belongs to its frame
    (§4.3).

        iex> design = %{frames: %{a: %{kind: :cartesian}, b: %{kind: :cartesian, scales: %{x: %{kind: :linear}}}},
        ...>   sources: %{s: %{fields: [:t, :v], types: %{t: :number, v: :number}}},
        ...>   marks: [%{type: :line, frame: :b, data: :s, channels: %{x: :t, y: :v}}]}
        iex> {Visualize.Chart.Builder.Scales.derive(design, %{}, :a), Visualize.Chart.Builder.Scales.derive(design, %{}, :b)}
        {%{}, %{y: %{kind: :linear, domain: :auto}}}
    """
    @spec derive(map(), pool_types(), atom()) :: %{atom() => map()}
    def derive(design, pool_types, frame) when is_map(design) do
      declared = declared(design, frame)

      design
      |> evidence(pool_types)
      |> Enum.filter(fn {in_frame, _name, _type, _path} -> in_frame == frame end)
      |> Enum.reject(fn {_frame, name, _type, _path} -> name in declared end)
      |> Enum.reduce(%{}, fn {_frame, name, type, _path}, acc ->
        case {Map.has_key?(acc, name), kind(name, type)} do
          {false, kind} when kind != nil -> Map.put(acc, name, %{kind: kind, domain: :auto})
          _other -> acc
        end
      end)
    end

    @doc """
    The position channels bound to a field that names a scale the frame lacks and no type
    could be read for: `{[:marks, i, :channels, ch], {:unscaled, field}}` each, the
    builder's needs (spec/14 §18.16).

        iex> design = %{frames: %{main: %{kind: :cartesian}}, sources: %{s: %{fields: [:t, :v]}},
        ...>   marks: [%{type: :line, data: :s, channels: %{x: :t, y: :v}}]}
        iex> Visualize.Chart.Builder.Scales.unscaled(design, %{})
        [{[:marks, 0, :channels, :x], {:unscaled, :t}}, {[:marks, 0, :channels, :y], {:unscaled, :v}}]
        iex> Visualize.Chart.Builder.Scales.unscaled(design, %{s: %{t: :number, v: :number}})
        []
    """
    @spec unscaled(map(), pool_types()) :: [{[term()], {:unscaled, atom()}}]
    def unscaled(design, pool_types) when is_map(design) do
      for {frame, name, nil, {path, field}} <- evidence(design, pool_types),
          name in @position,
          name not in declared(design, frame),
          is_atom(field),
          do: {path, {:unscaled, field}}
    end

    @doc """
    The types the pool's rows suggest, by source, over each source's first #{@sample} rows
    (`Visualize.Data.Table.column_types/1`); a source with no rows suggests nothing.

        iex> Visualize.Chart.Builder.Scales.pool_types(%{s: [%{t: 1, k: "a"}], e: []})
        %{s: %{t: :number, k: :text}, e: %{}}
    """
    @spec pool_types(map()) :: pool_types()
    def pool_types(pool) when is_map(pool) do
      Map.new(pool, fn {name, source} ->
        {name, source |> Table.rows() |> Enum.take(@sample) |> Table.column_types()}
      end)
    end

    @doc """
    For every mark that binds a source, the columns a channel may pick (spec/14 §18.6,
    #371): the source's declared `fields` and the pool's columns for it, sorted, each with
    its type — the design's, else the rows' — keyed by the channels node's path.

        iex> design = %{sources: %{s: %{fields: [:t, :v], types: %{t: :time}}},
        ...>   marks: [%{type: :line, data: :s}, %{type: :line}]}
        iex> Visualize.Chart.Builder.Scales.columns(design, %{s: [%{t: 1, v: 2, extra: "x"}]})
        %{[:marks, 0, :channels] => [%{name: :extra, type: :text}, %{name: :t, type: :time}, %{name: :v, type: :number}]}
    """
    @spec columns(map(), map()) :: %{[term()] => [%{name: atom(), type: atom() | nil}]}
    def columns(design, pool) when is_map(design) and is_map(pool) do
      pool_types = pool_types(pool)

      for {mark, i} <- Enum.with_index(List.wrap(Map.get(design, :marks, []))),
          is_map(mark),
          source = source_of(mark),
          source != nil,
          into: %{} do
        declared =
          case get_in(design, [:sources, source, :fields]) do
            fields when is_list(fields) -> Enum.filter(fields, &is_atom/1)
            _none -> []
          end

        names = Enum.uniq(declared ++ Map.keys(Map.get(pool_types, source, %{}))) |> Enum.sort()

        {[:marks, i, :channels],
         Enum.map(names, &%{name: &1, type: column_type(design, pool_types, source, &1)})}
      end
    end

    @doc """
    The position scales a mark reads — `x`, `y`, `angle`, `r` — through its channels and
    its `scales` renames, in channel order (spec/14 §18.16, #373).

        iex> design = %{frames: %{main: %{kind: :cartesian}}}
        iex> Visualize.Chart.Builder.Scales.position_scales(design, %{type: :line, channels: %{y: :v, x: :t, series: :k}})
        [:x, :y]
        iex> Visualize.Chart.Builder.Scales.position_scales(%{frames: %{main: %{kind: :polar}}}, %{type: :rose, channels: %{angle: :k, value: :v}})
        [:angle, :r]
    """
    @spec position_scales(map(), map()) :: [atom()]
    def position_scales(design, mark) when is_map(mark) do
      kind = frame_kind(design, Fragment.frame_of(design, mark))

      for {channel, _value} <- mark |> Map.get(:channels, %{}) |> Enum.sort(),
          scale = FrameScales.scale_for(kind, mark, channel),
          scale in @position,
          uniq: true,
          do: scale
    end

    @doc "The type the design declares for a source's field, else the type its rows suggest."
    @spec column_type(map(), pool_types(), atom(), atom()) :: atom() | nil
    def column_type(design, pool_types, source, field) do
      Chart.column_type(design, source, field) || get_in(pool_types, [source, field])
    end

    # Every channel of every mark that names a scale: `{frame, scale, type or nil, {path,
    # value}}`, the frame the mark is drawn in, in mark and channel order.
    defp evidence(design, pool_types) do
      marks = List.wrap(Map.get(design, :marks, []))

      for {mark, i} <- Enum.with_index(marks),
          is_map(mark),
          frame = Fragment.frame_of(design, mark),
          kind = frame_kind(design, frame),
          {channel, value} <- Map.get(mark, :channels, %{}) |> Enum.sort(),
          scale = FrameScales.scale_for(kind, mark, channel),
          scale != nil do
        type = value_type(design, pool_types, source_of(mark), value)
        {frame, scale, type, {[:marks, i, :channels, channel], value}}
      end
    end

    defp frame_kind(design, frame), do: get_in(design, [:frames, frame, :kind]) || :cartesian

    defp source_of(%{data: name}) when is_atom(name), do: name
    defp source_of(%{data: %{source: name}}) when is_atom(name), do: name
    defp source_of(_mark), do: nil

    defp value_type(_design, _pool, _source, n) when is_number(n), do: :number
    defp value_type(_design, _pool, nil, _value), do: nil

    defp value_type(design, pool_types, source, field) when is_atom(field) and field != nil,
      do: column_type(design, pool_types, source, field)

    defp value_type(_design, _pool, _source, _other), do: nil

    defp kind(:color, type) when type in [:category, :text], do: :ordinal
    defp kind(:color, :number), do: :sequential
    defp kind(:color, _type), do: nil
    defp kind(_name, :time), do: :time
    defp kind(_name, :number), do: :linear
    defp kind(_name, type) when type in [:category, :text], do: :band
    defp kind(_name, _type), do: nil

    defp declared(design, frame) do
      case get_in(design, [:frames, frame, :scales]) do
        scales when is_map(scales) -> Map.keys(scales)
        _none -> []
      end
    end
  end
end
