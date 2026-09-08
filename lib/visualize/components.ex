if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Components do
    @moduledoc """
    Phoenix LiveView function components for the common chart types (spec/10 §2).

    Each component builds one complete `<svg>` from its assigns through the library's own
    layers: `Visualize.Scale.apply/2` for every coordinate, `Visualize.Shape.generate/2`
    for every path and `Visualize.Axis.render/1` for the axes.

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
      every value zero) spans one unit from its value, so a single datum renders too.
    - `colors` is a scheme atom of `Visualize.Scale.Color.schemes/0`, whose colours are
      taken by index and cycled, or an explicit list of colours used as given. An unknown
      scheme or an empty list raises `ArgumentError`.
    - `animate={true}` puts `style="transition: all 0.3s ease-in-out;"` on every mark, so
      LiveView's DOM patches animate through CSS.
    - `theme` is a `Visualize.Theme` (default `Visualize.Theme.default/0`); every colour,
      font and size that is not an explicit assign is a slot of it, rendered as a CSS
      reference with the literal as fallback so a stylesheet overrides it (D-55). A colour
      assign left `nil` takes the slot its documentation names.
    - `margin` is merged over the component's default, so `%{left: 60}` moves one side.

    This module compiles only when `Phoenix.Component` is loaded: `phoenix_live_view` is an
    optional dependency, present in a host that has LiveView and never fetched otherwise.
    """

    use Phoenix.Component

    alias Visualize.{Axis, Scale, Shape}
    alias Visualize.Components.Support

    @default_margin %{top: 20, right: 20, bottom: 30, left: 40}
    @horizontal_margin %{top: 20, right: 20, bottom: 30, left: 100}

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
    * `stroke` - line colour, also the point fill (default `nil`: the theme's `:series_1`)
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
    attr(:width, :integer, default: 600)
    attr(:height, :integer, default: 400)
    attr(:margin, :map, default: @default_margin)
    attr(:curve, :atom, default: :linear)
    attr(:stroke, :string, default: nil)
    attr(:stroke_width, :integer, default: 2)
    attr(:animate, :boolean, default: false)
    attr(:class, :string, default: nil)
    attr(:responsive, :boolean, default: false)
    attr(:theme, :any, default: nil)
    attr(:title, :string, default: nil)
    attr(:description, :string, default: nil)
    attr(:x_label, :string, default: nil)
    attr(:y_label, :string, default: nil)
    attr(:show_points, :boolean, default: false)

    def line_chart(assigns) do
      assigns = Support.rows(assigns)
      theme = Support.theme(assigns.theme)
      ids = Support.label_ids(assigns.title, assigns.description)
      {margin, inner_width, inner_height} = Support.frame(assigns, @default_margin)
      x_scale = Support.x_scale(assigns.data, assigns.x, inner_width)

      y_scale =
        Scale.linear()
        |> Scale.domain(Support.extent(assigns.data, assigns.y))
        |> Scale.range([inner_height, 0])

      x = fn d -> Scale.apply(x_scale, assigns.x.(d)) end
      y = fn d -> Scale.apply(y_scale, assigns.y.(d)) end
      line = Shape.line() |> Shape.x(x) |> Shape.y(y) |> Shape.curve(assigns.curve)

      points =
        if assigns.show_points, do: Enum.map(assigns.data, &{fmt(x.(&1)), fmt(y.(&1))}), else: []

      assigns =
        assign(assigns,
          margin: margin,
          inner_width: inner_width,
          inner_height: inner_height,
          path: Shape.generate(line, assigns.data),
          points: points,
          stroke: Support.colour(assigns.stroke, theme, :series_1),
          text: Support.css(theme, :text),
          label_size: Support.css(theme, :label_size),
          theme: theme,
          ids: ids,
          x_axis: axis(Axis.bottom(x_scale), theme),
          y_axis: axis(Axis.left(y_scale), theme),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc>
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>{@x_axis}</g>
          <g class="y-axis">{@y_axis}</g>
          <path
            :if={@data != []}
            d={@path}
            fill="none"
            stroke={@stroke}
            stroke-width={@stroke_width}
            {@transition}
          />
          <circle :for={{cx, cy} <- @points} cx={cx} cy={cy} r="4" fill={@stroke} {@transition} />
          <text
            :if={@x_label}
            x={fmt(@inner_width / 2)}
            y={@inner_height + @margin.bottom - 5}
            text-anchor="middle"
            font-size={@label_size}
            fill={@text}
            class="axis-label"
          >{@x_label}</text>
          <text
            :if={@y_label}
            transform="rotate(-90)"
            x={fmt(-@inner_height / 2)}
            y={-@margin.left + 15}
            text-anchor="middle"
            font-size={@label_size}
            fill={@text}
            class="axis-label"
          >{@y_label}</text>
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
    * `fill` - bar colour (default `nil`: the theme's `:series_1`)
    * `padding` - band padding, 0 to 1 (default 0.1)
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions
    """
    attr(:data, :any, required: true)
    attr(:x, :any, required: true)
    attr(:y, :any, required: true)
    attr(:width, :integer, default: 600)
    attr(:height, :integer, default: 400)
    attr(:margin, :map, default: @default_margin)
    attr(:fill, :string, default: nil)
    attr(:animate, :boolean, default: false)
    attr(:class, :string, default: nil)
    attr(:responsive, :boolean, default: false)
    attr(:theme, :any, default: nil)
    attr(:title, :string, default: nil)
    attr(:description, :string, default: nil)
    attr(:padding, :float, default: 0.1)

    def bar_chart(assigns) do
      assigns = Support.rows(assigns)
      theme = Support.theme(assigns.theme)
      ids = Support.label_ids(assigns.title, assigns.description)
      {margin, inner_width, inner_height} = Support.frame(assigns, @default_margin)

      x_scale =
        Scale.band()
        |> Scale.domain(Enum.map(assigns.data, assigns.x))
        |> Scale.range([0, inner_width])
        |> Scale.padding(assigns.padding)

      y_scale =
        Scale.linear()
        |> Scale.domain(Support.from_zero(assigns.data, assigns.y))
        |> Scale.range([inner_height, 0])

      bandwidth = Scale.bandwidth(x_scale)

      bars =
        for d <- assigns.data do
          y = Scale.apply(y_scale, assigns.y.(d))

          %{
            x: fmt(Scale.apply(x_scale, assigns.x.(d))),
            y: fmt(y),
            w: fmt(bandwidth),
            h: fmt(inner_height - y)
          }
        end

      assigns =
        assign(assigns,
          margin: margin,
          inner_height: inner_height,
          bars: bars,
          fill: Support.colour(assigns.fill, theme, :series_1),
          theme: theme,
          ids: ids,
          x_axis: axis(Axis.bottom(x_scale), theme),
          y_axis: axis(Axis.left(y_scale), theme),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc>
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
    attr(:width, :integer, default: 600)
    attr(:height, :integer, default: 400)
    attr(:margin, :map, default: @horizontal_margin)
    attr(:fill, :string, default: nil)
    attr(:animate, :boolean, default: false)
    attr(:class, :string, default: nil)
    attr(:responsive, :boolean, default: false)
    attr(:theme, :any, default: nil)
    attr(:title, :string, default: nil)
    attr(:description, :string, default: nil)
    attr(:padding, :float, default: 0.1)

    def horizontal_bar_chart(assigns) do
      assigns = Support.rows(assigns)
      theme = Support.theme(assigns.theme)
      ids = Support.label_ids(assigns.title, assigns.description)
      {margin, inner_width, inner_height} = Support.frame(assigns, @horizontal_margin)

      y_scale =
        Scale.band()
        |> Scale.domain(Enum.map(assigns.data, assigns.y))
        |> Scale.range([0, inner_height])
        |> Scale.padding(assigns.padding)

      x_scale =
        Scale.linear()
        |> Scale.domain(Support.from_zero(assigns.data, assigns.x))
        |> Scale.range([0, inner_width])

      bandwidth = Scale.bandwidth(y_scale)

      bars =
        for d <- assigns.data do
          %{
            y: fmt(Scale.apply(y_scale, assigns.y.(d))),
            w: fmt(Scale.apply(x_scale, assigns.x.(d))),
            h: fmt(bandwidth)
          }
        end

      assigns =
        assign(assigns,
          margin: margin,
          inner_height: inner_height,
          bars: bars,
          fill: Support.colour(assigns.fill, theme, :series_1),
          theme: theme,
          ids: ids,
          x_axis: axis(Axis.bottom(x_scale), theme),
          y_axis: axis(Axis.left(y_scale), theme),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc>
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>{@x_axis}</g>
          <g class="y-axis">{@y_axis}</g>
          <rect
            :for={bar <- @bars}
            x="0"
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
    * `colors` - scheme atom or colour list; the i-th slice takes the i-th colour
      (default `:category10`)
    * `show_labels` - (default `true`)
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions

    A label sits at the centroid of the slice's mid-radius, as `Visualize.Shape.Arc.centroid/2`
    computes it.
    """
    attr(:data, :any, required: true)
    attr(:value, :any, required: true)
    attr(:label, :any, default: nil)
    attr(:width, :integer, default: 400)
    attr(:height, :integer, default: 400)
    attr(:inner_radius, :integer, default: 0)
    attr(:outer_radius, :integer, default: nil)
    attr(:pad_angle, :float, default: 0.02)
    attr(:colors, :any, default: :category10)
    attr(:animate, :boolean, default: false)
    attr(:class, :string, default: nil)
    attr(:responsive, :boolean, default: false)
    attr(:theme, :any, default: nil)
    attr(:title, :string, default: nil)
    attr(:description, :string, default: nil)
    attr(:show_labels, :boolean, default: true)

    def pie_chart(assigns) do
      assigns = Support.rows(assigns)
      theme = Support.theme(assigns.theme)
      ids = Support.label_ids(assigns.title, assigns.description)
      outer_radius = assigns.outer_radius || min(assigns.width, assigns.height) / 2 - 10
      pie = Shape.pie() |> Shape.value(assigns.value) |> Shape.pad_angle(assigns.pad_angle)

      arc =
        Shape.arc()
        |> Shape.inner_radius(assigns.inner_radius)
        |> Shape.outer_radius(outer_radius)

      arcs = Shape.generate(pie, assigns.data)
      palette = Support.palette(assigns.colors, length(arcs))
      label = if assigns.show_labels, do: assigns.label

      slices =
        for {a, i} <- Enum.with_index(arcs) do
          {x, y} = Shape.Arc.centroid(arc, a)

          %{
            d: Shape.generate(arc, a),
            fill: Scale.apply(palette, i),
            label: label && label.(a.data),
            x: fmt(x),
            y: fmt(y)
          }
        end

      assigns =
        assign(assigns,
          slices: slices,
          theme: theme,
          ids: ids,
          background: Support.css(theme, :background),
          label_size: Support.css(theme, :label_size),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc>
        <g transform={"translate(#{fmt(@width / 2)}, #{fmt(@height / 2)})"}>
          <%= for slice <- @slices do %>
            <path d={slice.d} fill={slice.fill} stroke={@background} stroke-width="2" {@transition} />
            <text
              :if={slice.label}
              x={slice.x}
              y={slice.y}
              text-anchor="middle"
              dominant-baseline="middle"
              font-size={@label_size}
              fill={@background}
            >{slice.label}</text>
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
    * `fill` - point colour (default `nil`: the theme's `:series_1`)
    * `size` - the radius, or a one-argument function of the datum returning it
      (default 5)
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions
    """
    attr(:data, :any, required: true)
    attr(:x, :any, required: true)
    attr(:y, :any, required: true)
    attr(:width, :integer, default: 600)
    attr(:height, :integer, default: 400)
    attr(:margin, :map, default: @default_margin)
    attr(:fill, :string, default: nil)
    attr(:size, :any, default: 5)
    attr(:animate, :boolean, default: false)
    attr(:class, :string, default: nil)
    attr(:responsive, :boolean, default: false)
    attr(:theme, :any, default: nil)
    attr(:title, :string, default: nil)
    attr(:description, :string, default: nil)

    def scatter_plot(assigns) do
      assigns = Support.rows(assigns)
      theme = Support.theme(assigns.theme)
      ids = Support.label_ids(assigns.title, assigns.description)
      {margin, inner_width, inner_height} = Support.frame(assigns, @default_margin)

      x_scale =
        Scale.linear()
        |> Scale.domain(Support.extent(assigns.data, assigns.x))
        |> Scale.range([0, inner_width])

      y_scale =
        Scale.linear()
        |> Scale.domain(Support.extent(assigns.data, assigns.y))
        |> Scale.range([inner_height, 0])

      points =
        for d <- assigns.data do
          %{
            cx: fmt(Scale.apply(x_scale, assigns.x.(d))),
            cy: fmt(Scale.apply(y_scale, assigns.y.(d))),
            r: fmt(radius(assigns.size, d))
          }
        end

      assigns =
        assign(assigns,
          margin: margin,
          inner_height: inner_height,
          points: points,
          fill: Support.colour(assigns.fill, theme, :series_1),
          theme: theme,
          ids: ids,
          x_axis: axis(Axis.bottom(x_scale), theme),
          y_axis: axis(Axis.left(y_scale), theme),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc>
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>{@x_axis}</g>
          <g class="y-axis">{@y_axis}</g>
          <circle
            :for={point <- @points}
            cx={point.cx}
            cy={point.cy}
            r={point.r}
            fill={@fill}
            opacity="0.7"
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
    attr(:width, :integer, default: 600)
    attr(:height, :integer, default: 400)
    attr(:margin, :map, default: @default_margin)
    attr(:fill, :string, default: nil)
    attr(:fill_opacity, :float, default: 0.3)
    attr(:stroke, :string, default: nil)
    attr(:stroke_width, :integer, default: 2)
    attr(:curve, :atom, default: :linear)
    attr(:animate, :boolean, default: false)
    attr(:class, :string, default: nil)
    attr(:responsive, :boolean, default: false)
    attr(:theme, :any, default: nil)
    attr(:title, :string, default: nil)
    attr(:description, :string, default: nil)

    def area_chart(assigns) do
      assigns = Support.rows(assigns)
      theme = Support.theme(assigns.theme)
      ids = Support.label_ids(assigns.title, assigns.description)
      {margin, inner_width, inner_height} = Support.frame(assigns, @default_margin)
      x_scale = Support.x_scale(assigns.data, assigns.x, inner_width)

      y_scale =
        Scale.linear()
        |> Scale.domain(Support.from_zero(assigns.data, assigns.y))
        |> Scale.range([inner_height, 0])

      x = fn d -> Scale.apply(x_scale, assigns.x.(d)) end
      y = fn d -> Scale.apply(y_scale, assigns.y.(d)) end

      area =
        Shape.area()
        |> Shape.x(x)
        |> Shape.y0(inner_height)
        |> Shape.y1(y)
        |> Shape.curve(assigns.curve)

      line = Shape.line() |> Shape.x(x) |> Shape.y(y) |> Shape.curve(assigns.curve)

      assigns =
        assign(assigns,
          margin: margin,
          inner_height: inner_height,
          area_path: Shape.generate(area, assigns.data),
          line_path: Shape.generate(line, assigns.data),
          fill: Support.colour(assigns.fill, theme, :series_1),
          stroke: Support.colour(assigns.stroke, theme, :series_1),
          theme: theme,
          ids: ids,
          x_axis: axis(Axis.bottom(x_scale), theme),
          y_axis: axis(Axis.left(y_scale), theme),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc>
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>{@x_axis}</g>
          <g class="y-axis">{@y_axis}</g>
          <path
            :if={@data != []}
            d={@area_path}
            fill={@fill}
            fill-opacity={@fill_opacity}
            {@transition}
          />
          <path
            :if={@data != []}
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
    `Visualize.Shape.stack/0`.

    ## Assigns

    * `data` - one map per category (required); empty renders the frame alone
    * `x` - accessor to the category, applied to each point's `data` (required)
    * `keys` - the series keys read from each datum (required)
    * `width`, `height` - pixels (default 600 by 400)
    * `margin` - merged over `%{top: 20, right: 20, bottom: 30, left: 40}`
    * `colors` - scheme atom or colour list, one colour per key in order
      (default `:category10`)
    * `padding` - band padding (default 0.1)
    * `animate`, `class`, `responsive`, `theme`, `title`, `description` - per the module
      conventions

    The y domain is `[0, max y1]` over every point of every series.
    """
    attr(:data, :any, required: true)
    attr(:x, :any, required: true)
    attr(:keys, :list, required: true)
    attr(:width, :integer, default: 600)
    attr(:height, :integer, default: 400)
    attr(:margin, :map, default: @default_margin)
    attr(:colors, :any, default: :category10)
    attr(:animate, :boolean, default: false)
    attr(:class, :string, default: nil)
    attr(:responsive, :boolean, default: false)
    attr(:theme, :any, default: nil)
    attr(:title, :string, default: nil)
    attr(:description, :string, default: nil)
    attr(:padding, :float, default: 0.1)

    def stacked_bar_chart(assigns) do
      assigns = Support.rows(assigns)
      theme = Support.theme(assigns.theme)
      ids = Support.label_ids(assigns.title, assigns.description)
      {margin, inner_width, inner_height} = Support.frame(assigns, @default_margin)
      series = Shape.generate(Shape.stack() |> Shape.keys(assigns.keys), assigns.data)
      tops = for s <- series, p <- s.points, do: p.y1

      x_scale =
        Scale.band()
        |> Scale.domain(Enum.map(assigns.data, assigns.x))
        |> Scale.range([0, inner_width])
        |> Scale.padding(assigns.padding)

      y_scale =
        Scale.linear()
        |> Scale.domain(Support.span([0, max(0, Enum.max(tops, fn -> 0 end))]))
        |> Scale.range([inner_height, 0])

      bandwidth = Scale.bandwidth(x_scale)
      palette = Support.palette(assigns.colors, length(assigns.keys))

      bars =
        for {s, i} <- Enum.with_index(series), p <- s.points do
          y1 = Scale.apply(y_scale, p.y1)

          %{
            x: fmt(Scale.apply(x_scale, assigns.x.(p.data))),
            y: fmt(y1),
            w: fmt(bandwidth),
            h: fmt(Scale.apply(y_scale, p.y0) - y1),
            fill: Scale.apply(palette, i)
          }
        end

      assigns =
        assign(assigns,
          margin: margin,
          inner_height: inner_height,
          bars: bars,
          theme: theme,
          ids: ids,
          x_axis: axis(Axis.bottom(x_scale), theme),
          y_axis: axis(Axis.left(y_scale), theme),
          transition: Support.transition(assigns.animate)
        )

      ~H"""
      <svg width={@width} height={@height} {Support.svg_attrs(@class, @responsive, @theme, @ids)} viewBox={"0 0 #{@width} #{@height}"}>
        <title :if={@ids.title} id={@ids.title}>{@title}</title>
        <desc :if={@ids.desc} id={@ids.desc}>{@description}</desc>
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

    # `Visualize.Axis.render/1` is a plain string; `raw/1` marks it safe for HEEx.
    defp axis(axis, theme), do: Phoenix.HTML.raw(Axis.render(Axis.theme(axis, theme)))

    defp fmt(number), do: Support.fmt(number)

    defp radius(size, _d) when is_number(size), do: size
    defp radius(size, d) when is_function(size, 1), do: size.(d)
  end
end
