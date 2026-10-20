defmodule Visualize.Board.StateTest do
  @moduledoc """
  A cell's states decided and drawn (spec/15 §8.4, #574, D-146), the rows a cell draws
  placed by their timestamp with a break in every gap (§8.5), and the board's
  `stale_after` key (§1.2).
  """
  use ExUnit.Case, async: true

  alias Visualize.Board
  alias Visualize.Board.{Rows, State}
  alias Visualize.Data.{Delivery, Schema}
  alias Visualize.Theme

  doctest State
  doctest Rows

  @schema Schema.new!(%{t: %{type: :time}, v: %{type: :number}})
  @now ~U[2026-10-11 12:10:00Z]

  defp slot(rows, opts \\ []) do
    delivery = if rows, do: Delivery.new(rows, Keyword.take(opts, [:capped]))
    %{delivery: delivery, schema: @schema, status: Keyword.get(opts, :status, :live)}
  end

  defp at(minutes), do: %{t: DateTime.add(~U[2026-10-11 12:00:00Z], minutes * 60), v: 1}

  describe "of/3: the first state that holds" do
    test "each state, in its order of precedence" do
      live = slot([at(9)])

      assert State.of(%{a: live, b: slot(nil, status: {:down, :timeout})}, @now, nil) ==
               {:down, :timeout}

      assert State.of(%{a: live, b: slot(nil, status: :loading)}, @now, nil) == :loading
      assert State.of(%{a: slot([]), b: slot([])}, @now, nil) == :no_data
      assert State.of(%{a: slot([at(1)])}, @now, 300) == {:stale, 540.0}
      assert State.of(%{a: slot([at(9)], status: :stale)}, @now, nil) == {:stale, 60.0}
      assert State.of(%{a: slot([at(9)], capped: true)}, @now, 300) == :capped
      assert State.of(%{a: live}, @now, 300) == :live
      assert State.of(%{}, @now, 300) == :live
    end

    test "down beats every other state, and stale beats capped" do
      stale_and_capped = slot([at(0)], capped: true)
      assert State.of(%{a: stale_and_capped}, @now, 60) == {:stale, 600.0}

      assert State.of(%{a: stale_and_capped, b: slot([], status: {:down, :gone})}, @now, 60) ==
               {:down, :gone}
    end
  end

  describe "the drawings (spec/15 §8.4)" do
    @states [
      {{:crashed, :killed}, :bad, "Crashed, restarting"},
      {{:down, {:unbound, :primary}}, :bad, "Feed down: :primary is not bound"},
      {:loading, :info, "Loading…"},
      {:no_data, :neutral, "No data yet"},
      {{:stale, 330}, :warning, "Stale: 5m30s old"},
      {:capped, :info, "Capped: part of the window"}
    ]

    test "every state renders as the whole cell, in its role's color, glyph and words" do
      theme = Theme.default()

      for {state, role, words} <- @states do
        assert State.role(state) == role
        assert State.words(state) == words
        svg = State.render(state, theme, {320, 160})

        assert svg =~ ~s(data-vis-state="#{State.name(state)}")
        assert svg =~ ~s(role="img")
        assert svg =~ ~s(aria-label="#{words}") and not (svg =~ "<title")
        assert svg =~ "var(#{Theme.css_name(role)}, "
        assert svg =~ ~s(class="vis-cell-state-glyph")
        assert svg =~ ~s(fill="var(--vis-surface, )
        assert svg =~ ~s(viewBox="0 0 320 160")
      end
    end

    test "every state but live renders as a banner across a chart" do
      for {state, role, words} <- @states do
        banner = State.banner(state, Theme.dark(), 400)
        assert banner =~ ~s(class="vis-cell-banner")
        assert banner =~ "var(#{Theme.css_name(role)}, "
        assert banner =~ ">#{words}</text>"
      end

      assert State.banner(:live, Theme.default(), 400) == nil
    end

    test "a cell whose data cannot be applied says why, in the validator's words" do
      words =
        State.words({:down, {:apply, [{[:sources, "primary"], {:unbound, :source, "primary"}}]}})

      assert words =~ "Feed down: sources.primary:"
    end
  end

  describe "Rows.place/2 (spec/15 §8.5)" do
    test "rows in time order, and break rows series by series" do
      schema =
        Schema.new!(%{
          t: %{type: :number, window: true},
          v: %{type: :number, continuity: 2000},
          host: %{type: :category}
        })

      rows = [
        %{t: 6000, v: 4, host: "a"},
        %{t: 0, v: 1, host: "a"},
        %{t: 1000, v: 2, host: "b"},
        %{t: 1500, v: 3, host: "a"},
        %{t: 2500, v: 5, host: "b"}
      ]

      placed = Rows.place(Delivery.new(rows, schema: "x"), schema)

      assert placed.schema == "x"

      assert placed.rows == [
               %{t: 0, v: 1, host: "a"},
               %{t: 1000, v: 2, host: "b"},
               %{t: 1500, v: 3, host: "a"},
               %{t: 2500, v: 5, host: "b"},
               %{t: 1500, v: nil, host: "a"},
               %{t: 6000, v: 4, host: "a"}
             ]
    end

    test "a schema with no continuity, or no time field, only orders or keeps the rows" do
      rows = [%{t: ~U[2026-01-01 00:10:00Z], v: 1}, %{t: ~U[2026-01-01 00:00:00Z], v: 2}]
      assert Rows.place(Delivery.new(rows), @schema).rows == Enum.reverse(rows)

      untimed = Schema.new!(%{v: %{type: :number}})
      assert Rows.place(Delivery.new(rows), untimed).rows == rows
      assert Rows.place(Delivery.new(rows), nil).rows == rows
    end

    test "seconds of every kind of time" do
      assert Rows.seconds(~U[1970-01-01 00:01:00Z]) == 60.0
      assert Rows.seconds(~D[0000-01-02]) == 86_400
      assert Rows.seconds(7) == 7
      assert Rows.seconds("noon") == nil
    end
  end

  describe "the board's stale_after key (spec/15 §1.2)" do
    test "a positive number of seconds or nil, through the map and JSON forms" do
      board = Board.from_map!(%{stale_after: 90})
      assert board.stale_after == 90
      assert {:ok, ^board} = board |> Board.to_map() |> Board.from_map()
      {:ok, json} = Board.to_json(board)
      assert {:ok, ^board} = Board.from_json(json)

      assert Board.from_map(%{stale_after: 0}) ==
               {:error, [{[:stale_after], {:type, :positive}}]}

      assert Board.from_map!(%{}).stale_after == nil
    end
  end
end
