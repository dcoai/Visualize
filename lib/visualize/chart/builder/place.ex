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

    alias Visualize.Chart.Fragment

    alias Visualize.Chart.{Frame, Schema}

    @typedoc "A region of the frame a drop lands in."
    @type region :: :plot | :top | :bottom | :left | :right

    @typedoc "What the palette offers: a component, or a mark of a type."
    @type component :: :axis | :legend | :title | :label | {:mark, atom()}

    @typedoc "A site to insert: its kind, its body under the kind's key, and its key if named."
    @type site :: %{kind: atom(), body: map(), key: atom() | nil}

    @doc """
    The palette's rows in the order shown: the four components, then a mark of every type.

        iex> Visualize.Chart.Builder.Place.components() |> Enum.take(5)
        [axis: "axis", legend: "legend", title: "title", label: "label", "mark:line": "mark: line"]
    """
    @spec components() :: [{atom(), String.t()}]
    def components do
      [axis: "axis", legend: "legend", title: "title", label: "label"] ++
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
      case Enum.find(Schema.mark_types(), &(Atom.to_string(&1) == type)) do
        nil -> :error
        found -> {:ok, {:mark, found}}
      end
    end

    def component(word) when word in ["axis", "legend", "title", "label"],
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
      frame = if is_map(design), do: get_in(design, Fragment.frame_path(design)) || %{}, else: %{}
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

    @doc """
    What a component becomes in a region of the composed design, dropped at a point:
    `{:sites, sites}` — lowest first, so an axis's scale comes before the axis — or
    `{:legend, node}` for the frame's legend, or `{:error, :no_scale}` for a legend on a
    design with no ordinal scale.

        iex> design = %{frames: %{main: %{scales: %{x: %{kind: :linear}}}}}
        iex> Visualize.Chart.Builder.Place.node(:axis, :bottom, design, {0, 0})
        {:sites, [%{kind: :axis, body: %{scale: :x, side: :bottom}, key: nil}]}
        iex> Visualize.Chart.Builder.Place.node(:axis, :left, design, {0, 0})
        {:sites, [%{kind: :scale, body: %{kind: :linear, domain: :auto}, key: :y}, %{kind: :axis, body: %{scale: :y, side: :left}, key: nil}]}
        iex> Visualize.Chart.Builder.Place.node(:legend, :plot, design, {0, 0})
        {:error, :no_scale}
    """
    @spec node(component(), region(), map(), {number(), number()}) ::
            {:sites, [site()]} | {:legend, map()} | {:error, :no_scale}
    def node(:axis, region, design, _point) do
      {scale, side} =
        case region do
          :top -> {:x, :top}
          :left -> {:y, :left}
          :right -> {:y, :right}
          _bottom_or_plot -> {:x, :bottom}
        end

      declared = if scale_declared?(design, scale), do: [], else: [scale_site(scale)]
      {:sites, declared ++ [%{kind: :axis, body: %{scale: scale, side: side}, key: nil}]}
    end

    def node(:title, region, _design, _point) do
      anchor = if region == :bottom, do: :caption, else: :title
      {:sites, [%{kind: :label, body: %{anchor: anchor, text: ["Title"]}, key: nil}]}
    end

    def node(:label, region, design, point) do
      anchor =
        case region do
          :top -> :subtitle
          :bottom -> {:axis, :x}
          :left -> {:axis, :y}
          :right -> {:frame, :top_right}
          :plot -> {:frame, corner(point, geometry(design))}
        end

      {:sites, [%{kind: :label, body: %{anchor: anchor, text: ["Label"]}, key: nil}]}
    end

    def node(:legend, region, design, point) do
      case ordinal_scale(design) do
        nil ->
          {:error, :no_scale}

        scale ->
          position = if region == :plot, do: position(point, geometry(design)), else: region
          {:legend, %{scale: scale, position: position}}
      end
    end

    def node({:mark, type}, _region, design, _point) do
      {:sites, [%{kind: :mark, body: Map.merge(%{type: type}, guess(design, type)), key: nil}]}
    end

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
          is_atom(bound) and bound != nil and Map.has_key?(sources, bound) -> bound
          map_size(sources) > 0 -> sources |> Map.keys() |> Enum.sort() |> List.first()
          true -> nil
        end

      case name && Map.get(sources, name) do
        %{fields: fields} when is_list(fields) -> {name, Enum.filter(fields, &is_atom/1)}
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
          :bottom -> {:axis, :x}
          :left -> {:axis, :y}
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
    brings it, `{:ok, body, [scale_site]}`.

        iex> Visualize.Chart.Builder.Place.moved(:axis, %{scale: :x, side: :bottom}, :top, {0, 0})
        {:ok, %{scale: :x, side: :top}}
        iex> Visualize.Chart.Builder.Place.moved(:axis, %{scale: :x, side: :bottom}, :left, {0, 0}, %{frames: %{main: %{scales: %{x: %{}, y: %{}}}}})
        {:ok, %{scale: :y, side: :left}}
        iex> Visualize.Chart.Builder.Place.moved(:axis, %{scale: :x, side: :bottom}, :left, {0, 0})
        {:ok, %{scale: :y, side: :left}, [%{kind: :scale, body: %{kind: :linear, domain: :auto}, key: :y}]}
        iex> Visualize.Chart.Builder.Place.moved(:axis, %{scale: :x, side: :bottom}, :bottom, {0, 0})
        :same
        iex> Visualize.Chart.Builder.Place.moved(:mark, %{type: :line}, :top, {0, 0})
        :unmovable
    """
    @spec moved(atom(), map(), region(), {number(), number()}, map()) ::
            {:ok, map()} | {:ok, map(), [site()]} | :same | :unmovable
    def moved(kind, body, region, point, design \\ %{})

    def moved(:axis, body, region, _point, design)
        when region in [:top, :bottom, :left, :right] do
      case rewritten(body, :side, region) do
        :same ->
          :same

        {:ok, turned} ->
          if orientation(region) == orientation(Map.get(body, :side)) do
            {:ok, turned}
          else
            scale = scale_for(design, region, Map.get(body, :scale))
            turned = Map.put(turned, :scale, scale)

            if scale_declared?(design, scale),
              do: {:ok, turned},
              else: {:ok, turned, [scale_site(scale)]}
          end
      end
    end

    def moved(:axis, _body, :plot, _point, _design), do: :same

    def moved(:legend, body, :plot, point, design),
      do: rewritten(body, :position, position(point, geometry(design)))

    def moved(:legend, body, region, _point, _design),
      do: rewritten(body, :position, region)

    def moved(:label, body, :plot, point, design),
      do: rewritten(body, :anchor, {:frame, corner(point, geometry(design))})

    def moved(:label, body, region, _point, _design) do
      current = Map.get(body, :anchor)

      anchor =
        case region do
          :top -> if current in [:title, :subtitle], do: current, else: :title
          :bottom -> if current in [:title, :subtitle, :caption], do: :caption, else: {:axis, :x}
          :left -> {:axis, :y}
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
    defp scale_for(design, side, own) do
      wanted = orientation(side)

      axes =
        case get_in(design, Fragment.frame_path(design) ++ [:axes]) do
          axes when is_list(axes) -> axes
          _none -> []
        end

      Enum.find_value(axes, fn axis ->
        is_map(axis) and orientation(Map.get(axis, :side)) == wanted and
          Map.get(axis, :scale) != own and Map.get(axis, :scale)
      end) || if(wanted == :horizontal, do: :x, else: :y)
    end

    defp rewritten(body, key, value) do
      if Map.get(body, key) == value, do: :same, else: {:ok, Map.put(body, key, value)}
    end

    # -- the design's word ----------------------------------------------------------------

    defp scale_declared?(design, name) do
      scales = get_in(design, Fragment.frame_path(design) ++ [:scales])
      is_map(scales) and Map.has_key?(scales, name)
    end

    defp scale_site(name),
      do: %{kind: :scale, body: %{kind: :linear, domain: :auto}, key: name}

    # The first ordinal scale by name: the one a legend reads its entries from (§4.5).
    defp ordinal_scale(design) do
      case get_in(design, Fragment.frame_path(design) ++ [:scales]) do
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
