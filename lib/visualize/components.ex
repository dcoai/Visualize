if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Components do
    @moduledoc """
    Phoenix LiveView components for common chart types.

    Provides ready-to-use chart components that integrate with LiveView
    for reactive, real-time data visualization.

    ## Usage

        # In your LiveView or component
        use Phoenix.Component
        import Visualize.Components

        # Then in your template
        <.line_chart
          data={@data}
          x={& &1.date}
          y={& &1.value}
          width={600}
          height={400}
        />

    ## Available Components

    - `line_chart/1` - Line charts for time series
    - `bar_chart/1` - Vertical bar charts
    - `horizontal_bar_chart/1` - Horizontal bar charts
    - `pie_chart/1` - Pie and donut charts
    - `scatter_plot/1` - Scatter plots
    - `area_chart/1` - Area charts
    - `stacked_bar_chart/1` - Stacked bar charts

    ## Animation

    All components support CSS transitions for smooth updates.
    Set `animate={true}` and values will transition on change.

    """

    use Phoenix.Component

    alias Visualize.{Scale, Shape, Axis, SVG, Data}

    @default_margin %{top: 20, right: 20, bottom: 30, left: 40}

    @doc """
    Renders a line chart.

    ## Attributes

    * `data` - List of data points (required)
    * `x` - Accessor function for x values (required)
    * `y` - Accessor function for y values (required)
    * `width` - Chart width in pixels (default: 600)
    * `height` - Chart height in pixels (default: 400)
    * `margin` - Map with :top, :right, :bottom, :left (optional)
    * `curve` - Curve type: :linear, :monotone_x, :cardinal, etc. (default: :linear)
    * `stroke` - Line color (default: "steelblue")
    * `stroke_width` - Line width (default: 2)
    * `animate` - Enable CSS transitions (default: false)
    * `class` - Additional CSS class for the SVG
    * `x_label` - Label for x-axis
    * `y_label` - Label for y-axis
    * `show_points` - Show data points (default: false)

    ## Example

        <.line_chart
          data={@sales_data}
          x={& &1.date}
          y={& &1.revenue}
          curve={:monotone_x}
          stroke="blue"
        />

    """
    attr :data, :list, required: true
    attr :x, :any, required: true
    attr :y, :any, required: true
    attr :width, :integer, default: 600
    attr :height, :integer, default: 400
    attr :margin, :map, default: @default_margin
    attr :curve, :atom, default: :linear
    attr :stroke, :string, default: "steelblue"
    attr :stroke_width, :integer, default: 2
    attr :animate, :boolean, default: false
    attr :class, :string, default: nil
    attr :x_label, :string, default: nil
    attr :y_label, :string, default: nil
    attr :show_points, :boolean, default: false

    def line_chart(assigns) do
      margin = Map.merge(@default_margin, assigns.margin || %{})
      inner_width = assigns.width - margin.left - margin.right
      inner_height = assigns.height - margin.top - margin.bottom

      x_values = Enum.map(assigns.data, assigns.x)
      y_values = Enum.map(assigns.data, assigns.y)

      x_scale = build_x_scale(x_values, inner_width)
      y_scale = Scale.linear()
                |> Scale.domain(Data.extent(y_values))
                |> Scale.range([inner_height, 0])

      line = Shape.line()
             |> Shape.x(fn d -> Scale.scale(x_scale, assigns.x.(d)) end)
             |> Shape.y(fn d -> Scale.scale(y_scale, assigns.y.(d)) end)
             |> Shape.curve(assigns.curve)

      path_data = Shape.generate(line, assigns.data)

      x_axis = Axis.bottom(x_scale)
      y_axis = Axis.left(y_scale)

      transition_style = if assigns.animate, do: "transition: all 0.3s ease-in-out;", else: ""

      assigns = assign(assigns,
        margin: margin,
        inner_width: inner_width,
        inner_height: inner_height,
        path_data: path_data,
        x_axis: x_axis,
        y_axis: y_axis,
        x_scale: x_scale,
        y_scale: y_scale,
        transition_style: transition_style
      )

      ~H"""
      <svg
        width={@width}
        height={@height}
        class={@class}
        viewBox={"0 0 #{@width} #{@height}"}
      >
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>
            <%= raw(Axis.render(@x_axis)) %>
          </g>
          <g class="y-axis">
            <%= raw(Axis.render(@y_axis)) %>
          </g>

          <path
            d={@path_data}
            fill="none"
            stroke={@stroke}
            stroke-width={@stroke_width}
            style={@transition_style}
          />

          <%= if @show_points do %>
            <%= for d <- @data do %>
              <circle
                cx={Scale.scale(@x_scale, @x.(d))}
                cy={Scale.scale(@y_scale, @y.(d))}
                r="4"
                fill={@stroke}
                style={@transition_style}
              />
            <% end %>
          <% end %>

          <%= if @x_label do %>
            <text
              x={@inner_width / 2}
              y={@inner_height + @margin.bottom - 5}
              text-anchor="middle"
              class="axis-label"
            ><%= @x_label %></text>
          <% end %>

          <%= if @y_label do %>
            <text
              transform={"rotate(-90)"}
              x={-@inner_height / 2}
              y={-@margin.left + 15}
              text-anchor="middle"
              class="axis-label"
            ><%= @y_label %></text>
          <% end %>
        </g>
      </svg>
      """
    end

    @doc """
    Renders a vertical bar chart.

    ## Attributes

    * `data` - List of data points (required)
    * `x` - Accessor function for category/x values (required)
    * `y` - Accessor function for numeric/y values (required)
    * `width` - Chart width in pixels (default: 600)
    * `height` - Chart height in pixels (default: 400)
    * `margin` - Map with :top, :right, :bottom, :left (optional)
    * `fill` - Bar fill color (default: "steelblue")
    * `animate` - Enable CSS transitions (default: false)
    * `class` - Additional CSS class
    * `padding` - Padding between bars 0-1 (default: 0.1)

    """
    attr :data, :list, required: true
    attr :x, :any, required: true
    attr :y, :any, required: true
    attr :width, :integer, default: 600
    attr :height, :integer, default: 400
    attr :margin, :map, default: @default_margin
    attr :fill, :string, default: "steelblue"
    attr :animate, :boolean, default: false
    attr :class, :string, default: nil
    attr :padding, :float, default: 0.1

    def bar_chart(assigns) do
      margin = Map.merge(@default_margin, assigns.margin || %{})
      inner_width = assigns.width - margin.left - margin.right
      inner_height = assigns.height - margin.top - margin.bottom

      categories = Enum.map(assigns.data, assigns.x)
      y_values = Enum.map(assigns.data, assigns.y)

      x_scale = Scale.band()
                |> Scale.domain(categories)
                |> Scale.range([0, inner_width])
                |> Scale.padding(assigns.padding)

      y_scale = Scale.linear()
                |> Scale.domain([0, Enum.max(y_values)])
                |> Scale.range([inner_height, 0])

      x_axis = Axis.bottom(x_scale)
      y_axis = Axis.left(y_scale)

      transition_style = if assigns.animate, do: "transition: all 0.3s ease-in-out;", else: ""

      assigns = assign(assigns,
        margin: margin,
        inner_width: inner_width,
        inner_height: inner_height,
        x_scale: x_scale,
        y_scale: y_scale,
        x_axis: x_axis,
        y_axis: y_axis,
        transition_style: transition_style
      )

      ~H"""
      <svg
        width={@width}
        height={@height}
        class={@class}
        viewBox={"0 0 #{@width} #{@height}"}
      >
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>
            <%= raw(Axis.render(@x_axis)) %>
          </g>
          <g class="y-axis">
            <%= raw(Axis.render(@y_axis)) %>
          </g>

          <%= for d <- @data do %>
            <rect
              x={Scale.scale(@x_scale, @x.(d))}
              y={Scale.scale(@y_scale, @y.(d))}
              width={Scale.bandwidth(@x_scale)}
              height={@inner_height - Scale.scale(@y_scale, @y.(d))}
              fill={@fill}
              style={@transition_style}
            />
          <% end %>
        </g>
      </svg>
      """
    end

    @doc """
    Renders a horizontal bar chart.

    ## Attributes

    * `data` - List of data points (required)
    * `x` - Accessor for numeric values (required)
    * `y` - Accessor for category values (required)
    * `width` - Chart width in pixels (default: 600)
    * `height` - Chart height in pixels (default: 400)
    * `margin` - Map with :top, :right, :bottom, :left (optional)
    * `fill` - Bar fill color (default: "steelblue")
    * `animate` - Enable CSS transitions (default: false)
    * `padding` - Padding between bars 0-1 (default: 0.1)

    """
    attr :data, :list, required: true
    attr :x, :any, required: true
    attr :y, :any, required: true
    attr :width, :integer, default: 600
    attr :height, :integer, default: 400
    attr :margin, :map, default: %{top: 20, right: 20, bottom: 30, left: 100}
    attr :fill, :string, default: "steelblue"
    attr :animate, :boolean, default: false
    attr :class, :string, default: nil
    attr :padding, :float, default: 0.1

    def horizontal_bar_chart(assigns) do
      margin = Map.merge(%{top: 20, right: 20, bottom: 30, left: 100}, assigns.margin || %{})
      inner_width = assigns.width - margin.left - margin.right
      inner_height = assigns.height - margin.top - margin.bottom

      categories = Enum.map(assigns.data, assigns.y)
      x_values = Enum.map(assigns.data, assigns.x)

      y_scale = Scale.band()
                |> Scale.domain(categories)
                |> Scale.range([0, inner_height])
                |> Scale.padding(assigns.padding)

      x_scale = Scale.linear()
                |> Scale.domain([0, Enum.max(x_values)])
                |> Scale.range([0, inner_width])

      x_axis = Axis.bottom(x_scale)
      y_axis = Axis.left(y_scale)

      transition_style = if assigns.animate, do: "transition: all 0.3s ease-in-out;", else: ""

      assigns = assign(assigns,
        margin: margin,
        inner_width: inner_width,
        inner_height: inner_height,
        x_scale: x_scale,
        y_scale: y_scale,
        x_axis: x_axis,
        y_axis: y_axis,
        transition_style: transition_style
      )

      ~H"""
      <svg
        width={@width}
        height={@height}
        class={@class}
        viewBox={"0 0 #{@width} #{@height}"}
      >
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>
            <%= raw(Axis.render(@x_axis)) %>
          </g>
          <g class="y-axis">
            <%= raw(Axis.render(@y_axis)) %>
          </g>

          <%= for d <- @data do %>
            <rect
              x={0}
              y={Scale.scale(@y_scale, @y.(d))}
              width={Scale.scale(@x_scale, @x.(d))}
              height={Scale.bandwidth(@y_scale)}
              fill={@fill}
              style={@transition_style}
            />
          <% end %>
        </g>
      </svg>
      """
    end

    @doc """
    Renders a pie or donut chart.

    ## Attributes

    * `data` - List of data points (required)
    * `value` - Accessor function for slice values (required)
    * `label` - Accessor function for labels (optional)
    * `width` - Chart width in pixels (default: 400)
    * `height` - Chart height in pixels (default: 400)
    * `inner_radius` - Inner radius for donut chart (default: 0)
    * `outer_radius` - Outer radius (default: auto-calculated)
    * `pad_angle` - Padding between slices in radians (default: 0.02)
    * `colors` - Color scheme name or list of colors (default: :category10)
    * `animate` - Enable CSS transitions (default: false)
    * `show_labels` - Show slice labels (default: true)

    """
    attr :data, :list, required: true
    attr :value, :any, required: true
    attr :label, :any, default: nil
    attr :width, :integer, default: 400
    attr :height, :integer, default: 400
    attr :inner_radius, :integer, default: 0
    attr :outer_radius, :integer, default: nil
    attr :pad_angle, :float, default: 0.02
    attr :colors, :any, default: :category10
    attr :animate, :boolean, default: false
    attr :class, :string, default: nil
    attr :show_labels, :boolean, default: true

    def pie_chart(assigns) do
      radius = min(assigns.width, assigns.height) / 2
      outer_radius = assigns.outer_radius || radius - 10
      inner_radius = assigns.inner_radius

      pie = Shape.pie()
            |> Shape.value(assigns.value)
            |> Shape.pad_angle(assigns.pad_angle)

      arcs = Shape.generate(pie, assigns.data)

      arc_generator = Shape.arc()
                      |> Shape.inner_radius(inner_radius)
                      |> Shape.outer_radius(outer_radius)

      label_arc = Shape.arc()
                  |> Shape.inner_radius((inner_radius + outer_radius) / 2)
                  |> Shape.outer_radius((inner_radius + outer_radius) / 2)

      color_scale = get_color_scale(assigns.colors, length(assigns.data))

      transition_style = if assigns.animate, do: "transition: all 0.3s ease-in-out;", else: ""

      assigns = assign(assigns,
        radius: radius,
        arcs: arcs,
        arc_generator: arc_generator,
        label_arc: label_arc,
        color_scale: color_scale,
        transition_style: transition_style
      )

      ~H"""
      <svg
        width={@width}
        height={@height}
        class={@class}
        viewBox={"0 0 #{@width} #{@height}"}
      >
        <g transform={"translate(#{@width / 2}, #{@height / 2})"}>
          <%= for {arc, i} <- Enum.with_index(@arcs) do %>
            <% path_data = Shape.generate(@arc_generator, arc) %>
            <path
              d={path_data}
              fill={Enum.at(@color_scale, i)}
              stroke="white"
              stroke-width="2"
              style={@transition_style}
            />
            <%= if @show_labels && @label do %>
              <% centroid = arc_centroid(@label_arc, arc) %>
              <text
                x={elem(centroid, 0)}
                y={elem(centroid, 1)}
                text-anchor="middle"
                dominant-baseline="middle"
                font-size="12"
              ><%= @label.(arc.data) %></text>
            <% end %>
          <% end %>
        </g>
      </svg>
      """
    end

    @doc """
    Renders a scatter plot.

    ## Attributes

    * `data` - List of data points (required)
    * `x` - Accessor function for x values (required)
    * `y` - Accessor function for y values (required)
    * `width` - Chart width in pixels (default: 600)
    * `height` - Chart height in pixels (default: 400)
    * `margin` - Map with :top, :right, :bottom, :left (optional)
    * `fill` - Point fill color (default: "steelblue")
    * `size` - Point radius or accessor function (default: 5)
    * `animate` - Enable CSS transitions (default: false)

    """
    attr :data, :list, required: true
    attr :x, :any, required: true
    attr :y, :any, required: true
    attr :width, :integer, default: 600
    attr :height, :integer, default: 400
    attr :margin, :map, default: @default_margin
    attr :fill, :string, default: "steelblue"
    attr :size, :any, default: 5
    attr :animate, :boolean, default: false
    attr :class, :string, default: nil

    def scatter_plot(assigns) do
      margin = Map.merge(@default_margin, assigns.margin || %{})
      inner_width = assigns.width - margin.left - margin.right
      inner_height = assigns.height - margin.top - margin.bottom

      x_values = Enum.map(assigns.data, assigns.x)
      y_values = Enum.map(assigns.data, assigns.y)

      x_scale = Scale.linear()
                |> Scale.domain(Data.extent(x_values))
                |> Scale.range([0, inner_width])

      y_scale = Scale.linear()
                |> Scale.domain(Data.extent(y_values))
                |> Scale.range([inner_height, 0])

      x_axis = Axis.bottom(x_scale)
      y_axis = Axis.left(y_scale)

      transition_style = if assigns.animate, do: "transition: all 0.3s ease-in-out;", else: ""

      assigns = assign(assigns,
        margin: margin,
        inner_width: inner_width,
        inner_height: inner_height,
        x_scale: x_scale,
        y_scale: y_scale,
        x_axis: x_axis,
        y_axis: y_axis,
        transition_style: transition_style
      )

      ~H"""
      <svg
        width={@width}
        height={@height}
        class={@class}
        viewBox={"0 0 #{@width} #{@height}"}
      >
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>
            <%= raw(Axis.render(@x_axis)) %>
          </g>
          <g class="y-axis">
            <%= raw(Axis.render(@y_axis)) %>
          </g>

          <%= for d <- @data do %>
            <circle
              cx={Scale.scale(@x_scale, @x.(d))}
              cy={Scale.scale(@y_scale, @y.(d))}
              r={get_size(@size, d)}
              fill={@fill}
              opacity="0.7"
              style={@transition_style}
            />
          <% end %>
        </g>
      </svg>
      """
    end

    @doc """
    Renders an area chart.

    ## Attributes

    * `data` - List of data points (required)
    * `x` - Accessor function for x values (required)
    * `y` - Accessor function for y values (required)
    * `width` - Chart width in pixels (default: 600)
    * `height` - Chart height in pixels (default: 400)
    * `margin` - Map with :top, :right, :bottom, :left (optional)
    * `fill` - Area fill color (default: "steelblue")
    * `fill_opacity` - Fill opacity 0-1 (default: 0.3)
    * `stroke` - Line stroke color (default: "steelblue")
    * `stroke_width` - Line width (default: 2)
    * `curve` - Curve type (default: :linear)
    * `animate` - Enable CSS transitions (default: false)

    """
    attr :data, :list, required: true
    attr :x, :any, required: true
    attr :y, :any, required: true
    attr :width, :integer, default: 600
    attr :height, :integer, default: 400
    attr :margin, :map, default: @default_margin
    attr :fill, :string, default: "steelblue"
    attr :fill_opacity, :float, default: 0.3
    attr :stroke, :string, default: "steelblue"
    attr :stroke_width, :integer, default: 2
    attr :curve, :atom, default: :linear
    attr :animate, :boolean, default: false
    attr :class, :string, default: nil

    def area_chart(assigns) do
      margin = Map.merge(@default_margin, assigns.margin || %{})
      inner_width = assigns.width - margin.left - margin.right
      inner_height = assigns.height - margin.top - margin.bottom

      x_values = Enum.map(assigns.data, assigns.x)
      y_values = Enum.map(assigns.data, assigns.y)

      x_scale = build_x_scale(x_values, inner_width)
      y_scale = Scale.linear()
                |> Scale.domain([0, Enum.max(y_values)])
                |> Scale.range([inner_height, 0])

      area = Shape.area()
             |> Shape.x(fn d -> Scale.scale(x_scale, assigns.x.(d)) end)
             |> Shape.y0(inner_height)
             |> Shape.y1(fn d -> Scale.scale(y_scale, assigns.y.(d)) end)
             |> Shape.curve(assigns.curve)

      line = Shape.line()
             |> Shape.x(fn d -> Scale.scale(x_scale, assigns.x.(d)) end)
             |> Shape.y(fn d -> Scale.scale(y_scale, assigns.y.(d)) end)
             |> Shape.curve(assigns.curve)

      area_path = Shape.generate(area, assigns.data)
      line_path = Shape.generate(line, assigns.data)

      x_axis = Axis.bottom(x_scale)
      y_axis = Axis.left(y_scale)

      transition_style = if assigns.animate, do: "transition: all 0.3s ease-in-out;", else: ""

      assigns = assign(assigns,
        margin: margin,
        inner_width: inner_width,
        inner_height: inner_height,
        area_path: area_path,
        line_path: line_path,
        x_axis: x_axis,
        y_axis: y_axis,
        transition_style: transition_style
      )

      ~H"""
      <svg
        width={@width}
        height={@height}
        class={@class}
        viewBox={"0 0 #{@width} #{@height}"}
      >
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>
            <%= raw(Axis.render(@x_axis)) %>
          </g>
          <g class="y-axis">
            <%= raw(Axis.render(@y_axis)) %>
          </g>

          <path
            d={@area_path}
            fill={@fill}
            fill-opacity={@fill_opacity}
            style={@transition_style}
          />
          <path
            d={@line_path}
            fill="none"
            stroke={@stroke}
            stroke-width={@stroke_width}
            style={@transition_style}
          />
        </g>
      </svg>
      """
    end

    @doc """
    Renders a stacked bar chart.

    ## Attributes

    * `data` - List of data points (required)
    * `x` - Accessor function for category values (required)
    * `keys` - List of keys to stack (required)
    * `width` - Chart width in pixels (default: 600)
    * `height` - Chart height in pixels (default: 400)
    * `margin` - Map with :top, :right, :bottom, :left (optional)
    * `colors` - Color scheme or list (default: :category10)
    * `animate` - Enable CSS transitions (default: false)
    * `padding` - Padding between bars 0-1 (default: 0.1)

    """
    attr :data, :list, required: true
    attr :x, :any, required: true
    attr :keys, :list, required: true
    attr :width, :integer, default: 600
    attr :height, :integer, default: 400
    attr :margin, :map, default: @default_margin
    attr :colors, :any, default: :category10
    attr :animate, :boolean, default: false
    attr :class, :string, default: nil
    attr :padding, :float, default: 0.1

    def stacked_bar_chart(assigns) do
      margin = Map.merge(@default_margin, assigns.margin || %{})
      inner_width = assigns.width - margin.left - margin.right
      inner_height = assigns.height - margin.top - margin.bottom

      categories = Enum.map(assigns.data, assigns.x)

      stack = Shape.stack()
              |> Shape.keys(assigns.keys)

      series = Shape.generate(stack, assigns.data)

      max_y = series
              |> Enum.flat_map(fn s -> Enum.map(s.points, & &1.y1) end)
              |> Enum.max(fn -> 0 end)

      x_scale = Scale.band()
                |> Scale.domain(categories)
                |> Scale.range([0, inner_width])
                |> Scale.padding(assigns.padding)

      y_scale = Scale.linear()
                |> Scale.domain([0, max_y])
                |> Scale.range([inner_height, 0])

      x_axis = Axis.bottom(x_scale)
      y_axis = Axis.left(y_scale)

      color_scale = get_color_scale(assigns.colors, length(assigns.keys))

      transition_style = if assigns.animate, do: "transition: all 0.3s ease-in-out;", else: ""

      assigns = assign(assigns,
        margin: margin,
        inner_width: inner_width,
        inner_height: inner_height,
        series: series,
        x_scale: x_scale,
        y_scale: y_scale,
        x_axis: x_axis,
        y_axis: y_axis,
        color_scale: color_scale,
        transition_style: transition_style
      )

      ~H"""
      <svg
        width={@width}
        height={@height}
        class={@class}
        viewBox={"0 0 #{@width} #{@height}"}
      >
        <g transform={"translate(#{@margin.left}, #{@margin.top})"}>
          <g class="x-axis" transform={"translate(0, #{@inner_height})"}>
            <%= raw(Axis.render(@x_axis)) %>
          </g>
          <g class="y-axis">
            <%= raw(Axis.render(@y_axis)) %>
          </g>

          <%= for {s, i} <- Enum.with_index(@series) do %>
            <%= for point <- s.points do %>
              <rect
                x={Scale.scale(@x_scale, @x.(point.data))}
                y={Scale.scale(@y_scale, point.y1)}
                width={Scale.bandwidth(@x_scale)}
                height={Scale.scale(@y_scale, point.y0) - Scale.scale(@y_scale, point.y1)}
                fill={Enum.at(@color_scale, i)}
                style={@transition_style}
              />
            <% end %>
          <% end %>
        </g>
      </svg>
      """
    end

    # Helper functions

    defp build_x_scale(values, width) do
      first = hd(values)

      cond do
        is_struct(first, DateTime) or is_struct(first, NaiveDateTime) ->
          Scale.time()
          |> Scale.domain(Data.extent(values))
          |> Scale.range([0, width])

        is_number(first) ->
          Scale.linear()
          |> Scale.domain(Data.extent(values))
          |> Scale.range([0, width])

        true ->
          Scale.band()
          |> Scale.domain(values)
          |> Scale.range([0, width])
          |> Scale.padding(0.1)
      end
    end

    defp get_color_scale(scheme, count) when is_atom(scheme) do
      Scale.color()
      |> Scale.scheme(scheme)
      |> Scale.domain(Enum.to_list(0..(count - 1)))
      |> then(fn scale ->
        Enum.map(0..(count - 1), &Scale.scale(scale, &1))
      end)
    end

    defp get_color_scale(colors, _count) when is_list(colors), do: colors

    defp get_size(size, _d) when is_number(size), do: size
    defp get_size(size_fn, d) when is_function(size_fn, 1), do: size_fn.(d)

    defp arc_centroid(arc_generator, arc_data) do
      mid_angle = (arc_data.start_angle + arc_data.end_angle) / 2
      inner = arc_generator.inner_radius
      outer = arc_generator.outer_radius
      r = (inner + outer) / 2

      x = r * :math.sin(mid_angle)
      y = -r * :math.cos(mid_angle)
      {x, y}
    end
  end
end
