if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Place do
    @moduledoc """
    Where a drop on the graph lands, and what a component means there (spec/14 §18.16).

    A drop is a point in chart coordinates; `region/2` classifies it against the frame the
    preview drew — the plot area, or one of the four margins — and `node/4` says what the
    dropped component becomes in that region: an axis on that side with the scale it needs,
    a title or a label at the anchor the region implies, a legend at the nearest position, a
    mark of a type. `home/1` is the region the keyboard twin and the `+` menu place in.

    Every function here is pure; the builder inserts what `node/4` returns.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    import Visualize.Chart.Names, only: [is_name: 1]

    alias Visualize.Chart.Fragment

    alias Visualize.Chart.{Frame, Schema}

    @typedoc "A region of the frame a drop lands in."
    @type region :: :plot | :top | :bottom | :left | :right

    @typedoc "What the palette offers: a component, or a mark of a type."
    @type component :: :axis | :legend | :title | :label | :frame | {:mark, atom()}

    @typedoc "A site to insert: its kind, its body under the kind's key, and its key if named."
    @type site :: %{kind: atom(), body: map(), key: atom() | nil}

    @doc """
    The palette's rows in the order shown: the five components — a frame among them (#616) —
    then a mark of every type.

        iex> Visualize.Chart.Builder.Place.components() |> Enum.take(6)
        [axis: "axis", legend: "legend", title: "title", label: "label", frame: "frame", "mark:line": "mark: line"]
    """
    @spec components() :: [{atom(), String.t()}]
    def components do
      [axis: "axis", legend: "legend", title: "title", label: "label", frame: "frame"] ++
        for type <- Schema.mark_types(), do: {:"mark:#{type}", "mark: #{type}"}
    end

    @doc """
    A component from the word its row carries, or `:error`.

        iex> Visualize.Chart.Builder.Place.component("mark:line")
        {:ok, {:mark, :line}}
        iex> Visualize.Chart.Builder.Place.component("axis")
        {:ok, :axis}
        iex> Visualize.Chart.Builder.Place.component("mark:banana")
        :error
    """
    @spec component(String.t()) :: {:ok, component()} | :error
    def component("mark:" <> type) do
      case Enum.find(Schema.mark_types(), &(to_string(&1) == type)) do
        nil -> :error
        found -> {:ok, {:mark, found}}
      end
    end

    def component(word) when word in ["axis", "legend", "title", "label", "frame"],
      do: {:ok, String.to_existing_atom(word)}

    def component(_word), do: :error

    @doc """
    The region a point in chart coordinates falls in: inside the plot area is `:plot`;
    otherwise the top or bottom band, then the left or right — so a corner is the top's or
    the bottom's, where the title and the x axis live.

        iex> frame = %{size: %{width: 400, height: 200}, margin: %{top: 20, right: 20, bottom: 30, left: 40}}
        iex> Visualize.Chart.Builder.Place.region({200, 100}, frame)
        :plot
        iex> Visualize.Chart.Builder.Place.region({200, 190}, frame)
        :bottom
        iex> Visualize.Chart.Builder.Place.region({5, 5}, frame)
        :top
        iex> Visualize.Chart.Builder.Place.region({5, 100}, frame)
        :left
    """
    @spec region({number(), number()}, %{size: map(), margin: map()}) :: region()
    def region({x, y}, %{size: size, margin: margin}) do
      cond do
        y < margin.top -> :top
        y > size.height - margin.bottom -> :bottom
        x < margin.left -> :left
        x > size.width - margin.right -> :right
        true -> :plot
      end
    end

    @doc """
    The region a component is placed in from the keyboard or the `+` menu: an axis at the
    bottom, a title at the top, a label at the bottom, a legend and a mark in the plot.
    """
    @spec home(component()) :: region()
    def home(:axis), do: :bottom
    def home(:title), do: :top
    def home(:label), do: :bottom
    def home(:legend), do: :plot
    def home(:frame), do: :plot
    def home({:mark, _type}), do: :plot

    @doc """
    The `size` and `margin` the preview draws a design at: the size is the render's own
    default, since a design records none (spec/14 §4.2), and the margin is the design's
    over the schema's default.

        iex> Visualize.Chart.Builder.Place.geometry(%{})
        %{size: %{width: 600, height: 400}, margin: %{top: 20, right: 20, bottom: 30, left: 40}}
    """
    @spec geometry(map()) :: %{size: map(), margin: map()}
    def geometry(design) do
      frame =
        if is_map(design),
          do: get_in(design, [:frames, Fragment.frame_of(design, nil)]) || %{},
          else: %{}

      frame = if is_map(frame), do: frame, else: %{}
      {width, height} = Frame.default_size()

      %{
        size: %{width: width, height: height},
        margin: Map.merge(Schema.default(:frame, :margin), plain(Map.get(frame, :margin)))
      }
    end

    defp plain(node) when is_map(node) and not is_struct(node),
      do: Map.filter(node, fn {_k, v} -> is_number(v) end)

    defp plain(_other), do: %{}

    @typedoc "Where a frame is drawn in the graph: its pixel box, its size and its margin."
    @type frame_geometry :: %{
            name: atom(),
            x: number(),
            y: number(),
            size: %{width: number(), height: number()},
            margin: map()
          }

    @typedoc "A point on the graph read in the frame under it (spec/14 §18.16)."
    @type spot :: %{
            frame: atom(),
            point: {number(), number()},
            geometry: %{size: map(), margin: map()}
          }

    @doc """
    Every frame of a design as the graph draws it at `size` (spec/14 §18.4, §18.16): its
    name, its pixel box (`x`, `y`, `size`) and its margin, in drawing order — `z`, then
    name, so the last is the one on top (§4.7). The box is `Visualize.Chart.Frame.box_of/3`
    of the frame, its cell resolved over the design's layout; a frame whose placement does
    not read yet is drawn over the whole box, as it would be with none. A design with no
    frame is one frame named as `Visualize.Chart.Fragment.frame_name/1` names it.

        iex> design = %{frames: %{history: %{box: [0, 0, 0.5, 1]}, now: %{box: [0.5, 0, 0.5, 1], margin: %{left: 10}}}}
        iex> for f <- Visualize.Chart.Builder.Place.frames(design, {800, 400}), do: {f.name, f.x, f.size.width, f.margin.left}
        [{:history, 0.0, 400.0, 40}, {:now, 400.0, 400.0, 10}]
    """
    @spec frames(map(), {number(), number()}) :: [frame_geometry()]
    def frames(design, {width, height}) do
      layout = if is_map(design), do: Map.get(design, :layout), else: nil
      layout = if is_map(layout) and not is_struct(layout), do: layout, else: nil

      design
      |> frame_nodes()
      |> Enum.sort_by(fn {name, node} -> {z(node), to_string(name)} end)
      |> Enum.map(fn {name, node} ->
        [x, y, w, h] =
          if placeable?(node, layout),
            do: Frame.box_of(node, layout, {width, height}),
            else: [0, 0, 1, 1]

        %{
          name: name,
          x: x * width * 1.0,
          y: y * height * 1.0,
          size: %{width: w * width * 1.0, height: h * height * 1.0},
          margin: Map.merge(Schema.default(:frame, :margin), plain(Map.get(node, :margin)))
        }
      end)
    end

    defp frame_nodes(design) do
      case is_map(design) && Map.get(design, :frames) do
        frames when is_map(frames) and map_size(frames) > 0 and not is_struct(frames) ->
          for {name, node} <- frames, do: {name, if(plain_map?(node), do: node, else: %{})}

        _none ->
          [{Fragment.frame_name(design), %{}}]
      end
    end

    defp plain_map?(node), do: is_map(node) and not is_struct(node)

    defp z(node) do
      case Map.get(node, :z) do
        z when is_integer(z) -> z
        _none -> 0
      end
    end

    # Whether a frame's placement reads, so resolving it cannot raise: a box of four
    # numbers, or a cell (and span) of whole numbers on a layout of positive weights.
    defp placeable?(node, layout) do
      case {Map.get(node, :cell), Map.get(node, :box)} do
        {nil, nil} -> true
        {nil, [x, y, w, h]} -> Enum.all?([x, y, w, h], &is_number/1)
        {[c, r], nil} when is_integer(c) and is_integer(r) -> span?(node) and weights?(layout)
        _other -> false
      end
    end

    defp span?(node) do
      case Map.get(node, :span) do
        nil -> true
        [a, d] -> is_integer(a) and is_integer(d) and a > 0 and d > 0
        _other -> false
      end
    end

    defp weights?(nil), do: true

    defp weights?(layout) do
      Enum.all?([:columns, :rows], fn key ->
        case Map.get(layout, key) do
          nil -> true
          weights when is_list(weights) -> Enum.all?(weights, &(is_number(&1) and &1 > 0))
          _other -> false
        end
      end) and is_number(Map.get(layout, :gap, 0))
    end

    @doc """
    A point on the graph, in chart coordinates, read in the frame under it (spec/14
    §18.16): the topmost frame whose box holds the point — else the nearest — with the
    point in that frame's own coordinates and the frame's size and margin, which `region/2`
    classifies.

        iex> design = %{frames: %{history: %{box: [0, 0, 0.5, 1]}, now: %{box: [0.5, 0, 0.5, 1]}}}
        iex> spot = Visualize.Chart.Builder.Place.spot(design, {800, 400}, {500, 390})
        iex> {spot.frame, spot.point, Visualize.Chart.Builder.Place.region(spot.point, spot.geometry)}
        {:now, {100.0, 390.0}, :bottom}
    """
    @spec spot(map(), {number(), number()}, {number(), number()}) :: spot()
    def spot(design, size, {px, py}) do
      frames = frames(design, size)

      frame =
        frames
        |> Enum.reverse()
        |> Enum.find(fn f ->
          px >= f.x and px <= f.x + f.size.width and py >= f.y and py <= f.y + f.size.height
        end) || Enum.min_by(frames, &distance(&1, {px, py}))

      %{
        frame: frame.name,
        point: {px - frame.x, py - frame.y},
        geometry: %{size: frame.size, margin: frame.margin}
      }
    end

    # How far a point lies outside a frame's box; zero inside it.
    defp distance(f, {px, py}) do
      dx = max(max(f.x - px, px - (f.x + f.size.width)), 0)
      dy = max(max(f.y - py, py - (f.y + f.size.height)), 0)
      dx * dx + dy * dy
    end

    @doc """
    A spot in a named frame, at its origin (#615): what the keyboard twin places with,
    which names a region and no point — the open node's frame, at the graph's size. A
    frame the design does not draw is read as `spot/3` reads the origin.

        iex> design = %{frames: %{history: %{box: [0, 0, 0.5, 1]}, now: %{box: [0.5, 0, 0.5, 1]}}}
        iex> spot = Visualize.Chart.Builder.Place.spot_in(design, {800, 400}, :now)
        iex> {spot.frame, spot.point, spot.geometry.size}
        {:now, {0, 0}, %{width: 400.0, height: 400.0}}
    """
    @spec spot_in(map(), {number(), number()}, atom()) :: spot()
    def spot_in(design, size, frame) do
      case Enum.find(frames(design, size), &(&1.name == frame)) do
        nil -> spot(design, size, {0, 0})
        f -> %{frame: f.name, point: {0, 0}, geometry: %{size: f.size, margin: f.margin}}
      end
    end

    @doc """
    A new frame dropped on the graph at a point (spec/14 §18.16, #616): a fresh name —
    `main` in a design with none, else the first free `frame_<n>` from 2 — and a box a
    quarter of the graph, half its width and half its height, centered on the point and
    kept inside, as fractions rounded to four places. `:center` is the graph's center,
    where the keyboard twin and *+ frame* place one.

        iex> design = %{frames: %{"main" => %{}, "frame_2" => %{}}}
        iex> Visualize.Chart.Builder.Place.new_frame(design, {800, 400}, {700, 100})
        {"frame_3", [0.5, 0, 0.5, 0.5]}
        iex> Visualize.Chart.Builder.Place.new_frame(%{}, {800, 400}, :center)
        {"main", [0.25, 0.25, 0.5, 0.5]}
    """
    @spec new_frame(map(), {number(), number()}, {number(), number()} | :center) ::
            {String.t(), [number()]}
    def new_frame(design, {width, height}, :center),
      do: new_frame(design, {width, height}, {width / 2, height / 2})

    def new_frame(design, {width, height}, {x, y}) do
      cx = x / width
      cy = y / height
      box = [clamp(cx - 0.25, 0, 0.5), clamp(cy - 0.25, 0, 0.5), 0.5, 0.5]
      {fresh_frame(design), Enum.map(box, &rounded/1)}
    end

    @doc """
    The design's layout as the graph draws it at a size (spec/14 §2.8, §18.16, #617): each
    column's `{x, w}` and each row's `{y, h}` as fractions, the gap taken out of the cells
    as `Visualize.Chart.Frame.box_of/3` takes it; `nil` for a design with no layout, or one
    whose weights do not read.

        iex> Visualize.Chart.Builder.Place.grid(%{layout: %{columns: [3, 1]}}, {800, 400})
        %{columns: [{0.0, 0.75}, {0.75, 0.25}], rows: [{0.0, 1.0}]}
        iex> Visualize.Chart.Builder.Place.grid(%{}, {800, 400})
        nil
    """
    @spec grid(map(), {number(), number()}) ::
            %{columns: [{number(), number()}], rows: [{number(), number()}]} | nil
    def grid(design, size) do
      case is_map(design) && Map.get(design, :layout) do
        layout when is_map(layout) and not is_struct(layout) ->
          if weights?(layout), do: lines(layout, size), else: nil

        _none ->
          nil
      end
    end

    defp lines(layout, size) do
      count = fn key -> layout |> Map.get(key, [1]) |> List.wrap() |> length() |> max(1) end

      %{
        columns:
          for c <- 0..(count.(:columns) - 1) do
            [x, _y, w, _h] = Frame.box_of(%{cell: [c, 0]}, layout, size)
            {x, w}
          end,
        rows:
          for r <- 0..(count.(:rows) - 1) do
            [_x, y, _w, h] = Frame.box_of(%{cell: [0, r]}, layout, size)
            {y, h}
          end
      }
    end

    defp clamp(v, low, high), do: v |> max(low) |> min(high)

    defp rounded(value) do
      r = Float.round(value * 1.0, 4)
      if r == trunc(r), do: trunc(r), else: r
    end

    defp fresh_frame(design) do
      taken =
        case is_map(design) && Map.get(design, :frames) do
          frames when is_map(frames) -> frames |> Map.keys() |> Enum.map(&to_string/1)
          _none -> []
        end

      # A frame is named by its string (D-195).
      if taken == [] do
        "main"
      else
        2
        |> Stream.iterate(&(&1 + 1))
        |> Enum.find(&("frame_#{&1}" not in taken))
        |> then(&"frame_#{&1}")
      end
    end

    # A point given bare is read in the design's frame at the render's default size, as
    # the graph drew it before it measured anything.
    defp spotted(%{point: _, geometry: _} = spot, _design), do: spot

    defp spotted({_x, _y} = point, design),
      do: %{frame: Fragment.frame_of(design, nil), point: point, geometry: geometry(design)}

    # A reading of the point against the geometry of the frame it is in.
    defp at(point, design, read) do
      %{point: local, geometry: geometry} = spotted(point, design)
      read.(local, geometry)
    end

    @doc """
    What a component becomes in a region of the composed design, dropped at a point:
    `{:sites, sites}` — lowest first, so an axis's scale comes before the axis — or
    `{:legend, node}` for the frame's legend, or `{:error, :no_scale}` for a legend on a
    design with no ordinal scale. The point is a `spot/3` — read in the frame under it —
    or a bare point, read in the design's frame at the render's default size.

        iex> design = %{frames: %{"main" => %{scales: %{"x" => %{kind: :linear}}}}}
        iex> Visualize.Chart.Builder.Place.node(:axis, :bottom, design, {0, 0})
        {:sites, [%{kind: :axis, body: %{scale: "x", side: :bottom}, key: nil}]}
        iex> Visualize.Chart.Builder.Place.node(:axis, :left, design, {0, 0})
        {:sites, [%{kind: :scale, body: %{kind: :linear, domain: :auto}, key: "y"}, %{kind: :axis, body: %{scale: "y", side: :left}, key: nil}]}
        iex> Visualize.Chart.Builder.Place.node(:legend, :plot, design, {0, 0})
        {:error, :no_scale}
    """
    @spec node(component(), region(), map(), {number(), number()} | spot()) ::
            {:sites, [site()]}
            | {:frame, atom(), %{scales: map(), axes: [map()]}}
            | {:legend, map()}
            | {:error, :no_scale}
    def node(:axis, region, design, point) do
      frame = spotted(point, design).frame

      {scale, side} =
        case region do
          :top -> {"x", :top}
          :left -> {"y", :left}
          :right -> {"y", :right}
          _bottom_or_plot -> {"x", :bottom}
        end

      declared? = scale_declared?(design, frame, scale)
      axis = %{scale: scale, side: side}

      # In a design of several frames an axis is the frame's own node, written into the
      # frame under the pointer: an axis or scale site lands in one frame of the design's
      # choosing (§19.6), which is not the one dropped on (#615).
      if several?(design) do
        scales = if declared?, do: %{}, else: %{scale => %{kind: :linear, domain: :auto}}
        {:frame, frame, %{scales: scales, axes: [axis]}}
      else
        declared = if declared?, do: [], else: [scale_site(scale)]
        {:sites, declared ++ [%{kind: :axis, body: axis, key: nil}]}
      end
    end

    def node(:title, region, design, point) do
      anchor = if region == :bottom, do: :caption, else: :title
      body = framed(%{anchor: anchor, text: ["Title"]}, design, point)
      {:sites, [%{kind: :label, body: body, key: nil}]}
    end

    def node(:label, region, design, point) do
      anchor =
        case region do
          :top -> :subtitle
          :bottom -> {:axis, "x"}
          :left -> {:axis, "y"}
          :right -> {:frame, :top_right}
          :plot -> {:frame, at(point, design, &corner/2)}
        end

      body = framed(%{anchor: anchor, text: ["Label"]}, design, point)
      {:sites, [%{kind: :label, body: body, key: nil}]}
    end

    def node(:legend, region, design, point) do
      case ordinal_scale(design, spotted(point, design).frame) do
        nil ->
          {:error, :no_scale}

        scale ->
          position = if region == :plot, do: at(point, design, &position/2), else: region
          {:legend, %{scale: scale, position: position}}
      end
    end

    def node({:mark, type}, _region, design, point) do
      body = framed(Map.merge(%{type: type}, guess(design, type)), design, point)
      {:sites, [%{kind: :mark, body: body, key: nil}]}
    end

    # A mark or a label placed in a design of several frames says the frame it was dropped
    # on (#615), since the validator asks a frame of each once there are two; in a design
    # of one it says nothing, as it always did.
    defp framed(body, design, point) do
      if several?(design), do: Map.put(body, :frame, spotted(point, design).frame), else: body
    end

    @doc """
    Whether a design has several frames (spec/14 §2.1), so that what is placed on the
    graph says which one it belongs to (#615).

        iex> Visualize.Chart.Builder.Place.several?(%{frames: %{a: %{}, b: %{}}})
        true
        iex> Visualize.Chart.Builder.Place.several?(%{frames: %{main: %{}}})
        false
    """
    @spec several?(term()) :: boolean()
    def several?(%{frames: frames}) when is_map(frames) and not is_struct(frames),
      do: map_size(frames) > 1

    def several?(_design), do: false

    @doc """
    A mark type's `data` and `channels` guessed over the composed design (spec/14 §18.16):
    the chart's first source — the one the last mark binds, else the first declared by
    name — and its fields in order over the type's required channels; fewer fields leave
    the rest unbound; no source, nothing.

        iex> design = %{sources: %{s: %{fields: [:hour, :value, :extra]}}}
        iex> Visualize.Chart.Builder.Place.guess(design, :line)
        %{data: :s, channels: %{x: :hour, y: :value}}
        iex> Visualize.Chart.Builder.Place.guess(design, :rect)
        %{data: :s, channels: %{x0: :hour, x1: :value, y0: :extra}}
        iex> Visualize.Chart.Builder.Place.guess(%{}, :line)
        %{}
    """
    @spec guess(map(), atom()) :: map()
    def guess(design, type) do
      case first_source(design) do
        nil ->
          %{}

        {name, fields} ->
          %{required: required} = Schema.channels(type)
          channels = required |> Enum.zip(fields) |> Map.new()
          %{data: name, channels: channels}
      end
    end

    # The source the last mark binds, else the first declared by name, with its fields.
    defp first_source(design) when is_map(design) do
      sources = Map.get(design, :sources)
      sources = if is_map(sources), do: sources, else: %{}

      bound =
        case Map.get(design, :marks) do
          [_ | _] = marks -> marks |> List.last() |> then(&(is_map(&1) && Map.get(&1, :data)))
          _none -> nil
        end

      name =
        cond do
          is_name(bound) and Map.has_key?(sources, bound) -> bound
          map_size(sources) > 0 -> sources |> Map.keys() |> Enum.sort() |> List.first()
          true -> nil
        end

      case name && Map.get(sources, name) do
        %{fields: fields} when is_list(fields) -> {name, Enum.filter(fields, &is_name/1)}
        _other -> nil
      end
    end

    defp first_source(_design), do: nil

    @doc """
    A library entry's body placed: an axis's `side`, a label's `anchor` set from the region
    where the region names one; anything else, and a drop in the plot, as the entry wrote it.

        iex> Visualize.Chart.Builder.Place.placed(%{axis: %{scale: :y, side: :left}}, :right)
        %{axis: %{scale: :y, side: :right}}
        iex> Visualize.Chart.Builder.Place.placed(%{axis: %{scale: :y, side: :left}}, :plot)
        %{axis: %{scale: :y, side: :left}}
    """
    @spec placed(map(), region()) :: map()
    def placed(%{axis: body} = fragment, region) when region in [:top, :bottom, :left, :right],
      do: %{fragment | axis: Map.put(body, :side, region)}

    def placed(%{label: body} = fragment, region) when region in [:top, :bottom, :left, :right] do
      anchor =
        case region do
          :top -> :title
          :bottom -> {:axis, "x"}
          :left -> {:axis, "y"}
          :right -> {:frame, :top_right}
        end

      %{fragment | label: Map.put(body, :anchor, anchor)}
    end

    def placed(fragment, _region), do: fragment

    @doc """
    Whether a drawn node's label names a node that is moved on the graph (spec/14 §18.16):
    an axis, the legend, a label. A mark's position is its data; the frame does not move.

        iex> Visualize.Chart.Builder.Place.movable?("frames.main.axes[1]")
        true
        iex> Visualize.Chart.Builder.Place.movable?("marks[0]")
        false
    """
    @spec movable?(String.t()) :: boolean()
    # A frame's own furniture moves, whatever the frame is called (spec/14 §4.1, #383).
    def movable?("frames." <> rest),
      do: String.contains?(rest, ".axes[") or String.ends_with?(rest, ".legend")

    def movable?("labels[" <> _rest), do: true
    def movable?(_label), do: false

    @doc """
    A node moved to a region at a point over the composed design (spec/14 §18.16): its body
    with the placement key rewritten — an axis's `side`, a legend's `position`, a label's
    `anchor` — or `:same` when the region names what it already is, or `:unmovable` for a
    kind with no placement. An axis whose orientation changes takes the scale its new side
    reads — the one another axis on that orientation reads, else `x` or `y` — since a
    scale's range is set by its name (§4.3); a scale the design lacks is brought as a drop
    brings it, `{:ok, body, [scale_site]}`. The point is a `spot/3` or a bare point, as
    `node/4` reads one.

        iex> Visualize.Chart.Builder.Place.moved(:axis, %{scale: :x, side: :bottom}, :top, {0, 0})
        {:ok, %{scale: :x, side: :top}}
        iex> Visualize.Chart.Builder.Place.moved(:axis, %{scale: :x, side: :bottom}, :left, {0, 0}, %{frames: %{"main" => %{scales: %{"x" => %{}, "y" => %{}}}}})
        {:ok, %{scale: "y", side: :left}}
        iex> Visualize.Chart.Builder.Place.moved(:axis, %{scale: :x, side: :bottom}, :left, {0, 0})
        {:ok, %{scale: "y", side: :left}, [%{kind: :scale, body: %{kind: :linear, domain: :auto}, key: "y"}]}
        iex> Visualize.Chart.Builder.Place.moved(:axis, %{scale: :x, side: :bottom}, :bottom, {0, 0})
        :same
        iex> Visualize.Chart.Builder.Place.moved(:mark, %{type: :line}, :top, {0, 0})
        :unmovable
    """
    @spec moved(atom(), map(), region(), {number(), number()} | spot(), map()) ::
            {:ok, map()} | {:ok, map(), [site()]} | :same | :unmovable
    def moved(kind, body, region, point, design \\ %{})

    def moved(:axis, body, region, point, design)
        when region in [:top, :bottom, :left, :right] do
      frame = spotted(point, design).frame

      case rewritten(body, :side, region) do
        :same ->
          :same

        {:ok, turned} ->
          if orientation(region) == orientation(Map.get(body, :side)) do
            {:ok, turned}
          else
            scale = scale_for(design, frame, region, Map.get(body, :scale))
            turned = Map.put(turned, :scale, scale)

            if scale_declared?(design, frame, scale),
              do: {:ok, turned},
              else: {:ok, turned, [scale_site(scale)]}
          end
      end
    end

    def moved(:axis, _body, :plot, _point, _design), do: :same

    def moved(:legend, body, :plot, point, design),
      do: rewritten(body, :position, at(point, design, &position/2))

    def moved(:legend, body, region, _point, _design),
      do: rewritten(body, :position, region)

    def moved(:label, body, :plot, point, design),
      do: rewritten(body, :anchor, {:frame, at(point, design, &corner/2)})

    def moved(:label, body, region, _point, _design) do
      current = Map.get(body, :anchor)

      anchor =
        case region do
          :top -> if current in [:title, :subtitle], do: current, else: :title
          :bottom -> if current in [:title, :subtitle, :caption], do: :caption, else: {:axis, "x"}
          :left -> {:axis, "y"}
          :right -> {:frame, :top_right}
        end

      rewritten(body, :anchor, anchor)
    end

    def moved(_kind, _body, _region, _point, _design), do: :unmovable

    defp orientation(side) when side in [:top, :bottom], do: :horizontal
    defp orientation(side) when side in [:left, :right], do: :vertical
    defp orientation(_none), do: nil

    # The scale a side reads: the one another axis on that orientation already reads —
    # other than the axis being moved — else `x` or `y` by orientation.
    defp scale_for(design, frame, side, own) do
      wanted = orientation(side)

      axes =
        case get_in(design, [:frames, frame, :axes]) do
          axes when is_list(axes) -> axes
          _none -> []
        end

      Enum.find_value(axes, fn axis ->
        is_map(axis) and orientation(Map.get(axis, :side)) == wanted and
          Map.get(axis, :scale) != own and Map.get(axis, :scale)
      end) || if(wanted == :horizontal, do: "x", else: "y")
    end

    defp rewritten(body, key, value) do
      if Map.get(body, key) == value, do: :same, else: {:ok, Map.put(body, key, value)}
    end

    # -- the design's word ----------------------------------------------------------------

    defp scale_declared?(design, frame, name) do
      scales = get_in(design, [:frames, frame, :scales])
      is_map(scales) and Map.has_key?(scales, name)
    end

    defp scale_site(name),
      do: %{kind: :scale, body: %{kind: :linear, domain: :auto}, key: name}

    # The first ordinal scale by name: the one a legend reads its entries from (§4.5).
    defp ordinal_scale(design, frame) do
      case get_in(design, [:frames, frame, :scales]) do
        scales when is_map(scales) ->
          scales
          |> Enum.filter(fn {_name, node} ->
            is_map(node) and Map.get(node, :kind) == :ordinal
          end)
          |> Enum.map(&elem(&1, 0))
          |> Enum.sort()
          |> List.first()

        _none ->
          nil
      end
    end

    # The corner of the plot area nearest a point.
    defp corner({x, y}, %{size: size, margin: margin}) do
      left? = x < margin.left + (size.width - margin.left - margin.right) / 2
      top? = y < margin.top + (size.height - margin.top - margin.bottom) / 2

      case {top?, left?} do
        {true, true} -> :top_left
        {true, false} -> :top_right
        {false, true} -> :bottom_left
        {false, false} -> :bottom_right
      end
    end

    # The nearest of the legend's eight positions: a corner, or an edge's middle when the
    # point is nearer the middle third of that edge.
    defp position({x, y}, %{size: size, margin: margin} = geometry) do
      w = size.width - margin.left - margin.right
      h = size.height - margin.top - margin.bottom
      fx = (x - margin.left) / w
      fy = (y - margin.top) / h
      middle_x? = fx > 1 / 3 and fx < 2 / 3
      middle_y? = fy > 1 / 3 and fy < 2 / 3

      cond do
        middle_x? and fy <= 0.5 -> :top
        middle_x? -> :bottom
        middle_y? and fx <= 0.5 -> :left
        middle_y? -> :right
        true -> corner({x, y}, geometry)
      end
    end
  end
end
