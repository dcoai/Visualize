if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Components.Support do
    @moduledoc false
    # What every component shares (spec/10 §1.2, D-64): the preset drawn through the layer,
    # the elements a template prints picked out of the frame's group, the `<svg>` shell
    # attributes and the transition.

    alias Visualize.{Chart, Theme}
    alias Visualize.Chart.{Frame, Mark, Presets, Style}
    alias Visualize.IR.{Element, Path, Transform}

    @transition "transition: all 0.3s ease-in-out;"
    @responsive [preserveAspectRatio: "xMidYMid meet", style: "width:100%;height:auto"]

    @typedoc """
    A component's preset drawn: the frame, the mapped source, the frame's generated group,
    the rows of each mark in the order of the design's marks — what a hierarchy template
    reads beside the elements for the parts of its markup that follow the node (spec/14
    §15.4) — the theme, the accessibility ids, and the margin and plot area the template
    lays out with.
    """
    @type drawn :: %{
            frame: Frame.t(),
            sources: %{data: [map()]},
            group: Element.t(),
            rows: [[map()]],
            theme: Theme.t(),
            ids: map(),
            margin: map(),
            plot: map()
          }

    @doc false
    # The preset of `name` over the assigns, drawn: the design through `Visualize.Chart`,
    # the frame over the mapped source, `Visualize.Chart.Frame.generate/2` with the source
    # so the marks are drawn too (spec/14 §15.1), and each mark's rows through its pipeline.
    @spec draw(Presets.name(), map()) :: drawn()
    def draw(name, assigns) do
      theme = theme(assigns.theme)
      sources = Presets.sources(name, assigns)
      chart = Chart.from_map!(Presets.design(name, assigns))
      # A component keeps its `width`/`height` assigns (spec/10 §1.2); the design records
      # no size (spec/14 §4.2, #427), so they are the realization's.
      size = {assigns.width, assigns.height}
      frame = Frame.new(chart, sources: sources, theme: theme, size: size)

      %{
        frame: frame,
        sources: sources,
        group: Frame.generate(frame, sources: sources),
        rows: Enum.map(frame.marks, &Mark.rows(frame, &1, sources)),
        theme: theme,
        ids: label_ids(assigns.title, assigns.description),
        margin: frame.margin,
        plot: frame.plot
      }
    end

    # -- the elements a template prints -------------------------------------------------

    @doc false
    # The mark groups of the frame's group in design order (spec/14 §4.7), reaching into
    # the centered group of a polar frame. A labeled mark is a wrapper of its styled
    # elements' group and its labels' group (spec/14 §5.6, #485); a template reads the
    # mark's style and its elements then its labels, so it is given the elements' group
    # with the labels after its elements.
    @spec marks(Element.t()) :: [Element.t()]
    def marks(%Element{children: children}) do
      Enum.flat_map(children, fn
        %Element{style: %{class: "polar"}} = polar -> marks(polar)
        %Element{style: %{class: "mark " <> _}} = mark -> [read(mark)]
        _other -> []
      end)
    end

    defp read(%Element{
           children: [
             %Element{style: %{class: "mark-elements"}} = elements,
             %Element{style: %{class: "mark-labels"}, children: labels}
           ]
         }),
         do: %{elements | children: elements.children ++ labels}

    defp read(mark), do: mark

    @doc false
    # The elements a template prints, each given the `labels` printed after it: the labels
    # all after the last element and none after any other, the order the layer draws a
    # labeled mark in (spec/14 §5.6, #485). A label a mark's fit dropped has no text, so
    # its element's place cannot be told from its text's, and a label is never printed
    # under a later element (spec/10 §2.5, §3.4, #494).
    @spec followed([map()], [map()]) :: [map()]
    def followed([], _labels), do: []

    def followed(items, labels) do
      {init, [last]} = Enum.split(items, -1)
      Enum.map(init, &Map.put(&1, :labels, [])) ++ [Map.put(last, :labels, labels)]
    end

    @doc false
    # The axis on `side` as the frame drew it: the `Visualize.Axis` group inside the
    # frame's `axis axis-<side>` group, rendered and marked safe for the template.
    @spec axis(Element.t(), :top | :right | :bottom | :left) :: Phoenix.HTML.safe()
    def axis(%Element{children: children}, side) do
      class = "axis axis-#{side}"
      %Element{children: [axis]} = Enum.find(children, &(&1.style[:class] == class))
      Phoenix.HTML.raw(Visualize.Render.to_string(axis))
    end

    @doc false
    # The frame's labels (spec/14 §6.3) as the template prints them: position, anchor,
    # style and the rotation, if any, as a transform attribute.
    @spec labels(Element.t()) :: [map()]
    def labels(%Element{children: children}) do
      for %Element{type: :text, style: %{class: "label"} = style} = text <- children do
        %{
          x: fmt(text.attrs.x),
          y: fmt(text.attrs.y),
          anchor: style.text_anchor,
          font_size: style.font_size,
          fill: style.fill,
          transform: if(text.transform, do: Transform.to_string(text.transform)),
          text: text.content
        }
      end
    end

    @doc false
    # The `d` of a path mark's only element, `nil` when the mark drew nothing to print — no
    # row placed, or an empty path.
    @spec path(Element.t()) :: String.t() | nil
    def path(%Element{children: [%Element{path: %Path{commands: [_ | _]} = path}]}),
      do: Path.to_string(path)

    def path(%Element{}), do: nil

    @doc false
    # The `d` of a path element.
    @spec d(Element.t()) :: String.t()
    def d(%Element{path: %Path{} = path}), do: Path.to_string(path)

    @doc false
    # A style name's element style bound to a row (spec/14 §3.4): the color scale's output
    # for a `{:field, f}`, every slot as a CSS reference.
    @spec style(Frame.t(), atom(), map()) :: map()
    def style(%Frame{} = frame, name, row) do
      frame.styles
      |> Style.node(name)
      |> Style.resolve(frame.theme, :css)
      |> Style.bind(row, frame, :css)
    end

    # -- the shell ---------------------------------------------------------------------

    @doc false
    # The attribute list a mark spreads: the CSS transition when animating, nothing
    # otherwise, so a mark without animation carries no `style` at all.
    def transition(true), do: [style: @transition]
    def transition(false), do: []

    @doc false
    # The `<style>` an animated chart carries (spec/10 §1.2, spec/14 §21.6, D-142): a
    # reader who asks for less motion gets none — the stylesheet's `!important` beats the
    # marks' inline transition.
    def reduced_motion,
      do:
        "@media (prefers-reduced-motion: reduce) { svg.vis-animated * { transition: none !important; } }"

    @doc false
    # The attributes of the `<svg>` beyond its size (spec/10 §1.2): `class` when given,
    # the theme's font so every text inherits it, and under `responsive` the
    # `preserveAspectRatio` and `style` that let CSS scale it (D-54), matching
    # `Visualize.IR.Element.root/3` under `responsive: true`. An animated chart's class
    # gains `vis-animated`, which `reduced_motion/0`'s rule stops (spec/14 §21.6).
    def svg_attrs(class, responsive, theme, ids, animate) do
      class =
        case {class, animate} do
          {nil, false} -> []
          {nil, true} -> [class: "vis-animated"]
          {class, false} -> [class: class]
          {class, true} -> [class: class <> " vis-animated"]
        end

      font = ["font-family": Theme.resolve(theme, :font_family, :css)]
      labeled = if ids.labelledby, do: ["aria-labelledby": ids.labelledby], else: []

      labeled =
        labeled ++ if ids.describedby, do: ["aria-describedby": ids.describedby], else: []

      class ++ font ++ [role: "img"] ++ labeled ++ if(responsive, do: @responsive, else: [])
    end

    @doc false
    # The ids of the `<title>` and `<desc>` a titled component renders first (spec/10 §1.2),
    # derived as `Visualize.IR.Element.root/3` derives them (D-56).
    def label_ids(title, description), do: Element.label_ids(nil, title, description)

    @doc false
    # The `theme` assign as a struct: `nil` is the default theme (spec/10 §1.2).
    def theme(nil), do: Theme.default()
    def theme(%Theme{} = theme), do: theme

    @doc false
    # A theme slot as the CSS reference the markup carries.
    def css(theme, slot), do: Theme.resolve(theme, slot, :css)

    @doc false
    # Coordinates print through the one number formatter of every serializer (spec/02 §3):
    # at most four decimals, never `-0`, so a golden does not record float noise.
    defdelegate fmt(number), to: Path, as: :format_number
  end
end
