defmodule ExamplesWeb.ChartLiveNavTest do
  @moduledoc """
  A chart page steps through the gallery (spec/14 §12.6, #484): Previous / Next beside the
  back link, labeled with the neighbors' titles in the gallery's order and wrapping;
  a step is a patch, which loads the new chart on the mount's path in the same view —
  a run stopped, the width kept, the reader's backend where the new chart offers it (#501); the arrow keys follow the
  links unless focus is in a form field; and the index and the chart page read one list.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  alias Examples.{Frames, Gallery}
  alias ExamplesWeb.{ChartLive, GalleryLive}

  @endpoint ExamplesWeb.Endpoint

  defp page(slug) do
    {:ok, s} = ChartLive.mount(%{"chart" => slug}, %{}, %Phoenix.LiveView.Socket{})
    # The mount's own params, as the view receives them after mounting: nothing to load.
    {:noreply, same} = ChartLive.handle_params(%{"chart" => slug}, "/chart/#{slug}", s)
    assert same == s
    s
  end

  defp html(s),
    do:
      Phoenix.LiveViewTest.rendered_to_string(
        ChartLive.render(Map.put(s.assigns, :__changed__, %{}))
      )

  # A step: the patch the view asked for, then the params the patch brings.
  defp step(s, to) do
    "/chart/" <> slug = to
    {:noreply, s} = ChartLive.handle_params(%{"chart" => slug}, to, %{s | redirected: nil})
    s
  end

  defp patched_to(%{redirected: {:live, :patch, %{to: to}}}), do: to
  defp patched_to(_socket), do: nil

  defp nav_link(html, rel) do
    [tag] = Regex.run(~r/<a[^>]*rel="#{rel}"[^>]*>.*?<\/a>/s, html)
    [_, href] = Regex.run(~r/href="([^"]+)"/, tag)
    assert tag =~ ~s(data-phx-link="patch"), "#{rel} is a patch, not a page load"
    {href, tag}
  end

  defp index_of(slug), do: Enum.find_index(Gallery.charts(), fn {_m, s} -> s == slug end)

  test "a chart's Previous and Next are its neighbors in the gallery's order, by title" do
    charts = Gallery.charts()
    {_module, slug} = Enum.at(charts, 4)
    {prev_module, prev_slug} = Enum.at(charts, 3)
    {next_module, next_slug} = Enum.at(charts, 5)

    html = html(page(slug))
    {prev_href, prev_tag} = nav_link(html, "prev")
    {next_href, next_tag} = nav_link(html, "next")

    assert prev_href == "/chart/#{prev_slug}"
    assert prev_tag =~ "Previous: #{prev_module.title()}"
    assert next_href == "/chart/#{next_slug}"
    assert next_tag =~ "Next: #{next_module.title()}"
    # Beside the back link, which still goes to the index.
    assert html =~ ~s(<a href="/" class="back-link">)
  end

  test "the order wraps: the first chart's Previous is the last, the last's Next the first" do
    {first_module, first} = List.first(Gallery.charts())
    {last_module, last} = List.last(Gallery.charts())

    {href, tag} = nav_link(html(page(first)), "prev")
    assert href == "/chart/#{last}" and tag =~ last_module.title()

    {href, tag} = nav_link(html(page(last)), "next")
    assert href == "/chart/#{first}" and tag =~ first_module.title()

    assert Gallery.neighbors(first) == {{last_module, last}, Enum.at(Gallery.charts(), 1)}
  end

  test "Next patches: the same view loads the next chart and keeps the page's own state" do
    s = page("bar")
    # The page's state: a measured width (#434), a color style, the drawer open.
    {:noreply, s} = ChartLive.handle_event("resize", %{"width" => 500}, s)
    {:noreply, s} = ChartLive.handle_event("change_palette", %{"palette" => "winter"}, s)
    {:noreply, s} = ChartLive.handle_event("drawer_toggle", %{}, s)

    {next, _tag} = nav_link(html(s), "next")
    {next_module, next_slug} = Enum.at(Gallery.charts(), index_of("bar") + 1)
    assert next == "/chart/#{next_slug}"

    s = step(s, next)
    assert s.assigns.slug == next_slug and s.assigns.module == next_module
    assert s.assigns.title == next_module.title()
    assert s.assigns.width == 500
    assert s.assigns.current_palette == :winter
    assert s.assigns.drawer_open
    # The new chart is drawn at the width the page already knew.
    assert s.assigns.still_frame != nil

    html = html(s)
    assert html =~ "<h2>#{next_module.title()}</h2>"
    {prev, _tag} = nav_link(html, "prev")
    assert prev == "/chart/bar"
  end

  test "a step away from a running chart stops its run and falls back from a backend the new chart lacks" do
    s = page("incremental_line")
    assert s.assigns.run_backend == :svg
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => "incremental"}, s)
    assert s.assigns.run_backend == :incremental
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    %{renderer: renderer, running: true} = s.assigns.run
    assert is_pid(renderer)
    monitor = Process.monitor(renderer)
    {:noreply, s} = ChartLive.handle_event("run_compare", %{}, s)
    %Task{pid: compare} = s.assigns.compare_task
    compare_monitor = Process.monitor(compare)

    s = step(s, "/chart/bar")

    assert_receive {:DOWN, ^monitor, :process, ^renderer, _}
    assert_receive {:DOWN, ^compare_monitor, :process, ^compare, _}
    refute s.assigns.run.running
    assert s.assigns.run.renderer == nil
    assert s.assigns.run_ticks == 0 and s.assigns.run_frame == nil
    assert s.assigns.compare_task == nil and s.assigns.compare == nil
    # The bar chart offers no Incremental (#432), so it opens on SVG (#501), and no window.
    refute :incremental in Frames.backends(Examples.Charts.BarChart)
    assert s.assigns.run_backend == :svg
    assert s.assigns.run_scroll == nil
    assert s.assigns.run.data_rate == 20

    # A late frame of the old run is stale for the new chart.
    {:noreply, after_late} = ChartLive.handle_info({:frame, make_ref(), %{plots: []}}, s)
    assert after_late.assigns.run_frame == nil
  end

  # Every chart offers Canvas, so a chosen Canvas holds across the whole gallery: Next from
  # each chart is the next in the index's order, wrapping, and keeps it (#501). One test a
  # chart (#735), where one test had walked the gallery with Next; the walk is these steps.
  describe "Next from each chart is the next in the gallery's order, and keeps a chosen Canvas" do
    charts = Gallery.charts()

    for {{_module, slug}, {next_module, next_slug}} <-
          Enum.zip(charts, tl(charts) ++ [hd(charts)]) do
      test slug, do: assert_next(unquote(slug), unquote(next_module), unquote(next_slug))
    end
  end

  defp assert_next(slug, next_module, next_slug) do
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => "canvas"}, page(slug))
    {next, _tag} = nav_link(html(s), "next")
    assert next == "/chart/#{next_slug}"
    s = step(s, next)
    assert s.assigns.slug == next_slug and s.assigns.module == next_module
    assert :canvas in Frames.backends(next_module), next_slug
    assert s.assigns.run_backend == :canvas, next_slug
  end

  test "Previous and Next keep the backend the reader chose where the chart offers it (#501)" do
    s = page("bar")
    assert s.assigns.run_backend == :svg
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => "canvas"}, s)
    {prev, _tag} = nav_link(html(s), "prev")
    assert step(s, prev).assigns.run_backend == :canvas

    # Incremental is a streaming design's own: Next from one keeps it on the next stream
    # and falls back to SVG on the first chart without it.
    s = page("scrolling_series")
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => "incremental"}, s)

    s =
      Enum.reduce_while(1..length(Gallery.charts()), s, fn _, s ->
        {next, _tag} = nav_link(html(s), "next")
        s = step(s, next)

        if :incremental in Frames.backends(s.assigns.module) do
          assert s.assigns.run_backend == :incremental, s.assigns.slug
          {:cont, s}
        else
          assert s.assigns.run_backend == :svg, s.assigns.slug
          {:halt, s}
        end
      end)

    assert s.assigns.run_backend == :svg
  end

  test "the arrow keys step as Previous and Next do, except in a form field or with a modifier" do
    s = page("bar")
    {prev_module, prev_slug} = List.last(Gallery.charts())
    {_next_module, next_slug} = Enum.at(Gallery.charts(), 1)

    {:noreply, right} = ChartLive.handle_event("key", %{"key" => "ArrowRight"}, s)
    assert patched_to(right) == "/chart/#{next_slug}"
    {:noreply, left} = ChartLive.handle_event("key", %{"key" => "ArrowLeft"}, s)
    assert patched_to(left) == "/chart/#{prev_slug}"
    assert step(left, patched_to(left)).assigns.title == prev_module.title()

    for params <- [
          %{"key" => "ArrowRight", "field" => true, "modified" => false},
          %{"key" => "ArrowLeft", "field" => false, "modified" => true},
          %{"key" => "ArrowUp"},
          %{"key" => "a"}
        ] do
      {:noreply, still} = ChartLive.handle_event("key", params, s)
      assert patched_to(still) == nil, inspect(params)
    end

    {:noreply, plain} =
      ChartLive.handle_event("key", %{"key" => "ArrowRight", "field" => false}, s)

    assert patched_to(plain) == "/chart/#{next_slug}"

    # The page listens on the window, and the layout says what the server cannot see.
    assert html(s) =~ ~s(phx-window-keyup="key")
    layout = File.read!("lib/examples_web/layouts.ex")
    assert layout =~ "metadata: {"
    assert layout =~ ~s|closest("input, select, textarea, [contenteditable]")|
    assert layout =~ "e.altKey || e.ctrlKey || e.metaKey || e.shiftKey"
  end

  test "one list: the index and the chart pages show the same charts in the same order" do
    {:ok, gallery} = GalleryLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    assert gallery.assigns.charts == Gallery.charts()
    assert ChartLive.charts() == Map.new(Gallery.charts(), fn {m, s} -> {s, m} end)
    assert length(Enum.uniq_by(Gallery.charts(), &elem(&1, 1))) == length(Gallery.charts())

    index = build_conn() |> get("/") |> html_response(200)
    hrefs = for [_, slug] <- Regex.scan(~r{<a href="/chart/([a-z_]+)"}, index), do: slug
    # So Next, which goes from each chart to the next of this order and from the last to
    # the first (above), visits every chart of the index in its order, and wraps.
    assert hrefs == Enum.map(Gallery.charts(), &elem(&1, 1))
  end

  test "a patch to a slug the gallery does not list goes to the index" do
    s = page("bar")
    {:noreply, s} = ChartLive.handle_params(%{"chart" => "nope"}, "/chart/nope", s)
    assert {:live, :redirect, %{to: "/"}} = s.redirected
    assert_raise ArgumentError, fn -> Gallery.neighbors("nope") end
  end
end
