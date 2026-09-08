defmodule Visualize.ChartGen do
  @moduledoc """
  StreamData generators for valid designs (spec/14): every node kind, every value type,
  every reference kind resolving against the design that carries it. Shared by the map
  and JSON round-trip properties.
  """

  import ExUnitProperties, only: [gen: 2]
  import StreamData

  alias Visualize.Chart.{Schema, Var}
  alias Visualize.Theme

  @names [:a, :b, :c]
  @fields [:t, :v, :w, :z, :count, :sha, :x0, :x1, :y0, :y1]
  @scale_names [:x, :y, :color, :angle, :r]
  @colours ["#3b6fa8", "#d9730d", "steelblue", "rgb(1, 2, 3)"]
  @fonts ["Inter, sans-serif", "monospace"]
  @sides [:top, :right, :bottom, :left]
  @positions [:top_left, :top_right, :bottom_left, :bottom_right, :top, :bottom, :left, :right]
  @mark_anchors [:top, :bottom, :left, :right, :start, :middle, :end]
  @orders [:none, :ascending, :descending, :inside_out, :reverse, :appearance]
  @offsets [:none, :expand, :silhouette, :wiggle, :diverging]

  @doc "A valid design map."
  def design do
    gen all(
          theme <- theme(),
          sources <- sources(),
          vars <- vars(),
          styles <- styles(theme, vars),
          frame <- frame(vars),
          marks <- marks(sources, vars, styles, frame),
          labels <- labels(vars, styles, frame),
          meta <- meta(vars)
        ) do
      %{
        version: 1,
        meta: meta,
        sources: sources,
        vars: vars,
        theme: theme,
        styles: styles,
        frame: frame,
        marks: marks,
        labels: labels
      }
    end
  end

  # -- leaves ---------------------------------------------------------------------------

  defp number, do: one_of([integer(-1000..1000), float(min: -1000.0, max: 1000.0)])

  defp text_string, do: string(:alphanumeric, min_length: 1, max_length: 8)

  defp category_string, do: filter(text_string(), &(&1 != "auto"))

  defp datetime, do: map(integer(0..2_000_000_000), &DateTime.from_unix!/1)

  defp json_term do
    one_of([
      integer(),
      float(),
      text_string(),
      boolean(),
      constant(nil),
      member_of([:series_1, :foo, :x]),
      datetime(),
      list_of(integer(), max_length: 3),
      optional_map(%{a: integer(), b: integer()})
    ])
  end

  defp field_ref(fields), do: map(member_of(fields), &{:field, &1})

  # A value generator, plus a declared variable when the design has any.
  defp with_var(gens, vars) when map_size(vars) == 0, do: one_of(gens)

  defp with_var(gens, vars) do
    one_of([map(member_of(Map.keys(vars)), &%Var{name: &1}) | gens])
  end

  defp text(vars, fields) do
    parts = [text_string()] ++ if(fields, do: [field_ref(fields)], else: [])
    list_of(with_var(parts, vars), max_length: 3)
  end

  # A node: its required keys, then a random subset of its optional keys.
  defp node(required, optional) do
    bind(fixed_map(required), fn r -> map(optional_map(optional), &Map.merge(r, &1)) end)
  end

  # -- theme, sources, vars, styles ---------------------------------------------------

  defp theme do
    one_of([constant(:default), constant(:dark), constant(Map.from_struct(Theme.dark()))])
  end

  defp theme_struct(:default), do: Theme.default()
  defp theme_struct(:dark), do: Theme.dark()
  defp theme_struct(map), do: Theme.new(map)

  defp slot(theme) do
    one_of([
      member_of(Theme.slots(theme_struct(theme))),
      map(integer(1..12), &{:series, &1})
    ])
  end

  defp sources do
    source =
      node(%{fields: uniq_list_of(member_of(@fields), min_length: 1, max_length: 4)}, %{
        default: member_of(@names)
      })

    filter(optional_map(Map.new(@names, &{&1, source})), &(&1 != %{}))
  end

  defp vars do
    declaration = optional_map(%{default: json_term()})
    optional_map(%{unit: declaration, accent: declaration, n: declaration})
  end

  defp styles(theme, vars) do
    style = style(theme, vars)
    optional_map(%{series: style, muted: style, axis: style})
  end

  defp style(theme, vars) do
    colour =
      with_var([member_of(@colours), constant(:none), slot(theme), field_ref(@fields)], vars)

    size = with_var([number(), slot(theme), field_ref(@fields)], vars)
    font = with_var([member_of(@fonts), slot(theme)], vars)

    optional_map(%{
      fill: colour,
      stroke: colour,
      stroke_width: size,
      stroke_dasharray: one_of([text_string(), list_of(number(), max_length: 3)]),
      stroke_linecap: member_of([:butt, :round, :square]),
      stroke_linejoin: member_of([:miter, :round, :bevel]),
      opacity: size,
      fill_opacity: size,
      stroke_opacity: size,
      font_family: font,
      font_size: size,
      font_weight: one_of([integer(100..900), member_of([:normal, :bold])]),
      text_anchor: member_of([:start, :middle, :end]),
      class: text_string(),
      curve: member_of(Schema.curve_types()),
      curve_opts: optional_map(%{tension: number(), alpha: number()}),
      symbol: member_of(Schema.symbol_types()),
      symbol_size: size
    })
  end

  defp style_ref(styles), do: member_of(Map.keys(styles) ++ Schema.builtin_styles())

  # -- frame ----------------------------------------------------------------------------

  defp frame(vars) do
    gen all(
          kind <- member_of([:cartesian, :polar, :geo, :facet]),
          size <- fixed_map(%{width: integer(100..1000), height: integer(100..1000)}),
          base <- optional_map(%{margin: margin(), projection: projection(), facet: facet()}),
          scales <- optional_map(Map.new(@scale_names, &{&1, scale()})),
          furniture <- furniture(Map.keys(scales), vars)
        ) do
      Map.merge(%{kind: kind, size: size, scales: scales}, Map.merge(base, furniture))
    end
  end

  defp furniture([], _vars), do: constant(%{})

  defp furniture(scales, vars) do
    optional_map(%{
      axes: list_of(axis(scales), max_length: 2),
      legend:
        node(%{scale: member_of(scales)}, %{
          position: member_of(@positions),
          title: text(vars, nil),
          style: member_of(Schema.builtin_styles())
        }),
      viewport: fixed_map(%{scale: member_of(scales), span: number()})
    })
  end

  defp margin, do: optional_map(Map.new(@sides, &{&1, number()}))

  defp extent do
    bound = one_of([number(), constant(:auto), datetime()])
    category = one_of([number(), category_string(), member_of([:a, :b])])

    one_of([
      constant(:auto),
      map(tuple({bound, bound}), &Tuple.to_list/1),
      list_of(category, min_length: 1, max_length: 4)
    ])
  end

  defp scale do
    node(%{kind: member_of(Schema.scale_kinds())}, %{
      domain: extent(),
      range: one_of([extent(), member_of([:category10, :viridis])]),
      nice: boolean(),
      clamp: boolean(),
      base: number(),
      exponent: number(),
      constant: number(),
      padding: number(),
      padding_inner: number(),
      padding_outer: number(),
      align: number(),
      round: boolean(),
      unknown: json_term()
    })
  end

  defp axis(scales) do
    ticks =
      optional_map(%{
        count: integer(1..10),
        values: list_of(json_term(), max_length: 3),
        size_inner: number(),
        size_outer: number(),
        padding: number()
      })

    node(%{scale: member_of(scales), side: member_of(@sides)}, %{
      ticks: one_of([integer(1..10), list_of(json_term(), max_length: 3), ticks]),
      format: text_string(),
      grid: boolean(),
      offset: number(),
      style: member_of(Schema.builtin_styles())
    })
  end

  defp projection do
    node(%{type: member_of([:mercator, :orthographic])}, %{
      scale: number(),
      translate: list_of(number(), length: 2),
      center: list_of(number(), length: 2),
      rotate: list_of(number(), max_length: 3),
      parallels: list_of(number(), length: 2),
      clip_angle: number()
    })
  end

  defp facet, do: node(%{by: member_of(@fields)}, %{columns: integer(1..4)})

  # -- marks and labels ---------------------------------------------------------------

  defp marks(sources, vars, styles, _frame) do
    list_of(mark(sources, vars, styles), max_length: 3)
  end

  defp mark(sources, vars, styles) do
    gen all(
          type <- member_of(Schema.mark_types()),
          name <- member_of(Map.keys(sources)),
          data <- one_of([constant(name), data_node(name)]),
          fields = mark_fields(data, sources),
          channels <- channels(type, fields, vars),
          rest <-
            optional_map(%{
              options: with_var([options(type)], vars),
              style: style_ref(styles),
              label: mark_label(fields, vars, styles),
              render: member_of([:auto, :svg, :canvas, :binary])
            })
        ) do
      Map.merge(%{type: type, data: data, channels: channels}, rest)
    end
  end

  # Without a transform the channels read the source's declared fields; after one the
  # columns are the transform's and any field name passes (spec/14 §5.4).
  defp mark_fields(name, sources) when is_atom(name), do: sources[name].fields
  defp mark_fields(%{transforms: [_ | _]}, _sources), do: @fields
  defp mark_fields(%{source: name}, sources), do: sources[name].fields

  defp data_node(name) do
    node(%{source: constant(name)}, %{transforms: list_of(transform(), max_length: 2)})
  end

  defp transform do
    bind(member_of(Schema.transform_ops()), fn op ->
      %{required: required, optional: optional} = Schema.transform_keys(op)
      keys = transform_keys()
      required = keys |> Map.take(required) |> Map.put(:op, constant(op))
      node(required, Map.take(keys, optional))
    end)
  end

  defp transform_keys do
    %{
      field: member_of(@fields),
      fields: list_of(member_of(@fields), length: 2),
      by: member_of(@fields),
      id: member_of(@fields),
      as: member_of(@names),
      thresholds: one_of([integer(1..50), list_of(number(), max_length: 3)]),
      order: member_of(@orders),
      offset: member_of(@offsets),
      size: list_of(number(), length: 2),
      padding: number(),
      tile: member_of([:squarify, :binary, :slice, :dice, :slice_dice]),
      bandwidth: number(),
      output: member_of([:nodes, :links, :groups, :chords, :triangles, :hull, :cells, :edges])
    }
  end

  defp channels(type, fields, vars) do
    %{required: required, optional: optional} = Schema.channels(type)
    value = with_var([member_of(fields), number(), field_ref(fields)], vars)
    node(Map.new(required, &{&1, value}), Map.new(optional, &{&1, value}))
  end

  defp options(type), do: optional_map(Map.new(Schema.options(type), &{&1, number()}))

  defp mark_label(fields, vars, styles) do
    node(%{text: text(vars, fields)}, %{
      anchor: member_of(@mark_anchors),
      style: style_ref(styles),
      dx: number(),
      dy: number()
    })
  end

  defp labels(vars, styles, frame) do
    scales = Map.keys(frame.scales)
    corners = [:top_left, :top_right, :bottom_left, :bottom_right]

    frame_anchors = [
      member_of([:title, :subtitle, :caption]),
      map(member_of(corners), &{:frame, &1}),
      map(tuple({json_term(), json_term()}), fn {x, y} -> {:data, [x, y]} end)
    ]

    axis_anchors = if scales == [], do: [], else: [map(member_of(scales), &{:axis, &1})]

    label =
      node(%{anchor: one_of(frame_anchors ++ axis_anchors), text: text(vars, nil)}, %{
        style: style_ref(styles),
        dx: number(),
        dy: number()
      })

    list_of(label, max_length: 2)
  end

  defp meta(vars), do: optional_map(%{name: text_string(), description: text(vars, nil)})
end
