defmodule ExamplesWeb.BuilderBindCostTest do
  @moduledoc """
  One binding in the builder's board mode within a reduction budget (spec/12 §6, #838,
  D-219): a slot of the gallery's heaviest component, *Grandma's Marathon*, bound to
  another feed by its `board_bind` event, with the render's editing pass after it — what a
  page pays for one choice in a slot's select.

  **The work is counted, not timed** (D-114): `Visualize.Work.reductions/1`, twice, the
  two counts agreeing within half a percent as the gallery's do (`gallery_cost_test.exs`).
  The budget is the count measured when #838 set it, with a margin under the cheapest
  defect it guards: before #838 the event read the cell's slots through the store
  (about 270,000 more), every pass flattened the component again (about 168,000 more each,
  the event's and the render's), the preview flattened it once more (about 162,000), and
  a binding ran the board's virtual sources again (about 40,000).
  """
  use ExUnit.Case, async: true

  import ExamplesWeb.BuilderBoard

  alias ExamplesWeb.BuilderLive.Library
  alias Visualize.Chart.Builder.{Boards, Editing}

  # Measured with #838's fix: 274,980 (1,066,065 before it), and a budget a tenth above,
  # under the 40,000 the cheapest defect adds.
  @budget 300_000

  @agree 0.005

  setup do
    {:ok, _} = Application.ensure_all_started(:examples)
    :ok
  end

  test "one binding of a Marathon slot, with the render after it, is within its budget" do
    {_page, s} = board_mode()
    {s, true} = one_cell(s, Library.id_of("Charts::Grandma's Marathon"))

    # Every slot bound and the pass kept, as a page holds the board between two choices.
    s = bind(s, :wave)
    [%{name: slot} | _] = Editing.editing(s.assigns).board_mode.selected.slots
    key = "slot." <> slot
    params = %{"_target" => [key], key => Boards.feed_key(:load)}

    bind_and_render = fn ->
      s = event(s, "board_bind", params)
      Editing.editing(s.assigns).board_mode
    end

    {first, mode} = Visualize.Work.reductions(bind_and_render)
    {second, _mode} = Visualize.Work.reductions(bind_and_render)

    # The binding was made, and the cell drew again over it.
    assert %{selected: %{slots: slots}, cells: [_cell]} = mode
    assert Enum.find(slots, &(&1.name == slot)).feed == "load"

    assert abs(first - second) <= @agree * min(first, second),
           "two counts are #{first} and #{second}: the count is not a property of the code"

    work = max(first, second)
    assert work <= @budget, "one binding costs #{work} reductions, over its budget of #{@budget}"
  end
end
