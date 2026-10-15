if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Components do
    @moduledoc """
    Phoenix LiveView function components for the common chart types (spec/10 §2).

    Each component is a preset design of `Visualize.Chart.Presets` plus an assign mapping
    (spec/14 §15, D-64): its assigns become a design and the rows the design's source binds
    to, `Visualize.Chart.Frame` realizes and draws the design, and the component prints the
    elements the layer returns — the axes, every path, rectangle, circle and label — in the
    markup spec/10 declares. Its template is the `<svg>` shell and the attribute order of
    each mark, nothing more.

    ## Usage

        use Phoenix.Component
        import Visualize.Components

        <.line_chart data={@data} x={& &1.date} y={& &1.value} width={600} height={400} />

    ## Components

    - `line_chart/1` and `area_chart/1` - one series over a time, linear or band x axis
    - `bar_chart/1`, `horizontal_bar_chart/1` and `stacked_bar_chart/1` - bars on a band
      scale
    - `scatter_plot/1` - one circle per datum on two linear axes
    - `pie_chart/1` - a pie or donut with optional labels

    ## Conventions

    - Empty `data` renders the frame - the `<svg>` and, where the chart has them, its axes
      over a `[0, 1]` domain - with no marks. A domain whose ends coincide (one datum, or
      every value zero) stays collapsed and maps to the middle of the axis (D-49, D-60).
    - `colors` is a scheme atom of `Visualize.Scale.Color.schemes/0`, whose colors are
      taken by index and cycled, or an explicit list of colors used as given. An unknown
      scheme or an empty list raises `ArgumentError`.
    - `animate={true}` puts `style="transition: all 0.3s ease-in-out;"` on every mark, so
      LiveView's DOM patches animate through CSS.
    - `theme` is a `Visualize.Theme` (default `Visualize.Theme.default/0`); every color,
      font and size that is not an explicit assign is a slot of it, rendered as a CSS
      reference with the literal as fallback so a stylesheet overrides it (D-55). A color
      assign left `nil` takes the slot its documentation names.
    - `margin` is merged over the component's default, so `%{left: 60}` moves one side.
    - The defaults below are `Visualize.Chart.Presets.defaults/1`.

    This module compiles only when `Phoenix.Component` is loaded: `phoenix_live_view` is an
    optional dependency, present in a host that has LiveView and never fetched otherwise.
    """

    use Phoenix.Component

    alias Visualize.Chart.Presets
    alias Visualize.Components.Support

    @line Presets.defaults(:line_chart)
    @bar Presets.defaults(:bar_chart)
    @horizontal Presets.defaults(:horizontal_bar_chart)
    @pie Presets.defaults(:pie_chart)
    @scatter Presets.defaults(:scatter_plot)
    @area Presets.defaults(:area_chart)
    @stacked Presets.defaults(:stacked_bar_chart)

    @doc """
    Renders a line chart: one series with bottom and left axes.

    ## Assigns

    * `data` - the data points (required); empty renders the frame alone
    * `x` - accessor to the x value: a `DateTime`, `NaiveDateTime` or `Date` gives a time
      scale, a number a linear scale, anything else a band scale, decided by the first
      datum (required)
    * `y` - accessor to a numeric y value; the y domain is the extent of the values
      (required)
    * `width`, `height` - pixels (default 600 by 400)
    * `margin` - `%{top:, right:, bottom:, left:}`, merged over
      `%{top: 20, right: 20, bottom: 30, left: 40}`
    * `curve` - any curve type of `Visualize.Shape.curve/3` (default `:linear`)
    * `stroke` - line color, also the point fill (default `nil`: the theme's `:series_1`)
    * `stroke_width` - (default 2)
    * `show_points` - draw an `r="4"` circle at each datum (default `false`)
    * `x_label`, `y_label` - axis titles as `<text class="axis-label">`
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions

    ## Example

        <.line_chart data={@sales} x={& &1.date} y={& &1.revenue} curve={:monotone_x} />
    """
    attr(:data, :any, required: true)
    attr(:x, :any, required: true)
    attr(:y, :any, required: true)
    attr(:width, :integer, default: @line.width)
    attr(:height, :integer, default: @line.height)
    attr(:margin, :map, default: @line.margin)
    attr(:curve, :atom, default: @line.curve)
    attr(:stroke, :string, default: @line.stroke)
    attr(:stroke_width, :integer, default: @line.stroke_width)
    attr(:animate, :boolean, default: @line.animate)
    attr(:class, :string, default: @line.class)
    attr(:responsive, :boolean, default: @line.responsive)
    attr(:theme, :any, default: @line.theme)
    attr(:title, :string, default: @line.title)
    attr(:description, :string, default: @line.description)
    attr(:x_label, :string, default: @line.x_label)
    attr(:y_label, :string, default: @line.y_label)
    attr(:show_points, :boolean, default: @line.show_points)

    def line_chart(assigns) do
      drawn = Support.draw(:line_chart, assigns)
      [line | points] = Support.marks(drawn.group)
      {x_title, y_title} = titles(Support.labels(drawn.group), assigns.x_label)

      points =
        for mark <- points,
            circle <- mark.children,
            do: {fmt(circle.attrs.cx), fmt(circle.attrs.cy)}

      assigns =
        assign(assigns,
          margin: drawn.margin,
          inner_height: drawn.plot.height,
          path: Support.path(line),
          points: points,
          stroke: line.style.stroke,
          x_title: x_title,
          y_title: y_title,
          theme: drawn.theme,
          ids: drawn.ids,
          x_axis: Support.axis(drawn.group, :bottom),
          y_axis: Support.axis(drawn.group, :left),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids, @animate)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc><style :if={@animate}><%= Support.reduced_motion() %></style>
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>{@x_axis}</g>
          <g class="y-axis">{@y_axis}</g>
          <path
            :if={@path}
            d={@path}
            fill="none"
            stroke={@stroke}
            stroke-width={@stroke_width}
            {@transition}
          />
          <circle :for={{cx, cy} <- @points} cx={cx} cy={cy} r="4" fill={@stroke} {@transition} />
          <text
            :if={@x_title}
            x={@x_title.x}
            y={@x_title.y}
            text-anchor={@x_title.anchor}
            font-size={@x_title.font_size}
            fill={@x_title.fill}
            class="axis-label"
          >{@x_title.text}</text>
          <text
            :if={@y_title}
            transform={@y_title.transform}
            x={@y_title.x}
            y={@y_title.y}
            text-anchor={@y_title.anchor}
            font-size={@y_title.font_size}
            fill={@y_title.fill}
            class="axis-label"
          >{@y_title.text}</text>
        </g>
      </svg>
      """
    end

    @doc """
    Renders a vertical bar chart: a band x scale over the categories in data order and a
    linear y scale from zero.

    ## Assigns

    * `data` - the data points (required); empty renders the frame alone
    * `x` - accessor to the category (required)
    * `y` - accessor to a non-negative number; the y domain is `[0, max]` (required)
    * `width`, `height` - pixels (default 600 by 400)
    * `margin` - merged over `%{top: 20, right: 20, bottom: 30, left: 40}`
    * `fill` - bar color (default `nil`: the theme's `:series_1`)
    * `padding` - band padding, 0 to 1 (default 0.1)
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions
    """
    attr(:data, :any, required: true)
    attr(:x, :any, required: true)
    attr(:y, :any, required: true)
    attr(:width, :integer, default: @bar.width)
    attr(:height, :integer, default: @bar.height)
    attr(:margin, :map, default: @bar.margin)
    attr(:fill, :string, default: @bar.fill)
    attr(:animate, :boolean, default: @bar.animate)
    attr(:class, :string, default: @bar.class)
    attr(:responsive, :boolean, default: @bar.responsive)
    attr(:theme, :any, default: @bar.theme)
    attr(:title, :string, default: @bar.title)
    attr(:description, :string, default: @bar.description)
    attr(:padding, :float, default: @bar.padding)

    def bar_chart(assigns) do
      drawn = Support.draw(:bar_chart, assigns)
      [bars] = Support.marks(drawn.group)

      assigns =
        assign(assigns,
          margin: drawn.margin,
          inner_height: drawn.plot.height,
          bars: Enum.map(bars.children, &rect/1),
          fill: bars.style.fill,
          theme: drawn.theme,
          ids: drawn.ids,
          x_axis: Support.axis(drawn.group, :bottom),
          y_axis: Support.axis(drawn.group, :left),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids, @animate)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc><style :if={@animate}><%= Support.reduced_motion() %></style>
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>{@x_axis}</g>
          <g class="y-axis">{@y_axis}</g>
          <rect
            :for={bar <- @bars}
            x={bar.x}
            y={bar.y}
            width={bar.w}
            height={bar.h}
            fill={@fill}
            {@transition}
          />
        </g>
      </svg>
      """
    end

    @doc """
    Renders a horizontal bar chart: `bar_chart/1` with the roles swapped - `y` is the
    category accessor on a band scale down the left, `x` the numeric accessor on a linear
    scale from zero along the bottom.

    ## Assigns

    As `bar_chart/1`, with `margin` merged over `%{top: 20, right: 20, bottom: 30, left: 100}`
    to leave room for the category labels.
    """
    attr(:data, :any, required: true)
    attr(:x, :any, required: true)
    attr(:y, :any, required: true)
    attr(:width, :integer, default: @horizontal.width)
    attr(:height, :integer, default: @horizontal.height)
    attr(:margin, :map, default: @horizontal.margin)
    attr(:fill, :string, default: @horizontal.fill)
    attr(:animate, :boolean, default: @horizontal.animate)
    attr(:class, :string, default: @horizontal.class)
    attr(:responsive, :boolean, default: @horizontal.responsive)
    attr(:theme, :any, default: @horizontal.theme)
    attr(:title, :string, default: @horizontal.title)
    attr(:description, :string, default: @horizontal.description)
    attr(:padding, :float, default: @horizontal.padding)

    def horizontal_bar_chart(assigns) do
      drawn = Support.draw(:horizontal_bar_chart, assigns)
      [bars] = Support.marks(drawn.group)

      assigns =
        assign(assigns,
          margin: drawn.margin,
          inner_height: drawn.plot.height,
          bars: Enum.map(bars.children, &rect/1),
          fill: bars.style.fill,
          theme: drawn.theme,
          ids: drawn.ids,
          x_axis: Support.axis(drawn.group, :bottom),
          y_axis: Support.axis(drawn.group, :left),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids, @animate)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc><style :if={@animate}><%= Support.reduced_motion() %></style>
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>{@x_axis}</g>
          <g class="y-axis">{@y_axis}</g>
          <rect
            :for={bar <- @bars}
            x={bar.x}
            y={bar.y}
            width={bar.w}
            height={bar.h}
            fill={@fill}
            {@transition}
          />
        </g>
      </svg>
      """
    end

    @doc """
    Renders a pie or donut chart.

    ## Assigns

    * `data` - the slices (required); empty renders an empty `<svg>`
    * `value` - accessor to the slice value (required)
    * `label` - accessor to the label text; drawn only when `show_labels` is also true
    * `width`, `height` - pixels (default 400 by 400)
    * `inner_radius` - greater than 0 makes a donut (default 0)
    * `outer_radius` - `nil` means `min(width, height) / 2 - 10`
    * `pad_angle` - radians between slices (default 0.02)
    * `colors` - scheme atom or color list; the i-th slice takes the i-th color
      (default `:category10`)
    * `show_labels` - (default `true`)
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions

    A label sits at the centroid of the slice's mid-radius, as `Visualize.Shape.Arc.centroid/2`
    computes it, inked the theme's text or background, whichever reads on the slice; a
    slice too narrow for its whole label draws none.
    """
    attr(:data, :any, required: true)
    attr(:value, :any, required: true)
    attr(:label, :any, default: @pie.label)
    attr(:width, :integer, default: @pie.width)
    attr(:height, :integer, default: @pie.height)
    attr(:inner_radius, :integer, default: @pie.inner_radius)
    attr(:outer_radius, :integer, default: @pie.outer_radius)
    attr(:pad_angle, :float, default: @pie.pad_angle)
    attr(:colors, :any, default: @pie.colors)
    attr(:animate, :boolean, default: @pie.animate)
    attr(:class, :string, default: @pie.class)
    attr(:responsive, :boolean, default: @pie.responsive)
    attr(:theme, :any, default: @pie.theme)
    attr(:title, :string, default: @pie.title)
    attr(:description, :string, default: @pie.description)
    attr(:show_labels, :boolean, default: @pie.show_labels)

    def pie_chart(assigns) do
      drawn = Support.draw(:pie_chart, assigns)
      [arcs] = Support.marks(drawn.group)
      {paths, texts} = Enum.split_with(arcs.children, &(&1.type == :path))

      # The labels the layer kept, each in its own contrast ink, follow every slice — the
      # order the layer draws a labeled mark in, and the only one there is, since a label
      # its fit hid has no text to pair with its slice (spec/10 §2.5, #494).
      labels =
        for text <- texts, text.content != "" do
          %{text: text.content, x: fmt(text.attrs.x), y: fmt(text.attrs.y), fill: text.style.fill}
        end

      slices =
        paths
        |> Enum.map(&%{d: Support.d(&1), fill: &1.style.fill})
        |> Support.followed(labels)

      assigns =
        assign(assigns,
          slices: slices,
          center: {fmt(drawn.plot.width / 2), fmt(drawn.plot.height / 2)},
          stroke: arcs.style.stroke,
          stroke_width: arcs.style.stroke_width,
          theme: drawn.theme,
          ids: drawn.ids,
          label_size: Support.css(drawn.theme, :label_size),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids, @animate)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc><style :if={@animate}><%= Support.reduced_motion() %></style>
        <g transform={"translate(#{elem(@center, 0)}, #{elem(@center, 1)})"}>
          <%= for slice <- @slices do %>
            <path d={slice.d} fill={slice.fill} stroke={@stroke} stroke-width={@stroke_width} {@transition} />
            <%= for label <- slice.labels do %>
              <text
                x={label.x}
                y={label.y}
                text-anchor="middle"
                dominant-baseline="middle"
                font-size={@label_size}
                fill={label.fill}
              >{label.text}</text>
            <% end %>
          <% end %>
        </g>
      </svg>
      """
    end

    @doc """
    Renders a scatter plot: one circle per datum on two linear scales over the extents of
    the values.

    ## Assigns

    * `data` - the data points (required); empty renders the frame alone
    * `x`, `y` - numeric accessors (required)
    * `width`, `height` - pixels (default 600 by 400)
    * `margin` - merged over `%{top: 20, right: 20, bottom: 30, left: 40}`
    * `fill` - point color (default `nil`: the theme's `:series_1`)
    * `size` - the radius, or a one-argument function of the datum returning it
      (default 5)
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions
    """
    attr(:data, :any, required: true)
    attr(:x, :any, required: true)
    attr(:y, :any, required: true)
    attr(:width, :integer, default: @scatter.width)
    attr(:height, :integer, default: @scatter.height)
    attr(:margin, :map, default: @scatter.margin)
    attr(:fill, :string, default: @scatter.fill)
    attr(:size, :any, default: @scatter.size)
    attr(:animate, :boolean, default: @scatter.animate)
    attr(:class, :string, default: @scatter.class)
    attr(:responsive, :boolean, default: @scatter.responsive)
    attr(:theme, :any, default: @scatter.theme)
    attr(:title, :string, default: @scatter.title)
    attr(:description, :string, default: @scatter.description)

    def scatter_plot(assigns) do
      drawn = Support.draw(:scatter_plot, assigns)
      [points] = Support.marks(drawn.group)

      circles =
        for %{attrs: %{cx: cx, cy: cy, r: r}} <- points.children,
            do: %{cx: fmt(cx), cy: fmt(cy), r: fmt(r)}

      assigns =
        assign(assigns,
          margin: drawn.margin,
          inner_height: drawn.plot.height,
          points: circles,
          fill: points.style.fill,
          opacity: points.style.opacity,
          theme: drawn.theme,
          ids: drawn.ids,
          x_axis: Support.axis(drawn.group, :bottom),
          y_axis: Support.axis(drawn.group, :left),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids, @animate)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc><style :if={@animate}><%= Support.reduced_motion() %></style>
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>{@x_axis}</g>
          <g class="y-axis">{@y_axis}</g>
          <circle
            :for={point <- @points}
            cx={point.cx}
            cy={point.cy}
            r={point.r}
            fill={@fill}
            opacity={@opacity}
            {@transition}
          />
        </g>
      </svg>
      """
    end

    @doc """
    Renders an area chart: the area from the baseline up to the series, then the series
    line on top of it.

    ## Assigns

    * `data` - the data points (required); empty renders the frame alone
    * `x` - as `line_chart/1`: time, linear or band by the first datum (required)
    * `y` - accessor to a non-negative number; the y domain is `[0, max]` (required)
    * `width`, `height` - pixels (default 600 by 400)
    * `margin` - merged over `%{top: 20, right: 20, bottom: 30, left: 40}`
    * `fill`, `fill_opacity` - the area (default `nil`, the theme's `:series_1`, at 0.3)
    * `stroke`, `stroke_width` - the line (default `nil`, the theme's `:series_1`, 2)
    * `curve` - applied to both the area and the line (default `:linear`)
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions
    """
    attr(:data, :any, required: true)
    attr(:x, :any, required: true)
    attr(:y, :any, required: true)
    attr(:width, :integer, default: @area.width)
    attr(:height, :integer, default: @area.height)
    attr(:margin, :map, default: @area.margin)
    attr(:fill, :string, default: @area.fill)
    attr(:fill_opacity, :float, default: @area.fill_opacity)
    attr(:stroke, :string, default: @area.stroke)
    attr(:stroke_width, :integer, default: @area.stroke_width)
    attr(:curve, :atom, default: @area.curve)
    attr(:animate, :boolean, default: @area.animate)
    attr(:class, :string, default: @area.class)
    attr(:responsive, :boolean, default: @area.responsive)
    attr(:theme, :any, default: @area.theme)
    attr(:title, :string, default: @area.title)
    attr(:description, :string, default: @area.description)

    def area_chart(assigns) do
      drawn = Support.draw(:area_chart, assigns)
      [area, line] = Support.marks(drawn.group)

      assigns =
        assign(assigns,
          margin: drawn.margin,
          inner_height: drawn.plot.height,
          area_path: Support.path(area),
          line_path: Support.path(line),
          fill: area.style.fill,
          stroke: line.style.stroke,
          theme: drawn.theme,
          ids: drawn.ids,
          x_axis: Support.axis(drawn.group, :bottom),
          y_axis: Support.axis(drawn.group, :left),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids, @animate)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc><style :if={@animate}><%= Support.reduced_motion() %></style>
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>{@x_axis}</g>
          <g class="y-axis">{@y_axis}</g>
          <path
            :if={@area_path}
            d={@area_path}
            fill={@fill}
            fill-opacity={@fill_opacity}
            {@transition}
          />
          <path
            :if={@line_path}
            d={@line_path}
            fill="none"
            stroke={@stroke}
            stroke-width={@stroke_width}
            {@transition}
          />
        </g>
      </svg>
      """
    end

    @doc """
    Renders a stacked bar chart: one bar per category, one segment per key, stacked by
    the `:stack` transform of spec/14 §5.4.

    ## Assigns

    * `data` - one map per category (required); empty renders the frame alone
    * `x` - accessor to the category, applied to each point's `data` (required)
    * `keys` - the series keys read from each datum (required)
    * `width`, `height` - pixels (default 600 by 400)
    * `margin` - merged over `%{top: 20, right: 20, bottom: 30, left: 40}`
    * `colors` - scheme atom or color list, one color per key in order
      (default `:category10`)
    * `padding` - band padding (default 0.1)
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions

    The y domain is `[0, max y1]` over every point of every series.
    """
    attr(:data, :any, required: true)
    attr(:x, :any, required: true)
    attr(:keys, :list, required: true)
    attr(:width, :integer, default: @stacked.width)
    attr(:height, :integer, default: @stacked.height)
    attr(:margin, :map, default: @stacked.margin)
    attr(:colors, :any, default: @stacked.colors)
    attr(:animate, :boolean, default: @stacked.animate)
    attr(:class, :string, default: @stacked.class)
    attr(:responsive, :boolean, default: @stacked.responsive)
    attr(:theme, :any, default: @stacked.theme)
    attr(:title, :string, default: @stacked.title)
    attr(:description, :string, default: @stacked.description)
    attr(:padding, :float, default: @stacked.padding)

    def stacked_bar_chart(assigns) do
      drawn = Support.draw(:stacked_bar_chart, assigns)
      [segments] = Support.marks(drawn.group)

      assigns =
        assign(assigns,
          margin: drawn.margin,
          inner_height: drawn.plot.height,
          bars: Enum.map(segments.children, &Map.put(rect(&1), :fill, &1.style.fill)),
          theme: drawn.theme,
          ids: drawn.ids,
          x_axis: Support.axis(drawn.group, :bottom),
          y_axis: Support.axis(drawn.group, :left),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids, @animate)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc><style :if={@animate}><%= Support.reduced_motion() %></style>
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>{@x_axis}</g>
          <g class="y-axis">{@y_axis}</g>
          <rect
            :for={bar <- @bars}
            x={bar.x}
            y={bar.y}
            width={bar.w}
            height={bar.h}
            fill={bar.fill}
            {@transition}
          />
        </g>
      </svg>
      """
    end

    # The frame's labels as the x and y axis titles: the x title first when it is given.
    defp titles(labels, nil), do: {nil, List.first(labels)}
    defp titles([x | rest], _x_label), do: {x, List.first(rest)}

    # A rect element's geometry as the template prints it.
    defp rect(%{attrs: %{x: x, y: y, width: w, height: h}}),
      do: %{x: fmt(x), y: fmt(y), w: fmt(w), h: fmt(h)}

    defp fmt(number), do: Support.fmt(number)
  end
end
