defmodule Visualize.Backend.CanvasBinary.SVG.Defs do
  @moduledoc false
  # What an SVG element's references draw on the binary stream (spec/09 §4.7, #825, D-211):
  # its `clip-path` and its `mask` as `clip` records, its `filter` as an `effect` record,
  # and its `fill` and its `stroke` as `paint` records (#837, D-218), each resolved against
  # the tree's elements by their `id`, as SVG resolves a `url(#id)` anywhere in the
  # document. A reference the stream cannot express — to nothing, or to a definition that
  # is not one the records hold — resolves to nothing, and the element draws unclipped or
  # unfiltered, as spec/09 §4.7 lists, or paints its fallback.

  alias Visualize.Backend.CanvasBinary.Opcodes
  alias Visualize.IR.{Paint, Transform}
  alias Visualize.SVG.{Element, Renderer}
  require Opcodes

  # The shapes a clip or a mask holds, each the geometry it is drawn with.
  @shapes [:rect, :circle, :ellipse, :path, :polygon, :polyline]

  # The square the library's outside mask paints white, and the reader's outside clip
  # adds: everything a canvas draws (spec/09 §4.3.18).
  @everything {-100_000.0, -100_000.0, 200_000.0, 200_000.0}

  @identity {1.0, 0.0, 0.0, 1.0, 0.0, 0.0}

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

  @doc false
  # A declaration's value in an inline `style`: the last one of the property, as CSS reads
  # them, without `!important`.
  @spec inline_style(term(), String.t()) :: String.t() | nil
  def inline_style(style, property) when is_binary(style) do
    style
    |> String.split(";")
    |> Enum.flat_map(fn declaration ->
      case String.split(declaration, ":", parts: 2) do
        [name, value] ->
          if String.trim(name) |> String.downcase() == property,
            do: [value |> String.replace("!important", "") |> String.trim()],
            else: []

        _other ->
          []
      end
    end)
    |> List.last()
  end

  def inline_style(_style, _property), do: nil

  # -- paints (#837, D-218) -------------------------------------------------------------------

  @doc false
  # What a `fill` or a `stroke` paints with (spec/09 §4.7, D-218): `:color` where the value
  # is no `url(#id)` reference; otherwise what the definition it names resolves to, the
  # opacity `alpha` folded into it — `{:paint, paint}`, `{:color, color, opacity}` where it
  # paints one color, or `:none` — and its fallback where the records cannot say it. `box`
  # gives the element's tight bounds, asked only of a gradient in user space.
  @spec paint(term(), map(), (-> Paint.box() | nil), float()) ::
          :color | {:paint, Paint.t()} | {:color, term(), float()} | :none
  def paint(value, ids, box, alpha) do
    case paint_ref(value) do
      nil ->
        :color

      {id, fallback} ->
        case resolve(Map.get(ids, id), box, alpha) do
          {:ok, paint} -> paint
          :error -> fallback(fallback)
        end
    end
  end

  @doc false
  # Whether a `fill` or a `stroke` is a `url(#id)` reference, with or without a fallback.
  @spec reference?(term()) :: boolean()
  def reference?(value), do: paint_ref(value) != nil

  defp paint_ref(value) when is_binary(value) do
    case Regex.run(~r/\A\s*url\(\s*["']?#([^"')\s]+)["']?\s*\)\s*(.*?)\s*\z/s, value) do
      [_, id, ""] -> {id, nil}
      [_, id, fallback] -> {id, fallback}
      nil -> nil
    end
  end

  defp paint_ref(_value), do: nil

  # An unresolvable reference paints its fallback, or nothing, as SVG paints it.
  defp fallback(nil), do: :none
  defp fallback("none"), do: :none
  defp fallback(color), do: {:color, color, 1.0}

  defp resolve(%Element{tag: tag, attrs: attrs, children: children}, box, alpha)
       when tag in [:linearGradient, :radialGradient] do
    a = names(attrs)
    units = if a["gradientUnits"] == "userSpaceOnUse", do: :user, else: :box

    with false <- Enum.any?(["href", "xlink:href", "xlink-href"], &Map.has_key?(a, &1)),
         true <- (a["spreadMethod"] || "pad") == "pad",
         {:ok, [_, _ | _] = stops} <- stops(children),
         {:ok, to_gradient} <- to_gradient(units, a["gradientTransform"], box) do
      gradient(tag, a, units, to_gradient, stops, alpha)
    else
      {:ok, []} -> {:ok, :none}
      {:ok, [{_at, color, opacity}]} -> {:ok, {:color, color, opacity}}
      _other -> :error
    end
  end

  defp resolve(%Element{tag: :pattern} = pattern, _box, alpha), do: hatch(pattern, alpha)
  defp resolve(_other, _box, _alpha), do: :error

  # The map from box units into the gradient's space: the inverse of its `gradientTransform`,
  # after the box for a gradient in user space, which a box without area cannot map.
  defp to_gradient(units, transform, box) do
    matrix =
      case is_binary(transform) and Visualize.Backend.CanvasBinary.SVG.transform(transform) do
        {:ok, t} -> Transform.to_matrix(t)
        _absent_or_in_error -> @identity
      end

    with {:ok, inverse} <- invert(matrix) do
      case {units, units == :user && box.()} do
        {:box, _} ->
          {:ok, inverse}

        {:user, {x, y, w, h}} when w > 0 and h > 0 ->
          {:ok, Transform.multiply(inverse, {w * 1.0, 0.0, 0.0, h * 1.0, x * 1.0, y * 1.0})}

        {:user, _no_area} ->
          :error
      end
    end
  end

  # A linear gradient's line in box units: its parameter is affine in the gradient's space,
  # so in box units too, and the line runs from the image of its start along the gradient
  # vector `G` to where the parameter is 1, `P₁ + G / |G|²`. One without length paints its
  # last stop.
  defp gradient(:linearGradient, a, units, to_gradient, stops, alpha) do
    with {:ok, x1} <- coord(a["x1"] || 0, units),
         {:ok, y1} <- coord(a["y1"] || 0, units),
         {:ok, x2} <- coord(a["x2"] || "100%", units),
         {:ok, y2} <- coord(a["y2"] || 0, units) do
      {dx, dy} = {x2 - x1, y2 - y1}
      dd = dx * dx + dy * dy

      if dd == 0 do
        last(stops)
      else
        {ma, mb, mc, md, _, _} = to_gradient
        {gx, gy} = {(ma * dx + mb * dy) / dd, (mc * dx + md * dy) / dd}
        gg = gx * gx + gy * gy
        {:ok, from_gradient} = invert(to_gradient)
        {px, py} = Transform.apply_matrix(from_gradient, {x1, y1})
        geometry = %{x1: px, y1: py, x2: px + gx / gg, y2: py + gy / gg}
        {:ok, {:paint, gradient_paint(a, :linear, geometry, stops, alpha)}}
      end
    end
  end

  # A radial gradient's circle in box units, where the map into them is a similarity and the
  # focus is the center; one of radius 0 paints its last stop.
  defp gradient(:radialGradient, a, units, to_gradient, stops, alpha) do
    with {:ok, cx} <- coord(a["cx"] || "50%", units),
         {:ok, cy} <- coord(a["cy"] || "50%", units),
         {:ok, r} when r >= 0 <- coord(a["r"] || "50%", units),
         {:ok, fx} <- coord(a["fx"] || cx, units),
         {:ok, fy} <- coord(a["fy"] || cy, units),
         {:ok, fr} when fr == 0 <- coord(a["fr"] || 0, units),
         true <- close?(fx, cx) and close?(fy, cy),
         {:ok, {la, lb, lc, ld, _, _} = from_gradient} <- invert(to_gradient),
         true <- (close?(la, ld) and close?(lb, -lc)) or (close?(la, -ld) and close?(lb, lc)) do
      if r == 0 do
        last(stops)
      else
        {x, y} = Transform.apply_matrix(from_gradient, {cx, cy})
        scale = :math.sqrt(abs(la * ld - lb * lc))
        geometry = %{cx: x, cy: y, r: r * scale}
        {:ok, {:paint, gradient_paint(a, :radial, geometry, stops, alpha)}}
      end
    else
      _ -> :error
    end
  end

  defp gradient_paint(a, type, geometry, stops, alpha) do
    stops = for {at, color, opacity} <- stops, do: {at, color, opacity * alpha}
    %Paint{id: a["id"] || "", type: type, geometry: geometry, stops: stops}
  end

  defp last(stops) do
    {_at, color, opacity} = List.last(stops)
    {:ok, {:color, color, opacity}}
  end

  # A gradient's `stop` children as `{at, color, opacity}`: each offset clamped to 0–1 and
  # raised to the one before it, as SVG orders them; more than a record's 255 none.
  defp stops(children) do
    {stops, _} =
      children
      |> Enum.filter(&match?(%Element{tag: :stop}, &1))
      |> Enum.map_reduce(0.0, fn %Element{attrs: attrs}, floor ->
        a = names(attrs)
        style = a["style"]
        at = a["offset"] |> offset() |> max(0.0) |> min(1.0) |> max(floor)
        color = a["stop-color"] || inline_style(style, "stop-color") || "black"
        opacity = number(a["stop-opacity"] || inline_style(style, "stop-opacity") || 1) || 1.0
        {{at, color_string(color), opacity |> max(0.0) |> min(1.0)}, at}
      end)

    if length(stops) < 256, do: {:ok, stops}, else: :error
  end

  defp offset(value) do
    case coord(value, :box) do
      {:ok, at} -> at
      :error -> 0.0
    end
  end

  # A coordinate: a number, a numeric string, or a percentage of the box in box units. A
  # percentage in user space is of the viewport, which the records do not know.
  defp coord(n, _units) when is_number(n), do: {:ok, n * 1.0}

  defp coord(value, units) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {n, ""} -> {:ok, n}
      {n, "%"} when units == :box -> {:ok, n / 100}
      _other -> :error
    end
  end

  defp coord(_value, _units), do: :error

  # The hatch `Visualize.IR.Paint.definition/1` writes, read back (spec/09 §4.7, #673): a
  # square tile in user space turned by one rotation, an optional ground, and its line, its
  # two lines or its dot; any other pattern the record cannot hold.
  defp hatch(%Element{attrs: attrs, children: children}, alpha) do
    a = names(attrs)

    with [] <- Map.keys(a) -- ["id", "patternUnits", "width", "height", "patternTransform"],
         "userSpaceOnUse" <- a["patternUnits"],
         s when is_float(s) and s > 0 <- number(a["width"]),
         true <- close?(number(a["height"]), s),
         {:ok, angle} <- rotation(a["patternTransform"]),
         {background, marks} = ground(children, s),
         {:ok, pattern, color, width} <- marks(marks, s / 2) do
      geometry = %{pattern: pattern, angle: angle, spacing: s, width: width}

      {:ok,
       {:paint,
        %Paint{
          id: a["id"] || "",
          type: :hatch,
          geometry: geometry,
          color: fold(color, alpha),
          background: background && fold(background, alpha)
        }}}
    else
      _ -> :error
    end
  end

  defp rotation(nil), do: {:ok, 0.0}

  defp rotation(transform) when is_binary(transform) do
    case Visualize.Backend.CanvasBinary.SVG.transform(transform) do
      {:ok, %Transform{operations: [{:rotate, angle}]}} -> {:ok, angle}
      {:ok, %Transform{operations: []}} -> {:ok, 0.0}
      _other -> :error
    end
  end

  defp rotation(_other), do: :error

  defp ground([%Element{tag: :rect, attrs: attrs, children: []} | rest] = children, s) do
    a = names(attrs)

    if Enum.sort(Map.keys(a)) == ["fill", "height", "width", "x", "y"] and
         at?(a, x: 0, y: 0, width: s, height: s),
       do: {color_string(a["fill"]), rest},
       else: {nil, children}
  end

  defp ground(children, _s), do: {nil, children}

  defp marks([%Element{tag: :circle} = dot], half), do: dot(dot, half)

  defp marks([line], half) do
    with {:ok, color, width} <- ink(line, x1: 0, y1: half, x2: 2 * half, y2: half),
         do: {:ok, :lines, color, width}
  end

  defp marks([across, down], half) do
    with {:ok, color, width} <- ink(across, x1: 0, y1: half, x2: 2 * half, y2: half),
         {:ok, ^color, ^width} <- ink(down, x1: half, y1: 0, x2: half, y2: 2 * half),
         do: {:ok, :crosshatch, color, width}
  end

  defp marks(_marks, _half), do: :error

  # A hatch's line, stroked and not filled, or its dot: its color and its width.
  defp ink(%Element{tag: :line, attrs: attrs, children: []}, at) do
    a = names(attrs)
    width = number(a["stroke-width"])

    if Enum.sort(Map.keys(a)) == ["fill", "stroke", "stroke-width", "x1", "x2", "y1", "y2"] and
         a["fill"] in ["none", :none] and is_float(width) and at?(a, at),
       do: {:ok, color_string(a["stroke"]), width},
       else: :error
  end

  defp ink(_other, _at), do: :error

  defp dot(%Element{tag: :circle, attrs: attrs, children: []}, half) do
    a = names(attrs)
    r = number(a["r"])

    if Enum.sort(Map.keys(a)) == ["cx", "cy", "fill", "r"] and is_float(r) and
         at?(a, cx: half, cy: half),
       do: {:ok, :dots, color_string(a["fill"]), r},
       else: :error
  end

  defp dot(_other, _half), do: :error

  defp at?(a, expected),
    do: Enum.all?(expected, fn {key, value} -> close?(number(a[Atom.to_string(key)]), value) end)

  defp close?(a, b) when is_number(a) and is_number(b),
    do: abs(a - b) <= 1.0e-9 * max(1.0, abs(b))

  defp close?(_a, _b), do: false

  # A color at an opacity, as `rgba()` where the opacity is not 1.
  defp fold(color, alpha) when alpha == 1.0, do: color

  defp fold(color, alpha) do
    {r, g, b, a} = Paint.rgba({0, color, alpha})
    "rgba(#{r},#{g},#{b},#{a / 255})"
  end

  defp color_string(color) when is_atom(color) and color != nil, do: Atom.to_string(color)
  defp color_string(color), do: color

  # Attributes under their SVG names (`gradient_units` and `gradientUnits` alike).
  defp names(attrs),
    do: Map.new(attrs, fn {key, value} -> {Renderer.attribute_name(key), value} end)

  defp invert({a, b, c, d, e, f}) do
    det = a * d - b * c

    if det == 0 do
      :error
    else
      {ia, ib, ic, id} = {d / det, -b / det, -c / det, a / det}
      {:ok, {ia, ib, ic, id, -(ia * e + ic * f), -(ib * e + id * f)}}
    end
  end
end
