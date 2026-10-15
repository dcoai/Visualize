defmodule Visualize.Chart.Builder.StyleFormTest do
  @moduledoc """
  A style edited in its parts (spec/14 §18.6, §18.7, §18.14, D-178): a section per part, the
  paint's type first, a control named by its path, a write that is only what was set, the
  parts an element does not draw grayed, and a created style declared in the design.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.BuilderFixture
  alias Visualize.Chart
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{Editor, StyleForm}
  alias Visualize.Chart.Schema

  doctest Visualize.Chart.Builder.StyleForm

  setup do
    s = BuilderFixture.socket(BuilderFixture.layers())
    {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)
    %{socket: s}
  end

  defp series(s), do: get_in(hd(s.assigns.uses).local, [:styles, :series])

  defp edit(s, name, value) do
    {:noreply, s} = Builder.handle_event("edit", %{"_target" => [name], name => value}, s)
    s
  end

  describe "a paint is chosen by its type first (§18.6)" do
    test "a fill's six types and a stroke's five are glyphs, and the type decides the keys" do
      html = render_component(&Editor.panel/1, %{kind: :style, node: %{}})

      for type <- ~w(none solid linear radial hatch paint) do
        assert html =~ ~s(<input type="radio" name="fill.type" value="#{type}")
      end

      for type <- ~w(none solid linear radial paint) do
        assert html =~ ~s(<input type="radio" name="stroke.type" value="#{type}")
      end

      refute html =~ ~s(name="stroke.type" value="hatch")

      # Unset reads no color and no geometry: the type, then what every type reads.
      refute html =~ ~s(data-builder-well="fill.color")
      refute html =~ ~s(name="fill.angle")
      assert html =~ ~s(name="fill.opacity")

      solid = render_component(&Editor.panel/1, %{kind: :style, node: %{fill: "#abc"}})
      assert solid =~ ~s(name="fill.type" value="solid" checked)
      assert solid =~ ~s(data-builder-well="fill.color")
      refute solid =~ ~s(name="fill.angle")

      hatch =
        render_component(&Editor.panel/1, %{
          kind: :style,
          node: %{fill: %{type: :hatch, color: "#abc", pattern: :dots}}
        })

      for key <- ~w(pattern spacing width) do
        assert hatch =~ ~s(phx-value-field="fill.#{key}")
      end

      assert hatch =~ ~s(data-builder-well="fill.background")
      assert hatch =~ ~s(<option value="dots" selected>dots</option>)
      refute hatch =~ ~s(name="fill.angle")

      named =
        render_component(&Editor.panel/1, %{
          kind: :style,
          node: %{fill: {:paint, :glow}},
          refs: %{paint: [:glow, :shade]}
        })

      assert named =~ ~s(<select name="fill.name">)
      assert named =~ ~s(<option value="glow" selected>glow</option>)
    end

    test "a gradient starts from the color, its stops are rows, and solid takes the first back",
         %{socket: s} do
      s = s |> edit("fill.type", "solid") |> edit("fill.color", "#abcdef")
      assert series(s).fill == %{type: :solid, color: "#abcdef"}

      s = edit(s, "fill.type", "linear")

      assert series(s).fill == %{
               type: :linear,
               stops: [
                 %{at: 0, color: "#abcdef", opacity: 0.8},
                 %{at: 1, color: "#abcdef", opacity: 0.1}
               ]
             }

      html = BuilderFixture.render(s)
      assert html =~ ~s(name="fill.type" value="linear" checked)
      refute html =~ ~s(data-builder-well="fill.color")
      assert html =~ ~s(data-builder-well="fill.stops.0.color")
      assert html =~ ~s(data-builder-well="fill.stops.1.color")
      assert html =~ ~s(name="fill.stops.1.opacity")
      assert html =~ ~s(name="fill.angle")
      assert html =~ ~s(phx-click="style_item" phx-value-field="fill.stops" phx-value-op="add")
      # The gradient is a paint in place: the preview draws it from the frame's defs.
      assert html =~ "<linearGradient"

      # A stop's color by a patch and by the chooser; the angle by its scrubber.
      {:noreply, s} =
        Builder.handle_event(
          "drop_colour",
          %{"field" => "fill.stops.1.color", "colour" => "axis"},
          s
        )

      s = s |> edit("fill.stops.0.color", "#123456") |> edit("fill.angle.range", "90")

      assert series(s).fill.angle == 90

      assert series(s).fill.stops == [
               %{at: 0, color: "#123456", opacity: 0.8},
               %{at: 1, color: :axis, opacity: 0.1}
             ]

      {:noreply, picked} =
        Builder.handle_event("select_field", %{"field" => "fill.stops.1.color"}, s)

      assert picked.assigns.context == :colour
      html = BuilderFixture.render(picked)
      assert html =~ ~s(<h3 class="vis-builder-context-title">fill.stops.1.color</h3>)
      assert html =~ ~s(name="fill.stops.1.color.slot" value="axis" checked)

      # Radial keeps the stops, and its centre and radius follow.
      radial = edit(s, "fill.type", "radial")
      assert series(radial).fill.stops == series(s).fill.stops
      assert BuilderFixture.render(radial) =~ ~s(phx-value-field="fill.radius")
      refute BuilderFixture.render(radial) =~ ~s(name="fill.angle")

      # Solid takes the first stop's color.
      solid = edit(radial, "fill.type", "solid")
      assert series(solid).fill == %{type: :solid, color: "#123456"}
    end

    test "a stop is added and removed by the rows' + and ×", %{socket: s} do
      s = s |> edit("fill.type", "solid") |> edit("fill.type", "linear")

      {:noreply, s} =
        Builder.handle_event("style_item", %{"field" => "fill.stops", "op" => "add"}, s)

      assert length(series(s).fill.stops) == 3

      {:noreply, s} =
        Builder.handle_event(
          "style_item",
          %{"field" => "fill.stops", "op" => "remove", "index" => "0"},
          s
        )

      assert [%{opacity: 0.1}, %{at: 1}] = series(s).fill.stops
    end

    test "a stroke's type change keeps its line", %{socket: s} do
      s = edit(s, "stroke.type", "linear")
      stroke = series(s).stroke
      assert stroke.type == :linear and stroke.width == 2
      assert [%{color: :series_1}, %{color: :series_1}] = stroke.stops

      none = edit(s, "stroke.type", "none")
      assert series(none).stroke == %{type: :none, width: 2}
    end
  end

  describe "every part is edited in place (§18.7)" do
    test "an edit through every compound part round-trips into the design and applies", %{
      socket: s
    } do
      edits = [
        {"extends", "axis", [:extends], :axis},
        {"opacity", "0.5", [:opacity], 0.5},
        {"blend", "multiply", [:blend], :multiply},
        {"class", "callout", [:class], "callout"},
        {"fill.type", "solid", [:fill, :type], :solid},
        {"fill.color", "#123456", [:fill, :color], "#123456"},
        {"fill.opacity", "0.4", [:fill, :opacity], 0.4},
        {"stroke.width", "3", [:stroke, :width], 3},
        {"stroke.dash", "4 2", [:stroke, :dash], "4 2"},
        {"stroke.cap", "round", [:stroke, :cap], :round},
        {"stroke.non_scaling", "true", [:stroke, :non_scaling], true},
        {"font.family", "Georgia", [:font, :family], "Georgia"},
        {"font.size", "14", [:font, :size], 14},
        {"font.face", "bold_italic", [:font, :weight], :bold},
        {"font.line_height", "1.4", [:font, :line_height], 1.4},
        {"text.anchor", "middle", [:text, :anchor], :middle},
        {"text.angle", "45", [:text, :angle], 45},
        {"effect.type", "shadow", [:effect, :type], :shadow},
        {"effect.radius", "3", [:effect, :radius], 3},
        {"marker.shape", "cross", [:marker, :shape], :cross},
        {"marker.size", "40", [:marker, :size], 40},
        {"curve.type", "step", [:curve, :type], :step},
        {"transition.duration", "300", [:transition, :duration], 300},
        {"transition.fill.duration", "200", [:transition, :fill, :duration], 200},
        {"transition.fill.easing", "linear", [:transition, :fill, :easing], :linear},
        {"animation.name", "pulse", [:animation, :name], :pulse},
        {"animation.iterations", "infinite", [:animation, :iterations], :infinite},
        {"enter.name", "fade", [:enter, :name], :fade},
        {"exit.name", "explode", [:exit, :name], :explode},
        {"exit.duration", "250", [:exit, :duration], 250}
      ]

      s =
        Enum.reduce(edits, s, fn {name, value, _path, _expected}, acc ->
          edit(acc, name, value)
        end)

      for {name, _value, path, expected} <- edits do
        assert get_in(series(s), path) == expected, "#{name} did not write #{inspect(path)}"
      end

      # Both keys of the face, in the one font part.
      assert series(s).font.style == :italic
      # No flat key survives the edits (D-178).
      refute Visualize.Chart.Style.Parts.flat?(series(s))

      design = BuilderFixture.design(s)
      assert design.styles.series == series(s)
      assert {:ok, _applied} = Chart.apply(design, sources: BuilderFixture.sources())
    end

    test "a host's name is the box beneath the list's words", %{socket: s} do
      html = BuilderFixture.render(s)
      assert html =~ ~s(name="animation.name.other")

      s = edit(s, "animation.name.other", "wiggle")
      assert series(s).animation.name == "wiggle"

      assert BuilderFixture.render(s) =~
               ~s(name="animation.name.other" class="vis-builder-declared-name" value="wiggle")
    end

    test "a node in the flat keys is rewritten in its parts by its first edit", %{socket: s} do
      # The fixture's house style is written in version 2's keys.
      assert series(s) == %{stroke: :series_1, stroke_width: 2}

      s = edit(s, "opacity", "0.5")
      assert series(s) == %{stroke: %{type: :solid, color: :series_1, width: 2}, opacity: 0.5}
    end

    test "a part blanked is removed with its last key", %{socket: s} do
      s = s |> edit("font.size", "14") |> edit("font.size", "")
      refute Map.has_key?(series(s), :font)
    end
  end

  describe "the parts an element does not draw are grayed (§5.6, §18.7)" do
    test "by the element's kind, and never for a named style" do
      undrawn = fn drawn_by ->
        html = render_component(&Editor.panel/1, %{kind: :style, node: %{}, drawn_by: drawn_by})

        ~r/<fieldset class="vis-builder-part vis-builder-part-undrawn" data-builder-part="(\w+)">/
        |> Regex.scan(html)
        |> Enum.map(fn [_, part] -> String.to_existing_atom(part) end)
      end

      for kind <- [:line, :rule, :area, :rect, :symbol, :text] do
        assert Enum.sort(undrawn.(kind)) == Enum.sort(Visualize.Chart.Style.Parts.undrawn(kind)),
               "#{kind}"
      end

      assert undrawn.(nil) == []

      html = render_component(&Editor.panel/1, %{kind: :style, node: %{}, drawn_by: :area})
      assert html =~ "not drawn by an area"
    end
  end

  describe "names and writes (§18.7)" do
    test "every key of every part is located by its name, and nothing else is" do
      for %{key: part, type: {:node, kind}} <- Schema.describe(:style),
          %{key: key} = spec <- Schema.describe(kind) do
        name = "#{part}.#{key}"
        assert %{path: [^part, ^key], spec: ^spec} = StyleForm.locate(:style, name), name
      end

      assert StyleForm.locate(:style, "fill.stops.x.color") == nil
      assert %{path: [:fill], suffix: nil} = StyleForm.locate(:style, "fill")
      assert StyleForm.locate(:style, "nonsense.width") == nil
      assert StyleForm.locate(:mark, "stroke.width") == nil
    end

    test "a local write holds only what was set, and a list edited at a site starts from the site's" do
      resolved = %{
        stroke: %{type: :linear, stops: [%{at: 0, color: "#000"}, %{at: 1, color: "#fff"}]}
      }

      assert StyleForm.write(%{}, [:stroke, :width], {:ok, 4}, resolved) ==
               [stroke: {:ok, %{width: 4}}]

      assert StyleForm.write(%{}, [:stroke, :stops, 1, :color], {:ok, "#f00"}, resolved) ==
               [stroke: {:ok, %{stops: [%{at: 0, color: "#000"}, %{at: 1, color: "#f00"}]}}]
    end
  end
end
