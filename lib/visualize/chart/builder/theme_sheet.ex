if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.ThemeSheet do
    @moduledoc """
    The theme mode's preview sheet (spec/14 §20.3, D-139): fixed sample charts drawn
    through the theme being edited, and the designs a person adds from the store.

    A theme is judged against everything it must serve, so the samples cover what a theme
    carries — the categorical series, the five roles, the thermal and diverging ramps, and
    axes, grid and text — and a card of the chrome's swatches. Each is drawn through the
    ordinary path, `Visualize.Chart.apply/2` then `render/2`, with `resolve: :literal`, so
    the sheet shows the edited theme and no stylesheet of the host's page re-points a slot
    under it.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    import Visualize.Chart.Build

    alias Visualize.Chart
    alias Visualize.Chart.Builder.Themes
    alias Visualize.Chart.Validator
    alias Visualize.Theme

    # A sample's size: small enough that the sheet shows them side by side.
    @size {300, 180}
    @margin %{top: 28, right: 14, bottom: 26, left: 34}
    @states ~w(good warning bad info neutral)
    @lines ~w(a b c d e f g h)

    attr(:id, :string, required: true, doc: "the sheet's id")
    attr(:theme, :any, required: true, doc: "the `%Visualize.Theme{}` being edited")

    attr(:designs, :list,
      default: [],
      doc: "designs from the store, each `%{id, name, design}`, drawn after the samples"
    )

    attr(:choices, :list, default: [], doc: "the store's composites to add, `{name, id}` each")
    attr(:sources, :map, default: %{}, doc: "the pool a stored design binds to")
    attr(:vars, :map, default: %{}, doc: "the values a stored design's variables take")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the sheet's events")

    @doc """
    Renders the preview sheet (spec/14 §20.3): `<div class="vis-builder-theme-sheet">` of
    `<figure class="vis-builder-theme-sample">` cards — the chrome's swatches, each fixed
    sample, then each design from the store with its **×** — and the form that adds a design.
    """
    def sheet(assigns) do
      theme = drawable(assigns.theme)

      assigns =
        assign(assigns,
          drawn: theme,
          samples: Enum.map(samples(), &drawn(&1, theme, size: @size)),
          stored:
            Enum.map(
              assigns.designs,
              &drawn(&1, theme,
                sources: assigns.sources,
                vars: assigns.vars
              )
            )
        )

      ~H"""
      <div id={@id} class="vis-builder-theme-sheet" style={"background: #{@drawn.background}"}>
        <figure class="vis-builder-theme-sample vis-builder-theme-chrome">
          <div class="vis-builder-theme-swatches">
            <span
              :for={colour <- @drawn.series}
              class="vis-builder-theme-chip"
              style={"background: #{colour}"}
              title={colour}
            ></span>
          </div>
          <div class="vis-builder-theme-swatches">
            <span
              :for={slot <- [:background, :surface, :text, :axis, :grid]}
              class="vis-builder-theme-chip vis-builder-theme-chip-named"
              style={"background: #{Map.fetch!(@drawn, slot)}; color: #{Theme.ink(@drawn, Map.fetch!(@drawn, slot))}"}
              title={"#{slot} #{Map.fetch!(@drawn, slot)}"}
            >{slot}</span>
          </div>
          <figcaption style={"color: #{@drawn.text}; font-family: #{@drawn.font_family}"}>chrome</figcaption>
        </figure>
        <figure :for={card <- @samples ++ @stored} class="vis-builder-theme-sample" data-sample={card.id}>
          <svg
            :if={card.markup}
            class="vis-builder-theme-chart"
            viewBox={"0 0 #{card.width} #{card.height}"}
            role="img"
            aria-label={card.title}
          >{card.markup}</svg>
          <ul :if={card.errors != []} class="vis-builder-errors">
            <li :for={line <- card.errors} class="vis-builder-error">{line}</li>
          </ul>
          <figcaption style={"color: #{@drawn.text}; font-family: #{@drawn.font_family}"}>
            {card.title}
            <button
              :if={card.stored?}
              type="button"
              class="vis-builder-theme-remove"
              title={"take #{card.title} off the sheet"}
              aria-label={"take #{card.title} off the sheet"}
              phx-click="theme_design_remove"
              phx-value-id={card.id}
              phx-target={@target}
            >×</button>
          </figcaption>
        </figure>
        <form
          :if={@choices != []}
          id={@id <> "-designs"}
          class="vis-builder-theme-designs"
          phx-submit="theme_design_add"
          phx-target={@target}
        >
          <label class="vis-builder-control-label" for={@id <> "-design"}>preview a design</label>
          <select id={@id <> "-design"} name="id">
            <option :for={{name, id} <- @choices} value={id}>{name}</option>
          </select>
          <button type="submit" class="vis-builder-add" title="add the design to the sheet" aria-label="add the design to the sheet">+</button>
        </form>
      </div>
      """
    end

    # One card: the design applied and rendered in the theme, or the faults application
    # reported (spec/14 §18.4), at the frame's own size.
    defp drawn(sample, theme, opts) do
      sources = Map.get(sample, :sources) || Keyword.get(opts, :sources, %{})
      vars = Keyword.get(opts, :vars, %{})
      size = Keyword.take(opts, [:size])

      base = %{
        id: sample.id,
        title: Map.get(sample, :title) || Map.get(sample, :name),
        stored?: not Map.has_key?(sample, :title)
      }

      case Chart.apply(sample.design, [sources: sources, vars: vars, theme: theme] ++ size) do
        {:ok, %{frame: %{size: %{width: w, height: h}}} = applied} ->
          Map.merge(base, %{
            markup: Phoenix.HTML.raw(Chart.render(applied, resolve: :literal)),
            errors: [],
            width: w,
            height: h
          })

        {:error, errors} ->
          Map.merge(base, %{
            markup: nil,
            errors: Enum.map(errors, &Validator.format/1),
            width: 0,
            height: 0
          })
      end
    end

    @doc """
    The theme with every ramp it cannot draw — fewer than two anchors, an anchor that is not
    a colour — and an empty series replaced by the default theme's, so a sheet always draws
    while the editor names the fault (spec/14 §20.3).

        iex> theme = %{Visualize.Theme.default() | ramps: %{status: ["#nope"]}, series: []}
        iex> drawn = Visualize.Chart.Builder.ThemeSheet.drawable(theme)
        iex> {drawn.ramps.status, drawn.series == Visualize.Theme.default().series}
        {["#4ca34b", "#bd7407", "#c23238"], true}
    """
    @spec drawable(Theme.t()) :: Theme.t()
    def drawable(%Theme{} = theme) do
      default = Theme.default()

      ramps =
        for name <- Theme.ramp_names(), into: %{} do
          anchors = Map.get(theme.ramps || %{}, name)
          {name, if(drawable_ramp?(anchors), do: anchors, else: Map.fetch!(default.ramps, name))}
        end

      roles =
        for name <- [:info, :neutral], into: %{} do
          colour = Map.get(theme.roles || %{}, name)
          {name, if(colour?(colour), do: colour, else: Map.fetch!(default.roles, name))}
        end

      chrome =
        for slot <- [:background, :surface, :text, :axis, :grid], into: %{} do
          value = Map.fetch!(theme, slot)
          {slot, if(colour?(value), do: value, else: Map.fetch!(default, slot))}
        end

      series =
        case Enum.filter(List.wrap(theme.series), &colour?/1) do
          [] -> default.series
          colours -> colours
        end

      theme
      |> Map.merge(chrome)
      |> Map.merge(%{ramps: ramps, roles: roles, series: series})
    end

    defp drawable_ramp?([_, _ | _] = anchors), do: Enum.all?(anchors, &colour?/1)
    defp drawable_ramp?(_anchors), do: false

    defp colour?(value), do: Themes.readable?(value)

    @doc """
    The fixed samples (spec/14 §20.3), each `%{id, title, design, sources}`: categorical
    series, a status chart in the five roles, a thermal and a diverging chart, and a titled
    chart of axes, grid and text.
    """
    @spec samples() :: [%{id: String.t(), title: String.t(), design: map(), sources: map()}]
    def samples do
      [
        %{id: "series", title: "series", design: series(), sources: %{s: series_rows()}},
        %{id: "status", title: "status — the roles", design: status(), sources: %{st: states()}},
        %{id: "thermal", title: "thermal", design: thermal(), sources: %{c: cells()}},
        %{id: "diverging", title: "diverging", design: diverging(), sources: %{d: deviations()}},
        %{id: "axes", title: "axes, grid and text", design: axes(), sources: %{r: readings()}}
      ]
    end

    defp fold(fragments) do
      {:ok, design} = Chart.compose(fragments)
      design
    end

    defp frame, do: cartesian(margin: @margin, background: :background)

    defp series do
      fold([
        chart(meta: %{name: "Series"}),
        source(:s, [:x, :y, :series]),
        style(:line, stroke: {:field, :series}, stroke_width: 2),
        frame(),
        linear_scale(:x),
        linear_scale(:y, domain: [0, :auto]),
        ordinal_scale(:color, domain: @lines),
        axis(:x, :bottom, ticks: 4),
        axis(:y, :left, ticks: 3),
        line(:s, %{x: :x, y: :y, series: :series}, style: :line)
      ])
    end

    defp series_rows do
      for {s, i} <- Enum.with_index(@lines), x <- 0..8 do
        %{series: s, x: x, y: Float.round(2 + i + :math.sin(x / 2 + i), 3)}
      end
    end

    defp status do
      fold([
        chart(meta: %{name: "Status"}),
        source(:st, [:state, :n]),
        style(:bar, fill: {:field, :state}),
        frame(),
        band_scale(:x, padding: 0.2),
        linear_scale(:y, domain: [0, :auto]),
        ordinal_scale(:color,
          domain: @states,
          range: [:good, :warning, :bad, :info, :neutral]
        ),
        axis(:x, :bottom),
        axis(:y, :left, ticks: 3),
        rect(:st, %{x0: :state, x1: :state, y0: 0, y1: :n}, style: :bar)
      ])
    end

    defp states do
      Enum.zip_with(@states, [9, 5, 2, 6, 4], &%{state: &1, n: &2})
    end

    defp thermal do
      fold([
        chart(meta: %{name: "Thermal"}),
        source(:c, [:x, :x1, :y, :t]),
        frame(),
        linear_scale(:x, domain: [0, 12]),
        band_scale(:y, domain: ~w(north east south west)),
        sequential_scale(:color, domain: [-10, 30], range: {:ramp, :thermal}),
        axis(:x, :bottom, ticks: 4),
        axis(:y, :left),
        rect(:c, %{x0: :x, x1: :x1, y0: :y, y1: :y, value: :t})
      ])
    end

    defp cells do
      for {y, j} <- Enum.with_index(~w(north east south west)), x <- 0..11 do
        %{x: x, x1: x + 1, y: y, t: Float.round(-10 + 40 * (x / 11) * (0.55 + j * 0.15), 2)}
      end
    end

    defp diverging do
      fold([
        chart(meta: %{name: "Diverging"}),
        source(:d, [:k, :v]),
        frame(),
        band_scale(:x, padding: 0.1),
        linear_scale(:y, domain: [-5, 5]),
        diverging_scale(:color, domain: [-5, 0, 5], range: {:ramp, :diverging}),
        axis(:y, :left, ticks: 3),
        rect(:d, %{x0: :k, x1: :k, y0: 0, y1: :v, value: :v})
      ])
    end

    defp deviations, do: for(k <- 0..10, do: %{k: k, v: k - 5})

    defp axes do
      fold([
        chart(meta: %{name: "Axes, grid and text"}),
        source(:r, [:t, :v]),
        style(:line, stroke: :series_1, stroke_width: 2),
        frame(),
        linear_scale(:t),
        linear_scale(:v, domain: [0, :auto], nice: true),
        axis(:t, :bottom, ticks: 4),
        axis(:v, :left, ticks: 4, grid: true),
        label(:title, ["Readings"]),
        label({:axis, :t}, ["hour"]),
        line(:r, %{x: :t, y: :v}, scales: %{x: :t, y: :v}, style: :line)
      ])
    end

    defp readings do
      for t <- 0..12, do: %{t: t, v: Float.round(40 + 25 * :math.sin(t / 2.5), 2)}
    end
  end
end
