defmodule ExamplesWeb.ChartLiveDesignTest do
  @moduledoc """
  A design chart's page shows the design (#318): the Canvas code sample opens with the
  Build calls that fold to the design the split takes, and a panel prints the design as
  data. A chart that is not a design shows neither.
  """
  use ExUnit.Case, async: true

  alias ExamplesWeb.ChartLive

  defp page(slug, backend) do
    {:ok, s} = ChartLive.mount(%{"chart" => slug}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => to_string(backend)}, s)

    # The code is highlighted (#506): read the code blocks' text, without the spans.
    Phoenix.LiveViewTest.rendered_to_string(
      ChartLive.render(Map.put(s.assigns, :__changed__, %{}))
    )
    |> String.replace(~r/<\/?span[^>]*>/, "")
  end

  test "the Build calls of a sample are everything before its apply line" do
    build = ChartLive.design_build_code(Examples.Charts.LineChart)
    assert build =~ "import Visualize.Chart.Build"
    assert build =~ "line(:points, %{x: :x, y: :y}, style: :wave)"
    assert String.ends_with?(build, "])\n")
    refute build =~ "Visualize.Chart.apply("
    refute build =~ "Visualize.Chart.render("
  end

  test "a design chart's Canvas sample opens with the design, and the page shows the design as data" do
    html = page("line", :canvas)
    assert html =~ "The design (Build), then the canvas rendering (the split)"
    # The design comes first, the split after it, in one sample.
    {build_at, _} = :binary.match(html, "import Visualize.Chart.Build")
    {split_at, _} = :binary.match(html, "Visualize.Chart.compile(applied, ceiling: 1)")
    assert build_at < split_at

    assert html =~ "The design (data)"
    assert html =~ "meta: %{name: &quot;Line Chart&quot;"
    assert html =~ "marks: ["
    assert html =~ "to_json/1</code> is the same map as JSON"
  end

  test "the SVG tab keeps the module's sample, and the data panel is there too" do
    html = page("line", :svg)
    assert html =~ "The design (Build), then the SVG rendering"
    assert html =~ "The design is the thing to copy"
    assert html =~ "The design (data)"
    refute html =~ "the canvas rendering (the split)"
  end

  test "every chart of the gallery is a design, so every Canvas tab is the split (#335)" do
    for {slug, module} <- ExamplesWeb.ChartLive.charts() do
      assert Examples.Charts.Design.design?(module), slug
    end

    html = page("hexbin", :canvas)
    assert html =~ "The design (data)"
    assert html =~ "the canvas rendering (the split)"
  end
end
