defmodule Visualize.Chart.Text do
  @moduledoc ~S"""
  A text as one string with interpolation (spec/14 §7.1): `"Uptime for #{var(:host)}"`.

  A `:text` — a label's `text`, a legend's `title`, `meta.name`, `meta.description` — is
  a string in which `#{var(:name)}` stands for a variable and `#{field(:name)}` for a
  datum's field (a mark's label reads one per element, §5.5). A literal `#{` is written
  `\#{`. `parse/1` reads the string into its parts and `unparse/1` writes parts back;
  the two are inverse, and a list of parts — the form an earlier version wrote — is
  what `unparse/1` takes, which is the migration (§9).

      iex> Visualize.Chart.Text.parse("Uptime for \#{var(:host)} over 24h")
      {:ok, ["Uptime for ", %Visualize.Chart.Var{name: :host}, " over 24h"]}

      iex> Visualize.Chart.Text.parse("cost \\\#{literal}")
      {:ok, ["cost \#{literal}"]}

      iex> Visualize.Chart.Text.unparse(["u: ", %Visualize.Chart.Var{name: :unit}])
      "u: \#{var(:unit)}"

      iex> Visualize.Chart.Text.parse("open \#{var(:x")
      {:error, :unterminated}
  """

  alias Visualize.Chart.Var

  @typedoc "One part of a text: a string, a variable, or a datum's field."
  @type part :: String.t() | Var.t() | {:field, atom()}

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
      string when is_binary(string) -> String.replace(string, "\#{", "\\\#{")
      other -> to_string(other)
    end)
  end

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
  defp hole(_other), do: :error

  defp named(name, wrap) do
    case String.trim_trailing(name, ")") do
      "" ->
        :error

      word ->
        if word =~ ~r/^[a-zA-Z_][a-zA-Z0-9_?!]*$/,
          do: {:ok, wrap.(String.to_atom(word))},
          else: :error
    end
  end
end
