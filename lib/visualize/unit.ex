defmodule Visualize.Unit do
  @moduledoc """
  Units named by their UCUM codes (spec/05 §4.1, D-138).

  A unit is named by its code in the Unified Code for Units of Measure — UCUM,
  <https://ucum.org/ucum>, version 2.1, Regenstrief Institute — the case-sensitive,
  unambiguous codes OpenTelemetry's semantic conventions use: `s`, `ms`, `By`, `kBy`,
  `MiBy`, `%`, `Cel`, `kW.h`, `{request}/s`. One code per unit is the point: a source that
  says `"s"` and one that says `"sec"` must not draw two labels, so a code is checked,
  never guessed at.

  This module reads the subset of UCUM's grammar (§2.1 of the specification, *Syntax
  rules*) that measurement data uses — products `.`, quotients `/` (left-associative,
  §2.1.3), signed integer exponents, integer factors and `{annotation}` blocks (§2.1.5)
  — over a fixed table of prefixes (`k M G m u n Ki Mi Gi`) and atoms (`s min h d By bit
  % Hz Cel [degF] K m g W J Pa`). A symbol is matched whole before it is split into a
  prefix and an atom (§2.1.4), so `min` is the minute, and a prefix is refused on an
  atom UCUM does not call metric (`kmin`). Parentheses and UCUM's other atoms are not
  read; the table grows by proposal.

  A code has a dimension and an exact factor to its base (the second, the byte, the
  metre, the gram, the kelvin), so values scale between two codes of one dimension —
  1,500 `ms` is 1.5 `s`. `Cel` and `[degF]` are UCUM's special units, scales with an
  offset, and have no factor: conversion between unit systems is out of scope.

  ## Examples

      iex> Visualize.Unit.valid?("kW.h")
      true

      iex> Visualize.Unit.parse("sec")
      {:error, {:unknown_atom, "sec"}}

      iex> Visualize.Unit.symbol("By/s")
      "B/s"

      iex> Visualize.Unit.convert(1500, "ms", "s")
      1.5

      iex> Visualize.Unit.from_telemetry(:millisecond)
      {:ok, "ms"}

  """

  @typedoc "A UCUM code, such as `ms` or `{request}/s`."
  @type code :: String.t()

  @typedoc """
  One component of a code: a prefixed atom, an integer factor or an annotation standing
  alone, with its exponent — negated when the component divides.
  """
  @type component :: %{
          prefix: String.t() | nil,
          atom: String.t() | nil,
          factor: pos_integer() | nil,
          annotation: String.t() | nil,
          exponent: integer()
        }

  @typedoc "Why a string is not a code."
  @type reason ::
          :empty
          | {:syntax, String.t()}
          | {:unknown_atom, String.t()}
          | {:not_metric, String.t(), String.t()}

  @typedoc "A base dimension and its exponent; `%{}` is dimensionless."
  @type dimension :: %{
          optional(:time | :information | :length | :mass | :temperature) => integer()
        }

  @typedoc "An exact factor, `{numerator, denominator}`."
  @type ratio :: {pos_integer(), pos_integer()}

  # Each atom: its dimension, its factor to the base (`nil` for a special unit), whether
  # UCUM calls it metric (only a metric atom takes a prefix), and its display symbol.
  @atoms %{
    "s" => {%{time: 1}, {1, 1}, true, "s"},
    "min" => {%{time: 1}, {60, 1}, false, "min"},
    "h" => {%{time: 1}, {3_600, 1}, false, "h"},
    "d" => {%{time: 1}, {86_400, 1}, false, "d"},
    "By" => {%{information: 1}, {1, 1}, true, "B"},
    "bit" => {%{information: 1}, {1, 8}, true, "bit"},
    "%" => {%{}, {1, 100}, false, "%"},
    "Hz" => {%{time: -1}, {1, 1}, true, "Hz"},
    "Cel" => {%{temperature: 1}, nil, true, "°C"},
    "[degF]" => {%{temperature: 1}, nil, false, "°F"},
    "K" => {%{temperature: 1}, {1, 1}, true, "K"},
    "m" => {%{length: 1}, {1, 1}, true, "m"},
    "g" => {%{mass: 1}, {1, 1}, true, "g"},
    "W" => {%{mass: 1, length: 2, time: -3}, {1_000, 1}, true, "W"},
    "J" => {%{mass: 1, length: 2, time: -2}, {1_000, 1}, true, "J"},
    "Pa" => {%{mass: 1, length: -1, time: -2}, {1_000, 1}, true, "Pa"}
  }

  # The prefixes, the two-letter binary ones first so `MiBy` splits as `Mi`·`By`.
  @prefixes [
    {"Ki", {1_024, 1}, "Ki"},
    {"Mi", {1_048_576, 1}, "Mi"},
    {"Gi", {1_073_741_824, 1}, "Gi"},
    {"k", {1_000, 1}, "k"},
    {"M", {1_000_000, 1}, "M"},
    {"G", {1_000_000_000, 1}, "G"},
    {"m", {1, 1_000}, "m"},
    {"u", {1, 1_000_000}, "µ"},
    {"n", {1, 1_000_000_000}, "n"}
  ]

  @telemetry %{
    second: "s",
    millisecond: "ms",
    microsecond: "us",
    nanosecond: "ns",
    minute: "min",
    hour: "h",
    day: "d",
    byte: "By",
    kilobyte: "kBy",
    megabyte: "MBy",
    gigabyte: "GBy",
    kibibyte: "KiBy",
    mebibyte: "MiBy",
    gibibyte: "GiBy",
    bit: "bit",
    kilobit: "kbit",
    megabit: "Mbit",
    percent: "%",
    unit: "1",
    hertz: "Hz",
    celsius: "Cel",
    fahrenheit: "[degF]",
    kelvin: "K",
    meter: "m",
    metre: "m",
    watt: "W",
    kilowatt: "kW",
    joule: "J",
    pascal: "Pa"
  }

  @superscripts %{
    ?0 => "⁰",
    ?1 => "¹",
    ?2 => "²",
    ?3 => "³",
    ?4 => "⁴",
    ?5 => "⁵",
    ?6 => "⁶",
    ?7 => "⁷",
    ?8 => "⁸",
    ?9 => "⁹"
  }

  @doc """
  The components of a code, or why it is not one (spec/05 §4.4).

  ## Examples

      iex> Visualize.Unit.parse("km/h")
      {:ok,
       [
         %{prefix: "k", atom: "m", factor: nil, annotation: nil, exponent: 1},
         %{prefix: nil, atom: "h", factor: nil, annotation: nil, exponent: -1}
       ]}

      iex> Visualize.Unit.parse("kmin")
      {:error, {:not_metric, "k", "min"}}

  """
  @spec parse(String.t()) :: {:ok, [component(), ...]} | {:error, reason()}
  def parse(""), do: {:error, :empty}

  # A leading `/` divides by the whole term after it (UCUM §2.1: main-term).
  def parse("/" <> rest) do
    with {:ok, components} <- term(rest, 1, []),
         do: {:ok, Enum.map(components, &%{&1 | exponent: -&1.exponent})}
  end

  def parse(code) when is_binary(code), do: term(code, 1, [])

  @doc "Whether a string is a code `parse/1` reads."
  @spec valid?(term()) :: boolean()
  def valid?(code) when is_binary(code), do: match?({:ok, _}, parse(code))
  def valid?(_code), do: false

  @doc """
  The dimension of a code: each base dimension's exponent, `%{}` when dimensionless.
  Raises `ArgumentError` for a string that is not a code.
  """
  @spec dimension(code()) :: dimension()
  def dimension(code) do
    code
    |> parse!()
    |> Enum.filter(& &1.atom)
    |> Enum.reduce(%{}, fn %{atom: atom, exponent: e}, acc ->
      {dims, _factor, _metric, _symbol} = Map.fetch!(@atoms, atom)
      Enum.reduce(dims, acc, fn {dim, n}, acc -> Map.update(acc, dim, n * e, &(&1 + n * e)) end)
    end)
    |> Map.reject(fn {_dim, n} -> n == 0 end)
  end

  @doc """
  The exact factor of a code to its base, `{numerator, denominator}`, or `nil` for a code
  holding a special unit (`Cel`, `[degF]`). Raises `ArgumentError` for a string that is
  not a code.
  """
  @spec factor(code()) :: ratio() | nil
  def factor(code) do
    code
    |> parse!()
    |> Enum.reduce_while({1, 1}, fn component, acc ->
      case component_factor(component) do
        nil -> {:halt, nil}
        ratio -> {:cont, multiply(acc, power(ratio, component.exponent))}
      end
    end)
  end

  @doc """
  A value in `from` written in `to`: `value × factor(from) / factor(to)`, for two codes
  of one dimension that both have a factor. Raises `ArgumentError` otherwise — between
  unit systems (`Cel` and `[degF]`) above all, which is out of scope.

  ## Examples

      iex> Visualize.Unit.convert(2_500_000, "By", "MBy")
      2.5

  """
  @spec convert(number(), code(), code()) :: float()
  def convert(value, from, to) when is_number(value) do
    with true <- dimension(from) == dimension(to),
         {fnum, fd} <- factor(from),
         {tn, td} <- factor(to) do
      {n, d} = reduce({fnum * td, fd * tn})
      value * n / d
    else
      _ ->
        raise ArgumentError,
              "cannot convert #{inspect(from)} to #{inspect(to)}: only units of one " <>
                "dimension that scale by a factor convert (spec/05 §4.1)"
    end
  end

  @doc """
  The display symbol of a code (spec/05 §4.1): `B` for `By`, `µs` for `us`, `°C` for
  `Cel`, `kW·h` for `kW.h`, `m²` for `m2`; the factor `1` and annotations are dropped, so
  `1` and `{request}` are `""`.

  ## Options

  - `:annotations` - write an annotation standing alone as its text (`{request}/s` →
    `request/s`), default `false`

  ## Examples

      iex> Visualize.Unit.symbol("us")
      "µs"

      iex> Visualize.Unit.symbol("{request}/s", annotations: true)
      "request/s"

  """
  @spec symbol(code(), keyword()) :: String.t()
  def symbol(code, opts \\ []) do
    annotations? = Keyword.get(opts, :annotations, false)
    {up, down} = code |> parse!() |> Enum.split_with(&(&1.exponent > 0))
    numerator = up |> Enum.map(&written(&1, annotations?)) |> Enum.reject(&(&1 == ""))
    denominator = down |> Enum.map(&written(&1, annotations?)) |> Enum.reject(&(&1 == ""))

    case denominator do
      [] -> Enum.join(numerator, "·")
      [one] -> Enum.join(numerator, "·") <> "/" <> one
      many -> Enum.join(numerator, "·") <> "/(" <> Enum.join(many, "·") <> ")"
    end
  end

  @doc """
  The code of a `Telemetry.Metrics` unit — its unit atom, or the `to` of a `{from, to}`
  conversion — with no dependency on `telemetry_metrics` (spec/05 §4.1). `:native` has
  no fixed size until a definition converts it, and an atom not in the table is refused
  rather than guessed at.

  ## Examples

      iex> Visualize.Unit.from_telemetry({:native, :microsecond})
      {:ok, "us"}

      iex> Visualize.Unit.from_telemetry(:native)
      {:error, :native}

  """
  @spec from_telemetry(atom() | {atom(), atom()}) ::
          {:ok, code()} | {:error, :native | {:unknown, term()}}
  def from_telemetry({_from, to}), do: from_telemetry(to)
  def from_telemetry(:native), do: {:error, :native}

  def from_telemetry(unit) do
    case Map.fetch(@telemetry, unit) do
      {:ok, code} -> {:ok, code}
      :error -> {:error, {:unknown, unit}}
    end
  end

  # -- reading ------------------------------------------------------------------------

  # Components and the operators between them, left to right; `sign` is the exponent sign
  # the operator before this component gives it.
  defp term(code, sign, acc) do
    with {:ok, component, rest} <- component(code) do
      acc = [%{component | exponent: sign * component.exponent} | acc]

      case rest do
        "" -> {:ok, Enum.reverse(acc)}
        "." <> more -> term(more, 1, acc)
        "/" <> more -> term(more, -1, acc)
        _other -> {:error, {:syntax, rest}}
      end
    end
  end

  defp component("{" <> _ = code) do
    with {:ok, annotation, rest} <- annotation(code),
         do: {:ok, blank(%{annotation: annotation}), rest}
  end

  defp component(<<digit, _::binary>> = code) when digit in ?0..?9 do
    {digits, rest} = take(code, &(&1 in ?0..?9))

    case String.to_integer(digits) do
      0 ->
        {:error, {:syntax, code}}

      factor ->
        with {:ok, annotation, rest} <- maybe_annotation(rest),
             do: {:ok, blank(%{factor: factor, annotation: annotation}), rest}
    end
  end

  defp component(code) do
    with {:ok, symbol, rest} <- symbol_run(code),
         {:ok, prefix, atom} <- resolve(symbol),
         {:ok, exponent, rest} <- exponent(rest),
         {:ok, annotation, rest} <- maybe_annotation(rest) do
      {:ok,
       %{prefix: prefix, atom: atom, factor: nil, annotation: annotation, exponent: exponent},
       rest}
    end
  end

  defp blank(fields),
    do: Map.merge(%{prefix: nil, atom: nil, factor: nil, annotation: nil, exponent: 1}, fields)

  # A bracketed atom (`[degF]`) whole, or a run of letters and `%`.
  defp symbol_run("[" <> _ = code) do
    case :binary.match(code, "]") do
      {at, 1} ->
        {:ok, binary_part(code, 0, at + 1), binary_part(code, at + 1, byte_size(code) - at - 1)}

      :nomatch ->
        {:error, {:syntax, code}}
    end
  end

  defp symbol_run(code) do
    case take(code, &(&1 in ?a..?z or &1 in ?A..?Z or &1 == ?%)) do
      {"", _rest} -> {:error, {:syntax, code}}
      {symbol, rest} -> {:ok, symbol, rest}
    end
  end

  # An atom matched whole first; then a prefix and a metric atom, longest prefix first.
  defp resolve(symbol) when is_map_key(@atoms, symbol), do: {:ok, nil, symbol}

  defp resolve(symbol) do
    split =
      for {prefix, _factor, _symbol} <- @prefixes,
          String.starts_with?(symbol, prefix),
          atom = binary_part(symbol, byte_size(prefix), byte_size(symbol) - byte_size(prefix)),
          is_map_key(@atoms, atom),
          do: {prefix, atom}

    case split do
      [] ->
        {:error, {:unknown_atom, symbol}}

      [{prefix, atom} | _] ->
        if metric?(atom), do: {:ok, prefix, atom}, else: {:error, {:not_metric, prefix, atom}}
    end
  end

  defp metric?(atom), do: @atoms |> Map.fetch!(atom) |> elem(2)

  defp exponent(<<sign, digit, _::binary>> = code) when sign in [?+, ?-] and digit in ?0..?9 do
    <<_sign, rest::binary>> = code
    {digits, rest} = take(rest, &(&1 in ?0..?9))
    n = String.to_integer(digits)
    {:ok, if(sign == ?-, do: -n, else: n), rest}
  end

  defp exponent(<<sign, _::binary>> = code) when sign in [?+, ?-], do: {:error, {:syntax, code}}

  defp exponent(<<digit, _::binary>> = code) when digit in ?0..?9 do
    {digits, rest} = take(code, &(&1 in ?0..?9))
    {:ok, String.to_integer(digits), rest}
  end

  defp exponent(code), do: {:ok, 1, code}

  defp maybe_annotation("{" <> _ = code), do: annotation(code)
  defp maybe_annotation(code), do: {:ok, nil, code}

  # `{` text `}`, the text one or more of ASCII 33–126 except the braces (UCUM §2.1.5).
  defp annotation("{" <> rest = code) do
    case take(rest, &(&1 in 33..126 and &1 not in [?{, ?}])) do
      {text, "}" <> rest} when text != "" -> {:ok, text, rest}
      _unclosed -> {:error, {:syntax, code}}
    end
  end

  defp take(code, keep?), do: take(code, keep?, 0)

  defp take(code, keep?, n) do
    case code do
      <<_::binary-size(^n), c, _::binary>> ->
        if keep?.(c), do: take(code, keep?, n + 1), else: split_at(code, n)

      _end ->
        split_at(code, n)
    end
  end

  defp split_at(code, n), do: {binary_part(code, 0, n), binary_part(code, n, byte_size(code) - n)}

  defp parse!(code) do
    case parse(code) do
      {:ok, components} ->
        components

      {:error, reason} ->
        raise ArgumentError,
              "not a UCUM code Visualize.Unit reads: #{inspect(code)} (#{inspect(reason)})"
    end
  end

  # -- factors ------------------------------------------------------------------------

  defp component_factor(%{atom: nil, factor: nil}), do: {1, 1}
  defp component_factor(%{atom: nil, factor: n}), do: {n, 1}

  defp component_factor(%{atom: atom, prefix: prefix}) do
    case Map.fetch!(@atoms, atom) do
      {_dims, nil, _metric, _symbol} -> nil
      {_dims, ratio, _metric, _symbol} -> multiply(prefix_factor(prefix), ratio)
    end
  end

  defp prefix_factor(nil), do: {1, 1}

  defp prefix_factor(prefix),
    do: @prefixes |> List.keyfind!(prefix, 0) |> elem(1)

  defp power({n, d}, e) when e >= 0, do: {Integer.pow(n, e), Integer.pow(d, e)}
  defp power({n, d}, e), do: {Integer.pow(d, -e), Integer.pow(n, -e)}

  defp multiply({a, b}, {c, d}), do: reduce({a * c, b * d})

  defp reduce({n, d}) do
    g = Integer.gcd(n, d)
    {div(n, g), div(d, g)}
  end

  # -- symbols ------------------------------------------------------------------------

  defp written(%{atom: nil, factor: nil, annotation: text}, true), do: text
  defp written(%{atom: nil, factor: nil}, false), do: ""
  defp written(%{atom: nil, factor: 1}, _annotations?), do: ""

  defp written(%{atom: nil, factor: n, exponent: e}, _annotations?),
    do: Integer.to_string(n) <> superscript(abs(e))

  defp written(%{atom: atom, prefix: prefix, exponent: e}, _annotations?) do
    {_dims, _factor, _metric, symbol} = Map.fetch!(@atoms, atom)
    prefix_symbol(prefix) <> symbol <> superscript(abs(e))
  end

  defp prefix_symbol(nil), do: ""
  defp prefix_symbol(prefix), do: @prefixes |> List.keyfind!(prefix, 0) |> elem(2)

  defp superscript(1), do: ""

  defp superscript(n),
    do: n |> Integer.to_string() |> String.to_charlist() |> Enum.map_join(&@superscripts[&1])
end
