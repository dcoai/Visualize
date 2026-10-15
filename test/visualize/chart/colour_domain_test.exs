defmodule Visualize.Chart.ColourDomainTest do
  @moduledoc """
  #487, D-122: a colour outside its ordinal domain is the colour scale's `unknown` — the
  theme's `:axis` by default — on SVG and canvas alike; a missing colour is `:none`, which
  both backends draw as no paint; and the validator reports the mismatch a design makes
  visible (spec/14 §3.4, §4.3, §10.1).
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.Canvas
  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart
  alias Visualize.Chart.Validator

  # Three cells, filled by `k` through a colour scale that holds "a" and "b".
  defp design(overrides \\ %{}) do
    Map.merge(
      %{
        version: 3,
        sources: %{cells: %{fields: [:x0, :x1, :k]}},
        styles: %{cell: %{fill: {:field, :k}, stroke: "#000000"}},
        frames: %{
          main: %{
            kind: :cartesian,
            scales: %{
              x: %{kind: :linear, domain: [0, 3]},
              y: %{kind: :linear, domain: [0, 1]},
              color: %{kind: :ordinal, domain: ["a", "b"], range: ["#ff0000", "#00ff00"]}
            }
          }
        },
        marks: [
          %{
            type: :rect,
            data: :cells,
            channels: %{x0: :x0, x1: :x1, y0: 0, y1: 1},
            style: :cell
          }
        ]
      },
      overrides
    )
  end

  defp applied(rows, design \\ design()) do
    {:ok, applied} = Chart.apply(Chart.from_map!(design), sources: %{cells: rows})
    applied
  end

  # The fill of each `<rect>` the mark draws, in order.
  defp svg_fills(applied) do
    svg = Chart.render(applied, resolve: :literal)

    ~r/<g [^>]*class="mark mark-rect"[^>]*>(.*?)<\/g>/s
    |> Regex.run(svg, capture: :all_but_first)
    |> hd()
    |> then(&Regex.scan(~r/<rect [^>]*?fill="([^"]*)"/, &1, capture: :all_but_first))
    |> List.flatten()
  end

  # The fill each canvas element is drawn with: `nil` where it issues no `fill()`.
  defp canvas_fills(applied) do
    applied
    |> Chart.generate(resolve: :literal)
    |> Canvas.render_element(format: :commands)
    |> Enum.reduce({nil, []}, fn
      {:set_fillStyle, [colour]}, {_style, rects} -> {colour, rects}
      # A rect's path is drawn by the fill() that follows it, or by none.
      {:rect, _}, {style, rects} -> {style, [nil | rects]}
      {:fill, []}, {style, [nil | rects]} -> {style, [style | rects]}
      _command, acc -> acc
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  describe "a value outside the colour domain" do
    test "draws the theme's :axis on SVG and on canvas" do
      applied =
        applied([
          %{x0: 0, x1: 1, k: "a"},
          %{x0: 1, x1: 2, k: "zzz"},
          %{x0: 2, x1: 3, k: "b"}
        ])

      assert svg_fills(applied) == ["#ff0000", "#666666", "#00ff00"]
      assert canvas_fills(applied) == ["#ff0000", "#666666", "#00ff00"]

      css = Chart.render(applied)
      assert css =~ ~s|fill="var(--vis-axis, #666666)"|
    end

    test "draws the unknown the scale node gives" do
      design =
        put_in(design(), [:frames, :main, :scales, :color, :unknown], "#0000ff")

      applied = applied([%{x0: 0, x1: 1, k: "zzz"}], design)

      assert svg_fills(applied) == ["#0000ff"]
      assert canvas_fills(applied) == ["#0000ff"]
    end

    test "on the binary stream too: the style record carries the unknown colour" do
      applied = applied([%{x0: 0, x1: 1, k: "zzz"}])
      records = Decoder.decode(Chart.render(applied, backend: :canvas, format: :binary))

      assert Enum.any?(records, &match?({:style, %{fill: {0x66, 0x66, 0x66, _}}}, &1)),
             inspect(records)

      assert :fill in records
    end
  end

  describe "a mark element with no paint" do
    test "is fill=\"none\" on SVG and no fill() on canvas" do
      applied = applied([%{x0: 0, x1: 1, k: "a"}, %{x0: 1, x1: 2, k: nil}])

      assert svg_fills(applied) == ["#ff0000", "none"]
      assert canvas_fills(applied) == ["#ff0000", nil]
    end

    test "draws nothing on the binary stream either" do
      applied = applied([%{x0: 1, x1: 2, k: nil}])
      records = Decoder.decode(Chart.render(applied, backend: :canvas, format: :binary))

      refute :fill in records
      assert :stroke in records
    end
  end

  describe "the validator (spec/14 §10.1)" do
    test "a constant colour channel outside a declared domain" do
      design =
        design(%{
          marks: [
            %{type: :rect, data: :cells, channels: %{x0: :x0, x1: :x1, y0: 0, y1: 1, value: 7}}
          ]
        })

      assert {:error, [{[:marks, 0, :channels, :value], {:outside_domain, :color, 7}} = e]} =
               Validator.validate(design)

      assert Validator.format(e) =~ "7 is not in scale :color's declared domain"

      in_domain = put_in(design, [:frames, :main, :scales, :color, :domain], [7, 8])
      assert Validator.validate(in_domain) == :ok
    end

    test "a typed column no value of the domain can hold, through the style" do
      design = put_in(design(), [:sources, :cells, :types], %{k: :number})

      assert {:error,
              [{[:marks, 0, :style], {:outside_domain, :color, {:column, :k, :number}}} = e]} =
               Validator.validate(design)

      assert Validator.format(e) =~ "field :k is a :number column"
    end

    test "a typed column through a series channel, renamed by the mark's scales" do
      design =
        design(%{
          sources: %{cells: %{fields: [:x0, :x1, :k], types: %{k: :text}}},
          marks: [
            %{
              type: :line,
              data: :cells,
              channels: %{x: :x0, y: :x1, series: :k},
              scales: %{color: :shade}
            }
          ]
        })
        |> put_in([:frames, :main, :scales, :shade], %{kind: :ordinal, domain: [1, 2]})

      assert {:error,
              [{[:marks, 0, :channels, :series], {:outside_domain, :shade, {:column, :k, :text}}}]} =
               Validator.validate(design)
    end

    test "what is not decidable is not reported" do
      # A :category column may hold anything.
      assert :ok ==
               Validator.validate(put_in(design(), [:sources, :cells, :types], %{k: :category}))

      # An untyped field.
      assert :ok == Validator.validate(design())

      # A domain that holds one value of the type.
      typed = put_in(design(), [:sources, :cells, :types], %{k: :number})
      mixed = put_in(typed, [:frames, :main, :scales, :color, :domain], ["a", 1])
      assert :ok == Validator.validate(mixed)

      # An inferred domain.
      inferred = put_in(typed, [:frames, :main, :scales, :color, :domain], :auto)
      assert :ok == Validator.validate(inferred)

      # Rows read through transforms.
      transformed =
        update_in(typed, [:marks, Access.at(0)], fn mark ->
          Map.put(mark, :data, %{
            source: :cells,
            transforms: [%{op: :filter, field: :k, test: :eq, value: 1}]
          })
        end)

      assert :ok == Validator.validate(transformed)
    end

    test "a time column holds strings and numbers, so only atoms are out" do
      typed = put_in(design(), [:sources, :cells, :types], %{k: :time})
      assert :ok == Validator.validate(typed)

      atoms = put_in(typed, [:frames, :main, :scales, :color, :domain], [:a, :b])

      assert {:error, [{_path, {:outside_domain, :color, {:column, :k, :time}}}]} =
               Validator.validate(atoms)
    end
  end
end
