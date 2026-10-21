defmodule ExamplesWeb.BuilderBoardBindTest do
  @moduledoc """
  A wrong binding is a fault panel, never a crash (spec/14 §18.4, §22.6, D-153): every
  component of the builder page's library in a board cell, its slots bound to one feed of
  each kind in the page's catalog in turn, and the page drawn after.

  **One test per component, one feed per kind** (spec/12 §6, #838). The test was one cross
  product of every component and every feed — 60 components and 18 feeds, 1,638 bindings —
  and ran out of its 60 s on a loaded CI runner as the gallery and the catalog grew. A
  feed's kind is the shape of its schema (`ExamplesWeb.BuilderBoard.feed_kinds/1`), and
  feeds of one kind take the same path through the binding check and the preview, so a
  new gallery chart is a test of its own and a feed of a kind already there adds nothing.
  """
  use ExUnit.Case, async: true

  import ExamplesWeb.BuilderBoard

  alias ExamplesWeb.BuilderLive.Library
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.Editing

  require Phoenix.LiveViewTest

  setup do
    {:ok, _} = Application.ensure_all_started(:examples)
    :ok
  end

  # The page drawn over the builder's assigns, as the LiveView renders the component.
  defp drawn(s) do
    s.assigns
    |> Map.drop([:__changed__, :flash, :myself])
    |> Map.put(:layers, Map.get(s.assigns, :host_layers, []))
    |> then(&Phoenix.LiveViewTest.render_component(Builder, &1))
  end

  # Every composite the page's library seeds, by name; the library is built at compile
  # time as it is at mount, from the page's own seeds.
  for %{kind: :composite, name: name} <- Library.list(nil) do
    @name name

    test "#{name} binds to every kind of feed without taking the builder down" do
      {page, s} = board_mode()
      {s, placed?} = one_cell(s, Library.id_of(@name))
      assert placed?, "the cell did not take #{@name}"

      for feed <- feed_kinds(page.assigns.catalog) do
        s = bind(s, feed)
        [cell] = Editing.editing(s.assigns).board_mode.cells

        assert match?({:ok, "<svg" <> _}, cell.preview) or
                 match?({:fault, "<svg" <> _, [_ | _]}, cell.preview) or
                 match?({:error, [_ | _]}, cell.preview),
               "#{@name} over #{inspect(feed)}: #{inspect(cell.preview, limit: 5)}"

        # The page draws, whatever the binding.
        assert drawn(s) =~ ~s(data-board-cell="wave")
      end
    end
  end

  test "a binding the component reads draws, and one of the wrong type is its fault panel" do
    {page, s} = board_mode()
    # The live board's own wave cell, which reads the wave feed.
    {s, true} = one_cell(s, s.assigns.board.cells["wave"].ref)
    kinds = feed_kinds(page.assigns.catalog)
    assert :wave in kinds and :invalid in kinds

    [cell] = Editing.editing(bind(s, :wave).assigns).board_mode.cells
    assert {:ok, "<svg" <> _} = cell.preview

    # The invalid feed sends text where the design reads a number (#821).
    [cell] = Editing.editing(bind(s, :invalid).assigns).board_mode.cells
    assert {:fault, "<svg" <> _, [_ | _]} = cell.preview
  end

  test "feeds of one schema shape are one kind, whatever their names or labels" do
    {page, _s} = board_mode()
    kinds = feed_kinds(page.assigns.catalog)

    # `stale`, `no_data` and `capped` are one schema; `requests` and `errors` another;
    # the two VM gauges differ only in their attributes' values.
    assert length(kinds) < map_size(page.assigns.catalog)
    assert Enum.count([:stale, :no_data, :capped], &(&1 in kinds)) == 1
    assert Enum.count([:requests, :errors], &(&1 in kinds)) == 1
    assert Enum.count(["examples.vm.memory", "examples.vm.run_queue"], &(&1 in kinds)) == 1
  end
end
