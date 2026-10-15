defmodule Visualize.Chart.FilledLineMigrationTest do
  @moduledoc """
  The filled line's migration (spec/14 §5.6, §9, #659, D-172): a version 2 line whose style
  gave a fill drew the area under it; the 2 -> 3 step gives it an `:area` beneath it with
  the same channels and that fill, and pins the series colour of every mark it moves, so the
  stored design draws as before. A version 3 line's fill is not drawn.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Frame, Migration}
  alias Visualize.IR.Element

  @rows [%{t: 0, v: 4, k: "a"}, %{t: 1, v: 9, k: "a"}, %{t: 2, v: 2, k: "a"}]

  defp design(version, marks) do
    %{
      version: version,
      sources: %{p: %{fields: [:t, :v, :k]}},
      styles: %{under: %{fill: "#cde", fill_opacity: 0.4, curve: :step_after, opacity: 0.9}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{x: %{kind: :linear, domain: [0, 2]}, y: %{kind: :linear, domain: [0, 10]}}
        }
      },
      marks: marks
    }
  end

  defp filled, do: %{type: :line, data: :p, channels: %{x: :t, y: :v, series: :k}, style: :under}
  defp plain, do: %{type: :line, data: :p, channels: %{x: :t, y: :v}}

  test "a filled line gets an area beneath it, and the marks it moves keep their colour" do
    {:ok, v3} = Migration.migrate(design(2, [filled(), plain()]))

    assert [area, line, other] = v3.marks

    assert area == %{
             type: :area,
             data: :p,
             channels: %{x: :t, y: :v, series: :k},
             style: %{
               fill: %{type: :solid, color: "#cde", opacity: 0.4},
               curve: %{type: :step_after},
               opacity: 0.9
             }
           }

    # The line was the frame's first mark and is now its second: it keeps series 1.
    assert line.style == [:under, %{stroke: %{type: :solid, color: {:series, 1}}}]
    assert other.style == [%{stroke: %{type: :solid, color: {:series, 2}}}]
  end

  test "the area draws what the filled line drew under it, and the lines their colours" do
    one = Map.update!(filled(), :channels, &Map.delete(&1, :series))
    chart = Chart.from_map!(design(2, [one, plain()]))
    frame = Frame.new(chart, sources: %{p: @rows}, size: {300, 200})
    %Element{children: children} = Frame.generate(frame, sources: %{p: @rows})
    [area, line, other] = Enum.filter(children, &match?(%{style: %{class: "mark " <> _}}, &1))

    assert area.style.fill == "#cde" and area.style.fill_opacity == 0.4
    [path] = area.children

    # The fill is the line's, not the series' colour an area would take as its paint.
    refute Map.has_key?(path.style, :fill)
    # The area from the line down to the y scale's zero (y 150), in the line's step curve.
    assert [{:M, +0.0, 90.0}, {:H, 120.0}, {:V, 15.0} | _] = path.path.commands
    assert {:V, 150.0} in path.path.commands

    assert line.style.fill == :none
    assert line.style.stroke == "var(--vis-series-1, #3b6fa8)"
    assert other.style.stroke == "var(--vis-series-2, #d9730d)"
  end

  test "with a series channel the area paints each series as any area does" do
    chart = Chart.from_map!(design(2, [filled()]))
    frame = Frame.new(chart, sources: %{p: @rows}, size: {300, 200})
    %Element{children: children} = Frame.generate(frame, sources: %{p: @rows})
    [area, _line] = Enum.filter(children, &match?(%{style: %{class: "mark " <> _}}, &1))
    [path] = area.children
    assert path.style.fill == "var(--vis-series-1, #3b6fa8)"
    assert path.attrs["data-series"] == "a"
  end

  test "a line with no fill, or fill none, and every version 3 design, is not rewritten" do
    unfilled = design(2, [plain(), Map.put(plain(), :style, %{fill: :none})])
    {:ok, v3} = Migration.migrate(unfilled)
    assert length(v3.marks) == 2

    {:ok, same} = Migration.migrate(design(3, [filled(), plain()]))
    assert length(same.marks) == 2
  end

  test "a role style's fill counts, read through the theme's palette" do
    {:ok, v3} = Migration.migrate(design(2, [Map.put(plain(), :style, :bad)]))
    assert [%{type: :area, style: %{fill: %{color: :bad}}}, %{type: :line}] = v3.marks
  end
end
