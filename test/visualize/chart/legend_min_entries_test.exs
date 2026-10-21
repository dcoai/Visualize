defmodule Visualize.Chart.LegendMinEntriesTest do
  # A legend is drawn from `min_entries` entries, decided at every realization: below the
  # minimum it is not drawn, has no extent and takes no margin (spec/14 §4.5, #861, D-223).
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Visualize.Chart
  alias Visualize.Chart.{Build, Compiled, Frame, Validator}
  alias Visualize.Chart.Builder.Editor
  alias Visualize.Chart.Frame.Legend

  @margin %{top: 10, right: 100, bottom: 10, left: 100}

  # A 400 × 300 frame whose legend explains an ordinal color scale over `domain`.
  defp design(legend, domain) do
    %{
      version: 3,
      sources: %{primary: %{fields: [:n, :v, :k]}},
      frames: %{
        main: %{
          kind: :cartesian,
          margin: @margin,
          scales: %{
            x: %{kind: :linear, domain: [0, 10]},
            y: %{kind: :linear, domain: [0, 10]},
            color: %{kind: :ordinal, domain: domain}
          },
          legend: Map.merge(%{scale: :color}, legend)
        }
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :n, y: :v}}]
    }
  end

  defp frame(legend, domain) do
    legend
    |> design(domain)
    |> Chart.from_map!()
    |> Frame.new(sources: %{primary: [%{n: 0, v: 1, k: "a"}]}, size: {400, 300})
  end

  defp domain(count), do: Enum.take(~w(alpha beta gamma), count)

  describe "drawn from min_entries entries (D-223)" do
    for {count, min, drawn?} <- [
          {0, 1, false},
          {1, 1, true},
          {2, 1, true},
          {0, 2, false},
          {1, 2, false},
          {2, 2, true}
        ] do
      test "#{count} entries at min_entries #{min} #{if drawn?, do: "are", else: "are not"} drawn" do
        frame = frame(%{min_entries: unquote(min)}, domain(unquote(count)))
        groups = Legend.generate(frame, :literal)
        extent = Frame.legend_extent(frame)

        if unquote(drawn?) do
          assert [%{children: children}] = groups
          assert length(children) == unquote(count)
          assert extent.height == (unquote(count) - 1) * 16 + 12
          assert extent.width > 0
        else
          assert groups == []
          assert extent == %{width: 0, height: 0}
          refute Frame.render(frame) =~ ~s(class="legend")
        end
      end

      test "#{count} entries at min_entries #{min}, a top legend in its margin, " <>
             "#{if drawn?, do: "grows", else: "leaves"} the margin" do
        frame =
          frame(
            %{min_entries: unquote(min), position: :top, inside: false},
            domain(unquote(count))
          )

        if unquote(drawn?),
          do: assert(frame.margin.top == 12 + 8),
          else: assert(frame.margin.top == @margin.top)
      end
    end

    test "the default is 1" do
      assert Frame.legend_extent(frame(%{}, domain(0))) == %{width: 0, height: 0}
      assert [_group] = Legend.generate(frame(%{}, domain(1)), :literal)
    end

    test "a side legend below the minimum asks nothing of a margin too narrow for it" do
      design =
        put_in(
          design(%{position: :right, inside: false, min_entries: 3}, domain(2)),
          [
            :frames,
            :main,
            :margin,
            :right
          ],
          4
        )

      frame = Frame.new(Chart.from_map!(design), size: {400, 300})
      assert frame.margin.right == 4
      assert Legend.generate(frame, :literal) == []

      # At its minimum the same legend cannot be fitted, as any side legend (§4.5).
      assert_raise ArgumentError, ~r/needs .* in the right margin, which is 4/, fn ->
        design
        |> put_in([:frames, :main, :legend, :min_entries], 2)
        |> Chart.from_map!()
        |> Frame.new(size: {400, 300})
      end
    end

    test "a legend of declared values counts its values" do
      values = fn list ->
        design(%{values: list, min_entries: 2}, domain(3))
        |> Chart.from_map!()
        |> Frame.new(size: {400, 300})
      end

      assert Legend.generate(values.(["up"]), :literal) == []
      assert [%{children: [_, _]}] = Legend.generate(values.(["up", "down"]), :literal)
    end

    test "the title is not an entry" do
      frame = frame(%{title: "Hosts", min_entries: 2}, domain(1))
      assert Legend.generate(frame, :literal) == []
    end

    test "a min_entries below 1 is an ArgumentError of Frame.new/2, for a chart not validated" do
      chart = Chart.from_map!(design(%{min_entries: 2}, domain(2)))

      frames =
        Map.new(chart.frames, fn {name, node} -> {name, put_in(node.legend.min_entries, 0)} end)

      assert_raise ArgumentError,
                   ~r/min_entries is a count of entries of at least 1, not 0/,
                   fn -> Frame.new(%{chart | frames: frames}, size: {400, 300}) end
    end
  end

  describe "decided at every realization (D-223, D-222)" do
    @size {300, 200}

    # A top legend in the margin over an inferred color scale, as a board cell's series.
    @live %{
      version: 3,
      sources: %{primary: %{fields: [:n, :v, :k]}},
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: 10, right: 20, bottom: 30, left: 40},
          scales: %{
            x: %{kind: :linear, domain: [0, 10]},
            y: %{kind: :linear, domain: [0, 10]},
            color: %{kind: :ordinal}
          },
          axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left}],
          legend: %{scale: :color, position: :top, inside: false, min_entries: 2}
        }
      },
      marks: [%{type: :line, data: :primary, channels: %{x: :n, y: :v, series: :k}}]
    }

    defp rows(count),
      do: %{primary: for(s <- 1..count, i <- 0..1, do: %{n: i * 5, v: s, k: "s#{s}"})}

    test "stepped from one series to three and back, the legend appears, then goes, and the margin follows" do
      {:ok, %{"main" => one}} = Chart.compile(@live, sources: rows(1), size: @size)
      assert one.margin.top == 10
      refute Compiled.svg(one, rows(1)) =~ ~s(class="legend")

      {_group, three} = Compiled.step(one, rows(3))
      assert three.margin.top == 12 + 8
      assert three.plot.height == one.plot.height - 10
      assert Compiled.svg(three, rows(3)) =~ ~s(class="legend")

      {_group, back} = Compiled.step(three, rows(1))
      assert back.margin == one.margin
      assert back.plot == one.plot
      assert Compiled.static(back) == Compiled.static(one)
      refute Compiled.svg(back, rows(1)) =~ ~s(class="legend")
    end
  end

  describe "the key (D-223)" do
    test "the validator takes a count at least 1 and rejects 0, a negative and a non-integer" do
      assert Validator.validate(design(%{min_entries: 1}, domain(2))) == :ok
      assert Validator.validate(design(%{min_entries: 3}, domain(2))) == :ok

      for {bad, type} <- [{0, :pos_integer}, {-1, :pos_integer}, {1.5, :integer}, {"2", :integer}] do
        assert {:error, [{[:frames, "main", :legend, :min_entries], {:type, ^type}}]} =
                 Validator.validate(design(%{min_entries: bad}, domain(2)))
      end

      assert {:error, [{_path, {:type, :pos_integer}} = error]} =
               Validator.validate(design(%{min_entries: 0}, domain(2)))

      assert Validator.format(error) =~ "a positive integer"
    end

    test "Build.legend/2 takes it" do
      assert %{frames: %{main: %{legend: %{scale: :color, min_entries: 2}}}} =
               Build.legend(:color, min_entries: 2)
    end

    test "the builder shows it on the legend's geometry tab, with its default" do
      html =
        render_component(&Editor.panel/1, %{
          kind: :legend,
          node: %{scale: "color"},
          facet: :geometry
        })

      keys =
        ~r/<span class="vis-builder-key">\s*(\w+)/
        |> Regex.scan(html)
        |> Enum.map(fn [_, key] -> key end)

      assert "min_entries" in keys
      assert html =~ ~s(name="min_entries")
    end

    test "it round-trips through JSON" do
      {:ok, chart} = Chart.from_map(design(%{min_entries: 2, position: :top}, domain(2)))
      {:ok, json} = Chart.to_json(chart)
      {:ok, back} = Chart.from_json(json)
      assert hd(Map.values(back.frames)).legend.min_entries == 2
    end
  end
end
