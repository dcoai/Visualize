defmodule Visualize.Chart.StyleSitesTest do
  @moduledoc """
  #766, D-196: a field binding is read where a datum is. The guard walks the schema's own
  list of style sites (`Visualize.Chart.Schema.style_sites/0`): a site with a datum draws
  a bound style per row on SVG, the JSON canvas and the binary canvas; a site without one
  refuses a bound value, inline or through a design style the
  stack names, while a stack's field entry lays nothing there (§3.6). A site the schema
  gains fails here until it is classified below.
  """
  use ExUnit.Case, async: true

  alias Visualize.Backend.CanvasBinary.Decoder
  alias Visualize.Chart
  alias Visualize.Chart.Schema

  @rows [%{x: 0, y: 3, v: "a"}, %{x: 1, y: 5, v: "b"}]
  # The two rows' fills, through the frame's color scale.
  @fills ["#ff0000", "#0000ff"]

  defp design do
    %{
      version: 3,
      sources: %{t: %{fields: [:x, :y, :v]}},
      frames: %{
        main: %{
          kind: :cartesian,
          scales: %{
            color: %{kind: :ordinal, domain: ["a", "b"], range: @fills},
            x: %{kind: :band, domain: [0, 1]},
            y: %{kind: :band, domain: [3, 5]}
          }
        }
      },
      marks: [%{type: :rect, data: :t, channels: %{x0: :x, x1: :x, y0: :y, y1: :y}}]
    }
  end

  # Each site of the schema: where its style goes in the design, and whether it draws from
  # a row. The rect's fill is the plain series color, so a bound fill seen is the site's.
  @sites %{
    {:mark, :style} => {:row, &__MODULE__.mark/2},
    {:mark_label, :style} => {:row, &__MODULE__.mark_label/2},
    {:choice, :style} => {:row, &__MODULE__.choice/2},
    {:label, :style} => {:none, &__MODULE__.label/2},
    {:axis, :style} => {:none, &__MODULE__.axis/2},
    {:legend, :style} => {:none, &__MODULE__.legend/2}
  }

  def mark(d, s), do: put_in(d, [:marks, Access.at(0), :style], s)

  def mark_label(d, s),
    do: put_in(d, [:marks, Access.at(0), :label], %{text: ["L"], anchor: :middle, style: s})

  def choice(d, s) do
    choose = %{
      type: :choose,
      data: :t,
      on: :v,
      channels: %{x: :x, y: :y},
      cases: %{a: %{type: :circle, style: s}, b: %{type: :circle, style: s}}
    }

    put_in(d, [:marks, Access.at(0)], choose)
  end

  def label(d, s),
    do: Map.put(d, :labels, [%{anchor: {:frame, :top_left}, text: ["T"], style: s}])

  def axis(d, s), do: put_in(d, [:frames, :main, :axes], [%{scale: :x, side: :bottom, style: s}])
  def legend(d, s), do: put_in(d, [:frames, :main, :legend], %{scale: :color, style: s})

  # The binding in its three spellings at a site: a value in an inline node, an entry of
  # the stack naming a style per row, and a design style the stack names.
  defp spellings(design) do
    styles = %{a: %{fill: "#ff0000"}, b: %{fill: "#0000ff"}, bound: %{fill: {:field, :v}}}
    design = Map.put(design, :styles, styles)

    [
      inline: {design, %{fill: {:field, :v}}},
      entry: {design, [{:field, :v}]},
      named: {put_in(design, [:styles, :derived], %{extends: :bound}), [:derived]}
    ]
  end

  test "every style site of the schema is classified here" do
    assert Enum.sort(Map.keys(@sites)) == Enum.sort(Schema.style_sites())
  end

  for {site, {:row, _place}} <- @sites do
    test "#{inspect(site)} reads a binding per row on every backend" do
      {:row, place} = @sites[unquote(Macro.escape(site))]

      for {spelling, {design, style}} <- spellings(design()) do
        design = place.(design, style)
        label = inspect({unquote(Macro.escape(site)), spelling})
        assert {:ok, applied} = Chart.apply(design, sources: %{t: @rows}, size: {200, 100}), label

        svg = Chart.render(applied, resolve: :literal)
        json = Chart.render(applied, backend: :canvas, format: :json)
        records = Decoder.decode(Chart.render(applied, backend: :canvas, format: :binary))

        for fill <- @fills do
          assert svg =~ ~s(fill="#{fill}"), label
          assert json =~ ~s("set_fillStyle","args":["#{fill}"]), label
        end

        # Text has no binary record (spec/09 §4.5): a label's stream is drawn without it,
        # every other site's fills are the rows'.
        drawn = for {:style, %{fill: {r, g, b, _a}}} <- records, do: {r, g, b}

        if unquote(Macro.escape(site)) != {:mark_label, :style} do
          assert {255, 0, 0} in drawn and {0, 0, 255} in drawn, label
        end
      end
    end
  end

  for {{kind, _key} = site, {:none, _place}} <- @sites do
    test "#{inspect(site)} has no datum: a bound value is refused, an entry lays nothing" do
      {:none, place} = @sites[unquote(Macro.escape(site))]
      spellings = spellings(design())

      # A value bound in a node, inline or through a style the stack names, has nothing
      # to read: a fault at its path, never a crash at render.
      for spelling <- [:inline, :named] do
        {design, style} = spellings[spelling]
        assert {:error, errors} = Chart.from_map(place.(design, style)), inspect(spelling)
        assert [{_path, {:invalid_for, unquote(kind)}}] = errors, inspect({spelling, errors})
      end

      # A field entry names a style per row, and with no row it lays nothing (§3.6): the
      # site draws as its stack without it, on every backend.
      {design, entry} = spellings[:entry]
      {:ok, bound} = Chart.apply(place.(design, entry), sources: %{t: @rows}, size: {200, 100})
      {:ok, plain} = Chart.apply(place.(design, []), sources: %{t: @rows}, size: {200, 100})

      for opts <- [[], [backend: :canvas, format: :json], [backend: :canvas, format: :binary]] do
        assert Chart.render(bound, opts) == Chart.render(plain, opts), inspect(opts)
      end
    end
  end

  test "the minimal design of #766: a mark label's fill per row" do
    design =
      mark_label(design(), %{fill: {:field, :v}})
      |> put_in([:marks, Access.at(0), :type], :rect)

    {:ok, applied} = Chart.apply(design, sources: %{t: @rows}, size: {200, 100})
    svg = Chart.render(applied, resolve: :literal)

    assert [_, _] =
             Regex.scan(~r/<text class="mark-label"[^>]*fill="(#ff0000|#0000ff)"/, svg)
  end
end
