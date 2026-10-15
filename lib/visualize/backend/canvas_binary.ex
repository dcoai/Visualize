defmodule Visualize.Backend.CanvasBinary do
  import Bitwise

  @moduledoc """
  Binary encoding for Canvas 2D rendering commands.

  Packs an element tree into a compact little-endian stream of records that the
  `CanvasBinaryChart` hook (`Visualize.Hooks.CanvasBinary`) replays on a Canvas 2D
  context. The byte-level contract is spec/09 §4.

  ## Records

  A stream is a concatenation of records; each begins with one opcode byte from
  `Visualize.Backend.CanvasBinary.Opcodes`, which fixes its layout:

  | Name | Byte | Record |
  |---|---|---|
  | `path` | `0x01` | `count:u32` then `count` points `x:f64 y:f64` — one open polyline |
  | `path_cubic` | `0x02` | `count:u32` then `count` path commands, each a sub-opcode and its f64 arguments |
  | `circles` | `0x03` | `count:u32` then `cx:f64 cy:f64 r:f64` per circle |
  | `rects` | `0x04` | `count:u32` then `x:f64 y:f64 w:f64 h:f64` per rectangle |
  | `path32` | `0x05` | `path` with every coordinate an f32 |
  | `path_cubic32` | `0x06` | `path_cubic` with every f64 argument an f32 |
  | `cubic_run` | `0x07` | `count:u32`, the start point `x0:f32 y0:f32`, then six f32 per cubic curve, no sub-opcodes |
  | `style` | `0x10` | `flags:u8` then the fields the flags select: fill RGBA, stroke RGBA, `stroke_width:f32`, `opacity:f32` |
  | `transform` | `0x20` | `kind:u8` then `tx ty` (`0x01`), `tx ty sx sy` (`0x03`) or a full matrix `a b c d e f` (`0xFF`), all f64 |
  | `save` | `0x30` | `ctx.save()` |
  | `restore` | `0x31` | `ctx.restore()` |
  | `fill` | `0x40` | `ctx.fill()` on the current path |
  | `stroke` | `0x41` | `ctx.stroke()` on the current path |
  | `version` | `0x00` | `version:u8` — version 2 and later; first in a stream that draws a paint |
  | `paint` | `0x50` | `index:u16 kind:u8`, the geometry in box units (f32), `count:u8` stops `at:f32 r g b a` |
  | `box` | `0x51` | `x y w h` (f32): the box the next draw's paint is built over |
  | `effect` | `0x52` | `kind:u8 radius:f32`, and for a shadow `dx dy:f32` and its RGBA colour |
  | `motion` | `0x53` | `length:u16` then the UTF-8 JSON of a motion span's arguments, `[id, box, transitions]` |
  | `motion_end` | `0x54` | the motion span ends |
  | `paint_state` | `0x55` | version 3: `flags:u8`, then the fill's and the stroke's alpha (f32), the cap and the join (u8), the dash (`count:u8` and f32 lengths) the flags select |

  The point-list record is used only for a path that is one `M` followed by `L`
  commands, and the cubic run only for one `M` followed by `C` commands — the shapes
  those records hold without loss, the run being what a curve generator emits (D-74);
  every other path is a command stream, with the smooth curves `S`/`T` expanded to
  `C`/`Q` first so the command count is exact (D-36). Both come in an f32 and an f64 form: the encoder writes the f32
  records by default, since a canvas coordinate is a pixel position and an f32 holds a
  value below 16,384 to within 2⁻¹¹ px, and `precision: :f64` selects the f64 records
  (D-73; spec/09 §4.5). Transforms fold into one matrix in SVG order. Colours are parsed
  by `Visualize.Color.parse/1`.

  A stream that draws a `Visualize.IR.Paint` is **version 2** (spec/09 §4.2, D-175): it begins
  with `version` 2 and one `paint` record per distinct paint, its style records refer to a
  paint by index (bits 5 and 6), and each element drawn with one has a `box` record before
  its draws. A stream without a paint is version 1, byte for byte.

  A style that sets a paint's opacity, a cap, a join or a dash makes the stream **version 3**
  (spec/09 §4.3.17, D-180): its style record is followed by a `paint_state` record, which
  the hook keeps as state that `save` and `restore` scope. A stream without one is as it
  was.

  ## Performance

  Binary encoding reduces payload size by ~80% compared to JSON and eliminates
  JSON parsing overhead in the browser. The browser can create typed-array views
  directly on the binary data.

  ## Requirements

  Requires the `nx` package to be installed.
  """

  alias Visualize.Backend.Canvas
  alias Visualize.Backend.CanvasBinary.{Opcodes, PathEncoder, SVG}
  alias Visualize.Color
  alias Visualize.IR.{Element, Motion, Paint, Path, Transform}
  require Opcodes

  # Nx is optional: the calls below stay direct (so a missing Nx raises
  # UndefinedFunctionError at the call, spec/04 §10.1) and the compiler is told not to warn
  # about them in a consumer that never fetched it (D-50).
  @compile {:no_warn_undefined, Nx}

  @typedoc "The coordinate width of the path records: f32 by default (D-73)."
  @type precision :: :f32 | :f64

  @doc """
  Checks if Nx is available for binary encoding.
  """
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(Nx)
  end

  @doc "As `encode_path/2` with no options."
  @spec encode_path(Path.t()) :: {:ok, binary()} | {:error, :nx_not_available}
  def encode_path(%Path{} = path), do: encode_path(path, [])

  @doc """
  Encodes a path element as binary data.

  Returns `{:ok, binary}` on success or `{:error, reason}` if Nx is not available.

  ## Options

    * `:precision` - `:f32` (the default) writes the `path32`/`path_cubic32` records,
      `:f64` the `path`/`path_cubic` ones (spec/09 §4.5)
  """
  @spec encode_path(Path.t(), keyword()) :: {:ok, binary()} | {:error, :nx_not_available}
  def encode_path(%Path{commands: commands}, opts) do
    precision = precision!(opts)

    if available?() do
      {:ok, do_encode_path(commands, precision)}
    else
      {:error, :nx_not_available}
    end
  end

  @doc "As `encode_path!/2` with no options."
  @spec encode_path!(Path.t()) :: binary()
  def encode_path!(%Path{} = path), do: encode_path!(path, [])

  @doc """
  Encodes a path element as binary, raising on error. Options as `encode_path/2`.
  """
  @spec encode_path!(Path.t(), keyword()) :: binary()
  def encode_path!(%Path{} = path, opts) do
    case encode_path(path, opts) do
      {:ok, binary} -> binary
      {:error, reason} -> raise "Failed to encode path: #{reason}"
    end
  end

  @doc "As `encode_element/2` with no options."
  @spec encode_element(Element.t() | Visualize.SVG.Element.t()) ::
          {:ok, binary()} | {:error, :nx_not_available}
  def encode_element(element), do: encode_element(element, [])

  @doc """
  Encodes an element tree as binary data.

  Returns a binary blob that can be sent to the browser and decoded
  by the CanvasBinaryChart JavaScript hook.

  Accepts either Visualize.IR.Element or Visualize.SVG.Element structs. Options as
  `encode_path/2`; the precision governs every path record in the stream.
  """
  @spec encode_element(Element.t() | Visualize.SVG.Element.t(), keyword()) ::
          {:ok, binary()} | {:error, :nx_not_available}
  def encode_element(%Element{} = element, opts) do
    precision = precision!(opts)

    if available?() do
      {:ok, encode_tree(element, precision)}
    else
      {:error, :nx_not_available}
    end
  end

  def encode_element(%Visualize.SVG.Element{} = svg_element, opts) do
    precision = precision!(opts)

    if available?() do
      {:ok, SVG.encode_element(svg_element, precision)}
    else
      {:error, :nx_not_available}
    end
  end

  @doc "As `encode_element!/2` with no options."
  @spec encode_element!(Element.t() | Visualize.SVG.Element.t()) :: binary()
  def encode_element!(element), do: encode_element!(element, [])

  @doc """
  Encodes element, raising on error. Options as `encode_path/2`.
  """
  @spec encode_element!(Element.t() | Visualize.SVG.Element.t(), keyword()) :: binary()
  def encode_element!(%Element{} = element, opts) do
    case encode_element(element, opts) do
      {:ok, binary} -> binary
      {:error, reason} -> raise "Failed to encode element: #{reason}"
    end
  end

  def encode_element!(%Visualize.SVG.Element{} = svg_element, opts) do
    case encode_element(svg_element, opts) do
      {:ok, binary} -> binary
      {:error, reason} -> raise "Failed to encode SVG element: #{reason}"
    end
  end

  @doc """
  Encodes binary data as base64 for embedding in HTML attributes.
  """
  @spec to_base64(binary()) :: String.t()
  def to_base64(binary) when is_binary(binary) do
    Base.encode64(binary)
  end

  # ============================================================
  # Internal Encoding Functions
  # ============================================================

  defp precision!(opts) do
    case Keyword.get(opts, :precision, :f32) do
      p when p in [:f32, :f64] -> p
      other -> raise ArgumentError, "precision: :f32 or :f64 is needed, got: #{inspect(other)}"
    end
  end

  # The point-list record holds exactly one open polyline, so it is chosen only for one
  # `M` followed by `L` commands, and the f32 cubic run exactly one `M` followed by `C`s
  # once the smooth curves are expanded (D-74); anything else — `Z`, a second subpath,
  # `H`/`V`, a relative command, a mixed run — goes into the full command stream (D-36).
  # The precision picks the f32 or the f64 form of whichever record (D-73).
  defp do_encode_path(commands, precision) do
    if polyline?(commands) do
      encode_simple_path(Enum.map(commands, fn {_, x, y} -> {x, y} end), precision)
    else
      %Path{commands: expanded} = Path.expand_smooth(%Path{commands: commands})

      if precision == :f32 and cubic_run?(expanded),
        do: PathEncoder.encode_cubic_run(hd(expanded), tl(expanded)),
        else: PathEncoder.encode_cubic_path(expanded, precision)
    end
  end

  defp cubic_run?([{:M, _, _}, _ | _] = run),
    do: Enum.all?(tl(run), &match?({:C, _, _, _, _, _, _}, &1))

  defp cubic_run?(_), do: false

  defp polyline?([{:M, _, _} | rest]), do: Enum.all?(rest, &match?({:L, _, _}, &1))
  defp polyline?(_), do: false

  # The f64 point list is written through an Nx tensor as it always was, so its bytes are
  # unchanged; the f32 one by the binary constructor.
  defp encode_simple_path(points, :f64) do
    coords =
      points
      |> Enum.flat_map(fn {x, y} -> [x, y] end)
      |> Nx.tensor(type: :f64)
      |> Nx.to_binary()

    <<Opcodes.path()::8, length(points)::little-32, coords::binary>>
  end

  defp encode_simple_path(points, :f32), do: PathEncoder.encode_polyline(points, :f32)

  # An element that names its identity is drawn inside a motion span carrying its style's
  # transition, or a group's above it (spec/09 §4.3.15, D-176): the span's arguments as the
  # `:json` command carries them.
  defp do_encode_element(
         %Element{attrs: %{"data-vis-id" => id} = attrs} = element,
         ctx,
         inherited
       ) do
    bare = do_encode_element(%{element | attrs: Map.delete(attrs, "data-vis-id")}, ctx, inherited)

    json = Motion.json(Motion.span(id, element, Map.merge(inherited, element.style)))

    IO.iodata_to_binary([
      <<Opcodes.motion()::8, byte_size(json)::little-16>>,
      json,
      bare,
      <<Opcodes.motion_end()::8>>
    ])
  end

  defp do_encode_element(%Element{type: :path, path: path} = element, ctx, inherited),
    do: leaf(element, do_encode_path(path.commands, ctx.precision), ctx, inherited)

  defp do_encode_element(%Element{type: :circle, attrs: attrs} = element, ctx, inherited) do
    %{cx: cx, cy: cy, r: r} = attrs

    circle =
      <<Opcodes.circles()::8, 1::little-32, cx::little-float-64, cy::little-float-64,
        r::little-float-64>>

    leaf(element, circle, ctx, inherited)
  end

  defp do_encode_element(%Element{type: :rect, attrs: attrs} = element, ctx, inherited) do
    %{x: x, y: y, width: w, height: h} = attrs

    rect =
      <<Opcodes.rects()::8, 1::little-32, x::little-float-64, y::little-float-64,
        w::little-float-64, h::little-float-64>>

    leaf(element, rect, ctx, inherited)
  end

  # A group's style is the state its children draw in, scoped by the save/restore, and
  # what they inherit for their draw records (spec/09 §4.4, D-111).
  defp do_encode_element(
         %Element{type: :group, children: children, style: style, transform: transform},
         ctx,
         inherited
       ) do
    parts = [<<Opcodes.save()::8>>]

    parts =
      if transform && transform.operations != [] do
        parts ++ [encode_transform(transform)]
      else
        parts
      end

    parts = if map_size(style) > 0, do: parts ++ [encode_style(style, ctx.paints)], else: parts

    # Encode all children
    child_data =
      Enum.map(children, &do_encode_element(&1, ctx, Map.merge(inherited, style)))

    parts = parts ++ child_data

    parts = parts ++ [<<Opcodes.restore()::8>>]

    IO.iodata_to_binary(parts)
  end

  # The geometric types that are not paths are encoded as the path they are (spec/09
  # §4.4, #269): each becomes a `:path` element with the same style and transform, so it
  # takes the same record and form selection as any path.
  defp do_encode_element(%Element{type: type} = element, ctx, inherited)
       when type in [:line, :polyline, :polygon, :ellipse] do
    do_encode_element(%{element | type: :path, path: as_path(element)}, ctx, inherited)
  end

  defp do_encode_element(%Element{type: :root, children: children}, ctx, inherited) do
    children
    |> Enum.map(&do_encode_element(&1, ctx, inherited))
    |> IO.iodata_to_binary()
  end

  defp do_encode_element(_element, _ctx, _inherited) do
    <<>>
  end

  # A leaf: its transform and its style record, its geometry, and the draw records of its
  # effective style. A leaf that writes a transform or a style is drawn inside save and
  # restore, so its next sibling draws in its parent's state as SVG draws it; a leaf that
  # writes neither pays nothing (spec/09 §4.4, #679, D-179).
  defp leaf(%Element{style: style, transform: transform} = element, geometry, ctx, inherited) do
    transform =
      if transform && transform.operations != [], do: [encode_transform(transform)], else: []

    setup = transform ++ if(map_size(style) > 0, do: [encode_style(style, ctx.paints)], else: [])
    body = [geometry | draw_records(Map.merge(inherited, style), element, ctx)]

    case setup do
      [] -> IO.iodata_to_binary(body)
      setup -> IO.iodata_to_binary([<<Opcodes.save()::8>>, setup, body, <<Opcodes.restore()::8>>])
    end
  end

  # A line is a two-point path; a polyline a move and its lines; a polygon the same,
  # closed; an ellipse four cubic quarter-arcs with the control distance κ of each radius.
  @kappa 0.5522847

  defp as_path(%Element{type: :line, attrs: %{x1: x1, y1: y1, x2: x2, y2: y2}}),
    do: Path.new() |> Path.move_to(x1, y1) |> Path.line_to(x2, y2)

  defp as_path(%Element{type: :polyline, attrs: %{points: points}}), do: polyline(points)

  defp as_path(%Element{type: :polygon, attrs: %{points: points}}),
    do: points |> polyline() |> Path.close()

  defp as_path(%Element{type: :ellipse, attrs: %{cx: cx, cy: cy, rx: rx, ry: ry}}) do
    kx = rx * @kappa
    ky = ry * @kappa

    Path.new()
    |> Path.move_to(cx + rx, cy)
    |> Path.curve_to(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry)
    |> Path.curve_to(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy)
    |> Path.curve_to(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry)
    |> Path.curve_to(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy)
    |> Path.close()
  end

  defp as_path(_element), do: Path.new()

  defp polyline([]), do: Path.new()

  defp polyline([{x, y} | rest]) do
    Path.from_commands([{:M, x, y} | for({px, py} <- rest, do: {:L, px, py})])
  end

  # The two compact kinds cover the common cases exactly; everything else folds into one
  # matrix with SVG composition order (`Visualize.IR.Transform.to_matrix/1`).
  defp encode_transform(%Transform{operations: ops} = transform) do
    case ops do
      [{:translate, x, y}] ->
        <<Opcodes.transform()::8, 0x01::8, x * 1.0::little-float-64, y * 1.0::little-float-64>>

      [{:translate, x, y}, {:scale, sx, sy}] ->
        <<Opcodes.transform()::8, 0x03::8, x * 1.0::little-float-64, y * 1.0::little-float-64,
          sx * 1.0::little-float-64, sy * 1.0::little-float-64>>

      _ ->
        {a, b, c, d, e, f} = Transform.to_matrix(transform)

        <<Opcodes.transform()::8, 0xFF::8, a::little-float-64, b::little-float-64,
          c::little-float-64, d::little-float-64, e::little-float-64, f::little-float-64>>
    end
  end

  defp encode_style(style, paints) do
    # Flags: bit 0 = has fill, bit 1 = has stroke, bit 2 = has stroke_width, bit 3 = has
    # opacity, bit 4 = the stroke width does not scale; version 2: bit 5 = the fill is a
    # paint, bit 6 = the stroke is one, each an index after the four fields above
    flags = 0
    parts = []

    {flags, parts} =
      case style[:fill] do
        nil ->
          {flags, parts}

        :none ->
          {flags, parts}

        %Paint{} ->
          {flags, parts}

        color ->
          {r, g, b, a} = parse_color(color)
          {flags ||| 0x01, parts ++ [<<r::8, g::8, b::8, a::8>>]}
      end

    {flags, parts} =
      case style[:stroke] do
        nil ->
          {flags, parts}

        :none ->
          {flags, parts}

        %Paint{} ->
          {flags, parts}

        color ->
          {r, g, b, a} = parse_color(color)
          {flags ||| 0x02, parts ++ [<<r::8, g::8, b::8, a::8>>]}
      end

    # Bit 4: the width does not scale (spec/09 §4.3.5, spec/14 §3.9).
    {flags, parts} =
      case {style[:stroke_width], style[:vector_effect]} do
        {nil, _effect} -> {flags, parts}
        {w, :non_scaling_stroke} -> {flags ||| 0x14, parts ++ [<<w::little-float-32>>]}
        {w, _effect} -> {flags ||| 0x04, parts ++ [<<w::little-float-32>>]}
      end

    {flags, parts} =
      case style[:opacity] do
        nil -> {flags, parts}
        o -> {flags ||| 0x08, parts ++ [<<o::little-float-32>>]}
      end

    {flags, parts} = paint_field(style[:fill], 0x20, paints, {flags, parts})
    {flags, parts} = paint_field(style[:stroke], 0x40, paints, {flags, parts})

    <<Opcodes.style()::8, flags::8>> <>
      IO.iodata_to_binary(parts) <> effect_record(style) <> paint_state_record(style)
  end

  # Version 2: a shadow's radius, offset and colour, or a blur's radius, after the style record
  # (spec/09 §4.3.14, #674); the offset and colour default as the canvas commands' do.
  defp effect_record(%{effect: :shadow} = style) do
    r = style[:effect_radius] || 3
    [dx, dy] = style[:effect_offset] || [r / 2, r / 2]
    {cr, cg, cb, ca} = if c = style[:effect_color], do: Paint.rgba({0, c, 1}), else: {0, 0, 0, 89}

    <<Opcodes.effect()::8, 0x01::8, r::little-float-32, dx::little-float-32, dy::little-float-32,
      cr::8, cg::8, cb::8, ca::8>>
  end

  defp effect_record(%{effect: :blur} = style),
    do: <<Opcodes.effect()::8, 0x02::8, style[:effect_radius] || 3::little-float-32>>

  defp effect_record(_style), do: <<>>

  @caps %{butt: 0, round: 1, square: 2}
  @joins %{miter: 0, round: 1, bevel: 2}

  # Version 3: what a fill or a stroke paints with beyond the style record — each paint's
  # own opacity, the cap, the join and the dash — after the style record, each field under
  # its flag bit (spec/09 §4.3.17, #675, D-180); nothing for a style that sets none.
  defp paint_state_record(style) do
    fields = [
      {0x01, alpha(style[:fill_opacity])},
      {0x02, alpha(style[:stroke_opacity])},
      {0x04, with(c when is_integer(c) <- Map.get(@caps, style[:stroke_linecap]), do: <<c::8>>)},
      {0x08,
       with(j when is_integer(j) <- Map.get(@joins, style[:stroke_linejoin]), do: <<j::8>>)},
      {0x10, dash(Canvas.dash(style[:stroke_dasharray]))}
    ]

    case for {bit, bytes} <- fields, is_binary(bytes), do: {bit, bytes} do
      [] ->
        <<>>

      set ->
        flags = Enum.reduce(set, 0, fn {bit, _}, acc -> acc ||| bit end)

        IO.iodata_to_binary([
          <<Opcodes.paint_state()::8, flags::8>> | Enum.map(set, &elem(&1, 1))
        ])
    end
  end

  defp alpha(a) when is_number(a), do: <<a::little-float-32>>
  defp alpha(_absent), do: nil

  defp dash(pattern) when is_list(pattern) and length(pattern) < 256,
    do:
      IO.iodata_to_binary([<<length(pattern)::8>> | Enum.map(pattern, &<<&1::little-float-32>>)])

  defp dash(_absent), do: nil

  # Whether a tree's styles set what only a `paint_state` record carries.
  defp paint_state?(%Element{style: style, children: children}),
    do: paint_state_record(style) != <<>> or Enum.any?(children, &paint_state?/1)

  # The draw records of an element under its effective style, with the box its paints are
  # built over first when it draws one (spec/09 §4.3.13).
  defp draw_records(style, element, _ctx) do
    fill = style[:fill] not in [nil, :none]
    stroke = style[:stroke] not in [nil, :none]

    box =
      if is_struct(style[:fill], Paint) or is_struct(style[:stroke], Paint),
        do: [box_record(Paint.bounds(element))],
        else: []

    box ++
      if(fill, do: [<<Opcodes.fill()::8>>], else: []) ++
      if(stroke, do: [<<Opcodes.stroke()::8>>], else: [])
  end

  defp box_record({x, y, w, h}),
    do:
      <<Opcodes.box()::8, x::little-float-32, y::little-float-32, w::little-float-32,
        h::little-float-32>>

  defp box_record(nil), do: box_record({0, 0, 0, 0})

  # A paint in the style record (bit 5 for the fill, 6 for the stroke): its index among the
  # stream's paints (spec/09 §4.3.5).
  defp paint_field(%Paint{} = paint, bit, paints, {flags, parts}),
    do: {flags ||| bit, parts ++ [<<Map.fetch!(paints, paint)::little-16>>]}

  defp paint_field(_colour, _bit, _paints, acc), do: acc

  # -- version 2: the stream's paints -----------------------------------------------------

  # The tree's records, after a `version` 2 record and one `paint` record per distinct paint
  # when its styles hold any (spec/09 §4.2, §4.4, D-175); a tree without one is a version 1
  # stream, byte for byte.
  defp encode_tree(element, precision) do
    paints = element |> paints() |> Enum.uniq() |> Enum.with_index()
    ctx = %{precision: precision, paints: Map.new(paints)}
    body = do_encode_element(element, ctx, %{})

    # The least version whose records the stream uses (spec/09 §4.2): 3 with a paint's
    # state (D-180), 2 with a paint, an effect or a motion span (D-175), else 1.
    version =
      cond do
        paint_state?(element) -> 3
        paints != [] or effects?(element) or spans?(element) -> 2
        true -> 1
      end

    case version do
      1 ->
        body

      version ->
        IO.iodata_to_binary([
          <<Opcodes.version()::8, version::8>>,
          Enum.map(paints, &paint_record/1),
          body
        ])
    end
  end

  defp effects?(%Element{style: style, children: children}),
    do: style[:effect] in [:shadow, :blur] or Enum.any?(children, &effects?/1)

  # Whether the tree draws a motion span (spec/09 §4.3.15): an element naming its identity.
  defp spans?(%Element{attrs: attrs, children: children}),
    do: Map.has_key?(attrs, "data-vis-id") or Enum.any?(children, &spans?/1)

  defp paints(%Element{style: style, children: children}) do
    Enum.filter([style[:fill], style[:stroke]], &is_struct(&1, Paint)) ++
      Enum.flat_map(children, &paints/1)
  end

  # A hatch (#673): the pattern, the angle, spacing and width, then its colour and its ground,
  # a ground of alpha 0 being none; no stops.
  defp paint_record({%Paint{type: :hatch, geometry: g} = paint, index}) do
    pattern = Map.fetch!(%{lines: 0x01, crosshatch: 0x02, dots: 0x03}, g.pattern)
    {r, gr, b, a} = Paint.rgba({0, paint.color, 1})

    {br, bg, bb, ba} =
      if paint.background, do: Paint.rgba({0, paint.background, 1}), else: {0, 0, 0, 0}

    <<Opcodes.paint()::8, index::little-16, 0x03::8, pattern::8, g.angle::little-float-32,
      g.spacing::little-float-32, g.width::little-float-32, r::8, gr::8, b::8, a::8, br::8, bg::8,
      bb::8, ba::8>>
  end

  defp paint_record({%Paint{type: type, geometry: g} = paint, index}) do
    {kind, geometry} =
      case type do
        :linear -> {0x01, [g.x1, g.y1, g.x2, g.y2]}
        :radial -> {0x02, [g.cx, g.cy, g.r]}
      end

    stops =
      for {at, _colour, _opacity} = stop <- paint.stops do
        {r, gr, b, a} = Paint.rgba(stop)
        <<at::little-float-32, r::8, gr::8, b::8, a::8>>
      end

    [
      <<Opcodes.paint()::8, index::little-16, kind::8>>,
      Enum.map(geometry, &<<&1::little-float-32>>),
      <<length(stops)::8>>,
      stops
    ]
  end

  # Every colour syntax `Visualize.Color.parse/1` knows — hex, `rgb()`/`rgba()`, `hsl()`
  # and the CSS names — to RGBA bytes; anything it cannot parse is opaque black.
  defp parse_color(color) when is_binary(color) do
    case Color.parse(color) do
      %Color{} = parsed ->
        {r, g, b, a} = Color.to_rgba(parsed)
        {r, g, b, round(a * 255)}

      nil ->
        {0, 0, 0, 255}
    end
  end

  defp parse_color(_), do: {0, 0, 0, 255}
end
