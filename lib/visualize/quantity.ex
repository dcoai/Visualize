defmodule Visualize.Quantity do
  @moduledoc """
  A fixed list of quantities, each with a base unit and a display-scaling family, and
  the display scaling they choose (spec/05 §4.2–4.3, D-138).

  A quantity is what a unit measures. A unit (a UCUM code, `Visualize.Unit`) and a
  quantity together are a *measure*, `%{unit: code, quantity: quantity}`, the two facts a
  field description carries. **They are facts about the data, not knobs**: a measure does
  not change a value, it says what the value already is, so a display can choose how to
  show it — 0–1,500 `ms` as 0–1.5 `s`, 2,500,000 `By` as 2.5 `MB`.

  The list is fixed and grows by proposal:

  | Quantity | Base unit | Display family |
  |---|---|---|
  | `:duration` | `s` | `ns us ms s min h d` |
  | `:information` | `By` | `By kBy MBy GBy`; binary `KiBy MiBy GiBy`; bits |
  | `:data_rate` | `By/s` | the information families over `/s` |
  | `:frequency` | `Hz` | `Hz kHz MHz GHz`; events `/h /min /s` |
  | `:ratio` | `1` | — |
  | `:count` | `1` | — (SI from a thousand) |
  | `:temperature` | `Cel` | — |
  | `:length` | `m` | `mm m km` |
  | `:speed` | `m/s` | — |
  | `:power` | `W` | `W kW MW GW` |
  | `:energy` | `J` | `J kJ MJ GJ`; watt-hours `W.h kW.h MW.h GW.h` |
  | `:pressure` | `Pa` | `Pa kPa MPa` |

  Information is **decimal by default** — UCUM's `kBy` and `Telemetry.Metrics`'
  `:kilobyte` are 1,000 bytes — and a unit written with a binary prefix (`MiBy`) or in
  `bit` scales in its own family: the data picks it, no setting does.

  Tick formats are built on `Visualize.Format.Auto` (spec/05 §3), and every function that
  formats takes its `locale:`.

  ## Examples

      iex> Visualize.Quantity.display_unit([0, 1500], %{unit: "ms"})
      "s"

      iex> scale = Visualize.Scale.linear() |> Visualize.Scale.domain([0, 1500])
      iex> Visualize.Quantity.formatter(scale, %{unit: "ms"}).(1500)
      "1.5 s"

      iex> Visualize.Quantity.label(%{unit: "{request}"})
      "request"

  """

  alias Visualize.{Format, Scale, Unit}

  @typedoc "One of the fixed list of quantities."
  @type t ::
          :duration
          | :information
          | :data_rate
          | :frequency
          | :ratio
          | :count
          | :temperature
          | :length
          | :speed
          | :power
          | :energy
          | :pressure

  @typedoc "A unit and a quantity, either or both; the two facts a field description carries."
  @type measure :: %{optional(:unit) => Unit.code() | nil, optional(:quantity) => t() | nil}

  @typedoc "Why a measure does not resolve."
  @type reason ::
          {:unit, Unit.code(), Unit.reason()}
          | {:quantity, t(), Unit.code()}
          | {:unknown_quantity, term()}

  @base %{
    duration: "s",
    information: "By",
    data_rate: "By/s",
    frequency: "Hz",
    ratio: "1",
    count: "1",
    temperature: "Cel",
    length: "m",
    speed: "m/s",
    power: "W",
    energy: "J",
    pressure: "Pa"
  }

  @all [
    :duration,
    :information,
    :data_rate,
    :frequency,
    :ratio,
    :count,
    :temperature,
    :length,
    :speed,
    :power,
    :energy,
    :pressure
  ]

  @dimensionless [:ratio, :count]

  @decimal ~w(By kBy MBy GBy)
  @binary ~w(By KiBy MiBy GiBy)
  @bits ~w(bit kbit Mbit Gbit)

  @numeric [Scale.Linear, Scale.Power, Scale.Radial]
  @logarithmic [Scale.Log, Scale.Symlog]

  @doc "The fixed list of quantities (spec/05 §4.2)."
  @spec all() :: [t(), ...]
  def all, do: @all

  @doc "A quantity's base unit, the unit its values are in when no unit is given."
  @spec base_unit(t()) :: Unit.code()
  def base_unit(quantity), do: Map.fetch!(@base, quantity)

  @doc """
  The display family a unit of the quantity scales in, smallest first; `[]` for a
  quantity displayed in its own unit (spec/05 §4.2). The unit picks among a quantity's
  families: bits, binary prefixes, hertz, watt-hours.

  ## Examples

      iex> Visualize.Quantity.family(:information, "MiBy")
      ["By", "KiBy", "MiBy", "GiBy"]

  """
  @spec family(t(), Unit.code() | nil) :: [Unit.code()]
  def family(quantity, nil), do: family(quantity, base_unit(quantity))
  def family(:duration, _unit), do: ~w(ns us ms s min h d)
  def family(:information, unit), do: information(unit)
  def family(:data_rate, unit), do: Enum.map(information(unit), &(&1 <> "/s"))

  def family(:frequency, unit),
    do: if(atom?(unit, "Hz"), do: ~w(Hz kHz MHz GHz), else: ~w(/h /min /s))

  def family(:length, _unit), do: ~w(mm m km)
  def family(:power, _unit), do: ~w(W kW MW GW)

  def family(:energy, unit),
    do: if(atom?(unit, "h"), do: ~w(W.h kW.h MW.h GW.h), else: ~w(J kJ MJ GJ))

  def family(:pressure, _unit), do: ~w(Pa kPa MPa)
  def family(quantity, _unit) when quantity in @all, do: []

  @doc """
  The quantity a code's dimension implies, or `nil` when none of the list has it. A
  dimensionless code holding `%` is a `:ratio`, any other a `:count`.

  ## Examples

      iex> Visualize.Quantity.of_unit("kW.h")
      :energy

      iex> Visualize.Quantity.of_unit("{request}")
      :count

  """
  @spec of_unit(Unit.code()) :: t() | nil
  def of_unit(unit) do
    case Unit.dimension(unit) do
      dims when dims == %{} ->
        if atom?(unit, "%"), do: :ratio, else: :count

      dims ->
        Enum.find(@all -- @dimensionless, &(Unit.dimension(base_unit(&1)) == dims))
    end
  end

  @doc """
  A measure completed and checked (spec/05 §4.2): a unit alone implies its quantity, a
  quantity alone means its base unit, and a unit whose dimension is not its quantity's is
  refused. A `:ratio` or a `:count` takes any dimensionless unit.

  ## Examples

      iex> Visualize.Quantity.resolve(%{quantity: :duration})
      {:ok, %{unit: "s", quantity: :duration}}

      iex> Visualize.Quantity.resolve(%{unit: "By", quantity: :duration})
      {:error, {:quantity, :duration, "By"}}

  """
  @spec resolve(measure()) ::
          {:ok, %{unit: Unit.code() | nil, quantity: t() | nil}} | {:error, reason()}
  def resolve(measure) when is_map(measure) do
    unit = Map.get(measure, :unit)
    quantity = Map.get(measure, :quantity)

    with :ok <- check_unit(unit),
         :ok <- check_quantity(quantity) do
      case {unit, quantity} do
        {nil, nil} -> {:ok, %{unit: nil, quantity: nil}}
        {unit, nil} -> {:ok, %{unit: unit, quantity: of_unit(unit)}}
        {nil, quantity} -> {:ok, %{unit: base_unit(quantity), quantity: quantity}}
        {unit, quantity} -> pair(unit, quantity)
      end
    end
  end

  @doc """
  The family member that fits a domain in a measure (spec/05 §4.3): the largest in which
  the domain's magnitude is at least 1, else the smallest. A measure with no family, a
  unit without a factor (`Cel`) or a zero magnitude keeps its unit; no unit is `nil`.
  """
  @spec display_unit([term()], measure()) :: Unit.code() | nil
  def display_unit(domain, measure) do
    %{unit: unit, quantity: quantity} = resolve!(measure)
    magnitude = magnitude(domain)

    cond do
      unit == nil or quantity == nil or magnitude == 0 or Unit.factor(unit) == nil -> unit
      family(quantity, unit) == [] -> unit
      true -> fit(family(quantity, unit), magnitude, unit)
    end
  end

  @doc """
  The tick formatter of a realised scale in a measure (spec/05 §4.3): each tick scaled
  into the display unit, written by `Visualize.Format.Auto`'s notation of the scaled
  domain, then followed by the unit's symbol. A log or symlog scale gives each tick its
  own display unit; any other scale but the numeric ones is
  `Visualize.Format.Auto.formatter/2`, the measure unused. Raises `ArgumentError` for a
  measure `resolve/1` refuses.

  ## Options

  - `:count` - the tick count the axis asks for (default `10`)
  - `:locale` - default `"en"`

  """
  @spec formatter(struct(), measure(), keyword()) :: (term() -> String.t()) | nil
  def formatter(scale, measure, opts \\ [])

  def formatter(%struct{domain: domain} = scale, measure, opts) when struct in @numeric do
    case resolve!(measure) do
      %{unit: nil} ->
        Format.Auto.formatter(scale, opts)

      %{unit: unit, quantity: quantity} = resolved ->
        display = display_unit(domain, resolved)
        scaled = for d <- domain, is_number(d), do: scale(d, unit, display)
        number = Format.Auto.number(notation(quantity, scaled, opts), opts)
        suffix = suffix(display)

        fn
          value when is_number(value) -> number.(scale(value, unit, display)) <> suffix
          value -> to_string(value)
        end
    end
  end

  def formatter(%struct{} = scale, measure, opts) when struct in @logarithmic do
    case resolve!(measure) do
      %{unit: nil} ->
        Format.Auto.formatter(scale, opts)

      %{unit: unit, quantity: quantity} ->
        si = Format.Auto.number(:si, Keyword.take(opts, [:locale]))
        decades = decades(quantity, unit)

        fn
          value when is_number(value) ->
            display =
              if value == 0 or decades == [], do: unit, else: fit(decades, abs(value), unit)

            si.(scale(value, unit, display)) <> suffix(display)

          value ->
            to_string(value)
        end
    end
  end

  def formatter(scale, measure, opts) do
    resolve!(measure)
    Format.Auto.formatter(scale, opts)
  end

  @doc """
  What follows a number written in a unit (spec/05 §4.3): its symbol after a space, `%`
  and a symbol beginning with `/` directly, and nothing for an empty symbol or no unit.

  ## Examples

      iex> Visualize.Quantity.suffix("Cel")
      " °C"

      iex> Visualize.Quantity.suffix("{request}/s")
      "/s"

  """
  @spec suffix(Unit.code() | nil) :: String.t()
  def suffix(nil), do: ""

  def suffix(unit) do
    case Unit.symbol(unit) do
      "" -> ""
      "%" -> "%"
      "/" <> _ = symbol -> symbol
      symbol -> " " <> symbol
    end
  end

  @doc """
  The label rule (spec/05 §4.3): **the unit, else the quantity, else nothing** — the
  unit's symbol with its annotations written when it is not empty, else the quantity's
  name with spaces for underscores, else `nil`. Raises `ArgumentError` for a measure
  `resolve/1` refuses.

  ## Examples

      iex> Visualize.Quantity.label(%{unit: "ms"})
      "ms"

      iex> Visualize.Quantity.label(%{quantity: :count})
      "count"

      iex> Visualize.Quantity.label(%{})
      nil

  """
  @spec label(measure()) :: String.t() | nil
  def label(measure) do
    %{unit: unit, quantity: quantity} = resolve!(measure)
    symbol = if unit, do: Unit.symbol(unit, annotations: true), else: ""

    cond do
      symbol != "" -> symbol
      quantity -> quantity |> Atom.to_string() |> String.replace("_", " ")
      true -> nil
    end
  end

  # -- resolving ------------------------------------------------------------------------

  defp check_unit(nil), do: :ok

  defp check_unit(unit) when is_binary(unit) do
    case Unit.parse(unit) do
      {:ok, _components} -> :ok
      {:error, reason} -> {:error, {:unit, unit, reason}}
    end
  end

  defp check_unit(unit), do: {:error, {:unit, unit, {:syntax, inspect(unit)}}}

  defp check_quantity(nil), do: :ok
  defp check_quantity(quantity) when quantity in @all, do: :ok
  defp check_quantity(quantity), do: {:error, {:unknown_quantity, quantity}}

  defp pair(unit, quantity) do
    fits? =
      if quantity in @dimensionless,
        do: Unit.dimension(unit) == %{},
        else: Unit.dimension(unit) == Unit.dimension(base_unit(quantity))

    if fits?,
      do: {:ok, %{unit: unit, quantity: quantity}},
      else: {:error, {:quantity, quantity, unit}}
  end

  defp resolve!(measure) do
    case resolve(measure) do
      {:ok, resolved} ->
        resolved

      {:error, reason} ->
        raise ArgumentError, "not a measure: #{inspect(measure)} (#{inspect(reason)})"
    end
  end

  # -- scaling --------------------------------------------------------------------------

  defp information(unit) do
    cond do
      atom?(unit, "bit") -> @bits
      binary_prefix?(unit) -> @binary
      true -> @decimal
    end
  end

  defp atom?(unit, atom), do: unit |> components() |> Enum.any?(&(&1.atom == atom))

  defp binary_prefix?(unit),
    do: unit |> components() |> Enum.any?(&(&1.prefix in ["Ki", "Mi", "Gi"]))

  defp components(unit) do
    {:ok, components} = Unit.parse(unit)
    components
  end

  defp magnitude(domain),
    do: domain |> Enum.filter(&is_number/1) |> Enum.map(&abs/1) |> Enum.max(fn -> 0 end)

  # The largest member the magnitude fills to at least 1, else the smallest.
  defp fit([smallest | _] = family, magnitude, unit) do
    family
    |> Enum.filter(&(Unit.convert(magnitude, unit, &1) >= 1))
    |> List.last(smallest)
  end

  # The family members a power of ten from the unit, which a log axis's ticks — powers
  # of ten in the unit — land on as round numbers: `ms` to `s`, never `s` to `min`.
  defp decades(nil, _unit), do: []

  defp decades(quantity, unit) do
    case Unit.factor(unit) do
      nil ->
        []

      {n, d} ->
        Enum.filter(family(quantity, unit), fn member ->
          {mn, md} = Unit.factor(member)
          power_of_ten?(mn * d, md * n)
        end)
    end
  end

  defp power_of_ten?(n, d) do
    g = Integer.gcd(n, d)
    {n, d} = {div(n, g), div(d, g)}
    (n == 1 and ten?(d)) or (d == 1 and ten?(n))
  end

  defp ten?(1), do: true
  defp ten?(n), do: rem(n, 10) == 0 and ten?(div(n, 10))

  defp scale(value, unit, unit), do: value
  defp scale(value, unit, display), do: Unit.convert(value, unit, display)

  # A count is SI from a thousand, one prefix for the axis; everything else as the
  # magnitude of its scaled domain calls for.
  defp notation(:count, domain, opts) do
    case Format.Auto.notation(domain, Keyword.take(opts, [:locale])) do
      :grouped -> {:si, 3}
      notation -> notation
    end
  end

  defp notation(_quantity, domain, opts),
    do: Format.Auto.notation(domain, Keyword.take(opts, [:locale]))
end
