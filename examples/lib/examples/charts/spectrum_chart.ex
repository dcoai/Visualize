defmodule Examples.Charts.SpectrumChart do
  @moduledoc """
  Time and frequency as one design (#375, #376): the area chart's signal — three sines and
  an offset, `sin(i/4)·30 + sin(2π·31i/100)·8 + sin(2π·27i/100)·5 + 50` — drawn in the
  upper panel as an area under a line, and its spectrum in the lower panel, the three
  tones divided out as three peaks.

  **The two panels are two frames** (#383, #429): `signal` over the upper half of the box
  and `spectrum` over the lower, each with its own `x` and `y` — two scales called `x`,
  one per frame, which is what a scale name belonging to its frame is for (spec/14 §4.3).
  It was one frame holding two panels until frames were a map: a second pair of scales,
  `fx`/`fy`, whose explicit ranges were half the plot each, with the spectrum's marks
  reading them through their `scales` renames (#376). Nothing in it carries a range now;
  the boxes say where each panel is and the scales say what they mean. The
  spectrum is the `:spectrum` step over the same source (256 samples, so the lines are
  sharp) with `detrend: true` — the `+50` offset would otherwise be a DC line dwarfing the
  tones and leaking into the bins beside it — followed by a `:filter` that drops the DC
  line itself. Animated, the wave's phase drifts and the peaks stand.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  # Each frame takes half the box; the gap between the two plots is the signal's bottom
  # margin and the spectrum's top.
  @signal_margin %{top: 30, right: 20, bottom: 7, left: 50}
  @spectrum_margin %{top: 7, right: 20, bottom: 40, left: 50}
  @samples 256

  # The three tones in cycles per sample, and the amplitude each reads at its peak.
  @peaks [
    %{f: 1 / (8 * :math.pi()), m: 30, name: "1/8π · 30"},
    %{f: 0.27, m: 5, name: "0.27 · 5"},
    %{f: 0.31, m: 8, name: "0.31 · 8"}
  ]

  def title, do: "Spectrum"
  def description, do: "The area chart's summed sines above their spectrum"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold(
        [
          chart(meta: %{name: title(), description: [description()]}),
          source(:points, [:t, :y], types: %{t: :number, y: :number}),
          source(:peaks, [:f, :m, :name], types: %{f: :number, m: :number, name: :text}),
          style(:area, fill: :series_1, opacity: 0.25, curve: :monotone_x),
          style(:edge, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
          style(:spectrum, fill: :series_2, opacity: 0.35, curve: :monotone_x),
          style(:peak, stroke: :series_2, stroke_width: 2, curve: :monotone_x),
          style(:name, fill: :text, font_size: 11, text_anchor: :middle)
        ] ++
          in_frame(:signal, [
            cartesian(box: [0, 0, 1, 0.5], margin: @signal_margin),
            linear_scale(:x),
            linear_scale(:y, domain: [0, 100]),
            axis(:x, :top, ticks: 8),
            axis(:y, :left, ticks: 4),
            area(:points, %{x: :t, y: :y}, style: :area),
            line(:points, %{x: :t, y: :y}, style: :edge)
          ]) ++
          in_frame(:spectrum, [
            # Frequency in cycles per sample, to Nyquist.
            cartesian(box: [0, 0.5, 1, 0.5], margin: @spectrum_margin),
            linear_scale(:x, domain: [0, 0.5]),
            linear_scale(:y, domain: [0, 36]),
            axis(:x, :bottom, ticks: 10, unit: " c/s"),
            axis(:y, :left, ticks: 3),
            area(spectrum_of(:points), %{x: :frequency, y: :magnitude}, style: :spectrum),
            line(spectrum_of(:points), %{x: :frequency, y: :magnitude}, style: :peak),
            text(:peaks, %{x: :f, y: :m, value: :name}, style: :name)
          ])
      )

    {design, %{points: rows(opts), peaks: @peaks}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  # The spectrum of the signal with its mean taken out: the `+50` offset would otherwise be
  # a DC line dwarfing the tones and leaking into the bins beside it.
  defp spectrum_of(source) do
    source
    |> from()
    |> spectrum(:y, time: :t, samples: @samples, detrend: true)
    |> filter(:frequency, test: :gt, value: 0)
  end

  defp rows(opts) do
    case opts[:animation_tick] do
      nil -> opts[:data] || samples(0)
      tick -> samples(tick)
    end
  end

  # The area chart's signal over 256 samples; its phase drifts with the tick as the area
  # chart's does, so the wave moves and the peaks stand.
  defp samples(tick) do
    phase = tick * 0.15

    for i <- 0..(@samples - 1) do
      y =
        :math.sin(i / 4 + phase) * 30 +
          :math.sin(i * 31 * :math.pi() * 2 / 100 + phase * 2.1) * 8 +
          :math.sin(i * 27 * :math.pi() * 2 / 100 + phase * 1.7) * 5 +
          50

      %{t: i, y: y}
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # Two panels are two frames: the signal over the upper half of the box, the spectrum
    # over the lower. Each declares its own x and y, so nothing needs a range or a rename.
    spectrum = from(:points) |> spectrum(:y, time: :t, samples: 256, detrend: true) |> filter(:frequency, test: :gt, value: 0)

    {:ok, design} =
      Visualize.Chart.compose(
        [
          chart(meta: %{name: "Spectrum"}),
          source(:points, [:t, :y], types: %{t: :number, y: :number}),
          style(:area, fill: :series_1, opacity: 0.25, curve: :monotone_x),
          style(:spectrum, fill: :series_2, opacity: 0.35, curve: :monotone_x)
        ] ++
          in_frame(:signal, [
            cartesian(box: [0, 0, 1, 0.5], margin: %{top: 30, right: 20, bottom: 7, left: 50}),
            linear_scale(:x),
            linear_scale(:y, domain: [0, 100]),
            axis(:x, :top, ticks: 8),
            axis(:y, :left, ticks: 4),
            area(:points, %{x: :t, y: :y}, style: :area)
          ]) ++
          in_frame(:spectrum, [
            cartesian(box: [0, 0.5, 1, 0.5], margin: %{top: 7, right: 20, bottom: 40, left: 50}),
            linear_scale(:x, domain: [0, 0.5]),
            linear_scale(:y, domain: [0, 36]),
            axis(:x, :bottom, ticks: 10, unit: " c/s"),
            axis(:y, :left, ticks: 3),
            area(spectrum, %{x: :frequency, y: :magnitude}, style: :spectrum)
          ])
      )

    # The area chart's signal: three sines and an offset.
    points =
      for i <- 0..255 do
        %{t: i, y: :math.sin(i / 4) * 30 + :math.sin(i * 31 * :math.pi() * 2 / 100) * 8 + :math.sin(i * 27 * :math.pi() * 2 / 100) * 5 + 50}
      end

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{points: points})
    Visualize.Chart.render(applied)
    """
  end
end
