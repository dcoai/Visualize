defmodule Visualize.Hooks.ExecutedLegendHookTest do
  @moduledoc """
  `LegendHook` executed under node over the markup a chart renders (spec/10 §14.3,
  spec/12 §6, #508). A series drawn as a line with points and an end label must be hidden
  whole by its legend entry, and nothing of another series with it. The hook's source
  tests read it as text, and the goldens hold the attribute on the path, so the points a
  `:circle` mark drew for the series stayed drawn and no test noticed.
  """
  use ExUnit.Case, async: true

  import Visualize.JsHooks, only: [run: 1, markup: 1]

  alias Visualize.Chart

  @moduletag :js

  @series ~w(alpha beta gamma)

  defp rows do
    for hour <- 0..5, {s, i} <- Enum.with_index(@series) do
      %{hour: hour, series: s, value: 10 + 5 * i + hour}
    end
  end

  # The /interaction page's legend chart: a line and its points, both by `series`, the
  # line labeled with its series at its end.
  defp svg do
    design = %{
      version: 2,
      sources: %{primary: %{fields: [:hour, :series, :value]}},
      frames: %{
        main: %{
          kind: :cartesian,
          margin: %{top: 20, right: 100, bottom: 30, left: 40},
          scales: %{
            x: %{kind: :linear, domain: [0, 5]},
            y: %{kind: :linear, domain: [0, :auto]},
            color: %{kind: :ordinal}
          },
          legend: %{scale: :color, position: :top_right, title: ["series"]}
        }
      },
      marks: [
        %{
          type: :line,
          data: :primary,
          channels: %{x: :hour, y: :value, series: :series},
          label: %{text: [{:field, :series}], anchor: :right}
        },
        %{
          type: :circle,
          data: :primary,
          channels: %{x: :hour, y: :value, series: :series},
          options: %{radius: 4}
        }
      ]
    }

    {:ok, applied} = Chart.apply(Chart.from_map!(design), sources: %{primary: rows()})
    Chart.render(applied, root: true)
  end

  defp toggle_scenario do
    tree = markup(svg())

    """
    const chart = () => #{tree};
    const el = Stub.markup('div', {id: 'legend-chart', 'data-legend-event': 'legend_toggle'}, [chart()]);
    const hook = Stub.mount(LegendHook, el);

    // Every element of the marks that names a series, as the hook finds them.
    const state = () => el.querySelectorAll('.mark [data-series]').map((n) => ({
      tag: n.tagName, series: n.getAttribute('data-series'), display: n.getAttribute('display')
    }));
    const entry = (s) =>
      el.querySelectorAll('.legend-item[data-series]').find((e) => e.getAttribute('data-series') === s);
    // A click lands on the entry's swatch, inside the entry, as a pointer's would.
    const click = (s) => el.fire('click', {target: entry(s).children[0]});
    const entries = () => el.querySelectorAll('.legend-item[data-series]').map((e) => ({
      series: e.getAttribute('data-series'), class: e.getAttribute('class'), opacity: e.getAttribute('opacity')
    }));

    const report = {initial: state()};
    click('beta');
    report.hidden = state();
    report.entries = entries();

    // A LiveView patch: the server re-renders the chart without the client's hidden set.
    el.children.slice().forEach((c) => c.remove());
    el.appendChild(chart());
    hook.updated();
    report.patched = state();

    click('beta');
    report.shown = state();
    report.restored = entries();
    Stub.done(report);
    """
  end

  defp by_series(state), do: Enum.group_by(state, & &1["series"])
  defp tags(nodes), do: nodes |> Enum.map(& &1["tag"]) |> Enum.frequencies()
  defp displays(nodes), do: nodes |> Enum.map(& &1["display"]) |> Enum.uniq()

  test "a toggle hides every element of the series — its path, every point and its label — and nothing of the others; again shows them" do
    assert {:ok, %{"log" => log, "report" => report}} = run(toggle_scenario())

    initial = by_series(report["initial"])
    assert Map.keys(initial) == @series

    # Each series draws one path, a point per hour and an end label, and every one of
    # them names the series: the points are not left out (#508).
    for s <- @series do
      assert tags(initial[s]) == %{"PATH" => 1, "CIRCLE" => 6, "TEXT" => 1}
      assert displays(initial[s]) == [nil]
    end

    hidden = by_series(report["hidden"])
    assert displays(hidden["beta"]) == ["none"]
    assert tags(hidden["beta"]) == %{"PATH" => 1, "CIRCLE" => 6, "TEXT" => 1}
    assert displays(hidden["alpha"]) == [nil]
    assert displays(hidden["gamma"]) == [nil]

    assert %{"class" => "legend-item legend-item-hidden", "opacity" => "0.35"} =
             Enum.find(report["entries"], &(&1["series"] == "beta"))

    assert %{"class" => "legend-item", "opacity" => nil} =
             Enum.find(report["entries"], &(&1["series"] == "alpha"))

    # A patch re-renders every element shown; updated() hides the series again.
    patched = by_series(report["patched"])
    assert displays(patched["beta"]) == ["none"]
    assert displays(patched["alpha"]) == [nil] and displays(patched["gamma"]) == [nil]

    shown = by_series(report["shown"])
    for s <- @series, do: assert(displays(shown[s]) == [nil])
    assert Enum.all?(report["restored"], &(&1["class"] == "legend-item" and &1["opacity"] == nil))

    assert for(%{"kind" => "push"} = push <- log, do: {push["name"], push["payload"]}) == [
             {"legend_toggle", %{"series" => "beta", "hidden" => true}},
             {"legend_toggle", %{"series" => "beta", "hidden" => false}}
           ]
  end

  test "the stub's descendant combinator reads the hook's selector as a browser does" do
    assert {:ok, %{"report" => report}} =
             run("""
             const leaf = Stub.markup('circle', {'data-series': 'a'});
             const loose = Stub.markup('circle', {'data-series': 'b'});
             const el = Stub.markup('div', {}, [
               Stub.markup('g', {class: 'mark mark-circle'}, [Stub.markup('g', {}, [leaf])]),
               Stub.markup('g', {class: 'legend'}, [loose])
             ]);
             Stub.done({
               found: el.querySelectorAll('.mark [data-series]').map((n) => n.getAttribute('data-series')),
               itself: el.querySelectorAll('.mark').length
             });
             """)

    assert report == %{"found" => ["a"], "itself" => 1}
  end
end
