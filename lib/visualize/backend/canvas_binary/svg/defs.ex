defmodule Visualize.Backend.CanvasBinary.SVG.Defs do
  @moduledoc false
  # What an SVG element's references draw on the binary stream (spec/09 §4.7, #825, D-211):
  # its `clip-path` and its `mask` as `clip` records, its `filter` as an `effect` record,
  # each resolved against the tree's elements by their `id`, as SVG resolves a `url(#id)`
  # anywhere in the document. A reference the stream cannot express — to nothing, or to a
  # definition that is not one the records hold — resolves to nothing, and the element
  # draws unclipped or unfiltered, as spec/09 §4.7 lists.

  alias Visualize.Backend.CanvasBinary.Opcodes
  alias Visualize.IR.Paint
  alias Visualize.SVG.Element
  require Opcodes

  # The shapes a clip or a mask holds, each the geometry it is drawn with.
  @shapes [:rect, :circle, :ellipse, :path, :polygon, :polyline]

  # The square the library's outside mask paints white, and the reader's outside clip
  # adds: everything a canvas draws (spec/09 §4.3.18).
  @everything {-100_000.0, -100_000.0, 200_000.0, 200_000.0}

  @doc false
  # Every element of the tree under its `id`, the first one where two share it, as SVG
  # resolves a reference to the first element with the id.
  @spec ids(Element.t()) :: %{String.t() => Element.t()}
  def ids(%Element{attrs: attrs, children: children} = element) do
    own =
      case Map.get(attrs, :id) do
        id when is_binary(id) -> %{id => element}
        _none -> %{}
      end

    Enum.reduce(children, own, fn child, acc -> Map.merge(ids(child), acc) end)
  end

  @doc false
  # The `id` a `url(#id)` reference names, or nil.
  @spec ref(term()) :: String.t() | nil
  def ref(value) when is_binary(value) do
    case Regex.run(~r/\A\s*url\(\s*["']?#([^"')\s]+)["']?\s*\)\s*\z/, value) do
      [_, id] -> id
      nil -> nil
    end
  end

  def ref(_value), do: nil

  @doc false
  # The clips an element's `clip-path` and `mask` make, in that order, each `{keep, shape}`:
  # `:inside` or `:outside` a shape element. A `clipPath` of one shape in user space keeps
  # inside it; a `mask` of one white shape keeps inside it, and one of a white rectangle and
  # a black shape keeps inside the rectangle and outside the shape — the rectangle no clip
  # when it covers everything, as the library's own outside mask does (spec/09 §2.3).
  @spec clips(%{clip_path: term(), mask: term()}, map()) :: [{:inside | :outside, Element.t()}]
  def clips(%{clip_path: clip_path, mask: mask}, ids) do
    clip_path(Map.get(ids, ref(clip_path))) ++ mask(Map.get(ids, ref(mask)))
  end

  defp clip_path(%Element{tag: :clipPath, attrs: attrs, children: [shape]}) do
    if Map.keys(attrs) -- [:id, :clip_path_units, :clipPathUnits] == [] and
         user_space?(attrs, :clip_path_units) and shape?(shape),
       do: [{:inside, shape}],
       else: []
  end

  defp clip_path(_absent), do: []

  defp mask(%Element{tag: :mask, attrs: attrs, children: children}) do
    with true <- user_space?(attrs, :mask_units),
         [_ | _] = clips <- mask_clips(children) do
      clips
    else
      _ -> []
    end
  end

  defp mask(_absent), do: []

  defp mask_clips([white]) do
    if shape?(white) and paint(white) == :white, do: [{:inside, white}], else: []
  end

  defp mask_clips([%Element{tag: :rect} = white, black]) do
    if paint(white) == :white and shape?(black) and paint(black) == :black do
      if covers_everything?(white),
        do: [{:outside, black}],
        else: [{:inside, white}, {:outside, black}]
    else
      []
    end
  end

  defp mask_clips(_children), do: []

  # A shape the clip records draw: one of the tags, with no transform of its own and no
  # clip or mask of its own.
  defp shape?(%Element{tag: tag, attrs: attrs, children: []}) when tag in @shapes do
    Enum.all?([:transform, :clip_path, :"clip-path", :mask], &(Map.get(attrs, &1) == nil))
  end

  defp shape?(_element), do: false

  # A mask's shape paints white or black: its fill, at its opacities, all or none of the
  # luminance a mask keeps.
  defp paint(%Element{attrs: attrs}) do
    fill = Map.get(attrs, :fill)
    opaque? = Enum.all?([:opacity, :fill_opacity, :"fill-opacity"], &(opacity(attrs, &1) == 1.0))

    case is_binary(fill) and Visualize.Color.parse(fill) do
      %Visualize.Color{} = color when opaque? ->
        case Visualize.Color.to_rgba(color) do
          {255, 255, 255, a} when a == 1.0 -> :white
          {0, 0, 0, a} when a == 1.0 -> :black
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp opacity(attrs, key) do
    case Map.get(attrs, key) do
      nil -> 1.0
      other -> number(other)
    end
  end

  defp covers_everything?(%Element{attrs: attrs}) do
    {x0, y0, w0, h0} = @everything
    [x, y, w, h] = for key <- [:x, :y, :width, :height], do: number(Map.get(attrs, key))

    is_number(x) and is_number(y) and is_number(w) and is_number(h) and x <= x0 and y <= y0 and
      x + w >= x0 + w0 and y + h >= y0 + h0
  end

  # A definition's units are the referencing element's user space, SVG's default for a
  # `clipPath`'s contents, written for a mask as the library writes it.
  defp user_space?(attrs, key) do
    camel = if key == :clip_path_units, do: :clipPathUnits, else: :maskUnits
    value = Map.get(attrs, key) || Map.get(attrs, camel)

    case key do
      :clip_path_units -> value in [nil, "userSpaceOnUse"]
      :mask_units -> value == "userSpaceOnUse"
    end
  end

  @doc false
  # The `effect` record (spec/09 §4.3.14) of an element's `filter`, or `<<>>`: a `filter`
  # holding one `feDropShadow` or one `feGaussianBlur` of one standard deviation — the
  # filters the library writes for a style's effect (spec/14 §2.7) — with no attribute
  # of its own but its `id`, and no primitive attribute the record has no field for.
  @spec effect(term(), map()) :: binary()
  def effect(filter, ids) do
    case Map.get(ids, ref(filter)) do
      %Element{tag: :filter, attrs: attrs, children: [primitive]} when map_size(attrs) == 1 ->
        primitive_record(primitive)

      _other ->
        <<>>
    end
  end

  @shadow_keys [
    :dx,
    :dy,
    :std_deviation,
    :stdDeviation,
    :flood_color,
    :"flood-color",
    :flood_opacity,
    :"flood-opacity"
  ]

  defp primitive_record(%Element{tag: :feDropShadow, attrs: attrs}) do
    with true <- Enum.all?(Map.keys(attrs), &(&1 in @shadow_keys)),
         r when is_number(r) <- std_deviation(attrs),
         dx when is_number(dx) <- number(Map.get(attrs, :dx, 2)),
         dy when is_number(dy) <- number(Map.get(attrs, :dy, 2)),
         opacity when is_number(opacity) <-
           number(either(attrs, :flood_opacity, :"flood-opacity", 1)) do
      color = either(attrs, :flood_color, :"flood-color", "black")
      {cr, cg, cb, ca} = Paint.rgba({0, color, opacity})

      <<Opcodes.effect()::8, 0x01::8, r::little-float-32, dx::little-float-32,
        dy::little-float-32, cr::8, cg::8, cb::8, ca::8>>
    else
      _ -> <<>>
    end
  end

  defp primitive_record(%Element{tag: :feGaussianBlur, attrs: attrs}) do
    with true <- Enum.all?(Map.keys(attrs), &(&1 in [:std_deviation, :stdDeviation])),
         r when is_number(r) <- std_deviation(attrs) do
      <<Opcodes.effect()::8, 0x02::8, r::little-float-32>>
    else
      _ -> <<>>
    end
  end

  defp primitive_record(_other), do: <<>>

  defp either(attrs, a, b, default), do: Map.get(attrs, a) || Map.get(attrs, b) || default

  # One standard deviation: a number, or a string of one (two, a blur differing by axis,
  # has no field).
  defp std_deviation(attrs), do: number(either(attrs, :std_deviation, :stdDeviation, 2))

  defp number(n) when is_number(n), do: n * 1.0

  defp number(s) when is_binary(s) do
    case Float.parse(String.trim(s)) do
      {f, ""} -> f
      _other -> nil
    end
  end

  defp number(_other), do: nil
end
