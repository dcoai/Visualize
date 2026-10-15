defmodule Visualize.Chart.SpellingMigrationTest do
  # #642 (spec/14 §9, §11.2, D-183): a stored document that holds a name this library
  # spelled in British English before — the `:color_safe` theme, the `$colors` tag, a
  # version 2 paint's `center` and a stop's `color` — reads as the same document written in
  # the American names, and draws byte for byte as it.
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.Theme, as: ChartTheme
  alias Visualize.Theme

  @rows [%{c: "ok", t: 0, v: 1}, %{c: "fail", t: 1, v: 3}]
  @size %{width: 200, height: 120}

  # spelling: allow — the old name, as a stored document holds it.
  @old_theme :colour_safe

  defp design(theme, range, style) do
    %{
      version: 3,
      theme: theme,
      sources: %{hosts: %{fields: [:c, :t, :v]}},
      styles: %{s: style},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{
            x: %{kind: :linear, domain: [0, 2]},
            y: %{kind: :linear, domain: [0, 4]},
            c: %{kind: :ordinal, domain: ["ok", "fail"], range: range}
          }
        }
      },
      marks: [
        %{type: :rect, data: :hosts, style: :s, channels: %{x0: :t, x1: 1, y0: 0, y1: :v}},
        %{
          type: :symbol,
          data: :hosts,
          channels: %{x: :t, y: :v},
          scales: %{color: :c},
          style: %{fill: {:field, :c}}
        }
      ]
    }
  end

  @range %{"ok" => :good, "fail" => :bad}
  @style %{fill: %{type: :solid, color: :good}}

  defp svg(chart) do
    {:ok, applied} = Chart.apply(chart, sources: %{hosts: @rows}, size: @size)
    Chart.render(applied)
  end

  test "the color-safe theme is read by its new name, from a map and from JSON" do
    new = Chart.from_map!(design(:color_safe, @range, @style))
    old = Chart.from_map!(design(@old_theme, @range, @style))
    assert old == new
    assert svg(old) == svg(new)

    {:ok, json} = Chart.to_json(new)
    old_json = String.replace(json, ~s("theme":"color_safe"), ~s("theme":"#{@old_theme}"))
    assert old_json != json
    assert {:ok, ^new} = Chart.from_json(old_json)
  end

  test "an inline theme's name and counterparts, and a theme document, read the new name" do
    inline = %{name: :house, dark: @old_theme, light: @old_theme}
    {:ok, read} = ChartTheme.from_map(%{theme: inline})
    assert read.dark == :color_safe and read.light == :color_safe

    assert ChartTheme.from_map(%{theme: @old_theme}) == {:ok, Theme.color_safe()}
  end

  test "a stored `$colors` range reads as `$colors` and draws the same" do
    chart = Chart.from_map!(design(:default, @range, @style))
    {:ok, json} = Chart.to_json(chart)
    assert json =~ ~s("$colors":)

    # spelling: allow — the tag as 0.6 wrote it.
    old_json = String.replace(json, ~s("$colors":), ~s("$colours":))
    assert {:ok, ^chart} = Chart.from_json(old_json)
  end

  test "a version 2 paint's `center` and a stop's `color` draw as version 3's words" do
    gradient = fn center_key, color_key ->
      %{
        :kind => :radial,
        center_key => [0.5, 0.5],
        stops: [%{:offset => 0, color_key => :good}, %{:offset => 1, color_key => :bad}]
      }
    end

    # spelling: allow — a version 2 document's keys.
    old = gradient.(:centre, :colour)
    new = gradient.(:center, :color)

    v2 = fn paint ->
      design(:default, @range, %{fill: {:paint, :g}})
      |> Map.put(:version, 2)
      |> Map.put(:defs, %{g: paint})
    end

    assert svg(Chart.from_map!(v2.(old))) == svg(Chart.from_map!(v2.(new)))
  end
end
