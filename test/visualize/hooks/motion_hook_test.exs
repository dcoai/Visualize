defmodule Visualize.Hooks.MotionHookTest do
  @moduledoc """
  `MotionHook` executed under node (spec/10 §20, spec/14 §3.12, #678): over the markup a
  board's cell rendered before and after its feed lost a row, the gone row's copy is placed
  in an overlay over the chart and exploded — sixteen clipped pieces moving outward and
  fading — then removed; a fade and a shrink; an element that a patch gave another
  identity restarts its enter; reduced motion places nothing.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]
  import Visualize.JsHooks, only: [run: 1, markup: 1]

  alias Visualize.Board
  alias Visualize.Board.{Binding, Server, View}
  alias Visualize.Components.Board.Cell
  alias Visualize.Data.Schema
  alias Visualize.Test.Feeds

  @moduletag :js
  @moduletag :capture_log

  @t0 ~U[2026-10-11 12:00:00Z]

  # A point per service, its row named by the declared identity, leaving by `exit`.
  defp design(exit) do
    %{
      version: 3,
      sources: %{primary: %{fields: [:t, :v, :name]}},
      frames: %{
        main: %{kind: :cartesian, scales: %{x: %{kind: :time}, y: %{kind: :linear}}}
      },
      marks: [
        %{
          type: :circle,
          data: :primary,
          channels: %{x: :t, y: :v},
          style: %{fill: "#336699", exit: exit, enter: %{name: :grow}}
        }
      ]
    }
  end

  defp rows(names) do
    for {name, i} <- Enum.with_index(names),
        do: %{t: DateTime.add(@t0, i * 60), v: i + 1, name: name}
  end

  # The cell's markup before and after its feed lost `gone` (spec/15 §9.1): a running board
  # whose cell redraws when its rows change, rendered by the cell's component each time.
  defp board_update(exit, gone) do
    schema =
      Schema.new!(%{
        t: %{type: :time},
        v: %{type: :number},
        name: %{type: :category, identity: true}
      })

    names = ["api", "db", "web"]
    {feed, agent} = Feeds.scripted(schema: schema, rows: rows(names))
    Process.unlink(agent)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)
    sup = start_supervised!(Visualize.Board.Supervisor)

    board =
      Board.from_map!(%{
        meta: %{name: "Ops"},
        window: %{last: 600},
        cells: %{services: %{x: 0, y: 0, w: 12, h: 3, ref: {:composite, 1}}}
      })

    {:ok, pid} =
      Server.start(sup,
        board: board,
        store: %{{:composite, 1} => design(exit)},
        binding: Binding.new(%{{:services, :primary} => :f}),
        feeds: %{f: feed},
        tick: nil,
        debounce: 0,
        clock: fn -> DateTime.add(@t0, 600) end
      )

    # The views come in a known order (#715): the board fetched the scripted feed in its
    # first turn and sent the cell its rows before the subscribe was answered, so the
    # cell's first view to this process is the drawing of all three rows, sent on
    # subscribing; the window call runs a turn that sends the cell the rows without `gone`,
    # and the cell's next view is their drawing. Each is asserted as it is taken.
    {:ok, _info} = Server.subscribe(pid)
    before = next_view(pid)
    assert before.state == :live
    assert before.svg =~ ~s(data-vis-id="main.1.name=#{gone}")

    Feeds.set(agent, rows: rows(names -- [gone]))
    :ok = Server.window(pid, %{from: @t0, to: DateTime.add(@t0, 600)})
    after_ = next_view(pid)
    assert after_.state == :live
    refute after_.svg =~ ~s(data-vis-id="main.1.name=#{gone}")

    {cell(before), cell(after_)}
  end

  # The cell's next view: a message the cell sends once it has drawn, waited on with no
  # `after` of its own, so a cell that never draws is bounded by the test's timeout and
  # nothing here reads the clock (spec/12 §6).
  defp next_view(board) do
    receive do
      {:visualize_board, ^board, {:cell, "services", %View{} = view}} -> view
    end
  end

  defp cell(view) do
    render_component(Cell,
      id: "ops-services",
      cell: :services,
      rect: %{x: 0, y: 0, w: 12, h: 3},
      title: nil,
      theme: Visualize.Theme.default(),
      target: 3,
      view: view
    )
  end

  # Mounts MotionHook over the first cell's motion element, patches it to the second's —
  # the children replaced, as a LiveView patch replaces what changed — and lets the clock
  # run, reporting what the overlay holds along the way.
  defp scenario(before, after_, opts \\ []) do
    """
    window.matchMedia = (q) => ({ matches: #{Keyword.get(opts, :reduced, false)} });
    const find = (root, id) => [root, ...root.descendants()].find((e) => e.getAttribute('id') === id);
    const first = #{markup(before)};
    const second = #{markup(after_)};
    const el = find(first, 'ops-services-motion');
    const next = find(second, 'ops-services-motion');
    el.querySelector('svg').rect = {left: 10, top: 20, width: 600, height: 400};
    const hook = Stub.mount(MotionHook, el);
    hook.beforeUpdate();
    el.children.forEach((c) => { c.parentNode = null; });
    el.children = [];
    next.children.forEach((c) => el.appendChild(c));
    hook.updated();
    const overlay = () => document.body.children.find((c) => c.getAttribute('class') === 'vis-motion-overlay');
    const describe = () => {
      const o = overlay();
      if (!o) return null;
      const all = o.descendants();
      return {
        display: o.style.display,
        clips: all.filter((e) => e.tagName === 'CLIPPATH').length,
        clipped: all.filter((e) => e.getAttribute('clip-path')).length,
        circles: all.filter((e) => e.tagName === 'CIRCLE').map((e) => e.getAttribute('data-vis-id')),
        moves: all.filter((e) => e.getAttribute('transform') && e.getAttribute('opacity') !== null)
          .map((e) => [e.getAttribute('transform'), Number(e.getAttribute('opacity'))]),
        wraps: all.filter((e) => e.tagName === 'G' && e.getAttribute('opacity') !== null && !e.getAttribute('clip-path'))
          .map((e) => [e.getAttribute('transform'), Number(e.getAttribute('opacity'))]),
        left: o.style.left, viewBox: o.getAttribute('viewBox')
      };
    };
    const at0 = describe();
    Stub.advance(#{Keyword.get(opts, :mid, 300)});
    const mid = describe();
    Stub.advance(1000);
    const end = describe();
    Stub.done({at0, mid, end});
    """
  end

  test "a row the board's feed lost explodes in the overlay, then is gone" do
    {before, after_} = board_update(%{name: :explode, duration: 700}, "db")
    assert before =~ ~s(<div id="ops-services-motion" phx-hook="MotionHook">)
    assert before =~ "data-vis-exit="

    assert {:ok, %{"report" => %{"at0" => at0, "mid" => mid, "end" => ended}}} =
             run(scenario(before, after_))

    # Sixteen pieces of the one gone point, each a clipped copy, over the chart.
    assert at0["clips"] == 16 and at0["clipped"] == 16
    assert Enum.uniq(at0["circles"]) == ["main.1.name=db"]
    assert at0["left"] == "10px"
    assert at0["display"] == "block"

    # Midway every piece has moved off and faded some; none is where it started.
    assert length(mid["moves"]) == 16

    for [transform, opacity] <- mid["moves"] do
      refute transform =~ "translate(0,0)"
      assert opacity > 0 and opacity < 1
    end

    # At the end the copy and its clips are gone and the overlay hidden.
    assert ended["clips"] == 0 and ended["circles"] == []
    assert ended["display"] == "none"
  end

  test "a fade fades the copy's wrapper" do
    {before, after_} = board_update(%{name: :fade, duration: 400}, "web")
    assert {:ok, %{"report" => %{"mid" => mid}}} = run(scenario(before, after_, mid: 200))
    assert [[_transform, opacity]] = mid["wraps"]
    assert opacity > 0.1 and opacity < 0.9
    assert mid["circles"] == ["main.1.name=web"]
  end

  test "a shrink scales the copy about its center; reduced motion places nothing" do
    {before, after_} = board_update(%{name: :shrink, duration: 400}, "api")
    assert {:ok, %{"report" => %{"mid" => mid}}} = run(scenario(before, after_, mid: 200))
    assert [[transform, 1]] = mid["wraps"]
    [scale] = Regex.run(~r/scale\(([\d.]+)\)/, transform, capture: :all_but_first)
    assert String.to_float(scale) > 0.05 and String.to_float(scale) < 0.95

    assert {:ok, %{"report" => %{"at0" => nil, "end" => nil}}} =
             run(scenario(before, after_, reduced: true))
  end

  test "an element a patch gives another identity runs its enter again" do
    assert {:ok, %{"report" => report}} =
             run("""
             const wrapper = Stub.markup('g', {class: 'vis-enter-abc'}, [
               Stub.markup('circle', {'data-vis-id': 'main.1.name=a'}, [])]);
             const svg = Stub.markup('svg', {viewBox: '0 0 10 10'}, [wrapper]);
             const el = Stub.markup('div', {id: 'm'}, [svg]);
             const hook = Stub.mount(MotionHook, el);
             const circle = wrapper.children[0];
             const seen = [];
             wrapper.classList.remove = ((remove) => (c) => { seen.push('off ' + c); return remove.call(wrapper.classList, c); })(wrapper.classList.remove);
             hook.beforeUpdate();
             circle.setAttribute('data-vis-id', 'main.1.name=b');
             hook.updated();
             Stub.done({seen, has: wrapper.classList.has('vis-enter-abc')});
             """)

    assert report == %{"seen" => ["off vis-enter-abc"], "has" => true}
  end
end
