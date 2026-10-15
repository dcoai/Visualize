defmodule Visualize.Unit do
  @moduledoc """
  Units named by their UCUM codes (spec/05 §4.1, D-138, D-155).

  A unit is named by its code in the Unified Code for Units of Measure — UCUM,
  <https://ucum.org/ucum>, Regenstrief Institute — the case-sensitive, unambiguous codes
  OpenTelemetry's semantic conventions use: `s`, `ms`, `By`, `kBy`, `MiBy`, `%`, `Cel`,
  `kW.h`, `{request}/s`, `[lb_av]`, `mm[Hg]`. One code per unit is the point: a source that
  says `"s"` and one that says `"sec"` must not draw two labels, so a code is checked,
  never guessed at. Every atom and prefix here is UCUM's, with UCUM's definition, checked
  against the UCUM essence table (`ucum-essence.xml`, version 2.2, 2024-06-17).

  This module reads the subset of UCUM's grammar (§2.1 of the specification, *Syntax
  rules*) that measurement data uses — products `.`, quotients `/` (left-associative,
  §2.1.3), signed integer exponents, integer factors and `{annotation}` blocks (§2.1.5)
  — over a fixed table of prefixes (`da h k M G T d c m u n p Ki Mi Gi Ti`) and atoms:
  time, information, ratios, temperature, SI and customary length, area, volume and mass,
  speed, power, energy, pressure, angle, charge, current, potential, illuminance, the
  mole and the logarithmic bel. A symbol is matched whole before it is split into a
  prefix and an atom (§2.1.4), so `min` is the minute, and a prefix is refused on an atom
  UCUM does not call metric (`kmin`, `k[in_i]`). Parentheses and UCUM's other atoms are
  not read; the table grows by proposal.

  A code has a dimension and an exact factor to its base (the second, the byte, the
  meter, the gram, the kelvin, the radian, the coulomb): a rational, times a power of π
  for a code holding the degree. So values scale between two codes of one dimension —
  1,500 `ms` is 1.5 `s` — and convert exactly, `value × scale + offset` (`conversion/2`).
  `Cel` and `[degF]` are UCUM's affine special units, scales with an offset: they have no
  factor and convert by their offsets. `B` and `B[SPL]` are its logarithmic ones; each has a
  level dimension of its own here, so a decibel scales to a bel and never to a linear
  unit. A currency never converts: an exchange rate is data.

  A person types symbols, not codes: `parse_alias/1` reads them, and refuses an ambiguous
  one (`KB`, `gal`) naming the codes it could mean.

  ## Examples

      iex> Visualize.Unit.valid?("kW.h")
      true

      iex> Visualize.Unit.parse("sec")
      {:error, {:unknown_atom, "sec"}}

      iex> Visualize.Unit.symbol("By/s")
      "B/s"

      iex> Visualize.Unit.convert(1500, "ms", "s")
      1.5

      iex> Visualize.Unit.parse_alias("mph")
      {:ok, "[mi_i]/h"}

      iex> Visualize.Unit.from_telemetry(:millisecond)
      {:ok, "ms"}

  """

  alias Visualize.Unit.{Alias, Currency}

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

  @typedoc "Why a string is not a code, or a symbol not an alias."
  @type reason ::
          :empty
          | {:syntax, String.t()}
          | {:unknown_atom, String.t()}
          | {:not_metric, String.t(), String.t()}
          | {:unknown_currency, String.t()}

  @typedoc "Why `parse_alias/1` refuses a symbol."
  @type alias_reason ::
          {:ambiguous, String.t(), [{code(), String.t()}, ...]}
          | {:unknown_alias, String.t()}

  @typedoc "Why `conversion/2` refuses a pair of codes."
  @type conversion_reason ::
          {:dimension | :logarithmic | :currency, code(), code()}
          | {:affine_in_term, code()}

  @typedoc "A base dimension and its exponent; `%{}` is dimensionless."
  @type dimension :: %{
          optional(
            :time
            | :information
            | :length
            | :mass
            | :temperature
            | :angle
            | :charge
            | :luminous_intensity
            | :level
            | :sound_pressure_level
            | {:currency, String.t()}
          ) => integer()
        }

  @typedoc "An exact rational factor, `{numerator, denominator}`."
  @type ratio :: {pos_integer(), pos_integer()}

  @typedoc """
  An exact factor: a rational, or `{numerator, denominator, k}` — the rational times
  π to the non-zero power `k`, for a code holding the degree.
  """
  @type exact :: ratio() | {pos_integer(), pos_integer(), integer()}

  @typedoc "How a code's values relate to its base: by a factor, an offset or a logarithm."
  @type kind :: :linear | :affine | :logarithmic

  # The dimensions of the derived SI atoms, in the bases (g, m, s, C, rad, cd).
  @power %{mass: 1, length: 2, time: -3}
  @energy %{mass: 1, length: 2, time: -2}
  @pressure %{mass: 1, length: -1, time: -2}

  # Each atom: its dimension, its exact factor to the base as `{n, d, k}` — n/d·πᵏ —
  # (`nil` for an affine unit), whether UCUM calls it metric (only a metric atom takes a
  # prefix), its display symbol, and its kind. Each factor is UCUM's definition, worked
  # to the bases; the comment is that definition.
  @atoms %{
    # time
    "s" => {%{time: 1}, {1, 1, 0}, true, "s", :linear},
    "min" => {%{time: 1}, {60, 1, 0}, false, "min", :linear},
    "h" => {%{time: 1}, {3_600, 1, 0}, false, "h", :linear},
    "d" => {%{time: 1}, {86_400, 1, 0}, false, "d", :linear},
    "Hz" => {%{time: -1}, {1, 1, 0}, true, "Hz", :linear},
    # information
    "By" => {%{information: 1}, {1, 1, 0}, true, "B", :linear},
    "bit" => {%{information: 1}, {1, 8, 0}, true, "bit", :linear},
    # dimensionless: 10*-2, 10*-6, 10*-9; the mole 6.02214076 × 10*23
    "%" => {%{}, {1, 100, 0}, false, "%", :linear},
    "[ppm]" => {%{}, {1, 1_000_000, 0}, false, "ppm", :linear},
    "[ppb]" => {%{}, {1, 1_000_000_000, 0}, false, "ppb", :linear},
    "mol" => {%{}, {602_214_076_000_000_000_000_000, 1, 0}, true, "mol", :linear},
    # temperature: cel(1 K) and degf(5 K/9) are affine
    "Cel" => {%{temperature: 1}, nil, true, "°C", :affine},
    "[degF]" => {%{temperature: 1}, nil, false, "°F", :affine},
    "K" => {%{temperature: 1}, {1, 1, 0}, true, "K", :linear},
    # length: [in_i] 2.54 cm; [ft_i] 12 [in_i]; [yd_i] 3 [ft_i]; [mi_i] 5280 [ft_i]
    "m" => {%{length: 1}, {1, 1, 0}, true, "m", :linear},
    "[in_i]" => {%{length: 1}, {127, 5_000, 0}, false, "in", :linear},
    "[ft_i]" => {%{length: 1}, {381, 1_250, 0}, false, "ft", :linear},
    "[yd_i]" => {%{length: 1}, {1_143, 1_250, 0}, false, "yd", :linear},
    "[mi_i]" => {%{length: 1}, {201_168, 125, 0}, false, "mi", :linear},
    "[nmi_i]" => {%{length: 1}, {1_852, 1, 0}, false, "nmi", :linear},
    # area: ar 100 m2; [acr_us] 160 [rd_us]2, [rd_us] 16.5 [ft_us], [ft_us] 1200/3937 m
    "ar" => {%{length: 2}, {100, 1, 0}, true, "a", :linear},
    "[acr_us]" => {%{length: 2}, {62_726_400_000, 15_499_969, 0}, false, "ac", :linear},
    # volume: l dm3; [gal_us] 231 [in_i]3, [pt_us] /8, [foz_us] /128;
    # [gal_br] 4.54609 l, [pt_br] /8, [foz_br] /160
    "l" => {%{length: 3}, {1, 1_000, 0}, true, "l", :linear},
    "L" => {%{length: 3}, {1, 1_000, 0}, true, "L", :linear},
    "[gal_us]" => {%{length: 3}, {473_176_473, 125_000_000_000, 0}, false, "gal", :linear},
    "[pt_us]" => {%{length: 3}, {473_176_473, 1_000_000_000_000, 0}, false, "pt", :linear},
    "[foz_us]" => {%{length: 3}, {473_176_473, 16_000_000_000_000, 0}, false, "fl oz", :linear},
    "[gal_br]" => {%{length: 3}, {454_609, 100_000_000, 0}, false, "gal", :linear},
    "[pt_br]" => {%{length: 3}, {454_609, 800_000_000, 0}, false, "pt", :linear},
    "[foz_br]" => {%{length: 3}, {454_609, 16_000_000_000, 0}, false, "fl oz", :linear},
    # mass: t 1e3 kg; [lb_av] 7000 [gr], [gr] 64.79891 mg; [oz_av] /16; [stone_av] 14 lb
    "g" => {%{mass: 1}, {1, 1, 0}, true, "g", :linear},
    "t" => {%{mass: 1}, {1_000_000, 1, 0}, true, "t", :linear},
    "[lb_av]" => {%{mass: 1}, {45_359_237, 100_000, 0}, false, "lb", :linear},
    "[oz_av]" => {%{mass: 1}, {45_359_237, 1_600_000, 0}, false, "oz", :linear},
    "[stone_av]" => {%{mass: 1}, {317_514_659, 50_000, 0}, false, "st", :linear},
    # speed: [kn_i] [nmi_i]/h
    "[kn_i]" => {%{length: 1, time: -1}, {463, 900, 0}, false, "kn", :linear},
    # power: W J/s; [HP] 550 [ft_i].[lbf_av]/s, [lbf_av] [lb_av].[g], [g] 9.80665 m/s2
    "W" => {@power, {1_000, 1, 0}, true, "W", :linear},
    "[HP]" => {@power, {37_284_993_579_113_511, 50_000_000_000, 0}, false, "hp", :linear},
    # energy: J N.m; cal cal_th 4.184 J; [Cal] kcal_th
    "J" => {@energy, {1_000, 1, 0}, true, "J", :linear},
    "cal" => {@energy, {4_184, 1, 0}, true, "cal", :linear},
    "[Cal]" => {@energy, {4_184_000, 1, 0}, false, "Cal", :linear},
    # pressure: Pa N/m2; bar 1e5 Pa; [psi] [lbf_av]/[in_i]2; m[Hg] 133.3220 kPa;
    # [in_i'Hg] m[Hg].[in_i]/m
    "Pa" => {@pressure, {1_000, 1, 0}, true, "Pa", :linear},
    "bar" => {@pressure, {100_000_000, 1, 0}, true, "bar", :linear},
    "[psi]" => {@pressure, {8_896_443_230_521, 1_290_320, 0}, false, "psi", :linear},
    "m[Hg]" => {@pressure, {133_322_000, 1, 0}, true, "mHg", :linear},
    "[in_i'Hg]" => {@pressure, {16_931_894, 5, 0}, false, "inHg", :linear},
    # angle: rad the base; deg 2 [pi].rad/360
    "rad" => {%{angle: 1}, {1, 1, 0}, true, "rad", :linear},
    "deg" => {%{angle: 1}, {1, 180, 1}, false, "°", :linear},
    # electricity: C the base; A C/s; V J/C
    "C" => {%{charge: 1}, {1, 1, 0}, true, "C", :linear},
    "A" => {%{charge: 1, time: -1}, {1, 1, 0}, true, "A", :linear},
    "V" => {Map.put(@energy, :charge, -1), {1_000, 1, 0}, true, "V", :linear},
    # light: lx lm/m2, lm cd.sr, sr rad2
    "lx" => {%{luminous_intensity: 1, angle: 2, length: -2}, {1, 1, 0}, true, "lx", :linear},
    # levels: B lg(1 1), B[SPL] 2lg(2 10*-5.Pa); each its own level dimension (D-155)
    "B" => {%{level: 1}, {1, 1, 0}, true, "B", :logarithmic},
    "B[SPL]" => {%{sound_pressure_level: 1}, {1, 1, 0}, true, "B(SPL)", :logarithmic}
  }

  # The prefixes, the two-letter ones first so `MiBy` splits as `Mi`·`By` and `dam` as
  # `da`·`m`.
  @prefixes [
    {"da", {10, 1}, "da"},
    {"Ki", {1_024, 1}, "Ki"},
    {"Mi", {1_048_576, 1}, "Mi"},
    {"Gi", {1_073_741_824, 1}, "Gi"},
    {"Ti", {1_099_511_627_776, 1}, "Ti"},
    {"h", {100, 1}, "h"},
    {"k", {1_000, 1}, "k"},
    {"M", {1_000_000, 1}, "M"},
    {"G", {1_000_000_000, 1}, "G"},
    {"T", {1_000_000_000_000, 1}, "T"},
    {"d", {1, 10}, "d"},
    {"c", {1, 100}, "c"},
    {"m", {1, 1_000}, "m"},
    {"u", {1, 1_000_000}, "µ"},
    {"n", {1, 1_000_000_000}, "n"},
    {"p", {1, 1_000_000_000_000}, "p"}
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

  ## Examples

      iex> Visualize.Unit.dimension("[psi]")
      %{mass: 1, length: -1, time: -2}

      iex> Visualize.Unit.dimension("dB[SPL]")
      %{sound_pressure_level: 1}

  """
  @spec dimension(code()) :: dimension()
  def dimension(code), do: code |> parse!() |> dims()

  @doc """
  The exact factor of a code to its base: `{numerator, denominator}`, or
  `{numerator, denominator, k}` — that rational times πᵏ — for a code holding the degree,
  or `nil` for a code holding an affine unit (`Cel`, `[degF]`). Raises `ArgumentError`
  for a string that is not a code.

  ## Examples

      iex> Visualize.Unit.factor("[ft_i]")
      {381, 1250}

      iex> Visualize.Unit.factor("deg")
      {1, 180, 1}

  """
  @spec factor(code()) :: exact() | nil
  def factor(code) do
    case exact(code) do
      nil -> nil
      {n, d, 0} -> {n, d}
      exact -> exact
    end
  end

  @doc """
  The ISO 4217 code a code is in when it is a currency alone — `{iso4217:USD}` is
  `"USD"` — else `nil`: a rate (`{iso4217:USD}/h`), any other unit, or a string that is not
  a code (spec/05 §4.1).

  ## Examples

      iex> Visualize.Unit.currency("{iso4217:EUR}")
      "EUR"

      iex> Visualize.Unit.currency("{iso4217:EUR}/kW/h")
      nil

  """
  @spec currency(term()) :: String.t() | nil
  def currency(code) when is_binary(code) do
    with {:ok, components} <- parse(code),
         [{{:currency, iso}, 1}] <- Map.to_list(dims(components)) do
      iso
    else
      _other -> nil
    end
  end

  def currency(_code), do: nil

  @doc """
  An ISO 4217 code's minor units — the decimals an amount in it is written to — or `nil`
  for a code with none (`XAU`). Raises `ArgumentError` for a code not in the table.

  ## Examples

      iex> Enum.map(~w(USD JPY BHD XAU), &Visualize.Unit.minor_units/1)
      [2, 0, 3, nil]

  """
  @spec minor_units(String.t()) :: non_neg_integer() | nil
  def minor_units(iso), do: Currency.minor_units(iso)

  @doc """
  How a code's values relate to its base (spec/05 §4.1): `:affine` for a code holding
  `Cel` or `[degF]`, `:logarithmic` for one holding `B` or `B[SPL]`, else `:linear`.
  Raises `ArgumentError` for a string that is not a code.

  ## Examples

      iex> Visualize.Unit.kind("dB")
      :logarithmic

  """
  @spec kind(code()) :: kind()
  def kind(code), do: code |> parse!() |> kind_of()

  @doc """
  The exact conversion from one code to another (spec/05 §4.1, D-155):
  `{:ok, {scale, offset}}`, so that a value in `from` is `value × scale + offset` in `to`
  — `scale` an exact factor (`{n, d}`, or `{n, d, k}` for n/d·πᵏ), `offset` an exact
  signed rational `{n, d}` — or why the two do not convert.

  Two codes of one dimension convert by their factors. The affine units `Cel` and
  `[degF]` convert with their offsets, standing alone. A logarithmic unit converts only
  to its own level. A currency never converts. A refusal is `{:dimension, from, to}`,
  `{:logarithmic, from, to}`, `{:currency, from, to}`, `{:affine_in_term, code}`, or the
  reason `parse/1` refuses a code.

  ## Examples

      iex> Visualize.Unit.conversion("Cel", "[degF]")
      {:ok, {{9, 5}, {32, 1}}}

      iex> Visualize.Unit.conversion("[lb_av]", "kg")
      {:ok, {{45359237, 100000000}, {0, 1}}}

      iex> Visualize.Unit.conversion("dB[SPL]", "Pa")
      {:error, {:logarithmic, "dB[SPL]", "Pa"}}

  """
  @spec conversion(code(), code()) ::
          {:ok, {exact(), {integer(), pos_integer()}}} | {:error, reason() | conversion_reason()}
  def conversion(from, to) do
    with {:ok, fc} <- parse(from),
         {:ok, tc} <- parse(to) do
      cond do
        from == to -> {:ok, {{1, 1}, {0, 1}}}
        currencies(fc) != currencies(tc) -> {:error, {:currency, from, to}}
        dims(fc) != dims(tc) -> {:error, {mismatch(fc, tc), from, to}}
        affine?(fc) or affine?(tc) -> affine(from, fc, to, tc)
        true -> {:ok, {public(divide(exact_of(fc), exact_of(tc))), {0, 1}}}
      end
    end
  end

  @doc """
  A value in `from` written in `to` (spec/05 §4.1): `value × scale + offset` of
  `conversion/2`, as a float — the scale and offset exact, and the arithmetic rounded
  once for an integer value. Raises `ArgumentError` naming the reason for a pair
  `conversion/2` refuses.

  ## Examples

      iex> Visualize.Unit.convert(2_500_000, "By", "MBy")
      2.5

      iex> Visualize.Unit.convert(100, "Cel", "[degF]")
      212.0

      iex> Visualize.Unit.convert(30, "dB", "B")
      3.0

  """
  @spec convert(number(), code(), code()) :: float()
  def convert(value, from, to) when is_number(value) do
    case conversion(from, to) do
      {:ok, {scale, offset}} ->
        apply_conversion(value, scale, offset)

      {:error, reason} ->
        raise ArgumentError,
              "cannot convert #{inspect(from)} to #{inspect(to)}: #{format_error(reason)} " <>
                "(spec/05 §4.1)"
    end
  end

  @doc """
  The code a person means by a symbol they typed (spec/05 §4.1, D-155): `°C`, `lb`,
  `mph`, `kWh`, `KiB`. The alias table is read first, so a person's `B` is the byte and
  not the bel; a symbol the table does not hold is read by `parse/1`, a code being its
  own alias. An ambiguous symbol is refused with the codes it could mean, never guessed.
  Surrounding whitespace is ignored.

  ## Examples

      iex> Visualize.Unit.parse_alias("°F")
      {:ok, "[degF]"}

      iex> Visualize.Unit.parse_alias("KB")
      {:error, {:ambiguous, "KB", [{"kBy", "1,000 bytes"}, {"KiBy", "1,024 bytes"}]}}

      iex> Visualize.Unit.parse_alias("kPa")
      {:ok, "kPa"}

  """
  @spec parse_alias(String.t()) :: {:ok, code()} | {:error, alias_reason()}
  def parse_alias(symbol) when is_binary(symbol) do
    symbol = String.trim(symbol)

    case Alias.lookup(symbol) do
      {:code, code} -> {:ok, code}
      {:ambiguous, choices} -> {:error, {:ambiguous, symbol, choices}}
      :none -> if valid?(symbol), do: {:ok, symbol}, else: {:error, {:unknown_alias, symbol}}
    end
  end

  @doc """
  A refusal of `parse/1`, `parse_alias/1` or `conversion/2` as a line a person reads.

  ## Examples

      iex> Visualize.Unit.format_error({:ambiguous, "gal", [{"[gal_us]", "US gallon"}, {"[gal_br]", "imperial gallon"}]})
      ~s|"gal" is ambiguous: [gal_us] (US gallon) or [gal_br] (imperial gallon)|

  """
  @spec format_error(reason() | alias_reason() | conversion_reason()) :: String.t()
  def format_error({:ambiguous, symbol, choices}) do
    {last, rest} =
      choices |> Enum.map(fn {code, meaning} -> "#{code} (#{meaning})" end) |> List.pop_at(-1)

    or_list = if rest == [], do: last, else: Enum.join(rest, ", ") <> " or " <> last
    "#{inspect(symbol)} is ambiguous: #{or_list}"
  end

  def format_error({:unknown_alias, symbol}),
    do: "#{inspect(symbol)} is neither a unit symbol visualize knows nor a UCUM code"

  def format_error({:dimension, from, to}),
    do: "#{inspect(from)} and #{inspect(to)} measure different dimensions"

  def format_error({:logarithmic, from, to}),
    do: "a level converts only to its own level, so #{inspect(from)} and #{inspect(to)} do not"

  def format_error({:currency, from, to}) do
    "#{inspect(from)} and #{inspect(to)} are in different currencies, which never convert: " <>
      "an exchange rate is data, not a fact about a unit"
  end

  def format_error({:affine_in_term, code}) do
    "#{inspect(code)} holds °C or °F inside a term, which is not a temperature and has no " <>
      "offset to convert by"
  end

  def format_error({:unknown_currency, code}),
    do: "#{inspect(code)} is not an ISO 4217 code of visualize's currency extension"

  def format_error(:empty), do: "a unit code is not empty"
  def format_error({:syntax, rest}), do: "a UCUM code does not read at #{inspect(rest)}"

  def format_error({:unknown_atom, atom}),
    do: "#{inspect(atom)} is not a UCUM unit visualize reads"

  def format_error({:not_metric, prefix, atom}),
    do: "#{inspect(atom)} is not metric, so it takes no prefix (#{inspect(prefix)})"

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
    with {:ok, component, rest} <- component(code),
         :ok <- known_currency(component) do
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

  # The currency extension's annotation names a code of the ISO 4217 table (spec/05 §4.1).
  defp known_currency(%{annotation: "iso4217:" <> code}) do
    if Currency.known?(code), do: :ok, else: {:error, {:unknown_currency, code}}
  end

  defp known_currency(_component), do: :ok

  defp blank(fields),
    do: Map.merge(%{prefix: nil, atom: nil, factor: nil, annotation: nil, exponent: 1}, fields)

  # A run of letters, `%` and bracketed parts — `[` to the next `]` — so `[degF]`,
  # `mm[Hg]` and `dB[SPL]` are each one symbol, as UCUM writes them.
  defp symbol_run(code), do: symbol_run(code, 0)

  defp symbol_run(code, n) do
    case code do
      <<_::binary-size(^n), c, _::binary>> when c in ?a..?z or c in ?A..?Z or c == ?% ->
        symbol_run(code, n + 1)

      <<_::binary-size(^n), ?[, rest::binary>> ->
        case :binary.match(rest, "]") do
          {at, 1} -> symbol_run(code, n + at + 2)
          :nomatch -> {:error, {:syntax, binary_part(code, n, byte_size(code) - n)}}
        end

      _end when n == 0 ->
        {:error, {:syntax, code}}

      _end ->
        {symbol, rest} = split_at(code, n)
        {:ok, symbol, rest}
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

  defp metric?(atom), do: atom |> atom!() |> elem(2)

  defp atom!(atom), do: Map.fetch!(@atoms, atom)

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

  # A code's factor as `{n, d, k}`, n/d·πᵏ, or `nil` when it holds an affine unit.
  defp exact(code), do: code |> parse!() |> exact_of()

  defp component_factor(%{atom: nil, factor: nil}), do: {1, 1, 0}
  defp component_factor(%{atom: nil, factor: n}), do: {n, 1, 0}

  defp component_factor(%{atom: atom, prefix: prefix}) do
    case atom!(atom) do
      {_dims, nil, _metric, _symbol, _kind} -> nil
      {_dims, exact, _metric, _symbol, _kind} -> multiply(prefix_factor(prefix), exact)
    end
  end

  defp prefix_factor(nil), do: {1, 1, 0}

  defp prefix_factor(prefix) do
    {n, d} = @prefixes |> List.keyfind!(prefix, 0) |> elem(1)
    {n, d, 0}
  end

  defp power({n, d, k}, e) when e >= 0, do: {Integer.pow(n, e), Integer.pow(d, e), k * e}
  defp power({n, d, k}, e), do: {Integer.pow(d, -e), Integer.pow(n, -e), k * e}

  defp multiply({a, b, j}, {c, d, k}) do
    {n, d} = reduce({a * c, b * d})
    {n, d, j + k}
  end

  defp reduce({n, d}) do
    g = Integer.gcd(n, d)
    {div(n, g), div(d, g)}
  end

  # -- conversion ---------------------------------------------------------------------

  # The affine units, each as its definition to the kelvin: K = value × scale + offset.
  @affine %{"Cel" => {{1, 1}, {27_315, 100}}, "[degF]" => {{5, 9}, {45_967, 180}}}

  # Each atom's dimension times its exponent, and each currency annotation's own.
  defp dims(components) do
    components
    |> Enum.flat_map(fn
      %{annotation: "iso4217:" <> code, atom: nil, exponent: e} ->
        [{{:currency, code}, e}]

      %{annotation: "iso4217:" <> code, atom: atom, exponent: e} ->
        [{{:currency, code}, e} | atom_dims(atom, e)]

      %{atom: nil} ->
        []

      %{atom: atom, exponent: e} ->
        atom_dims(atom, e)
    end)
    |> Enum.reduce(%{}, fn {dim, n}, acc -> Map.update(acc, dim, n, &(&1 + n)) end)
    |> Map.reject(fn {_dim, n} -> n == 0 end)
  end

  defp atom_dims(atom, e) do
    {dims, _factor, _metric, _symbol, _kind} = atom!(atom)
    for {dim, n} <- dims, do: {dim, n * e}
  end

  defp exact_of(components) do
    Enum.reduce_while(components, {1, 1, 0}, fn component, acc ->
      case component_factor(component) do
        nil -> {:halt, nil}
        exact -> {:cont, multiply(acc, power(exact, component.exponent))}
      end
    end)
  end

  # The currencies a code holds, each `{iso4217:…}` annotation with its exponent.
  defp currencies(components) do
    components
    |> Enum.filter(&match?("iso4217:" <> _, &1.annotation || ""))
    |> Enum.map(&{&1.annotation, &1.exponent})
    |> Enum.sort()
  end

  defp mismatch(fc, tc),
    do:
      if(kind_of(fc) == :logarithmic or kind_of(tc) == :logarithmic,
        do: :logarithmic,
        else: :dimension
      )

  defp kind_of(components) do
    kinds = for %{atom: atom} <- components, atom != nil, do: atom |> atom!() |> elem(4)

    cond do
      :affine in kinds -> :affine
      :logarithmic in kinds -> :logarithmic
      true -> :linear
    end
  end

  defp affine?(components), do: kind_of(components) == :affine

  # Two temperatures through the kelvin, each a standalone affine unit or a linear one.
  defp affine(from, fc, to, tc) do
    with {:ok, {fs, fo}} <- to_kelvin(from, fc),
         {:ok, {ts, to_offset}} <- to_kelvin(to, tc) do
      {sn, sd} = reduce({elem(fs, 0) * elem(ts, 1), elem(fs, 1) * elem(ts, 0)})
      {on, od} = subtract(fo, to_offset)
      offset = reduce_signed({on * elem(ts, 1), od * elem(ts, 0)})
      {:ok, {{sn, sd}, offset}}
    end
  end

  # A temperature code as `{scale, offset}` to the kelvin: `K = value × scale + offset`.
  defp to_kelvin(_code, [%{atom: atom, prefix: prefix, exponent: 1}])
       when is_map_key(@affine, atom) do
    {{n, d}, offset} = Map.fetch!(@affine, atom)
    {pn, pd, 0} = prefix_factor(prefix)
    {:ok, {reduce({n * pn, d * pd}), offset}}
  end

  defp to_kelvin(code, components) do
    case exact_of(components) do
      nil -> {:error, {:affine_in_term, code}}
      {n, d, 0} -> {:ok, {{n, d}, {0, 1}}}
    end
  end

  defp subtract({a, b}, {c, d}), do: reduce_signed({a * d - c * b, b * d})

  defp reduce_signed({0, _d}), do: {0, 1}

  defp reduce_signed({n, d}) do
    g = Integer.gcd(n, d)
    {div(n, g), div(d, g)}
  end

  defp divide({a, b, j}, {c, d, k}), do: multiply({a, b, j}, {d, c, -k})

  defp public({n, d, 0}), do: {n, d}
  defp public(exact), do: exact

  # One rounding for an integer value and a rational scale; a float rounds as it goes.
  defp apply_conversion(value, {n, d}, {on, od}) when is_integer(value),
    do: (value * n * od + on * d) / (d * od)

  defp apply_conversion(value, {n, d}, {on, od}), do: value * n / d + on / od

  defp apply_conversion(value, {n, d, k}, {0, 1}),
    do: value * n / d * :math.pow(:math.pi(), k)

  # -- symbols ------------------------------------------------------------------------

  defp written(%{atom: nil, annotation: "iso4217:" <> code, exponent: e}, _annotations?),
    do: code <> superscript(abs(e))

  defp written(%{atom: nil, factor: nil, annotation: text}, true), do: text
  defp written(%{atom: nil, factor: nil}, false), do: ""
  defp written(%{atom: nil, factor: 1}, _annotations?), do: ""

  defp written(%{atom: nil, factor: n, exponent: e}, _annotations?),
    do: Integer.to_string(n) <> superscript(abs(e))

  defp written(%{atom: atom, prefix: prefix, exponent: e}, _annotations?) do
    {_dims, _factor, _metric, symbol, _kind} = atom!(atom)
    prefix_symbol(prefix) <> symbol <> superscript(abs(e))
  end

  defp prefix_symbol(nil), do: ""
  defp prefix_symbol(prefix), do: @prefixes |> List.keyfind!(prefix, 0) |> elem(2)

  defp superscript(1), do: ""

  defp superscript(n),
    do: n |> Integer.to_string() |> String.to_charlist() |> Enum.map_join(&@superscripts[&1])
end
