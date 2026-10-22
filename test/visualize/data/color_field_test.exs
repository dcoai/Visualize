defmodule Visualize.Data.ColorFieldTest do
  # A field of type `:color` (spec/08 §10.1, #875, #925, D-233): its rows carry color values
  # the theme resolves at render, held to the type by a virtual source's conformance,
  # carried by the codecs, and drawn from a virtual source as from a host source.
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Visualize.Board
  alias Visualize.Board.{Binding, Server, Snapshot, View}
  alias Visualize.Board.Snapshot.Codec, as: SnapshotCodec
  alias Visualize.Chart
  alias Visualize.Data.{Schema, Table}
  alias Visualize.Feed.Conformance
  alias Visualize.Test.Feeds
  alias Visualize.{Theme, VirtualSource}

  # The host's function (spec/08 §10.5.8), as metresis's status strip shapes its blocks: each
  # block's fill the theme's color of its verdict, a rate's that color shaded. A stored
  # function's atoms are their strings (D-195), so a typed color comes from a host's.
  defmodule Host do
    use Visualize.VirtualSources

    defsource status_blocks(inputs) do
      [rows] = Map.values(inputs)

      Enum.map(rows, fn row ->
        fill =
          if row.status == "ok",
            do: {:color, :good},
            else: Visualize.Color.alpha({:color, :good}, 0.74)

        Map.put(row, :fill, fill)
      end)
    end
  end

  @names ~w(raw strip host x0 x1 y0 y1 fill status status_blocks)a
  setup_all do
    {:ok, names: @names}
  end

  @t0 ~U[2026-10-22 12:00:00Z]

  @good {:color, :good}
  @shaded {:alpha, {:color, :good}, 0.74}

  @fields %{
    x0: %{type: :time},
    x1: %{type: :time},
    y0: %{type: :number},
    y1: %{type: :number},
    fill: %{type: :color},
    status: %{type: :text}
  }

  defp source(schema \\ @fields) do
    {:ok, source} =
      VirtualSource.new(%{
        id: :strip,
        from: [{:raw, nil}],
        schema: schema,
        elixir: "fn r -> r end"
      })

    source
  end

  describe "the schema" do
    test "a :color field is valid, takes only label and continuity, and still names no color" do
      assert {:ok, schema} =
               Schema.new(%{fill: %{type: :color, label: "Verdict", continuity: 60}})

      assert Schema.fetch(schema, :fill, :type) == {:ok, :color}

      for {key, value} <- [unit: "s", order: ["a"], values: ["a"], window: true, identity: true] do
        assert Schema.new(%{fill: %{type: :color} |> Map.put(key, value)}) ==
                 {:error, [{[:fill, key], {:invalid_for, :color}}]}
      end

      # The description holds no color (D-224): `type: :color` is what the rows carry.
      assert Schema.new(%{fill: %{type: :color, color: "#0a0"}}) ==
               {:error, [{[:fill, :color], {:color_key, :color}}]}
    end
  end

  describe "a virtual source's conformance (spec/08 §10.5.7)" do
    test "a :color field takes every color value whose literals parse" do
      colors = [
        @good,
        @shaded,
        {:color, "brand"},
        {:series, 2},
        {:ramp, :status, 0.5},
        {:shade, @good, 300},
        {:lighten, {:color, :bad}, 0.2},
        {:darken, "#336699", 0.1},
        {:blend, [@good, "#ffffff"]},
        {:contrast, @good},
        {:contrast, :under},
        "#2e7d32",
        "orange",
        "rgb(46, 125, 50)",
        nil
      ]

      for color <- colors do
        rows = [%{fill: color}]
        assert VirtualSource.conform(source(), rows) == {:ok, rows}, inspect(color)
      end
    end

    test "anything else is refused with {:type, :color}" do
      for bad <- [
            "good",
            "",
            3,
            0.5,
            :good,
            true,
            {:color, nil},
            {:alpha, @good, 2},
            {:alpha, "nope", 0.5},
            [@good],
            %{},
            # A stored function's `{:color, :good}`, its atoms spelled as strings (D-195).
            {"color", "good"}
          ] do
        assert VirtualSource.conform(source(), [%{status: "ok"}, %{fill: bad}]) ==
                 {:error, {1, "fill", {:type, :color}}},
               inspect(bad)
      end
    end

    test "a color value in a :text field is still refused (metresis#504's fault)" do
      source = source(%{@fields | fill: %{type: :text}})

      assert VirtualSource.conform(source, [%{fill: @good}]) ==
               {:error, {0, "fill", {:type, :text}}}
    end
  end

  describe "a feed" do
    test "a feed's schema with a :color field validates, and its rows conform to the kit" do
      schema = Schema.new!(@fields)
      {feed, _agent} = Feeds.scripted(schema: schema, supports: [:push], rows: rows())

      for check <- [:describe, :deliveries] do
        assert Conformance.check(check, feed, windows: [nil], budgets: [nil]) == []
      end
    end
  end

  describe "the codecs" do
    test "a schema's :color field round-trips through its JSON form" do
      # Names as a source holds them, strings (D-195); the type is a word of the library's.
      fields = Schema.new!(Map.new(@fields, fn {k, v} -> {to_string(k), v} end)).fields
      json = fields |> SnapshotCodec.schema_json() |> Jason.encode!() |> Jason.decode!()

      assert ["fill", %{"type" => %{"$atom" => "color"}}] in json
      assert SnapshotCodec.read_schema_json(json) == fields
    end

    test "a virtual source with a :color field round-trips through a board's JSON form" do
      board = Board.from_map!(board(%{strip: strip()}))
      {:ok, json} = Board.to_json(board)

      assert {:ok, ^board} = Board.from_json(json)
      assert Board.virtual_sources(board)[["strip"]].schema.fields["fill"] == %{type: :color}
    end

    test "a snapshot with color values in its rows round-trips through JSON" do
      server = start(Theme.default(), :host)
      settled(server)

      snapshot = Server.snapshot(server)
      assert snapshot.cells["a"].slots["primary"].delivery.rows == rows()

      {:ok, json} = Snapshot.to_json(snapshot)
      assert json =~ ~s({"$alpha":[{"$color":"good"},0.74]})

      assert {:ok, ^snapshot} = Snapshot.from_json(json)
      assert Snapshot.from_map(Snapshot.to_map(snapshot)) == {:ok, snapshot}
    end
  end

  describe "the type check (spec/14 §7.4)" do
    test "a :color field read as a color passes, and through a scale it is refused" do
      schema = Schema.new!(@fields)
      assert Chart.check_types(strip_design(), %{primary: schema}) == :ok

      scaled = put_in(strip_design(), [:frames, :main, :scales, :color], %{kind: :ordinal})

      assert Chart.check_types(scaled, %{primary: schema}) ==
               {:error,
                [
                  {[:marks, 0, :channels, :value],
                   {:type_mismatch, "primary", "fill", :category, :color}}
                ]}

      on_y = put_in(strip_design(), [:marks, Access.at(0), :channels, :y1], :fill)

      assert {:error,
              [
                {[:marks, 0, :channels, :y1],
                 {:type_mismatch, "primary", "fill", :number, :color}}
              ]} =
               Chart.check_types(on_y, %{primary: schema})

      assert Board.format_error({[], {:type_mismatch, "primary", "fill", :number, :color}}) =~
               "is a color, and the design reads it as a number"
    end

    test "rows of typed colors suggest :color, and a design may declare it" do
      assert Table.column_types(rows()).fill == :color
      assert Chart.Schema.column_types() == [:time, :number, :category, :text, :color]

      typed = put_in(strip_design(), [:sources, :primary, :types], %{fill: :color})
      assert {:ok, chart} = Chart.from_map(typed)
      assert Chart.column_type(chart, :primary, :fill) == :color
    end

    test "a preview's sample rows give a :color field the palette's series in turn" do
      rows = Visualize.Chart.Builder.Boards.sample(Schema.new!(@fields), @t0)

      assert rows |> Enum.take(4) |> Enum.map(& &1.fill) == [
               series: 1,
               series: 2,
               series: 3,
               series: 1
             ]
    end
  end

  describe "drawing (spec/15 §14.5)" do
    test "a virtual source's color values draw as a host source's, re-colored by the theme" do
      svgs =
        for theme <- [Theme.default(), Theme.builtin(:color_safe)] do
          host = theme |> start(:host) |> settled() |> Map.fetch!(:svg)
          virtual = theme |> start(:virtual) |> settled() |> Map.fetch!(:svg)

          assert host == virtual

          # Each block is painted with the theme's color of its verdict, resolved at render.
          for color <- [@good, @shaded] do
            assert host =~ ~s(fill="#{Visualize.Color.resolve(color, theme, :css)}")
          end

          host
        end

      # Another theme, another drawing: the rows name meanings, not colors.
      [default, color_safe] = svgs
      refute default == color_safe
    end
  end

  # -- helpers ------------------------------------------------------------------------------

  defp rows do
    for {state, i} <- Enum.with_index(["ok", "rate", "ok"]) do
      %{
        x0: DateTime.add(@t0, i * 60),
        x1: DateTime.add(@t0, (i + 1) * 60),
        y0: 0,
        y1: 1,
        fill: if(state == "ok", do: @good, else: @shaded),
        status: state
      }
    end
  end

  # The raw feed's rows carry the status; the virtual source writes each block's fill.
  defp raw_rows, do: Enum.map(rows(), &Map.delete(&1, :fill))

  defp strip, do: %{from: [{:raw, nil}], schema: @fields, function: :status_blocks}

  defp strip_design do
    %{
      version: 2,
      sources: %{primary: %{fields: [:x0, :x1, :y0, :y1, :fill]}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{x: %{kind: :time}, y: %{kind: :linear, domain: [0, 1]}}
        }
      },
      marks: [
        %{
          type: :rect,
          data: :primary,
          channels: %{x0: :x0, x1: :x1, y0: :y0, y1: :y1, value: :fill}
        }
      ]
    }
  end

  defp board(sources) do
    %{
      cells: %{a: %{x: 0, y: 0, w: 6, h: 2, ref: {:composite, 1}, title: "Strip"}},
      virtual_sources: sources
    }
  end

  defp start(theme, kind) do
    sup = start_supervised!(Supervisor.child_spec(Visualize.Board.Supervisor, id: make_ref()))

    {raw, agent} =
      case kind do
        :host ->
          Feeds.scripted(schema: Schema.new!(@fields), rows: rows())

        :virtual ->
          Feeds.scripted(schema: Schema.new!(Map.delete(@fields, :fill)), rows: raw_rows())
      end

    Process.unlink(agent)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)

    {sources, feeds, bound} =
      case kind do
        :host -> {%{}, %{host: raw}, :host}
        :virtual -> {%{strip: strip()}, %{raw: raw}, :strip}
      end

    {:ok, server} =
      Server.start(sup,
        board: Board.from_map!(board(sources)),
        store: %{{:composite, 1} => strip_design()},
        binding: Binding.new(%{{:a, :primary} => bound}),
        feeds: feeds,
        theme: theme,
        tick: nil,
        debounce: 0,
        clock: fn -> DateTime.add(@t0, 3600) end,
        virtual_sources: [Host]
      )

    {:ok, _info} = Server.subscribe(server)
    :ok = Server.tick(server)
    server
  end

  # The cell's first live view drawn by this board.
  defp settled(server) do
    receive do
      {:visualize_board, ^server, {:cell, "a", %View{state: :live, svg: svg} = view}}
      when is_binary(svg) ->
        view

      {:visualize_board, ^server, {:cell, "a", %View{state: {:down, _} = down}}} ->
        flunk(
          "the cell is down: #{inspect(down)}: #{inspect(Server.info(server).virtual_sources)}"
        )
    end
  end
end
