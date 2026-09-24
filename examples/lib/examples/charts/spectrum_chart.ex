defmodule Examples.Charts.SpectrumChart do
  @moduledoc """
  Time and frequency as one design (#375, #376): the area chart's signal — three sines and
  an offset, `sin(i/4)·30 + sin(2π·31i/100)·8 + sin(2π·27i/100)·5 + 50` — drawn in the
  upper panel as an area under a line, and its spectrum in the lower panel, the three
  tones divided out as three peaks.

  The two panels are the layer's own means (spec/14 §4.3): two pairs of position scales,
  `x`/`y` for the signal with `y` ranging over the upper half of the plot and `fx`/`fy`
  for the spectrum with `fy` over the lower half, the spectrum's marks reading the second
  pair through their `scales` renames, an axis per scale, each spanning its own range. The
  spectrum is the `:spectrum` step over the same source (256 samples, so the lines are
  sharp) with `detrend: true` — the `+50` offset would otherwise be a DC line dwarfing the
  tones and leaking into the bins beside it — followed by a `:filter` that drops the DC
  line itself. Animated, the wave's phase drifts and the peaks stand.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 30, right: 20, bottom: 40, left: 50}
  @samples 256
  @gap 14

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
    {_width, height} = Design.size(__MODULE__, opts)
    plot = height - @margin.top - @margin.bottom
    half = div(plot, 2)

    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:points, [:t, :y], types: %{t: :number, y: :number}),
        source(:peaks, [:f, :m, :name], types: %{f: :number, m: :number, name: :text}),
        style(:area, fill: :series_1, opacity: 0.25, curve: :monotone_x),
        style(:edge, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
        style(:spectrum, fill: :series_2, opacity: 0.35, curve: :monotone_x),
        style(:peak, stroke: :series_2, stroke_width: 2, curve: :monotone_x),
        style(:name, fill: :text, font_size: 11, text_anchor: :middle),
        cartesian(margin: @margin),
        # The signal's scales, the upper half of the plot.
        linear_scale(:x),
        linear_scale(:y, domain: [0, 100], range: [half - @gap, 0]),
        # The spectrum's scales, the lower half: frequency in cycles per sample to Nyquist.
        linear_scale(:fx, domain: [0, 0.5]),
        linear_scale(:fy, domain: [0, 36], range: [plot, half + @gap]),
        axis(:x, :top, ticks: 8),
        axis(:y, :left, ticks: 4),
        axis(:fx, :bottom, ticks: 10, unit: " c/s"),
        axis(:fy, :left, ticks: 3),
        area(:points, %{x: :t, y: :y}, style: :area),
        line(:points, %{x: :t, y: :y}, style: :edge),
        area(spectrum_of(:points), %{x: :frequency, y: :magnitude},
          style: :spectrum,
          scales: %{x: :fx, y: :fy}
        ),
        line(spectrum_of(:points), %{x: :frequency, y: :magnitude},
          style: :peak,
          scales: %{x: :fx, y: :fy}
        ),
        text(:peaks, %{x: :f, y: :m, value: :name}, style: :name, scales: %{x: :fx, y: :fy})
      ])

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

    # Two panels in one frame: the signal's y ranges over the upper half of the plot, the
    # spectrum's fy over the lower half, and the spectrum's marks read fx/fy through
    # their `scales` renames.
    spectrum = from(:points) |> spectrum(:y, time: :t, samples: 256, detrend: true) |> filter(:frequency, test: :gt, value: 0)

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Spectrum"}),
        source(:points, [:t, :y], types: %{t: :number, y: :number}),
        style(:area, fill: :series_1, opacity: 0.25, curve: :monotone_x),
        style(:spectrum, fill: :series_2, opacity: 0.35, curve: :monotone_x),
        cartesian(margin: %{top: 30, right: 20, bottom: 40, left: 50}),
        linear_scale(:x),
        linear_scale(:y, domain: [0, 100], range: [151, 0]),
        linear_scale(:fx, domain: [0, 0.5]),
        linear_scale(:fy, domain: [0, 36], range: [330, 179]),
        axis(:x, :top, ticks: 8),
        axis(:y, :left, ticks: 4),
        axis(:fx, :bottom, ticks: 10, unit: " c/s"),
        axis(:fy, :left, ticks: 3),
        area(:points, %{x: :t, y: :y}, style: :area),
        area(spectrum, %{x: :frequency, y: :magnitude}, style: :spectrum, scales: %{x: :fx, y: :fy})
      ])

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
