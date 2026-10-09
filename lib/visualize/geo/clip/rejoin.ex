defmodule Visualize.Geo.Clip.Rejoin do
  @moduledoc false
  # d3-geo's src/clip/rejoin.js (v3.1.1): "a generalized polygon clipping algorithm: given
  # a polygon that has been cut into its visible line segments, rejoins the segments by
  # interpolating along the clip edge" (rejoin.js:13–15).
  #
  # d3 links `Intersection` objects into two circular lists and marks them visited in
  # place. Here each segment `j` gives two intersections, indexed `2j` (its start, an
  # entry) and `2j + 1` (its end, an exit). The *subject* list is that index order; the
  # *clip* list is the same intersections sorted along the clip edge; `o` joins an
  # intersection's two entries. Nodes are `{:s, i}` and `{:c, i}`, and the walk carries the
  # visited set.

  alias Visualize.Geo.Clip

  @doc false
  @spec rejoin([[Clip.point()]], (Clip.point() -> float()), boolean(), function()) ::
          [[Clip.point()]]
  def rejoin(segments, key, start_inside, interpolate) do
    eps = Clip.epsilon()

    # rejoin.js:245–264
    {closed, open} =
      Enum.reduce(segments, {[], []}, fn segment, {closed, open} ->
        n = length(segment) - 1
        p0 = hd(segment)
        p1 = List.last(segment)

        cond do
          n <= 0 ->
            {closed, open}

          point_equal?(p0, p1) and not flagged?(p0) and not flagged?(p1) ->
            {[Enum.take(segment, n) | closed], open}

          # Handle degenerate cases by moving the point (rejoin.js:256–257).
          point_equal?(p0, p1) ->
            moved = put_elem(p1, 0, elem(p1, 0) + 2 * eps)
            {closed, [List.replace_at(segment, n, moved) | open]}

          true ->
            {closed, [segment | open]}
        end
      end)

    Enum.reverse(closed) ++ walk_all(Enum.reverse(open), key, start_inside, interpolate)
  end

  defp walk_all([], _key, _start_inside, _interpolate), do: []

  defp walk_all(open, key, start_inside, interpolate) do
    segments = List.to_tuple(open)
    size = 2 * tuple_size(segments)

    x = fn i ->
      segment = elem(segments, div(i, 2))
      if rem(i, 2) == 0, do: hd(segment), else: List.last(segment)
    end

    # rejoin.js:268–274: the clip list sorted along the edge, its entries alternating
    # from the opposite of `start_inside`.
    order = Enum.sort_by(0..(size - 1), &key.(x.(&1)))
    order_t = List.to_tuple(order)
    position = order |> Enum.with_index() |> Map.new()

    graph = %{
      segments: segments,
      size: size,
      x: x,
      order: order_t,
      position: position,
      clip_entry:
        order
        |> Enum.with_index()
        |> Map.new(fn {i, k} ->
          {i, if(rem(k, 2) == 0, do: not start_inside, else: start_inside)}
        end),
      interpolate: interpolate
    }

    rings(graph, MapSet.new(), [])
  end

  # rejoin.js:280–310: from the first unvisited subject intersection, round and round.
  defp rings(graph, visited, acc) do
    case first_unvisited(graph, visited, {:s, 0}, {:s, 0}) do
      nil ->
        Enum.reverse(acc)

      current ->
        {ring, visited} = walk(graph, current, true, visited, [])
        rings(graph, visited, [ring | acc])
    end
  end

  defp first_unvisited(graph, visited, current, start) do
    if MapSet.member?(visited, current) do
      case next(graph, current) do
        ^start -> nil
        node -> first_unvisited(graph, visited, node, start)
      end
    else
      current
    end
  end

  # One ring: the do…while of rejoin.js:287–308, the points emitted in reverse.
  defp walk(graph, current, subject?, visited, out) do
    visited = visited |> MapSet.put(current) |> MapSet.put(other(current))

    {out, current} =
      if entry?(graph, current) do
        out =
          if subject?,
            do: Enum.reverse(z(graph, current), out),
            else:
              Enum.reverse(
                graph.interpolate.(x(graph, current), x(graph, next(graph, current)), 1),
                out
              )

        {out, next(graph, current)}
      else
        out =
          if subject?,
            do: Enum.reverse(Enum.reverse(z(graph, prev(graph, current))), out),
            else:
              Enum.reverse(
                graph.interpolate.(x(graph, current), x(graph, prev(graph, current)), -1),
                out
              )

        {out, prev(graph, current)}
      end

    current = other(current)

    if MapSet.member?(visited, current),
      do: {Enum.reverse(out), visited},
      else: walk(graph, current, not subject?, visited, out)
  end

  defp other({:s, i}), do: {:c, i}
  defp other({:c, i}), do: {:s, i}

  defp x(graph, {_, i}), do: graph.x.(i)
  defp z(graph, {:s, i}), do: elem(graph.segments, div(i, 2))

  # A subject intersection is an entry at its segment's start (rejoin.js:260–263); a clip
  # intersection's flag was set by its place along the edge (rejoin.js:272–274).
  defp entry?(_graph, {:s, i}), do: rem(i, 2) == 0
  defp entry?(graph, {:c, i}), do: Map.fetch!(graph.clip_entry, i)

  defp next(graph, {:s, i}), do: {:s, rem(i + 1, graph.size)}
  defp next(graph, {:c, i}), do: {:c, elem(graph.order, rem(graph.position[i] + 1, graph.size))}

  defp prev(graph, {:s, i}), do: {:s, rem(i - 1 + graph.size, graph.size)}

  defp prev(graph, {:c, i}),
    do: {:c, elem(graph.order, rem(graph.position[i] - 1 + graph.size, graph.size))}

  # pointEqual.js
  defp point_equal?(a, b) do
    eps = Clip.epsilon()
    abs(elem(a, 0) - elem(b, 0)) < eps and abs(elem(a, 1) - elem(b, 1)) < eps
  end

  defp flagged?({_, _, m}) when m not in [nil, 0, false], do: true
  defp flagged?(_), do: false
end
