defmodule Visualize.Hooks.ResizeTest do
  @moduledoc "The `ResizeHook` source (spec/10 §10, D-54): observe, settle once, disconnect."
  use ExUnit.Case, async: true

  alias Visualize.Hooks
  alias Visualize.Hooks.Resize

  test "the hook observes its element with a ResizeObserver and stops on destroyed()" do
    js = Resize.js_hook()
    assert js =~ "export const ResizeHook = {"
    assert js =~ "new ResizeObserver("
    assert js =~ "this.observer.observe(this.el)"
    assert js =~ "if (typeof ResizeObserver === 'undefined') return;"
    assert js =~ "destroyed() {"
    assert js =~ "this.observer.disconnect()"
    assert js =~ "clearTimeout(this.timer)"
  end

  test "the event name and debounce come from data attributes with the specified defaults" do
    js = Resize.js_hook()
    assert js =~ "this.el.dataset.resizeEvent || 'resize'"
    assert js =~ "parseInt(this.el.dataset.resizeDebounce, 10) || 150"
  end

  test "a settle pushes {width, height, reduced_motion} once, rounded, and never the same size twice" do
    js = Resize.js_hook()
    assert js =~ "setTimeout(() => this.settled(), this.debounce)"
    assert js =~ "Math.round(rect.width)"
    assert js =~ "Math.round(rect.height)"
    assert js =~ "this.last.width === size.width && this.last.height === size.height"
    assert js =~ "this.push(this.payload(size))"
    # The settle's push, and the motion preference's change (spec/14 §21.6), both through
    # the one push that picks the LiveView or the target.
    assert js =~ "this.push(this.payload(this.last))"
    assert length(String.split(js, "this.pushEvent(")) == 2
    assert length(String.split(js, "this.pushEventTo(")) == 2
  end

  test "data-resize-target sends the push to a component with pushEventTo (spec/14 §18.4)" do
    assert Resize.js_hook() =~ "this.target = this.el.dataset.resizeTarget || null"
  end

  describe "executed (spec/12 §6)" do
    @describetag :js

    # A ResizeObserver and a matchMedia the scenario drives: an observation, a settle, then
    # the reader turning reduced motion on, then a hook destroyed.
    @scenario """
    let observed = null;
    globalThis.ResizeObserver = class { constructor(fn) { observed = fn; } observe() {} disconnect() {} };
    const query = { matches: false, listeners: [],
      addEventListener(_t, fn) { this.listeners.push(fn); },
      removeEventListener(_t, fn) { this.listeners = this.listeners.filter((f) => f !== fn); } };
    window.matchMedia = (q) => { query.media = q; return query; };

    const hook = Stub.mount(ResizeHook, Stub.node('div', {resizeEvent: 'resize'}));
    observed([{contentRect: {width: 640.4, height: 399.6}}]);
    Stub.advance(150);
    query.matches = true;
    query.listeners.forEach((fn) => fn({matches: true}));
    hook.destroyed();
    Stub.done({media: query.media, listeners: query.listeners.length});
    """

    test "the motion preference rides on every push, and its change is pushed with the last size" do
      assert {:ok, %{"log" => log, "report" => report}} = Visualize.JsHooks.run(@scenario)

      pushes = for %{"kind" => "push", "payload" => p} <- log, do: p

      assert pushes == [
               %{"width" => 640, "height" => 400, "reduced_motion" => false},
               %{"width" => 640, "height" => 400, "reduced_motion" => true}
             ]

      assert report == %{"media" => "(prefers-reduced-motion: reduce)", "listeners" => 0}
    end

    # The builder's graph hosts the hook from inside a component (spec/14 §18.4): the push
    # goes to the target the element names, never to the LiveView.
    test "with data-resize-target the settle is pushed to that target" do
      scenario = """
      let observed = null;
      globalThis.ResizeObserver = class { constructor(fn) { observed = fn; } observe() {} disconnect() {} };
      const hook = Stub.mount(ResizeHook, Stub.node('div', {resizeEvent: 'graph_size', resizeTarget: '3'}));
      observed([{contentRect: {width: 812.2, height: 501.7}}]);
      Stub.advance(150);
      Stub.done({});
      """

      assert {:ok, %{"log" => log}} = Visualize.JsHooks.run(scenario)

      assert [
               %{
                 "name" => "graph_size",
                 "target" => "3",
                 "payload" => %{"width" => 812, "height" => 502, "reduced_motion" => false}
               }
             ] = for(%{"kind" => "push"} = push <- log, do: push)
    end
  end

  test "the bundle carries the hook once and exports it" do
    js = Hooks.js_code()
    assert length(String.split(js, "export const ResizeHook = {")) == 2
    assert js =~ ~r/export default \{[^}]*\bResizeHook\b/
  end
end
