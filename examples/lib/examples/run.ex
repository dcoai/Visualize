defmodule Examples.Run do
  @moduledoc """
  The frame loop every page that streams frames drives (spec/14 §12.6, #322): a struct of
  a run's state and pure functions over it, the clock passed in.

  A run ticks by deadline (`schedule/2`), accounts the samples due since the last tick as
  whole columns of the page's density (`tick/3`), decides what a frame goes as — strips,
  the empty `"none"` update, a full render, or held back by flow control (`decide/5`) —
  numbers every frame it sends (`sending/1`), renders it in a task under
  `Examples.TaskSupervisor`, one in flight, and measures the result (`rendering/2`,
  `result/2`, `rendered/3`); the hook's acks (`acked/4`) bound the frames in flight to a
  lag budget with a hold that fails open (`hold/2`); `stop/1` terminates a render in
  flight at once. A page owns the run in one assign and reads its metrics from it.
  """

  alias Visualize.Backend.CanvasIncremental

  @max_lag_ms 250
  @ack_timeout 2000
  @lag_alpha 2 / 31
  @history 120

  @type mode :: :scroll_x | :none | :full_redraw | :drop

  @type t :: %__MODULE__{}

  defstruct running: false,
            target_fps: 60,
            data_rate: 0,
            flow_control: true,
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
            acks: [],
            client_fps: 0.0,
            dropped: 0,
            hold_since: nil,
            last_ack_at: nil,
            acking: :unknown,
            stalls: 0,
            ack_age: nil,
            # the render in flight
            task: nil,
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
      running: true,
      last_tick: now_ms,
      next_due: now_us,
      needs_full: true
    )
  end

  @doc "The run stopped: a render in flight terminated and its messages flushed."
  @spec stop(t()) :: t()
  def stop(%__MODULE__{} = run), do: %{cancel(run) | running: false}

  @doc "The run with a render in flight terminated; nothing else changes."
  @spec cancel(t()) :: t()
  def cancel(%__MODULE__{task: %Task{ref: ref, pid: pid}} = run) do
    Process.demonitor(ref, [:flush])
    Task.Supervisor.terminate_child(Examples.TaskSupervisor, pid)
    %{run | task: nil}
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
    {next, delay} = if fps > 2000, do: {now_us, 0}, else: deadline(due, now_us, fps)
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

    if run.task do
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
  @spec decide(t(), non_neg_integer(), boolean(), {number(), number()}, integer()) :: {t(), mode()}
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
  def window(%__MODULE__{target_fps: fps}), do: max(2, ceil(@max_lag_ms * min(fps, 2000) / 1000))

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

  @doc "A frame rendering in a task (#323): `fun` runs under `Examples.TaskSupervisor`, unlinked."
  @spec rendering(t(), (-> term())) :: t()
  def rendering(%__MODULE__{task: nil} = run, fun) do
    task = Task.Supervisor.async_nolink(Examples.TaskSupervisor, fun)
    %{run | task: task, render_started: System.monotonic_time(:microsecond)}
  end

  @doc """
  A task's message: `{:ok, run}` for the render in flight, its monitor flushed, or
  `:stale` for one that was cancelled — nothing to do with it.
  """
  @spec result(t(), reference()) :: {:ok, t()} | :stale
  def result(%__MODULE__{task: %Task{ref: ref}} = run, ref) do
    Process.demonitor(ref, [:flush])
    {:ok, %{run | task: nil}}
  end

  def result(%__MODULE__{}, ref) do
    Process.demonitor(ref, [:flush])
    :stale
  end

  @doc "The render in flight died: the run stops and says why; a stale DOWN is `:stale`."
  @spec down(t(), reference(), term()) :: {:ok, t()} | :stale
  def down(%__MODULE__{task: %Task{ref: ref}} = run, ref, reason) do
    {:ok, %{run | task: nil, running: false, error: inspect(reason)}}
  end

  def down(%__MODULE__{}, _ref, _reason), do: :stale

  @doc """
  A frame sent at `now_ms`: its render time (from the task's start, or zero for a frame
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

  @doc "The hook's ack (spec/10 §9.2): the last frame it drew and how many since its last ack."
  @spec acked(t(), integer(), non_neg_integer(), integer()) :: t()
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
  defp lag(%{target_fps: fps} = run) when fps > 2000, do: run.lag
  defp lag(%{target_fps: fps, lag: lag} = run), do: lag + @lag_alpha * (in_flight(run) * 1000 / fps - lag)
end
