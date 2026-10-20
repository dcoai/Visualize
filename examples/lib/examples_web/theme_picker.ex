defmodule ExamplesWeb.ThemePicker do
  @moduledoc """
  The chart page's theme picker (spec/14 §12.6, #792, work item #794): a button per theme
  of `Examples.Themes.list/0` — the built-in themes and the host themes, each a real
  `Visualize.Theme` — showing its first five series colors and its name, the picked one
  marked. A press pushes `theme` with the theme's key, which `pick/2` looks up in the same
  list, so there is no list of names beside the themes' own and no atom made from a press.

  Beside it, **What this theme changes** (`changes/1`, work item #795): what the picked
  theme changes from Default, aspect by aspect (`Examples.Themes.Changes`), whether the
  chart in view draws each, a link to the chart's *Why it looks as it does* panel, which
  explains an element under the picked theme, and *Open in Theme lab*. Whether the chart
  draws an aspect is learned by drawing it (`Examples.Themes.Changes.drawn/2`), off the
  page's process once it is connected (`measure/1`), so a heavy chart never holds the page.
  """

  use Phoenix.Component

  import Phoenix.LiveView, only: [connected?: 1, start_async: 3]

  alias Examples.Themes
  alias Examples.Themes.Changes

  @doc """
  The key a press of `word` picks: `word` when the list holds it, else `current`, so a word
  the list lacks changes nothing.

      iex> ExamplesWeb.ThemePicker.pick("default", "print")
      "print"
      iex> ExamplesWeb.ThemePicker.pick("winter", "no_such_theme")
      "winter"
  """
  @spec pick(String.t(), term()) :: String.t()
  def pick(current, word) do
    case Themes.entry(word) do
      nil -> current
      %{key: key} -> key
    end
  end

  @doc """
  The page with what the chart in view draws of its picked theme measured: at once before
  the page connects, and in the page's `:theme_drawn` async once it has, the answer
  (`theme_drawn`) cleared until it arrives. The answer carries the theme's key and the
  chart's slug it was measured for, so a late one for another pick is never shown.
  """
  @spec measure(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def measure(%{assigns: %{module: module, slug: slug, theme: key}} = socket) do
    theme = Themes.theme(key)

    if connected?(socket) do
      socket
      |> assign(theme_drawn: nil)
      |> start_async(:theme_drawn, fn -> {key, slug, Changes.drawn(module, theme)} end)
    else
      assign(socket, theme_drawn: {key, slug, Changes.drawn(module, theme)})
    end
  end

  @doc "The page with a `:theme_drawn` async's result: kept when it is still the page's pick."
  @spec measured(Phoenix.LiveView.Socket.t(), {:ok, tuple()} | {:exit, term()}) ::
          Phoenix.LiveView.Socket.t()
  def measured(%{assigns: %{slug: slug, theme: key}} = socket, {:ok, {key, slug, _} = drawn}),
    do: assign(socket, theme_drawn: drawn)

  def measured(socket, _stale), do: socket

  attr(:current, :string, required: true, doc: "the picked theme's key")

  @doc "The picker: a button per listed theme, the picked one marked."
  def picker(assigns) do
    assigns = assign(assigns, :themes, Themes.list())

    ~H"""
    <div class="theme-picker" role="group" aria-label="Theme">
      <span class="theme-picker-label">Theme:</span>
      <div class="theme-picker-buttons">
        <button
          :for={theme <- @themes}
          type="button"
          phx-click="theme"
          phx-value-theme={theme.key}
          data-theme={theme.key}
          aria-pressed={to_string(theme.key == @current)}
          class={"theme-btn" <> if(theme.key == @current, do: " active", else: "")}
          title={theme.description}
        >
          <span class="theme-preview">
            <span
              :for={color <- Enum.take(theme.theme.series, 5)}
              class="color-dot"
              style={"background-color: #{color}"}
            ></span>
          </span>
          <span class="theme-name">{theme.name}</span>
        </button>
      </div>
      <style>
        .theme-picker { display: flex; align-items: center; flex-wrap: wrap; gap: 0.5rem; }
        .theme-picker-label { font-weight: 600; color: #444; margin-right: 0.5rem; }
        .theme-picker-buttons { display: flex; flex-wrap: wrap; gap: 0.5rem; }
        .theme-btn { display: flex; flex-direction: column; align-items: center; padding: 0.5rem 0.75rem; border: 2px solid #ddd; border-radius: 8px; background: white; cursor: pointer; transition: all 0.2s ease; }
        .theme-btn:hover { border-color: #999; transform: translateY(-2px); box-shadow: 0 4px 8px rgba(0,0,0,0.1); }
        .theme-btn.active { border-color: #4e79a7; background: #f0f7ff; box-shadow: 0 0 0 2px rgba(78, 121, 167, 0.2); }
        .theme-preview { display: flex; gap: 2px; margin-bottom: 4px; }
        .theme-picker .color-dot { width: 12px; height: 12px; border-radius: 2px; border: 1px solid rgba(0,0,0,0.1); }
        .theme-name { font-size: 11px; color: #666; font-weight: 500; }
        .theme-btn.active .theme-name { color: #4e79a7; font-weight: 600; }
      </style>
    </div>
    """
  end

  @aspect_names [
    page: "Page",
    series: "Series",
    colors: "Color table",
    ramps: "Ramps",
    styles: "Palette styles",
    type: "Type"
  ]

  @doc """
  What `theme` changes, worded: `{aspect, name, detail}` per aspect of
  `Examples.Themes.Changes.of/1`.

      iex> ExamplesWeb.ThemePicker.worded(Examples.Themes.theme("color_safe"))
      [{:ramps, "Ramps", ":status (the roles :good, :warning and :bad follow it)"}]
  """
  @spec worded(Visualize.Theme.t()) :: [{Changes.aspect(), String.t(), String.t()}]
  def worded(theme) do
    for {aspect, changed} <- Changes.of(theme),
        do: {aspect, Keyword.fetch!(@aspect_names, aspect), detail(aspect, changed, theme)}
  end

  defp detail(:page, slots, _theme), do: Enum.map_join(slots, ", ", &Atom.to_string/1)
  defp detail(:series, n, _theme), do: "its own #{n} colors"
  defp detail(:type, fields, _theme), do: Enum.map_join(fields, ", ", &Atom.to_string/1)

  defp detail(:ramps, names, _theme) do
    if :status in names,
      do: names(names) <> " (the roles :good, :warning and :bad follow it)",
      else: names(names)
  end

  defp detail(:styles, names, theme) do
    case Changes.hatched(theme, names) do
      [] -> names(names)
      hatched -> names(names) <> " (#{names(hatched)} hatched)"
    end
  end

  defp detail(:colors, names, _theme), do: names(names)

  defp names(names), do: Enum.map_join(names, ", ", &inspect/1)

  attr(:current, :string, required: true, doc: "the picked theme's key")

  attr(:slug, :string,
    required: true,
    doc: "the chart's slug, which the explain panel's id carries"
  )

  attr(:drawn, :any,
    required: true,
    doc: "`{key, slug, aspects}` as `measure/1` leaves it, or `nil` while measuring"
  )

  @doc """
  **What this theme changes**: the picked theme's changes from Default, each marked as
  drawn by the chart in view or not, a summary, and the links to the chart's explain panel
  and to the Theme lab with the theme loaded.
  """
  def changes(assigns) do
    entry = Themes.entry(assigns.current)

    drawn =
      case assigns.drawn do
        {key, slug, aspects} when key == assigns.current and slug == assigns.slug -> aspects
        _measuring -> nil
      end

    assigns = assign(assigns, entry: entry, changes: worded(entry.theme), aspects: drawn)

    ~H"""
    <section id="theme-changes" class="theme-changes" aria-live="polite">
      <h3 class="theme-changes-title">What this theme changes</h3>
      <p :if={@changes == []} class="theme-changes-note">
        Default is the baseline: every other theme is listed by what it changes from it.
      </p>
      <%= if @changes != [] do %>
        <p class="theme-changes-note">{@entry.name} changes, from Default:</p>
        <ul class="theme-changes-list">
          <li :for={{aspect, name, detail} <- @changes} data-aspect={aspect}>
            <strong>{name}</strong>: {detail}
            <span :if={@aspects && aspect in @aspects} class="theme-drawn">drawn here</span>
            <span :if={@aspects && aspect not in @aspects} class="theme-undrawn">
              not drawn by this chart
            </span>
          </li>
        </ul>
        <p :if={@aspects == nil} class="theme-changes-note">
          Measuring which of these this chart draws…
        </p>
        <p :if={@aspects == []} class="theme-changes-none">
          This chart draws none of them, so it looks as it does under Default.
        </p>
        <p :if={@aspects not in [nil, []]} class="theme-changes-note">
          This chart draws {length(@aspects)} of the {length(@changes)}.
        </p>
      <% end %>
      <p class="theme-changes-links">
        <a href={"#chart-panel-explain-#{@slug}"}>Why it looks as it does</a>
        shows one element's style stack under this theme, layer by layer ·
        <a id="open-in-theme-lab" href={"/theme-lab?theme=#{@current}"}>Open in Theme lab</a>
      </p>
      <style>
        .theme-changes { margin: 0 0 1rem; padding: 0.6rem 0.9rem; border: 1px solid #e5e7eb; border-radius: 8px; background: #fafafa; font-size: 0.85rem; }
        .theme-changes-title { margin: 0 0 0.3rem; font-size: 0.95rem; }
        .theme-changes-note, .theme-changes-none, .theme-changes-links { margin: 0.3rem 0; color: #555; }
        .theme-changes-none { font-weight: 600; color: #444; }
        .theme-changes-list { margin: 0.2rem 0; padding-left: 1.2rem; }
        .theme-drawn, .theme-undrawn { margin-left: 0.4rem; font-size: 0.75rem; padding: 0 0.35rem; border-radius: 4px; }
        .theme-drawn { background: #e0f0e3; color: #1d5b2b; }
        .theme-undrawn { background: #eee; color: #666; }
      </style>
    </section>
    """
  end
end
