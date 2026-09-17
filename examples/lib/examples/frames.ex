defmodule Examples.Frames do
  @moduledoc """
  One chart's frames, for a run or a comparison (spec/14 §12.6, #322): what a backend
  renders of a chart module at a tick, and the state a backend keeps between ticks.

  Two backends: `:svg`, the chart rendered whole; `:canvas`, for a design the split —
  compiled once (`prepare/3`), ticked per frame with `render: :binary` — and for a chart
  that is not yet a design the whole-element binary. A frame is `%{svg, canvas,
  dynamic_svg, bytes, points}`: the SVG to show or nil, the base64 stream to push or nil,
  a tick's SVG-layer marks, the bytes the frame cost, and the rows it drew.
  """

  alias Examples.Charts.Design
  alias Visualize.Backend.CanvasBinary
  alias Visualize.Chart
  alias Visualize.Chart.Compiled

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
  The state a backend keeps for a run of `module` at `opts`: for a design on the canvas,
  the compiled chart and its static SVG (the furniture, rendered once); nothing otherwise.
  """
  @spec prepare(module(), keyword(), backend()) :: map() | nil
  def prepare(module, opts, backend) when backend in [:canvas, :incremental] do
    if Design.design?(module) do
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
  end

  def prepare(_module, _opts, :svg), do: nil

  @doc "The static SVG a prepared state carries, or an empty string."
  @spec static(map() | nil) :: String.t()
  def static(%{static: static}), do: static
  def static(_state), do: ""

  @doc "A frame of `module` at `opts` on `backend`, and the state after it."
  @spec frame(module(), keyword(), backend(), map() | nil) :: {frame(), map() | nil}
  def frame(module, opts, :svg, state) do
    svg =
      case module.render(opts) do
        svg when is_binary(svg) ->
          svg

        element ->
          element
          |> Examples.Accessible.name(module.title(), module.description())
          |> Visualize.SVG.Renderer.render_to_string()
      end

    {%{svg: svg, canvas: nil, incremental: nil, dynamic_svg: "", bytes: byte_size(svg), points: points(module, opts)},
     state}
  end

  # The compiled chart ticked: `now:` from the opts for a streaming design, so the
  # window's upper end is the run's and not the rows' (spec/14 §12.5).
  def frame(module, opts, backend, %{compiled: compiled} = state) when backend in [:canvas, :incremental] do
    {_design, sources} = module.design(opts)
    tick_opts = if now = opts[:now], do: [now: now], else: []
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

  def frame(module, opts, :canvas, nil) do
    canvas =
      case CanvasBinary.encode_element(module.render(opts)) do
        {:ok, binary} -> Base.encode64(binary)
        {:error, _} -> ""
      end

    {%{svg: nil, canvas: canvas, incremental: nil, dynamic_svg: "", bytes: byte_size(canvas), points: nil}, nil}
  end

  # The rows a design binds at `opts`, or nil for a chart that is not one.
  defp points(module, opts) do
    if Design.design?(module) do
      {_design, sources} = module.design(opts)
      rows(sources)
    end
  end

  defp rows(sources) when is_map(sources) do
    Enum.reduce(sources, 0, fn
      {_slot, rows}, acc when is_list(rows) -> acc + length(rows)
      _other, acc -> acc
    end)
  end
end
