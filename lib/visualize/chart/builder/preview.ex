if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Preview do
    @moduledoc """
    The builder's preview pane: the stacked design drawn, or its faults (spec/14 §18.4).

    The pane draws through the ordinary path — `Visualize.Chart.apply/2` over the pool of
    sample sources and the variables, then `Visualize.Chart.render/2` — so what a person
    sees while editing and what the host is handed on save cannot differ. Where application
    reports faults the pane lists them instead, one line per error as
    `Visualize.Chart.Validator.format/1` renders it and in the validator's order: an
    incomplete design is the normal state of one being built, so the error list is a panel
    of the tool and not an error page.

    A binding of the wrong type is checked before anything is applied (spec/14 §18.4,
    D-153): `Visualize.Chart.check_types/2` over each slot's types — what its rows show and,
    for a catalog feed, its schema — and a mismatch is drawn as a fault panel in the board
    runtime's cell-state style, `Visualize.Board.State.render/3` of `{:invalid, errors}`,
    with every fault listed beneath it. Any other fault the frame *raises* rather than
    reports — a theme name nothing resolves — raises here as it does anywhere else (spec/14
    §7.3): those are faults of the host's data, and catching them would hide a bug in the
    host.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Board.State
    alias Visualize.Chart
    alias Visualize.Chart.{Frame, Template, Validator}
    alias Visualize.Data.{Delivery, Table}
    alias Visualize.IR.Path

    # The fault panel's box: the cell-state drawing is responsive, so this is its aspect.
    @fault_size {600, 160}

    attr(:design, :map, required: true, doc: "the stacked design to draw")
    attr(:sources, :map, default: %{}, doc: "the pool the design's slots bind to")
    attr(:vars, :map, default: %{}, doc: "the values the design's variables take")
    attr(:theme, :any, default: nil, doc: "a `Visualize.Theme`, `nil` for the design's own")

    attr(:catalog, :map,
      default: nil,
      doc: "the connector catalog: a slot bound to one of its feeds is typed by its schema"
    )

    attr(:class, :string, default: nil, doc: "appended to the pane's class")

    attr(:selected, :string,
      default: nil,
      doc: "the open node's label, carried on the `<svg>` for the graph's hook (spec/14 §18.4)"
    )

    attr(:steps, :list,
      default: [],
      doc:
        "what the chart still needs, as `Visualize.Chart.Builder.Steps.steps/1` gives it (#374)"
    )

    attr(:target, :any, default: nil, doc: "the `phx-target` of a step's button")

    attr(:size, :any,
      default: nil,
      doc:
        "the `{width, height}` the design is drawn at — the graph's measured box — or `nil` for the render's default (spec/14 §18.4)"
    )

    attr(:box, :string,
      default: nil,
      doc:
        "the id of the box the chart sits in, which hosts `ResizeHook` and reports `graph_size` to `target`; `nil` draws the chart bare (spec/14 §18.4)"
    )

    @doc """
    Renders the preview pane (spec/10 §15.3).

    `<div class="vis-builder-preview">` holding either the chart's markup or
    `<ul class="vis-builder-errors">` with one `<li class="vis-builder-error">` per fault.
    Exactly one of the two is present; beneath either, the steps the chart still has to take
    as `<ol class="vis-builder-steps">`, each a button (spec/14 §18.4, #374). The chart is drawn with `paths: true`, so every
    node it draws carries `data-node`, and the `<svg>` carries `data-builder-selected`
    with the open node's label (spec/14 §18.4, §18.16).
    """
    def panel(assigns) do
      assigns = assign(assigns, draw(assigns))

      ~H"""
      <div class={class(@class)}>
        <div :if={@fault} class="vis-builder-fault">{@fault}</div>
        <ul :if={@errors != []} class="vis-builder-errors">
          <li :for={line <- @errors} class="vis-builder-error">{line}</li>
        </ul>
        <div
          :if={@chart && @box}
          id={@box}
          class="vis-builder-box"
          phx-hook="ResizeHook"
          data-resize-event="graph_size"
          data-resize-target={@target}
        >
          <.chart chart={@chart} width={@width} height={@height} selected={@selected} frames={@frames} overlay={@overlay} />
        </div>
        <.chart :if={@chart && !@box} chart={@chart} width={@width} height={@height} selected={@selected} frames={@frames} overlay={@overlay} />
        <ol :if={@steps != []} class="vis-builder-steps">
          <li :for={{step, i} <- Enum.with_index(@steps, 1)} class="vis-builder-step">
            <button
              type="button"
              class="vis-builder-step-button"
              phx-click={step.event}
              {for {key, value} <- step.values, do: {"phx-value-#{key}", value}}
              phx-target={@target}
            >{i} · {step.words}</button>
          </li>
        </ol>
      </div>
      """
    end

    attr(:chart, :any, required: true)
    attr(:width, :any, required: true)
    attr(:height, :any, required: true)
    attr(:selected, :string, required: true)
    attr(:frames, :string, required: true)
    attr(:overlay, :any, default: nil)

    # The chart's `<svg>` shell, at the size it was drawn at; `data-builder-frames` is every
    # frame's pixel box and margins in drawing order, which the graph's hook reads a point
    # against (spec/10 §16.2).
    defp chart(assigns) do
      ~H"""
      <svg
        class="vis-builder-chart"
        width={@width}
        height={@height}
        role="img"
        viewBox={"0 0 #{@width} #{@height}"}
        data-builder-selected={@selected}
        data-builder-frames={@frames}
      >{@chart}<g :if={@overlay} class="vis-builder-frame-overlay" data-builder-frame-box={@overlay.name}><rect class="vis-builder-frame-outline" x={@overlay.x} y={@overlay.y} width={@overlay.w} height={@overlay.h} /><rect :for={{at, x, y} <- @overlay.handles} class={"vis-builder-frame-handle vis-builder-frame-handle-#{at}"} data-builder-frame-handle={at} x={x} y={y} width={@overlay.handle} height={@overlay.handle} /></g></svg>
      """
    end

    # A `nil` class assign leaves the pane's own class alone, with no trailing space.
    defp class(nil), do: "vis-builder-preview"
    defp class(extra), do: "vis-builder-preview " <> extra

    # The design applied over the pool and drawn into the `<svg>` shell at the frame's own
    # size, or the faults application reported. The frame renders a group and the shell is
    # the pane's, as it is a component's (spec/10 §1.2); the markup is a string and MUST be
    # raw to reach the document (§11.2). Drawn with paths, so a click can name what it hit
    # (spec/14 §4.7, §18.16).
    defp draw(%{design: design, sources: sources} = assigns) do
      case type_faults(design, sources, assigns[:catalog]) do
        [] -> applied(assigns)
        errors -> fault(errors, assigns.theme)
      end
    end

    @doc false
    # The binding's type faults (spec/14 §18.4, D-153), ordered by path: the design checked
    # against what each bound slot's rows show and, for a catalog feed, its schema. Every
    # place the builder applies a design over its pool asks this first.
    @spec type_faults(map(), map(), map() | nil) :: [Validator.error()]
    def type_faults(design, pool, catalog) do
      {rows, schemas} = types(design, pool, catalog)

      (faults(design, schemas) ++ faults(design, rows))
      |> Enum.uniq()
      |> Enum.sort_by(&elem(&1, 0))
    end

    defp faults(design, types) do
      case Chart.check_types(design, types) do
        :ok -> []
        {:error, errors} -> errors
      end
    end

    # Every frame of the design is drawn, whatever it is called, at the size the graph was
    # measured at (spec/14 §18.4, #386).
    defp applied(%{design: design, sources: sources, vars: vars, theme: theme} = assigns) do
      {width, height} = size = assigns[:size] || Frame.default_size()

      case Chart.apply(design, sources: sources, vars: vars, theme: theme, size: size) do
        {:ok, %{frames: frames} = applied} ->
          %{
            chart: Phoenix.HTML.raw(Chart.render(applied, paths: true)),
            fault: nil,
            errors: [],
            width: width,
            height: height,
            frames: frames_attribute(frames),
            overlay: overlay(frames, assigns[:selected])
          }

        {:error, errors} ->
          %{
            chart: nil,
            fault: nil,
            errors: Enum.map(errors, &Validator.format/1),
            width: 0,
            height: 0,
            frames: "",
            overlay: nil
          }
      end
    end

    @doc false
    # Every realised frame as `name x y w h top right bottom left` in pixels, frames joined
    # by `;`, in drawing order — `z`, then name, the last on top (spec/14 §4.7, spec/10
    # §16.2).
    @spec frames_attribute(%{atom() => Frame.t()}) :: String.t()
    def frames_attribute(frames) do
      frames
      |> Map.values()
      |> Enum.sort_by(&{&1.z, to_string(&1.name)})
      |> Enum.map_join(";", fn %Frame{box: [x, y, w, h], size: size, margin: m} = frame ->
        Enum.map_join(
          [
            frame.name,
            x * size.width,
            y * size.height,
            w * size.width,
            h * size.height,
            m.top,
            m.right,
            m.bottom,
            m.left
          ],
          " ",
          &word/1
        )
      end)
    end

    # The side of a corner handle, in the chart's pixels (spec/14 §18.16).
    @handle 10

    @doc false
    # The open frame's outline and its four corner handles, drawn over the chart when the
    # open node is a frame itself (spec/14 §18.16, #614); `nil` for any other node. Only the
    # handles take the pointer, so every drawn node stays clickable under the outline.
    @spec overlay(%{atom() => Frame.t()}, String.t() | nil) :: map() | nil
    def overlay(frames, "frames." <> name) do
      case Enum.find(frames, fn {key, _frame} -> Atom.to_string(key) == name end) do
        {key, %Frame{box: [x, y, w, h], size: size}} ->
          {px, py, pw, ph} = {x * size.width, y * size.height, w * size.width, h * size.height}
          half = @handle / 2

          corners = [
            {"nw", px, py},
            {"ne", px + pw, py},
            {"sw", px, py + ph},
            {"se", px + pw, py + ph}
          ]

          %{
            name: Atom.to_string(key),
            x: word(px),
            y: word(py),
            w: word(pw),
            h: word(ph),
            handle: @handle,
            handles:
              for(
                {at, hx, hy} <- corners,
                do:
                  {at, word(inside(hx - half, size.width - @handle)),
                   word(inside(hy - half, size.height - @handle))}
              )
          }

        nil ->
          nil
      end
    end

    def overlay(_frames, _selected), do: nil

    # A handle kept on the chart, so one at its edge is not cut in half.
    defp inside(at, last), do: at |> max(0) |> min(last)

    defp word(name) when is_atom(name), do: Atom.to_string(name)
    defp word(n) when is_number(n), do: Path.format_number(n)

    # A binding the type check refuses, never applied: the cell-state panel and every
    # fault beneath it (spec/14 §18.4, D-153).
    defp fault(errors, theme) do
      panel = State.render({:invalid, errors}, theme || Visualize.Theme.default(), @fault_size)

      %{
        chart: nil,
        fault: Phoenix.HTML.raw(panel),
        errors: Enum.map(errors, &Validator.format/1),
        width: 0,
        height: 0,
        frames: "",
        overlay: nil
      }
    end

    # What the preview knows of each slot's fields' types (spec/14 §18.4), `{rows,
    # schemas}`: each slot bound as application binds it — its own name, else its
    # `default` — typed by what its rows show, the values the pane draws, and a slot whose
    # feed is in the catalog by its schema too.
    defp types(design, pool, catalog) do
      catalog = catalog || %{}

      bound =
        case Map.get(design, :sources) do
          slots when is_map(slots) and not is_struct(slots) ->
            for {slot, node} <- slots,
                is_map(node),
                {:ok, feed, source} <- [Template.entry(pool, slot, node)],
                do: {slot, feed, source}

          _variable_or_none ->
            []
        end

      {Map.new(bound, fn {slot, _feed, source} -> {slot, Table.column_types(rows(source))} end),
       for(
         {slot, feed, _source} <- bound,
         is_map_key(catalog, feed),
         into: %{},
         do: {slot, catalog[feed]}
       )}
    end

    defp rows(%Delivery{} = delivery), do: Delivery.source(delivery)
    defp rows(source), do: source
  end
end
