defmodule Examples.LoadGaugeTest do
  @moduledoc """
  The load gauge's needles travel to their readings (#417): a dial whose reading changes
  three seconds of machine time at a step is a dial only if the pointer sweeps.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.LoadGauge
  alias Examples.Frames

  # The loads the gauge's rows carry at a tick, in the order the needles are drawn.
  defp loads(tick) do
    {_design, %{reading: rows}} = LoadGauge.design(animation_tick: tick)
    Enum.map(rows, & &1.load)
  end

  # The one mark that eases, and what it shows each row's load at.
  defp shown(%{compiled: compiled}) do
    [{_index, rows}] = Map.to_list(compiled.moving)

    rows
    |> Enum.filter(&match?({{_position, :load}, _state}, &1))
    |> Enum.sort_by(fn {{position, _field}, _state} -> position end)
    |> Enum.map(fn {_key, state} -> state.shown end)
  end

  test "a run keeps a compiled chart on SVG, the easing having nowhere else to live" do
    assert %{compiled: _} = Frames.prepare(LoadGauge, [], :svg)
  end

  test "each needle is half-way at half the duration and arrives at the end" do
    state = Frames.prepare(LoadGauge, [], :svg)
    {_frame, state} = Frames.frame(LoadGauge, [animation_tick: 0, at: 0], :svg, state)
    assert shown(state) == loads(0)

    # The reading changes: the needle stays where it is and is retargeted.
    {_frame, state} = Frames.frame(LoadGauge, [animation_tick: 1, at: 0], :svg, state)
    assert shown(state) == loads(0)
    refute loads(1) == loads(0)

    # `sin_in_out` is exactly half-way through its travel at half its duration.
    {_frame, mid} = Frames.frame(LoadGauge, [animation_tick: 1, at: 225], :svg, state)

    for {half, {from, to}} <- Enum.zip(shown(mid), Enum.zip(loads(0), loads(1))) do
      assert_in_delta half, (from + to) / 2, 1.0e-9
    end

    {_frame, done} = Frames.frame(LoadGauge, [animation_tick: 1, at: 450], :svg, state)
    assert shown(done) == loads(1)
  end

  test "the needle is drawn where it has travelled to, not where its row reads" do
    state = Frames.prepare(LoadGauge, [], :svg)
    {_frame, state} = Frames.frame(LoadGauge, [animation_tick: 0, at: 0], :svg, state)
    {_frame, state} = Frames.frame(LoadGauge, [animation_tick: 1, at: 0], :svg, state)
    {mid, _state} = Frames.frame(LoadGauge, [animation_tick: 1, at: 225], :svg, state)
    {done, _state} = Frames.frame(LoadGauge, [animation_tick: 1, at: 450], :svg, state)

    refute mid.svg == done.svg
  end
end
