defmodule Visualize.Chart.Text do
  @moduledoc ~S"""
  A text as one string with interpolation (spec/14 §7.1): `"Uptime for #{var(:host)}"`.

  A `:text` — a label's `text`, a legend's `title`, `meta.name`, `meta.description` — is
  a string in which `#{var(:name)}` stands for a variable and `#{field(:name)}` for a
  datum's field (a mark's label reads one per element, §5.5), and
  `#{fact(:source, :field, :key)}` for a fact of a feed's schema (§7.4). A literal `#{` is written
  `\#{`. `parse/1` reads the string into its parts and `unparse/1` writes parts back;
  the two are inverse, and a list of parts — the form an earlier version wrote — is
  what `unparse/1` takes, which is the migration (§9).

      iex> Visualize.Chart.Text.parse("Uptime for \#{var(:host)} over 24h")
      {:ok, ["Uptime for ", %Visualize.Chart.Var{name: "host"}, " over 24h"]}

      iex> Visualize.Chart.Text.parse("cost \\\#{literal}")
      {:ok, ["cost \#{literal}"]}

      iex> Visualize.Chart.Text.unparse(["u: ", %Visualize.Chart.Var{name: :unit}])
      "u: \#{var(:unit)}"

      iex> Visualize.Chart.Text.parse("open \#{var(:x")
      {:error, :unterminated}
  """

  alias Visualize.Chart.{Fact, Var}

  @attributes Visualize.Vocabulary.table(Fact.keys())

  @typedoc "One part of a text: a string, a variable, a datum's field, or a schema's fact."
  @type part :: String.t() | Var.t() | {:field, String.t()} | Fact.t()

  @doc ~S"""
  The parts of a text. A list is already parts and is returned as it is; a string is
  read, and an unterminated `#{` or a hole that names neither a variable nor a field is
  an error.
  """
  @spec parse(String.t() | [part()]) ::
          {:ok, [part()]} | {:error, :unterminated | {:hole, String.t()}}
  def parse(parts) when is_list(parts), do: {:ok, parts}

  def parse(string) when is_binary(string) do
    case read(string, "", []) do
      {:ok, parts} -> {:ok, parts |> Enum.reject(&(&1 == "")) |> Enum.reverse()}
      {:error, _} = error -> error
    end
  end

  @doc "The parts of a text, raising on one that does not read — for a text already validated."
  @spec parse!(String.t() | [part()]) :: [part()]
  def parse!(text) do
    case parse(text) do
      {:ok, parts} ->
        parts

      {:error, reason} ->
        raise ArgumentError, "a text that does not read (#{inspect(reason)}): #{inspect(text)}"
    end
  end

  @doc ~S"""
  The string form of parts: a variable as `#{var(:name)}`, a field as `#{field(:name)}`,
  a literal `#{` escaped. A string is returned as it is.
  """
  @spec unparse(String.t() | [part()]) :: String.t()
  def unparse(string) when is_binary(string), do: string

  def unparse(parts) when is_list(parts) do
    Enum.map_join(parts, "", fn
      %Var{name: name} -> "\#{var(:#{name})}"
      {:field, name} -> "\#{field(:#{name})}"
      %Fact{source: s, field: f, key: k} -> "\#{fact(:#{s}, :#{f}, :#{k})}"
      string when is_binary(string) -> String.replace(string, "\#{", "\\\#{")
      other -> to_string(other)
    end)
  end

  @doc ~S"""
  Parts as lines: the parts split at every newline in a string part; `[[]]` for an empty
  text (spec/14 §7.1).

      iex> Visualize.Chart.Text.lines(["Uptime\n24 h ", %Visualize.Chart.Var{name: :unit}])
      [["Uptime"], ["24 h ", %Visualize.Chart.Var{name: :unit}]]

      iex> Visualize.Chart.Text.lines(["one line"])
      [["one line"]]

      iex> Visualize.Chart.Text.lines([])
      [[]]
  """
  @spec lines([part()]) :: [[part()]]
  def lines(parts) when is_list(parts) do
    parts
    |> Enum.reduce([[]], fn
      string, [line | done] when is_binary(string) ->
        # The first piece continues the open line; every further piece opens one.
        [first | rest] = String.split(string, "\n")
        Enum.reduce(rest, [[first | line] | done], fn piece, acc -> [[piece] | acc] end)

      part, [line | done] ->
        [[part | line] | done]
    end)
    |> Enum.map(fn line -> line |> Enum.reverse() |> Enum.reject(&(&1 == "")) end)
    |> Enum.reverse()
  end

  # The estimate's advance per character, in ems (spec/14 §4.5, §5.5).
  @per_char 0.6

  @doc """
  The estimated width of a text at a font size: 0.6 × the font size per character
  (spec/14 §5.5). It is the one estimate the library makes of a text's width — the
  legend's layout and a mark label's `fit` read it — and it is public so a design can
  size itself by it, as a ring leaves room for the labels outside it (#489). A design
  cannot measure a glyph, so it is an estimate: a wide glyph runs over it.

      iex> Visualize.Chart.Text.width("Wednesday", 11)
      59.4

      iex> Visualize.Chart.Text.width("", 11)
      0.0
  """
  @spec width(String.t(), number()) :: float()
  def width(text, font_size) when is_binary(text) and is_number(font_size),
    do: @per_char * font_size * String.length(text)

  @doc "Whether a string carries a hole, so a plain string can be told from a template at a glance."
  @spec template?(term()) :: boolean()
  def template?(string) when is_binary(string), do: String.contains?(string, "\#{")
  def template?(_other), do: false

  # -- reading --------------------------------------------------------------------------

  defp read("", acc, parts), do: {:ok, [acc | parts]}
  defp read("\\\#{" <> rest, acc, parts), do: read(rest, acc <> "\#{", parts)

  defp read("\#{" <> rest, acc, parts) do
    case String.split(rest, "}", parts: 2) do
      [hole, rest] ->
        case hole(String.trim(hole)) do
          {:ok, part} -> read(rest, "", [part, acc | parts])
          :error -> {:error, {:hole, hole}}
        end

      [_unterminated] ->
        {:error, :unterminated}
    end
  end

  defp read(<<c::utf8, rest::binary>>, acc, parts), do: read(rest, acc <> <<c::utf8>>, parts)

  defp hole("var(:" <> name), do: named(name, &%Var{name: &1})
  defp hole("field(:" <> name), do: named(name, &{:field, &1})
  defp hole("fact(" <> args), do: fact(args)
  defp hole(_other), do: :error

  # `fact(:source, :field, :key)` (spec/14 §7.4): three names, each written as an atom.
  defp fact(args) do
    names = args |> String.trim_trailing(")") |> String.split(",") |> Enum.map(&String.trim/1)

    with [_, _, _] <- names,
         {:ok, [s, f, k]} <- atoms(names) do
      # The attribute is one of the feed schema's, its atom; any other is left as the string,
      # for the validator to refuse (spec/14 §9.4).
      {:ok, %Fact{source: s, field: f, key: Visualize.Vocabulary.read(@attributes, k)}}
    else
      _other -> :error
    end
  end

  defp atoms(names) do
    Enum.reduce_while(names, {:ok, []}, fn
      ":" <> name, {:ok, acc} ->
        case named(name, & &1) do
          {:ok, atom} -> {:cont, {:ok, acc ++ [atom]}}
          :error -> {:halt, :error}
        end

      _bare, _acc ->
        {:halt, :error}
    end)
  end

  defp named(name, wrap) do
    case String.trim_trailing(name, ")") do
      "" ->
        :error

      word ->
        if word =~ ~r/^[a-zA-Z_][a-zA-Z0-9_?!]*$/,
          do: {:ok, wrap.(word)},
          else: :error
    end
  end
end
