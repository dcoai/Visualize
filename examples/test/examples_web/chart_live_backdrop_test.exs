defmodule ExamplesWeb.ChartLiveBackdropTest do
  @moduledoc """
  A basemap is the page's backdrop (spec/14 §12.4, #476, D-120): on the Canvas backend
  the marathon's tiles sit in layers beneath the canvases, the dense course on a canvas
  over them, and the static and dynamic SVG over both, the attribution in the SVG so it
  reads over the data. The tiles are URLs in the markup; nothing is fetched.

  *Grandma's Marathon* (#783) has two fitted `:geo` frames, the course and the pack inset,
  so the page has a backdrop layer for each.
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.{Design, Marathon}
  alias ExamplesWeb.ChartLive

  @attribution "© OpenStreetMap contributors"
  @tile ~r{<image [^>]*href="https://tile\.openstreetmap\.org/\d+/\d+/\d+\.png"}

  defp page(backend) do
    {:ok, s} =
      ChartLive.mount(%{"chart" => "grandmas_marathon"}, %{}, %Phoenix.LiveView.Socket{})

    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => to_string(backend)}, s)
    s
  end

  # The markup, the canvas's base64 elided as the size test does: a regex over a long
  # attribute hits PCRE's match limit.
  defp html(s) do
    ChartLive.render(Map.put(s.assigns, :__changed__, %{}))
    |> Phoenix.LiveViewTest.rendered_to_string()
    |> String.replace(~r/data-binary="([^"]*)"/, fn match ->
      if match == ~s(data-binary=""), do: match, else: ~s(data-binary="…")
    end)
  end

  # One layer of the wrapper: the markup of each `<div class="<class>" …>…</div>`, in page
  # order. The layers hold one `<svg>` document each and no nested `<div>`.
  defp layers(h, class) do
    for [layer] <- Regex.scan(~r{<div[^>]*class="#{class}"[^>]*>.*?</div>}s, h), do: layer
  end

  defp at(h, needle) do
    {at, _} = :binary.match(h, needle)
    at
  end

  test "the Canvas backend stacks backdrop, canvas, static SVG and dynamic SVG, in that order" do
    s = page(:canvas)
    h = html(s)

    # A backdrop for each fitted frame: the course and the inset.
    backdrops = layers(h, "hybrid-backdrop-layer")
    assert length(backdrops) == 2
    [static] = layers(h, "hybrid-static-layer")
    dynamics = layers(h, "hybrid-dynamic-layer")
    assert dynamics != []

    # The z-order the markup states and the order it is written in agree.
    assert Enum.all?(backdrops, &(&1 =~ "z-index: 0;"))
    assert static =~ "z-index: 2;"
    assert Enum.all?(dynamics, &(&1 =~ "z-index: 3;"))
    [canvas_tag] = Regex.run(~r/<div[^>]*id="plot-canvas-course"[^>]*>/, h)
    assert canvas_tag =~ "z-index: 1;"
    assert canvas_tag =~ ~s(data-binary="…")

    assert at(h, "hybrid-backdrop-layer") < at(h, ~s(id="plot-canvas-course"))
    assert at(h, ~s(id="plot-canvas-course")) < at(h, "hybrid-static-layer")
    assert at(h, "hybrid-static-layer") < at(h, "hybrid-dynamic-layer")

    # The tiles are the backdrops alone; the attribution is over the canvas.
    backdrop = Enum.join(backdrops)
    dynamic = Enum.join(dynamics)
    assert length(Regex.scan(@tile, backdrop)) > 0
    refute backdrop =~ @attribution
    refute static =~ "<image"
    refute dynamic =~ "<image"
    assert dynamic =~ @attribution

    # The course is on the canvas, not in either SVG layer: the runners are SVG.
    refute static =~ "mark-line"
    refute dynamic =~ "mark-line"
    assert dynamic =~ "mark-circle"
  end

  test "the course is drawn on the canvas, and its stream draws" do
    hybrid = Design.hybrid(Marathon, [])
    course = Enum.find(hybrid.plots, &(to_string(&1.name) == "course"))

    records = course.canvas |> Base.decode64!() |> Visualize.Backend.CanvasBinary.Decoder.decode()
    assert Enum.count(records, &(&1 == :stroke)) > 0
    assert length(Regex.scan(@tile, course.backdrop)) > 0
    refute hybrid.static =~ "<image"
  end

  test "on SVG the page draws one document with the tiles first and the attribution" do
    h = html(page(:svg))
    assert h =~ @attribution
    assert at(h, "mark-tiles") < at(h, "mark-line")
    refute h =~ "hybrid-backdrop-layer"
  end

  test "a chart without a basemap has no backdrop layer" do
    {:ok, s} = ChartLive.mount(%{"chart" => "line"}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => "canvas"}, s)
    refute html(s) =~ "hybrid-backdrop-layer"
  end
end
