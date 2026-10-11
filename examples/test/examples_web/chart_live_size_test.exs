defmodule ExamplesWeb.ChartLiveSizeTest do
  @moduledoc """
  A gallery chart is capped at its design size (spec/10 §10.2, #457): the page takes the
  measured width up to the module's `size/0` width and the height at its aspect, so a
  narrow container shrinks a chart and a wide one never grows it. Every plot's canvas, the
  hybrid wrapper and the SVG layers agree, and a multi-frame design's plots stay inside
  its wrapper. And a still frame reaches an incremental canvas, which takes nothing from
  the markup (spec/14 §12.6).
  """
  use ExUnit.Case, async: true

  alias Examples.Charts.Design
  alias ExamplesWeb.ChartLive

  defp page(slug, backend) do
    {:ok, s} = ChartLive.mount(%{"chart" => slug}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => to_string(backend)}, s)
    s
  end

  defp resized(s, width) do
    # The socket is not connected here, so the still frame renders in place (#362).
    {:noreply, s} = ChartLive.handle_event("resize", %{"width" => width, "height" => 0}, s)
    s
  end

  # A connected page at `width` on `backend`, its still frame settled. Connected, a still
  # frame renders in a task and each change — the mount, the backend, the resize —
  # terminates the render before it (#362), so the chart is rendered once, at the size the
  # test asserts, rather than three times in this process (D-148).
  defp connected(slug, backend, width) do
    socket = %Phoenix.LiveView.Socket{transport_pid: self()}
    {:ok, s} = ChartLive.mount(%{"chart" => slug}, %{}, socket)
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => to_string(backend)}, s)
    {:noreply, s} = ChartLive.handle_event("resize", %{"width" => width, "height" => 0}, s)
    %Task{ref: ref} = s.assigns.still_task
    assert_receive {^ref, {:still, _frame, _state, _design, _access} = still}, 30_000
    {:noreply, s} = ChartLive.handle_info({ref, still}, s)
    s
  end

  # The markup, the canvas's base64 elided: a regex over a long attribute hits PCRE's
  # match limit and silently finds nothing.
  defp html(s) do
    ChartLive.render(Map.put(s.assigns, :__changed__, %{}))
    |> Phoenix.LiveViewTest.rendered_to_string()
    |> String.replace(~r/data-binary="[^"]*"/, ~s(data-binary=""))
  end

  defp num(string), do: string |> Float.parse() |> elem(0)

  # The hybrid wrapper's box.
  defp wrapper(h) do
    [_, w, ht] =
      Regex.run(
        ~r/class="hybrid-wrapper" style="position: relative; width: ([\d.]+)px; height: ([\d.]+)px;"/,
        h
      )

    {num(w), num(ht)}
  end

  # Every plot's element: its offset in the wrapper, its data-width/height and its canvas's.
  defp plots(h) do
    for [_, tag, canvas] <- Regex.scan(~r/(<div[^>]*id="plot-[^"]*"[^>]*>)\s*(<canvas[^>]*>)/, h) do
      attr = fn source, name ->
        [_, v] = Regex.run(~r/#{name}[=:] ?"?([\d.]+)/, source)
        num(v)
      end

      %{
        top: attr.(tag, "top"),
        left: attr.(tag, "left"),
        width: attr.(tag, "data-width"),
        height: attr.(tag, "data-height"),
        canvas: {attr.(canvas, " width"), attr.(canvas, " height")}
      }
    end
  end

  # Every `<svg>` root on the page: its width and height attributes.
  defp svgs(h) do
    for [tag] <- Regex.scan(~r/<svg\b[^>]*>/, h),
        [_, w] <- [Regex.run(~r/\swidth="([\d.]+)"/, tag)],
        [_, ht] <- [Regex.run(~r/\sheight="([\d.]+)"/, tag)],
        do: {num(w), num(ht)}
  end

  test "a 600x400 chart in a wide container is drawn at 600x400: wrapper, plot and SVG" do
    s = page("line", :canvas)
    assert Design.size(Examples.Charts.LineChart, []) == {600, 400}

    h = s |> resized(1336) |> html()
    assert wrapper(h) == {600.0, 400.0}

    assert [%{width: 600.0, height: 400.0, top: +0.0, left: +0.0, canvas: {600.0, 400.0}}] =
             plots(h)

    assert {600.0, 400.0} in svgs(h)
    refute Enum.any?(svgs(h), fn {w, ht} -> w > 600 or ht > 400 end)
  end

  test "a 600x400 chart in a narrow container shrinks to 400x267" do
    s = page("line", :canvas)
    h = s |> resized(400) |> html()
    assert wrapper(h) == {400.0, 267.0}
    assert [%{width: 400.0, height: 267.0, canvas: {400.0, 267.0}}] = plots(h)
    assert {400.0, 267.0} in svgs(h)

    # On SVG the one document is at that size too.
    s = page("line", :svg) |> resized(400)
    assert {400.0, 267.0} in svgs(html(s))
  end

  test "a width past the cap draws nothing new" do
    s = page("line", :canvas) |> resized(1336)
    assert {:noreply, ^s} = ChartLive.handle_event("resize", %{"width" => 1600, "height" => 0}, s)
  end

  test "a multi-frame design's plots stay inside the wrapper, capped and shrunk" do
    for slug <- ["load", "context", "spectrum"], width <- [1336, 420] do
      module = ChartLive.charts()[slug]
      {dw, dh} = Design.size(module, [])
      h = html(connected(slug, :canvas, width))

      {ww, wh} = wrapper(h)
      expected = min(width, dw)
      assert ww == expected, "#{slug} at #{width}: wrapper #{ww} wide, expected #{expected}"
      assert wh == round(expected * dh / dw)

      plots = plots(h)
      assert length(plots) > 1, "#{slug} is a design of several frames"

      for p <- plots do
        assert p.canvas == {p.width, p.height}
        assert p.left >= 0 and p.top >= 0
        assert p.left + p.width <= ww, "#{slug} at #{width}: a plot overruns the wrapper's width"
        assert p.top + p.height <= wh, "#{slug} at #{width}: a plot overruns the wrapper's height"
      end

      for {w, ht} <- svgs(h), do: assert(w <= ww and ht <= wh)
    end
  end

  # One test a chart, so the gallery's charts run as async cases rather than one 86-case
  # loop at the edge of its timeout (#520).
  for {slug, module} <- ChartLive.charts() do
    test "#{slug}, on every backend, is no larger than its size/0 after a large resize" do
      slug = unquote(slug)
      module = unquote(module)

      for backend <- Examples.Frames.backends(module) do
        {dw, dh} = Design.size(module, [])
        h = html(connected(slug, backend, 2400))
        where = "#{slug} on #{backend}"

        for {w, ht} <- svgs(h) do
          assert w <= dw and ht <= dh, "#{where}: an <svg> at #{w}x#{ht} past #{dw}x#{dh}"
        end

        if backend != :svg do
          {ww, wh} = wrapper(h)
          assert {ww, wh} == {dw / 1, dh / 1}, "#{where}: wrapper #{ww}x#{wh}, design #{dw}x#{dh}"

          for p <- plots(h) do
            assert p.canvas == {p.width, p.height}, "#{where}: canvas and element disagree"
            assert p.left + p.width <= ww and p.top + p.height <= wh, "#{where}: plot outside"
          end
        end
      end
    end
  end

  test "a still frame on Incremental is pushed to its canvas as a full record, without a seq" do
    s = page("scrolling_series", :incremental)
    frame = s.assigns.still_frame
    ref = make_ref()

    s =
      Phoenix.Component.assign(s,
        still_task: %Task{ref: ref, pid: self(), owner: self(), mfa: {:erlang, :apply, 2}}
      )

    {:noreply, s} =
      ChartLive.handle_info({ref, {:still, frame, s.assigns.still_state, "design", nil}}, s)

    assert [["canvas_incremental", payload]] = Phoenix.LiveView.Utils.get_push_events(s)
    assert payload.mode == "full" and is_binary(payload.binary)
    assert payload.frame == hd(frame.plots).name
    refute Map.has_key?(payload, :seq)

    # A binary canvas takes its data from the markup: nothing is pushed for it.
    s = page("line", :canvas)
    ref = make_ref()

    s =
      Phoenix.Component.assign(s,
        still_task: %Task{ref: ref, pid: self(), owner: self(), mfa: {:erlang, :apply, 2}}
      )

    {:noreply, s} =
      ChartLive.handle_info(
        {ref, {:still, s.assigns.still_frame, s.assigns.still_state, "d", nil}},
        s
      )

    assert Phoenix.LiveView.Utils.get_push_events(s) == []
  end

  test "while a run is drawing, a still frame pushes nothing over its stream" do
    s = page("scrolling_series", :incremental)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, s)
    frame = s.assigns.still_frame
    ref = make_ref()

    s =
      Phoenix.Component.assign(s,
        still_task: %Task{ref: ref, pid: self(), owner: self(), mfa: {:erlang, :apply, 2}}
      )

    {:noreply, s} =
      ChartLive.handle_info({ref, {:still, frame, s.assigns.still_state, "design", nil}}, s)

    refute Enum.any?(Phoenix.LiveView.Utils.get_push_events(s), fn [n, p] ->
             n == "canvas_incremental" and not Map.has_key?(p, :seq)
           end)

    {:noreply, _s} = ChartLive.handle_event("run_stop", %{}, s)
  end
end
