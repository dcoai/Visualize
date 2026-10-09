defmodule ExamplesWeb.Highlight do
  @moduledoc """
  The one way a page of the examples shows code (#506, spec/14 §12.6): highlighted
  server-side by Makeup, inside `<pre><code class="highlight lang-…">`.

  `lang` is a Makeup language name — `"elixir"`, `"heex"`, … whatever lexer is
  registered. Elixir samples that show a template carry it in a `~H` sigil, which
  `makeup_eex` highlights as HEEx. A language with no registered lexer renders the
  source as escaped plain text under `class="plain"`, which the guard test refuses on
  any page, so the fallback is for robustness and never what a page ships.

  The spans add no text, so the text a reader copies is the source.
  """
  use Phoenix.Component

  alias Makeup.Formatters.HTML.HTMLFormatter

  # Readable on the dark `pre` of the root layout; `pre` keeps its own background.
  @stylesheet Makeup.stylesheet(Makeup.Styles.HTML.StyleMap.one_dark_style(), "highlight")

  @doc "The highlighter's stylesheet, for the root layout."
  def css, do: @stylesheet <> "\npre code.highlight { background: none; }\n"

  attr :code, :string, required: true
  attr :lang, :string, default: "elixir"

  def code(assigns) do
    case Makeup.Registry.fetch_lexer_by_name(assigns.lang) do
      {:ok, {lexer, options}} ->
        assigns = assign(assigns, :html, highlight(assigns.code, lexer, options))

        ~H"""
        <pre><code class={"highlight lang-#{@lang}"}>{Phoenix.HTML.raw(@html)}</code></pre>
        """

      :error ->
        ~H"""
        <pre><code class="plain">{@code}</code></pre>
        """
    end
  end

  @doc """
  The source as the highlighter's inner HTML: the lexer's tokens, formatted without
  the group ids a lexer stamps for bracket matching — random per call (a `~H`
  sigil's inner lexer draws its own), so leaving them would make every render of the
  same source different bytes, and they serve a script the examples do not ship.
  """
  def highlight(source, lexer, options \\ []) do
    source
    |> lexer.lex(options)
    |> Enum.map(fn {type, meta, value} -> {type, Map.delete(meta, :group_id), value} end)
    |> HTMLFormatter.format_inner_as_binary([])
  end
end
