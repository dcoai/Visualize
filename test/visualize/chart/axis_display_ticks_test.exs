defmodule Visualize.Chart.AxisDisplayTicksTest do
  @moduledoc """
  An axis shown in another unit than its data's picks its ticks in that unit (spec/05
  §4.3, spec/14 §4.4, #594, D-156): round numbers in the display unit, placed at their
  values converted back into the data's unit and labelled with the round numbers; and
  the unit system that chooses the display unit is a render option, carried from
  `apply/2`, `compile/2` and the board's render paths to every axis.
  """
  use ExUnit.Case, async: true

  @moduletag :capture_log

  @patience 10_000

  alias Visualize.Board
  alias Visualize.Board.{Binding, Export, Server, Snapshot, View}
  alias Visualize.Chart
  alias Visualize.Chart.{Compiled, Frame}
  alias Visualize.Chart.Frame.Furniture
  alias Visualize.Data.Schema
  alias Visualize.{Quantity, Scale}
  alias Visualize.Test.Feeds
  alias Visualize.Unit

  defp design(axis, opts) do
    %{
      version: 2,
      sources: %{primary: %{fields: [:n, :v]}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{
            x: %{kind: :linear, domain: [0, 10]},
            y: %{kind: Keyword.get(opts, :kind, :linear), domain: Keyword.get(opts, :domain)}
          },
          axes: [Map.merge(%{scale: :y, side: :left}, axis)]
        }
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :n, y: :v}}]
    }
  end

  @rows [%{n: 0, v: 1}, %{n: 10, v: 30}]

  defp mass(axis \\ %{}, opts \\ []),
    do: design(Map.merge(%{measure: %{unit: "kg"}, ticks: 5}, axis), [domain: [0, 40]] ++ opts)

  defp duration(axis \\ %{}),
    do: design(Map.merge(%{measure: %{unit: "s"}, ticks: 10}, axis), domain: [0, 100])

  defp frame(design, opts \\ []) do
    {:ok, chart} = Chart.from_map(design)
    Frame.new(chart, [sources: %{primary: @rows}, size: {400, 300}] ++ opts)
  end

  # The axis a frame draws for its only axis node.
  defp axis(frame), do: Furniture.axis(frame, hd(frame.axes))

  defp labels(axis), do: Enum.map(axis.tick_values, axis.tick_format)

  defp tick_labels(svg) do
    Regex.scan(~r/<text dy="0.32em"[^>]*>([^<]*)<\/text>/, svg) |> Enum.map(&Enum.at(&1, 1))
  end

  defp titles(svg) do
    Regex.scan(~r/<text class="label"[^>]*>([^<]*)<\/text>/, svg) |> Enum.map(&Enum.at(&1, 1))
  end

  describe "Quantity.ticks/3" do
    test "0–40 kg under :us ticks at round pounds, placed in kilograms" do
      scale = Scale.linear() |> Scale.domain([0, 40])
      ticks = Quantity.ticks(scale, %{unit: "kg"}, count: 5, system: :us)

      assert ticks == Enum.map([0, 20, 40, 60, 80], &Unit.convert(&1, "[lb_av]", "kg"))

      format = Quantity.formatter(scale, %{unit: "kg"}, count: 5, system: :us)
      assert Enum.map(ticks, format) == ["0 lb", "20 lb", "40 lb", "60 lb", "80 lb"]
    end

    test "0–100 s shown in minutes ticks at round minutes" do
      scale = Scale.linear() |> Scale.domain([0, 100])
      ticks = Quantity.ticks(scale, %{unit: "s"}, count: 10)

      assert ticks == [0.0, 12.0, 24.0, 36.0, 48.0, 60.0, 72.0, 84.0, 96.0]

      assert Enum.map(ticks, Quantity.formatter(scale, %{unit: "s"}, count: 10)) ==
               ~w(0 0.2 0.4 0.6 0.8 1 1.2 1.4 1.6) |> Enum.map(&(&1 <> " min"))
    end

    test "a label is the round number itself, never the round trip's last bit" do
      # 20 lb to kg and back is 19.999999999999996 lb; the label is the 20 it came from.
      assert Unit.convert(Unit.convert(20, "[lb_av]", "kg"), "kg", "[lb_av]") != 20.0

      scale = Scale.linear() |> Scale.domain([0, 40])
      format = Quantity.formatter(scale, %{unit: "kg"}, count: 5, system: :us)

      for {placed, round} <-
            Enum.zip(Quantity.ticks(scale, %{unit: "kg"}, count: 5, system: :us), [
              0,
              20,
              40,
              60,
              80
            ]) do
        assert format.(placed) == "#{round} lb"
      end
    end

    test "nil where the axis keeps the scale's own ticks" do
      linear = Scale.linear() |> Scale.domain([0, 900])
      assert Quantity.ticks(linear, %{unit: "ms"}) == nil
      assert Quantity.ticks(linear, %{quantity: :count}) == nil
      assert Quantity.ticks(linear, %{}) == nil
      assert Quantity.ticks(linear, %{unit: "{iso4217:USD}"}, system: :us) == nil

      log = Scale.log() |> Scale.domain([1, 100_000])
      assert Quantity.ticks(log, %{unit: "ms"}) == nil

      assert Quantity.ticks(Scale.band() |> Scale.domain([:a, :b]), %{unit: "ms"}) == nil
    end

    test "a measure resolve/1 refuses raises" do
      assert_raise ArgumentError, fn ->
        Quantity.ticks(Scale.linear() |> Scale.domain([0, 1]), %{unit: "By", quantity: :duration})
      end
    end
  end

  describe "the axis (spec/14 §4.4)" do
    test "a mass axis under system: :us ticks at round pounds placed exactly where the kilograms are" do
      frame = frame(mass(), system: :us)
      axis = axis(frame)
      y = Frame.scale(frame, :y)

      assert labels(axis) == ["0 lb", "20 lb", "40 lb", "60 lb", "80 lb"]

      for {value, round} <- Enum.zip(axis.tick_values, [0, 20, 40, 60, 80]) do
        assert value == Unit.convert(round, "[lb_av]", "kg")
        assert Visualize.Axis.tick_position(axis, value) == Scale.apply(y, value)
      end
    end

    test "a duration axis auto-scaled into minutes ticks at round minutes" do
      axis = axis(frame(duration()))
      assert axis.tick_values == [0.0, 12.0, 24.0, 36.0, 48.0, 60.0, 72.0, 84.0, 96.0]
      assert hd(labels(axis)) == "0 min" and List.last(labels(axis)) == "1.6 min"

      svg = Frame.render(frame(duration()))
      assert tick_labels(svg) == ~w(0 0.2 0.4 0.6 0.8 1 1.2 1.4 1.6) |> Enum.map(&(&1 <> " min"))
    end

    test "the grid draws at the same round values" do
      svg = Frame.render(frame(duration(%{grid: true})))
      [_, grid] = Regex.run(~r/<g[^>]*class="grid"[^>]*>(.*?)<\/g>/s, svg)
      assert length(Regex.scan(~r/<line /, grid)) == 9
    end

    test "explicit tick values win, labelled in the display unit" do
      axis = axis(frame(mass(%{ticks: [0, 10, 20]}), system: :us))
      assert axis.tick_values == [0, 10, 20]
      assert labels(axis) == ["0 lb", "22.046226 lb", "44.092452 lb"]
    end

    test "an explicit count only sets the count" do
      axis = axis(frame(mass(%{ticks: %{count: 2}}), system: :us))
      assert labels(axis) == ["0 lb", "50 lb"]
    end

    test "an explicit format keeps the scale's own ticks in the data's unit" do
      axis = axis(frame(mass(%{format: ",d"}), system: :us))
      assert axis.tick_values == nil
      assert Enum.map(Scale.ticks(axis.scale, 5), axis.tick_format) == ~w(0 10 20 30 40)
    end

    test "a log axis keeps its powers of ten, each in its own unit" do
      design = design(%{measure: %{unit: "ms"}}, kind: :log, domain: [1, 100_000])
      axis = axis(frame(design))
      assert axis.tick_values == nil
    end

    test "a display unit equal to the data's leaves the axis as it was" do
      design = design(%{measure: %{unit: "kg"}, ticks: 5}, domain: [0, 40])
      assert axis(frame(design)).tick_values == nil
      assert Frame.render(frame(design)) == Frame.render(frame(design, system: :as_posted))
    end

    test "the title decision reads the same system" do
      # `[degF]` has a symbol under :us, so the ticks carry it and no title is drawn.
      design = design(%{measure: %{unit: "Cel"}, ticks: 5}, domain: [0, 40])
      svg = Frame.render(frame(design, system: :us))
      assert titles(svg) == []
      assert Enum.all?(tick_labels(svg), &String.ends_with?(&1, " °F"))
    end

    test "a system that is not one of the four is refused when the frame is realised" do
      assert_raise ArgumentError, ~r/system: must be one of/, fn ->
        frame(mass(), system: :imperial)
      end
    end
  end

  describe "system: is a render option (spec/14 §4.4)" do
    test "apply/2 carries it to the frame and the rendered axis" do
      {:ok, applied} = Chart.apply(mass(), sources: %{primary: @rows}, system: :us)
      assert applied.frame.system == :us
      assert tick_labels(Chart.render(applied)) == ["0 lb", "20 lb", "40 lb", "60 lb", "80 lb"]

      {:ok, plain} = Chart.apply(mass(), sources: %{primary: @rows})
      assert plain.frame.system == :as_posted
      assert tick_labels(Chart.render(plain)) == ["0 kg", "10 kg", "20 kg", "30 kg", "40 kg"]
    end

    test "compile/2 keeps it for every realisation per tick" do
      {:ok, %{main: compiled}} = Chart.compile(mass(), sources: %{primary: @rows}, system: :us)
      assert compiled.system == :us

      {group, _compiled} = Compiled.step(compiled, %{primary: @rows})
      svg = Visualize.Render.to_string(group)
      assert tick_labels(svg) == ["0 lb", "20 lb", "40 lb", "60 lb", "80 lb"]
    end

    test "the text alternative writes values in the same system" do
      {:ok, applied} = Chart.apply(mass(), sources: %{primary: @rows}, system: :us)

      assert Visualize.Chart.Summary.formatter(applied.frame, :y).(
               Unit.convert(20, "[lb_av]", "kg")
             ) =~ " lb"
    end
  end

  describe "a board passes system: through (spec/15 §6, §8.3, §12)" do
    @t0 ~U[2026-10-11 12:00:00Z]
    @schema Schema.new!(%{t: %{type: :time}, v: %{type: :number}})

    @cell_design %{
      version: 2,
      sources: %{primary: %{fields: [:t, :v]}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{x: %{kind: :time}, y: %{kind: :linear, domain: [0, 40]}},
          axes: [
            %{scale: :x, side: :bottom},
            %{scale: :y, side: :left, ticks: 5, measure: %{unit: "kg"}}
          ]
        }
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
    }

    @store %{{:composite, 1} => @cell_design}

    defp board,
      do: Board.from_map!(%{cells: %{a: %{x: 0, y: 0, w: 12, h: 3, ref: {:composite, 1}}}})

    defp board_rows, do: for(i <- 0..9, do: %{t: DateTime.add(@t0, i * 60), v: i * 4})

    defp pools, do: %{a: %{primary: board_rows()}}

    test "realise/4 applies every cell in it" do
      {:ok, applied, _cache} = Board.realise(board(), @store, pools(), system: :us)
      assert applied.a.frame.system == :us
    end

    test "a snapshot is drawn in the reader's system, and an export with it" do
      {:ok, snapshot} = Snapshot.realise(board(), @store, pools(), now: DateTime.add(@t0, 600))

      assert %{a: %View{svg: kg}} = Snapshot.views(snapshot)
      assert %{a: %View{svg: lb}} = Snapshot.views(snapshot, system: :us)
      assert kg =~ ">40 kg<" and not (kg =~ " lb<")
      assert lb =~ ">80 lb<"

      assert Export.svg(snapshot, system: :us) =~ ">80 lb<"
    end

    test "a board server draws its cells in its system" do
      {feed, agent} = Feeds.scripted(schema: @schema, rows: board_rows())
      Process.unlink(agent)
      on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)

      sup = start_supervised!(Supervisor.child_spec(Visualize.Board.Supervisor, id: make_ref()))

      {:ok, server} =
        Server.start(sup,
          board: board(),
          store: @store,
          feeds: %{f: feed},
          binding: Binding.new(%{{:a, :primary} => :f}),
          tick: nil,
          clock: fn -> DateTime.add(@t0, 600) end,
          system: :us
        )

      {:ok, _info} = Server.subscribe(server)
      assert live_view(:a).svg =~ ">80 lb<"
    end
  end

  defp live_view(cell) do
    receive do
      {:visualize_board, _board, {:cell, ^cell, %View{state: :live} = view}} -> view
      {:visualize_board, _board, _other} -> live_view(cell)
    after
      @patience -> flunk("no live view of #{inspect(cell)} within #{@patience} ms")
    end
  end
end
