defmodule Visualize.Chart.Builder.ColorTest do
  @moduledoc """
  The chooser picks a color by name from the theme's table and builds a typed transform as
  a chain, step by step (spec/14 §19.10, D-178 as amended by #683).
  """
  use ExUnit.Case, async: true

  import Visualize.Color, only: [color: 1, shade: 2, alpha: 2, intensity: 2, blend: 1]

  alias Visualize.BuilderFixture
  alias Visualize.Chart.Builder
  alias Visualize.Chart.Builder.{Chain, Picker}
  alias Visualize.{Color, Theme}

  doctest Visualize.Chart.Builder.Chain
  doctest Visualize.Chart.Builder.Picker, only: [groups: 1]

  setup do
    s = BuilderFixture.socket(BuilderFixture.layers())
    {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)
    {:noreply, s} = Builder.handle_event("select_field", %{"field" => "stroke.color"}, s)
    %{socket: s}
  end

  defp stroke(s), do: get_in(hd(s.assigns.uses).local, [:styles, :series, :stroke, :color])

  defp chain(s, params), do: elem(Builder.handle_event("color_chain", params, s), 1)

  describe "the color table by name (§19.10)" do
    test "grouped by use, each name in the color the theme gives it" do
      for theme <- [Theme.default(), Theme.dark()] do
        groups = Map.new(Picker.groups(theme))

        assert Enum.map(groups["series"], &elem(&1, 0)) ==
                 for(i <- 1..length(theme.series), do: "series_#{i}")

        assert Enum.map(groups["roles"], &elem(&1, 0)) == ~w(good warning bad info neutral)

        assert Enum.map(groups["furniture"], &elem(&1, 0)) ==
                 ~w(axis grid text background surface)

        assert {"red", _} = List.keyfind(groups["the theme's colors"], "red", 0)
        assert {"steelblue", "#4682b4"} = List.keyfind(groups["CSS names"], "steelblue", 0)

        for {_group, names} <- groups, {name, value} <- names do
          assert value ==
                   Color.resolve({:color, String.to_existing_atom(name)}, theme, :literal)
        end
      end

      # The dark theme's furniture is its own.
      assert Picker.groups(Theme.dark()) != Picker.groups(Theme.default())
    end

    test "a name picked is color(:name), and the design's own theme colors the patches" do
      s = BuilderFixture.socket(BuilderFixture.layers() ++ [{:dark, %{theme: :dark}}])
      {:noreply, s} = Builder.handle_event("select_node", %{"node" => "styles.series"}, s)
      {:noreply, s} = Builder.handle_event("select_field", %{"field" => "stroke.color"}, s)
      html = BuilderFixture.render(s)

      [{_name, background}] =
        for {"furniture", names} <- Picker.groups(Theme.dark()),
            {"background", _} = pair <- names,
            do: pair

      assert html =~ ~s(title="background · #{background}")

      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["stroke.color.slot"], "stroke.color.slot" => "warning"},
          s
        )

      assert get_in(hd(s.assigns.uses).local, [:styles, :series, :stroke, :color]) ==
               color(:warning)
    end
  end

  describe "the transform chain (§19.10)" do
    test "built step by step, each step the typed value Visualize.Color would build", %{
      socket: s
    } do
      s = chain(s, %{"_target" => ["stroke.color.step"], "stroke.color.step" => "shade"})
      assert stroke(s) == shade(color(:series_1), 500)

      s =
        chain(s, %{"_target" => ["amount||0"], "amount||0" => "700", "field" => "stroke.color"})

      assert stroke(s) == shade(color(:series_1), 700)

      s = chain(s, %{"_target" => ["add|"], "add|" => "alpha", "field" => "stroke.color"})
      s = chain(s, %{"_target" => ["amount||1"], "amount||1" => "0.8", "field" => "stroke.color"})
      assert stroke(s) == color(:series_1) |> shade(700) |> alpha(0.8)

      # A name picked is the chain's new base; the steps are kept.
      {:noreply, s} =
        Builder.handle_event(
          "edit",
          %{"_target" => ["stroke.color.slot"], "stroke.color.slot" => "bad"},
          s
        )

      assert stroke(s) == color(:bad) |> shade(700) |> alpha(0.8)

      # The chooser draws the chain, each row the color reached so far.
      html = BuilderFixture.render(s)

      assert html =~
               ~s(<form id="b-picker-chain" class="vis-builder-chain" phx-change="color_chain")

      for row <- Chain.rows(stroke(s), Theme.default()) do
        assert html =~ ~s(aria-label="#{row.word}: #{row.color}")
      end

      assert Enum.map(Chain.rows(stroke(s), Theme.default()), & &1.color) == [
               Color.resolve(color(:bad), Theme.default(), :literal),
               Color.resolve(color(:bad) |> shade(700), Theme.default(), :literal),
               Color.resolve(color(:bad) |> shade(700) |> alpha(0.8), Theme.default(), :literal)
             ]

      # A step removed.
      s = chain(s, %{"field" => "stroke.color", "op" => "remove", "index" => "0", "path" => ""})
      assert stroke(s) == color(:bad) |> alpha(0.8)
    end

    test "a blend's operands are chains of their own", %{socket: s} do
      s = chain(s, %{"_target" => ["stroke.color.step"], "stroke.color.step" => "blend"})
      assert stroke(s) == blend([color(:series_1), color(:background)])

      s =
        chain(s, %{"_target" => ["add|1"], "add|1" => "intensity", "field" => "stroke.color"})

      s =
        chain(s, %{"_target" => ["amount|1|0"], "amount|1|0" => "0.3", "field" => "stroke.color"})

      assert stroke(s) == blend([color(:series_1), color(:background) |> intensity(0.3)])

      s = chain(s, %{"field" => "stroke.color", "op" => "operand_add", "path" => ""})
      assert {:blend, [_, _, _]} = stroke(s)

      s =
        chain(s, %{
          "field" => "stroke.color",
          "op" => "operand_remove",
          "index" => "2",
          "path" => ""
        })

      s =
        chain(s, %{
          "field" => "stroke.color",
          "op" => "operand_remove",
          "index" => "1",
          "path" => ""
        })

      # A blend of one is its operand.
      assert stroke(s) == color(:series_1)
    end

    test "an edit of a field that is not a color changes nothing", %{socket: s} do
      before = hd(s.assigns.uses).local

      s =
        chain(s, %{"field" => "stroke.width", "op" => "remove", "index" => "0", "path" => ""})

      assert hd(s.assigns.uses).local == before
    end
  end
end
