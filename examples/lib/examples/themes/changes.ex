defmodule Examples.Themes.Changes do
  @moduledoc """
  What a theme of the picker changes from the gallery's Default, and which of those changes
  a chart draws (spec/14 §12.6, #792, work item #795).

  A theme is plain data, so what it changes is read field by field: its **page** slots,
  its **series**, the entries of its **color table**, its **ramps**, its **palette
  styles** (a hatched fill named as such) and its **type** — the font, the sizes and the
  root defaults. Each is one *aspect*.

  Whether a chart draws an aspect is answered by drawing it: the chart under Default, and
  under Default with that one aspect taken from the theme. The two SVGs differ exactly when
  the chart draws something the aspect sets, whichever way it reaches it — a series slot,
  a `color(:red)`, a role style, a ramp a scale ranges over — so the answer needs no model
  of the chart, only its render. A role color that follows the status ramp is the ramp's,
  as it is in the theme: Color-safe changes only `:status`, and a chart that draws a role
  draws that ramp.
  """

  alias Examples.Charts.Design
  alias Examples.Themes
  alias Visualize.{Chart, Theme}

  @type aspect :: :page | :series | :colors | :ramps | :styles | :type

  @slots [:background, :surface, :text, :axis, :grid]
  @type_fields [:font_family, :font_size, :label_size, :title_size, :defaults]

  # Each aspect's fields of `Visualize.Theme`, in the order the panel lists them.
  @aspects [
    page: @slots,
    series: [:series],
    colors: [:colors],
    ramps: [:ramps],
    styles: [:styles],
    type: @type_fields
  ]

  @doc "The aspects, in the order the panel lists them."
  @spec aspects() :: [aspect()]
  def aspects, do: Keyword.keys(@aspects)

  @doc """
  What `theme` changes from the gallery's Default: `{aspect, changed}` for each aspect that
  differs, in `aspects/0`'s order — `changed` the slots, the color or ramp or palette names
  whose entries differ (sorted), the number of series colors, or the type fields.

      iex> Examples.Themes.Changes.of(Examples.Themes.theme("color_safe"))
      [ramps: [:status]]
      iex> Examples.Themes.Changes.of(Examples.Themes.default())
      []
  """
  @spec of(Theme.t()) :: [{aspect(), [atom() | String.t()] | pos_integer()}]
  def of(%Theme{} = theme) do
    default = Themes.default()

    for {aspect, _fields} <- @aspects,
        changed = changed(aspect, theme, default),
        changed not in [[], 0],
        do: {aspect, changed}
  end

  defp changed(:page, theme, default),
    do: Enum.filter(@slots, &(Map.fetch!(theme, &1) != Map.fetch!(default, &1)))

  defp changed(:series, %{series: series}, %{series: series}), do: 0
  defp changed(:series, %{series: series}, _default), do: length(series)

  defp changed(:type, theme, default),
    do: Enum.filter(@type_fields, &(Map.fetch!(theme, &1) != Map.fetch!(default, &1)))

  defp changed(field, theme, default) when field in [:colors, :ramps, :styles] do
    ours = Map.fetch!(theme, field)
    theirs = Map.fetch!(default, field)

    (Map.keys(ours) ++ Map.keys(theirs))
    |> Enum.uniq()
    |> Enum.filter(&(Map.get(ours, &1) != Map.get(theirs, &1)))
    |> Enum.sort_by(&to_string/1)
  end

  @doc """
  The palette names of `names` whose entry under `theme` fills with a hatch (spec/14
  §3.1) — the print theme's roles.
  """
  @spec hatched(Theme.t(), [atom()]) :: [atom()]
  def hatched(%Theme{styles: styles}, names),
    do: Enum.filter(names, &match?(%{fill: %{type: :hatch}}, Map.get(styles, &1)))

  @doc """
  Default with only `aspect` taken from `theme`: the theme a chart is drawn under to learn
  whether it draws that aspect. A struct update, as a comparison needs — never checked
  (spec/08 §7.5), since the default's role styles on another theme's page are a mix no
  host would build.
  """
  @spec only(Theme.t(), aspect()) :: Theme.t()
  def only(%Theme{} = theme, aspect) do
    fields = Keyword.fetch!(@aspects, aspect)
    struct!(Themes.default(), Map.take(theme, fields))
  end

  @doc """
  The aspects `theme` changes that the gallery chart `module` draws, in `aspects/0`'s
  order: each one whose `only/2` theme draws the chart other than Default does. A chart
  that draws none of them looks under `theme` as it does under Default.
  """
  @spec drawn(module(), Theme.t()) :: [aspect()]
  def drawn(module, %Theme{} = theme), do: drawn(module, theme, fn -> svg(module, nil) end)

  @doc """
  `drawn/2` against `default`, the chart's SVG under Default as `svg/2` draws it — or a
  function that draws it, called only when the theme changes something — for a caller
  that compares many themes on one chart.
  """
  @spec drawn(module(), Theme.t(), String.t() | (-> String.t())) :: [aspect()]
  def drawn(module, %Theme{} = theme, default) do
    case of(theme) do
      [] ->
        []

      changes ->
        default = if is_function(default, 0), do: default.(), else: default
        for {aspect, _changed} <- changes, svg(module, only(theme, aspect)) != default, do: aspect
    end
  end

  @doc """
  The gallery chart `module` drawn as SVG under `theme` — a `Visualize.Theme`, or a key of
  `Examples.Themes` (Default for `nil`) — the document `drawn/3` compares.
  """
  @spec svg(module(), Theme.t() | String.t() | nil) :: String.t()
  def svg(module, theme), do: module |> Design.applied(theme: theme) |> Chart.render()
end
