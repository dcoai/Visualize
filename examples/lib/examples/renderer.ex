defmodule Examples.Renderer do
  @moduledoc """
  One process renders a run's frames (spec/14 §12.6, #413): started when a run starts and
  kept for as long as it lasts, it holds the backend's state — the compiled chart and its
  static SVG — and, for a streaming design, the window's rows, so nothing crosses to it
  but a tick's options and nothing comes back but the frame.

  A task per frame copied all of that on every frame: the same frame cost 5 ms in the
  process that built it and 14 ms through a task, the window's rows being two megabytes
  of it at 22,201 points. The rule the task was there for (#323) is unchanged — no frame
  renders in the view's process — and now it costs the message alone.

  The owner receives `{:frame, id, frame}` per rendered frame, and monitors the renderer:
  a render that raises takes the renderer down with it, and the view stops the run with
  the reason, as it did for a task's `:DOWN`.
  """

  use GenServer, restart: :temporary

  alias Examples.{Frames, Scroll}

  @typedoc "What a caller starts a renderer with."
  @type opts :: [module: module(), backend: Frames.backend(), opts: keyword(), owner: pid()]

  @doc """
  Starts a renderer for `module` on `backend`, preparing that backend's state over `opts`.

  Runs under `Examples.RendererSupervisor`; `{:error, message}` when that supervisor is
  not running, as `Examples.Run.supervisor/0` reports for tasks (#340).
  """
  @spec start(module(), Frames.backend(), keyword(), pid()) :: {:ok, pid()} | {:error, String.t()}
  def start(module, backend, opts, owner \\ self()) do
    case supervisor() do
      :ok ->
        DynamicSupervisor.start_child(
          Examples.RendererSupervisor,
          {__MODULE__, module: module, backend: backend, opts: opts, owner: owner}
        )

      {:error, _message} = error ->
        error
    end
  end

  @no_supervisor "the renderer supervisor is not running — the server was started before Examples.RendererSupervisor joined its supervision tree; restart the server (a recompile does not rebuild the tree)"

  @doc "Whether `Examples.RendererSupervisor` is running: `:ok`, or `{:error, message}`."
  @spec supervisor() :: :ok | {:error, String.t()}
  def supervisor do
    if Process.whereis(Examples.RendererSupervisor), do: :ok, else: {:error, @no_supervisor}
  end

  @doc """
  Asks for a frame at `opts`, answered to the owner as `{:frame, id, frame}`.

  `columns` is how many pixel columns the window advanced by, for a streaming design: the
  renderer slides its own rows by them (`module.rows/3`), so the window never crosses.
  """
  @spec frame(pid(), term(), keyword(), non_neg_integer()) :: :ok
  def frame(renderer, id, opts, columns \\ 0) do
    GenServer.cast(renderer, {:frame, id, opts, columns})
  end

  @doc """
  Re-prepares the backend's state for `backend` at `opts` without stopping (spec/14 §12.6):
  a new size (#434), another backend (#502), a theme or a hex size picked mid-run (#796) —
  whatever the page changes that the compiled chart is built over. The fresh state
  **carries the easing** of the one it replaces (spec/14 §12.5), which is dropped —
  released, never drawn again — and the window's rows are the run's, kept.

  A compiled chart's plot, its theme and its marks are part of its state, so a chart drawn
  under other options is compiled again; `Visualize.Chart.Compiled.carry/2` keeps each
  frame's eased scales and mark motions, so a transition goes on from where it stood. A
  cast handled in order, like `frame/4`, so it never blocks the view: a frame asked before
  it is drawn under the old options and one asked after under the new.
  """
  @spec prepare(pid(), Frames.backend(), keyword()) :: :ok
  def prepare(renderer, backend, opts),
    do: GenServer.cast(renderer, {:prepare, backend, opts})

  @doc "Stops a renderer; a pid that is gone is `:ok` too."
  @spec stop(pid() | nil) :: :ok
  def stop(nil), do: :ok

  def stop(renderer) when is_pid(renderer) do
    if Process.alive?(renderer), do: GenServer.stop(renderer, :normal), else: :ok
  end

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    module = Keyword.fetch!(opts, :module)
    backend = Keyword.fetch!(opts, :backend)
    chart_opts = Keyword.get(opts, :opts, [])

    {:ok,
     %{
       module: module,
       backend: backend,
       owner: Keyword.fetch!(opts, :owner),
       state: Frames.prepare(module, chart_opts, backend),
       rows: streaming_rows(module, chart_opts)
     }}
  end

  @impl true
  def handle_cast({:frame, id, opts, columns}, state) do
    rows = slide(state, opts, columns)
    opts = if rows, do: Keyword.put(opts, :rows, rows), else: opts
    {frame, render_state} = Frames.frame(state.module, opts, state.backend, state.state)
    send(state.owner, {:frame, id, frame})
    {:noreply, %{state | state: render_state, rows: rows}}
  end

  @impl true
  def handle_cast({:prepare, backend, opts}, state) do
    fresh = Frames.prepare(state.module, opts, backend)
    {:noreply, %{state | backend: backend, state: Frames.carry(state.state, fresh)}}
  end

  @doc """
  The backend's state as the renderer holds it — the compiled chart and what it carries
  between ticks. For a test or a diagnosis, never a frame: it is a copy.
  """
  @spec state(pid()) :: map() | nil
  def state(renderer), do: GenServer.call(renderer, :state)

  @doc "The backend the renderer draws on: the one it started on, or the last switched to."
  @spec backend(pid()) :: Frames.backend()
  def backend(renderer), do: GenServer.call(renderer, :backend)

  @impl true
  def handle_call(:state, _from, state), do: {:reply, state.state, state}
  def handle_call(:backend, _from, state), do: {:reply, state.backend, state}

  # The window's rows: built once at the start for a streaming design, nothing otherwise.
  defp streaming_rows(module, opts) do
    if Frames.stream?(module), do: module.rows(module.scroll(opts)), else: nil
  end

  # The rows of the tick: the window slid by the columns it advanced (#408), or rebuilt
  # when the caller says the window changed shape — a rate change gives no columns and a
  # window whose count differs from the rows held.
  defp slide(%{rows: nil}, _opts, _columns), do: nil

  defp slide(%{module: module, rows: held}, opts, columns) do
    scroll = module.scroll(opts)

    if columns > 0 and count_of(held) == Scroll.count(scroll) do
      module.rows(scroll, columns, held)
    else
      module.rows(scroll)
    end
  end

  defp count_of(rows) do
    case Map.values(rows) do
      [first | _] -> length(first)
      [] -> 0
    end
  end
end
