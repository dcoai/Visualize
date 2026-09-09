defmodule Examples.Charts.PieChart do
  @moduledoc """
  Pie chart as a design (#126): one `:arc` mark over a polar frame.

  `Visualize.Shape.Pie` is not called: an `:arc` whose `value` channel is a share runs the
  pie itself over the mark's rows, in row order, with the radii and the pad angle as options
  (spec/14 §5.6). The slices read largest first because the rows do, and each takes its
  colour from an ordinal `color` scale through a `{:field, :index}` on the style's `fill`.

  The white slice separator is the theme's `background` rather than the literal `"white"`,
  so it follows a palette instead of fighting it. The slice's label sits at the arc's
  centroid, which is halfway out rather than the 0.6 of the radius the hand-built version
  used; a mark label has no radial offset (#137).
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @zero_margin %{top: 0, right: 0, bottom: 0, left: 0}

  @data [
    %{name: "Chrome", value: 64.5},
    %{name: "Safari", value: 18.8},
    %{name: "Firefox", value: 3.1},
    %{name: "Edge", value: 4.9},
    %{name: "Opera", value: 2.3},
    %{name: "Other", value: 6.4}
  ]

  def title, do: "Pie Chart"
  def description, do: "Browser market share"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    width = opts[:width] || 400
    height = opts[:height] || 400

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:slices, [:name, :value, :index]),
        style(:slice, fill: {:field, :index}, stroke: :background, stroke_width: 2),
        style(:slice_label,
          extends: :label,
          fill: :background,
          font_size: 12,
          font_weight: :bold
        ),
        polar(width, height, margin: @zero_margin),
        ordinal_scale(:color),
        arc(:slices, %{value: :value},
          options: %{inner_radius: 0, outer_radius: min(width, height) / 2 - 40},
          label: %{text: [{:field, :name}], anchor: :middle, style: :slice_label},
          style: :slice
        )
      ])

    {design, %{slices: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # The pie draws its rows in order and the colour follows the row's index, so the sort is
  # the assign mapping's: largest slice first, coloured first.
  defp rows(opts) do
    data = opts[:data] || @data

    data =
      case opts[:animation_tick] do
        nil -> data
        tick -> animated(data, tick)
      end

    data
    |> Enum.sort_by(& &1.value, :desc)
    |> Enum.with_index(fn row, i -> Map.put(row, :index, i) end)
  end

  # Animation: vary slice sizes with different phases.
  defp animated(data, tick) do
    Enum.with_index(data, fn item, i ->
      %{item | value: item.value * (1.0 + 0.4 * :math.sin(tick * 0.12 + i * 0.8))}
    end)
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # Rows largest first, each carrying its index: the pie draws them in order.
    rows = [%{name: "Chrome", value: 64.5, index: 0}, %{name: "Safari", value: 18.8, index: 1}]

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Pie Chart"}),
        source(:slices, [:name, :value, :index]),
        style(:slice, fill: {:field, :index}, stroke: :background, stroke_width: 2),
        style(:slice_label, extends: :label, fill: :background, font_size: 12, font_weight: :bold),
        polar(400, 400, margin: %{top: 0, right: 0, bottom: 0, left: 0}),
        ordinal_scale(:color),

        # An :arc whose `value` is a share runs Visualize.Shape.Pie itself.
        arc(:slices, %{value: :value},
          options: %{inner_radius: 0, outer_radius: 160},
          label: %{text: [{:field, :name}], anchor: :middle, style: :slice_label},
          style: :slice
        )
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{slices: rows})
    Visualize.Chart.render(applied)
    """
  end
end
