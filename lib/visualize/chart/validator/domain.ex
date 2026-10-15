defmodule Visualize.Chart.Validator.Domain do
  @moduledoc false
  # The colour-domain check of the validator (spec/14 §10.1, #487, D-122): a value a mark
  # sends to its frame's colour scale that the scale's *declared* ordinal domain can be seen
  # not to hold. Every element it reaches would draw the scale's `unknown`, so the design
  # says something it cannot mean.
  #
  # Only what the design decides is reported: a constant channel's number, and a field
  # whose source declares a column type no value of the domain can have. An untyped field,
  # a `:category` column, a source read through transforms, an inferred or variable domain
  # and a style reached through a variable are not decidable here and are passed over. The
  # walk is total over any map, since the validator is handed arbitrary input: a shape it
  # does not recognise contributes nothing, and the schema walk reports it.
  #
  # And the inferred-domain check (#490, D-124): a `:text` mark's position channel that is
  # a literal number naming a scale whose domain is inferred. Inference reads the constant
  # as data, so a caption holds the domain open where the data has left it.

  alias Visualize.Chart.Frame.Scales
  alias Visualize.Chart.{Schema, Style, Var}
  alias Visualize.Chart.Style.Parts

  @colour_keys [:fill, :stroke]
  @temporal [DateTime, Date, NaiveDateTime]
  # The position scales a channel names before a mark's `scales` renames it (spec/14 §4.3).
  @positions [:x, :y, :angle, :r]

  @doc false
  @spec faults(map()) :: [{list(), term()}]
  def faults(%{marks: marks} = design) when is_list(marks) do
    frames = map_or_empty(design[:frames])
    styles = Style.all(map_or_empty(design[:styles]))
    sources = map_or_empty(design[:sources])

    marks
    |> Enum.with_index()
    |> Enum.flat_map(fn {mark, i} -> mark(mark, [:marks, i], frames, styles, sources) end)
  end

  def faults(_design), do: []

  defp mark(%{} = mark, path, frames, styles, sources) when not is_struct(mark) do
    frame = frame(mark[:frame], frames)
    scales = map_or_empty(frame[:scales])
    columns = columns(mark[:data], sources)

    channels(mark, frame, scales, columns, path) ++
      style(mark, scales, styles, columns, path) ++ inferred(mark, frame, frames, path)
  end

  defp mark(_mark, _path, _frames, _styles, _sources), do: []

  # A mark is drawn in the frame it names, or the design's only frame (spec/14 §5.1).
  defp frame(name, frames) when is_map_key(frames, name), do: map_or_empty(frames[name])

  defp frame(_name, frames) when map_size(frames) == 1,
    do: frames |> Map.values() |> hd() |> map_or_empty()

  defp frame(_name, _frames), do: %{}

  # The column types of the mark's source, when its rows are the source's own.
  defp columns(name, sources) when is_atom(name) and is_map_key(sources, name) do
    case sources[name] do
      %{types: types} when is_map(types) and not is_struct(types) -> types
      _ -> %{}
    end
  end

  defp columns(%{source: name} = data, sources) when not is_struct(data) do
    case Map.get(data, :transforms, []) do
      [] -> columns(name, sources)
      _transformed -> %{}
    end
  end

  defp columns(_data, _sources), do: %{}

  # -- channels -------------------------------------------------------------------------

  # `series` names the colour scale in every frame kind, `value` on a `:rect` and in a
  # `:geo` frame (spec/14 §4.3); a mark's `scales` node may rename it.
  defp channels(mark, frame, scales, columns, path) do
    channels = map_or_empty(mark[:channels])
    name = colour_scale(map_or_empty(mark[:scales]))

    case domain(scales[name]) do
      nil ->
        []

      domain ->
        for key <- colour_channels(mark[:type], frame[:kind]),
            Map.has_key?(channels, key),
            reason = channel(channels[key], name, domain, columns),
            do: {path ++ [:channels, key], reason}
    end
  end

  defp colour_scale(%{color: name}) when is_atom(name) and name not in [nil, true, false],
    do: name

  defp colour_scale(_scales), do: :color

  defp colour_channels(:rect, _kind), do: [:series, :value]
  defp colour_channels(_type, :geo), do: [:series, :value]
  defp colour_channels(_type, _kind), do: [:series]

  defp channel(value, name, domain, _columns) when is_number(value) do
    if Enum.any?(domain, &(&1 == value)), do: nil, else: {:outside_domain, name, value}
  end

  defp channel({:field, field}, name, domain, columns), do: column(field, name, domain, columns)
  defp channel(field, name, domain, columns), do: column(field, name, domain, columns)

  # -- a constant on an inferred domain (#490, D-124) -----------------------------------

  # A `:text` mark is its label (spec/14 §5.2): a number in a position channel is where the
  # words stand, never a reading the axis must reach. Any other type's constant — a rule's
  # baseline — is data the author means the domain to hold, and is not reported.
  defp inferred(%{type: :text} = mark, frame, frames, path) do
    channels = map_or_empty(mark[:channels])
    kind = frame[:kind]
    renames = %{scales: map_or_empty(mark[:scales])}
    table = Scales.channel_scales(kind)
    scales = map_or_empty(frame[:scales])

    for {channel, n} <- channels,
        is_number(n),
        Map.get(table, channel) in @positions,
        name = Scales.scale_for(kind, renames, channel),
        infers?(scales[name], frames, []),
        do: {path ++ [:channels, channel], {:feeds_domain, name, n}}
  end

  defp inferred(_mark, _frame, _frames, _path), do: []

  # Whether a scale node infers its domain — `:auto`, or `:auto` at an end, the schema's
  # default when absent — following an adoption `{:frame, f, s}` to the node that owns it
  # (spec/14 §4.3). A variable domain, an undeclared or cyclic adoption and anything else
  # are not decidable here, and the schema walk reports what is malformed.
  defp infers?({:frame, f, s} = ref, frames, seen) when is_map_key(frames, f) do
    if ref in seen,
      do: false,
      else: infers?(map_or_empty(map_or_empty(frames[f])[:scales])[s], frames, [ref | seen])
  end

  defp infers?(%{} = node, _frames, _seen) when not is_struct(node),
    do: auto?(Map.get(node, :domain, Schema.default(:scale, :domain)))

  defp infers?(_node, _frames, _seen), do: false

  defp auto?(:auto), do: true
  defp auto?([lo, hi]), do: lo == :auto or hi == :auto
  defp auto?(_domain), do: false

  # -- the mark's style -----------------------------------------------------------------

  # A `{:field, f}` on a colour key reads through the mark's colour scale, `color` renamed
  # by its `scales` like any channel (spec/14 §4.3, D-143).
  defp style(mark, scales, styles, columns, path) do
    name = colour_scale(map_or_empty(mark[:scales]))

    case domain(scales[name]) do
      nil ->
        []

      domain ->
        node = cascade(mark[:style], styles)

        @colour_keys
        |> Enum.flat_map(fn key ->
          case Map.get(node, key) do
            {:field, field} -> [column(field, name, domain, columns)]
            _other -> []
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.map(&{path ++ [:style], &1})
    end
  end

  # The stack's entries cascaded left to right, each through its `extends` chain
  # (spec/14 §3.5, §3.6). A cycle stops the walk where it closes — the validator reports
  # it by path — and a variable contributes nothing. The entries merge in their parts and
  # the result is projected onto the flat keys, as `Visualize.Chart.Style.node/2` does
  # (D-172).
  @doc false
  @spec cascade(term(), map()) :: map()
  def cascade(entries, styles) when is_list(entries) do
    entries
    |> Enum.reduce(%{}, fn entry, node -> Parts.merge(node, entry(entry, styles, [])) end)
    |> Parts.project()
  end

  def cascade(entry, styles), do: entry |> entry(styles, []) |> Parts.project()

  defp entry(%Var{}, _styles, _seen), do: %{}

  defp entry(%{} = inline, styles, seen) when not is_struct(inline) do
    inline = Parts.normalize(inline)

    parent =
      if Map.has_key?(inline, :extends), do: entry(inline[:extends], styles, seen), else: %{}

    Parts.merge(parent, Map.delete(inline, :extends))
  end

  defp entry(name, styles, seen) when is_atom(name) and is_map_key(styles, name) do
    if name in seen, do: %{}, else: named(styles[name], styles, [name | seen])
  end

  defp entry(_entry, _styles, _seen), do: %{}

  defp named(%{} = node, styles, seen) when not is_struct(node) do
    node = Parts.normalize(node)
    parent = if Map.has_key?(node, :extends), do: entry(node[:extends], styles, seen), else: %{}
    Parts.merge(parent, Map.delete(node, :extends))
  end

  defp named(_node, _styles, _seen), do: %{}

  # -- domains and columns --------------------------------------------------------------

  # A declared ordinal domain: a literal, non-empty list with no variable and no `:auto`.
  defp domain(%{kind: :ordinal, domain: domain}) when is_list(domain) and domain != [] do
    if Enum.any?(domain, &(is_struct(&1, Var) or &1 == :auto)), do: nil, else: domain
  end

  defp domain(_node), do: nil

  defp column(field, name, domain, columns) when is_atom(field) do
    case Map.get(columns, field) do
      type when type in [:number, :text, :time] ->
        if Enum.any?(domain, &holds?(type, &1)),
          do: nil,
          else: {:outside_domain, name, {:column, field, type}}

      _untyped_or_category ->
        nil
    end
  end

  defp column(_field, _name, _domain, _columns), do: nil

  # Whether a column of the type can hold the value (spec/14 §2.3): a `:time` column holds
  # temporal structs, ISO 8601 strings and numbers, so only what is none of them is out.
  defp holds?(:number, value), do: is_number(value)
  defp holds?(:text, value), do: is_binary(value) or is_atom(value)

  defp holds?(:time, value),
    do:
      is_binary(value) or is_number(value) or (is_struct(value) and value.__struct__ in @temporal)

  defp map_or_empty(%{} = map) when not is_struct(map), do: map
  defp map_or_empty(_other), do: %{}
end
