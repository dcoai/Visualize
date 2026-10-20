defmodule Visualize.Backend.Canvas.Output do
  @moduledoc false
  # The `:js` and `:json` serializers of `Visualize.Backend.Canvas`'s command list (spec/09
  # §3), and the hatch pattern source the hooks share. `Canvas` translates elements into
  # commands; this module only writes them out.

  alias Visualize.IR.{Motion, Path}

  @doc false
  # A command list in the requested output: as it is, a `:js` script or a `:json` array.
  @spec format_output([tuple()], :commands | :js | :json) :: iolist() | [tuple()]
  def format_output(commands, :commands), do: commands
  def format_output(commands, :js), do: commands_to_js(commands)
  def format_output(commands, :json), do: commands_to_json(commands)

  # A script runs with no library beside it to move an element: it draws the end state, and
  # a motion span writes nothing (spec/09 §3.4).
  @doc false
  @spec commands_to_js([tuple()]) :: iolist()
  def commands_to_js(commands) do
    commands
    |> Enum.reject(fn {cmd, _args} -> cmd in [:motion, :motionEnd] end)
    |> Enum.map(&command_to_js_line/1)
    |> Enum.intersperse("\n")
  end

  defp command_to_js_line({:set_fillStyle, [color]}), do: ["ctx.fillStyle = '", color, "';"]
  defp command_to_js_line({:set_strokeStyle, [color]}), do: ["ctx.strokeStyle = '", color, "';"]
  defp command_to_js_line({:set_lineWidth, [w]}), do: ["ctx.lineWidth = ", format_num(w), ";"]

  defp command_to_js_line({:nonScalingLineWidth, [w]}) do
    [
      "ctx.lineWidth = ",
      format_num(w),
      " / (function(t){return Math.sqrt(Math.abs(t.a*t.d-t.b*t.c));})(ctx.getTransform());"
    ]
  end

  # A gradient as one self-contained statement (spec/09 §3.4): a `:js` script runs with no
  # library beside it.
  defp command_to_js_line({:linearGradient, [target, x0, y0, x1, y1, stops]}),
    do: gradient_js(target, ["ctx.createLinearGradient(", js_args([x0, y0, x1, y1]), ")"], stops)

  defp command_to_js_line({:radialGradient, [target, cx, cy, r, stops]}),
    do:
      gradient_js(
        target,
        ["ctx.createRadialGradient(", js_args([cx, cy, 0, cx, cy, r]), ")"],
        stops
      )

  defp command_to_js_line({:hatchPattern, [target | args]}),
    do: [
      "ctx.",
      target,
      "Style = (",
      hatch_js(),
      ")(ctx, ",
      Enum.map_intersperse(args, ", ", &js_value/1),
      ");"
    ]

  defp command_to_js_line({:set_lineCap, [cap]}), do: ["ctx.lineCap = '", cap, "';"]
  defp command_to_js_line({:set_lineJoin, [join]}), do: ["ctx.lineJoin = '", join, "';"]

  defp command_to_js_line({:setLineDash, [pattern]}),
    do: ["ctx.setLineDash([", js_args(pattern), "]);"]

  defp command_to_js_line({:set_globalAlpha, [a]}), do: ["ctx.globalAlpha = ", format_num(a), ";"]

  defp command_to_js_line({:set_globalCompositeOperation, [op]}),
    do: ["ctx.globalCompositeOperation = '", op, "';"]

  defp command_to_js_line({:set_shadowColor, [c]}), do: ["ctx.shadowColor = '", c, "';"]
  defp command_to_js_line({:set_shadowBlur, [r]}), do: ["ctx.shadowBlur = ", format_num(r), ";"]

  defp command_to_js_line({:set_shadowOffsetX, [x]}),
    do: ["ctx.shadowOffsetX = ", format_num(x), ";"]

  defp command_to_js_line({:set_shadowOffsetY, [y]}),
    do: ["ctx.shadowOffsetY = ", format_num(y), ";"]

  defp command_to_js_line({:set_filter, [f]}), do: ["ctx.filter = '", f, "';"]
  defp command_to_js_line({:set_font, [font]}), do: ["ctx.font = '", escape_js(font), "';"]
  defp command_to_js_line({:set_textAlign, [align]}), do: ["ctx.textAlign = '", align, "';"]
  defp command_to_js_line({:beginPath, []}), do: "ctx.beginPath();"
  defp command_to_js_line({:closePath, []}), do: "ctx.closePath();"

  defp command_to_js_line({:moveTo, [x, y]}),
    do: ["ctx.moveTo(", format_num(x), ", ", format_num(y), ");"]

  defp command_to_js_line({:lineTo, [x, y]}),
    do: ["ctx.lineTo(", format_num(x), ", ", format_num(y), ");"]

  defp command_to_js_line({:bezierCurveTo, [x1, y1, x2, y2, x, y]}) do
    [
      "ctx.bezierCurveTo(",
      format_num(x1),
      ", ",
      format_num(y1),
      ", ",
      format_num(x2),
      ", ",
      format_num(y2),
      ", ",
      format_num(x),
      ", ",
      format_num(y),
      ");"
    ]
  end

  defp command_to_js_line({:quadraticCurveTo, [x1, y1, x, y]}) do
    [
      "ctx.quadraticCurveTo(",
      format_num(x1),
      ", ",
      format_num(y1),
      ", ",
      format_num(x),
      ", ",
      format_num(y),
      ");"
    ]
  end

  defp command_to_js_line({:arc, args}) do
    formatted = Enum.map(args, &format_num/1) |> Enum.intersperse(", ")
    ["ctx.arc(", formatted, ");"]
  end

  defp command_to_js_line({:ellipse, args}) do
    formatted = Enum.map(args, &format_num/1) |> Enum.intersperse(", ")
    ["ctx.ellipse(", formatted, ");"]
  end

  defp command_to_js_line({:rect, [x, y, w, h]}) do
    [
      "ctx.rect(",
      format_num(x),
      ", ",
      format_num(y),
      ", ",
      format_num(w),
      ", ",
      format_num(h),
      ");"
    ]
  end

  defp command_to_js_line({:fill, []}), do: "ctx.fill();"
  defp command_to_js_line({:stroke, []}), do: "ctx.stroke();"
  defp command_to_js_line({:save, []}), do: "ctx.save();"
  defp command_to_js_line({:clip, []}), do: "ctx.clip();"
  defp command_to_js_line({:clip, [rule]}), do: ["ctx.clip('", rule, "');"]
  defp command_to_js_line({:restore, []}), do: "ctx.restore();"

  defp command_to_js_line({:translate, [x, y]}),
    do: ["ctx.translate(", format_num(x), ", ", format_num(y), ");"]

  defp command_to_js_line({:rotate, [angle]}), do: ["ctx.rotate(", format_num(angle), ");"]

  defp command_to_js_line({:rotate_around, [angle, cx, cy]}) do
    [
      "ctx.translate(",
      format_num(cx),
      ", ",
      format_num(cy),
      "); ctx.rotate(",
      format_num(angle),
      "); ctx.translate(",
      format_num(-cx),
      ", ",
      format_num(-cy),
      ");"
    ]
  end

  defp command_to_js_line({:scale, [sx, sy]}),
    do: ["ctx.scale(", format_num(sx), ", ", format_num(sy), ");"]

  defp command_to_js_line({:transform, [a, b, c, d, e, f]}) do
    [
      "ctx.transform(",
      format_num(a),
      ", ",
      format_num(b),
      ", ",
      format_num(c),
      ", ",
      format_num(d),
      ", ",
      format_num(e),
      ", ",
      format_num(f),
      ");"
    ]
  end

  defp command_to_js_line({:fillText, [text, x, y]}) do
    ["ctx.fillText('", escape_js(text || ""), "', ", format_num(x), ", ", format_num(y), ");"]
  end

  # An image loads asynchronously: the draw runs in `onload`, at the transform current
  # when the statement executed.
  defp command_to_js_line({:drawImage, [href, x, y, w, h]}) do
    [
      "(function(){var img=new Image();var t=ctx.getTransform();",
      "img.onload=function(){ctx.save();ctx.setTransform(t);ctx.drawImage(img, ",
      format_num(x),
      ", ",
      format_num(y),
      ", ",
      format_num(w),
      ", ",
      format_num(h),
      ");ctx.restore();};img.src='",
      escape_js(href),
      "';})();"
    ]
  end

  defp gradient_js(target, create, stops) do
    adds =
      Enum.map(stops, fn [at, color] ->
        ["g.addColorStop(", format_num(at), ", '", escape_js(color), "');"]
      end)

    ["ctx.", target, "Style = (function(g){", adds, "return g;})(", create, ");"]
  end

  defp js_value(nil), do: "null"
  defp js_value(v) when is_binary(v), do: ["'", escape_js(v), "'"]
  defp js_value(v), do: format_num(v)

  @doc false
  # The one source of a hatch's CanvasPattern (spec/09 §3.3.3, #673), written into a `:js`
  # script and into the hooks' `visualizePattern`: a tile `n = ⌈4·spacing⌉` pixels square,
  # scaled to one period, holding the ground and the lines or the dot, and the pattern's
  # transform `rotate(angle) · scale(spacing / n)`.
  @spec hatch_js() :: String.t()
  def hatch_js do
    "function(ctx, pattern, angle, s, w, color, background) {" <>
      "var n = Math.max(1, Math.ceil(4 * s)), tile = document.createElement('canvas');" <>
      "tile.width = n; tile.height = n; var t = tile.getContext('2d'); t.scale(n / s, n / s);" <>
      "if (background) { t.fillStyle = background; t.fillRect(0, 0, s, s); }" <>
      "t.strokeStyle = color; t.fillStyle = color; t.lineWidth = w; t.beginPath();" <>
      "if (pattern === 'dots') { t.arc(s / 2, s / 2, w, 0, 2 * Math.PI); t.fill(); } else {" <>
      "t.moveTo(0, s / 2); t.lineTo(s, s / 2);" <>
      "if (pattern === 'crosshatch') { t.moveTo(s / 2, 0); t.lineTo(s / 2, s); } t.stroke(); }" <>
      "var p = ctx.createPattern(tile, 'repeat'), a = angle * Math.PI / 180, k = s / n;" <>
      "p.setTransform({a: Math.cos(a) * k, b: Math.sin(a) * k, c: -Math.sin(a) * k, d: Math.cos(a) * k, e: 0, f: 0});" <>
      "return p; }"
  end

  defp js_args(args), do: args |> Enum.map(&format_num/1) |> Enum.intersperse(", ")

  @doc false
  # The `:json` output's commands without the brackets around them: what a segment of the
  # stream carries (spec/09 §1.4, #813), `[]` for none.
  @spec json_items([tuple()]) :: iolist()
  def json_items(commands),
    do:
      commands
      |> Enum.map(fn {cmd, args} -> %{cmd: Atom.to_string(cmd), args: args} end)
      |> encode_json_array()

  @doc false
  @spec commands_to_json([tuple()]) :: iolist()
  def commands_to_json(commands) do
    encoded =
      commands
      |> Enum.map(fn {cmd, args} ->
        %{cmd: Atom.to_string(cmd), args: args}
      end)

    # Simple JSON encoding without external deps
    ["[", encode_json_array(encoded), "]"]
  end

  defp encode_json_array([]), do: ""

  defp encode_json_array(items) do
    items
    |> Enum.map(&encode_json_object/1)
    |> Enum.intersperse(",")
  end

  # A span's arguments are nested lists whose strings are a datum's: `Visualize.IR.Motion`
  # writes them, every character escaped, the text the binary record carries too.
  defp encode_json_object(%{cmd: "motion", args: args}),
    do: ["{\"cmd\":\"motion\",\"args\":", Motion.json(args), "}"]

  defp encode_json_object(%{cmd: cmd, args: args}) do
    args_json =
      args
      |> Enum.map(&encode_json_value/1)
      |> Enum.intersperse(",")

    ["{\"cmd\":\"", cmd, "\",\"args\":[", args_json, "]}"]
  end

  defp encode_json_value(nil), do: "null"
  defp encode_json_value(v) when is_binary(v), do: ["\"", escape_json_string(v), "\""]
  defp encode_json_value(v) when is_number(v), do: format_num(v)
  defp encode_json_value(v) when is_boolean(v), do: Atom.to_string(v)
  defp encode_json_value(v) when is_atom(v), do: ["\"", Atom.to_string(v), "\""]

  defp encode_json_value(v) when is_list(v),
    do: ["[", v |> Enum.map(&encode_json_value/1) |> Enum.intersperse(","), "]"]

  defp encode_json_value(v), do: ["\"", to_string(v), "\""]

  # A string with nothing to escape, nearly every one a stream carries, is written as it is.
  defp escape_json_string(str) do
    case :binary.match(str, ["\\", "\"", "\n", "\r", "\t"]) do
      :nomatch -> str
      _found -> escape_json_chars(str)
    end
  end

  defp escape_json_chars(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  # A string in a single-quoted JavaScript literal (spec/14 §10.3, #660): its quote, the
  # escape, every line break and `<`, so a design's text never ends the literal, the line
  # or a `</script>` around the program.
  defp escape_js(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\u2028", "\\u2028")
    |> String.replace("\u2029", "\\u2029")
    |> String.replace("<", "\\x3c")
  end

  # The one number formatter of every serializer (spec/09 §1.3, D-12, D-32).
  defp format_num(n) when is_number(n), do: Path.format_number(n)

  defp format_num(n) when is_boolean(n), do: Atom.to_string(n)
end
