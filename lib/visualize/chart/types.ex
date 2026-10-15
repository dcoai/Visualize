defmodule Visualize.Chart.Types do
  @moduledoc false
  # The type check of a binding (spec/14 §7.4, D-153): every field a mark reads through a
  # scale, with what the scale's kind needs of it, and the reads a set of known types does
  # not satisfy. Pure and total over any map — an unfinished design, or one with variables
  # still in it, is checked as far as it says anything; a shape it does not recognize
  # contributes nothing, and the validator reports it.

  alias Visualize.Chart.Frame.Scales
  alias Visualize.Chart.{Style, Var}
  alias Visualize.Chart.Validator.Domain
  alias Visualize.Data.Schema

  @type need :: Visualize.Chart.need()

  @typedoc "One read: where it is, the slot and the field it reads, and what its scale needs."
  @type read :: {list(), atom(), atom(), need()}

  @type known :: Visualize.Chart.field_types()

  @numeric [
    :linear,
    :log,
    :power,
    :sqrt,
    :symlog,
    :radial,
    :quantize,
    :quantile,
    :threshold,
    :sequential,
    :diverging
  ]

  # The steps that keep every field of a row as it is (spec/14 §5.4): a field read after
  # them is the slot's own. Any other step can make or rename one.
  @keeping [:filter, :sort, :take, :window, :lttb, :m4]

  @doc false
  # What a scale of the kind needs of a field it reads; `nil` for no kind of spec/14 §4.3.
  @spec need(term()) :: need() | nil
  def need(:time), do: :time
  def need(kind) when kind in @numeric, do: :number
  def need(kind) when kind in [:band, :ordinal], do: :category
  def need(_kind), do: nil

  @doc false
  # Whether a type satisfies a need (spec/14 §7.4). A schema's type is what a field means:
  # `:text` is as discrete as `:category`, and `:time` is instants (D-154), which no
  # numeric scale takes — a feed's tick is a `:number`. A rows' type is how values are
  # written: `:time` is instants there too, and a band or ordinal scale takes a value of
  # any type.
  @spec satisfies?(atom(), need(), :schema | :rows) :: boolean()
  def satisfies?(:text, :category, :schema), do: true
  def satisfies?(_type, :category, :rows), do: true
  def satisfies?(type, need, _from), do: type == need

  @doc false
  # Every field the design's marks read through a scale, in mark order.
  @spec reads(map()) :: [read()]
  def reads(%{marks: marks} = design) when is_list(marks) do
    frames = map_or_empty(design[:frames])
    styles = Style.all(map_or_empty(design[:styles]))
    slots = map_or_empty(design[:sources])

    marks
    |> Enum.with_index()
    |> Enum.flat_map(fn {mark, i} -> mark(mark, [:marks, i], frames, styles, slots) end)
  end

  def reads(_design), do: []

  @doc false
  # Every read whose field the known types describe with a type that does not satisfy its
  # need, as `{path, {:type_mismatch, slot, field, expected, given}}`. A slot the map does
  # not hold, and a field it does not describe, are not checked.
  @spec faults([read()], %{atom() => known()}) :: [{list(), tuple()}]
  def faults(reads, known) when is_list(reads) and is_map(known) do
    for {path, slot, field, need} <- reads,
        {:ok, types} <- [Map.fetch(known, slot)],
        given = type(types, field),
        given != nil,
        not satisfies?(given, need, from(types)),
        uniq: true,
        do: {path, {:type_mismatch, slot, field, need, given}}
  end

  defp from(%Schema{}), do: :schema
  defp from(_rows), do: :rows

  # A field's type, in either spelling (D-52).
  defp type(%Schema{} = schema, field) do
    case Schema.fetch(schema, field, :type) do
      {:ok, type} -> type
      :error -> nil
    end
  end

  defp type(types, field) when is_map(types) do
    case Map.fetch(types, field) do
      {:ok, type} when is_atom(type) -> type
      _absent -> types |> Map.get(Atom.to_string(field)) |> atom_or_nil()
    end
  end

  defp type(_types, _field), do: nil

  defp atom_or_nil(type) when is_atom(type), do: type
  defp atom_or_nil(_other), do: nil

  # -- a mark's reads ---------------------------------------------------------------------

  defp mark(%{} = mark, path, frames, styles, slots) when not is_struct(mark) do
    with slot when slot != nil <- slot(mark[:data], slots),
         %{} = frame <- frame(mark[:frame], frames) do
      kind = frame[:kind]
      scales = map_or_empty(frame[:scales])
      need = fn name -> scale_need(scales[name], frames, []) end

      channels(mark, kind, need, slot, path) ++
        style(mark, styles, need, slot, path) ++ offsets(mark, kind, need, slot, path)
    else
      _unchecked -> []
    end
  end

  defp mark(_mark, _path, _frames, _styles, _slots), do: []

  # The slot whose rows the mark reads as they are: named, or named with steps that keep
  # every field; `nil` otherwise.
  defp slot(name, slots) when is_atom(name) and is_map_key(slots, name), do: name

  defp slot(%{source: name} = data, slots) when not is_struct(data) do
    case Map.get(data, :transforms, []) do
      steps when is_list(steps) -> if Enum.all?(steps, &keeping?/1), do: slot(name, slots)
      _variable -> nil
    end
  end

  defp slot(_data, _slots), do: nil

  defp keeping?(%{op: op}) when op in @keeping, do: true
  defp keeping?(_step), do: false

  # A mark is drawn in the frame it names, or the design's only frame (spec/14 §5.1).
  defp frame(name, frames) when is_atom(name) and is_map_key(frames, name),
    do: map_or_nil(frames[name])

  defp frame(_name, frames) when map_size(frames) == 1,
    do: frames |> Map.values() |> hd() |> map_or_nil()

  defp frame(_name, _frames), do: nil

  # What a scale node needs, following an adoption `{:frame, f, s}` to the node that owns
  # it (spec/14 §4.3); `nil` for a variable kind, an undeclared or cyclic adoption, or none.
  defp scale_need({:frame, f, s} = ref, frames, seen) when is_map_key(frames, f) do
    if ref in seen,
      do: nil,
      else: scale_need(map_or_empty(map_or_empty(frames[f])[:scales])[s], frames, [ref | seen])
  end

  defp scale_need(%{kind: kind} = node, _frames, _seen) when not is_struct(node), do: need(kind)
  defp scale_need(_node, _frames, _seen), do: nil

  # Each channel naming a scale whose value is a field (spec/14 §4.3, §5.2).
  defp channels(mark, kind, need, slot, path) do
    for {channel, value} <- mark |> Map.get(:channels) |> map_or_empty() |> Enum.sort(),
        field = field(value),
        field != nil,
        name = Scales.scale_for(kind, mark, channel),
        needed = name && need.(name),
        needed != nil,
        do: {path ++ [:channels, channel], slot, field, needed}
  end

  # A `{:field, f}` on the style's color keys reads through the mark's color scale
  # (spec/14 §4.3, D-143).
  defp style(mark, styles, need, slot, path) do
    case need.(Scales.color_scale(mark)) do
      nil ->
        []

      needed ->
        node = Domain.cascade(mark[:style], styles)

        for key <- [:fill, :stroke],
            {:field, field} <- [Map.get(node, key)],
            name?(field),
            uniq: true,
            do: {path ++ [:style], slot, field, needed}
    end
  end

  # An offset family's field reads through its offset scale (spec/14 §5.1).
  defp offsets(mark, kind, need, slot, path) do
    for {family, value} <- mark |> Map.get(:offset) |> map_or_empty() |> Enum.sort(),
        family in [:x, :y],
        field = field(value),
        field != nil,
        Scales.scale_for(kind, mark, family) != nil,
        needed = need.(Scales.offset_scale(mark, family)),
        needed != nil,
        do: {path ++ [:offset, family], slot, field, needed}
  end

  defp field({:field, field}), do: if(name?(field), do: field)
  defp field(%Var{}), do: nil
  defp field(value), do: if(name?(value), do: value)

  defp name?(value), do: is_atom(value) and value not in [nil, true, false]

  defp map_or_empty(%{} = map) when not is_struct(map), do: map
  defp map_or_empty(_other), do: %{}

  defp map_or_nil(%{} = map) when not is_struct(map), do: map
  defp map_or_nil(_other), do: nil
end
