defmodule Visualize.Render.Raster.Families do
  @moduledoc false
  # The font-family side of `Visualize.Render.Raster` (spec/09 §9.7), in plain Elixir: the
  # family lists an SVG names, how each splits into members, how a member resolves against
  # a font database's family set, and the family names `Resvg.list_fonts/1` describes.
  # resvg drops text in a family it lacks without a word, so these rules are resvg's own:
  # names and generic keywords match case-sensitively and nothing is substituted.

  @generics %{
    "serif" => :serif,
    "sans-serif" => :sans_serif,
    "monospace" => :monospace,
    "cursive" => :cursive,
    "fantasy" => :fantasy
  }

  @attribute ~r/\sfont-family\s*=\s*(?:"([^"]*)"|'([^']*)')/
  @property ~r/font-family\s*:\s*([^;"]+)/
  @root ~r/<svg\b[^>]*>/
  @tag ~r/<(\/?)([A-Za-z][^\s\/>]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>/

  @typedoc "A missing family list: as written, and the families its members asked for."
  @type warning :: {:missing_family, String.t(), [String.t()]}

  # Writes `family` as the root element's `font-family` when a text element has no family of
  # its own or from an ancestor, so every text's family is one the SVG names (spec/09 §9.7,
  # step 1).
  @doc false
  @spec with_default(String.t(), String.t()) :: String.t()
  def with_default(svg, family) do
    case Regex.run(@root, svg, return: :index) do
      [{at, len}] ->
        root = binary_part(svg, at, len)

        if orphan_text?(svg) and not Regex.match?(@attribute, root) do
          attr = ~s( font-family="#{escape(family)}")
          split = at + 4
          binary_part(svg, 0, split) <> attr <> binary_part(svg, split, byte_size(svg) - split)
        else
          svg
        end

      nil ->
        svg
    end
  end

  # Whether a `<text` element has no `font-family`, attribute or style, of its own or on an
  # ancestor: resvg would draw it in its own default family, not one the SVG names.
  @doc false
  @spec orphan_text?(String.t()) :: boolean()
  def orphan_text?(svg) do
    @tag
    |> Regex.scan(svg, capture: :all_but_first)
    |> Enum.reduce_while([false], fn
      ["/" | _], [_ | stack] ->
        {:cont, stack}

      [_, name, attrs, closing], [inherited | _] = stack ->
        named = inherited or Regex.match?(@attribute, attrs) or Regex.match?(@property, attrs)

        cond do
          name == "text" and not named -> {:halt, :orphan}
          closing == "/" -> {:cont, stack}
          true -> {:cont, [named | stack]}
        end
    end)
    |> Kernel.==(:orphan)
  end

  # Whether the document has a `<text` element: without one nothing can go missing.
  @doc false

  @spec text?(String.t()) :: boolean()
  def text?(svg), do: String.contains?(svg, "<text")

  # Every `font-family` list the SVG holds, attribute and style, in document order.
  @doc false
  @spec lists(String.t()) :: [String.t()]
  def lists(svg) do
    attributes =
      for [{at, _} | groups] <- Regex.scan(@attribute, svg, return: :index),
          {start, len} <- groups,
          start >= 0,
          do: {at, decode(binary_part(svg, start, len))}

    properties =
      for [{at, _}, {start, len}] <- Regex.scan(@property, svg, return: :index),
          do: {at, decode(binary_part(svg, start, len))}

    (attributes ++ properties)
    |> Enum.sort()
    |> Enum.map(fn {_at, list} -> String.trim(list) end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  # The members of a family list: `{:name, family}` or `{:generic, key}`. Quoted members are
  # names; an unquoted member is a generic keyword only when it is one exactly.
  @doc false
  @spec members(String.t()) :: [{:name, String.t()} | {:generic, atom()}]
  def members(list) do
    list
    |> split([], "", nil)
    |> Enum.map(&member/1)
    |> Enum.reject(&(&1 == {:name, ""}))
  end

  # The warnings of the SVG's lists against a family set and the generic mapping.
  @doc false
  @spec missing(String.t(), MapSet.t(String.t()), keyword(String.t())) :: [warning()]
  def missing(svg, families, generics) do
    if text?(svg) do
      for list <- lists(svg),
          tried = tried(list, generics),
          not Enum.any?(tried, &MapSet.member?(families, &1)),
          do: {:missing_family, list, tried}
    else
      []
    end
  end

  defp tried(list, generics) do
    Enum.map(members(list), fn
      {:name, name} -> name
      {:generic, key} -> Keyword.fetch!(generics, key)
    end)
  end

  # The family names of `Resvg.list_fonts/1`'s lines, each
  # `path: 'Family (Language, Region)', 'Family (…)', index, Style, weight, Stretch`.
  # A line of another form contributes nothing (spec/09 §9.7).
  @doc false
  @spec from_listing([String.t()]) :: MapSet.t(String.t())
  def from_listing(lines) do
    for line <- lines,
        [_, names] <- [Regex.run(~r/^.*?: '(.*)', \d+, \w+, \d+, \w+$/s, line)],
        [_, name] <- Regex.scan(~r/(.+?) \([^()]*\)(?:', '|$)/s, names),
        into: MapSet.new(),
        do: name
  end

  # A comma outside quotes ends a member; a quote opens and the same quote closes.
  defp split("", acc, current, _quote), do: Enum.reverse([current | acc])

  defp split(<<q, rest::binary>>, acc, current, nil) when q in [?", ?'],
    do: split(rest, acc, current <> <<q>>, q)

  defp split(<<q, rest::binary>>, acc, current, q), do: split(rest, acc, current <> <<q>>, nil)
  defp split(<<?,, rest::binary>>, acc, current, nil), do: split(rest, [current | acc], "", nil)

  defp split(<<c::utf8, rest::binary>>, acc, current, quote),
    do: split(rest, acc, current <> <<c::utf8>>, quote)

  defp member(raw) do
    trimmed = String.trim(raw)

    case Regex.run(~r/^(["'])(.*)\1$/s, trimmed) do
      [_, _, name] ->
        {:name, name}

      nil ->
        case Map.fetch(@generics, trimmed) do
          {:ok, key} -> {:generic, key}
          :error -> {:name, String.replace(trimmed, ~r/\s+/, " ")}
        end
    end
  end

  defp decode(value) do
    value
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&apos;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
  end

  defp escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
  end
end
