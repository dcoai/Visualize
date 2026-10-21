if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Components.Chart do
    @moduledoc """
    A chart whose marks declare events, in LiveView (spec/10 §19, D-170).

    A `Phoenix.LiveComponent` over a `%Visualize.Chart.Applied{}`. It draws the chart —
    as SVG by default, or on a canvas — inside `TooltipHook`, the datum under the pointer
    outlined as the palette's `:hover` (`Visualize.Hooks.Tooltip.attrs/1`), holds the
    drawing and a token for it, and resolves a click on a mark's datum to the row that was
    drawn. The page receives the click as one `Visualize.Event`, the same on every backend
    (D-197):

        <.live_component module={Visualize.Components.Chart} id="sales" chart={@applied} />

        def handle_info({:visualize_event, "sales", %Visualize.Event{event: "point_click", row: row}}, socket) do
          {:noreply, assign(socket, picked: row)}
        end

    A click is dropped, never forwarded with partial data, when it was made on a drawing
    the component no longer holds, names an event its mark does not declare, or names a row
    the drawing does not have. A chart whose marks declare no event needs no component.

    ## Assigns

      * `id` - the component's id, its hook element's DOM id, and the `id` of the events it
        sends (required)
      * `chart` - the `%Visualize.Chart.Applied{}` drawn (required)
      * `backend` - `:svg` (default) or `:canvas`: on a canvas the drawing carries its hit
        index, `Visualize.Hooks.Tooltip.items/1`, so a click resolves as on the SVG
      * `canvas_format` - `:binary` (default) for `CanvasBinaryChart`, or `:json` for
        `CanvasChart`; the binary stream draws no text, so its text is laid over the canvas
        as an SVG layer
      * `render` - options for `Visualize.Chart.render/2` — `title:`, `description:`,
        `responsive:` … — the SVG always a root (default `[]`)
      * `tooltip_class` - the hook's `data-tooltip-class` (default `"vis-tooltip"`)

    ## What a move sends

    The drawing travels as keyed segments (`Visualize.Render.Segments`, spec/10 §19.3,
    D-203): one per item — a mark's element, a label — and one for each start and end of a
    group, each keyed by the item's identity (D-167) or its place in the drawing, sent as a
    LiveView comprehension. An update that changes three cells of a grid sends those three
    segments and none of the others, on SVG and on either canvas, where the canvas's hook
    puts the stream together from its segments. The keyboard's points travel one element
    each the same way (`Visualize.Hooks.Keyboard.listed/2`, D-204), and every other part —
    the hit index, the canvas's text layer, the summary — is its own assign, sent only when
    it changed (D-205). A segment whose element did not change is not written again.
    """

    use Phoenix.LiveComponent

    alias Visualize.Chart
    alias Visualize.Chart.{Applied, Summary}
    alias Visualize.Event
    alias Visualize.Hooks.{Keyboard, Tooltip}
    alias Visualize.IR.Element
    alias Visualize.Render.Segments

    # A binary heap no drawing reaches, in words: binaries never trigger a collection.
    @bin_vheap 1_000_000_000

    @impl true
    def mount(socket) do
      {:ok,
       assign(socket,
         drawing: nil,
         drawn: nil,
         backend: :svg,
         segments: [],
         cache: %{},
         canvas: nil,
         items: nil,
         text: [],
         text_cache: %{},
         summary: nil,
         hover: %{},
         keyboard: %{},
         points: [],
         points_cache: %{},
         motion: false,
         heap: nil
       )}
    end

    @impl true
    def update(%{id: id, chart: %Applied{} = chart} = assigns, socket) do
      render_opts = Map.get(assigns, :render, [])

      backend =
        backend!(Map.get(assigns, :backend, :svg), Map.get(assigns, :canvas_format, :binary))

      socket =
        socket
        |> assign(id: id, tooltip_class: Map.get(assigns, :tooltip_class, "vis-tooltip"))
        |> draw({chart, render_opts, backend})

      {:ok, socket}
    end

    defp backend!(:svg, _format), do: :svg
    defp backend!(:canvas, format) when format in [:binary, :json], do: {:canvas, format}

    defp backend!(backend, format) do
      raise ArgumentError,
            "backend: :svg or :canvas with canvas_format: :binary or :json is needed, " <>
              "got: #{inspect({backend, format})}"
    end

    # A new chart, new render options or a new backend is a new drawing with a new token
    # (spec/10 §19.3); the same ones keep both, so an unrelated update does not drop a
    # click in flight.
    defp draw(%{assigns: %{drawing: drawing}} = socket, drawing), do: socket

    defp draw(socket, {chart, render_opts, backend} = drawing) do
      # What the last drawing wrote, kept only for the same backend.
      last =
        if socket.assigns.backend == backend,
          do: Map.take(socket.assigns, [:cache, :text_cache, :points_cache]),
          else: %{cache: %{}, text_cache: %{}, points_cache: %{}}

      {drawn, heap} =
        apart(fn -> drawn(chart, render_opts, backend, last) end, socket.assigns.heap)

      socket
      |> assign(
        drawing: drawing,
        backend: backend,
        heap: heap,
        drawn: Integer.to_string(System.unique_integer([:positive, :monotonic]))
      )
      |> assign(drawn)
    end

    # The drawing is made in a process of its own (spec/10 §19.3, D-206): a large chart
    # allocates tens of megabytes it drops at once, and collecting them in the LiveView's
    # process, around its state, tripled the time of a move. Sized to the drawing's need,
    # the process collects nothing — its binaries do not trigger a collection either — and
    # its heap is freed whole when it ends; only what it returns is copied back. It is
    # linked, so a fault in it is the LiveView's, as it was in place.
    #
    # The need is measured from outside (#850, D-216): a process reading its own
    # `heap_size` gets its heap block, so a drawing measuring itself reported the heap it
    # was given, and the size grew by half a move without bound. Once the drawing has
    # sent its parts it waits, and its heap in use is read here before it is let go.
    # `heap` is the size `next_heap/1` made of the last drawing, or `nil`: unsized.
    @doc false
    @spec apart((-> result), pos_integer() | nil) :: {result, pos_integer() | nil}
          when result: term()
    def apart(fun, heap) do
      parent = self()
      ref = make_ref()
      sized = if heap, do: [min_heap_size: heap, min_bin_vheap_size: @bin_vheap], else: []

      pid =
        :erlang.spawn_opt(
          fn ->
            send(parent, {ref, fun.()})

            receive do
              ^ref -> :ok
            end
          end,
          [:link, {:max_heap_size, max_heap()} | sized]
        )

      receive do
        {^ref, result} ->
          {:garbage_collection_info, info} = Process.info(pid, :garbage_collection_info)
          send(pid, ref)
          {result, next_heap(info)}
      end
    end

    @doc false
    # The next drawing's minimum heap, from one drawing's own measurement (D-216): the
    # words it used and a quarter more when it never collected; when it did, what it used
    # is only a lower bound, and 16 times the data its collections kept — its old heap and
    # what the last one left on its young heap — is over its need (3–9 times on the cost
    # test's boards). Never a function of the heap it was given, and never past the bound:
    # past it, unsized.
    @spec next_heap(keyword()) :: pos_integer() | nil
    def next_heap(info) do
      used = info[:heap_size] + info[:old_heap_size]
      # Data a collection kept: none in a drawing that never collected.
      kept = info[:recent_size] + info[:old_heap_size]
      next = if kept > 0, do: 16 * kept, else: used + div(used, 4)
      if next <= heap_bound(), do: next
    end

    @doc false
    # The most a drawing's minimum heap is: 512 MiB in this system's words, about 15
    # times a 2,500-cell move's need (spec/10 §19.3, D-216). Not an option.
    @spec heap_bound() :: pos_integer()
    def heap_bound, do: div(512 * 1024 * 1024, :erlang.system_info(:wordsize))

    # A drawing whose heap passes four times the bound is killed and reported, and takes
    # its LiveView with it, not the node (D-216).
    defp max_heap do
      %{size: 4 * heap_bound(), kill: true, error_logger: true, include_shared_binaries: false}
    end

    @doc false
    # Everything an update draws (spec/10 §19.3): the placements made once, the keyboard's
    # points (D-204), and the drawing as segments on its backend (D-203), each part an
    # assign of its own (D-205). `last` is what the last drawing on this backend kept.
    # The cost test counts this (spec/12 §6, D-202).
    @spec drawn(Applied.t(), keyword(), term(), map()) :: map()
    def drawn(chart, render_opts, backend, last) do
      # The items placed once, for the drawing and the keyboard (#811).
      placements = Chart.placements(chart)
      # Every point and every keyed item reached from the keyboard (spec/10 §17, D-198), one
      # element each (D-204).
      {keyboard, points, points_cache} =
        Keyboard.listed(chart, placements: placements, cache: last.points_cache)

      %{
        hover: Tooltip.attrs(chart.frame),
        keyboard: keyboard,
        points: points,
        points_cache: points_cache
      }
      |> Map.merge(drawn_as(backend, chart, [placements: placements] ++ render_opts, last))
    end

    # As SVG: the root `Visualize.Chart.render/2` writes, in segments.
    defp drawn_as(:svg, chart, render_opts, %{cache: cache}) do
      generate = [root: true, resolve: Keyword.get(render_opts, :resolve, :css)]
      tree = Chart.generate(chart, generate ++ Keyword.drop(render_opts, [:resolve, :backend]))
      {segments, cache} = Segments.svg(tree, cache)

      # A drawing that names identities plays its exits and enters (spec/10 §19.3, §20).
      motion = Enum.any?(segments, fn {key, _text} -> String.starts_with?(key, "id:") end)
      %{segments: segments, cache: cache, canvas: nil, motion: motion}
    end

    # On a canvas (spec/10 §19.3, D-197): the stream, the hit index and the size from one
    # generated tree in literal colors, and on the binary stream the text it cannot carry.
    # Each is an assign of its own, so one that did not change is not sent (D-205).
    defp drawn_as({:canvas, format}, chart, render_opts, last) do
      %{cache: cache, text_cache: text_cache} = last
      tree = Chart.generate(chart, resolve: :literal, placements: render_opts[:placements])
      %{width: width, height: height} = chart.frame.size
      summary = Summary.new(chart)
      title = Keyword.get(render_opts, :title, summary.name)
      {segments, cache} = pieces(tree, format, cache)

      {text, text_cache} =
        if format == :binary,
          do: text_layer(tree, width, height, text_cache),
          else: {[], %{}}

      %{
        canvas: %{format: format, width: width, height: height},
        segments: segments,
        cache: cache,
        text: text,
        text_cache: text_cache,
        items: Tooltip.items(tree),
        summary: %{summary | name: title},
        motion: false
      }
    end

    defp pieces(tree, :binary, cache), do: Segments.binary(tree, cache)
    defp pieces(tree, :json, cache), do: Segments.json(tree, cache)

    # The chart's text as an SVG over the canvas, `aria-hidden` and taking no pointer, in
    # segments: one picture with the canvas, which names it. None for a chart that draws
    # no text.
    defp text_layer(tree, width, height, cache) do
      case only_text(tree) do
        nil ->
          {[], %{}}

        text ->
          Element.root(width, height, hidden: true, children: [text])
          |> Segments.svg(cache)
      end
    end

    defp only_text(%Element{type: :text} = element), do: element

    defp only_text(%Element{type: :group, children: children} = element) do
      case children |> Enum.map(&only_text/1) |> Enum.reject(&is_nil/1) do
        [] -> nil
        kept -> %{element | children: kept}
      end
    end

    defp only_text(_element), do: nil

    @impl true
    def handle_event("visualize_event", params, socket) do
      %{id: id, drawing: {chart, _render_opts, _backend}, drawn: drawn} = socket.assigns

      with {:ok, click} <- Event.decode(params),
           {:ok, event} <- Event.resolve(click, chart, drawn: drawn) do
        send(self(), {:visualize_event, id, event})
      end

      {:noreply, socket}
    end

    def handle_event(_event, _params, socket), do: {:noreply, socket}

    # A segment of markup, written as it is.
    defp segment(assigns), do: ~H"{Phoenix.HTML.raw(@text)}"

    # The drawing's segments, keyed (D-203).
    defp segments(assigns) do
      ~H"""
      <.segment :for={{key, text} <- @segments} :key={key} text={text} />
      """
    end

    # The keyboard's points, one element each, keyed (D-204).
    defp points(assigns) do
      ~H"""
      <div hidden data-keyboard-list="">
        <i :for={{key, point} <- @points} :key={key} data-p={point}></i>
      </div>
      """
    end

    @impl true
    def render(%{canvas: nil} = assigns) do
      ~H"""
      <div id={"#{@id}-keys"} phx-hook="KeyboardHook" data-keyboard-drawn={@drawn} {@keyboard}>
        <.points points={@points} />
        <div
          id={@id}
          phx-hook="TooltipHook"
          data-tooltip-target={@myself}
          data-tooltip-drawn={@drawn}
          data-tooltip-class={@tooltip_class}
          {@hover}
        >
          <div :if={@motion} id={"#{@id}-motion"} phx-hook="MotionHook">
            <.segments segments={@segments} />
          </div>
          <.segments :if={!@motion} segments={@segments} />
        </div>
      </div>
      """
    end

    def render(assigns) do
      ~H"""
      <div id={"#{@id}-keys"} phx-hook="KeyboardHook" data-keyboard-drawn={@drawn} {@keyboard}>
      <.points points={@points} />
      <div
        id={@id}
        phx-hook="TooltipHook"
        data-tooltip-target={@myself}
        data-tooltip-drawn={@drawn}
        data-tooltip-class={@tooltip_class}
        data-vis-items={@items}
        data-size={"#{@canvas.width},#{@canvas.height}"}
        {@hover}
      >
        <div
          class="vis-chart-layers"
          style={"position: relative; width: #{@canvas.width}px; height: #{@canvas.height}px;"}
          {Summary.attrs(@summary, "#{@id}-access")}
        >
          {Phoenix.HTML.raw(Summary.description(@summary, "#{@id}-access"))}
          <div hidden data-vis-stream="">
            <i :for={{key, piece} <- @segments} :key={key} data-c={piece}></i>
          </div>
          <div
            :if={@canvas.format == :binary}
            id={"#{@id}-canvas"}
            phx-hook="CanvasBinaryChart"
            phx-update="ignore"
            data-stream=""
            data-drawn={@drawn}
            data-width={@canvas.width}
            data-height={@canvas.height}
          >
            <canvas width={@canvas.width} height={@canvas.height} style="display: block;"></canvas>
          </div>
          <div
            :if={@canvas.format == :json}
            id={"#{@id}-canvas"}
            phx-hook="CanvasChart"
            phx-update="ignore"
            data-stream=""
            data-drawn={@drawn}
            data-width={@canvas.width}
            data-height={@canvas.height}
          >
            <canvas width={@canvas.width} height={@canvas.height} style="display: block;"></canvas>
          </div>
          <div
            :if={@text != []}
            class="vis-chart-text"
            style="position: absolute; top: 0; left: 0; pointer-events: none;"
          >
            <.segments segments={@text} />
          </div>
        </div>
      </div>
      </div>
      """
    end
  end
end
