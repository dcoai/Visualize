defmodule Examples.Charts.Downsampling do
  @moduledoc """
  **Shape-preserving downsampling** (#448): one 50,000-row series drawn three times, in
  three frames stacked down the box — whole, through an `:m4` step, and through an `:lttb`
  step — each frame saying how many rows it draws.

  SVG draws a line of a thousand points well and fifty thousand badly (spec/01 §2), and
  a raw series at its native resolution — a per-second watch stream, a sensor every few
  seconds — is routinely the latter. Neither of the existing selections keeps it looking
  like itself: a uniform `:take` drops the spikes and a `:bin` averages them flat. The two
  steps of spec/14 §5.4.1 do:

  - `m4(from(:series), [:t, :v], :plot)` keeps, per **pixel column**, the first, last,
    lowest and highest rows — so the reduced line draws the same pixels as the whole one
    (the `x` scale is inferred and not `nice`, so its columns are the plot's), and the
    rare spikes in this series all survive. At most four rows a column.
  - `lttb(from(:series), [:t, :v], :plot)` keeps one row per pixel column by
    Largest-Triangle-Three-Buckets: fewer rows than M4, the shape kept by visual area.

  `:plot` is the step's **binding to the frame's geometry**: the plot's width in pixels,
  read when the pipeline runs, so neither step names a number and both follow the page
  when it is resized.

  **The counts are the design's own.** Each frame's caption is a `:text` mark over the
  frame's rows counted by a one-bin `:bin` step (`thresholds: []`, a bin over the whole
  `t` extent, `as: :rows`), so the number is what that frame draws at the size it is
  drawn, not a figure written beside it.

  The series is a slow wave with noise, rare spikes and one **dropout** — a run of rows
  with no reading — which both steps pass through as a gap: each reduced line breaks
  exactly where the whole one does. Each row is a pure function of its index, so the
  chart is the same on every render and an animation tick scrolls the same series.
  """

  import Visualize.Chart.Build

  alias Examples.Charts.Design

  @points 50_000
  # The dropout: a stretch of rows whose reading is missing.
  @dropout 31_000..31_799
  # The y extent: room above the tallest spike for the caption.
  @ceiling 140
  @caption 128
  @margin %{top: 22, right: 20, bottom: 26, left: 46}

  # The three frames, top to bottom: the name, the data a line reads, and the caption's
  # words after the count.
  @frames [
    {:whole, :whole, " rows, whole"},
    {:m4, :m4, " rows after m4 — first, last, min and max per pixel column"},
    {:lttb, :lttb, " rows after lttb — one per pixel column"}
  ]

  @doc "The size this chart is drawn at when the caller names none (spec/14 §4.2)."
  def size, do: {760, 520}

  def title, do: "Downsampling"
  def description, do: "50,000 rows whole, then reduced per pixel by :m4 and :lttb"

  @doc "The design and the rows it binds (spec/14 §16.1)."
  def design(opts \\ []) do
    design =
      Design.fold(
        [
          chart(meta: %{name: title(), description: [description()]}),
          layout(rows: [1, 1, 1], gap: 6),
          source(:series, [:t, :v], types: %{t: :number, v: :number}),
          style(:trace, stroke: :series_1, stroke_width: 1),
          style(:caption, extends: :label, font_size: 11)
        ] ++ Enum.flat_map(Enum.with_index(@frames), &frame/1)
      )

    {design, %{series: rows(opts)}}
  end

  def render(opts \\ []), do: Design.render(__MODULE__, opts)

  defp frame({{name, reduction, words}, index}) do
    data = data(reduction)

    in_frame(name, [
      cartesian(cell: [0, index], margin: @margin),
      linear_scale(:x),
      linear_scale(:y, domain: [-@ceiling, @ceiling]),
      axis(:x, :bottom, ticks: 6),
      axis(:y, :left, ticks: 4, grid: true),
      line(data, %{x: :t, y: :v}, style: :trace),
      # The caption in the band above the tallest spike, in data units: the count of the rows
      # this frame's line draws, from the same pipeline.
      text(bin(data, :t, thresholds: [], as: :rows), %{x: 0, y: @caption},
        label: %{text: [{:field, :rows}, words], anchor: :right, style: :caption}
      )
    ])
  end

  defp data(:whole), do: from(:series)
  defp data(:m4), do: m4(from(:series), [:t, :v], :plot)
  defp data(:lttb), do: lttb(from(:series), [:t, :v], :plot)

  # A slow wave, noise, a spike about once in two thousand rows and the dropout. Each
  # row's noise is a hash of its index, so the series is the same on every render and an
  # animation tick scrolls it — the window moves 250 rows along the same series — without
  # regenerating what came before.
  defp rows(opts) do
    count = opts[:points] || @points
    offset = (opts[:animation_tick] || 0) * 250

    for i <- offset..(offset + count - 1) do
      spike = if unit(i, :chance) < 0.0005, do: (unit(i, :height) - 0.5) * 120, else: 0

      v =
        :math.sin(i / 3_000) * 40 + :math.sin(i / 170) * 6 + (unit(i, :noise) - 0.5) * 14 + spike

      %{t: i, v: if(i in @dropout, do: nil, else: Float.round(v, 3))}
    end
  end

  # A number in [0, 1) fixed by the row's index and what it is for.
  defp unit(i, purpose), do: :erlang.phash2({i, purpose}, 1_000_000) / 1_000_000

  def sample_code do
    ~S"""
    import Visualize.Chart.Build

    # One series in three frames: whole, and reduced to the plot's width by each step.
    # `:plot` is the plot's width in pixels, so neither step names a number.
    frames = [
      {:whole, from(:series)},
      {:m4, m4(from(:series), [:t, :v], :plot)},
      {:lttb, lttb(from(:series), [:t, :v], :plot)}
    ]

    {:ok, design} =
      Visualize.Chart.compose(
        [
          chart(meta: %{name: "Downsampling"}),
          layout(rows: [1, 1, 1], gap: 6),
          source(:series, [:t, :v], types: %{t: :number, v: :number})
        ] ++
          Enum.flat_map(Enum.with_index(frames), fn {{name, data}, i} ->
            in_frame(name, [
              cartesian(cell: [0, i], margin: %{top: 22, right: 20, bottom: 26, left: 46}),
              linear_scale(:x),
              linear_scale(:y, domain: [-140, 140]),
              axis(:x, :bottom, ticks: 6),
              axis(:y, :left, ticks: 4, grid: true),
              line(data, %{x: :t, y: :v}),
              # The rows this frame draws, counted by a one-bin :bin of the same pipeline.
              text(bin(data, :t, thresholds: [], as: :rows), %{x: 0, y: 128},
                label: %{text: [{:field, :rows}, " rows"], anchor: :right}
              )
            ])
          end)
      )

    series = for t <- 0..49_999, do: %{t: t, v: :math.sin(t / 3_000) * 40}

    {:ok, applied} = Visualize.Chart.apply(design, sources: %{series: series})
    Visualize.Chart.render(applied)
    """
  end
end
