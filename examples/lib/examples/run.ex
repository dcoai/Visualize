defmodule Examples.Run do
  @moduledoc """
  The frame loop every page that streams frames drives (spec/14 §12.6, #322): a struct of
  a run's state and pure functions over it, the clock passed in.

  A run ticks by deadline (`schedule/2`), accounts the samples due since the last tick as
  whole columns of the page's density (`tick/3`), decides what a frame goes as — strips,
  the empty `"none"` update, a full render, or held back by flow control (`decide/5`) —
  numbers every frame it sends (`sending/1`), renders it in the run's own renderer under
  `Examples.RendererSupervisor`, one in flight, and measures the result (`renderer/4`,
  `asking/3`, `result/2`, `rendered/3`); the hook's acks (`acked/4`) bound the frames in flight to a
  lag budget with a hold that fails open (`hold/2`); `stop/1` terminates a render in
  flight at once. A page owns the run in one assign and reads its metrics from it.
  """

  alias Visualize.Backend.CanvasIncremental

  @max_lag_ms 250
  @ack_timeout 2000
  # The slider's cap (spec/14 §12.6, #400): a target above it is unlimited.
  @max_fps 120
  @lag_alpha 2 / 31
  @history 120

  @type mode :: :scroll_x | :none | :full_redraw | :drop

  @type t :: %__MODULE__{}

  defstruct running: false,
            target_fps: 60,
            data_rate: 0,
            flow_control: true,
            # the reader's choice of flow control, kept while a backend that cannot ack is on
            flow_wanted: true,
            # the backend the run renders on, and the closed measurement segments (#502, D-128)
            backend: nil,
            segments: [],
            # the clock
            next_due: nil,
            last_tick: nil,
            # samples: whole ones pending a column, the fraction carried, the last second's arrivals
            pending: 0,
            carry: 0.0,
            arrivals: [],
            measured_rate: 0.0,
            # frames sent and measured
            frame: 0,
            frame_times: [],
            render_times: [],
            fps: 0.0,
            lag: 0.0,
            payload_size: 0,
            needs_full: true,
            # the hook's acks and flow control
            sent_seq: 0,
            acked_seq: 0,
            # the last sequence sent before a backend switch: an ack at or below it is ignored
            seq_floor: 0,
            acks: [],
            client_fps: 0.0,
            dropped: 0,
            hold_since: nil,
            last_ack_at: nil,
            acking: :unknown,
            stalls: 0,
            ack_age: nil,
            # the render in flight
            renderer: nil,
            render_id: nil,
            monitor: nil,
            render_started: nil,
            skipped: 0,
            error: nil

  @doc "A run with its target rate, data rate (samples/s per series, 0 for none) and flow control."
  @spec new(keyword()) :: t()
  def new(opts \\ []), do: struct(__MODULE__, opts)

  @doc "The run started at `now_ms`/`now_us`: counters at zero, the first frame a full one."
  @spec start(t(), integer(), integer()) :: t()
  def start(%__MODULE__{} = run, now_ms, now_us) do
    new(
      target_fps: run.target_fps,
      data_rate: run.data_rate,
      flow_control: run.flow_control,
      flow_wanted: run.flow_wanted,
      backend: run.backend,
      running: true,
      last_tick: now_ms,
      next_due: now_us,
      needs_full: true
    )
  end

  @doc """
  The run on `backend`: flow control is the reader's choice of it (`flow_wanted`) where
  the backend acks and off where it does not — an SVG frame has no ack to wait for
  (spec/10 §8.2) — so a run that passes through SVG keeps the reader's choice (#502).
  """
  @spec on(t(), Examples.Frames.backend()) :: t()
  def on(%__MODULE__{} = run, backend) do
    %{run | backend: backend, flow_control: run.flow_wanted and Examples.Frames.acks?(backend)}
  end

  @doc "The reader's flow-control toggle: the choice and the run's flow control flip together."
  @spec toggle_flow_control(t()) :: t()
  def toggle_flow_control(%__MODULE__{flow_control: on} = run),
    do: %{run | flow_control: not on, flow_wanted: not on}

  @doc """
  The run switched to `backend` without stopping (spec/14 §12.6, #502, D-128).

  The measurement segment of the backend it was on closes — its numbers kept, newest
  first, in `segments` when it drew a frame — and every frame and ack metric starts
  again, so the metrics are never two backends'. The data clock carries on. The sequence
  floor is the last sequence sent: sequences keep rising, so an ack at or below it is the
  old backend's and `acked/4` ignores it, and nothing is in flight for the new one. The
  frame in flight was asked of the old backend and is forgotten, so its answer is stale
  (`result/2`); the next frame is a full one.
  """
  @spec switch(t(), Examples.Frames.backend()) :: t()
  def switch(%__MODULE__{} = run, backend) do
    segments = if run.frame > 0, do: [segment(run) | run.segments], else: run.segments

    %{
      on(run, backend)
      | segments: segments,
        seq_floor: run.sent_seq,
        acked_seq: run.sent_seq,
        needs_full: true,
        render_id: nil,
        render_started: nil,
        frame: 0,
        frame_times: [],
        render_times: [],
        fps: 0.0,
        lag: 0.0,
        payload_size: 0,
        acks: [],
        client_fps: 0.0,
        dropped: 0,
        hold_since: nil,
        last_ack_at: nil,
        acking: :unknown,
        stalls: 0,
        ack_age: nil,
        skipped: 0
    }
  end

  @doc """
  The run's measurement on its backend as it stands: what a switch closes into a segment
  and what the drawer's per-backend table reads for the current one (D-128).
  """
  @spec segment(t()) :: map()
  def segment(%__MODULE__{} = run) do
    %{
      backend: run.backend,
      frames: run.frame,
      fps: run.fps,
      client_fps: run.client_fps,
      avg_render_us: avg_render_us(run),
      payload_size: run.payload_size,
      dropped: run.dropped,
      stalls: run.stalls,
      skipped: run.skipped
    }
  end

  @doc "The run stopped: a render in flight terminated and its messages flushed."
  @spec stop(t()) :: t()
  def stop(%__MODULE__{} = run), do: %{cancel(run) | running: false}

  @doc """
  The run whose next frame is a full redraw (spec/14 §12.6, #401): what a dropped scroll
  frame raises, and what a density change needs — a column drawn at the old density means
  a different span at the new one, so the canvas is repainted rather than copy-shifted.
  """
  @spec resync(t()) :: t()
  def resync(%__MODULE__{} = run), do: %{run | needs_full: true}

  @doc """
  The run whose renderer was re-prepared at the page's new options (spec/14 §12.6, #796):
  a theme, a size or a hex size changed mid-run. The frame in flight was asked under the
  old options and is forgotten, so its answer is stale (`result/2`) and never shown; the
  next tick asks again, answered after the re-preparation, and that frame is full. The
  backend, its segment and the counters are untouched — `switch/2` is this with a backend.
  """
  @spec reprepared(t()) :: t()
  def reprepared(%__MODULE__{} = run),
    do: %{run | needs_full: true, render_id: nil, render_started: nil}

  @doc "The run's renderer stopped and its monitor dropped; nothing else changes."
  @spec cancel(t()) :: t()
  def cancel(%__MODULE__{renderer: pid, monitor: monitor} = run) when is_pid(pid) do
    if monitor, do: Process.demonitor(monitor, [:flush])
    Examples.Renderer.stop(pid)
    %{run | renderer: nil, monitor: nil, render_id: nil}
  end

  def cancel(%__MODULE__{} = run), do: run

  # ── the clock ─────────────────────────────────────────────────────────────────────────

  @doc """
  The next tick's deadline and the milliseconds to wait for it (#302): the deadline
  advances by the period, never before `now_us`, and the wait is the nearest whole
  millisecond, so a target between whole-millisecond rates averages to it. A target
  above 2,000 is unlimited: no wait.
  """
  @spec schedule(t(), integer()) :: {t(), non_neg_integer()}
  def schedule(%__MODULE__{target_fps: fps, next_due: due} = run, now_us) do
    {next, delay} = if fps > @max_fps, do: {now_us, 0}, else: deadline(due, now_us, fps)
    {%{run | next_due: next}, delay}
  end

  @doc "The next deadline after `due` at `fps`, never before `now`, and the whole ms to wait."
  @spec deadline(number(), integer(), pos_integer()) :: {number(), non_neg_integer()}
  def deadline(due, now, fps) do
    next = max(due + 1_000_000 / fps, now)
    {next, round((next - now) / 1000)}
  end

  # ── samples and columns ───────────────────────────────────────────────────────────────

  @doc """
  A tick at `now_ms`: the samples due since the last tick at the data rate join the
  pending count (#300), and — with no render in flight — the whole columns they fill at
  `samples_per_px` are the frame's scroll, the remainder kept; a tick that finds a render
  in flight is counted *Skipped* and its samples wait (#323), so the next frame scrolls
  by all of them.
  """
  @spec tick(t(), integer(), pos_integer()) :: {t(), {:draw, non_neg_integer()} | :skipped}
  def tick(%__MODULE__{} = run, now_ms, samples_per_px) do
    elapsed = if run.last_tick, do: now_ms - run.last_tick, else: 0
    due = run.carry + run.data_rate * elapsed / 1000
    arrived = trunc(due)
    arrivals = Enum.take([{now_ms, arrived} | run.arrivals], @history)

    run = %{
      run
      | last_tick: now_ms,
        carry: due - arrived,
        pending: run.pending + arrived,
        arrivals: arrivals,
        measured_rate: rate_over(arrivals, now_ms)
    }

    if run.render_id do
      {%{run | skipped: run.skipped + 1}, :skipped}
    else
      columns = div(run.pending, samples_per_px)
      {%{run | pending: rem(run.pending, samples_per_px)}, {:draw, columns}}
    end
  end

  # ── what a frame goes as ──────────────────────────────────────────────────────────────

  @doc """
  What this tick's frame goes as, for a scroll of `columns` pixels over a plot of `size`
  (D-107): `:drop` when flow control holds it back — the window in flight and the hold
  young, `hold/2` — counted and, if the picture moved, making the next frame a full one;
  `:full_redraw` with incremental rendering off, on a run's first frame or after a
  dropped scroll; otherwise what `scroll_mode/2` says of the scroll — `:scroll_x` strips,
  or the empty `:none` update. The run returned has the hold, the drop and the lag's
  age applied.
  """
  @spec decide(t(), non_neg_integer(), boolean(), {number(), number()}, integer()) ::
          {t(), mode()}
  def decide(%__MODULE__{} = run, columns, incremental?, size, now_ms) do
    run = %{hold(run, now_ms) | ack_age: ack_age(run, now_ms)}

    cond do
      holding?(run) ->
        {%{run | dropped: run.dropped + 1, needs_full: run.needs_full or columns > 0}, :drop}

      not incremental? or run.needs_full ->
        {run, :full_redraw}

      true ->
        {run, CanvasIncremental.scroll_mode({columns, 0}, size)}
    end
  end

  @doc "Frames sent and not yet acknowledged."
  @spec in_flight(t()) :: integer()
  def in_flight(%__MODULE__{sent_seq: sent, acked_seq: acked}), do: sent - acked

  @doc "The frames the lag budget allows in flight at the target rate — fifteen at 60 fps."
  @spec window(t()) :: pos_integer()
  def window(%__MODULE__{target_fps: fps}),
    do: max(2, ceil(@max_lag_ms * min(fps, @max_fps) / 1000))

  @doc "The slider's cap: the highest target that is a rate; above it a run is unlimited."
  @spec max_fps() :: pos_integer()
  def max_fps, do: @max_fps

  @doc "Whether the run's target is above the cap: frames as fast as they render, no lag read."
  @spec unlimited?(t()) :: boolean()
  def unlimited?(%__MODULE__{target_fps: fps}), do: fps > @max_fps

  defp holding?(run) do
    run.flow_control and run.acking != :no and in_flight(run) >= window(run)
  end

  @doc """
  A hold fails open (#306, D-107): a hold that outlives the ack timeout ends — with no ack
  ever in the run the client does not acknowledge and the run stops holding
  (`acking: :no`); with acks before, the client is stalled, the window is released and the
  stall counted.
  """
  @spec hold(t(), integer()) :: t()
  def hold(%__MODULE__{} = run, now_ms) do
    cond do
      not holding?(run) -> %{run | hold_since: nil}
      run.hold_since == nil -> %{run | hold_since: now_ms}
      now_ms - run.hold_since <= @ack_timeout -> run
      run.last_ack_at == nil -> %{run | acking: :no, hold_since: nil}
      true -> %{run | acked_seq: run.sent_seq, stalls: run.stalls + 1, hold_since: nil}
    end
  end

  defp ack_age(%{last_ack_at: nil}, _now), do: nil
  defp ack_age(%{last_ack_at: at}, now), do: now - at

  # ── sending, rendering, measuring ─────────────────────────────────────────────────────

  @doc "The next frame's sequence, the frame counted as sent; a full frame clears the need for one."
  @spec sending(t(), mode()) :: {t(), pos_integer()}
  def sending(%__MODULE__{} = run, mode) do
    seq = run.sent_seq + 1
    needs_full = if mode == :full_redraw, do: false, else: run.needs_full
    {%{run | sent_seq: seq, needs_full: needs_full}, seq}
  end

  @doc """
  The run's renderer, started for as long as the run lasts (#413): one process holds the
  backend's state and the window's rows, so a frame costs the message and not a copy of
  them (#323 is unchanged — no frame renders in the view's process). With no supervisor
  running the run fails open — stopped, its `error` saying what to do — rather than
  raising in the view (#340). The caller monitors what comes back.
  """
  @spec renderer(t(), module(), atom(), keyword()) :: t()
  def renderer(%__MODULE__{renderer: pid} = run, _module, _backend, _opts) when is_pid(pid),
    do: run

  def renderer(%__MODULE__{} = run, module, backend, opts) do
    case Examples.Renderer.start(module, backend, opts) do
      {:ok, pid} ->
        %{run | renderer: pid, monitor: Process.monitor(pid)}

      {:error, message} when is_binary(message) ->
        %{run | running: false, error: message}

      {:error, reason} ->
        %{run | running: false, error: inspect(reason)}
    end
  end

  @doc """
  A frame asked of the run's renderer: its id, which the answer carries back, and the
  clock the render time is read from. A run with no renderer, or one already rendering,
  is unchanged and nothing is asked.
  """
  @spec asking(t(), keyword(), non_neg_integer()) :: {t(), term() | nil}
  def asking(%__MODULE__{renderer: pid, render_id: nil} = run, opts, columns) when is_pid(pid) do
    id = (run.sent_seq || 0) + run.dropped + run.skipped + System.unique_integer([:positive])
    Examples.Renderer.frame(pid, id, opts, columns)
    {%{run | render_id: id, render_started: System.monotonic_time(:microsecond)}, id}
  end

  def asking(%__MODULE__{} = run, _opts, _columns), do: {run, nil}

  @no_supervisor "the task supervisor is not running — the server was started before Examples.TaskSupervisor joined its supervision tree; restart the server (a recompile does not rebuild the tree)"

  @doc """
  Whether `Examples.TaskSupervisor` is running: `:ok`, or `{:error, message}` saying
  what to do — a server started before the supervisor joined the application's tree has
  the new code and the old tree, and every task start would raise (#340).
  """
  @spec supervisor() :: :ok | {:error, String.t()}
  def supervisor do
    if Process.whereis(Examples.TaskSupervisor), do: :ok, else: {:error, @no_supervisor}
  end

  @doc """
  A renderer's answer: `{:ok, run}` for the render in flight, or `:stale` for one that
  was superseded — a frame asked before a Stop, a backend change or a new run.
  """
  @spec result(t(), term()) :: {:ok, t()} | :stale
  def result(%__MODULE__{render_id: id} = run, id) when id != nil do
    {:ok, %{run | render_id: nil}}
  end

  def result(%__MODULE__{}, _id), do: :stale

  @doc "The renderer died: the run stops and says why; a stale DOWN is `:stale`."
  @spec down(t(), reference(), term()) :: {:ok, t()} | :stale
  def down(%__MODULE__{monitor: monitor} = run, monitor, reason) when monitor != nil do
    {:ok,
     %{run | renderer: nil, monitor: nil, render_id: nil, running: false, error: inspect(reason)}}
  end

  def down(%__MODULE__{}, _ref, _reason), do: :stale

  @doc """
  A frame sent at `now_ms`: its render time (from the render's start, or zero for a frame
  that needed none), its payload, and the rolling metrics — the FPS over the last sixty
  frames and the lag as a moving average of `in flight × period` (#308).
  """
  @spec rendered(t(), non_neg_integer(), integer()) :: t()
  def rendered(%__MODULE__{} = run, bytes, now_ms) do
    render_time =
      if run.render_started, do: System.monotonic_time(:microsecond) - run.render_started, else: 0

    frame_times = Enum.take([now_ms | run.frame_times], 60)
    render_times = Enum.take([render_time | run.render_times], 60)

    %{
      run
      | frame: run.frame + 1,
        frame_times: frame_times,
        render_times: render_times,
        render_started: nil,
        payload_size: bytes,
        fps: fps(frame_times),
        lag: lag(run)
    }
  end

  @doc """
  The hook's ack (spec/10 §9.2): the last frame it drew and how many since its last ack.

  A design of several frames has a canvas each and each acks the frame it drew (#432), so
  an ack for a sequence already acknowledged is another plot of a frame already counted:
  it says the client is alive and nothing more. The first ack of a sequence is the frame's.

  An ack at or below the sequence floor is a hook of the backend the run switched from
  (#502, D-128): it is ignored outright, neither a frame drawn nor a sign of life.
  """
  @spec acked(t(), integer(), non_neg_integer(), integer()) :: t()
  def acked(%__MODULE__{seq_floor: floor} = run, seq, _drawn, _now_ms) when seq <= floor,
    do: run

  def acked(%__MODULE__{acked_seq: acked} = run, seq, _drawn, now_ms) when seq <= acked do
    %{run | last_ack_at: now_ms, acking: :yes}
  end

  def acked(%__MODULE__{} = run, seq, drawn, now_ms) do
    acks = Enum.take([{now_ms, drawn} | run.acks], @history)

    %{
      run
      | acked_seq: max(run.acked_seq, seq),
        acks: acks,
        client_fps: rate_over(acks, now_ms),
        last_ack_at: now_ms,
        acking: :yes
    }
  end

  @doc "The mean render time of the last sixty frames, in microseconds."
  @spec avg_render_us(t()) :: float()
  def avg_render_us(%__MODULE__{render_times: []}), do: 0.0
  def avg_render_us(%__MODULE__{render_times: times}), do: Enum.sum(times) / length(times)

  # Events per second over the last second of `{at, count}` entries, newest first.
  defp rate_over(entries, now) do
    recent = Enum.take_while(entries, fn {at, _} -> now - at <= 1000 end)

    case recent do
      [] ->
        0.0

      [_] ->
        0.0

      _ ->
        {oldest, _} = List.last(recent)
        span = now - oldest
        if span > 0, do: Enum.sum(for {_, n} <- recent, do: n) * 1000 / span, else: 0.0
    end
  end

  defp fps([]), do: 0.0
  defp fps([_]), do: 0.0

  defp fps(times) do
    duration_ms = hd(times) - List.last(times)
    if duration_ms > 0, do: (length(times) - 1) / (duration_ms / 1000), else: 0.0
  end

  # Held at an unlimited target, where a period has no meaning.
  defp lag(%{target_fps: fps} = run) when fps > @max_fps, do: run.lag

  defp lag(%{target_fps: fps, lag: lag} = run),
    do: lag + @lag_alpha * (in_flight(run) * 1000 / fps - lag)
end
