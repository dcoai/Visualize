defmodule Examples.Charts.RadialBarChart do
  @moduledoc """
  Radial bar chart as a design (#126, #137): a `:rose` mark over a polar frame's `angle`
  and `r` scales, the bars colored by value through a `:sequential` `color` scale, and
  the weekday names outside the ring on each sector's own spoke — the `:outward` anchor
  with a radial offset and `rotate: :radial` (spec/14 §5.5), which is what kept this chart
  imperative until #137. The center shows the average as two frame labels at
  `{:frame, :center}`, the polar origin whatever the `r` range — `{:data, [0, 0]}` would map
  radius zero through `r`, whose range starts at the hole's 50 (#489). The ring is sized
  from the plot and its longest day name, so no name leaves the plot (§5.5).
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @zero_margin %{top: 0, right: 0, bottom: 0, left: 0}
  @day_size 11
  @day_dr 11

  @data [
    %{name: "Monday", value: 85},
    %{name: "Tuesday", value: 72},
    %{name: "Wednesday", value: 90},
    %{name: "Thursday", value: 65},
    %{name: "Friday", value: 78},
    %{name: "Saturday", value: 45},
    %{name: "Sunday", value: 35}
  ]

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {400, 400}

  def title, do: "Radial Bar Chart"
  def description, do: "Weekly activity levels"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    {width, height} = Design.size(__MODULE__, opts)
    rows = rows(opts)
    # The plot is the whole box (no margin); the ring leaves room for the day names.
    outer = Design.ring_radius({width, height}, Enum.map(rows, & &1.name), @day_size, @day_dr)
    avg = Float.round(Enum.sum(Enum.map(rows, & &1.value)) / length(rows), 1)

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:days, [:name, :value, :index]),
        style(:bar, fill: {:field, :value}, stroke: :background, stroke_width: 1),
        style(:day, extends: :label, font_size: @day_size),
        style(:average, extends: :title, font_size: 24, text_anchor: :middle),
        style(:average_word, extends: :label, font_size: 12, fill: :axis, text_anchor: :middle),
        polar(margin: @zero_margin),
        radial_scale(:angle, domain: [0, length(rows)]),
        linear_scale(:r, domain: [0, 100], range: [50, outer]),
        sequential_scale(:color, domain: [0, :auto]),
        rose(:days, %{angle: :index, value: :value},
          options: %{width: 1, inner_radius: 50, pad_angle: 0.1},
          label: %{
            text: [{:field, :name}],
            anchor: :outward,
            dr: @day_dr,
            rotate: :radial,
            style: :day
          },
          style: :bar
        ),
        label({:frame, :center}, [to_string(avg)], style: :average, dy: -5),
        label({:frame, :center}, ["average"], style: :average_word, dy: 15)
      ])

    {design, %{days: rows}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    base = opts[:data] || @data

    data =
      case opts[:animation_tick] do
        nil -> base
        tick -> animate(base, tick)
      end

    for {d, i} <- Enum.with_index(data), do: Map.put(d, :index, i)
  end

  # Animation: each bar breathes between half and one and a half of its value.
  defp animate(data, tick) do
    for {item, i} <- Enum.with_index(data) do
      multiplier = 1.0 + 0.5 * :math.sin(tick * 0.15 + i * 0.9)
      %{item | value: max(10, min(100, item.value * multiplier))}
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Radial Bar Chart"}),
        source(:days, [:name, :value, :index]),
        style(:bar, fill: {:field, :value}, stroke: :background),
        style(:day, extends: :label, font_size: 11),
        polar(margin: %{top: 0, right: 0, bottom: 0, left: 0}),
        radial_scale(:angle, domain: [0, 7]),
        # The ring leaves room for the longest name outside it (spec/14 §5.5).
        linear_scale(:r, domain: [0, 100], range: [50, 121.6]),
        sequential_scale(:color, domain: [0, :auto]),
        # The names outside the ring, on each sector's own spoke, reading along it:
        # the :outward anchor with a radial offset and rotate: :radial (spec/14 §5.5).
        rose(:days, %{angle: :index, value: :value},
          options: %{width: 1, inner_radius: 50, pad_angle: 0.1},
          label: %{text: [{:field, :name}], anchor: :outward, dr: 11, rotate: :radial, style: :day},
          style: :bar
        ),
        # The plot's center — the polar origin, whatever the r range (spec/14 §6.3).
        label({:frame, :center}, ["67.1"], style: :title, dy: -5)
      ])

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{days: days})
    Visualize.Chart.render(applied)
    """
  end
end
