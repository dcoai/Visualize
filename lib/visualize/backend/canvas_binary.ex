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

  The point-list record is used only for a path that is one `M` followed by `L`
  commands, and the cubic run only for one `M` followed by `C` commands — the shapes
  those records hold without loss, the run being what a curve generator emits (D-74);
  every other path is a command stream, with the smooth curves `S`/`T` expanded to
  `C`/`Q` first so the command count is exact (D-36). Both come in an f32 and an f64 form: the encoder writes the f32
  records by default, since a canvas coordinate is a pixel position and an f32 holds a
  value below 16,384 to within 2⁻¹¹ px, and `precision: :f64` selects the f64 records
  (D-73; spec/09 §4.5). Transforms fold into one matrix in SVG order. Colours are parsed
  by `Visualize.Color.parse/1`.

  ## Performance

  Binary encoding reduces payload size by ~80% compared to JSON and eliminates
  JSON parsing overhead in the browser. The browser can create typed-array views
  directly on the binary data.

  ## Requirements

  Requires the `nx` package to be installed.
  """

  alias Visualize.Backend.CanvasBinary.{Opcodes, PathEncoder, SVG}
  alias Visualize.Color
  alias Visualize.IR.{Element, Path, Transform}
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
      {:ok, do_encode_element(element, precision, %{})}
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

  defp do_encode_element(
         %Element{type: :path, path: path, style: style, transform: transform},
         precision,
         inherited
       ) do
    parts = []

    # Transform
    parts =
      if transform && transform.operations != [] do
        parts ++ [encode_transform(transform)]
      else
        parts
      end

    # Style
    parts =
      if map_size(style) > 0 do
        parts ++ [encode_style(style)]
      else
        parts
      end

    # Path data
    parts = parts ++ [do_encode_path(path.commands, precision)]

    # Draw commands
    parts = parts ++ encode_draw_commands(Map.merge(inherited, style))

    IO.iodata_to_binary(parts)
  end

  defp do_encode_element(
         %Element{type: :circle, attrs: attrs, style: style, transform: transform},
         _precision,
         inherited
       ) do
    %{cx: cx, cy: cy, r: r} = attrs

    parts = []

    parts =
      if transform && transform.operations != [] do
        parts ++ [encode_transform(transform)]
      else
        parts
      end

    parts =
      if map_size(style) > 0 do
        parts ++ [encode_style(style)]
      else
        parts
      end

    # Circle data
    parts =
      parts ++
        [
          <<Opcodes.circles()::8, 1::little-32, cx::little-float-64, cy::little-float-64,
            r::little-float-64>>
        ]

    # Draw commands
    parts = parts ++ encode_draw_commands(Map.merge(inherited, style))

    IO.iodata_to_binary(parts)
  end

  defp do_encode_element(
         %Element{type: :rect, attrs: attrs, style: style, transform: transform},
         _precision,
         inherited
       ) do
    %{x: x, y: y, width: w, height: h} = attrs

    parts = []

    parts =
      if transform && transform.operations != [] do
        parts ++ [encode_transform(transform)]
      else
        parts
      end

    parts =
      if map_size(style) > 0 do
        parts ++ [encode_style(style)]
      else
        parts
      end

    # Rect data
    parts =
      parts ++
        [
          <<Opcodes.rects()::8, 1::little-32, x::little-float-64, y::little-float-64,
            w::little-float-64, h::little-float-64>>
        ]

    # Draw commands
    parts = parts ++ encode_draw_commands(Map.merge(inherited, style))

    IO.iodata_to_binary(parts)
  end

  # A group's style is the state its children draw in, scoped by the save/restore, and
  # what they inherit for their draw records (spec/09 §4.4, D-111).
  defp do_encode_element(
         %Element{type: :group, children: children, style: style, transform: transform},
         precision,
         inherited
       ) do
    parts = [<<Opcodes.save()::8>>]

    parts =
      if transform && transform.operations != [] do
        parts ++ [encode_transform(transform)]
      else
        parts
      end

    parts = if map_size(style) > 0, do: parts ++ [encode_style(style)], else: parts

    # Encode all children
    child_data =
      Enum.map(children, &do_encode_element(&1, precision, Map.merge(inherited, style)))

    parts = parts ++ child_data

    parts = parts ++ [<<Opcodes.restore()::8>>]

    IO.iodata_to_binary(parts)
  end

  # The geometric types that are not paths are encoded as the path they are (spec/09
  # §4.4, #269): each becomes a `:path` element with the same style and transform, so it
  # takes the same record and form selection as any path.
  defp do_encode_element(%Element{type: type} = element, precision, inherited)
       when type in [:line, :polyline, :polygon, :ellipse] do
    do_encode_element(%{element | type: :path, path: as_path(element)}, precision, inherited)
  end

  defp do_encode_element(%Element{type: :root, children: children}, precision, inherited) do
    children
    |> Enum.map(&do_encode_element(&1, precision, inherited))
    |> IO.iodata_to_binary()
  end

  defp do_encode_element(_element, _precision, _inherited) do
    <<>>
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
    Enum.reduce(rest, Path.move_to(Path.new(), x, y), fn {px, py}, path ->
      Path.line_to(path, px, py)
    end)
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

  defp encode_style(style) do
    # Flags: bit 0 = has fill, bit 1 = has stroke, bit 2 = has stroke_width
    flags = 0
    parts = []

    {flags, parts} =
      case style[:fill] do
        nil ->
          {flags, parts}

        :none ->
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

        color ->
          {r, g, b, a} = parse_color(color)
          {flags ||| 0x02, parts ++ [<<r::8, g::8, b::8, a::8>>]}
      end

    {flags, parts} =
      case style[:stroke_width] do
        nil -> {flags, parts}
        w -> {flags ||| 0x04, parts ++ [<<w::little-float-32>>]}
      end

    {flags, parts} =
      case style[:opacity] do
        nil -> {flags, parts}
        o -> {flags ||| 0x08, parts ++ [<<o::little-float-32>>]}
      end

    <<Opcodes.style()::8, flags::8>> <> IO.iodata_to_binary(parts)
  end

  defp encode_draw_commands(style) do
    cmds = []

    cmds =
      case style[:fill] do
        nil -> cmds
        :none -> cmds
        _ -> cmds ++ [<<Opcodes.fill()::8>>]
      end

    cmds =
      case style[:stroke] do
        nil -> cmds
        :none -> cmds
        _ -> cmds ++ [<<Opcodes.stroke()::8>>]
      end

    cmds
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
