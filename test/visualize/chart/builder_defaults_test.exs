defmodule Visualize.Chart.Builder.DefaultsTest do
  @moduledoc """
  Sizes in units and container defaults in the builder (spec/14 §18.6, §18.7, D-178 as
  amended by #684).
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.BuilderFixture
  alias Visualize.Chart
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{Editor, Stack}
  alias Visualize.Units

  doctest Visualize.Chart.Validator.Units, only: [units: 2]

  defp edit(s, name, value, node \\ nil) do
    params = %{"_target" => [name], name => value}
    params = if node, do: Map.put(params, "_node", node), else: params
    {:noreply, s} = Builder.handle_event("edit", params, s)
    s
  end

  defp series(s), do: get_in(hd(s.assigns.uses).local, [:styles, "series"])

  describe "a size is a number and a unit (§18.6)" do
    setup do
      s = BuilderFixture.socket(BuilderFixture.layers())
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)
      %{socket: s}
    end

    test "each unit written and read back, and a typed number keeps it", %{socket: s} do
      for unit <- Units.units() -- [:pct] do
        s = edit(s, "stroke.width.unit", to_string(unit))
        assert series(s).stroke.width == {2, unit}

        html = BuilderFixture.render(s)
        assert html =~ ~s(<input type="text" name="stroke.width" value="2">)
        assert html =~ ~s(<option value="#{unit}" selected>)
      end

      s = s |> edit("stroke.width.unit", "pt") |> edit("stroke.width", "3")
      assert series(s).stroke.width == {3, :pt}

      # User units is the bare number.
      s = edit(s, "stroke.width.unit", "")
      assert series(s).stroke.width == 3
    end

    test "% is offered only where a size has a box, and an opacity has no unit" do
      html =
        render_component(&Editor.panel/1, %{
          kind: :style,
          node: %{stroke: %{width: 1}, font: %{size: 12}, marker: %{size: 10}}
        })

      [_, stroke] = String.split(html, ~s(name="stroke.width.unit"), parts: 2)
      [stroke, _] = String.split(stroke, "</select>", parts: 2)
      refute stroke =~ ~s(value="pct")
      assert stroke =~ ~s(value="pt")

      [_, font] = String.split(html, ~s(name="font.size.unit"), parts: 2)
      [font, _] = String.split(font, "</select>", parts: 2)
      assert font =~ ~s(<option value="pct">%</option>)

      refute html =~ ~s(name="opacity.unit")
      refute html =~ ~s(name="stroke.opacity.unit")
    end

    test "a slot word has no unit", %{socket: s} do
      s = edit(s, "font.size", ":label_size")
      assert series(s).font.size == :label_size
      refute BuilderFixture.render(s) =~ ~s(name="font.size.unit")
    end

    test "a gradient's center is a pair, starting from its default", %{socket: s} do
      s = s |> edit("fill.type", "solid") |> edit("fill.type", "radial")
      html = BuilderFixture.render(s)
      assert html =~ ~s(name="fill.center.0" value="0.5")
      assert html =~ ~s(name="fill.center.1" value="0.5")

      s = edit(s, "fill.center.1", "0.25")
      assert series(s).fill.center == [0.5, 0.25]
    end
  end

  describe "defaults where their container is (§18.7)" do
    test "a frame's and the design's on the frame's page, by part and by mark kind" do
      s = BuilderFixture.socket(BuilderFixture.layers())
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "frames.main"}, s)
      html = BuilderFixture.render(s)
      assert html =~ ~s(data-builder-node="frames.main.defaults")
      assert html =~ ~s(data-builder-node="defaults")

      s = edit(s, "stroke.width", "3", "frames.main.defaults")
      s = edit(s, "font.size", "11", "defaults")
      s = edit(s, "+kind", "line", "frames.main.defaults")
      s = edit(s, "line.stroke.cap", "round", "frames.main.defaults")

      design = BuilderFixture.design(s)

      assert design.frames["main"].defaults == %{
               stroke: %{width: 3},
               line: %{stroke: %{cap: :round}}
             }

      assert design.defaults == %{font: %{size: 11}}

      # The line's look takes them, each from its container (§17.3).
      {:ok, applied} = Chart.apply(design, sources: BuilderFixture.sources())
      %{parts: parts} = Chart.explain(applied, at: [:marks, 0])

      containers =
        for link <- parts.stroke.chain, link.layer in [:defaults, :kind], do: link.container

      assert {:frame, "main"} in containers

      # The kind's entry shows, with its ×; the others are offered.
      html = BuilderFixture.render(s)
      assert html =~ ~s(data-builder-part="line")
      assert html =~ ~s(<option value="rect">rect</option>)

      {:noreply, s} =
        Builder.handle_event(
          "style_item",
          %{"field" => "line", "op" => "drop", "_node" => "frames.main.defaults"},
          s
        )

      refute Map.has_key?(BuilderFixture.design(s).frames["main"].defaults, :line)
    end

    test "a group's in the site's context, written into the composite and composed under its objects" do
      s = BuilderFixture.socket(BuilderFixture.layers())

      {:noreply, s} =
        Builder.handle_event("select_layer", %{"index" => "2", "extend" => "range"}, s)

      {:noreply, s} = Builder.handle_event("group_sites", %{"index" => "2"}, s)
      group = Stack.get(s.assigns.uses, s.assigns.selected)
      assert Stack.group?(group)

      html = BuilderFixture.render(s)
      assert html =~ ~s(<form id="b-site-defaults-form")
      assert html =~ ~s(phx-change="edit_defaults")

      {:noreply, s} =
        Builder.handle_event(
          "edit_defaults",
          %{"_target" => ["stroke.width"], "stroke.width" => "4"},
          s
        )

      assert Stack.get(s.assigns.uses, group.id).local.composite.defaults ==
               %{stroke: %{width: 4}}

      # Its objects place them as their own, as the flattening does.
      [mark] = BuilderFixture.design(s).marks
      assert mark.defaults == %{stroke: %{width: 4}}

      {:noreply, s} =
        Builder.handle_event(
          "edit_defaults",
          %{"_target" => ["stroke.width"], "stroke.width" => ""},
          s
        )

      refute Map.has_key?(Stack.get(s.assigns.uses, group.id).local.composite, :defaults)
    end
  end
end
