defmodule Examples.Charts.SpectrumChart do
  @moduledoc """
  Spectrum as a design (#375): a time series through the `:spectrum` transform (spec/14
  §5.4.1) to its one-sided amplitude spectrum — an `:area` under a `:line` over a linear
  frequency axis in hertz.

  The rows are 256 samples at 100 Hz of two tones — 5 Hz at amplitude 3 and a second one
  near 12 Hz at 1.5 — under a little noise; animated, the second tone drifts, so the
  spectrum's peak moves while the first stands. The transform reads the sample interval
  from the `t` column and takes the newest 256 samples, so the chart is 128 lines from 0 to
  the Nyquist frequency, 50 Hz.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @margin %{top: 20, right: 20, bottom: 40, left: 50}
  @rate 100
  @samples 256

  def title, do: "Spectrum"
  def description, do: "A time series to its frequency spectrum by FFT"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold([
        chart(meta: %{name: title(), description: [description()]}),
        source(:samples, [:t, :v], types: %{t: :number, v: :number}),
        style(:area, fill: :series_1, opacity: 0.25, curve: :monotone_x),
        style(:edge, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
        cartesian(opts[:width] || 600, opts[:height] || 400, margin: @margin),
        linear_scale(:x, domain: [0, @rate / 2]),
        linear_scale(:y, domain: [0, :auto], nice: true, transition: %{duration: 300}),
        axis(:x, :bottom, ticks: 10, unit: " Hz"),
        axis(:y, :left, ticks: 5),
        area(
          spectrum(from(:samples), :v, time: :t, samples: @samples),
          %{x: :frequency, y: :magnitude},
          style: :area
        ),
        line(
          spectrum(from(:samples), :v, time: :t, samples: @samples),
          %{x: :frequency, y: :magnitude},
          style: :edge
        )
      ])

    {design, %{samples: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp rows(opts) do
    case opts[:animation_tick] do
      nil -> opts[:data] || samples(0)
      tick -> samples(tick)
    end
  end

  # Two tones under a little deterministic noise; the second drifts with the tick.
  defp samples(tick) do
    drift = 12 + 6 * :math.sin(tick * 0.05)

    for i <- 0..(@samples - 1) do
      t = i / @rate

      v =
        3 * :math.sin(2 * :math.pi() * 5 * t) +
          1.5 * :math.sin(2 * :math.pi() * drift * t + tick * 0.1) +
          0.3 * :math.sin(i * 7.3 + tick)

      %{t: t, v: v}
    end
  end

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    {:ok, design} =
      Visualize.Chart.compose([
        chart(meta: %{name: "Spectrum"}),
        source(:samples, [:t, :v], types: %{t: :number, v: :number}),
        style(:area, fill: :series_1, opacity: 0.25, curve: :monotone_x),
        style(:edge, stroke: :series_1, stroke_width: 2, curve: :monotone_x),
        cartesian(600, 400, margin: %{top: 20, right: 20, bottom: 40, left: 50}),
        linear_scale(:x, domain: [0, 50]),
        linear_scale(:y, domain: [0, :auto], nice: true),
        axis(:x, :bottom, ticks: 10, unit: " Hz"),
        axis(:y, :left, ticks: 5),
        # The transform reads the sample interval from t and takes the newest 256 samples.
        area(spectrum(from(:samples), :v, time: :t, samples: 256), %{x: :frequency, y: :magnitude}, style: :area),
        line(spectrum(from(:samples), :v, time: :t, samples: 256), %{x: :frequency, y: :magnitude}, style: :edge)
      ])

    samples = for i <- 0..255, do: %{t: i / 100, v: 3 * :math.sin(2 * :math.pi() * 5 * i / 100)}
    {:ok, applied} = Visualize.Chart.apply(design, sources: %{samples: samples})
    Visualize.Chart.render(applied)
    """
  end
end
