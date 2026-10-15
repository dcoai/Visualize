defmodule Visualize.Chart.Builder.CostTest do
  @moduledoc """
  The builder's editing pass within a reduction budget (spec/12 §6, spec/14 §19.10, #704,
  D-184). `Visualize.Chart.Builder.Editing.editing/1` is what every builder event and every
  render derives first, so a table rebuilt per name or per field inside it is paid on every
  click; counted here, it fails at a test that names it rather than as a timeout of a test
  that happens to run the pass many times.

  Each count is the second of two (#703): a first run may fill what the second only reads.
  """
  use ExUnit.Case, async: true

  alias Visualize.BuilderFixture
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{Editing, Picker}
  alias Visualize.Theme

  # Measured with #704's fix (reductions, default theme): the pass below about 143,000, the
  # picker's groups about 21,000. Before it the pass was about 708,000 and the groups about
  # 332,000 — the theme's ~190 color names rebuilt and sorted per name resolved, and a node
  # kind's key specs rebuilt on every schema lookup. Each budget is about twice the cost.
  @budget %{editing: 300_000, groups: 50_000}

  defp counted(fun) do
    {_first, _} = Visualize.Work.reductions(fun)
    Visualize.Work.reductions(fun)
  end

  test "one editing pass, a color field selected, is within its budget" do
    s = BuilderFixture.socket(BuilderFixture.layers())
    {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)
    {:noreply, s} = Builder.handle_event("select_field", %{"field" => "stroke.color"}, s)

    {work, editing} = counted(fn -> Editing.editing(s.assigns) end)

    # The pass is the one the chooser draws from: the field selected, the table grouped.
    assert editing.color.key == "stroke.color"
    assert [{"series", _} | _] = editing.color.groups
    assert work <= @budget.editing, "editing/1 spent #{work} reductions, over #{@budget.editing}"
  end

  test "the picker's color table is linear in the theme's names" do
    for theme <- [Theme.default(), Theme.dark()] do
      {work, groups} = counted(fn -> Picker.groups(theme) end)
      assert length(groups) == 5

      assert work <= @budget.groups,
             "Picker.groups/1 (#{theme.name}) spent #{work} reductions, over #{@budget.groups}"
    end
  end
end
