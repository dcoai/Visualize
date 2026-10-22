defmodule Visualize.Chart.TickFaultsTest do
  @moduledoc """
  Bad data is a fault, not a blank chart or a crash (spec/14 §7.3, §12.5, spec/15 §8.3,
  D-232, #855, #924): tuple rows bound to a slot are named by its declared fields as a
  tensor is, and a source a compiled chart's tick cannot read is a fault the chart carries
  — read by `Visualize.Chart.Compiled.faults/1` — where it used to raise. A board cell fed
  such a delivery keeps its frame and shows `{:invalid, errors}` over it.
  """
  use ExUnit.Case, async: true

  alias Visualize.Board.Cell
  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Validator}
  alias Visualize.Data.{Delivery, Schema}

  defp design(fields \\ [:x, :y], type \\ :line) do
    %{
      version: 2,
      sources: %{pts: %{fields: fields, types: %{x: :number, y: :number}}},
      frames: %{
        main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}
      },
      marks: [%{type: type, data: :pts, channels: %{x: :x, y: :y}}]
    }
  end

  defp tuples, do: [{1, 4.0}, {2, 5.0}, {3, 6.0}]
  defp tensor, do: Nx.tensor([[1, 4.0], [2, 5.0], [3, 6.0]])
  defp lists, do: %{x: [1, 2, 3], y: [4.0, 5.0, 6.0]}

  defp render(source, fields \\ [:x, :y], type \\ :line) do
    {:ok, applied} = Chart.apply(design(fields, type), sources: %{pts: source}, size: {300, 200})
    Chart.render(applied)
  end

  defp compiled(source \\ lists()) do
    {:ok, %{"main" => compiled}} = Chart.compile(design(), sources: %{pts: source})
    compiled
  end

  describe "tuple rows bound to a slot that declares its fields" do
    test "draw exactly what the equivalent tensor draws" do
      svg = render(tuples())
      assert svg =~ "<path"
      assert svg == render(tensor())
      assert svg == render(lists())
    end

    test "draw every point of a :circle mark, as the tensor does" do
      svg = render(tuples(), [:x, :y], :circle)
      assert length(Regex.scan(~r/<circle\b/, svg)) == 3
      assert svg == render(tensor(), [:x, :y], :circle)
    end

    test "are named in the declared order, each row a map" do
      {:ok, applied} = Chart.apply(design([:y, :x]), sources: %{pts: [{1, 4.0}]})
      assert applied.sources["pts"] == [%{"y" => 1, "x" => 4.0}]
    end

    test "carried by a delivery bind as the rows do" do
      {:ok, applied} = Chart.apply(design(), sources: %{pts: Delivery.new(tuples())})
      assert hd(applied.sources["pts"]) == %{"x" => 1, "y" => 4.0}
    end

    test "a row of another width is a width fault at the slot, the first such row's" do
      rows = [{1, 4.0}, {2, 5.0, 9}, {3}]

      assert {:error, [{[:sources, "pts"], {:width, 2, 3}} = fault]} =
               Chart.apply(design(), sources: %{pts: rows})

      assert Validator.format(fault) =~ "a tuple row's elements"
    end

    test "a keyword list of columns is still columns, not tuple rows" do
      assert render(x: [1, 2, 3], y: [4.0, 5.0, 6.0]) == render(lists())
    end
  end

  test "tuple rows under a slot that declares no fields are refused at the slot" do
    d = design() |> put_in([:sources, :pts], %{fields: []}) |> Map.put(:marks, [])

    assert Chart.apply(d, sources: %{pts: tuples()}) ==
             {:error, [{[:sources, "pts"], {:type, :named_rows}}]}
  end

  describe "a compiled chart's tick (spec/14 §12.5)" do
    test "names tuple rows by the slot's fields, as application does" do
      compiled = compiled()
      {lists, _} = Compiled.tick(compiled, %{pts: lists()}, at: 0)
      {tuples, _} = Compiled.tick(compiled, %{pts: tuples()}, at: 0)
      assert tuples == lists
      assert Compiled.faults(compiled) == []
    end

    test "fed a wrong-width tensor mid-run carries the fault, and a good tick clears it" do
      {good, compiled} = Compiled.tick(compiled(), %{pts: lists()}, at: 0)
      assert good.svg =~ "<path"

      # No raise: the fault is the chart's, and the slot draws as an omitted one.
      {bad, compiled} = Compiled.tick(compiled, %{pts: Nx.tensor([[1, 2, 3]])}, at: 1)
      assert Compiled.faults(compiled) == [{[:sources, "pts"], {:width, 2, 3}}]
      refute bad.svg =~ "<path"

      {again, compiled} = Compiled.tick(compiled, %{pts: lists()}, at: 2)
      assert Compiled.faults(compiled) == []
      assert again.svg == good.svg
    end

    test "every faulted slot is reported, by path, and a step carries them too" do
      {_group, stepped} = Compiled.step(compiled(), %{pts: [{1, 2, 3}]}, at: 0)
      assert Compiled.faults(stepped) == [{[:sources, "pts"], {:width, 2, 3}}]

      {_group, stepped} = Compiled.step(stepped, %{pts: tuples()}, at: 1)
      assert Compiled.faults(stepped) == []
    end

    test "render/2 and svg/2, which return no chart, still raise naming the fault" do
      assert_raise ArgumentError, ~r/sources\.pts.*3 columns wide/, fn ->
        Compiled.render(compiled(), %{pts: [{1, 2, 3}]})
      end
    end
  end

  describe "a board cell fed bad rows on a tick (spec/15 §8.3, §8.4)" do
    @schema Schema.new!(%{t: %{type: :time}, v: %{type: :number}})
    @t0 ~U[2026-10-22 09:00:00Z]

    defp timed do
      %{
        version: 2,
        sources: %{pts: %{fields: [:t, :v]}},
        frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :time}, y: %{kind: :linear}}}},
        marks: [%{type: :line, data: :pts, channels: %{x: :t, y: :v}}]
      }
    end

    defp slots(rows),
      do: %{"pts" => %{delivery: Delivery.new(rows), schema: @schema, status: :live}}

    defp rows(n), do: for(i <- 0..n, do: {DateTime.add(@t0, i * 60), i * 1.0})

    defp start_cell(data) do
      {:ok, chart} = Chart.from_map(timed())

      start_supervised!(
        {Cell,
         name: "c",
         board: self(),
         chart: chart,
         vars: %{},
         size: {300, 200},
         theme: Visualize.Theme.default(),
         max_heap: 50_000_000,
         subscribers: [self()],
         data: {:data, data, @t0}}
      )
    end

    defp view do
      assert_receive {:visualize_board, _board, {:cell, "c", view}}
      view
    end

    test "keeps its frame under an invalid banner, keeps running, and recovers" do
      cell = start_cell(slots(rows(3)))
      live = view()
      assert live.state == :live and live.svg =~ "<path"

      # Tuple rows one element too wide, through the placement of a windowed feed.
      wide = for {t, v} <- rows(4), do: {t, v, :extra}
      send(cell, {:data, slots(wide), @t0})
      faulted = view()

      assert {:invalid, [{[:sources, "pts"], {:width, 2, 3}}]} = faulted.state
      assert faulted.svg == live.svg
      assert faulted.drawn == live.drawn
      assert faulted.note =~ "Wrong binding"
      assert Process.alive?(cell)

      send(cell, {:data, slots(rows(5)), @t0})
      recovered = view()
      assert recovered.state == :live
      assert recovered.note == nil
      assert recovered.svg != live.svg
    end

    test "fed bad rows first shows the whole-cell panel, never a crash" do
      cell = start_cell(slots([{@t0}]))
      faulted = view()

      assert {:invalid, [{[:sources, "pts"], {:width, 2, 1}}]} = faulted.state
      assert faulted.svg == nil
      assert faulted.note =~ "Wrong binding"
      assert Process.alive?(cell)
    end
  end
end
