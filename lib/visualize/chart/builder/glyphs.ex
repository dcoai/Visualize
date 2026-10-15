if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Glyphs do
    @moduledoc """
    The pictures a drawn enum is chosen by (spec/14 §18.6).

    Some enums name a look — the join of a stroke, the shape of a curve, a symbol, a side —
    and a person chooses a look by seeing it. `glyph/2` draws one allowed value of a drawn
    key as a small inline SVG, in `currentColor` so it reads in either theme; `drawn?/1`
    says which keys have pictures. A curve is drawn by `Visualize.Shape.Line` and a symbol
    by `Visualize.Shape.Symbol`, so the picture is the library's own work and cannot lie.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Schema
    alias Visualize.Shape.{Line, Symbol}

    @drawn [
      :paint_type,
      :hatch_pattern,
      :effect,
      :vertical_align,
      :stroke_style,
      :stroke_linejoin,
      :stroke_linecap,
      :curve,
      :symbol,
      :side,
      :anchor,
      :position,
      :text_anchor,
      :orientation,
      :link,
      :kind
    ]

    @doc """
    Whether a key's enum is chosen by its picture.

        iex> Visualize.Chart.Builder.Glyphs.drawn?(:curve)
        true

        iex> Visualize.Chart.Builder.Glyphs.drawn?(:op)
        false
    """
    @spec drawn?(atom()) :: boolean()
    def drawn?(key), do: key in @drawn

    @doc """
    The inline SVG for one value of a drawn key, or `nil` for a key that is not drawn or a
    value it does not know.

        iex> Visualize.Chart.Builder.Glyphs.glyph(:stroke_linecap, :round) =~ ~s|stroke-linecap="round"|
        true

        iex> Visualize.Chart.Builder.Glyphs.glyph(:op, :sum)
        nil
    """
    @spec glyph(atom(), atom()) :: String.t() | nil
    def glyph(key, value) when is_atom(key) and is_atom(value) do
      case picture(key, value) do
        nil ->
          nil

        inner ->
          ~s|<svg class="vis-builder-glyph-svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">#{inner}</svg>|
      end
    end

    @doc """
    The inline SVG of a control's icon — `:eye` and `:eye_off` for the layer toggle, `:lock`
    for a library layer and `:lock_open` for one unlocked from it (spec/14 §18.8), `:inspect`, `:color` and `:variables` for the
    panel row, and a root's name (a string) for the node row (§18.13, #314) — in
    `currentColor`, 18px, hidden from readers since the control names itself.

        iex> Visualize.Chart.Builder.Glyphs.icon(:lock) =~ ~s|<rect x="5" y="11"|
        true
    """
    @spec icon(atom() | String.t()) :: String.t()
    def icon(name)
        when name in [:eye, :eye_off, :lock, :lock_open, :inspect, :color, :variables] do
      ~s|<svg class="vis-builder-icon vis-builder-icon-#{name}" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">#{icon_inner(name)}</svg>|
    end

    # A root of the design as the node row's icon (spec/14 §18.13, #314): the seven the
    # schema names each drawn, any other as its first letter in a ring.
    def icon(root) when is_binary(root) do
      class = "vis-builder-icon vis-builder-icon-root vis-builder-icon-" <> root

      ~s|<svg class="#{class}" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">#{root_inner(root)}</svg>|
    end

    defp icon_inner(:eye),
      do:
        ~s|<path d="M2 12 C5 6 9 4 12 4 C15 4 19 6 22 12 C19 18 15 20 12 20 C9 20 5 18 2 12 Z"/><circle cx="12" cy="12" r="3"/>|

    defp icon_inner(:eye_off),
      do:
        ~s|<path d="M2 12 C5 6 9 4 12 4 C15 4 19 6 22 12 C19 18 15 20 12 20 C9 20 5 18 2 12 Z"/><circle cx="12" cy="12" r="3"/><path d="M4 20 L20 4"/>|

    defp icon_inner(:lock),
      do:
        ~s|<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11 V7 a4 4 0 0 1 8 0 V11"/>|

    # The shackle swung open: a site unlocked from its entry (§18.8, #381).
    defp icon_inner(:lock_open),
      do:
        ~s|<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11 V7 a4 4 0 0 1 8 0 V8"/>|

    # The panel row (§19.10).
    defp icon_inner(:inspect),
      do:
        ~s|<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M8 9 H16 M8 13 H16 M8 17 H12"/>|

    defp icon_inner(:color),
      do:
        ~s|<circle cx="12" cy="12" r="8"/><circle cx="9" cy="10" r="1.5" fill="currentColor" stroke="none"/><circle cx="14" cy="8.5" r="1.5" fill="currentColor" stroke="none"/><circle cx="15.5" cy="13" r="1.5" fill="currentColor" stroke="none"/>|

    defp icon_inner(:variables),
      do:
        ~s|<path d="M6 6 C4 6 4 10 4 12 C4 14 4 18 6 18"/><path d="M18 6 C20 6 20 10 20 12 C20 14 20 18 18 18"/><path d="M9 9 L15 15 M15 9 L9 15"/>|

    # The plot's corner with an axis each way, and a mark inside.
    defp root_inner("frame"),
      do:
        ~s|<path d="M5 4 V19 H20"/><path d="M5 19 L10 12 L14 15 L19 7"/><path d="M8 19 V21 M13 19 V21 M5 9 H3 M5 14 H3"/>|

    # The sine wave the signals carried.
    defp root_inner("sources"), do: ~s|<path d="M3 12 C6 4 9 4 12 12 C15 20 18 20 21 12"/>|

    # A brush.
    defp root_inner("styles"),
      do:
        ~s|<path d="M20 4 L10 14"/><path d="M9.5 13.5 C7 13.5 5 15.5 5 18 C5 19.5 4 20 3 20.5 C6 21.5 10.5 21 10.5 17 C10.5 15.5 10 14.5 9.5 13.5 Z" fill="currentColor" stroke="none"/>|

    # Two bars and a line.
    defp root_inner("marks"),
      do:
        ~s|<rect x="4" y="12" width="4" height="8" fill="currentColor" stroke="none"/><rect x="10" y="8" width="4" height="12" fill="currentColor" stroke="none"/><path d="M4 8 L11 4 L16 7 L20 3"/>|

    # A tag.
    defp root_inner("labels"),
      do:
        ~s|<path d="M4 4 H12 L20 12 L12 20 L4 12 Z"/><circle cx="8.5" cy="8.5" r="1.5" fill="currentColor" stroke="none"/>|

    # A swatch grid.
    defp root_inner("theme"),
      do:
        ~s|<rect x="4" y="4" width="7" height="7" rx="1" fill="currentColor" stroke="none"/><rect x="13" y="4" width="7" height="7" rx="1"/><rect x="4" y="13" width="7" height="7" rx="1"/><rect x="13" y="13" width="7" height="7" rx="1" fill="currentColor" stroke="none" opacity="0.5"/>|

    # A gradient disc.
    defp root_inner("defs"),
      do:
        ~s|<circle cx="12" cy="12" r="8"/><path d="M12 4 A8 8 0 0 1 12 20 Z" fill="currentColor" stroke="none"/>|

    # Any other root: its first letter in a ring.
    defp root_inner(root) do
      letter =
        root
        |> String.first()
        |> String.upcase()
        |> Phoenix.HTML.html_escape()
        |> Phoenix.HTML.safe_to_string()

      ~s|<circle cx="12" cy="12" r="9"/><text x="12" y="16" text-anchor="middle" font-size="11" font-weight="700" fill="currentColor" stroke="none">#{letter}</text>|
    end

    # -- the pictures ---------------------------------------------------------------------

    # A vertical alignment (§3.1): a bar of text against the point's line.
    defp picture(:vertical_align, align) when align in [:top, :middle, :baseline, :bottom] do
      y =
        case align do
          :top -> 6
          :middle -> 9.5
          :baseline -> 11
          :bottom -> 13
        end

      ~s|<path d="M3 12 H21" stroke="currentColor" stroke-width="1" opacity="0.5"/><rect x="8" y="#{y}" width="8" height="5" fill="currentColor"/>|
    end

    # An effect (§3.1): a plain square, one with a shadow, one blurred.
    defp picture(:effect, effect) when effect in [:none, :shadow, :blur] do
      case effect do
        :none ->
          ~s|<rect x="6" y="6" width="12" height="12" fill="currentColor"/>|

        :shadow ->
          ~s|<rect x="8" y="8" width="12" height="12" fill="currentColor" opacity="0.35"/><rect x="5" y="5" width="12" height="12" fill="currentColor"/>|

        # A soft edge: the square inside two wider, fainter ones. No filter, so no id.
        :blur ->
          ~s|<rect x="3" y="3" width="18" height="18" rx="4" fill="currentColor" opacity="0.15"/><rect x="5" y="5" width="14" height="14" rx="2" fill="currentColor" opacity="0.35"/><rect x="7" y="7" width="10" height="10" fill="currentColor"/>|
      end
    end

    # A paint's type (§18.6, D-178): no paint, a solid, a gradient down the square, one out
    # from its centre, hatching, a paint the design names. A gradient is drawn as
    # translucent bands, not a paint server: a glyph is shown once per choice in one HTML
    # document, so an id would repeat (#471); hatching is lines, not a pattern, for the same
    # reason.
    defp picture(:paint_type, type)
         when type in [:none, :solid, :linear, :radial, :hatch, :paint] do
      case type do
        :none ->
          ~s|<rect x="5" y="5" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M5 19 L19 5" stroke="currentColor" stroke-width="1.5"/>|

        :solid ->
          ~s|<rect x="5" y="5" width="14" height="14" fill="currentColor"/>|

        :linear ->
          bands([0.9, 0.75, 0.6, 0.45, 0.3, 0.2, 0.1], fn i -> {5, 5 + i * 2, 14, 2} end)

        :radial ->
          bands([0.2, 0.25, 0.3, 0.4], fn i -> {5 + i * 2, 5 + i * 2, 14 - i * 4, 14 - i * 4} end)

        :hatch ->
          ~s|<rect x="5" y="5" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1"/><path d="M5 12 L12 5 M5 19 L19 5 M12 19 L19 12" stroke="currentColor" stroke-width="1.5"/>|

        # A named paint: a swatch with its name's tag.
        :paint ->
          ~s|<rect x="5" y="5" width="14" height="14" fill="currentColor" opacity="0.35"/><path d="M8 9 H16 M8 12 H16 M8 15 H13" stroke="currentColor" stroke-width="1.5"/>|
      end
    end

    # A square's edge with the stroke where the style puts it: on it, twice, within, without.
    # A hatch's pattern (spec/14 §18.6, #684): lines, crossed lines, dots — drawn as lines
    # and circles, never a paint server, so no id (#471).
    defp picture(:hatch_pattern, pattern) when pattern in [:lines, :crosshatch, :dots] do
      frame =
        ~s|<rect x="5" y="5" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1"/>|

      inner =
        case pattern do
          :lines ->
            ~s|<path d="M5 12 L12 5 M5 19 L19 5 M12 19 L19 12" stroke="currentColor" stroke-width="1.5"/>|

          :crosshatch ->
            ~s|<path d="M5 12 L12 5 M5 19 L19 5 M12 19 L19 12 M12 5 L19 12 M5 5 L19 19 M5 12 L12 19" stroke="currentColor" stroke-width="1.2"/>|

          :dots ->
            for(
              x <- [8.5, 12, 15.5],
              y <- [8.5, 12, 15.5],
              into: "",
              do: ~s|<circle cx="#{x}" cy="#{y}" r="1.2" fill="currentColor"/>|
            )
        end

      frame <> inner
    end

    defp picture(:stroke_style, :center), do: picture(:stroke_style, :single)

    defp picture(:stroke_style, style) when style in [:single, :double, :inside, :outside] do
      fill = ~s|<rect x="6" y="6" width="12" height="12" fill="currentColor" opacity="0.25"/>|

      stroke =
        case style do
          :single ->
            ~s|<rect x="6" y="6" width="12" height="12" fill="none" stroke="currentColor" stroke-width="3"/>|

          :double ->
            ~s|<rect x="5" y="5" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.5"/><rect x="8.5" y="8.5" width="7" height="7" fill="none" stroke="currentColor" stroke-width="1.5"/>|

          :inside ->
            ~s|<rect x="7.5" y="7.5" width="9" height="9" fill="none" stroke="currentColor" stroke-width="3"/>|

          :outside ->
            ~s|<rect x="4.5" y="4.5" width="15" height="15" fill="none" stroke="currentColor" stroke-width="3"/>|
        end

      fill <> stroke
    end

    defp picture(:stroke_linejoin, join) when join in [:miter, :round, :bevel],
      do:
        ~s|<path d="M4 20 L12 5 L20 20" fill="none" stroke="currentColor" stroke-width="6" stroke-linejoin="#{join}" stroke-linecap="butt"/>|

    defp picture(:stroke_linecap, cap) when cap in [:butt, :round, :square],
      do:
        ~s|<path d="M7 12 H17" fill="none" stroke="currentColor" stroke-width="7" stroke-linecap="#{cap}"/>|

    defp picture(:curve, kind) do
      if kind in Schema.curve_types() do
        d = Line.new() |> Line.curve(kind) |> Line.generate([{2, 19}, {8, 6}, {15, 17}, {22, 5}])

        ~s|<path d="#{d}" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>|
      end
    end

    defp picture(:symbol, type) do
      if type in Symbol.types() do
        d = Symbol.new() |> Symbol.type(type) |> Symbol.size(120) |> Symbol.generate()
        ~s|<path d="#{d}" transform="translate(12 12)" fill="currentColor"/>|
      end
    end

    defp picture(:side, side) when side in [:top, :right, :bottom, :left] do
      edge =
        case side do
          :top -> ~s|<path d="M5 5 H19"/>|
          :bottom -> ~s|<path d="M5 19 H19"/>|
          :left -> ~s|<path d="M5 5 V19"/>|
          :right -> ~s|<path d="M19 5 V19"/>|
        end

      ~s|<rect x="5" y="5" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1" opacity="0.4"/><g fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round">#{edge}</g>|
    end

    defp picture(:anchor, anchor) do
      dot(
        case anchor do
          :top -> {12, 5}
          :bottom -> {12, 19}
          :left -> {5, 12}
          :right -> {19, 12}
          :start -> {6, 12}
          :middle -> {12, 12}
          :end -> {18, 12}
          _ -> nil
        end
      )
    end

    defp picture(:position, position) do
      dot(
        case position do
          :top_left -> {6, 6}
          :top_right -> {18, 6}
          :bottom_left -> {6, 18}
          :bottom_right -> {18, 18}
          :top -> {12, 6}
          :bottom -> {12, 18}
          :left -> {6, 12}
          :right -> {18, 12}
          _ -> nil
        end
      )
    end

    defp picture(:text_anchor, anchor) when anchor in [:start, :middle, :end] do
      {x1, x2, x3} =
        case anchor do
          :start -> {"M5 7 H19", "M5 12 H13", "M5 17 H16"}
          :middle -> {"M5 7 H19", "M8 12 H16", "M6.5 17 H17.5"}
          :end -> {"M5 7 H19", "M11 12 H19", "M8 17 H19"}
        end

      ~s|<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="#{x1}"/><path d="#{x2}"/><path d="#{x3}"/></g>|
    end

    defp picture(:orientation, :vertical),
      do:
        ~s|<g fill="currentColor"><rect x="5" y="9" width="4" height="10"/><rect x="10" y="5" width="4" height="14"/><rect x="15" y="12" width="4" height="7"/></g>|

    defp picture(:orientation, :horizontal),
      do:
        ~s|<g fill="currentColor"><rect x="5" y="5" width="10" height="4"/><rect x="5" y="10" width="14" height="4"/><rect x="5" y="15" width="7" height="4"/></g>|

    # A parent at the top left joined to a child at the bottom right (spec/14 §5.4.2).
    defp picture(:link, :curve),
      do:
        ~s|<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 5 C6 14 18 10 18 19"/></g>|

    defp picture(:link, :elbow),
      do:
        ~s|<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 5 H18 V19"/></g>|

    defp picture(:link, :line),
      do:
        ~s|<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 5 L18 19"/></g>|

    defp picture(:kind, :cartesian),
      do:
        ~s|<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M5 4 V19 H20"/><path d="M8 15 L12 9 L16 12 L19 6" stroke-width="1.5"/></g>|

    defp picture(:kind, :polar),
      do:
        ~s|<g fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4" stroke-width="1"/><path d="M12 12 L18 7" stroke-width="1.5"/></g>|

    defp picture(:kind, :geo),
      do:
        ~s|<g fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="8"/><ellipse cx="12" cy="12" rx="3.5" ry="8"/><path d="M4 12 H20 M5.5 8 H18.5 M5.5 16 H18.5"/></g>|

    defp picture(:kind, :facet),
      do:
        ~s|<g fill="none" stroke="currentColor" stroke-width="1.5"><rect x="4" y="4" width="7" height="7"/><rect x="13" y="4" width="7" height="7"/><rect x="4" y="13" width="7" height="7"/><rect x="13" y="13" width="7" height="7"/></g>|

    defp picture(_key, _value), do: nil

    # Rectangles at falling or rising opacity inside the square's outline: a gradient
    # drawn without a paint server, so with no id (#471).
    defp bands(opacities, rect) do
      fills =
        opacities
        |> Enum.with_index()
        |> Enum.map_join(fn {opacity, i} ->
          {x, y, w, h} = rect.(i)

          ~s|<rect x="#{x}" y="#{y}" width="#{w}" height="#{h}" fill="currentColor" opacity="#{opacity}"/>|
        end)

      fills <>
        ~s|<rect x="5" y="5" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1"/>|
    end

    defp dot(nil), do: nil

    defp dot({x, y}),
      do:
        ~s|<rect x="4" y="4" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1" opacity="0.4"/><circle cx="#{x}" cy="#{y}" r="3" fill="currentColor"/>|
  end
end
