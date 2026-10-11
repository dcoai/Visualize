defmodule Visualize.Hooks.KeyboardTest do
  @moduledoc """
  A chart's points reached from the keyboard (spec/10 §17, spec/14 §21.5, #558): the
  attributes `attrs/1` writes from an applied chart, and `KeyboardHook` executed under node
  over them (spec/12 §6) — one tab stop, arrows between points and series, Home and End,
  a live-region readout, the focus marker on the point, and Escape handing focus back to a
  board's cell.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1]

  alias Visualize.Chart
  alias Visualize.Hooks.Keyboard

  defp applied do
    design = %{
      version: 2,
      meta: %{name: "Rain"},
      sources: %{s: %{fields: [:t, :mm, :city]}},
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: 10, right: 10, bottom: 10, left: 20},
          scales: %{x: %{kind: :linear, domain: [0, 2]}, y: %{kind: :linear, domain: [0, 10]}},
          axes: [%{scale: :x, side: :bottom}, %{scale: :y, side: :left, unit: " mm"}]
        }
      },
      marks: [%{type: :line, data: :s, channels: %{x: :t, y: :mm, series: :city}}]
    }

    rows = [
      %{t: 0, mm: 2, city: "Oslo"},
      %{t: 1, mm: 5, city: "Oslo"},
      %{t: 2, mm: 1, city: "Oslo"},
      %{t: 0, mm: 8, city: "Bergen \"west\""},
      %{t: 1, mm: 10, city: "Bergen \"west\""}
    ]

    {:ok, applied} = Chart.apply(design, sources: %{s: rows}, size: {220, 120})
    applied
  end

  describe "attrs/1 (spec/10 §17.2)" do
    test "the name, the size, and every point by series with its position and readout" do
      attrs = Keyboard.attrs(applied())

      assert attrs["data-keyboard-name"] == "Rain"
      assert attrs["data-size"] == "220,120"

      # The plot is 190 by 100 at (20, 10): t 1 is x 115, 5 mm is y 60.
      assert attrs["data-keyboard-points"] ==
               ~s([{"name":"Oslo","points":[[20,90,"Oslo, 1 of 3: t 0, mm 2 mm"],) <>
                 ~s([115,60,"Oslo, 2 of 3: t 1, mm 5 mm"],[210,100,"Oslo, 3 of 3: t 2, mm 1 mm"]]},) <>
                 ~s({"name":"Bergen \\"west\\"","points":[[20,30,"Bergen \\"west\\", 1 of 2: t 0, mm 8 mm"],) <>
                 ~s([115,10,"Bergen \\"west\\", 2 of 2: t 1, mm 10 mm"]]}])
    end

    test "a series of more than 1,000 points is sampled evenly, its ends kept and its rows counted" do
      design = %{
        version: 2,
        sources: %{s: %{fields: [:t, :v]}},
        frames: %{main: %{kind: :cartesian, scales: %{x: %{kind: :linear}, y: %{kind: :linear}}}},
        marks: [%{type: :line, data: :s, channels: %{x: :t, y: :v}}]
      }

      rows = for t <- 0..2499, do: %{t: t, v: rem(t, 7)}
      {:ok, applied} = Chart.apply(design, sources: %{s: rows})
      [%{points: points}] = Visualize.Chart.Summary.points(applied)

      assert length(points) == 1000
      assert hd(points).text == "v, 1 of 2500: t 0, v 0"
      assert List.last(points).text == "v, 2500 of 2500: t 2,499, v 0"
    end

    test "a point in a polar frame is read and not placed" do
      design = %{
        version: 2,
        sources: %{s: %{fields: [:name, :v]}},
        frames: %{main: %{kind: :polar}},
        marks: [%{type: :arc, data: :s, channels: %{value: :v, series: :name}}]
      }

      {:ok, applied} = Chart.apply(design, sources: %{s: [%{name: "a", v: 3}]})

      assert Keyboard.attrs(applied)["data-keyboard-points"] ==
               ~s([{"name":"a","points":[[null,null,"a, 1 of 1: a, v 3"]]}])
    end
  end

  describe "KeyboardHook executed (spec/10 §17.3)" do
    @describetag :js

    defp scenario(attrs) do
      json = Jason.encode!(attrs)

      """
      const attrs = #{json};
      const chart = Stub.markup('svg', {viewBox: '0 0 220 120'});
      chart.rect = {left: 100, top: 50, width: 440, height: 240};
      const el = Stub.markup('div', Object.assign({id: 'keys', 'data-keyboard-event': 'point'}, attrs), [chart]);
      const cell = Stub.markup('section', {id: 'cell', 'data-vis-cell': 'a1'}, [el]);
      const hook = Stub.mount(KeyboardHook, el);
      const readout = document.body.querySelector('.vis-keyboard-readout');
      const overlay = document.body.querySelector('.vis-keyboard-focus');
      const marker = overlay.children[0];
      const key = (k) => { let prevented = false; el.fire('keydown', {key: k, preventDefault: () => { prevented = true; }}); return prevented; };
      const state = () => ({text: readout.textContent, display: overlay.style.display,
                            cx: marker.getAttribute('cx'), cy: marker.getAttribute('cy')});

      const report = {tabindex: el.getAttribute('tabindex'), role: el.getAttribute('role'),
                      label: el.getAttribute('aria-label'), live: readout.getAttribute('aria-live')};
      el.focus();
      report.focus = state();
      report.firstPrevented = key('ArrowRight');
      report.first = state();
      key('ArrowRight');
      report.second = state();
      report.viewBox = overlay.getAttribute('viewBox');
      report.left = overlay.style.left;
      key('ArrowDown');
      report.down = state();
      key('ArrowDown');
      report.clampedDown = state();
      key('End');
      report.end = state();
      key('ArrowRight');
      report.pastEnd = state();
      key('ArrowUp');
      key('Home');
      report.home = state();
      report.tabPrevented = key('Tab');

      // A patch drops what the server did not render; the hook sets it again.
      el.removeAttribute('tabindex');
      hook.updated();
      report.patchedTabindex = el.getAttribute('tabindex');

      el.fire('blur', {});
      report.blurred = state();
      key('Escape');
      report.escaped = state();
      hook.destroyed();
      report.removed = [document.body.querySelector('.vis-keyboard-readout'), document.body.querySelector('.vis-keyboard-focus')];
      Stub.done(report);
      """
    end

    test "one stop; arrows, Home and End move and read the point; Escape hands focus to the cell" do
      assert {:ok, %{"log" => log, "report" => r}} = run(scenario(Keyboard.attrs(applied())))

      assert r["tabindex"] == "0" and r["role"] == "group"
      assert r["label"] == "Rain, chart: arrow keys move between points"
      assert r["live"] == "polite"

      assert r["focus"]["text"] == "Rain: 2 series, 5 points."
      assert r["focus"]["display"] == "none"

      assert r["firstPrevented"]

      assert r["first"] == %{
               "text" => "Oslo, 1 of 3: t 0, mm 2 mm",
               "display" => "block",
               "cx" => "20",
               "cy" => "90"
             }

      assert r["second"]["text"] == "Oslo, 2 of 3: t 1, mm 5 mm"
      assert {r["second"]["cx"], r["second"]["cy"]} == {"115", "60"}
      # The overlay sits over the chart, mapped through the chart's own size.
      assert r["viewBox"] == "0 0 220 120" and r["left"] == "100px"

      assert r["down"]["text"] == "Bergen \"west\", 2 of 2: t 1, mm 10 mm"
      assert r["clampedDown"]["text"] == r["down"]["text"]
      assert r["end"]["text"] == r["down"]["text"]
      assert r["pastEnd"]["text"] == r["down"]["text"]
      assert r["home"]["text"] == "Oslo, 1 of 3: t 0, mm 2 mm"
      refute r["tabPrevented"]
      assert r["patchedTabindex"] == "0"

      assert r["blurred"]["display"] == "none"
      assert r["escaped"]["display"] == "none"
      assert r["removed"] == [nil, nil]

      pushes = for %{"kind" => "push", "name" => "point", "payload" => p} <- log, do: p

      assert pushes == [
               %{"series" => 0, "index" => 0},
               %{"series" => 0, "index" => 1},
               %{"series" => 1, "index" => 1},
               %{"series" => 0, "index" => 1},
               %{"series" => 0, "index" => 0}
             ]

      assert %{"on" => "cell", "kind" => "focus"} in log
    end

    test "Enter at the reached point and a click pick a point, to the target (spec/15 §13.2)" do
      json = Jason.encode!(Keyboard.attrs(applied()))

      assert {:ok, %{"log" => log, "report" => r}} =
               run("""
               const attrs = #{json};
               const chart = Stub.markup('svg', {viewBox: '0 0 220 120'});
               chart.rect = {left: 100, top: 50, width: 440, height: 240};
               const el = Stub.markup('div', Object.assign({id: 'keys',
                 'data-keyboard-pick-event': 'pick', 'data-keyboard-target': '7'}, attrs), [chart]);
               Stub.mount(KeyboardHook, el);
               let prevented = false;
               const key = (k) => el.fire('keydown', {key: k, preventDefault: () => { prevented = true; }});
               // A point in chart units, clicked at its client position: the chart is drawn at twice its size.
               const at = (x, y) => ({clientX: 100 + x * 2, clientY: 50 + y * 2});
               const click = (x, y) => el.fire('click', at(x, y));

               Stub.mark('enter before a point');
               key('Enter');
               const early = prevented;
               Stub.mark('click near Bergen at t 1');
               el.fire('mousedown', at(115, 12));
               click(115, 12);
               Stub.mark('a drag is a brush');
               el.fire('mousedown', at(100, 12));
               click(130, 12);
               Stub.mark('outside the chart');
               el.fire('click', {clientX: 20, clientY: 20});
               Stub.mark('arrows go on from the picked point, Enter picks');
               key('ArrowLeft');
               key('Enter');
               const late = prevented;
               Stub.mark('nearest x first');
               click(200, 95);
               Stub.done({early, late});
               """)

      picks = fn mark ->
        for %{"kind" => "push", "name" => "pick"} = p <- Visualize.JsHooks.after_mark(log, mark),
            do: {p["target"], p["payload"]}
      end

      assert picks.("enter before a point") == []
      refute r["early"]
      assert picks.("click near Bergen at t 1") == [{"7", %{"series" => 1, "index" => 1}}]
      assert picks.("a drag is a brush") == []
      assert picks.("outside the chart") == []

      assert picks.("arrows go on from the picked point, Enter picks") ==
               [{"7", %{"series" => 1, "index" => 0}}]

      assert r["late"]
      assert picks.("nearest x first") == [{"7", %{"series" => 0, "index" => 2}}]
    end
  end
end
