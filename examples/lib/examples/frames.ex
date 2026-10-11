defmodule Examples.Frames do
  @moduledoc """
  One chart's frames, for a run or a comparison (spec/14 §12.6, #322): what a backend
  renders of a chart module at a tick, and the state a backend keeps between ticks.

  Two backends: `:svg`, the chart rendered whole; `:canvas`, the split — compiled once
  (`prepare/3`), ticked per frame with `render: :binary` (every chart of the gallery is a
  design, #335).

  A design has **one plot per frame** (spec/14 §12.1, #385, #432), so a frame of a run is
  `%{svg, plots, bytes, points}`: the SVG to show or nil, one entry per plot — its name,
  its base64 stream or its incremental record, its SVG-layer marks, its backdrop (a fitted
  basemap's tiles, beneath the canvas, #476) and the geometry the page places its canvas
  by — and the bytes and rows of the whole frame. A design of one
  frame has one plot, so the page has one shape to draw whatever the design holds.
  """

  alias Examples.Charts.Design
  alias Visualize.Chart
  alias Visualize.Chart.Compiled

  @type backend :: :svg | :canvas | :incremental

  @typedoc "One plot of a frame: what to push for it, and where its canvas goes."
  @type plot :: %{
          name: atom(),
          canvas: String.t() | nil,
          incremental: map() | nil,
          dynamic_svg: String.t(),
          backdrop: String.t(),
          box: %{x: number(), y: number(), width: number(), height: number()},
          plot: %{width: number(), height: number()},
          margin: %{top: number(), right: number(), bottom: number(), left: number()}
        }

  @type frame :: %{
          svg: String.t() | nil,
          plots: [plot()],
          bytes: non_neg_integer(),
          points: non_neg_integer() | nil
        }

  @doc """
  The backends a chart offers: SVG and Canvas for every chart, Incremental for a streaming
  design (#327) — whatever the number of frames, since a design draws one plot per frame
  (spec/14 §12.1, #432).
  """
  @spec backends(module()) :: [backend()]
  def backends(module) do
    if stream?(module), do: [:svg, :canvas, :incremental], else: [:svg, :canvas]
  end

  @doc "How many frames a chart's design holds (spec/14 §2.1, #383)."
  @spec frames(module()) :: non_neg_integer()
  def frames(module) do
    {design, _sources} = module.design([])
    design |> Map.get(:frames, %{}) |> map_size()
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
  chart, its static SVG (the furniture, rendered once) and its static backdrop (a
  basemap's tiles, rendered once, for beneath the canvas: spec/14 §12.4, #476); nothing on
  SVG.
  """
  @spec prepare(module(), keyword(), backend()) :: map() | nil
  def prepare(module, opts, backend) when backend in [:canvas, :incremental] do
    applied = Design.applied(module, opts)
    compiled = compiled!(applied, ceiling: 1)

    %{
      compiled: compiled,
      # What the chart says to a screen reader (spec/14 §21.4): the page names the layers'
      # wrapper with it, since no one layer is the picture.
      summary: Visualize.Chart.Summary.new(applied),
      # Each plot's static document is the design's size with that frame's group at its
      # box (spec/14 §12.4), so the frames' documents stack in `z` order.
      static: Enum.map_join(compiled, "", fn {_name, one} -> Compiled.static(one) end),
      backdrop: Enum.map_join(compiled, "", fn {_name, one} -> Compiled.backdrop(one) end),
      width: applied.frame.size.width,
      height: applied.frame.size.height,
      plot: applied.frame.plot,
      margin: applied.frame.margin
    }
  end

  # A design that carries state between ticks — it eases (spec/14 §12.5, #360), or a
  # `:force` step's layout is warm (#527, D-132) — keeps its compiled chart on SVG too, so
  # the state has somewhere to live; any other chart renders whole per frame.
  def prepare(module, opts, :svg) do
    if Design.stateful?(module) do
      applied = Design.applied(module, opts)

      %{
        compiled: compiled!(applied, ceiling: 1_000_000_000),
        summary: Visualize.Chart.Summary.text(applied)
      }
    end
  end

  # One compiled chart per frame (spec/14 §12.1, #385), in the order the frames draw —
  # `z`, ties by name (§4.2) — so the plots' canvases and static documents stack as the
  # design says.
  defp compiled!(applied, opts) do
    {:ok, frames} = Chart.compile(applied, opts)

    for {name, _compiled} <- order(applied), into: [], do: {name, Map.fetch!(frames, name)}
  end

  defp order(applied) do
    applied.frames
    |> Enum.sort_by(fn {name, frame} -> {frame.z, to_string(name)} end)
    |> Enum.map(fn {name, frame} -> {name, frame} end)
  end

  @doc """
  A freshly prepared state carrying the easing of the one it replaces (spec/14 §12.5,
  #434): a resize is a recompilation, and a scale mid-transition goes on from where it
  stood rather than jumping back to its target. Frame by frame, by name; a frame the
  fresh state does not have is dropped, and a state with no compiled chart — the SVG
  backend's, for a design that eases nothing — is the fresh one.
  """
  @spec carry(map() | nil, map() | nil) :: map() | nil
  def carry(%{compiled: was}, %{compiled: fresh} = state) when is_list(was) and is_list(fresh) do
    previous = Map.new(was)

    carried =
      for {name, one} <- fresh do
        case previous do
          %{^name => before} -> {name, Compiled.carry(before, one)}
          _absent -> {name, one}
        end
      end

    %{state | compiled: carried}
  end

  def carry(_was, state), do: state

  @doc "The static SVG a prepared state carries, or an empty string."
  @spec static(map() | nil) :: String.t()
  def static(%{static: static}), do: static
  def static(_state), do: ""

  @doc """
  The summary a prepared hybrid state carries (spec/14 §21.4), or `nil`: what names the
  wrapper of the chart's layers.
  """
  @spec summary(map() | nil) :: Visualize.Chart.Summary.t() | nil
  def summary(%{summary: %Visualize.Chart.Summary{} = summary}), do: summary
  def summary(_state), do: nil

  @doc "The static backdrop a prepared state carries, or an empty string (spec/14 §12.4, #476)."
  @spec backdrop(map() | nil) :: String.t()
  def backdrop(%{backdrop: backdrop}), do: backdrop
  def backdrop(_state), do: ""

  @doc "A frame of `module` at `opts` on `backend`, and the state after it."
  @spec frame(module(), keyword(), backend(), map() | nil) :: {frame(), map() | nil}
  # A design that carries state steps its compiled chart (#360, #527); any other renders
  # whole.
  def frame(module, opts, :svg, %{compiled: compiled} = state) do
    {design, sources} = module.design(opts)
    compiled = recompiled(compiled, design, module, opts, :svg)

    {svg, compiled} =
      Design.step(module, compiled, design, sources, [summary: state.summary] ++ opts)

    {svg_frame(svg, sources), %{state | compiled: compiled}}
  end

  def frame(module, opts, :svg, state) do
    {_design, sources} = module.design(opts)
    {svg_frame(Design.render(module, opts), sources), state}
  end

  # The compiled chart ticked: `now:` from the opts for a streaming design, so the
  # window's upper end is the run's and not the rows' (spec/14 §12.5), and `at:`, the
  # clock a transition eases by, as `Design.step/5` passes it on SVG (#498).
  def frame(module, opts, backend, %{compiled: compiled} = state)
      when backend in [:canvas, :incremental] do
    {design, sources} = module.design(opts)
    compiled = recompiled(compiled, design, module, opts, backend)
    clock = for key <- [:now, :at], value = opts[key], do: {key, value}

    {plots, compiled} =
      Enum.map_reduce(compiled, [], fn {name, one}, acc ->
        # The tick's own frame, so a design that animates through it moves here too (#424).
        {payload, one} = Compiled.tick(one, sources, [frame: node(design, name)] ++ clock)

        {%{
           name: name,
           canvas: payload.canvas,
           incremental: payload.incremental,
           dynamic_svg: payload.svg,
           backdrop: payload.backdrop,
           bytes: payload.bytes,
           box: one.box,
           plot: one.plot,
           margin: one.margin
         }, [{name, one} | acc]}
      end)

    {%{
       svg: nil,
       plots: plots,
       bytes: Enum.sum(Enum.map(plots, & &1.bytes)),
       points: rows(sources)
     }, %{state | compiled: Enum.reverse(compiled)}}
  end

  # The design's node for one frame: what `tick/3` re-realises the frame at (#424).
  defp node(design, name), do: get_in(design, [:frames, name])

  # A design whose *marks* move between ticks is a different chart, and the caller
  # compiles it again (spec/14 §12.5, #424): the region builders close over the mark
  # nodes and the render targets are counted from them, so a tick cannot swap them. The
  # force graph animates the link distance of its `:force` step, which is a mark's
  # transform; its frame never moves, so `tick/3`'s `frame:` cannot reach it.
  #
  # The fresh compilation carries the last one's state (`carry/2`): the easing, and the
  # force graph's warm layout, which is what makes it one graph moving rather than a new
  # graph every frame (#527, D-132).
  defp recompiled(compiled, design, module, opts, backend) do
    drawn = Enum.flat_map(compiled, fn {_name, one} -> one.chart.marks end)

    if design.marks == drawn do
      compiled
    else
      carry(%{compiled: compiled}, prepare(module, opts, backend)).compiled
    end
  end

  defp svg_frame(svg, sources) do
    %{svg: svg, plots: [], bytes: byte_size(svg), points: rows(sources)}
  end

  defp rows(sources) when is_map(sources) do
    Enum.reduce(sources, 0, fn
      {_slot, rows}, acc when is_list(rows) -> acc + length(rows)
      _other, acc -> acc
    end)
  end
end
