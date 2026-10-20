defmodule Visualize.Chart.Frame.Cull do
  @moduledoc false
  # What a clipped frame cannot show, left out before it is drawn (spec/14 §4.1, #839). A
  # frame with `clip: true` draws each mark inside a clip to its plot area, and a mark that
  # reaches far past the plot — the whole course of a route under an inset zoomed in on a
  # mile of it — would otherwise be built, serialized and sent whole every tick, to be
  # clipped away by the renderer.
  #
  # The cull is exact for the picture: it removes only what lies wholly beyond the plot by
  # more than its stroke can reach, so the clipped drawing is pixel for pixel what it was.
  #
  #   * A path's runs of points beyond one edge keep their first and last point. The
  #     segment that crosses into the plot on each side, and the join at its inner end,
  #     are unchanged; between the two kept points one segment lies beyond that same edge,
  #     since a segment between two points beyond an edge is beyond it too. A fill loses
  #     only area beyond the edge, the region between the run and that chord.
  #   * An element whose box, widened by its stroke's reach, lies wholly outside the plot
  #     is dropped: a point, a marker, a shape, a label, a whole path.
  #
  # What it cannot bound safely it keeps as it is: an element under a transform other than
  # a translation, one with an effect (a shadow or blur reaches past the box), one whose
  # stroke width or font size is not a number (a theme slot's `var(--name, Npx)`, which a
  # stylesheet may set to anything, among them), a moving mark's element (`data-vis-id`,
  # whose motion keys by it and would enter rather than move in across the edge), and a
  # path whose paint is a gradient or a pattern, laid over its box, which a changed box
  # would move. Such a path may still be dropped whole.

  alias Visualize.IR.{Element, Paint, Path, Transform}

  # One pixel more than the geometry needs, against antialiasing at the edge.
  @slack 1

  @typedoc "The plot area in the mark's coordinates, `{x, y, width, height}`."
  @type rect :: {number(), number(), number(), number()}

  @doc false
  # The mark's group with what cannot reach `rect` left out.
  @spec cull(Element.t(), rect()) :: Element.t()
  def cull(%Element{} = element, {x, y, w, h}) do
    case visit(element, {x, y, x + w, y + h}, {0, 0}, %{}) do
      nil -> %{element | children: []}
      kept -> kept
    end
  end

  # An element, its translation so far and the style it inherits: `nil` to drop it.
  defp visit(%Element{} = element, edges, offset, inherited) do
    style = Map.merge(inherited, element.style || %{})

    with {:ok, offset} <- translated(element.transform, offset),
         false <- moving?(element),
         false <- effect?(style) do
      shape(element, edges, offset, style)
    else
      _cannot_bound -> element
    end
  end

  defp shape(%Element{type: :group, children: children} = group, edges, offset, style) do
    %{
      group
      | children: for(child <- children, kept = visit(child, edges, offset, style), do: kept)
    }
  end

  defp shape(%Element{type: :text} = text, edges, offset, style) do
    with box when box != nil <- text_box(text, style),
         m when is_number(m) <- reach(style),
         true <- outside?(box, edges, offset, m) do
      nil
    else
      _inside_or_unbounded -> text
    end
  end

  defp shape(%Element{type: :path, path: %Path{} = path} = element, edges, offset, style) do
    case reach(style) do
      nil -> element
      m -> path(element, absolute(path), edges, offset, m, style)
    end
  end

  defp shape(%Element{} = element, edges, offset, style) do
    with m when is_number(m) <- reach(style),
         box when box != nil <- Paint.bounds(element),
         true <- outside?(box, edges, offset, m) do
      nil
    else
      _inside_or_unbounded -> element
    end
  end

  # -- paths ----------------------------------------------------------------------------

  # A path of moves and lines alone is cut in one pass: dropped when every point lies
  # beyond one common edge, else its runs cut. Any other path — curves, arcs — is dropped
  # when its box is outside and otherwise kept as it is.
  defp path(element, commands, edges, offset, m, style) do
    if Enum.all?(commands, &line?/1) do
      codes = Enum.map(commands, &code(&1, edges, offset, m))

      cond do
        codes
        |> Enum.zip(commands)
        |> Enum.reject(&(elem(&1, 1) == :Z))
        |> Enum.reduce(15, fn {c, _}, mask -> band(mask, c) end) != 0 ->
          nil

        laid_over_box?(style) ->
          element

        true ->
          cut(element, commands, codes)
      end
    else
      box = Paint.bounds(element)
      if box != nil and outside?(box, edges, offset, m), do: nil, else: element
    end
  end

  # A path's commands made absolute, unless they are already moves, lines and closes.
  defp absolute(%Path{commands: commands} = path) do
    if Enum.all?(commands, &line?/1), do: commands, else: Path.absolute(path).commands
  end

  defp line?({:M, _, _}), do: true
  defp line?({:L, _, _}), do: true
  defp line?(:Z), do: true
  defp line?(_other), do: false

  # The path with every run of lines beyond one edge cut to its two ends: from a kept
  # point, the following points that all lie, with it, beyond one common edge make a run;
  # its last point is kept and the ones between go. The path as it was when nothing goes,
  # so its markup is unchanged.
  defp cut(%Element{path: path} = element, commands, codes) do
    kept = walk(Enum.zip(commands, codes), 0, [], [])

    if length(kept) == length(commands),
      do: element,
      else: %{element | path: %{path | commands: kept}}
  end

  # `mask`, the edges the kept point and the run so far share; `run`, the run's lines,
  # reversed; `acc`, the kept commands, reversed.
  defp walk([], _mask, run, acc), do: Enum.reverse(flush(run, acc))

  defp walk([{{:L, _, _} = line, c} | rest], mask, run, acc) do
    cond do
      band(mask, c) != 0 ->
        walk(rest, band(mask, c), [{line, c} | run], acc)

      run == [] ->
        walk(rest, c, [], [line | acc])

      true ->
        # The run ends at its last point, which is kept and starts the next one.
        [{_last, last_c} | _] = run
        walk([{line, c} | rest], last_c, [], flush(run, acc))
    end
  end

  # A move starts afresh from its own point; a close returns to a point not tracked here,
  # so nothing runs across it.
  defp walk([{{:M, _, _} = move, c} | rest], _mask, run, acc),
    do: walk(rest, c, [], [move | flush(run, acc)])

  defp walk([{:Z, _c} | rest], _mask, run, acc), do: walk(rest, 0, [], [:Z | flush(run, acc)])

  # A run of two or more is its last line; a run of one is that line.
  defp flush([], acc), do: acc
  defp flush([{last, _c} | _], acc), do: [last | acc]

  defp band(a, b), do: Bitwise.band(a, b)

  # Which edges a command's point lies beyond by more than `m`: left 1, right 2, top 4,
  # bottom 8; a close has none of its own.
  defp code(:Z, _edges, _offset, _m), do: 0

  defp code({_cmd, x, y}, {x0, y0, x1, y1}, {dx, dy}, m) do
    m = m + @slack
    {x, y} = {x + dx, y + dy}

    if(x < x0 - m, do: 1, else: 0) + if(x > x1 + m, do: 2, else: 0) +
      if(y < y0 - m, do: 4, else: 0) + if(y > y1 + m, do: 8, else: 0)
  end

  # -- boxes ----------------------------------------------------------------------------

  defp outside?({bx, by, bw, bh}, {x0, y0, x1, y1}, {dx, dy}, m) do
    m = m + @slack
    left = bx + dx
    top = by + dy
    left + bw < x0 - m or left > x1 + m or top + bh < y0 - m or top > y1 + m
  end

  # How far past its geometry an element paints: nothing without a stroke; with one, twice
  # its width, which a miter join at SVG's default limit of 4 can reach. `nil` when the
  # width is not a number to reason from.
  defp reach(style) do
    case {Map.get(style, :stroke), Map.get(style, :stroke_width, 1)} do
      {stroke, _width} when stroke in [nil, :none, "none"] -> 0
      {_stroke, width} when is_number(width) -> 2 * width
      _unknown -> nil
    end
  end

  # A text's box, generous on every side: as wide as an em a character either way of its
  # point whatever its anchor, and a line and a half an em per line above and below it
  # besides one more each way for a `dy`. `nil` when its point or size is not a number.
  defp text_box(%Element{attrs: attrs} = text, style) do
    with x when is_number(x) <- Map.get(attrs, :x),
         y when is_number(y) <- Map.get(attrs, :y),
         size when is_number(size) <- Map.get(style, :font_size, 16) do
      chars = text |> content() |> String.length()
      lines = max(1, Enum.count(text.children, &(&1.type == :tspan)))
      across = (chars + 2) * size
      down = (lines + 1) * 1.5 * size
      {x - across, y - down, 2 * across, 2 * down}
    else
      _not_a_number -> nil
    end
  end

  defp content(%Element{content: content, children: children}),
    do: (content || "") <> Enum.map_join(children, "", &content/1)

  # -- what is not culled ----------------------------------------------------------------

  # The offset a translation adds, `:error` for any other transform.
  defp translated(nil, offset), do: {:ok, offset}

  defp translated(%Transform{operations: operations}, offset) do
    Enum.reduce_while(operations, {:ok, offset}, fn
      {:translate, tx, ty}, {:ok, {dx, dy}} when is_number(tx) and is_number(ty) ->
        {:cont, {:ok, {dx + tx, dy + ty}}}

      _other, _acc ->
        {:halt, :error}
    end)
  end

  defp moving?(%Element{attrs: attrs}), do: Map.has_key?(attrs, "data-vis-id")

  defp effect?(style), do: Map.get(style, :effect) not in [nil, :none]

  # A gradient or a pattern is laid over the element's box (spec/14 §3.2).
  defp laid_over_box?(style) do
    Enum.any?([:fill, :stroke], fn key ->
      case Map.get(style, key) do
        %Paint{} -> true
        "url(" <> _ -> true
        _plain -> false
      end
    end)
  end
end
