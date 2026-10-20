defmodule Examples.ThemeLab do
  @moduledoc """
  The Theme lab of `/theme-lab` (spec/08 §7, #784, work item #785): a host theme built in
  code, and what a theme of 0.7.0 holds — its color table and the names it adds, steps
  pinned from a brand's tokens, its ramps, the colors it resolves, the forced-colors block
  of its stylesheet, a palette of its own over the default's, its defaults, and the
  contracts that refuse a theme which would break a meaning.

  Everything here is a value: the page (`ExamplesWeb.ThemeLabLive`) draws it.
  """

  import Visualize.Color, only: [color: 1, shade: 2, saturate: 2, lighten: 2, alpha: 2]

  alias Visualize.{Chart, Color, Theme}

  # The brand's tokens: a green the house adds, and two steps of red its design system
  # pins (`--vis-red-100`, `--vis-red-500`), the rest computed on the step curve.
  @brand "#0b6e4f"
  @red_tokens %{100 => "#fde8e8", 500 => "#d62728"}

  @doc """
  The house theme: the default with a brand color added, red's steps pinned, a palette of
  its own over the default's — a serif title in the brand, a dashed grid, the good role in
  the brand — and defaults every element inherits (spec/08 §7.1, §7.7, spec/14 §3.8).
  """
  @spec house() :: Theme.t()
  def house do
    Theme.new(
      name: "house",
      colors: %{"brand" => @brand, red: @red_tokens},
      styles: %{
        title: %{font: %{family: "Georgia, serif", size: 17, weight: :bold}, fill: color("brand")},
        grid: %{stroke: %{color: color(:grid), width: 1, dash: [2, 3]}},
        good: %{fill: color("brand"), stroke: %{color: color("brand")}}
      },
      defaults: %{stroke: %{width: 1.5}, font: %{family: "Georgia, serif"}}
    )
  end

  @doc "The code that builds `house/0`, as the page shows it."
  @spec house_code() :: String.t()
  def house_code do
    ~S"""
    import Visualize.Color

    house =
      Visualize.Theme.new(
        name: "house",
        # A name the table gains, and two steps of red pinned from the brand's tokens.
        colors: %{"brand" => "#0b6e4f", red: %{100 => "#fde8e8", 500 => "#d62728"}},
        # The house's own palette entries, over the default theme's.
        styles: %{
          title: %{font: %{family: "Georgia, serif", size: 17, weight: :bold}, fill: color("brand")},
          grid: %{stroke: %{color: color(:grid), width: 1, dash: [2, 3]}},
          good: %{fill: color("brand"), stroke: %{color: color("brand")}}
        },
        # What every element drawn under the theme inherits.
        defaults: %{stroke: %{width: 1.5}, font: %{family: "Georgia, serif"}}
      )

    Visualize.Theme.check(house)
    #=> :ok
    """
  end

  @doc """
  The theme's color table without the CSS named colors folded in: `{name, literal, added?}`
  for every name of `Theme.color_names/1` that is the theme's own or the library's (the
  furniture, the series, the roles, the hues), `added?` for a name the default theme lacks.
  """
  @spec table(Theme.t()) :: [{atom() | String.t(), String.t(), boolean()}]
  def table(theme) do
    default = Theme.color_names(Theme.default())

    for name <- Theme.color_names(theme),
        Map.has_key?(theme.colors, name) or Color.named(to_string(name)) == nil do
      {name, Color.resolve(color(name), theme, :literal), name not in default}
    end
  end

  @doc "The steps of `shade/2` the page draws, 0 to 1000."
  @spec steps() :: [non_neg_integer()]
  def steps, do: Enum.map(0..10, &(&1 * 100))

  @doc """
  Step `n` of red under `theme`: `{literal, css, pinned?}` — the color, what `:css` SVG
  writes for it, and whether the theme pins it.
  """
  @spec step(Theme.t(), non_neg_integer()) :: {String.t(), String.t(), boolean()}
  def step(theme, n) do
    c = shade(color(:red), n)

    {Color.resolve(c, theme, :literal), Color.resolve(c, theme, :css), pinned?(theme, :red, n)}
  end

  defp pinned?(theme, name, n), do: match?(%{^n => _}, Map.get(theme.colors, name))

  @doc "A ramp sampled at eleven positions with `Theme.ramp/3`: `{t, literal}`."
  @spec ramp(Theme.t(), atom()) :: [{float(), String.t()}]
  def ramp(theme, name) do
    for i <- 0..10, t = i / 10, do: {t, Theme.ramp(theme, name, t)}
  end

  @doc """
  Colors as values, resolved: `{expression, literal, css, oklch}` — `Color.resolve/3` in
  `:literal` mode (what a canvas and a PNG draw), in `:css` mode (what SVG writes, over the
  theme's custom properties), and the literal's `l c h` in OKLCH (`Color.to_oklch/1`).
  """
  @spec resolved(Theme.t()) :: [{String.t(), String.t(), String.t(), String.t()}]
  def resolved(theme) do
    for {expr, value} <- [
          {~S{color("brand")}, color("brand")},
          {~S{color("brand") |> saturate(0.5)}, color("brand") |> saturate(0.5)},
          {~S{color("brand") |> lighten(0.4)}, color("brand") |> lighten(0.4)},
          {"color(:red) |> shade(100)", color(:red) |> shade(100)},
          {"color(:red) |> shade(300)", color(:red) |> shade(300)},
          {"color(:bad) |> alpha(0.5)", color(:bad) |> alpha(0.5)}
        ] do
      literal = Color.resolve(value, theme, :literal)
      {expr, literal, Color.resolve(value, theme, :css), oklch(literal)}
    end
  end

  defp oklch(literal) do
    %{l: l, c: c, h: h} = literal |> Color.parse() |> Color.to_oklch()
    "oklch(#{fixed(l, 3)} #{fixed(c, 3)} #{fixed(h, 1)})"
  end

  defp fixed(x, digits), do: :erlang.float_to_binary(x * 1.0, decimals: digits)

  @doc "The `@media (forced-colors: active)` block of a theme's `stylesheet/1`."
  @spec forced_colors(Theme.t()) :: String.t()
  def forced_colors(theme) do
    [_before, block] = String.split(Theme.stylesheet(theme), "@media (forced-colors: active)")
    "@media (forced-colors: active)" <> String.trim_trailing(block)
  end

  @doc """
  The palette entries the house theme changes, as `Theme.style/2` answers them under each
  theme, and its root defaults (`Theme.defaults/1`) beside the default theme's.
  """
  @spec palette(Theme.t()) :: [{atom(), map(), map()}]
  def palette(theme) do
    for name <- [:title, :grid, :good],
        do: {name, Theme.style(Theme.default(), name), Theme.style(theme, name)}
  end

  @doc "The role chart: a bar per role, each in the style its row names (spec/14 §3.6)."
  @spec roles_design() :: map()
  def roles_design do
    %{
      version: 3,
      meta: %{name: "Service health", description: "A bar per role, styled by its name"},
      sources: %{"roles" => %{fields: ["role", "share"]}},
      frames: %{
        "main" => %{
          kind: :cartesian,
          margin: %{top: 36, right: 12, bottom: 28, left: 36},
          scales: %{
            "x" => %{kind: :band, padding: 0.25},
            "y" => %{kind: :linear, domain: [0, 100]}
          },
          axes: [
            %{scale: "x", side: :bottom},
            %{scale: "y", side: :left, ticks: 4, grid: true}
          ]
        }
      },
      marks: [
        %{
          type: :rect,
          data: "roles",
          channels: %{x0: "role", x1: "role", y0: 0, y1: "share"},
          style: {:field, "role"}
        }
      ],
      labels: [%{anchor: :title, text: ["Service health"]}]
    }
  end

  @doc "The role chart's rows: one per role the palette names."
  @spec roles_rows() :: [map()]
  def roles_rows do
    for {role, share} <- [good: 82, warning: 56, bad: 34, info: 64, neutral: 45],
        do: %{"role" => Atom.to_string(role), "share" => share}
  end

  @doc "The role chart under `theme`, drawn as a document `<svg>` (spec/02 §2.1)."
  @spec roles_svg(Theme.t(), String.t()) :: String.t()
  def roles_svg(theme, id) do
    {:ok, applied} =
      Chart.apply(roles_design(),
        sources: %{"roles" => roles_rows()},
        theme: theme,
        size: {360, 220}
      )

    Chart.render(applied, root: true, id: id)
  end

  @doc """
  The contract cases: a host theme written inline in a design, as a stored design carries
  it (spec/14 §2.1), each refused at its path with the measured value and the rule, and
  one that holds. `{id, title, theme}`.
  """
  @spec cases() :: [{String.t(), String.t(), map()}]
  def cases do
    [
      {"pale", "A role's fill under 3:1",
       %{styles: %{good: %{fill: "#c8e6c9", stroke: %{color: "#c8e6c9"}}}}},
      {"hue", "Two roles that differ only in hue",
       %{
         styles: %{
           good: %{fill: "#2e7d32", stroke: %{color: "#2e7d32"}, marker: %{shape: :circle}},
           bad: %{fill: "#c62828", stroke: %{color: "#c62828"}, marker: %{shape: :circle}}
         }
       }},
      {"unknown", "A name the table lacks", %{styles: %{bad: %{fill: color("crimson_brand")}}}},
      {"holds", "The same roles, fixed",
       %{
         colors: %{"crimson_brand" => "#b3261e"},
         styles: %{
           good: %{fill: "#2e7d32", stroke: %{color: "#2e7d32"}},
           bad: %{
             fill: color("crimson_brand"),
             stroke: %{color: color("crimson_brand"), dash: [2, 3]}
           }
         }
       }}
    ]
  end

  @doc "The ids of `cases/0`, the only words the page's case switch takes."
  @spec case_ids() :: [String.t()]
  def case_ids, do: for({id, _title, _theme} <- cases(), do: id)

  @doc """
  A case read as `Visualize.Chart.from_map/1` reads a stored design: `{:ok, svg}` drawn
  under the inline theme, or `{:error, messages}`, each fault worded by
  `Visualize.Chart.Validator.format/1`.
  """
  @spec check(String.t()) :: {:ok, String.t()} | {:error, [String.t()]}
  def check(id) do
    {^id, _title, theme} = List.keyfind(cases(), id, 0)

    case Chart.from_map(Map.put(roles_design(), :theme, theme)) do
      {:ok, chart} ->
        {:ok, applied} =
          Chart.apply(chart, sources: %{"roles" => roles_rows()}, size: {360, 220})

        {:ok, Chart.render(applied, root: true, id: "theme-lab-case")}

      {:error, faults} ->
        {:error, Enum.map(faults, &Chart.Validator.format/1)}
    end
  end

  @doc "A case's inline theme as Elixir, as the page shows it."
  @spec case_code(String.t()) :: String.t()
  def case_code(id) do
    {^id, _title, theme} = List.keyfind(cases(), id, 0)
    "theme: " <> inspect(theme, pretty: true, width: 80)
  end

  @doc """
  A chart page's theme in the lab (#792, work item #795): the theme of the listed `key`
  (`Examples.Themes`) beside Default — the code that builds it, the names of its color
  table whose color differs from Default's or that Default lacks (`{name, literal,
  default_literal | nil}`), red's steps under each, the palette entries it changes
  (`{name, default, own}`), the role chart under each, and its contract faults (none for a
  theme the list holds). `nil` for a key the list lacks, which the lab shows as its house.
  """
  @spec picked(term()) :: map() | nil
  def picked(key) do
    case Examples.Themes.entry(key) do
      nil -> nil
      entry -> picked_entry(entry)
    end
  end

  defp picked_entry(%{key: key, theme: theme} = entry) do
    default = Examples.Themes.default()

    Map.merge(entry, %{
      code: Examples.Themes.code(key),
      table: compare_table(theme, default),
      steps: for(n <- steps(), do: {n, step(theme, n), step(default, n)}),
      palette:
        for(
          name <- Theme.style_names(theme),
          Theme.style(theme, name) != Theme.style(default, name),
          do: {name, Theme.style(default, name), Theme.style(theme, name)}
        ),
      default_svg: roles_svg(default, "theme-lab-picked-default"),
      svg: roles_svg(theme, "theme-lab-picked"),
      violations: Theme.violations(theme)
    })
  end

  defp compare_table(theme, default) do
    defaults = Map.new(table(default), fn {name, literal, _added} -> {name, literal} end)

    for {name, literal, _added} <- table(theme),
        Map.get(defaults, name) != literal,
        do: {name, literal, Map.get(defaults, name)}
  end
end
