defmodule Visualize.Chart.Compiled.Transition do
  @moduledoc false
  # A moving scale's shown domain easing toward its inferred one between the ticks of a
  # compiled chart (spec/14 §12.5, #360). The state per scale: where the easing started
  # (`from`), where it goes (`target`), when it started (`since`), where it is (`shown`),
  # and a pending shrink's first sighting — the hysteresis `shrink_after` waits on.

  alias Visualize.Chart
  alias Visualize.Chart.Compiled.Regions
  alias Visualize.Chart.{Frame, Schema}
  alias Visualize.{Ease, Scale}

  @numeric [:linear, :log, :power, :sqrt, :symlog, :radial]

  @typedoc "One scale's easing state."
  @type state :: %{
          from: [number()],
          target: [number()],
          since: integer(),
          shown: [number()],
          pending: integer() | nil
        }

  @doc false
  # The scales a compiled chart eases: those with a `transition` node, a moving domain and
  # a numeric kind, as `%{name => transition node}`.
  @spec scales(Chart.t(), atom() | nil) :: %{atom() => map()}
  def scales(%Chart{} = chart, viewport) do
    node = chart.frames |> Map.values() |> hd()
    for {name, scale} <- Map.get(node, :scales, %{}),
        transition = Map.get(scale, :transition),
        is_map(transition),
        Map.fetch!(scale, :kind) in @numeric,
        Regions.moving?(chart, name, viewport),
        into: %{},
        do: {name, transition}
  end

  @doc false
  # The frame drawn at every eased scale's shown domain, and the states after this tick
  # at `at` milliseconds: a scale seen for the first time shows its inferred domain; one
  # whose inferred extent changed is retargeted — at once for a grow, after `shrink_after`
  # of every extent staying inside the target for a shrink — and eases from where it is.
  @spec apply(Frame.t(), %{atom() => map()}, %{atom() => state()}, integer()) ::
          {Frame.t(), %{atom() => state()}}
  def apply(frame, transitions, states, at) do
    Enum.reduce(transitions, {frame, states}, fn {name, node}, {frame, states} ->
      scale = Frame.scale(frame, name)
      state = step(Map.get(states, name), Enum.map(scale.domain, &(&1 * 1.0)), node, at)

      frame =
        if state.shown == scale.domain,
          do: frame,
          else: Frame.put_scale(frame, name, Scale.domain(scale, state.shown))

      {frame, Map.put(states, name, state)}
    end)
  end

  defp step(nil, inferred, _node, at) do
    %{from: inferred, target: inferred, since: at, shown: inferred, pending: nil}
  end

  defp step(state, inferred, node, at) do
    shown = position(state, node, at)
    shrink_after = Map.get(node, :shrink_after, Schema.default(:transition, :shrink_after))

    cond do
      inferred == state.target ->
        %{state | shown: shown, pending: nil}

      not inside?(inferred, state.target) or shrink_after <= 0 ->
        retarget(state, shown, inferred, at)

      state.pending == nil ->
        %{state | shown: shown, pending: at}

      at - state.pending >= shrink_after ->
        retarget(state, shown, inferred, at)

      true ->
        %{state | shown: shown}
    end
  end

  defp retarget(state, shown, target, at),
    do: %{state | from: shown, target: target, since: at, shown: shown, pending: nil}

  # Where the easing stands at `at`: `from` toward `target` along the curve, done when
  # the duration has passed or is nothing.
  defp position(%{from: from, target: target, since: since}, node, at) do
    duration = Map.get(node, :duration, Schema.default(:transition, :duration))
    easing = Map.get(node, :easing, Schema.default(:transition, :easing))
    t = if duration <= 0, do: 1.0, else: min(1.0, max(0.0, (at - since) / duration))
    e = Kernel.apply(Ease, easing, [t])
    Enum.zip_with(from, target, fn a, b -> a + (b - a) * e end)
  end

  defp inside?([lo, hi], [tlo, thi]), do: lo >= tlo and hi <= thi
  defp inside?(_extent, _target), do: false
end
