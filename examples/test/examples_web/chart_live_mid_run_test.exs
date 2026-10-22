defmodule ExamplesWeb.ChartLiveMidRunTest do
  @moduledoc """
  Every page control that feeds a run's options reaches a running renderer (spec/14 §12.6,
  #796, work item #798): changed mid-run, the next frame drawn reflects it, on SVG and on
  a canvas backend, and the run's tick and data go on without a restart.

  The controls are the ones `run_opts/2` reads — the theme, the hex size, the width, the
  reader's motion preference, the data rate and the backend — each changed on one or two
  gallery charts, never the whole gallery in one test (spec/12 §6, #735).
  """
  use ExUnit.Case, async: true

  alias Examples.{Renderer, Themes}
  alias ExamplesWeb.ChartLive

  defp page(slug, backend) do
    {:ok, s} = ChartLive.mount(%{"chart" => slug}, %{}, %Phoenix.LiveView.Socket{})
    {:noreply, s} = ChartLive.handle_event("set_backend", %{"backend" => to_string(backend)}, s)
    {:noreply, s} = ChartLive.handle_event("run_start", %{}, at(s, 0))
    settled(s)
  end

  # The page's clock stopped at `ms` (D-148): every instant the page reads is this one.
  defp at(s, ms),
    do: Phoenix.Component.assign(s, run_clock: &System.convert_time_unit(ms, :millisecond, &1))

  defp later(s, ms), do: at(s, s.assigns.run_clock.(:millisecond) + ms)

  # The frame in flight, answered and taken by the page.
  defp settled(s) do
    id = s.assigns.run.render_id
    assert id != nil, "no frame is in flight"
    assert_receive {:frame, ^id, frame}
    {:noreply, s} = ChartLive.handle_info({:frame, id, frame}, s)
    s
  end

  # A tick `ms` after the last on the page's stopped clock: its frame asked, not yet taken.
  defp tick(s, ms) do
    {:noreply, s} = ChartLive.handle_info(:run_tick, later(s, ms))
    s
  end

  defp ticked(s, ms), do: s |> tick(ms) |> settled()

  defp event(s, name, params) do
    {:noreply, s} = ChartLive.handle_event(name, params, s)
    s
  end

  # The markup, the canvas's base64 elided.
  defp html(s) do
    ChartLive.render(Map.put(s.assigns, :__changed__, %{}))
    |> Phoenix.LiveViewTest.rendered_to_string()
    |> String.replace(~r/data-binary="[^"]*"/, ~s(data-binary=""))
  end

  # Whether a frame paints `hex`: an SVG frame names it, a binary canvas carries its three
  # bytes after a fill or a stroke opcode.
  defp paints?(%{svg: svg}, hex) when is_binary(svg), do: svg =~ hex

  defp paints?(%{plots: plots}, "#" <> hex) do
    rgb = Base.decode16!(hex, case: :mixed)
    Enum.any?(plots, &(:binary.match(Base.decode64!(&1.canvas), rgb) != :nomatch))
  end

  # What a frame draws: an SVG frame's geometry and paint — every attribute but the
  # document's ids, which each render mints afresh, and its description, which a run
  # writes with the summary it was prepared with — or a canvas frame's plots.
  defp drawn(%{svg: svg}) when is_binary(svg) do
    svg
    |> String.replace(~r/<desc[^>]*>.*?<\/desc>/s, "")
    |> String.replace(~r/vis-[0-9a-z]+/, "vis-id")
  end

  defp drawn(%{plots: plots}), do: Enum.map(plots, & &1.canvas)

  defp first_series(key), do: hd(Themes.theme(key).series)

  # The y scale's easing as the run's renderer holds it after its last frame: where it is
  # shown and where it goes (spec/14 §12.5).
  defp eased_y(s) do
    [{_name, compiled}] = Renderer.state(s.assigns.run.renderer).compiled
    Map.fetch!(compiled.eased, "y")
  end

  # The frame a fresh render draws at the page's options: Stop, and the still frame is
  # the chart at the run's tick, prepared afresh (#362).
  defp still_after_stop(s), do: event(s, "run_stop", %{}).assigns.still_frame

  for backend <- [:svg, :canvas] do
    describe "on #{backend}" do
      @backend backend

      test "a theme picked mid-run recolors the next frame; the tick and the renderer go on" do
        s = page("line", @backend) |> ticked(100)
        renderer = s.assigns.run.renderer
        ticks = s.assigns.run_ticks
        assert paints?(s.assigns.run_frame, first_series("default"))

        s = event(s, "theme", %{"theme" => "dark"}) |> ticked(50)

        assert s.assigns.run.running and s.assigns.run.renderer == renderer
        assert s.assigns.run_ticks == ticks + 1
        assert paints?(s.assigns.run_frame, first_series("dark"))
        refute paints?(s.assigns.run_frame, first_series("default"))
        # The page's own furniture is the new theme's from that frame: a canvas run's
        # static layer is drawn in its text color, an SVG frame carries its own.
        assert html(s) =~ Themes.theme("dark").text
      end

      test "a frame asked before the pick is never shown: the next one is the new theme's" do
        s = page("line", @backend) |> ticked(100) |> tick(50)
        stale = s.assigns.run.render_id
        shown = s.assigns.run_frame

        s = event(s, "theme", %{"theme" => "sunset"})
        assert_receive {:frame, ^stale, old}
        {:noreply, s} = ChartLive.handle_info({:frame, stale, old}, s)
        assert s.assigns.run_frame == shown

        s = ticked(s, 50)
        assert paints?(s.assigns.run_frame, first_series("sunset"))
      end

      test "a hex size changed mid-run draws the next frame at that size" do
        s = page("hexbin", @backend) |> ticked(100)
        s = event(s, "change_hex_radius", %{"hex_radius" => "9"}) |> ticked(50)

        assert s.assigns.run.running
        # The hexbin eases nothing, so the run's frame is exactly what a fresh render of
        # the chart at its tick and its new size draws.
        assert drawn(s.assigns.run_frame) == drawn(still_after_stop(s))
      end

      test "a width measured mid-run draws the next frame, and the page's furniture, at it" do
        s = page("line", @backend) |> ticked(100)
        s = event(s, "resize", %{"width" => 400}) |> ticked(50)
        {w, h} = Examples.Charts.Design.fitted(Examples.Gallery.module("line"), 400)
        markup = html(s)

        case @backend do
          :svg ->
            assert s.assigns.run_frame.svg =~ ~s(width="#{w}")

          :canvas ->
            [plot] = s.assigns.run_frame.plots
            assert plot.box.width == w
            assert markup =~ "width: #{w}px; height: #{h}px;"
            assert s.assigns.run_state.width == w
        end
      end

      test "less motion asked for mid-run reaches the next frame's easing" do
        # Two runs of the line in step; one is told mid-run that the reader asks for less
        # motion. Its y scale is then at its target on every frame, the other's eases.
        sized = %{"width" => 700, "reduced_motion" => false}
        full = page("line", @backend) |> event("resize", sized) |> ticked(100)
        reduce = page("line", @backend) |> event("resize", sized) |> ticked(100)

        reduce = event(reduce, "resize", %{sized | "reduced_motion" => true})
        assert reduce.assigns.motion == :reduce

        {full, reduce} =
          Enum.reduce(1..6, {full, reduce}, fn _, {f, r} -> {ticked(f, 50), ticked(r, 50)} end)

        assert reduce.assigns.run_ticks == full.assigns.run_ticks
        # The easing reads the page's stopped clock (#921), so where each y scale stands is
        # the ticks' and not the test's speed: the full run's is still on its way.
        %{shown: shown, target: target} = eased_y(full)
        assert shown != target
        assert %{shown: ^target, target: ^target} = eased_y(reduce)
        refute drawn(reduce.assigns.run_frame) == drawn(full.assigns.run_frame)
        # Under :reduce the run draws what the still draws: the target, never mid-transition.
        assert drawn(reduce.assigns.run_frame) == drawn(still_after_stop(reduce))
      end

      test "a data rate changed mid-run advances the next frame's tick at it" do
        s = page("line", @backend) |> ticked(100)
        ticks = s.assigns.run_ticks
        s = event(s, "run_data_rate", %{"data_rate" => "40"}) |> ticked(100)
        # 100 ms at 40 a second is four ticks; at the 20 it started at, two.
        assert s.assigns.run_ticks == ticks + 4
      end
    end
  end

  test "a backend chosen mid-run draws the next frame on it, with the theme picked before" do
    s = page("line", :svg) |> ticked(100)
    s = event(s, "theme", %{"theme" => "dark"}) |> ticked(50)
    renderer = s.assigns.run.renderer

    s = event(s, "run_backend", %{"backend" => "canvas"}) |> ticked(50)

    assert Renderer.backend(renderer) == :canvas
    assert %{svg: nil, plots: [_]} = s.assigns.run_frame
    assert paints?(s.assigns.run_frame, first_series("dark"))
  end
end
