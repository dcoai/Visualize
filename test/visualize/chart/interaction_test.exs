defmodule Visualize.Chart.InteractionTest do
  @moduledoc """
  The `interaction` key (spec/14 §2.9, #466): a sync group is rendered as data — the
  group and the x mapping a hook needs — on the frame it reads, and nowhere without one.
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.{Build, Frame}
  alias Visualize.Hooks.Crosshair

  defp design(x, extra \\ %{}) do
    Map.merge(
      %{
        version: 2,
        interaction: %{sync: "dash-42"},
        sources: %{s: %{fields: [:t, :v]}},
        frames: %{main: %{kind: :cartesian, scales: %{x: x, y: %{kind: :linear}}}},
        marks: [%{type: :line, data: :s, channels: %{x: :t, y: :v}}]
      },
      extra
    )
  end

  defp applied(design, rows, size) do
    {:ok, applied} = Chart.apply(design, sources: %{s: rows}, size: size)
    applied
  end

  defp rows, do: for(t <- 0..100//10, do: %{t: t, v: t * 2})

  test "a linear x renders its group and its mapping on the frame's group" do
    applied = applied(design(%{kind: :linear, domain: [0, 100]}), rows(), {600, 200})
    svg = Chart.render(applied, root: true)

    # Margin left 40, plot 540 wide: the domain's ends sit at 40 and 580 of a 600-wide chart.
    assert svg =~ ~s(data-vis-sync="dash-42")
    assert svg =~ ~s(data-vis-sync-x="0,100,40,580,600")

    assert Frame.sync_attrs(applied.frame) == %{
             "data-vis-sync" => "dash-42",
             "data-vis-sync-x" => "0,100,40,580,600"
           }
  end

  test "a time x is in milliseconds since the Unix epoch" do
    t0 = ~U[2026-10-08 14:00:00Z]
    rows = for m <- 0..10, do: %{t: DateTime.add(t0, m * 60), v: m}
    applied = applied(design(%{kind: :time}), rows, {300, 200})

    ms = DateTime.to_unix(t0, :millisecond)

    assert Frame.sync_attrs(applied.frame)["data-vis-sync-x"] ==
             "#{ms},#{ms + 600_000},40,280,300"
  end

  test "the crosshair's attributes carry the group, so a container in the group needs no markup" do
    applied = applied(design(%{kind: :linear, domain: [0, 100]}), rows(), {600, 200})
    attrs = Crosshair.attrs(applied.frame, applied.sources)

    assert attrs["data-vis-sync"] == "dash-42"
    assert attrs["data-vis-sync-x"] == "0,100,40,580,600"
  end

  test "in a design of several frames only the frame read carries it, at its own offset" do
    frames = %{
      left: %{kind: :cartesian, box: [0, 0, 0.5, 1], scales: %{x: %{kind: :linear}}},
      right: %{
        kind: :cartesian,
        box: [0.5, 0, 0.5, 1],
        scales: %{x: %{kind: :linear, domain: [0, 100]}, y: %{kind: :linear}}
      }
    }

    design =
      design(%{kind: :linear}, %{
        frames: frames,
        interaction: %{sync: "dash-42", frame: :right},
        marks: [%{type: :line, data: :s, frame: :right, channels: %{x: :t, y: :v}}]
      })

    applied = applied(design, rows(), {800, 200})
    svg = Chart.render(applied)

    # The right frame starts at 400; its plot is 400 - 40 - 20 = 340 wide.
    assert [_one] = Regex.scan(~r/data-vis-sync="dash-42"/, svg)
    assert svg =~ ~r/class="frame frame-right"[^>]*data-vis-sync-x="0,100,440,780,800"/
    assert Frame.sync_attrs(applied.frames.left) == %{}
  end

  test "no sync, no attribute" do
    design = design(%{kind: :linear}) |> Map.delete(:interaction)
    applied = applied(design, rows(), {600, 200})

    refute Chart.render(applied, root: true) =~ "data-vis-"
    refute Map.has_key?(Crosshair.attrs(applied.frame, applied.sources), "data-vis-sync")
  end

  test "the builder writes the key, and the design round-trips through JSON" do
    assert Build.interaction(sync: "dash-42", frame: :main) ==
             %{interaction: %{sync: "dash-42", frame: :main}}

    chart = Chart.from_map!(design(%{kind: :linear}))
    {:ok, json} = Chart.to_json(chart)
    assert Chart.from_json(json) == {:ok, chart}
  end
end
