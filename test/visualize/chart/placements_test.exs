defmodule Visualize.Chart.PlacementsTest do
  @moduledoc """
  One placement pass per update (spec/14 §21.5, #811, D-202): the drawing and the keyboard
  read the same placement, and reading it changes nothing either of them writes.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Designs
  alias Visualize.Hooks.Keyboard

  # A band × band grid with an identity and an event: the keyboard's grid points (D-198).
  defp grid(n) do
    design = %{
      version: 3,
      sources: %{cells: %{fields: [:row, :col, :state]}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{
            x: %{kind: :band, domain: Enum.to_list(0..(n - 1))},
            y: %{kind: :band, domain: Enum.to_list((n - 1)..0//-1)}
          }
        }
      },
      marks: [
        %{
          type: :rect,
          data: :cells,
          channels: %{x0: :col, x1: :col, y0: :row, y1: :row},
          tooltip: %{fields: [:state], event: :cell_click}
        }
      ]
    }

    rows = for r <- 0..(n - 1), c <- 0..(n - 1), do: %{row: r, col: c, state: "hidden"}
    {:ok, applied} = Chart.apply(design, sources: %{cells: rows}, size: {20 * n, 20 * n})
    applied
  end

  test "the drawing and the keyboard are what they are without a placement" do
    for name <- Designs.names() do
      applied = Designs.apply(name)
      placements = Chart.placements(applied)

      assert Chart.generate(applied, placements: placements) == Chart.generate(applied),
             "#{name}: the drawing"

      assert Chart.render(applied, root: true, placements: placements) ==
               Chart.render(applied, root: true),
             "#{name}: the markup"

      assert Keyboard.attrs(applied, placements: placements) == Keyboard.attrs(applied),
             "#{name}: the keyboard"
    end
  end

  test "a grid's cells are placed once and read by both" do
    applied = grid(12)
    placements = Chart.placements(applied)

    assert [%{mark: %{type: :rect}, rows: rows, pixels: pixels}] = Map.values(placements)
    assert length(rows) == 144 and length(pixels) == 144
    assert Keyboard.attrs(applied, placements: placements) == Keyboard.attrs(applied)
    assert Chart.generate(applied, placements: placements) == Chart.generate(applied)

    # Counted, not timed (D-114): the keyboard reads the placement instead of placing.
    {placed, _} = Visualize.Work.reductions(fn -> Keyboard.attrs(applied) end)

    {read, _} =
      Visualize.Work.reductions(fn -> Keyboard.attrs(applied, placements: placements) end)

    assert read < placed
  end

  test "a placement of another mark is not read" do
    applied = grid(3)
    [{key, entry}] = Map.to_list(Chart.placements(applied))
    stale = %{key => %{entry | mark: Map.put(entry.mark, :id, "other"), pixels: []}}

    assert Chart.generate(applied, placements: stale) == Chart.generate(applied)
    assert Keyboard.attrs(applied, placements: stale) == Keyboard.attrs(applied)
  end
end
