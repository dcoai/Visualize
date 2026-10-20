defmodule ExamplesWeb.ThemeLabLive do
  @moduledoc """
  The Theme lab (spec/08 §7, #784, work item #785): `Examples.ThemeLab`'s house theme, built
  in code, and what it holds — its color table, its pinned steps, a ramp, colors resolved
  in both modes and in OKLCH, the forced-colors block of its stylesheet, its palette and
  defaults drawn beside the default theme's, the contracts that refuse a theme, and the
  print theme's hatched roles on a grayscale view.

  The page's three switches — forced colors, grayscale and the contract case — each match
  their parameter against a fixed list of words, so no event makes an atom.
  """
  use Phoenix.LiveView

  alias Examples.ThemeLab
  alias ExamplesWeb.{Highlight, Panel}
  alias Visualize.Theme

  @forced ~w(system forced)
  @gray ~w(color gray)
  @rule "@media (forced-colors: active)"

  @impl true
  def mount(_params, _session, socket) do
    house = ThemeLab.house()

    {:ok,
     assign(socket,
       house: house,
       table: ThemeLab.table(house),
       steps:
         for(
           n <- ThemeLab.steps(),
           do: {n, ThemeLab.step(house, n), ThemeLab.step(Theme.default(), n)}
         ),
       ramps: for(name <- [:thermal, :status], do: {name, ThemeLab.ramp(house, name)}),
       resolved: ThemeLab.resolved(house),
       stylesheet: Theme.stylesheet(house),
       forced_block: ThemeLab.forced_colors(house),
       palette: ThemeLab.palette(house),
       default_svg: ThemeLab.roles_svg(Theme.default(), "theme-lab-default"),
       house_svg: ThemeLab.roles_svg(house, "theme-lab-house"),
       plain_svg: ThemeLab.roles_svg(Theme.default(), "theme-lab-plain"),
       print_svg: ThemeLab.roles_svg(Theme.print(), "theme-lab-print"),
       forced: "system",
       gray: "gray"
     )
     |> pick_case("pale")}
  end

  @impl true
  def handle_event("forced", %{"mode" => mode}, socket) when mode in @forced,
    do: {:noreply, assign(socket, forced: mode)}

  def handle_event("gray", %{"mode" => mode}, socket) when mode in @gray,
    do: {:noreply, assign(socket, gray: mode)}

  def handle_event("case", %{"case" => id}, socket) do
    if id in ThemeLab.case_ids(),
      do: {:noreply, pick_case(socket, id)},
      else: {:noreply, socket}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp pick_case(socket, id),
    do:
      assign(socket, case: id, case_code: ThemeLab.case_code(id), case_result: ThemeLab.check(id))

  # The house stylesheet as the page carries it: as written, or with its forced-colors
  # block's media condition read as always true, previewing a high-contrast viewer.
  defp stylesheet(css, "system"), do: css
  defp stylesheet(css, "forced"), do: String.replace(css, @rule, "@media all")

  # What `:css` SVG writes for a pinned step and a computed one, as Elixir a reader can read.
  defp css_code(steps) do
    for {n, {_literal, css, pinned}, _default} <- steps, n in [100, 300] do
      ~s|Visualize.Color.resolve(shade(color(:red), #{n}), house, :css)\n#=> #{inspect(css)}#{if pinned, do: "  # pinned", else: ""}|
    end
    |> Enum.join("\n\n")
  end

  defp name(name) when is_atom(name), do: ":" <> Atom.to_string(name)
  defp name(name), do: inspect(name)

  @impl true
  def render(assigns) do
    ~H"""
    <ExamplesWeb.SiteHeader.header tab={:theme_lab} />
    <main class="theme-lab">
      <a href="/" class="back-link"><span>&larr;</span> Back to Charts</a>
      <h2>Theme lab</h2>
      <p class="panel-note">
        A host's theme, built in code with <code>Visualize.Theme.new/1</code>: a brand color
        added to the table, two steps of red pinned from the brand's tokens, a palette of its
        own over the default theme's, and defaults every element inherits. Each section shows
        one thing the theme now holds.
      </p>

      <div class="panels">
        <Panel.panel id="panel-house">
          <:title>The house theme</:title>
          <Highlight.code code={ThemeLab.house_code()} />
        </Panel.panel>

        <Panel.panel id="panel-table">
          <:title>Its color table</:title>
          <p class="panel-note">
            <code>Visualize.Theme.color_names(house)</code>, the CSS named colors left out:
            the furniture, the series, the roles and the hues are names, and <code>color(name)</code>
            finds each in the theme's own table first. The
            house adds <strong>"brand"</strong>; its red is pinned, so <code>:bad</code>,
            the status ramp's red end, follows.
          </p>
          <ul class="lab-swatches">
            <li :for={{name, literal, added} <- @table} class={if added, do: "added"}>
              <span class="lab-swatch" style={"background: #{literal}"}></span>
              <code>{name(name)}</code> <span class="lab-hex">{literal}</span>
            </li>
          </ul>
        </Panel.panel>

        <Panel.panel id="panel-steps">
          <:title>Steps, pinned from the brand's tokens</:title>
          <p class="panel-note">
            <code>shade(color(:red), n)</code>
            from 0 to 1000 under the house theme, the
            default's steps beneath. The house pins 100 and 500
            (<code>colors: %{"{red: %{100 => \"#fde8e8\", 500 => \"#d62728\"}}"}</code>):
            a pinned step is its own custom property, <code>--vis-red-100</code>, which
            <code>stylesheet/1</code>
            declares, and the steps between are computed on the curve in OKLCH.
          </p>
          <table class="lab-steps">
            <tr>
              <th>n</th>
              <td :for={{n, _house, _default} <- @steps}>{n}</td>
            </tr>
            <tr>
              <th>house</th>
              <td
                :for={{n, {literal, css, pinned}, _default} <- @steps}
                class={if pinned, do: "pinned"}
              >
                <span class="lab-swatch" style={"background: #{literal}"} title={css}></span>
                <span :if={pinned} class="lab-pin" data-step={n}>pinned</span>
              </td>
            </tr>
            <tr>
              <th>default</th>
              <td :for={{_n, _house, {literal, css, _pinned}} <- @steps}>
                <span class="lab-swatch" style={"background: #{literal}"} title={css}></span>
              </td>
            </tr>
          </table>
          <p class="panel-note">
            What <code>:css</code> SVG writes for a pinned step and a computed one:
          </p>
          <Highlight.code code={css_code(@steps)} />
        </Panel.panel>

        <Panel.panel id="panel-ramps">
          <:title>A ramp</:title>
          <p class="panel-note">
            <code>Visualize.Theme.ramp(house, name, t)</code>
            at eleven positions: the anchors spread over 0..1 and interpolated in CIE Lab.
          </p>
          <div :for={{name, stops} <- @ramps} class="lab-ramp">
            <code>{name(name)}</code>
            <span
              :for={{t, literal} <- stops}
              class="lab-swatch"
              style={"background: #{literal}"}
              title={"t = #{t}: #{literal}"}
            ></span>
          </div>
        </Panel.panel>

        <Panel.panel id="panel-resolve">
          <:title>Colors resolved: literal, CSS and OKLCH</:title>
          <p class="panel-note">
            <code>Visualize.Color.resolve(value, house, :literal)</code>
            is what a canvas and a PNG draw; <code>:css</code>
            is what SVG writes, a transform as relative <code>oklch(from …)</code>
            over the theme's custom properties, so a theme switch recolors it too. The last
            column is the literal in OKLCH, <code>Visualize.Color.to_oklch/1</code>;
            <code>saturate</code>
            moves the chroma toward full there.
          </p>
          <table class="lab-resolve">
            <tr>
              <th>value</th>
              <th></th>
              <th>:literal</th>
              <th>:css</th>
              <th>OKLCH</th>
            </tr>
            <tr :for={{expr, literal, css, oklch} <- @resolved}>
              <td><code>{expr}</code></td>
              <td><span class="lab-swatch" style={"background: #{literal}"}></span></td>
              <td><code>{literal}</code></td>
              <td><code class="lab-wrap">{css}</code></td>
              <td><code>{oklch}</code></td>
            </tr>
          </table>
        </Panel.panel>

        <Panel.panel id="panel-palette">
          <:title>A palette of its own, and defaults</:title>
          <p class="panel-note">
            The same design — a bar per role, each styled by its name,
            <code>style: {"{:field, \"role\"}"}</code>
            — under the default theme and under the house theme. The house's <code>styles</code>
            replace three palette entries whole (a serif title in the brand, a dashed grid,
            the good role in the brand), and its <code>defaults</code>
            give every element a 1.5 stroke and the serif face.
          </p>
          <div class="lab-pair">
            <figure>
              {Phoenix.HTML.raw(@default_svg)}
              <figcaption>Visualize.Theme.default()</figcaption>
            </figure>
            <figure>
              {Phoenix.HTML.raw(@house_svg)}
              <figcaption>house</figcaption>
            </figure>
          </div>
          <table class="lab-palette">
            <tr>
              <th>entry</th>
              <th>Theme.style(default, name)</th>
              <th>Theme.style(house, name)</th>
            </tr>
            <tr :for={{name, default, own} <- @palette}>
              <td><code>{name(name)}</code></td>
              <td><code class="lab-wrap">{inspect(default)}</code></td>
              <td><code class="lab-wrap">{inspect(own)}</code></td>
            </tr>
          </table>
          <p class="panel-note">
            <code>Visualize.Theme.defaults(house)</code>, the root every element inherits:
          </p>
          <Highlight.code code={inspect(Theme.defaults(@house), pretty: true, width: 90)} />
        </Panel.panel>

        <Panel.panel id="panel-forced">
          <:title>Forced colors</:title>
          <p class="panel-note">
            <code>stylesheet/1</code> ends with a block that maps the furniture to the user's
            system colors in high-contrast mode. The bars keep their roles' colors, which
            the system may still override; the text, axes, grid and background follow the
            viewer. <em>Forced</em> reads the block's media condition as always true, to
            preview it here.
          </p>
          <p class="lab-switch" role="group" aria-label="Forced colors">
            <button
              :for={mode <- ~w(system forced)}
              type="button"
              phx-click="forced"
              phx-value-mode={mode}
              aria-pressed={to_string(mode == @forced)}
            >
              {if mode == "system", do: "Your system", else: "Forced"}
            </button>
          </p>
          <style>
            <%= Phoenix.HTML.raw(stylesheet(@stylesheet, @forced)) %>
          </style>
          <div class="vis-theme-house lab-forced">
            {Phoenix.HTML.raw(ThemeLab.roles_svg(@house, "theme-lab-forced"))}
          </div>
          <Highlight.code code={@forced_block} />
        </Panel.panel>

        <Panel.panel id="panel-contracts">
          <:title>Contracts: a theme refused, and one that holds</:title>
          <p class="panel-note">
            A theme a stored design carries is checked as it is read
            (<code>Visualize.Chart.from_map/1</code>), each refusal at its path with the
            value measured and the rule broken; <code>Visualize.Theme.new/1</code>
            raises on the same, and <code>Visualize.Theme.check/1</code>
            answers it.
          </p>
          <p class="lab-switch" role="group" aria-label="Contract case">
            <button
              :for={{id, title, _theme} <- ThemeLab.cases()}
              type="button"
              phx-click="case"
              phx-value-case={id}
              aria-pressed={to_string(id == @case)}
            >
              {title}
            </button>
          </p>
          <Highlight.code code={@case_code} />
          <%= case @case_result do %>
            <% {:error, messages} -> %>
              <ul class="lab-faults">
                <li :for={message <- messages} class="lab-fault">{message}</li>
              </ul>
            <% {:ok, svg} -> %>
              <p class="lab-holds">Accepted: the design reads, and draws under its own theme.</p>
              {Phoenix.HTML.raw(svg)}
          <% end %>
        </Panel.panel>

        <Panel.panel id="panel-print">
          <:title>Print, in grayscale</:title>
          <p class="panel-note">
            The same role bars under the default theme and under <code>Visualize.Theme.print()</code>,
            which hatches its role fills: <code>:good</code>
            and <code>:warning</code>
            diagonal lines, <code>:bad</code>
            a crosshatch, <code>:info</code>
            dots. On a grayscale view the default's roles fall to near grays; the print
            theme's keep their meaning.
          </p>
          <p class="lab-switch" role="group" aria-label="Grayscale">
            <button
              :for={mode <- ~w(gray color)}
              type="button"
              phx-click="gray"
              phx-value-mode={mode}
              aria-pressed={to_string(mode == @gray)}
            >
              {if mode == "gray", do: "Grayscale", else: "Color"}
            </button>
          </p>
          <div class={"lab-pair" <> if(@gray == "gray", do: " lab-gray", else: "")}>
            <figure>
              {Phoenix.HTML.raw(@plain_svg)}
              <figcaption>Visualize.Theme.default()</figcaption>
            </figure>
            <figure>
              {Phoenix.HTML.raw(@print_svg)}
              <figcaption>Visualize.Theme.print()</figcaption>
            </figure>
          </div>
        </Panel.panel>
      </div>
    </main>

    <style>
      .theme-lab .lab-swatches { display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 0.3rem 1rem; list-style: none; padding: 0; font-size: 0.85rem; }
      .theme-lab .lab-swatches li.added { font-weight: bold; }
      .theme-lab .lab-swatch { display: inline-block; width: 1.4rem; height: 1.4rem; border: 1px solid #0002; border-radius: 3px; vertical-align: middle; }
      .theme-lab .lab-hex { color: #666; }
      .theme-lab table { border-collapse: collapse; font-size: 0.8rem; }
      .theme-lab th, .theme-lab td { padding: 0.25rem 0.4rem; text-align: left; vertical-align: middle; }
      .theme-lab .lab-steps td { text-align: center; }
      .theme-lab .lab-steps td.pinned .lab-swatch { outline: 2px solid #333; outline-offset: 1px; }
      .theme-lab .lab-pin { display: block; font-size: 0.7rem; color: #333; }
      .theme-lab .lab-wrap { word-break: break-all; }
      .theme-lab .lab-ramp { display: flex; gap: 2px; align-items: center; margin: 0.3rem 0; }
      .theme-lab .lab-ramp code { width: 6rem; }
      .theme-lab .lab-pair { display: flex; flex-wrap: wrap; gap: 1rem; }
      .theme-lab .lab-pair figure { margin: 0; }
      .theme-lab .lab-pair figcaption { font-family: monospace; font-size: 0.8rem; color: #555; }
      .theme-lab .lab-gray svg { filter: grayscale(1); }
      .theme-lab .lab-switch button { margin-right: 0.35rem; }
      .theme-lab .lab-switch button[aria-pressed="true"] { font-weight: bold; }
      .theme-lab .lab-forced { background: var(--vis-background, #fff); display: inline-block; padding: 0.25rem; }
      .theme-lab .lab-fault { color: #a3171c; font-family: monospace; font-size: 0.85rem; }
      .theme-lab .lab-holds { color: #1d6b2b; font-weight: bold; }
    </style>
    """
  end
end
