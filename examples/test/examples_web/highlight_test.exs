defmodule ExamplesWeb.HighlightTest do
  @moduledoc """
  Every code block the examples show is highlighted (#506, spec/14 §12.6): the component
  highlights Elixir and the HEEx in its `~H` sigil, falls back to plain text for a
  language with no lexer, adds no text to the source — and no page renders a `<pre>`
  that is not the highlighter's.
  """
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest, only: [render_component: 2, rendered_to_string: 1]

  alias ExamplesWeb.{ChartLive, Highlight}

  @endpoint ExamplesWeb.Endpoint

  defp block(code, lang), do: render_component(&Highlight.code/1, code: code, lang: lang)

  # The text a reader copies out of a block: its markup gone, its entities read.
  defp text(html) do
    html
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
  end

  @sample ~S'''
  # A comment, then a design.
  design = Build.chart(width: 640) |> Build.mark(:line, x: :t, y: "value & more")

  ~H"""
  <div id="chart" phx-hook="Hook" data-x="<'&'>">{raw(@svg)}</div>
  """
  '''

  test "Elixir is highlighted, the HEEx in its ~H sigil as HEEx" do
    html = block(@sample, "elixir")

    assert html =~ ~s(<pre><code class="highlight lang-elixir">)
    assert html =~ ~s(<span class="c1"># A comment, then a design.</span>)
    assert html =~ ~s(<span class="ss">width:</span>) or html =~ ~s(<span class="ss">width</span>)
    assert html =~ ~s(<span class="s">&quot;value &amp; more&quot;</span>)
    # The template's tag and attribute are HEEx tokens, not Elixir operators.
    assert html =~ ~s(<span class="nt">div</span>)
    assert html =~ ~s(<span class="na">phx-hook</span>)
  end

  test "the highlighted text is the source, so copying gives the source" do
    [_, inner] = Regex.run(~r/<code[^>]*>(.*)<\/code>/s, block(@sample, "elixir"))
    assert text(inner) == @sample
  end

  test "a block renders the same bytes every time — no per-call group ids" do
    assert block(@sample, "elixir") == block(@sample, "elixir")
    refute block(@sample, "elixir") =~ "data-group-id"
  end

  test "a language with no lexer falls back to escaped plain text" do
    html = block("SELECT 1 < 2 & 'x'", "no-such-language")

    assert html =~ ~s(<pre><code class="plain">)
    refute html =~ "<span"
    assert html =~ "SELECT 1 &lt; 2 &amp; &#39;x&#39;"
  end

  test "the root layout carries the highlighter's stylesheet" do
    html = build_conn() |> get("/") |> html_response(200)
    assert html =~ ".highlight .c1 {"
  end

  # ── the guard ──────────────────────────────────────────────────────────────────────

  # Every `<pre>` of a page: its opening and what it holds. A block is the highlighter's
  # when its code is `highlight` and holds the lexer's spans.
  defp unhighlighted(html) do
    for [pre] <- Regex.scan(~r/<pre\b.*?<\/pre>/s, html),
        not (pre =~ ~r/\A<pre><code class="highlight lang-[\w.-]+">/ and pre =~ ~s(<span class=")),
        do: pre
  end

  defp assert_highlighted(where, html) do
    assert unhighlighted(html) == [],
           "#{where} shows code the highlighter did not:\n" <>
             Enum.join(unhighlighted(html), "\n---\n")
  end

  # The router's pages but the chart pages, which the tests below take one a chart.
  defp pages do
    Phoenix.Router.routes(ExamplesWeb.Router)
    |> Enum.filter(&(&1.verb == :get and not String.starts_with?(&1.path, "/hooks")))
    |> Enum.map(& &1.path)
    |> Enum.reject(&(&1 == "/chart/:chart"))
  end

  test "no page of the router renders a code block the highlighter did not" do
    assert "/" in pages()

    for path <- pages() do
      conn = build_conn() |> get(path)

      case conn.status do
        200 -> assert_highlighted(path, html_response(conn, 200))
        302 -> :redirect
      end
    end
  end

  # The code a chart page shows changes with its backend (the Canvas sample is the split,
  # the Incremental one the scroll): every backend of every chart, one test a chart (#735),
  # the page as the router serves it first.
  describe "every chart page shows highlighted code on every backend it offers" do
    for {slug, module} <- ChartLive.charts() do
      test slug, do: assert_chart_highlighted(unquote(slug), unquote(module))
    end
  end

  defp assert_chart_highlighted(slug, module) do
    assert_highlighted(
      "/chart/#{slug}",
      build_conn() |> get("/chart/#{slug}") |> html_response(200)
    )

    for backend <- Examples.Frames.backends(module) do
      {:ok, s} = ChartLive.mount(%{"chart" => slug}, %{}, %Phoenix.LiveView.Socket{})

      {:noreply, s} =
        ChartLive.handle_event("set_backend", %{"backend" => to_string(backend)}, s)

      html = rendered_to_string(ChartLive.render(Map.put(s.assigns, :__changed__, %{})))
      assert html =~ "<pre>", "/chart/#{slug} on #{backend} shows no code"
      assert_highlighted("/chart/#{slug} on #{backend}", html)
    end
  end
end
