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

    A fault the frame *raises* rather than reports — a value a scale cannot take, a theme
    name nothing resolves — raises here as it does anywhere else (spec/14 §7.3): those are
    faults of the host's data, and catching them would hide a bug in the host.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart
    alias Visualize.Chart.Validator

    attr(:design, :map, required: true, doc: "the stacked design to draw")
    attr(:sources, :map, default: %{}, doc: "the pool the design's slots bind to")
    attr(:vars, :map, default: %{}, doc: "the values the design's variables take")
    attr(:theme, :any, default: nil, doc: "a `Visualize.Theme`, `nil` for the design's own")
    attr(:class, :string, default: nil, doc: "appended to the pane's class")

    attr(:selected, :string,
      default: nil,
      doc: "the open node's label, carried on the `<svg>` for the graph's hook (spec/14 §18.4)"
    )

    @doc """
    Renders the preview pane (spec/10 §15.3).

    `<div class="vis-builder-preview">` holding either the chart's markup or
    `<ul class="vis-builder-errors">` with one `<li class="vis-builder-error">` per fault.
    Exactly one of the two is present. The chart is drawn with `paths: true`, so every
    node it draws carries `data-node`, and the `<svg>` carries `data-builder-selected`
    with the open node's label (spec/14 §18.4, §18.16).
    """
    def panel(assigns) do
      assigns = assign(assigns, draw(assigns))

      ~H"""
      <div class={class(@class)}>
        <ul :if={@errors != []} class="vis-builder-errors">
          <li :for={line <- @errors} class="vis-builder-error">{line}</li>
        </ul>
        <svg
          :if={@chart}
          class="vis-builder-chart"
          width={@width}
          height={@height}
          role="img"
          viewBox={"0 0 #{@width} #{@height}"}
          data-builder-selected={@selected}
          data-builder-frame={"#{@width} #{@height} #{@margin.top} #{@margin.right} #{@margin.bottom} #{@margin.left}"}
        >{@chart}</svg>
      </div>
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
    defp draw(%{design: design, sources: sources, vars: vars, theme: theme}) do
      case Chart.apply(design, sources: sources, vars: vars, theme: theme) do
        {:ok, %{frame: %{size: size, margin: margin}} = applied} ->
          %{
            chart: Phoenix.HTML.raw(Chart.render(applied, paths: true)),
            errors: [],
            width: size.width,
            height: size.height,
            margin: margin
          }

        {:error, errors} ->
          %{
            chart: nil,
            errors: Enum.map(errors, &Validator.format/1),
            width: 0,
            height: 0,
            margin: %{top: 0, right: 0, bottom: 0, left: 0}
          }
      end
    end
  end
end
