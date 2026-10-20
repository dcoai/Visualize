defmodule ExamplesWeb.SiteHeader do
  @moduledoc """
  The one header of the examples (#329): the title, the subtitle *Liveview data
  visualizations*, and the tab bar — Charts, Performance Test, Client-side Interactions,
  Theme lab (#792), Chart Builder — the current one marked. Every page renders it; none
  draws its own.
  """

  use Phoenix.Component

  attr(:tab, :atom,
    required: true,
    doc: "the current tab: :charts, :performance, :interaction, :theme_lab or :builder"
  )

  def header(assigns) do
    ~H"""
    <header class="site-header">
      <h1>Visualize Examples</h1>
      <p>Liveview data visualizations</p>
      <nav class="site-tabs" aria-label="sections">
        <a
          :for={{tab, href, name, icon} <- tabs()}
          href={href}
          class="site-tab"
          aria-current={if(tab == @tab, do: "page", else: false)}
        >
          <span class="site-tab-icon">{Phoenix.HTML.raw(icon)}</span><span class="site-tab-name">{name}</span>
        </a>
      </nav>
    </header>
    """
  end

  @doc "The tabs: `{tab, href, name, icon}`, the icon inline SVG in `currentColor`."
  def tabs do
    [
      {:charts, "/", "Charts",
       ~s|<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="4" y="12" width="4" height="8" fill="currentColor" stroke="none"/><rect x="10" y="7" width="4" height="13" fill="currentColor" stroke="none"/><rect x="16" y="3" width="4" height="17" fill="currentColor" stroke="none"/></svg>|},
      {:performance, "/performance", "Performance Test",
       ~s|<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 16 A8 8 0 0 1 20 16"/><path d="M12 16 L16 9"/><circle cx="12" cy="16" r="1.5" fill="currentColor" stroke="none"/></svg>|},
      {:interaction, "/interaction", "Client-side Interactions",
       ~s|<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 18 L9 12 L13 15 L20 6"/><path d="M14 13 L20 15 L17 17 L19 21 L17 22 L15 18 L13 20 Z" fill="currentColor" stroke="none"/></svg>|},
      {:theme_lab, "/theme-lab", "Theme lab",
       ~s|<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 A9 9 0 1 0 12 21 C13.5 21 14 20 14 19 C14 17.5 12.8 17 12.8 15.8 C12.8 14.8 13.6 14 14.6 14 L17 14 A4 4 0 0 0 21 10 C21 6 17 3 12 3 Z"/><circle cx="7.5" cy="11" r="1.5" fill="currentColor" stroke="none"/><circle cx="10.5" cy="7" r="1.5" fill="currentColor" stroke="none"/><circle cx="15.5" cy="7.5" r="1.5" fill="currentColor" stroke="none"/></svg>|},
      {:builder, "/builder", "Chart Builder",
       ~s|<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M8 16 L15 9 L17 11 L10 18 L7 18 Z" fill="currentColor" stroke="none"/></svg>|}
    ]
  end
end
