defmodule Visualize.Chart.StyleTest do
  @moduledoc """
  Style resolution of spec/14 §3.4 and D-63: one node, two outputs by mode, a `{:field, f}`
  bound per datum through the frame's colour scale.
  """
  use ExUnit.Case, async: true

  alias Visualize.{Chart, Theme}
  alias Visualize.Chart.{Frame, Style}

  doctest Style

  @theme Theme.default()
  @node %{
    fill: :series_2,
    stroke: "#f00",
    stroke_width: 2,
    stroke_dasharray: [4, 2],
    opacity: :none,
    font_family: :font_family,
    font_size: :label_size,
    class: "hot",
    curve: :step_after,
    curve_opts: %{tension: 0.5},
    symbol: :star,
    symbol_size: 30
  }

  test "the :css output carries custom-property references and the class" do
    assert Style.resolve(@node, @theme, :css) == %{
             fill: "var(--vis-series-2, #d9730d)",
             stroke: "#f00",
             stroke_width: 2,
             stroke_dasharray: "4 2",
             opacity: :none,
             font_family: "var(--vis-font-family, sans-serif)",
             font_size: "var(--vis-label-size, 12px)",
             class: "hot"
           }
  end

  test "the :literal output carries the plain values a canvas reads" do
    assert Style.resolve(@node, @theme, :literal) == %{
             fill: "#d9730d",
             stroke: "#f00",
             stroke_width: 2,
             stroke_dasharray: "4 2",
             opacity: :none,
             font_family: "sans-serif",
             font_size: 12,
             class: "hot"
           }
  end

  test "the four generator keys never reach an element" do
    resolved = Style.resolve(@node, @theme, :css)
    refute Enum.any?([:curve, :curve_opts, :symbol, :symbol_size], &Map.has_key?(resolved, &1))
  end

  test "a field reference survives resolve/3 and a variable raises" do
    assert Style.resolve(%{fill: {:field, :k}}, @theme, :css) == %{fill: {:field, :k}}

    assert_raise ArgumentError, ~r/variable :accent is unresolved/, fn ->
      Style.resolve(%{stroke: Chart.var(:accent)}, @theme, :css)
    end
  end

  describe "bind/4" do
    defp frame(scales) do
      Frame.new(
        Chart.from_map!(%{
          version: 1,
          sources: %{primary: %{fields: [:k, :w]}},
          frame: %{kind: :cartesian, scales: scales}
        })
      )
    end

    test "a colour key reads through the colour scale and resolves the slot" do
      frame = frame(%{color: %{kind: :ordinal, domain: ["a", "b"]}})
      style = %{fill: {:field, :k}, stroke_width: {:field, :w}, opacity: 0.5}

      assert Style.bind(style, %{k: "b", w: 3}, frame, :css) ==
               %{fill: "var(--vis-series-2, #d9730d)", stroke_width: 3, opacity: 0.5}

      assert Style.bind(style, %{k: "b", w: 3}, frame, :literal) ==
               %{fill: "#d9730d", stroke_width: 3, opacity: 0.5}
    end

    test "without a colour scale the reading is the colour, a slot resolved" do
      frame = frame(%{})
      assert Style.bind(%{fill: {:field, :k}}, %{k: "#abc"}, frame, :css) == %{fill: "#abc"}

      assert Style.bind(%{fill: {:field, :k}}, %{k: :axis}, frame, :literal) ==
               %{fill: "#666666"}
    end

    test "a nil reading or a category the scale does not hold drops the key" do
      frame = frame(%{color: %{kind: :ordinal, domain: ["a"]}})
      assert Style.bind(%{fill: {:field, :k}, opacity: 1}, %{}, frame, :css) == %{opacity: 1}
      assert Style.bind(%{fill: {:field, :k}}, %{k: "zzz"}, frame, :css) == %{}
    end
  end
end
