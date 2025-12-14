defmodule Visualize.Format do
  @moduledoc """
  Number and time formatting utilities for chart labels.

  ## Examples

      Visualize.Format.number(1234567)
      # => "1,234,567"

      Visualize.Format.si(1234567)
      # => "1.23M"

      Visualize.Format.percent(0.1234)
      # => "12.3%"

  """

  @si_prefixes [
    {1.0e24, "Y"},
    {1.0e21, "Z"},
    {1.0e18, "E"},
    {1.0e15, "P"},
    {1.0e12, "T"},
    {1.0e9, "G"},
    {1.0e6, "M"},
    {1.0e3, "k"},
    {1.0e0, ""},
    {1.0e-3, "m"},
    {1.0e-6, "µ"},
    {1.0e-9, "n"},
    {1.0e-12, "p"},
    {1.0e-15, "f"},
    {1.0e-18, "a"},
    {1.0e-21, "z"},
    {1.0e-24, "y"}
  ]

  @doc """
  Formats a number with thousands separators.

  ## Options

  - `:precision` - decimal places (default: auto)
  - `:separator` - thousands separator (default: ",")
  - `:decimal` - decimal separator (default: ".")

  """
  @spec number(number(), keyword()) :: String.t()
  def number(value, opts \\ []) do
    precision = Keyword.get(opts, :precision)
    separator = Keyword.get(opts, :separator, ",")
    decimal_sep = Keyword.get(opts, :decimal, ".")

    {int_part, dec_part} = split_number(value, precision)

    formatted_int =
      int_part
      |> Integer.to_string()
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.reverse/1)
      |> Enum.reverse()
      |> Enum.join(separator)

    if dec_part && dec_part != "" do
      formatted_int <> decimal_sep <> dec_part
    else
      formatted_int
    end
  end

  @doc """
  Formats a number with SI prefix (k, M, G, etc.).

  ## Options

  - `:precision` - significant digits (default: 3)

  """
  @spec si(number(), keyword()) :: String.t()
  def si(value, opts \\ []) when is_number(value) do
    precision = Keyword.get(opts, :precision, 3)

    if value == 0 do
      "0"
    else
      abs_value = abs(value)
      sign = if value < 0, do: "-", else: ""

      {divisor, prefix} =
        Enum.find(@si_prefixes, {1.0, ""}, fn {d, _} -> abs_value >= d end)

      scaled = abs_value / divisor

      # Format with precision
      formatted = format_significant(scaled, precision)

      sign <> formatted <> prefix
    end
  end

  @doc """
  Formats a number as a percentage.

  ## Options

  - `:precision` - decimal places (default: 1)
  - `:multiply` - multiply by 100 (default: true)

  """
  @spec percent(number(), keyword()) :: String.t()
  def percent(value, opts \\ []) do
    precision = Keyword.get(opts, :precision, 1)
    multiply = Keyword.get(opts, :multiply, true)

    value = if multiply, do: value * 100, else: value

    :erlang.float_to_binary(value * 1.0, decimals: precision) <> "%"
  end

  @doc """
  Formats a number in exponential notation.
  """
  @spec exponential(number(), keyword()) :: String.t()
  def exponential(value, opts \\ []) do
    precision = Keyword.get(opts, :precision, 2)
    :erlang.float_to_binary(value * 1.0, [{:scientific, precision}])
  end

  @doc """
  Formats a number with fixed decimal places.
  """
  @spec fixed(number(), integer()) :: String.t()
  def fixed(value, precision) do
    :erlang.float_to_binary(value * 1.0, decimals: precision)
  end

  @doc """
  Formats currency.

  ## Options

  - `:symbol` - currency symbol (default: "$")
  - `:precision` - decimal places (default: 2)

  """
  @spec currency(number(), keyword()) :: String.t()
  def currency(value, opts \\ []) do
    symbol = Keyword.get(opts, :symbol, "$")
    precision = Keyword.get(opts, :precision, 2)

    abs_value = abs(value)
    sign = if value < 0, do: "-", else: ""

    formatted = number(Float.round(abs_value, precision), precision: precision)

    sign <> symbol <> formatted
  end

  @doc """
  Creates a number formatter function with preset options.

  ## Examples

      formatter = Visualize.Format.formatter(".2s")
      formatter.(1234567)  # => "1.2M"

      formatter = Visualize.Format.formatter(",.0f")
      formatter.(1234567)  # => "1,234,567"

  ## Format specifiers

  - `s` - SI prefix
  - `%` - percentage
  - `f` - fixed point
  - `e` - exponential
  - `d` - integer
  - `,` - use thousands separator

  """
  @spec formatter(String.t()) :: (number() -> String.t())
  def formatter(specifier) do
    # Parse simple format specifiers
    cond do
      String.contains?(specifier, "s") ->
        precision = parse_precision(specifier) || 3
        fn v -> si(v, precision: precision) end

      String.contains?(specifier, "%") ->
        precision = parse_precision(specifier) || 1
        fn v -> percent(v, precision: precision) end

      String.contains?(specifier, "e") ->
        precision = parse_precision(specifier) || 2
        fn v -> exponential(v, precision: precision) end

      String.contains?(specifier, "f") ->
        precision = parse_precision(specifier) || 2
        use_comma = String.contains?(specifier, ",")

        if use_comma do
          fn v -> number(v, precision: precision) end
        else
          fn v -> fixed(v, precision) end
        end

      String.contains?(specifier, "d") ->
        use_comma = String.contains?(specifier, ",")

        if use_comma do
          fn v -> number(round(v)) end
        else
          fn v -> Integer.to_string(round(v)) end
        end

      true ->
        fn v -> to_string(v) end
    end
  end

  @doc """
  Formats a date/time value.

  ## Format directives

  - `%Y` - 4-digit year
  - `%m` - 2-digit month
  - `%d` - 2-digit day
  - `%H` - 2-digit hour (24h)
  - `%M` - 2-digit minute
  - `%S` - 2-digit second
  - `%b` - abbreviated month name
  - `%B` - full month name

  """
  @spec time(DateTime.t() | Date.t() | NaiveDateTime.t(), String.t()) :: String.t()
  def time(datetime, format \\ "%Y-%m-%d") do
    format
    |> String.replace("%Y", pad_int(year(datetime), 4))
    |> String.replace("%m", pad_int(month(datetime), 2))
    |> String.replace("%d", pad_int(day(datetime), 2))
    |> String.replace("%H", pad_int(hour(datetime), 2))
    |> String.replace("%M", pad_int(minute(datetime), 2))
    |> String.replace("%S", pad_int(second(datetime), 2))
    |> String.replace("%b", month_abbr(month(datetime)))
    |> String.replace("%B", month_name(month(datetime)))
  end

  # Private helpers

  defp split_number(value, precision) when is_integer(value) do
    if precision do
      {value, String.duplicate("0", precision)}
    else
      {value, nil}
    end
  end

  defp split_number(value, precision) when is_float(value) do
    precision = precision || auto_precision(value)
    rounded = Float.round(value, precision)
    int_part = trunc(rounded)
    dec_part = abs(rounded - int_part)

    dec_str =
      if precision > 0 do
        dec_part
        |> Float.round(precision)
        |> Float.to_string()
        |> String.split(".")
        |> List.last()
        |> String.pad_trailing(precision, "0")
        |> String.slice(0, precision)
      else
        nil
      end

    {int_part, dec_str}
  end

  defp auto_precision(value) when is_float(value) do
    abs_val = abs(value)

    cond do
      abs_val >= 100 -> 0
      abs_val >= 10 -> 1
      abs_val >= 1 -> 2
      true -> 3
    end
  end

  defp format_significant(value, precision) do
    if value >= 1 do
      # Count integer digits
      int_digits = trunc(:math.log10(value)) + 1
      decimals = max(0, precision - int_digits)
      :erlang.float_to_binary(value, decimals: decimals)
    else
      :erlang.float_to_binary(value, decimals: precision - 1)
    end
  end

  defp parse_precision(specifier) do
    case Regex.run(~r/\.(\d+)/, specifier) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  defp year(%DateTime{year: y}), do: y
  defp year(%Date{year: y}), do: y
  defp year(%NaiveDateTime{year: y}), do: y

  defp month(%DateTime{month: m}), do: m
  defp month(%Date{month: m}), do: m
  defp month(%NaiveDateTime{month: m}), do: m

  defp day(%DateTime{day: d}), do: d
  defp day(%Date{day: d}), do: d
  defp day(%NaiveDateTime{day: d}), do: d

  defp hour(%DateTime{hour: h}), do: h
  defp hour(%Date{}), do: 0
  defp hour(%NaiveDateTime{hour: h}), do: h

  defp minute(%DateTime{minute: m}), do: m
  defp minute(%Date{}), do: 0
  defp minute(%NaiveDateTime{minute: m}), do: m

  defp second(%DateTime{second: s}), do: s
  defp second(%Date{}), do: 0
  defp second(%NaiveDateTime{second: s}), do: s

  defp pad_int(n, width), do: n |> Integer.to_string() |> String.pad_leading(width, "0")

  @month_abbrs ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  @month_names ~w(January February March April May June July August September October November December)

  defp month_abbr(m), do: Enum.at(@month_abbrs, m - 1)
  defp month_name(m), do: Enum.at(@month_names, m - 1)
end
