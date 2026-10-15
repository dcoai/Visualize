defmodule Visualize.Specs.ForceSimulation do
  @moduledoc """
  The timer discipline of `Visualize.Layout.Force.Simulation` (spec/06 §8.5), as a model.

  What is abstracted: nodes, links and forces are gone; `alpha` is a three-valued `heat`
  (`0` below `alpha_min`, `1` and `2` above) and `alpha_target` is `target_hot` (at or above
  `alpha_min`, or not). What is kept exactly: every message the GenServer handles, the
  deferred `:start_simulation` that `init/1` enqueues, and the two kinds of tick message —
  a *live* one from the timer the server is waiting on, and a *stale* one from a timer that
  was cancelled after its message had already reached the mailbox.

  Three constants select the intended behaviour (`true`, the default) or the defect the
  code shipped with; the negative tests in `test/specs/` prove the checker finds each:

    * `guarded_deferred_start` — `:start_simulation` does not arm a second timer when a
      `:start` already did.
    * `restart_keeps_stopped` — `:restart` resets alpha but does not start a stopped
      simulation.
    * `tagged_ticks` — a tick carries its timer's reference and a stale tick is ignored,
      so a stop followed by a start cannot leave two tick chains running.

  `env_active` switches the client off, which is how the cooling-down property is stated:
  with no client acting, a target below `alpha_min` leads to a stopped simulation.
  """

  use ExTLA.Spec

  constant(:guarded_deferred_start, default: true)
  constant(:restart_keeps_stopped, default: true)
  constant(:tagged_ticks, default: true)
  constant(:env_active, default: true)
  # Stale ticks still in flight are bounded so the model is finite; two is enough to show
  # every interleaving that matters, since a third could only arise from a third stop.
  constant(:max_stale, default: 2)

  variable(:running, type: [true, false])
  variable(:live, type: 0..2)
  variable(:stale, type: 0..^max_stale)
  variable(:heat, type: 0..2)
  variable(:target_hot, type: [true, false])
  variable(:pending_start, type: [true, false])
  # History: has a :restart ever started a stopped simulation? (Only the defect can set it.)
  variable(:restart_started_stopped, type: [true, false])

  init do
    running = false
    live = 0
    stale = 0
    heat = 2
    target_hot = false
    pending_start = true
    restart_started_stopped = false
  end

  # init/1's deferred :start_simulation message is handled.
  action :deferred_start do
    require pending_start
    pending_start = false
    running = true
    live = if running and ^guarded_deferred_start, do: live, else: live + 1
  end

  # GenServer.cast(sim, :start); the handler already guards on `running`.
  action :start do
    require ^env_active
    require not running
    running = true
    live = live + 1
  end

  # GenServer.cast(sim, :stop). `Process.cancel_timer/1` either removes the timer or finds
  # its message already delivered, in which case the tick is now stale.
  action :stop, params: [cancelled: [true, false]] do
    require ^env_active
    require live > 0 or cancelled
    require cancelled or stale < ^max_stale
    running = false
    live = if live > 0, do: live - 1, else: 0
    stale = if live > 0 and not cancelled, do: stale + 1, else: stale
  end

  # GenServer.cast(sim, :restart): alpha back to 1.0, and (defect) an unconditional start.
  action :restart do
    require ^env_active
    heat = 2
    running = if ^restart_keeps_stopped, do: running, else: true
    live = if ^restart_keeps_stopped or running, do: live, else: live + 1

    restart_started_stopped =
      restart_started_stopped or (not running and not (^restart_keeps_stopped))
  end

  # The timer the server is waiting on fires: one integration step; re-arm while alpha is
  # at or above alpha_min, otherwise stop.
  action :live_tick do
    require live > 0
    require running
    heat = cooled(heat, target_hot)
    running = cooled(heat, target_hot) >= 1
    live = if cooled(heat, target_hot) >= 1, do: live, else: live - 1
  end

  # A stale tick arrives. Tagged: ignored. Untagged (defect): while running it is taken for
  # a live one — a step, and a second timer chain.
  action :stale_tick do
    require stale > 0
    stale = stale - 1
    heat = if ^tagged_ticks or not running, do: heat, else: cooled(heat, target_hot)
    live = if ^tagged_ticks or not running, do: live, else: live + 1
  end

  # GenServer.cast(sim, :tick): a manual step, no timer involved.
  action :manual_tick do
    require ^env_active
    heat = cooled(heat, target_hot)
  end

  action :set_alpha, params: [h: 0..2] do
    require ^env_active
    heat = h
  end

  action :set_alpha_target, params: [t: [true, false]] do
    require ^env_active
    target_hot = t
  end

  # One integration step moves alpha toward alpha_target: below alpha_min eventually when
  # the target is below it, never below it when the target is at or above it.
  def cooled(heat, target_hot) do
    if target_hot, do: max(heat, 1), else: max(heat - 1, 0)
  end

  invariant :running_iff_live_timer, desc: "running exactly when one live timer is armed" do
    running == (live == 1)
  end

  invariant :at_most_one_live_timer do
    live <= 1
  end

  invariant :restart_never_starts,
    desc: "restart resets alpha; a stopped simulation stays stopped" do
    not restart_started_stopped
  end

  temporal :cools_down do
    (not target_hot and not (^env_active)) ~> not running
  end

  fairness(:weak, [:deferred_start, :live_tick, :stale_tick])

  terminal :quiet do
    not running and live == 0 and stale == 0 and not pending_start
  end
end
