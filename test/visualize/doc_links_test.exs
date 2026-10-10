defmodule Visualize.DocLinksTest do
  @moduledoc """
  A shipped document links only to what the docs carry (spec/12 §6, #529, D-133).

  ExDoc turns a relative link to an extra's file into that extra's page; a relative link to
  any other file — a specification document, `API_SURFACE.md`, `usage-rules.md` — is a dead
  link on hexdocs, although it works on GitHub and in the repository. The specification, the
  conformance record and the usage rules ship in the package but are not extras, so a
  shipped document links them by absolute URL.

  The extras are read from `mix.exs` itself, so the list checked is the list the docs are
  built from. Every extra and the `@moduledoc` of every module of the application is
  scanned for inline links (`[text](target)`) and reference definitions (`[label]: target`)
  outside code; a target that is relative — no scheme, not a bare `#anchor` — must resolve
  to an extra, against the linking file's directory, or the project root for a moduledoc.
  """
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  defp extras do
    Enum.map(Mix.Project.config()[:docs][:extras], fn
      {path, _options} -> to_string(path)
      path -> to_string(path)
    end)
  end

  @doc false
  # The link targets of a Markdown text, outside fenced code and inline code spans.
  def targets(text) do
    prose =
      text
      |> String.replace(~r/^\s*```.*?^\s*```[^\n]*$/ms, "")
      |> String.replace(~r/`[^`\n]*`/, "")

    inline = for [_, t] <- Regex.scan(~r/\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/, prose), do: t
    refs = for [_, t] <- Regex.scan(~r/^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s|$)/m, prose), do: t
    inline ++ refs
  end

  @doc false
  # The targets of `text`, linked from a file in `dir` (relative to the root), that are
  # relative and resolve to no extra.
  def dead_targets(text, dir, extras) do
    for target <- targets(text), relative?(target), resolve(target, dir) not in extras do
      target
    end
  end

  defp relative?(target),
    do: not (target =~ ~r/^[a-zA-Z][a-zA-Z0-9+.-]*:/ or String.starts_with?(target, "#"))

  defp resolve(target, dir) do
    [path | _anchor] = String.split(target, "#", parts: 2)

    dir
    |> Path.join(path)
    |> Path.expand(@root)
    |> Path.relative_to(@root)
  end

  defp failure(where, dead) do
    "#{where} links #{Enum.map_join(dead, ", ", &"(#{&1})")}: not a docs extra. " <>
      "A shipped document links the specification, API_SURFACE.md or usage-rules.md by " <>
      "absolute URL, https://github.com/dcoai/Visualize/blob/main/<path>, with GitHub's " <>
      "heading slug for an anchor (D-133)."
  end

  test "the extras are the README, the guides and the changelog" do
    assert "README.md" in extras()
    assert "CHANGELOG.md" in extras()
    assert Enum.any?(extras(), &String.starts_with?(&1, "guides/"))
    refute Enum.any?(extras(), &String.starts_with?(&1, "spec/"))
    refute "API_SURFACE.md" in extras()
    refute "usage-rules.md" in extras()
  end

  test "the checker finds a relative link to a file that is not an extra" do
    text = """
    See [the spec](../spec/14-declarative-chart.md#7-3-application), the
    [surface](../API_SURFACE.md), [liveview](liveview.md#hooks), [up](#top),
    [GitHub](https://github.com/dcoai/Visualize/blob/main/spec/README.md) and `[x](y.md)`.

    [ref]: ../usage-rules.md

    ```elixir
    [a](b.md)
    ```
    """

    assert dead_targets(text, "guides", ["guides/liveview.md"]) ==
             [
               "../spec/14-declarative-chart.md#7-3-application",
               "../API_SURFACE.md",
               "../usage-rules.md"
             ]
  end

  test "every relative link in an extra resolves to an extra" do
    extras = extras()

    for extra <- extras do
      dead =
        @root |> Path.join(extra) |> File.read!() |> dead_targets(Path.dirname(extra), extras)

      assert dead == [], failure(extra, dead)
    end
  end

  test "every relative link in a moduledoc resolves to an extra" do
    extras = extras()
    {:ok, modules} = :application.get_key(:visualize, :modules)
    assert length(modules) > 100

    for module <- modules,
        {:docs_v1, _, _, _, %{"en" => doc}, _, _} <- [Code.fetch_docs(module)] do
      dead = dead_targets(doc, ".", extras)
      assert dead == [], failure("The @moduledoc of #{inspect(module)}", dead)
    end
  end
end
