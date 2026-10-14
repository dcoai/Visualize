defmodule Visualize.Hooks.CrosshairTest do
  @moduledoc """
  `Visualize.Hooks.Crosshair.attrs/3` — the arrays the server writes once (spec/10 §13.2,
  D-76) — and the `CrosshairHook` source (spec/10 §13.3).
  """
  use ExUnit.Case, async: true

  alias Visualize.Chart
  alias Visualize.Chart.Frame
  alias Visualize.Hooks
  alias Visualize.Hooks.Crosshair

  @rows [
    %{t: 0, v: 4, k: "a"},
    %{t: 1, v: 9, k: "a"},
    %{t: 2, v: 2, k: "a"},
    %{t: 0, v: 7, k: "b"},
    %{t: 2, v: 5, k: "b"},
    %{t: 3, v: 1, k: "b"},
    %{t: 1, v: nil, k: "b"}
  ]
  @sources %{primary: @rows}

  defp frame(marks, kind \\ :cartesian) do
    chart =
      Chart.from_map!(%{
        version: 2,
        sources: %{primary: %{fields: [:t, :v, :k]}},
        frames: %{
          main: %{
            kind: kind,
            margin: %{top: 10, right: 30, bottom: 10, left: 40},
            scales: %{
              x: %{kind: :linear, domain: [0, 3]},
              y: %{kind: :linear, domain: [0, 10]},
              color: %{kind: :ordinal}
            }
          }
        },
        marks: marks
      })

    Frame.new(chart, sources: @sources, size: {340, 220})
  end

  describe "attrs/3" do
    test "one series: the distinct xs ascending, the ys parallel, the plot and the size" do
      attrs =
        Crosshair.attrs(
          frame([%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]),
          @sources
        )

      assert attrs == %{
               "data-xs" => "[0,90,180,270]",
               "data-ys" => "[[120,20,160,180]]",
               "data-plot" => "40,10,270,200",
               "data-size" => "340,220",
               "data-vis-hover" => ~s({"stroke":"#333333","stroke-width":"2"})
             }
    end

    test "a series channel gives one array per series in order of first appearance, null gaps" do
      attrs =
        Crosshair.attrs(
          frame([%{type: :line, data: :primary, channels: %{x: :t, y: :v, series: :k}}]),
          @sources
        )

      assert attrs["data-xs"] == "[0,90,180,270]"
      assert attrs["data-ys"] == "[[120,20,160,null],[60,null,100,180]]"
    end

    test "the first row wins where a series has two rows at one x" do
      sources = %{primary: [%{t: 0, v: 4, k: "a"}, %{t: 0, v: 8, k: "a"}]}
      frame = frame([%{type: :circle, data: :primary, channels: %{x: :t, y: :v}}])
      assert Crosshair.attrs(frame, sources)["data-ys"] == "[[120]]"
    end

    test ":mark picks the mark; attrs/2 is the first" do
      marks = [
        %{type: :rule, data: :primary, channels: %{x: :t}},
        %{type: :circle, data: :primary, channels: %{x: :t, y: :v}}
      ]

      frame = frame(marks)
      assert Crosshair.attrs(frame, @sources, mark: 2)["data-xs"] == "[0,90,180,270]"
      assert_raise ArgumentError, ~r/x and y channels/, fn -> Crosshair.attrs(frame, @sources) end

      assert_raise ArgumentError, ~r/no mark 3/, fn ->
        Crosshair.attrs(frame, @sources, mark: 3)
      end
    end

    test "the markers' style is the palette's :hover, a design's own winning (#638)" do
      chart =
        Chart.from_map!(%{
          version: 2,
          sources: %{primary: %{fields: [:t, :v]}},
          styles: %{hover: %{stroke: :warning, stroke_width: 1.5, stroke_dasharray: [2, 1]}},
          frames: %{
            main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}
          },
          marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
        })

      frame = Frame.new(chart, sources: @sources, size: {340, 220})

      assert Crosshair.attrs(frame, @sources)["data-vis-hover"] ==
               ~s({"stroke":"#{Visualize.Theme.resolve(Visualize.Theme.default(), :warning, :literal)}",) <>
                 ~s("stroke-width":"1.5","stroke-dasharray":"2 1"})
    end

    test "an unbound source gives empty arrays; a facet frame raises" do
      frame = frame([%{type: :line, data: :primary, channels: %{x: :t, y: :v}}])
      assert Crosshair.attrs(frame, %{})["data-xs"] == "[]"
      assert Crosshair.attrs(frame, %{})["data-ys"] == "[[]]"

      facet =
        Chart.from_map!(%{
          version: 2,
          sources: %{primary: %{fields: [:t, :v, :k]}},
          frames: %{
            main: %{
              kind: :facet,
              scales: %{x: %{kind: :linear}, y: %{kind: :linear}},
              facet: %{by: :k}
            }
          },
          marks: [%{type: :line, data: :primary, channels: %{x: :t, y: :v}}]
        })
        |> Frame.new(sources: @sources, size: {340, 220})

      assert_raise ArgumentError, ~r/facet/, fn -> Crosshair.attrs(facet, @sources) end
    end
  end

  describe "CrosshairHook executed (#638)" do
    @describetag :js

    test "each marker is its series' fill with data-vis-hover laid over it; absent, the fill alone" do
      attrs = %{
        "data-xs" => "[0,10]",
        "data-ys" => "[[5,6],[7,8]]",
        "data-plot" => "0,0,100,100",
        "data-crosshair-colors" => ~s(["#111111","#222222"]),
        "data-vis-hover" => ~s({"stroke":"#333333","stroke-width":"2"})
      }

      assert {:ok, %{"report" => r}} =
               Visualize.JsHooks.run("""
               const look = (hook) => hook.markers.map((m) =>
                 ['fill', 'stroke', 'stroke-width'].map((name) => m.getAttribute(name)));
               const el = Stub.markup('div', Object.assign({id: 'x'}, #{Jason.encode!(attrs)}), [Stub.markup('svg')]);
               const hook = Stub.mount(CrosshairHook, el);
               const report = {styled: look(hook)};
               delete el.dataset.visHover;
               hook.updated();
               report.dropped = look(hook);
               Stub.done(report);
               """)

      assert r["styled"] == [["#111111", "#333333", "2"], ["#222222", "#333333", "2"]]
      assert r["dropped"] == [["#111111", nil, nil], ["#222222", nil, nil]]
    end
  end

  describe "js_hook/0" do
    test "the overlay is appended to the body on mount and removed on destroy" do
      js = Crosshair.js_hook()
      assert js =~ "export const CrosshairHook = {"
      assert js =~ "document.createElementNS('http://www.w3.org/2000/svg', tag)"
      assert js =~ "this.overlay.style.pointerEvents = 'none';"
      assert js =~ "document.body.appendChild(this.overlay);"

      assert js =~
               "if (this.overlay.parentNode) this.overlay.parentNode.removeChild(this.overlay);"

      refute js =~ "this.el.appendChild"
    end

    test "four listeners are bound once, kept and removed with the same references (D-47)" do
      js = Crosshair.js_hook()
      # The four pointer listeners and the sync bus's one (spec/10 §4.3).
      assert length(Regex.scan(~r/\.bind\(this\)/, js)) == 5
      assert js =~ "this.onSync = this.handleSync.bind(this);"
      assert js =~ "VisualizeSync.detach(this);"

      for name <- ~w(mousemove mouseleave touchmove touchend) do
        assert js =~ ~r/this\.el\.addEventListener\('#{name}', this\.on\w+[,)]/
        assert js =~ ~r/this\.el\.removeEventListener\('#{name}', this\.on\w+\)/
      end
    end

    test "the arrays are read from the attributes on mount and on updated()" do
      js = Crosshair.js_hook()
      assert js =~ "this.xs = JSON.parse(ds.xs || '[]');"
      assert js =~ "this.ys = JSON.parse(ds.ys || '[]');"
      assert js =~ "(ds.plot || '0,0,0,0').split(',').map(parseFloat)"
      assert js =~ "this.size = ds.size ? ds.size.split(',').map(parseFloat) : null;"
      assert js =~ "updated() {\n    this.read();"
      assert js =~ "if (this.markers.length !== this.ys.length) {"
    end

    test "the nearest x is a binary search taking the lower of two equidistant neighbours" do
      js = Crosshair.js_hook()
      assert js =~ "const mid = (lo + hi) >> 1;"
      assert js =~ "if (lo > 0 && x - xs[lo - 1] <= xs[lo] - x) return lo - 1;"
    end

    test "the pointer maps through the container's rectangle and the chart's viewBox" do
      js = Crosshair.js_hook()
      assert js =~ "this.overlay.setAttribute('viewBox', `0 0 ${width} ${height}`);"
      assert js =~ "x: (clientX - rect.left) * width / rect.width - this.plot.left,"
      assert js =~ "if (p.x < 0 || p.x > this.plot.width || p.y < 0 || p.y > this.plot.height) {"
      assert js =~ "marker.setAttribute('visibility', 'hidden');"
    end

    test "the documented defaults and the one event, pushed only on an index change" do
      js = Crosshair.js_hook()
      assert js =~ "this.eventName = ds.crosshairEvent || null;"
      assert js =~ "this.color = ds.crosshairColor || '#666';"
      # A hover received from the sync group draws but never pushes (spec/10 §13.4).
      assert js =~ "if (local && this.eventName && index !== this.lastIndex) {"
      assert js =~ "this.pushEvent(this.eventName, { index });"
      assert length(String.split(js, "pushEvent(")) == 2
    end

    test "the bundle carries the hook once and exports it" do
      js = Hooks.js_code()
      assert length(String.split(js, "export const CrosshairHook = {")) == 2
      assert js =~ ~r/export default \{[^}]*\bCrosshairHook\b/
    end
  end
end
