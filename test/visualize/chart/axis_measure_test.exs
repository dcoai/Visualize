defmodule Visualize.Chart.AxisMeasureTest do
  # An axis's measure (spec/14 §4.4, D-138): ticks scaled into the display unit with its
  # symbol, a title by the label rule where the ticks cannot say the unit, and the
  # validator's checks of the code and the pair.
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Frame, Validator}

  defp design(axis, opts \\ []) do
    %{
      version: 3,
      sources: %{primary: %{fields: [:n, :v]}},
      labels: Keyword.get(opts, :labels, []),
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{
            x: %{kind: :linear, domain: [0, 10]},
            y: %{
              kind: Keyword.get(opts, :kind, :linear),
              domain: Keyword.get(opts, :domain, [0, 1500])
            }
          },
          axes: [Map.merge(%{scale: :y, side: Keyword.get(opts, :side, :left), ticks: 4}, axis)]
        }
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :n, y: :v}}]
    }
  end

  defp render(design, rows \\ [%{n: 0, v: 0}, %{n: 10, v: 1500}]) do
    {:ok, chart} = Chart.from_map(design)
    chart |> Frame.new(sources: %{primary: rows}, size: {400, 300}) |> Frame.render()
  end

  defp tick_labels(svg) do
    Regex.scan(~r/<text dy="0.32em"[^>]*>([^<]*)<\/text>/, svg) |> Enum.map(&Enum.at(&1, 1))
  end

  defp titles(svg) do
    Regex.scan(~r/<text class="label"[^>]*>([^<]*)<\/text>/, svg) |> Enum.map(&Enum.at(&1, 1))
  end

  describe "ticks in the display unit" do
    test "0–1500 ms reads in seconds with the symbol, and no title repeats it" do
      svg = render(design(%{measure: %{unit: "ms"}}))
      assert tick_labels(svg) == ["0 s", "0.5 s", "1 s", "1.5 s"]
      assert titles(svg) == []
    end

    test "a domain under a second stays in milliseconds; a quantity alone is its base unit" do
      assert tick_labels(render(design(%{measure: %{unit: "ms"}}, domain: [0, 900]))) ==
               ["0 ms", "200 ms", "400 ms", "600 ms", "800 ms"]

      assert tick_labels(
               render(design(%{measure: %{quantity: :information}}, domain: [0, 3.0e6]))
             ) ==
               ["0 MB", "1 MB", "2 MB", "3 MB"]
    end

    test "an inferred domain moves its display unit with the data" do
      measure = %{measure: %{unit: "ms"}}
      small = render(design(measure, domain: :auto), [%{n: 0, v: 0}, %{n: 1, v: 600}])
      large = render(design(measure, domain: :auto), [%{n: 0, v: 0}, %{n: 1, v: 6000}])
      assert List.last(tick_labels(small)) == "600 ms"
      assert List.last(tick_labels(large)) == "6 s"
    end

    test "prefix and unit wrap the scaled label as they wrap any" do
      assert hd(tick_labels(render(design(%{measure: %{unit: "ms"}, prefix: "≈"})))) == "≈0 s"
    end

    test "an explicit format wins, unscaled, and the axis titles its unit instead" do
      svg = render(design(%{measure: %{unit: "ms"}, format: ",d"}))
      assert tick_labels(svg) == ["0", "500", "1,000", "1,500"]
      assert titles(svg) == ["ms"]
    end
  end

  describe "the axis says its measure once (the label rule)" do
    test "a count's ticks carry no unit, so its annotation is the title" do
      svg = render(design(%{measure: %{unit: "{request}"}}, domain: [0, 90_000]))
      assert tick_labels(svg) == ["0", "20k", "40k", "60k", "80k"]
      assert titles(svg) == ["request"]
    end

    test "else the quantity names the axis; nothing says nothing" do
      assert titles(render(design(%{measure: %{quantity: :count}}))) == ["count"]
      assert titles(render(design(%{measure: %{unit: "1", quantity: :ratio}}))) == ["ratio"]
      assert titles(render(design(%{measure: %{}}))) == []
      assert titles(render(design(%{}))) == []
    end

    test "a label the design anchors at the axis is the title, and none is added" do
      label = %{anchor: {:axis, :y}, text: "Requests"}
      svg = render(design(%{measure: %{unit: "{request}"}}, labels: [label]))
      assert titles(svg) == ["Requests"]
    end

    test "the title sits where an {:axis, s} label would, on every side" do
      for side <- [:left, :right, :top, :bottom] do
        via_measure = render(design(%{measure: %{quantity: :count}}, side: side))

        via_label =
          render(design(%{}, side: side, labels: [%{anchor: {:axis, :y}, text: "count"}]))

        [measured] = Regex.run(~r/<text class="label"[^>]*>count<\/text>/, via_measure)
        [labelled] = Regex.run(~r/<text class="label"[^>]*>count<\/text>/, via_label)
        assert measured == labelled, "#{side}"
      end
    end

    test "the title is inside the axis's group, counter-translated to plot coordinates" do
      svg = render(design(%{measure: %{quantity: :count}}, side: :right))

      assert svg =~
               ~r/<g class="axis axis-right" transform="translate\(340,0\)">.*<g transform="translate\(-340,0\)"><text class="label"/s
    end
  end

  describe "validation (spec/14 §10.1)" do
    test "a code that does not read and a pair that disagrees are faults at their keys" do
      assert {:error,
              [
                {[:frames, :main, :axes, 0, :measure, :unit],
                 {:unit, "sec", {:unknown_atom, "sec"}}}
              ]} =
               Validator.validate(design(%{measure: %{unit: "sec"}}))

      assert {:error,
              [
                {[:frames, :main, :axes, 0, :measure, :quantity], {:quantity, :duration, "By"}} =
                  error
              ]} =
               Validator.validate(design(%{measure: %{unit: "By", quantity: :duration}}))

      assert Validator.format(error) =~ ~s(unit "By" does not measure :duration)
    end

    test "a quantity not in the list is the enumeration's fault alone" do
      assert {:error, [{[:frames, :main, :axes, 0, :measure, :quantity], {:enum, _}}]} =
               Validator.validate(design(%{measure: %{quantity: :weight}}))
    end

    test "a measure round-trips through JSON" do
      design = design(%{measure: %{unit: "{request}/s", quantity: :frequency}})
      {:ok, chart} = Chart.from_map(design)
      {:ok, json} = Chart.to_json(chart)
      {:ok, back} = Chart.from_json(json)

      assert hd(hd(Map.values(back.frames)).axes).measure == %{
               unit: "{request}/s",
               quantity: :frequency
             }
    end
  end
end
