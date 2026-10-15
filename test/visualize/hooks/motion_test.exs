defmodule Visualize.Hooks.MotionTest do
  @moduledoc """
  A style's transition on a canvas, executed under node (spec/10 §4.5, spec/14 §3.10, #653,
  D-176): `CanvasChart` and `CanvasBinaryChart` replay a stream whose rows changed style,
  moving each identity's fill through OKLab and its stroke width numerically in their
  frame loop until they reach the target, then requesting no more frames; reduced motion
  shows the target at once, and a stream without a span is drawn once.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1, after_mark: 2]

  alias Visualize.Backend.CanvasBinary
  alias Visualize.Chart

  @moduletag :js

  # Two named points; a point's state names the style it is drawn in, and `error` moves.
  defp design(error) do
    %{
      version: 3,
      sources: %{s: %{fields: [:x, :y, :name, :state]}},
      styles: %{error: error},
      frames: %{
        main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}
      },
      marks: [
        %{
          type: :symbol,
          data: :s,
          channels: %{x: :x, y: :y, series: :name},
          style: [%{fill: "#3b6fa8", stroke: %{color: "#000000", width: 1}}, {:field, :state}]
        }
      ]
    }
  end

  @fades %{fill: "#c23238", transition: %{fill: %{duration: 400, easing: :linear}}}
  @widens %{stroke: %{width: 5}, transition: %{stroke: %{duration: 160, easing: :linear}}}

  defp rows(state),
    do: [%{x: 1, y: 2, name: "a", state: "ok"}, %{x: 2, y: 3, name: "b", state: state}]

  defp applied(design, state) do
    {:ok, applied} = Chart.apply(Chart.from_map!(design), sources: %{s: rows(state)})
    applied
  end

  defp json(design, state),
    do: Chart.render(applied(design, state), backend: :canvas, format: :json)

  defp encode(:json, design, state), do: json(design, state)
  defp encode(:binary, design, state), do: binary(design, state)

  defp binary(design, state) do
    applied(design, state)
    |> Chart.generate(resolve: :literal)
    |> CanvasBinary.encode_element!()
    |> CanvasBinary.to_base64()
  end

  # A scenario that mounts `hook` over the first value, updates it to the second, and lets
  # the clock run; each draw's time is reported.
  defp scenario(hook, key, first, second, opts \\ []) do
    reduced = Keyword.get(opts, :reduced, false)

    """
    window.matchMedia = (q) => ({ matches: #{reduced} && q === '(prefers-reduced-motion: reduce)' });
    const el = Stub.element({#{key}: #{Jason.encode!(first)}}, 600, 400);
    const hook = Stub.mount(#{hook}, el);
    const times = [];
    const draw = hook.draw.bind(hook);
    hook.draw = () => { times.push(performance.now()); draw(); };
    Stub.advance(1000);
    Stub.mark('update');
    el.dataset.#{key} = #{Jason.encode!(second)};
    hook.updated();
    Stub.advance(1000);
    Stub.done({times});
    """
  end

  # The value a property had at each draw call `op`, in order.
  defp at_draws(entries, prop, op) do
    {values, _} =
      Enum.reduce(entries, {[], nil}, fn
        %{"kind" => "set", "name" => ^prop, "value" => v}, {acc, _} -> {acc, v}
        %{"kind" => "call", "name" => ^op}, {acc, v} -> {[v | acc], v}
        _entry, state -> state
      end)

    Enum.reverse(values)
  end

  defp oklab_mix(a, b, t) do
    [p, q] = for c <- [a, b], do: Visualize.Color.to_oklab(Visualize.Color.parse(c))
    lerp = fn k -> Map.fetch!(p, k) + (Map.fetch!(q, k) - Map.fetch!(p, k)) * t end
    %{r: r, g: g, b: bl} = Visualize.Color.oklab(lerp.(:l), lerp.(:a), lerp.(:b))
    Enum.map([r, g, bl], &round/1)
  end

  # A colour a context was given, as its three channels: `#rrggbb` or `rgba()`.
  defp channels(colour) do
    %{r: r, g: g, b: b} = Visualize.Color.parse(colour)
    Enum.map([r, g, b], &round/1)
  end

  # The second point's fills after the update, one per draw, with each draw's time.
  defp moving_fills(log, times) do
    fills = log |> after_mark("update") |> at_draws("fillStyle", "fill")
    # Two points per draw: the moving one is the second.
    seconds = fills |> Enum.chunk_every(2) |> Enum.map(&List.last/1)
    Enum.zip(Enum.drop(times, length(times) - length(seconds)), seconds)
  end

  for {hook, key, encode} <- [
        {"CanvasChart", "commands", :json},
        {"CanvasBinaryChart", "binary", :binary}
      ] do
    @hook hook
    @key key
    @encode encode

    test "#{hook} moves a fill through OKLab to its target, then stops" do
      d = design(@fades)
      [first, second] = for state <- ["ok", "error"], do: encode(@encode, d, state)

      assert {:ok, %{"log" => log, "report" => %{"times" => times}}} =
               run(scenario(@hook, @key, first, second))

      # Where the point was: its series' colour, before its row chose `error`.
      was = log |> at_draws("fillStyle", "fill") |> Enum.at(1)
      [{start, shown_at_start} | rest] = moving_fills(log, times)
      # The first draw after the update shows where the point was.
      assert channels(shown_at_start) == channels(was)

      # Every frame in between is the OKLab mix at its time, within a unit per channel.
      for {time, value} <- Enum.drop(rest, -1) do
        t = (time - start) / 400
        expected = oklab_mix(was, "#c23238", t)
        assert Enum.zip(channels(value), expected) |> Enum.all?(fn {a, b} -> abs(a - b) <= 1 end)
      end

      # It ends at the target, at 400 ms, and no frame is asked for after.
      {last_time, last} = List.last(rest)
      assert channels(last) == channels("#c23238")
      assert last_time - start >= 400 and last_time - start < 416
      assert length(rest) == 25
    end

    test "#{hook} shows the target at once to a reader who prefers reduced motion" do
      d = design(@fades)
      [first, second] = for state <- ["ok", "error"], do: encode(@encode, d, state)

      assert {:ok, %{"log" => log, "report" => %{"times" => times}}} =
               run(scenario(@hook, @key, first, second, reduced: true))

      assert [{_t, shown}] = moving_fills(log, times)
      assert channels(shown) == channels("#c23238")
    end
  end

  test "a stroke's width moves numerically along its curve" do
    d = design(@widens)
    [first, second] = for state <- ["ok", "error"], do: json(d, state)

    assert {:ok, %{"log" => log}} = run(scenario("CanvasChart", "commands", first, second))

    widths =
      log
      |> after_mark("update")
      |> at_draws("lineWidth", "stroke")
      |> Enum.chunk_every(2)
      |> Enum.map(&List.last/1)

    assert hd(widths) == 1
    assert List.last(widths) == 5
    assert widths == Enum.sort(widths)
    assert Enum.any?(widths, &(&1 > 1 and &1 < 5))
  end

  test "a stream without a span is drawn once per value and asks for no frame" do
    d = design(%{fill: "#c23238"})
    [first, second] = for state <- ["ok", "error"], do: json(d, state)
    refute first =~ "motion"

    assert {:ok, %{"report" => %{"times" => times}}} =
             run(scenario("CanvasChart", "commands", first, second))

    assert length(times) == 1
  end
end
