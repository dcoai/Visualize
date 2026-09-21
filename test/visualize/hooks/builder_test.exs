defmodule Visualize.Hooks.BuilderTest do
  @moduledoc """
  `BuilderHook`, the chart builder's two browser gestures (spec/10 §16, D-87).

  The source is held to the shape §16.3 declares: the five listeners bound once and removed
  on `destroyed()`, the drop that pushes a move without making one, and the click that
  highlights locally and selects on the server.
  """
  use ExUnit.Case, async: true

  alias Visualize.Hooks

  @listeners ~w(dragstart dragover drop dragend click contextmenu)

  test "the hook is one export and joins the bundle once (D-48)" do
    js = Hooks.js_code()
    assert length(String.split(js, "export const BuilderHook = {")) == 2
    assert js =~ ~r/export default \{[^}]*\bBuilderHook\b/
  end

  test "every listener is bound once, kept, and removed on destroyed (D-47)" do
    js = Hooks.Builder.js_hook()

    for event <- @listeners do
      assert js =~ "this.el.addEventListener('#{event}', this.on"
      assert js =~ "this.el.removeEventListener('#{event}', this.on"
    end

    assert js =~ "bind(this)"
  end

  # The menu of #379 (spec/14 §18.16, §18.17): a right-click on a drawn node or a layer row
  # pushes `menu` with the target and the point in the builder's own box; anywhere else the
  # browser's menu stays. The row's keyboard twin is Shift+F10 or the Menu key.
  test "a right-click on a node or a row pushes the menu at the point; the keyboard twin too" do
    js = Hooks.Builder.js_hook()
    assert js =~ "handleContextMenu(e)"

    assert js =~
             "this.push('menu', { node: node.getAttribute('data-node'), ...this.menuPoint(e.clientX, e.clientY) })"

    assert js =~
             "this.push('menu', { layer: row.getAttribute('data-builder-layer'), ...this.menuPoint(e.clientX, e.clientY) })"

    assert js =~ "e.key === 'ContextMenu' || (e.shiftKey && e.key === 'F10')"
    assert js =~ "this.el.closest('.vis-builder')"
  end

  # A drop on the middle third of a group's row lands inside it (spec/14 §18.17, #380).
  test "a drop on a group's row pushes into, a move or an insert" do
    js = Hooks.Builder.js_hook()
    assert js =~ "intoAt(e)"
    assert js =~ "row.getAttribute('data-builder-into')"
    assert js =~ "this.push('reorder', { from: this.from, into: into })"
    assert js =~ "this.push('insert', { name: stored, into: into })"
  end

  test "a drop pushes the move and makes none: the server owns the list" do
    js = Hooks.Builder.js_hook()
    assert js =~ "this.push('reorder', { from: this.from, to: to })"
    assert js =~ "if (to !== this.from)"
    assert js =~ "e.preventDefault()"
    refute js =~ "insertBefore"
    refute js =~ "appendChild"
  end

  test "a click highlights in the browser and pushes the path and the layer" do
    js = Hooks.Builder.js_hook()
    assert js =~ "closest('[data-builder-path]')"
    assert js =~ "row.classList.add('vis-builder-entry-open')"
    assert js =~ "path: row.getAttribute('data-builder-path')"
    assert js =~ "layer: row.getAttribute('data-builder-layer')"
  end

  test "the pushes reach the component when data-builder-target names one" do
    js = Hooks.Builder.js_hook()
    assert js =~ "this.target = this.el.dataset.builderTarget || null"
    assert js =~ "if (this.target) this.pushEventTo(this.target, event, carried)"
    assert js =~ "else this.pushEvent(event, carried)"
  end

  test "a click selects a field once: a well its own, any other click in a row the row's (spec/14 §19.10)" do
    js = Hooks.Builder.js_hook()
    {well_at, _} = :binary.match(js, "closest('[data-builder-well]')")
    {row_at, _} = :binary.match(js, "closest('[data-builder-bind]')")
    assert well_at < row_at

    assert js =~
             "this.push('select_field', this.aimed(well, { field: well.getAttribute('data-builder-well') }))"

    assert js =~
             "this.push('select_field', this.aimed(field, { field: field.getAttribute('data-builder-bind') }))"

    # A push from inside a node's form carries the node (spec/14 §18.15).
    assert js =~ "closest('[data-builder-node]')"

    # The rows carry no click binding of their own, only the keyboard's.
    html =
      Visualize.BuilderFixture.render_case(
        {&Visualize.Chart.Builder.Editor.panel/1, %{kind: :style, node: %{}, facet: :style}}
      )

    refute html =~ ~s(phx-click="select_field")
    assert html =~ ~s(phx-keyup="select_field")
    # The style row is not a label, so a click on its word picks no radio.
    assert html =~ ~s(<div class="vis-builder-field vis-builder-field-fill-style">)
  end

  test "nothing is logged and no element outside the hook takes part" do
    js = Hooks.Builder.js_hook()
    refute js =~ "console.log"
    assert js =~ "this.el.contains(layer)"
    assert js =~ "this.el.contains(row)"
  end
end
