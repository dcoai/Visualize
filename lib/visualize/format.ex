defmodule Visualize.Format do
  @moduledoc """
  Number and time formatting utilities for chart labels.

  `formatter/1` is a d3-format specifier parser; `time/2` a strftime-style directive
  formatter. The simpler functions (`number/2`, `si/2`, `percent/2`, …) are presets with
  keyword options.

  ## Examples

      Visualize.Format.number(1234567)
      # => "1,234,567"

      Visualize.Format.si(1234567)
      # => "1.23M"

      Visualize.Format.percent(0.1234)
      # => "12.3%"

      Visualize.Format.formatter("($.2f").(-1234.5)
      # => "($1,234.50)"

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

    # The magnitude is grouped; the sign goes back on afterwards, unless the magnitude
    # rounded away to nothing.
    {int_part, dec_part} = split_number(abs(value), precision)

    formatted_int =
      int_part
      |> Integer.to_string()
      |> group(separator, :infinity)

    magnitude =
      if dec_part && dec_part != "" do
        formatted_int <> decimal_sep <> dec_part
      else
        formatted_int
      end

    if value < 0 and String.match?(magnitude, ~r/[1-9]/), do: "-" <> magnitude, else: magnitude
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

    formatted = number(Float.round(abs_value * 1.0, precision), precision: precision)

    sign <> symbol <> formatted
  end

  # --- formatter/1: d3-format ---------------------------------------------------------------

  @specifier ~r/^(?:(.)?([<>=^]))?([+\-( ])?([$#])?(0)?(\d+)?(,)?(\.\d+)?(~)?([a-z%])?$/i
  @prefixes ~w(y z a f p n µ m) ++ [""] ++ ~w(k M G T P E Z Y)
  @nan "NaN"

  @month_abbrs ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  @month_names ~w(January February March April May June July August September October November December)
  @weekday_abbrs ~w(Mon Tue Wed Thu Fri Sat Sun)
  @weekday_names ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  @doc """
  Creates a number formatter function from a d3-format specifier.

  The specifier grammar is d3-format's:

      [[fill]align][sign][symbol][0][width][,][.precision][~][type]

  - `fill` is any character, used with `align`: `>` right (default), `<` left, `^` centre,
    `=` after the sign and symbol.
  - `sign`: `-` (minus for negatives only, default), `+` (plus or minus), `(` (parentheses
    for negatives), space (space for positives).
  - `symbol`: `$` for a currency prefix, `#` for the `0b`/`0o`/`0x` prefix of the
    `b`/`o`/`x`/`X` types.
  - `0` pads with zeros after the sign and symbol; `width` is the minimum output width;
    `,` groups thousands; `.precision` is the number of digits after the point (`e`, `f`,
    `%`) or of significant digits (`g`, `r`, `s`, `p`); `~` trims insignificant trailing
    zeros.
  - `type`: `e` exponential, `f` fixed, `g` general (either, by magnitude), `r` rounded to
    significant digits, `s` SI prefix, `%` percentage fixed, `p` percentage rounded, `d`
    integer, `b`/`o`/`x`/`X` integer in base 2/8/16, `c` the value as a string, `n` for
    `,g`; no type is `~g` with a default precision of 12.

  ## Examples

      Visualize.Format.formatter(".2s").(1234567)     # => "1.2M"
      Visualize.Format.formatter(",.0f").(1234567)    # => "1,234,567"
      Visualize.Format.formatter("+.1%").(0.123)      # => "+12.3%"
      Visualize.Format.formatter("($.2f").(-12.5)     # => "($12.50)"
      Visualize.Format.formatter("08.2f").(3.14159)   # => "00003.14"
      Visualize.Format.formatter("#x").(255)          # => "0xff"

  An invalid specifier raises `ArgumentError`.
  """
  @spec formatter(String.t()) :: (number() -> String.t())
  def formatter(specifier) when is_binary(specifier) do
    spec = parse_specifier(specifier)
    fn value -> format(spec, value) end
  end

  defp parse_specifier(specifier) do
    case Regex.run(@specifier, specifier) do
      nil ->
        raise ArgumentError, "invalid format specifier: #{inspect(specifier)}"

      match ->
        [_, fill, align, sign, symbol, zero, width, comma, precision, trim, type] =
          Enum.map(0..10, &(Enum.at(match, &1) || ""))

        %{
          fill: if(fill == "", do: " ", else: fill),
          align: if(align == "", do: ">", else: align),
          sign: if(sign == "", do: "-", else: sign),
          symbol: symbol,
          zero: zero == "0",
          width: if(width == "", do: nil, else: String.to_integer(width)),
          comma: comma == ",",
          precision:
            if(precision == "",
              do: nil,
              else: String.to_integer(String.slice(precision, 1..-1//1))
            ),
          trim: trim == "~",
          type: type
        }
        |> normalise_specifier()
    end
  end

  @types ~w(e f g r s % p d b o x X c)

  defp normalise_specifier(spec) do
    spec =
      cond do
        # "n" is an alias for ",g".
        spec.type == "n" ->
          %{spec | comma: true, type: "g"}

        # No type (or an unknown one) is ".12~g".
        spec.type not in @types ->
          %{spec | precision: spec.precision || 12, trim: true, type: "g"}

        true ->
          spec
      end

    # Zero fill means padding after the sign and symbol, whichever way it was written.
    spec =
      if spec.zero or (spec.fill == "0" and spec.align == "="),
        do: %{spec | zero: true, fill: "0", align: "="},
        else: spec

    # Significant precision is in [1, 21]; fixed precision in [0, 20].
    precision =
      case {spec.precision, spec.type} do
        {nil, _} -> 6
        {p, t} when t in ~w(g p r s) -> p |> max(1) |> min(21)
        {p, _} -> p |> max(0) |> min(20)
      end

    %{spec | precision: precision}
  end

  defp format(%{type: "c"} = spec, value) do
    {prefix, suffix} = affixes(spec)
    assemble(spec, prefix, "", to_string(value) <> suffix)
  end

  defp format(spec, value) when is_number(value) do
    {prefix, suffix} = affixes(spec)
    negative? = value < 0
    {body, si_exponent} = format_type(spec.type, abs(value) * 1.0, spec.precision)
    body = if spec.trim, do: trim_zeros(body), else: body

    # A negative that rounds to zero shows no sign unless a plus sign was asked for.
    negative? = negative? and not (zero_string?(body, spec.type) and spec.sign != "+")

    value_prefix =
      cond do
        negative? and spec.sign == "(" -> "("
        negative? -> "-"
        spec.sign in ["-", "("] -> ""
        true -> spec.sign
      end <> prefix

    value_suffix =
      if(spec.type == "s", do: Enum.at(@prefixes, 8 + div(si_exponent, 3)), else: "") <>
        suffix <> if(negative? and spec.sign == "(", do: ")", else: "")

    # Split the digits that can be grouped from the fraction or exponent that cannot.
    {digits, value_suffix} =
      if spec.type in ~w(d e f g p r s %) do
        case Regex.run(~r/^(\d*)(.*)$/s, body) do
          [_, digits, ""] -> {digits, value_suffix}
          [_, digits, "." <> rest] -> {digits, "." <> rest <> value_suffix}
          [_, digits, rest] -> {digits, rest <> value_suffix}
        end
      else
        {body, value_suffix}
      end

    assemble(spec, value_prefix, digits, value_suffix)
  end

  defp format(spec, _value), do: assemble(spec, "", @nan, "")

  defp affixes(spec) do
    prefix =
      cond do
        spec.symbol == "$" -> "$"
        spec.symbol == "#" and spec.type in ~w(b o x X) -> "0" <> String.downcase(spec.type)
        true -> ""
      end

    suffix = if spec.type in ["%", "p"], do: "%", else: ""
    {prefix, suffix}
  end

  # Grouping, padding and alignment, as d3's `format` closure.
  defp assemble(spec, prefix, digits, suffix) do
    digits = if spec.comma and not spec.zero, do: group(digits, ",", :infinity), else: digits

    length = String.length(prefix) + String.length(digits) + String.length(suffix)

    padding =
      if spec.width && length < spec.width,
        do: String.duplicate(spec.fill, spec.width - length),
        else: ""

    # With zero fill the grouping is applied after padding, limited to the width.
    {digits, padding} =
      if spec.comma and spec.zero do
        limit = if padding == "", do: :infinity, else: spec.width - String.length(suffix)
        {group(padding <> digits, ",", limit), ""}
      else
        {digits, padding}
      end

    case spec.align do
      "<" ->
        prefix <> digits <> suffix <> padding

      "=" ->
        prefix <> padding <> digits <> suffix

      "^" ->
        half = div(String.length(padding), 2)

        String.slice(padding, 0, half) <>
          prefix <> digits <> suffix <> String.slice(padding, half..-1//1)

      _ ->
        padding <> prefix <> digits <> suffix
    end
  end

  # d3's `formatGroup` for grouping `[3]`: thousands from the right, and with a finite
  # width the groups shrink so that the grouped string does not exceed it.
  defp group(digits, separator, width) do
    do_group(digits, String.length(digits), 3, 0, width, [])
    |> Enum.join(separator)
  end

  defp do_group(_digits, i, _g, _length, _width, acc) when i <= 0, do: acc

  defp do_group(digits, i, g, length, width, acc) do
    g = if width != :infinity and length + g + 1 > width, do: max(1, width - length), else: g
    i = i - g
    acc = [String.slice(digits, max(i, 0), g + min(i, 0)) | acc]
    length = length + g + 1

    if width != :infinity and length > width,
      do: acc,
      else: do_group(digits, i, 3, length, width, acc)
  end

  # --- Type formatters, over the magnitude ------------------------------------------------

  defp format_type("%", x, p), do: {to_fixed(x * 100, p), 0}
  defp format_type("f", x, p), do: {to_fixed(x, p), 0}
  defp format_type("e", x, p), do: {to_exponential(x, p), 0}
  defp format_type("g", x, p), do: {to_precision(x, p), 0}
  defp format_type("r", x, p), do: {rounded(x, p), 0}
  defp format_type("p", x, p), do: {rounded(x * 100, p), 0}
  defp format_type("s", x, p), do: prefix_auto(x, p)
  defp format_type("d", x, _p), do: {Integer.to_string(round(x)), 0}
  defp format_type("b", x, _p), do: {Integer.to_string(round(x), 2), 0}
  defp format_type("o", x, _p), do: {Integer.to_string(round(x), 8), 0}
  defp format_type("x", x, _p), do: {Integer.to_string(round(x), 16) |> String.downcase(), 0}
  defp format_type("X", x, _p), do: {Integer.to_string(round(x), 16), 0}

  defp to_fixed(x, p), do: :erlang.float_to_binary(x, decimals: p)

  # JavaScript's `toExponential(p)`: `d.ddde+X` with the exponent unpadded.
  defp to_exponential(x, p) do
    {coefficient, exponent} = decimal_parts(x, p + 1)
    {first, rest} = String.split_at(coefficient, 1)
    mantissa = if rest == "", do: first, else: first <> "." <> rest
    mantissa <> "e" <> exponent_string(exponent)
  end

  defp exponent_string(e) when e < 0, do: "-" <> Integer.to_string(-e)
  defp exponent_string(e), do: "+" <> Integer.to_string(e)

  # JavaScript's `toPrecision(p)`: exponential notation when the exponent is below −6 or at
  # least `p`, fixed notation with `p` significant digits otherwise.
  defp to_precision(x, p) do
    {coefficient, exponent} = decimal_parts(x, p)

    cond do
      exponent < -6 or exponent >= p ->
        {first, rest} = String.split_at(coefficient, 1)
        if(rest == "", do: first, else: first <> "." <> rest) <> "e" <> exponent_string(exponent)

      exponent >= 0 ->
        {int, frac} = String.split_at(coefficient, exponent + 1)
        if frac == "", do: int, else: int <> "." <> frac

      true ->
        "0." <> String.duplicate("0", -exponent - 1) <> coefficient
    end
  end

  # d3's `formatRounded`: `p` significant digits in plain notation.
  defp rounded(x, p) do
    {coefficient, exponent} = decimal_parts(x, p)
    n = String.length(coefficient)

    cond do
      exponent < 0 ->
        "0." <> String.duplicate("0", -exponent - 1) <> coefficient

      n > exponent + 1 ->
        String.slice(coefficient, 0, exponent + 1) <>
          "." <> String.slice(coefficient, (exponent + 1)..-1//1)

      true ->
        coefficient <> String.duplicate("0", exponent - n + 1)
    end
  end

  # d3's `formatPrefixAuto`: the mantissa for the SI prefix of the value's thousands
  # exponent, and that exponent (a multiple of 3 in [−24, 24]) for the caller's suffix.
  defp prefix_auto(x, p) do
    {coefficient, exponent} = decimal_parts(x, p)
    prefix_exponent = (exponent |> Integer.floor_div(3) |> max(-8) |> min(8)) * 3
    i = exponent - prefix_exponent + 1
    n = String.length(coefficient)

    mantissa =
      cond do
        i == n -> coefficient
        i > n -> coefficient <> String.duplicate("0", i - n)
        i > 0 -> String.slice(coefficient, 0, i) <> "." <> String.slice(coefficient, i..-1//1)
        # Less than 1y: re-round to the digits that fit.
        true -> "0." <> String.duplicate("0", -i) <> elem(decimal_parts(x, max(0, p + i - 1)), 0)
      end

    {mantissa, prefix_exponent}
  end

  # d3's `formatDecimalParts`: the significant digits (no point) and the decimal exponent of
  # `x` rounded to `p` significant digits, from the scientific form `d.ddde±XX`.
  defp decimal_parts(x, p) do
    [mantissa, exponent] =
      x |> :erlang.float_to_binary(scientific: max(p - 1, 0)) |> String.split("e")

    {String.replace(mantissa, ".", ""), String.to_integer(exponent)}
  end

  # d3's `formatTrim`: drop insignificant trailing zeros after the point, and the point
  # itself when nothing else follows it, stopping at an exponent.
  defp trim_zeros(s) do
    case Regex.run(~r/^(\d*)\.(\d*?)0*(e.*)?$/, s) do
      nil -> s
      [_, int, ""] -> int
      [_, int, frac] -> int <> "." <> frac
      [_, int, "", exp] -> int <> exp
      [_, int, frac, exp] -> int <> "." <> frac <> exp
    end
  end

  defp zero_string?(s, type) when type in ~w(b o x X), do: String.trim_leading(s, "0") == ""
  defp zero_string?(s, _type), do: not String.match?(s, ~r/[1-9]/)

  # --- duration/1 ----------------------------------------------------------------------------

  @doc """
  A length of time in seconds, in the unit its magnitude chooses (spec/05 §2.9, #191): the
  largest of `d`, `h`, `m`, `s`, `ms` the value reaches — a whole count as it is, one that
  is whole in the next finer unit as both, any other to one decimal.

  ## Examples

      iex> Enum.map([45, 150, 5400, 5430, 3660, 2.5, 0.25, 0, -90], &Visualize.Format.duration/1)
      ["45s", "2m30s", "1h30m", "1.5h", "1h1m", "2.5s", "250ms", "0s", "−1m30s"]

  """
  @spec duration(number()) :: String.t()
  def duration(seconds) when is_number(seconds) and seconds < 0, do: "−" <> duration(-seconds)
  def duration(0), do: "0s"
  def duration(+0.0), do: "0s"

  def duration(seconds) when is_number(seconds) do
    units = [{"d", 86_400}, {"h", 3600}, {"m", 60}, {"s", 1}, {"ms", 0.001}]

    case Enum.drop_while(units, fn {_u, size} -> seconds < size end) do
      [] ->
        "#{trim(Float.round(seconds * 1000, 1))}ms"

      [{unit, size} | finer] ->
        count = seconds / size

        cond do
          whole?(count) ->
            "#{round(count)}#{unit}"

          finer != [] and unit != "s" and whole?(rem_in(seconds, size, hd(finer))) and
              rem_in(seconds, size, hd(finer)) >= 1 ->
            {finer_unit, _} = hd(finer)
            "#{trunc(count)}#{unit}#{round(rem_in(seconds, size, hd(finer)))}#{finer_unit}"

          true ->
            "#{trim(Float.round(count * 1.0, 1))}#{unit}"
        end
    end
  end

  defp rem_in(seconds, size, {_unit, finer_size}),
    do: (seconds - trunc(seconds / size) * size) / finer_size

  defp whole?(count), do: abs(count - round(count)) < 1.0e-9

  defp trim(float),
    do:
      float
      |> :erlang.float_to_binary(decimals: 1)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")

  # --- time/2: strftime ---------------------------------------------------------------------

  @doc """
  Formats a date/time value with strftime-style directives.

  | Directive | Value |
  |---|---|
  | `%Y` | four-digit year |
  | `%y` | two-digit year |
  | `%m` | month `01`–`12` |
  | `%d` | day of month `01`–`31` |
  | `%e` | day of month, space-padded ` 1`–`31` |
  | `%j` | day of year `001`–`366` |
  | `%H` | hour `00`–`23` |
  | `%I` | hour `01`–`12` |
  | `%M` | minute `00`–`59` |
  | `%S` | second `00`–`60` |
  | `%L` | milliseconds `000`–`999` |
  | `%p` | `AM` or `PM` |
  | `%a` | abbreviated weekday name |
  | `%A` | full weekday name |
  | `%b` | abbreviated month name |
  | `%B` | full month name |
  | `%U` | week of the year, Sunday first, `00`–`53` |
  | `%w` | weekday as a number, Sunday `0` |
  | `%Z` | time zone abbreviation (`DateTime` only; otherwise empty) |
  | `%z` | time zone offset `+hhmm` (`DateTime` only; otherwise empty) |
  | `%%` | a literal `%` |

  A `Date` has the time fields at zero. An unknown directive passes through verbatim.
  """
  @spec time(DateTime.t() | Date.t() | NaiveDateTime.t(), String.t()) :: String.t()
  def time(datetime, format \\ "%Y-%m-%d") do
    fields = time_fields(datetime)
    format |> tokenize([]) |> Enum.map_join(&directive(&1, fields))
  end

  defp tokenize("", acc), do: Enum.reverse(acc)

  defp tokenize("%" <> <<c::utf8, rest::binary>>, acc),
    do: tokenize(rest, [{:directive, <<c::utf8>>} | acc])

  defp tokenize(<<c::utf8, rest::binary>>, acc), do: tokenize(rest, [<<c::utf8>> | acc])

  defp directive({:directive, "Y"}, f), do: pad_int(f.year, 4)
  defp directive({:directive, "y"}, f), do: pad_int(rem(f.year, 100), 2)
  defp directive({:directive, "m"}, f), do: pad_int(f.month, 2)
  defp directive({:directive, "d"}, f), do: pad_int(f.day, 2)
  defp directive({:directive, "e"}, f), do: f.day |> Integer.to_string() |> String.pad_leading(2)
  defp directive({:directive, "j"}, f), do: pad_int(Date.day_of_year(f.date), 3)
  defp directive({:directive, "H"}, f), do: pad_int(f.hour, 2)
  defp directive({:directive, "I"}, f), do: pad_int(twelve_hour(f.hour), 2)
  defp directive({:directive, "M"}, f), do: pad_int(f.minute, 2)
  defp directive({:directive, "S"}, f), do: pad_int(f.second, 2)
  defp directive({:directive, "L"}, f), do: pad_int(div(f.microsecond, 1000), 3)
  defp directive({:directive, "p"}, f), do: if(f.hour < 12, do: "AM", else: "PM")
  defp directive({:directive, "a"}, f), do: Enum.at(@weekday_abbrs, Date.day_of_week(f.date) - 1)
  defp directive({:directive, "A"}, f), do: Enum.at(@weekday_names, Date.day_of_week(f.date) - 1)
  defp directive({:directive, "b"}, f), do: month_abbr(f.month)
  defp directive({:directive, "B"}, f), do: month_name(f.month)

  defp directive({:directive, "U"}, f),
    do: pad_int(div(Date.day_of_year(f.date) + 6 - sunday_weekday(f.date), 7), 2)

  defp directive({:directive, "w"}, f), do: Integer.to_string(sunday_weekday(f.date))
  defp directive({:directive, "Z"}, f), do: f.zone_abbr
  defp directive({:directive, "z"}, f), do: offset_string(f.utc_offset)
  defp directive({:directive, "%"}, _f), do: "%"
  defp directive({:directive, other}, _f), do: "%" <> other
  defp directive(literal, _f), do: literal

  defp time_fields(%DateTime{} = dt) do
    %{
      date: DateTime.to_date(dt),
      year: dt.year,
      month: dt.month,
      day: dt.day,
      hour: dt.hour,
      minute: dt.minute,
      second: dt.second,
      microsecond: elem(dt.microsecond, 0),
      zone_abbr: dt.zone_abbr,
      utc_offset: dt.utc_offset + dt.std_offset
    }
  end

  defp time_fields(%NaiveDateTime{} = dt) do
    %{
      date: NaiveDateTime.to_date(dt),
      year: dt.year,
      month: dt.month,
      day: dt.day,
      hour: dt.hour,
      minute: dt.minute,
      second: dt.second,
      microsecond: elem(dt.microsecond, 0),
      zone_abbr: "",
      utc_offset: nil
    }
  end

  defp time_fields(%Date{} = date) do
    %{
      date: date,
      year: date.year,
      month: date.month,
      day: date.day,
      hour: 0,
      minute: 0,
      second: 0,
      microsecond: 0,
      zone_abbr: "",
      utc_offset: nil
    }
  end

  defp twelve_hour(hour) do
    case rem(hour, 12) do
      0 -> 12
      h -> h
    end
  end

  # Sunday is 0, as in strftime; `Date.day_of_week/2` with `:sunday` gives Sunday as 1.
  defp sunday_weekday(date), do: Date.day_of_week(date, :sunday) - 1

  defp offset_string(nil), do: ""

  defp offset_string(seconds) do
    sign = if seconds < 0, do: "-", else: "+"
    minutes = div(abs(seconds), 60)
    sign <> pad_int(div(minutes, 60), 2) <> pad_int(rem(minutes, 60), 2)
  end

  # --- Private helpers -------------------------------------------------------------------

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

  defp pad_int(n, width), do: n |> Integer.to_string() |> String.pad_leading(width, "0")

  defp month_abbr(m), do: Enum.at(@month_abbrs, m - 1)
  defp month_name(m), do: Enum.at(@month_names, m - 1)
end
