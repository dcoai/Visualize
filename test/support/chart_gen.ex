defmodule Visualize.ChartGen do
  @moduledoc """
  StreamData generators for valid designs (spec/14): every node kind, every value type,
  every reference kind resolving against the design that carries it. Shared by the map
  and JSON round-trip properties.
  """

  import ExUnitProperties, only: [gen: 2]
  import StreamData

  alias Visualize.Chart.{Schema, Var}
  alias Visualize.Chart.Validator.Domain
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
    # A colour channel and its frame's colour scale are drawn independently, so a constant
    # or a typed column can land outside a declared domain — the validator's
    # `{:outside_domain, …}` (spec/14 §10.1, D-122). Such a design is not valid; drop it.
    filter(designs(), &(Domain.faults(&1) == []), 50)
  end

  defp designs do
    gen all(
          theme <- theme(),
          sources <- sources(),
          vars <- vars(),
          defs <- defs(theme, vars),
          styles <- styles(theme, vars, defs),
          frame <- frame(vars),
          marks <- marks(sources, vars, styles, frame),
          labels <- labels(vars, styles, frame),
          meta <- meta(vars)
        ) do
      %{
        version: 3,
        meta: meta,
        sources: sources,
        vars: vars,
        theme: theme,
        styles: styles,
        defs: defs,
        # The grid a design's frames are placed on (spec/14 §2.8, #384); one cell here,
        # since the generator writes one frame and places it by its box.
        layout: %{},
        # No sync group (spec/14 §2.9): the generator writes no interaction.
        interaction: %{},
        frames: %{main: frame},
        marks: marks,
        labels: labels
      }
    end
  end

  # -- leaves ---------------------------------------------------------------------------

  defp number, do: one_of([integer(-1000..1000), float(min: -1000.0, max: 1000.0)])

  defp text_string, do: string(:alphanumeric, min_length: 1, max_length: 8)

  defp category_string, do: filter(text_string(), &(&1 != "auto"))

  # An axis's `format` string "duration" reads back as `:duration` (spec/14 §11.1, D-144).
  defp format_string, do: filter(text_string(), &(&1 != "duration"))

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

  # A channel at its scale's own end (spec/14 §5.2, §11.2, #554).
  defp scale_end, do: map(member_of([:min, :max]), &{:scale, &1})

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

  # A colour (spec/14 §3.2, #664): a colour slot written bare, as a host's code may, or
  # typed, or a transform of colours, every one canonicalized to its typed form on read.
  defp colour_slot(theme) do
    name = member_of(Theme.color_slots(theme_struct(theme)) ++ [:red, :steelblue])
    unit = float(min: 0.0, max: 1.0)
    typed = map(name, &{:color, &1})

    one_of([
      name,
      typed,
      map(integer(1..12), &{:series, &1}),
      map({member_of([:intensity, :alpha, :lighten, :darken, :saturate]), typed, unit}, & &1),
      map(
        list_of(one_of([typed, member_of(@colours)]), min_length: 1, max_length: 3),
        &{:blend, &1}
      ),
      map(typed, &{:contrast, &1})
    ])
  end

  # A source's `types` names only its fields (#369): the fields are drawn first and a type
  # is given to a subset of them.
  defp sources do
    source =
      bind(uniq_list_of(member_of(@fields), min_length: 1, max_length: 4), fn fields ->
        types =
          fields
          |> Map.new(&{&1, one_of([constant(nil), member_of(Schema.column_types())])})
          |> fixed_map()
          |> map(fn m -> for {k, v} <- m, v != nil, into: %{}, do: {k, v} end)

        node(%{fields: constant(fields)}, %{types: types, default: member_of(@names)})
      end)

    filter(optional_map(Map.new(@names, &{&1, source})), &(&1 != %{}))
  end

  defp vars do
    declaration = optional_map(%{default: json_term()})
    optional_map(%{unit: declaration, accent: declaration, n: declaration})
  end

  defp styles(theme, vars, defs) do
    style = style(theme, vars, defs)
    optional_map(%{series: style, muted: style, axis: style})
  end

  # The paints (spec/14 §2.7): a gradient in the words a person uses, its stops' colours
  # any colour a style takes but a paint.
  defp defs(theme, vars) do
    stop =
      fixed_map(%{
        offset: float(min: 0.0, max: 1.0),
        color: with_var([member_of(@colours), colour_slot(theme)], vars)
      })
      |> bind(fn stop ->
        optional_map(%{opacity: float(min: 0.0, max: 1.0)}) |> map(&Map.merge(stop, &1))
      end)

    gradient =
      fixed_map(%{
        kind: member_of([:linear, :radial]),
        stops: list_of(stop, min_length: 2, max_length: 3)
      })
      |> bind(fn g ->
        optional_map(%{
          angle: integer(0..360),
          center: list_of(float(min: 0.0, max: 1.0), length: 2),
          radius: float(min: 0.0, max: 1.0)
        })
        |> map(&Map.merge(g, &1))
      end)

    optional_map(%{fade: gradient, glow: gradient})
  end

  defp style(theme, vars, defs) do
    paints = if map_size(defs) == 0, do: [], else: [map(member_of(Map.keys(defs)), &{:paint, &1})]

    colour =
      with_var(
        [member_of(@colours), constant(:none), colour_slot(theme), field_ref(@fields)] ++ paints,
        vars
      )

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
      line_height: float(min: 0.8, max: 3.0),
      vertical_align: member_of([:top, :middle, :baseline, :bottom]),
      margin_x: float(min: 0.0, max: 40.0),
      margin_y: float(min: 0.0, max: 40.0),
      text_angle: integer(-180..180),
      blend: member_of([:normal, :multiply, :screen, :overlay, :darken, :lighten]),
      effect: member_of([:none, :shadow, :blur]),
      effect_radius: size,
      # A class is CSS class names (spec/14 §10.3).
      class: map(text_string(), &("c" <> &1)),
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
          base <- optional_map(%{margin: margin(), projection: projection(), facet: facet()}),
          scales <- optional_map(Map.new(@scale_names, &{&1, scale()})),
          furniture <- furniture(Map.keys(scales), vars)
        ) do
      Map.merge(%{kind: kind, scales: scales}, Map.merge(base, furniture))
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
      format: one_of([format_string(), constant(:duration)]),
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

  # A needle is a polar frame's mark (spec/14 §5.2, #392): drawn only there. A basemap
  # needs a Mercator `:geo` frame and its provider node, and has tests of its own
  # (`test/visualize/chart/tiles_test.exs`, #475).
  defp marks(sources, vars, styles, frame) do
    types =
      if frame.kind == :polar,
        do: Schema.mark_types() -- [:tiles],
        else: Schema.mark_types() -- [:needle, :tiles]

    list_of(mark(sources, vars, styles, types), max_length: 3)
  end

  defp mark(sources, vars, styles, types) do
    gen all(
          type <- member_of(types),
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
      bind(transform_key_sets(op), fn {required, optional} ->
        # A fold's `as` is a pair of names, every other op's one (spec/14 §5.4).
        # A stack's order may be fixed by its keys; a sort's is a direction (#492).
        keys =
          case op do
            :fold -> Map.put(transform_keys(), :as, list_of(member_of(@names), length: 2))
            :stack -> Map.put(transform_keys(), :order, stack_order())
            _op -> transform_keys()
          end

        required = keys |> Map.take(required) |> Map.put(:op, constant(op))
        node(required, Map.take(keys, optional))
      end)
    end)
  end

  # The op's required and optional keys; a projection reads points through `fields` or
  # geometries through `field`, one of the two and never both (spec/14 §5.4.4).
  defp transform_key_sets(:projection), do: member_of([{[:fields], []}, {[:field], []}])

  defp transform_key_sets(op) do
    %{required: required, optional: optional} = Schema.transform_keys(op)
    constant({required, optional})
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
      output:
        member_of([:nodes, :links, :groups, :chords, :triangles, :hull, :cells, :edges, :points]),
      n: integer(0..10),
      width: one_of([integer(1..10), constant(:plot)]),
      side: member_of([:end, :start]),
      from: duration(),
      to: duration()
    }
  end

  defp stack_order do
    one_of([member_of(@orders), tuple({constant(:keys), list_of(member_of(@fields))})])
  end

  # A `:window` bound is `[n, unit]` (spec/14 §5.4.1, #426).
  defp duration do
    fixed_list([integer(1..10), member_of([:second, :minute, :hour, :day, :week, :year])])
  end

  # An arc's `start` and `end` come as a pair, drawn together or not at all (spec/14 §5.2,
  # D-69): the validator holds either one to the other.
  defp channels(:arc, fields, vars) do
    %{required: required, optional: optional} = Schema.channels(:arc)
    value = channel_value(fields, vars)
    pair = fixed_map(%{start: value, end: value})
    single = Map.new(optional -- [:start, :end], &{&1, value})

    node(Map.new(required, &{&1, value}), Map.put(single, :angles, pair))
    |> map(fn channels ->
      {angles, rest} = Map.pop(channels, :angles, %{})
      Map.merge(rest, angles)
    end)
  end

  # A rule stands at `x`, or at a radius `y` in a polar frame (spec/14 §5.2, #391): the
  # generator gives it `x`, since the validator holds a rule without `y` to it.
  defp channels(:rule, fields, vars) do
    value = channel_value(fields, vars)
    node(%{x: value}, %{y: value})
  end

  defp channels(type, fields, vars) do
    %{required: required, optional: optional} = Schema.channels(type)
    value = channel_value(fields, vars)
    node(Map.new(required, &{&1, value}), Map.new(optional, &{&1, value}))
  end

  defp channel_value(fields, vars) do
    with_var([member_of(fields), number(), field_ref(fields), scale_end()], vars)
  end

  # Every option is a number but a needle's cap, an enum (spec/14 §5.3, #392).
  defp options(type) do
    optional_map(
      Map.new(Schema.options(type), fn
        :cap -> {:cap, member_of([:point, :round, :flat])}
        :closed -> {:closed, boolean()}
        key -> {key, number()}
      end)
    )
  end

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
