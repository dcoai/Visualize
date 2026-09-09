defmodule Visualize.Chart.StyleTest do
  @moduledoc """
  Style resolution of spec/14 §3.4 and D-63: one node, two outputs by mode, a `{:field, f}`
  bound per datum through the frame's colour scale, and the `extends` chain flattened at
  the lookup (§3.5, D-80).
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

  describe "extends (spec/14 §3.5)" do
    defp styles(declared), do: Style.all(declared)

    test "the parent's keys first, the child's over them" do
      styles = styles(%{series: %{stroke: "#f00", stroke_width: 1}})

      assert Style.node(styles, :series) == %{stroke: "#f00", stroke_width: 1}

      styles = styles(%{series: %{stroke: "#f00", stroke_width: 1}, heavy: %{extends: :series}})
      assert Style.node(styles, :heavy) == %{stroke: "#f00", stroke_width: 1}

      styles =
        styles(%{
          series: %{stroke: "#f00", stroke_width: 1},
          heavy: %{extends: :series, stroke_width: 3}
        })

      assert Style.node(styles, :heavy) == %{stroke: "#f00", stroke_width: 3}
    end

    test "a chain of three, and a built-in style as the parent" do
      styles =
        styles(%{
          a: %{stroke: "#001", opacity: 0.2},
          b: %{extends: :a, opacity: 0.5, fill: "#002"},
          c: %{extends: :b, fill: "#003"}
        })

      assert Style.node(styles, :c) == %{stroke: "#001", opacity: 0.5, fill: "#003"}

      assert Style.node(styles(%{heavy: %{extends: :axis, stroke_width: 2}}), :heavy) ==
               Map.put(Style.builtin(:axis), :stroke_width, 2)
    end

    test "the key never reaches a resolved node" do
      styles = styles(%{base: %{stroke: :axis}, derived: %{extends: :base, stroke_width: 2}})
      node = Style.node(styles, :derived)

      refute Map.has_key?(node, :extends)
      assert Style.resolve(node, @theme, :literal) == %{stroke: "#666666", stroke_width: 2}
    end

    test "a cycle raises at resolution, having been reported by the validator" do
      styles = styles(%{a: %{extends: :b}, b: %{extends: :a}})

      assert_raise ArgumentError, ~r/style :a extends itself/, fn -> Style.node(styles, :a) end
    end
  end

  describe "a stack at a site (spec/14 §3.6, D-98)" do
    test "a bare reference and a one-element stack are the same node" do
      styles = %{series: %{stroke: "#111", stroke_width: 2}}

      assert Style.node(styles, :series) == Style.node(styles, [:series])
      assert Style.node(styles, :series) == %{stroke: "#111", stroke_width: 2}
    end

    test "entries cascade left to right, the later winning" do
      styles = %{
        series: %{stroke: "#111", stroke_width: 2},
        emphasis: %{stroke_width: 5}
      }

      assert Style.node(styles, [:series, :emphasis]) == %{stroke: "#111", stroke_width: 5}
      assert Style.node(styles, [:emphasis, :series]) == %{stroke: "#111", stroke_width: 2}
    end

    test "an inline node is an entry like any other, and is where a local edit sits" do
      styles = %{series: %{stroke: "#111", stroke_width: 2}}

      assert Style.node(styles, [:series, %{stroke_width: 5}]) ==
               %{stroke: "#111", stroke_width: 5}

      # The shared style is untouched by the local one: that is the whole point of it.
      assert Style.node(styles, :series) == %{stroke: "#111", stroke_width: 2}
    end

    test "each entry is flattened through its own extends before the entries cascade" do
      styles = %{
        base: %{stroke: "#111", stroke_width: 1, opacity: 0.5},
        series: %{extends: :base, stroke_width: 2},
        emphasis: %{stroke_width: 5}
      }

      # `series` resolves to base's keys with its own over them, and only then does
      # `emphasis` win the width. Nothing carries `extends` out.
      assert Style.node(styles, [:series, :emphasis]) ==
               %{stroke: "#111", stroke_width: 5, opacity: 0.5}
    end

    test "an inline entry may extend a declared style" do
      styles = %{base: %{stroke: "#111", stroke_width: 1}}

      assert Style.node(styles, [%{extends: :base, stroke_width: 4}]) ==
               %{stroke: "#111", stroke_width: 4}
    end

    test "an empty stack, and a stack naming nothing, are the empty node" do
      assert Style.node(%{}, []) == %{}
      assert Style.node(%{}, [:nothing, :also_nothing]) == %{}
    end

    test "the same style twice is harmless" do
      styles = %{series: %{stroke_width: 2}}
      assert Style.node(styles, [:series, :series]) == Style.node(styles, :series)
    end

    test "a cycle through extends still raises, from inside a stack" do
      styles = %{a: %{extends: :b}, b: %{extends: :a}}

      assert_raise ArgumentError, ~r/style :a extends itself/, fn ->
        Style.node(styles, [:a])
      end
    end

    test "the built-in four are reachable from a stack" do
      # `node/2` looks up whatever map it is given; the frame gives it `all/1`, which is the
      # declared styles over the built-in four (spec/14 §3.3).
      styles = Style.all(%{})

      assert Style.node(styles, [:axis]) == Style.builtin(:axis)
      assert Style.node(styles, [:grid, %{stroke_width: 3}]).stroke_width == 3
      assert Style.node(styles, [:grid, %{stroke_width: 3}]).stroke == Style.builtin(:grid).stroke
    end
  end
end
