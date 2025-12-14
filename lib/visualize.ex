defmodule Visualize do
  @moduledoc """
  Server-side SVG visualization library for Elixir.

  Inspired by D3.js, designed for Phoenix LiveView.

  ## Quick Start

      # Create a simple line chart
      data = [
        %{date: ~D[2024-01-01], value: 10},
        %{date: ~D[2024-01-02], value: 25},
        %{date: ~D[2024-01-03], value: 15}
      ]

      # Create scales
      x_scale = Visualize.Scale.time()
        |> Visualize.Scale.domain(Visualize.Data.extent(data, & &1.date))
        |> Visualize.Scale.range([0, 500])

      y_scale = Visualize.Scale.linear()
        |> Visualize.Scale.domain([0, Visualize.Data.max(data, & &1.value)])
        |> Visualize.Scale.range([300, 0])
        |> Visualize.Scale.nice()

      # Create line generator
      line = Visualize.Shape.line()
        |> Visualize.Shape.x(fn d -> Visualize.Scale.apply(x_scale, d.date) end)
        |> Visualize.Shape.y(fn d -> Visualize.Scale.apply(y_scale, d.value) end)
        |> Visualize.Shape.curve(:monotone_x)

      # Generate path
      path_data = Visualize.Shape.generate(line, data)

  ## Modules

  - `Visualize.SVG` - SVG element creation and rendering
  - `Visualize.Scale` - Data to visual mapping (linear, time, band, etc.)
  - `Visualize.Shape` - Path generators (line, area, arc, pie, symbol)
  - `Visualize.Axis` - Axis generators with ticks and labels
  - `Visualize.Data` - Data utilities (extent, mean, group, bin)
  - `Visualize.Format` - Number and date formatting
  - `Visualize.Layout.Force` - Force-directed graph layout

  ## LiveView Integration

  All SVG elements implement `Phoenix.HTML.Safe`, so they can be used
  directly in HEEx templates:

      def render(assigns) do
        ~H\"\"\"
        <svg width="600" height="400">
          <%= @chart_element %>
        </svg>
        \"\"\"
      end

  """

  # Re-export commonly used modules
  defdelegate linear(), to: Visualize.Scale
  defdelegate time(), to: Visualize.Scale
  defdelegate band(), to: Visualize.Scale
  defdelegate ordinal(), to: Visualize.Scale

  defdelegate line(), to: Visualize.Shape
  defdelegate area(), to: Visualize.Shape
  defdelegate arc(), to: Visualize.Shape
  defdelegate pie(), to: Visualize.Shape
  defdelegate symbol(), to: Visualize.Shape

  # Convenience functions

  @doc """
  Creates a new SVG element.

  ## Examples

      Visualize.svg(width: 600, height: 400)

  """
  defdelegate svg(attrs \\ []), to: Visualize.SVG, as: :new

  @doc """
  Renders an SVG element to a string.
  """
  defdelegate render(element), to: Visualize.SVG

  @doc """
  Returns the version of the library.
  """
  def version, do: "0.1.0"
end
