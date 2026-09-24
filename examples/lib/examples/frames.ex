defmodule Examples.Frames do
  @moduledoc """
  One chart's frames, for a run or a comparison (spec/14 §12.6, #322): what a backend
  renders of a chart module at a tick, and the state a backend keeps between ticks.

  Two backends: `:svg`, the chart rendered whole; `:canvas`, the split — compiled once
  (`prepare/3`), ticked per frame with `render: :binary` (every chart of the gallery is a
  design, #335). A frame is `%{svg, canvas,
  dynamic_svg, bytes, points}`: the SVG to show or nil, the base64 stream to push or nil,
  a tick's SVG-layer marks, the bytes the frame cost, and the rows it drew.
  """

  alias Examples.Charts.Design
  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Fragment}

  @type backend :: :svg | :canvas | :incremental
  @type frame :: %{
          svg: String.t() | nil,
          canvas: String.t() | nil,
          incremental: map() | nil,
          dynamic_svg: String.t(),
          bytes: non_neg_integer(),
          points: non_neg_integer() | nil
        }

  @doc "The backends a chart offers: SVG and Canvas for every chart, Incremental for a streaming design (#327)."
  @spec backends(module()) :: [backend()]
  def backends(module) do
    if stream?(module), do: [:svg, :canvas, :incremental], else: [:svg, :canvas]
  end

  @doc "Whether a chart module streams: a design with a viewport that says `stream?/0`."
  @spec stream?(module()) :: boolean()
  def stream?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :stream?, 0) and module.stream?()
  end

  @doc "Whether frames of a backend are acknowledged by the browser: the canvases' are (spec/10 §8.2, §9.2), an SVG frame's, in the LiveView diff, are not."
  @spec acks?(backend()) :: boolean()
  def acks?(:canvas), do: true
  def acks?(:incremental), do: true
  def acks?(:svg), do: false

  @doc """
  The state a backend keeps for a run of `module` at `opts`: on a canvas, the compiled
  chart and its static SVG (the furniture, rendered once); nothing on SVG.
  """
  @spec prepare(module(), keyword(), backend()) :: map() | nil
  def prepare(module, opts, backend) when backend in [:canvas, :incremental] do
    applied = Design.applied(module, opts)
    {:ok, compiled} = Chart.compile(applied, ceiling: 1)

    %{
      compiled: compiled,
      static: Compiled.static(compiled),
      width: applied.frame.size.width,
      height: applied.frame.size.height,
      plot: compiled.plot,
      margin: compiled.margin
    }
  end

  # A design that eases a scale keeps its compiled chart on SVG too, so the easing has a
  # state to live in (spec/14 §12.5, #360); any other chart renders whole per frame.
  def prepare(module, opts, :svg) do
    if Design.transitions?(module) do
      applied = Design.applied(module, opts)
      {:ok, compiled} = Chart.compile(applied, ceiling: 1_000_000_000)
      %{compiled: compiled}
    end
  end

  @doc "The static SVG a prepared state carries, or an empty string."
  @spec static(map() | nil) :: String.t()
  def static(%{static: static}), do: static
  def static(_state), do: ""

  @doc "A frame of `module` at `opts` on `backend`, and the state after it."
  @spec frame(module(), keyword(), backend(), map() | nil) :: {frame(), map() | nil}
  # A design that eases a scale steps its compiled chart (#360); any other renders whole.
  def frame(module, opts, :svg, %{compiled: compiled} = state) do
    {design, sources} = module.design(opts)
    step_opts = [frame: tick_frame(design)] ++ Keyword.take(opts, [:now, :at])
    {svg, compiled} = Design.step(module, compiled, sources, step_opts)
    {svg_frame(svg, sources), %{state | compiled: compiled}}
  end

  def frame(module, opts, :svg, state) do
    {_design, sources} = module.design(opts)
    {svg_frame(Design.render(module, opts), sources), state}
  end

  # The compiled chart ticked: `now:` from the opts for a streaming design, so the
  # window's upper end is the run's and not the rows' (spec/14 §12.5).
  def frame(module, opts, backend, %{compiled: compiled} = state)
      when backend in [:canvas, :incremental] do
    {design, sources} = module.design(opts)
    compiled = recompiled(compiled, design, module, opts)
    # The tick's own frame, so a design that animates through it moves here too (#424).
    tick_opts = [frame: tick_frame(design)] ++ if(now = opts[:now], do: [now: now], else: [])
    {payload, compiled} = Compiled.tick(compiled, sources, tick_opts)

    {%{
       svg: nil,
       canvas: payload.canvas,
       incremental: payload.incremental,
       dynamic_svg: payload.svg,
       bytes: payload.bytes,
       points: rows(sources)
     }, %{state | compiled: compiled}}
  end

  # A compiled chart is one frame until #385, so the tick's frame is that one frame's
  # node (spec/14 §12.1): the design's single frame, whatever it is named.
  defp tick_frame(design), do: get_in(design, Fragment.frame_path(design))

  # A design whose *marks* move between ticks is a different chart, and the caller
  # compiles it again (spec/14 §12.5, #424): the region builders close over the mark
  # nodes and the render targets are counted from them, so a tick cannot swap them. The
  # force graph animates the link distance of its `:force` step, which is a mark's
  # transform; its frame never moves, so `tick/3`'s `frame:` cannot reach it.
  defp recompiled(compiled, design, module, opts) do
    if design.marks == compiled.chart.marks do
      compiled
    else
      prepare(module, opts, :canvas).compiled
    end
  end

  defp svg_frame(svg, sources) do
    %{
      svg: svg,
      canvas: nil,
      incremental: nil,
      dynamic_svg: "",
      bytes: byte_size(svg),
      points: rows(sources)
    }
  end

  defp rows(sources) when is_map(sources) do
    Enum.reduce(sources, 0, fn
      {_slot, rows}, acc when is_list(rows) -> acc + length(rows)
      _other, acc -> acc
    end)
  end
end
