defmodule Visualize.Chart.BuilderReferencedGroupTest do
  @moduledoc """
  A referenced group expands in the tree, read-only (spec/14 §18.8, #388).

  §18.8: *a referenced group (a library composite dropped linked) expands to show its
  objects, read-only and tagged with the entry's name; selecting one selects the group*.
  The entry's sites carry the entry's ids, not the tree's, so they have no flat position
  of their own: each names its owner and is drawn inside the owner's row. Every entry
  point that names a row by position — select, drag, the menu — therefore resolves to the
  group, and a drop into the group is refused as into a locked group. One test per entry
  point, since the failure mode of a half-done mapping is a drag that reparents into the
  library's inside.
  """
  use ExUnit.Case, async: true

  alias Visualize.BuilderFixture
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.Stack
  alias Visualize.Chart.Use

  defmodule Library do
    @moduledoc false
    @behaviour Visualize.Chart.Builder.Store

    @entries %{
      {:style, 1} => %{name: "Styles::thick", fragment: %{style: %{stroke_width: 5}}},
      {:frame, 1} => %{name: "Frame::wide", fragment: %{frames: %{main: %{margin: %{top: 9}}}}},
      {:composite, 1} => %{
        name: "Charts::pair",
        fragment: %{
          composite: %{
            uses: [
              %Use{id: {:use, 1}, ref: {:frame, 1}},
              %Use{id: {:use, 2}, ref: nil, local: %{theme: :dark}},
              %Use{
                id: {:use, 3},
                ref: nil,
                local: %{composite: %{uses: [%Use{id: {:use, 4}, ref: {:style, 1}}], vars: %{}}}
              }
            ],
            vars: %{}
          }
        }
      }
    }

    @impl true
    def list(_context) do
      for {{kind, _} = id, entry} <- @entries, do: %{id: id, name: entry.name, kind: kind}
    end

    @impl true
    def get({kind, _} = id, _context) do
      case Map.fetch(@entries, id) do
        {:ok, entry} -> {:ok, Map.merge(entry, %{id: id, kind: kind})}
        :error -> :error
      end
    end

    @impl true
    def put(_entry, _context), do: {:error, :read_only}

    @impl true
    def delete(_id, _context), do: :ok

    @impl true
    def import(_bundle, _context), do: {:error, :read_only}
  end

  # The fixture's three layers with Charts::pair dropped linked on top, at position 0.
  defp linked do
    s = BuilderFixture.socket(BuilderFixture.layers(), store: Library)
    {:noreply, s} = Builder.handle_event("insert", %{"name" => "composite:1", "at" => 0}, s)
    s
  end

  defp opened do
    {:noreply, s} = Builder.handle_event("toggle_site", %{"index" => "0"}, linked())
    s
  end

  # The markup of the row at a flat position: its `<li>` and everything drawn in it.
  defp row(html, index) do
    [_before, rest] = String.split(html, ~s(-layers-row-#{index}"), parts: 2)
    [row | _after] = String.split(rest, ~s(-layers-row-#{index + 1}"), parts: 2)
    row
  end

  describe "the rows (spec/14 §18.8, #388)" do
    test "Stack.all/2 puts the entry's sites under the referenced site, each naming its owner and the owner's position" do
      s = linked()
      [pair | _] = s.assigns.uses
      rows = Stack.all(s.assigns.uses, Stack.fetch(Library))

      assert for(row <- rows, do: {row.use.id, row.depth, row.index, row.owner}) == [
               {pair.id, 0, 0, nil},
               {{:use, 1}, 1, 0, pair.id},
               {{:use, 2}, 1, 0, pair.id},
               {{:use, 3}, 1, 0, pair.id},
               {{:use, 4}, 2, 0, pair.id}
               | for(
                   %{use: use, index: i} <- Stack.all(tl(s.assigns.uses)),
                   do: {use.id, 0, i + 1, nil}
                 )
             ]

      # The tree's own rows are exactly all/1's: a flat position still names a site of the tree.
      assert Enum.filter(rows, &(&1.owner == nil)) == Stack.all(s.assigns.uses)
      assert Stack.inside(pair, Stack.fetch(Library)) |> length() == 3
      assert Stack.inside(hd(tl(s.assigns.uses)), Stack.fetch(Library)) == nil
    end
  end

  describe "a referenced group expands, read-only (spec/14 §18.8, #388)" do
    test "a linked Charts:: drop is a container: ▸ and count, its objects drawn tagged with the entry's name when opened" do
      s = linked()
      assert %Use{ref: {:composite, 1}} = hd(s.assigns.uses)
      assert Stack.linkage(hd(s.assigns.uses)) == :linked

      html = BuilderFixture.render(s)
      group = row(html, 0)
      # A container: the ▸ and the count of the entry's sites — but locked, so no drop target.
      assert group =~ ~s(phx-click="toggle_site" phx-value-index="0")
      assert group =~ ~s(<span class="vis-builder-site-count" title="3 inside">3</span>)
      assert group =~ "vis-builder-layer-locked"
      refute group =~ "data-builder-into"
      # Closed, nothing of the inside is drawn.
      refute html =~ "vis-builder-site-inside"

      html = BuilderFixture.render(opened())
      group = row(html, 0)
      assert group =~ ~s(<ul class="vis-builder-site-inside")

      inside = Regex.scan(~r/<li class="vis-builder-site-inside-row"[^>]*>/, group)
      assert length(inside) == 4

      names =
        Regex.scan(~r/<span class="vis-builder-layer-name">([^<]*)<\/span>/, group)
        |> Enum.map(fn [_, name] -> name end)

      # The group's own name, then the entry's sites: a referenced one by its entry's name,
      # one declared in place by its kind, an inner group by the composite's name and its site.
      assert names == ["Charts::pair", "Frame::wide", "theme", "Charts::pair", "Styles::thick"]

      assert length(
               Regex.scan(
                 ~r/<span class="vis-builder-site-tag" title="from Charts::pair">Charts::pair<\/span>/,
                 group
               )
             ) == 4

      assert group =~ ~s(<li class="vis-builder-site-inside-row" style="--vis-builder-depth: 1">)

      # Read-only: an inside row is no row of the tree — no position, no drop target, no
      # event, no drag of its own.
      [_, inside_markup] = String.split(group, ~s(<ul class="vis-builder-site-inside"), parts: 2)
      refute inside_markup =~ "data-builder-layer"
      refute inside_markup =~ "data-builder-into"
      refute inside_markup =~ "phx-click"
      refute inside_markup =~ "draggable"

      # The tree's positions are unchanged by the opening: four sites, four rows.
      assert length(Regex.scan(~r/<li id="b-layers-row-\d+"/, html)) == 4
      assert BuilderFixture.names(opened()) == ["Charts::pair", :house, :shared, :panel]
    end
  end

  describe "every gesture on an inside row is the group's (spec/14 §18.8, #388)" do
    test "select: a click on an inside row selects the group" do
      s = opened()
      [pair, house | _] = s.assigns.uses
      html = BuilderFixture.render(s)
      group = row(html, 0)

      # The inside rows sit in the group's <li>, whose click names the group's position;
      # that is the only position a click on them can send.
      [opening, _] = String.split(group, ~s(<ul class="vis-builder-site-inside"), parts: 2)
      assert opening =~ ~s(phx-click="select_layer" phx-keydown="layer_key" phx-value-index="0")

      {:noreply, picked} = Builder.handle_event("select_layer", %{"index" => "0"}, s)
      assert picked.assigns.selected == pair.id

      # The row after the group is the next site of the tree, not an inside row.
      {:noreply, next} = Builder.handle_event("select_layer", %{"index" => "1"}, s)
      assert next.assigns.selected == house.id
    end

    test "drag: dragging an inside row drags the group, with nothing of its inside left behind" do
      s = opened()
      [pair | rest] = s.assigns.uses
      group = row(BuilderFixture.render(s), 0)

      # The drag source is the group's <li>, carrying the group's position.
      assert group =~ ~s(data-builder-layer="0" draggable="true")

      {:noreply, moved} = Builder.handle_event("reorder", %{"from" => 0, "to" => 3}, s)
      assert moved.assigns.uses == rest ++ [pair]
      assert BuilderFixture.names(moved) == [:house, :shared, :panel, "Charts::pair"]
      assert moved.assigns.uses |> List.last() |> Stack.children() == []
    end

    test "the menu: opened on an inside row, it is the group's" do
      s = opened()
      group = row(BuilderFixture.render(s), 0)
      # The hook names the closest row carrying a position: the group's <li>.
      assert group =~ ~s(data-builder-layer="0")

      {:noreply, menu} = Builder.handle_event("menu", %{"layer" => "0", "x" => 1, "y" => 2}, s)

      assert menu.assigns.menu.site == %{
               index: 0,
               items: [{"group_sites", "Group"}, {"copy_site", "Copy"}, {"unlock_site", "Unlock"}]
             }
    end

    test "a drop into a referenced group is refused as into a locked group" do
      s = opened()
      [pair | _] = s.assigns.uses
      into = to_string(elem(pair.id, 1))

      # A library entry dropped into it: refused, the notice the locked write gives.
      {:noreply, refused} =
        Builder.handle_event("insert", %{"name" => "style:1", "into" => into}, s)

      assert refused.assigns.uses == s.assigns.uses
      assert refused.assigns.notice == "Charts::pair is from the library — open it to edit"

      # A row dragged into it: refused the same way, nothing reparented.
      {:noreply, refused} = Builder.handle_event("reorder", %{"from" => 1, "into" => into}, s)
      assert refused.assigns.uses == s.assigns.uses
      assert refused.assigns.notice == "Charts::pair is from the library — open it to edit"

      # Unlocked, it is an inline group of copies — its sites now rows of the tree, 0 to 4
      # — and a row dropped on it lands inside again (#381).
      {:noreply, unlocked} = Builder.handle_event("unlock_site", %{"index" => "0"}, s)

      {:noreply, inside} =
        Builder.handle_event("reorder", %{"from" => 5, "into" => into}, unlocked)

      assert inside.assigns.notice == nil
      assert length(Stack.children(hd(inside.assigns.uses))) == 4
    end
  end
end
