defmodule ExamplesWeb.ThemePicker do
  @moduledoc """
  The chart page's theme picker (spec/14 §12.6, #792, work item #794): a button per theme
  of `Examples.Themes.list/0` — the built-in themes and the host themes, each a real
  `Visualize.Theme` — showing its first five series colors and its name, the picked one
  marked. A press pushes `theme` with the theme's key, which `pick/2` looks up in the same
  list, so there is no list of names beside the themes' own and no atom made from a press.
  """

  use Phoenix.Component

  alias Examples.Themes

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
end
