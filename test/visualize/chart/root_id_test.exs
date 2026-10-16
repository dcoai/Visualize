defmodule Visualize.Chart.RootIdTest do
  @moduledoc """
  #712, D-188: a chart's root takes its id from the host (spec/14 §4.7). Two charts of one
  title and description share a content-derived id, and with it the automatic dark-mode
  rule scoped to it; given `id:` each has its own, and its rule reaches only its own root.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Designs

  defp applied, do: Designs.apply(hd(Designs.names()))

  defp root_id(svg), do: hd(Regex.run(~r/^<svg[^>]* id="([^"]+)"/, svg, capture: :all_but_first))

  # The selectors the root's dark-mode rules are scoped to.
  defp scoped(svg),
    do: ~r/\n  (#[^ ]+) \{/ |> Regex.scan(svg, capture: :all_but_first) |> List.flatten()

  test "two alike charts given their own ids keep their own ids and their own rules" do
    a = Chart.render(applied(), root: true, id: "chart-a")
    b = Chart.render(applied(), root: true, id: "chart-b")

    assert root_id(a) == "chart-a" and root_id(b) == "chart-b"
    assert a =~ ~s(<title id="chart-a-title">) and a =~ ~s(aria-labelledby="chart-a-title")
    assert b =~ ~s(<desc id="chart-b-desc">) and b =~ ~s(aria-describedby="chart-b-desc")

    assert scoped(a) == ["#chart-a"]
    assert scoped(b) == ["#chart-b"]
    refute a =~ "chart-b" or b =~ "chart-a"
  end

  test "without an id two alike charts share one, and one's rule names the other's root" do
    a = Chart.render(applied(), root: true)
    b = Chart.render(applied(), root: true, color_scheme: false)

    assert "vis-" <> _ = root_id(a)
    assert root_id(a) == root_id(b)
    assert scoped(a) == ["#" <> root_id(b)]
  end

  test "an id is the root's with no title or description to name" do
    root = Visualize.IR.Element.root(10, 10, id: "bare")
    assert root.attrs.id == "bare"
    refute Map.has_key?(root.attrs, :aria_labelledby)
  end
end
