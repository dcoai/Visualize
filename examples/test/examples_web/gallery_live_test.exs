defmodule ExamplesWeb.GalleryLiveTest do
  @moduledoc """
  The gallery never renders a chart in its own process (#397): a dead render carries
  placeholders where the cache is empty, a connected mount starts a task per preview
  whose result arrives by message, and the cache then answers every later mount.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Examples.Previews
  alias ExamplesWeb.GalleryLive

  @endpoint ExamplesWeb.Endpoint
  @size {320, 220}

  setup do
    Previews.clear()
    :ok
  end

  defp html(socket) do
    Phoenix.LiveViewTest.rendered_to_string(
      GalleryLive.render(Map.put(socket.assigns, :__changed__, %{}))
    )
  end

  # The gallery's own list, as its socket carries it.
  defp charts do
    {:ok, socket} = GalleryLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{})
    socket.assigns.charts
  end

  test "every design of the gallery is a card in the grid, the streaming ones included (#403)" do
    listed = for {module, _slug} <- charts(), into: MapSet.new(), do: module
    assert MapSet.new(Examples.Charts.Templates.gallery_modules()) == listed
    assert Examples.Charts.ScrollingSeries in listed
    assert Examples.Charts.IncrementalLine in listed

    html = build_conn() |> get("/") |> html_response(200)

    for {module, slug} <- charts() do
      assert html =~ ~s(href="/chart/#{slug}"), slug
      assert html =~ module.title(), slug
    end
  end

  test "a dead render has a placeholder per chart and no chart document" do
    charts = charts()
    html = build_conn() |> get("/") |> html_response(200)
    assert length(Regex.scan(~r/<div class="chart-preview-pending"/, html)) == length(charts)
    refute html =~ ~s(role="img")
    # Nothing was rendered on the way: the cache is still empty.
    for {module, _slug} <- charts, do: assert(Previews.get(module, @size) == :miss)
  end

  test "a connected mount starts a task per preview; each arrives by message and fills its card; the cache then hits" do
    charts = charts()
    n = length(charts)

    # A connected socket: the tasks are started from this process, so their results
    # come here, exactly as they would reach the view.
    {:ok, socket} = GalleryLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{transport_pid: self()})
    assert socket.assigns.previews == %{}
    assert length(Regex.scan(~r/<div class="chart-preview-pending"/, html(socket))) == n

    socket =
      Enum.reduce(1..n, socket, fn _, s ->
        assert_receive {ref, {:preview, module, svg}}, 30_000
        assert is_reference(ref) and is_atom(module) and svg =~ ~s(role="img")
        {:noreply, s} = GalleryLive.handle_info({ref, {:preview, module, svg}}, s)
        s
      end)

    filled = html(socket)
    refute filled =~ ~s(<div class="chart-preview-pending")
    assert length(Regex.scan(~r/role="img"/, filled)) == n

    # Every preview is cached now: a dead render carries them all, and a connected mount
    # starts no task.
    for {module, _slug} <- charts, do: assert({:ok, _} = Previews.get(module, @size))
    again = build_conn() |> get("/") |> html_response(200)
    refute again =~ ~s(<div class="chart-preview-pending")
    assert length(Regex.scan(~r/role="img"/, again)) == n
    # A task started by `Task.Supervisor.async_nolink/2` is monitored by the caller, so a
    # mount that started none added no monitor here: asserted at once, with nothing to wait
    # for, where a 200 ms `refute_receive` had only shown that nothing came quickly (D-148).
    {:monitors, before} = Process.info(self(), :monitors)
    {:ok, warm} = GalleryLive.mount(%{}, %{}, %Phoenix.LiveView.Socket{transport_pid: self()})
    assert map_size(warm.assigns.previews) == n
    {:monitors, now} = Process.info(self(), :monitors)
    assert now -- before == []
  end

  test "the cache renders once and remembers; clear forgets" do
    assert Previews.get(Examples.Charts.LineChart, @size) == :miss
    svg = Previews.render(Examples.Charts.LineChart, @size)
    assert {:ok, ^svg} = Previews.get(Examples.Charts.LineChart, @size)
    assert Previews.render(Examples.Charts.LineChart, @size) == svg
    Previews.clear()
    assert Previews.get(Examples.Charts.LineChart, @size) == :miss
  end
end
