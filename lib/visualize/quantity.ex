defmodule Visualize.Quantity do
  @moduledoc """
  A fixed list of quantities, each with its facts — a base unit, a kind, bounds,
  additivity and display families by unit system — and the display scaling they choose
  (spec/05 §4.2–4.3, D-138, D-155).

  A quantity is what a unit measures. A unit (a UCUM code, `Visualize.Unit`) and a
  quantity together are a *measure*, `%{unit: code, quantity: quantity}`, the two facts a
  field description carries. **They are facts about the data, not knobs**: a measure does
  not change a value, it says what the value already is, so a display can choose how to
  show it — 0–1,500 `ms` as 0–1.5 `s`, 2,500,000 `By` as 2.5 `MB`, 80 `kg` in `lb` for a
  viewer on the US system.

  The list is fixed and grows by proposal: `duration`, `information`, `data_rate`,
  `frequency`, `ratio`, `count`, `temperature`, `length`, `speed`, `power`, `energy`,
  `pressure`, `area`, `volume`, `mass`, `pace`, `angle`, `currency`,
  `electric_potential`, `electric_current`, `electric_charge`, `illuminance`,
  `sound_level`, `mass_concentration` and `amount_concentration`. spec/05 §4.2 tables
  each one's facts and families.

  - **Kind** is `:linear`, `:affine` (a temperature), `:logarithmic` (a sound level) or
    `:cyclic` (an angle, whose mean is circular).
  - **Bounds** are a display hint, never validation: a difference is legitimately
    negative, so a value outside them is never refused.
  - **Additivity** depends on the aggregation: `additivity/2` refines the quantity's
    defaults across series and over time by the field's metric kind (`:gauge`,
    `:counter`, `:rate`).
  - **Unit systems** are `:metric`, `:us`, `:uk` and `:as_posted`; a system picks the
    family a value is shown in and never touches the data.

  Information is **decimal by default** — UCUM's `kBy` and `Telemetry.Metrics`'
  `:kilobyte` are 1,000 bytes — and a unit written with a binary prefix (`MiBy`) or in
  `bit` scales in its own family: the data picks it, no setting does.

  Tick formats are built on `Visualize.Format.Auto` (spec/05 §3), and every function that
  formats takes its `locale:`.

  ## Examples

      iex> Visualize.Quantity.display_unit([0, 1500], %{unit: "ms"})
      "s"

      iex> Visualize.Quantity.display_unit([0, 80], %{unit: "kg"}, system: :us)
      "[lb_av]"

      iex> scale = Visualize.Scale.linear() |> Visualize.Scale.domain([0, 1500])
      iex> Visualize.Quantity.formatter(scale, %{unit: "ms"}).(1500)
      "1.5 s"

      iex> Visualize.Quantity.additivity(:data_rate)
      %{across: true, over_time: false}

      iex> Visualize.Quantity.label(%{unit: "{request}"})
      "request"

  """

  alias Visualize.{Format, Scale, Unit}
  alias Visualize.Quantity.Facts

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
          | :area
          | :volume
          | :mass
          | :pace
          | :angle
          | :currency
          | :electric_potential
          | :electric_current
          | :electric_charge
          | :illuminance
          | :sound_level
          | :mass_concentration
          | :amount_concentration

  @typedoc "How a quantity's values combine (spec/05 §4.2)."
  @type kind :: :linear | :affine | :logarithmic | :cyclic

  @typedoc "A unit system: a display preference, never applied to the data."
  @type system :: :metric | :us | :uk | :as_posted

  @typedoc "How a field's values were measured, which refines its quantity's additivity."
  @type metric_kind :: :gauge | :counter | :rate

  @typedoc "A unit and a quantity, either or both; the two facts a field description carries."
  @type measure :: %{optional(:unit) => Unit.code() | nil, optional(:quantity) => t() | nil}

  @typedoc "Why a measure does not resolve."
  @type reason ::
          {:unit, Unit.code(), Unit.reason()}
          | {:quantity, t(), Unit.code()}
          | {:unknown_quantity, term()}

  @all Facts.all()
  @systems [:metric, :us, :uk, :as_posted]
  @metric_kinds [:gauge, :counter, :rate]

  @dimensionless [:ratio, :count, :currency]

  @numeric [Scale.Linear, Scale.Power, Scale.Radial]
  @logarithmic [Scale.Log, Scale.Symlog]

  @doc "The fixed list of quantities (spec/05 §4.2)."
  @spec all() :: [t(), ...]
  def all, do: @all

  @doc "The unit systems a display may prefer (spec/05 §4.2), `:as_posted` the default."
  @spec systems() :: [system(), ...]
  def systems, do: @systems

  @doc """
  A quantity's base unit, the unit its values are in when no unit is given; `nil` for a
  `:currency`, whose code the data must say.
  """
  @spec base_unit(t()) :: Unit.code() | nil
  def base_unit(quantity), do: Facts.fetch!(quantity).base

  @doc """
  How a quantity's values combine (spec/05 §4.2): `:linear`, `:affine` (a temperature),
  `:logarithmic` (a sound level) or `:cyclic` (an angle).

  ## Examples

      iex> Visualize.Quantity.kind(:angle)
      :cyclic

  """
  @spec kind(t()) :: kind()
  def kind(quantity), do: Facts.fetch!(quantity).kind

  @doc """
  Where a quantity's values physically lie, in its base unit, `{min | nil, max | nil}`
  (spec/05 §4.2): a **display hint** an axis may anchor at, never validation — a value
  outside them is never refused.

  ## Examples

      iex> Visualize.Quantity.bounds(:duration)
      {0, nil}

  """
  @spec bounds(t()) :: {number() | nil, number() | nil}
  def bounds(quantity), do: Facts.fetch!(quantity).bounds

  @doc """
  A quantity's bounds in a unit of it: the base's, converted. A unit without a factor
  (`Cel`) takes the base's bounds as they are.

  ## Examples

      iex> Visualize.Quantity.bounds(:ratio, "%")
      {0.0, 100.0}

  """
  @spec bounds(t(), Unit.code()) :: {number() | nil, number() | nil}
  def bounds(quantity, unit) do
    {min, max} = bounds(quantity)
    base = base_unit(quantity)

    if base == nil or base == unit or Unit.factor(unit) == nil,
      do: {min, max},
      else: {bound(min, base, unit), bound(max, base, unit)}
  end

  @doc """
  Whether a sum of the quantity's values means anything (spec/05 §4.2, D-155):
  `%{across: boolean, over_time: boolean}` — summing several series at one instant, and
  summing one series over time. The quantity's physical defaults are refined by the
  field's metric kind: a `:gauge` and a `:rate` never add over time, and a `:counter`'s
  increments add over time when the quantity adds across. No quantity (a plain number)
  defaults to both.

  ## Examples

      iex> Visualize.Quantity.additivity(:count, :gauge)
      %{across: true, over_time: false}

      iex> Visualize.Quantity.additivity(:temperature, :counter)
      %{across: false, over_time: false}

  """
  @spec additivity(t() | nil, metric_kind() | nil) :: %{across: boolean(), over_time: boolean()}
  def additivity(quantity, metric_kind \\ nil) when metric_kind in [nil | @metric_kinds] do
    defaults =
      case quantity do
        nil -> %{across: true, over_time: true}
        quantity -> Map.take(Facts.fetch!(quantity), [:across, :over_time])
      end

    case metric_kind do
      nil -> defaults
      :counter -> %{defaults | over_time: defaults.across}
      _gauge_or_rate -> %{defaults | over_time: false}
    end
  end

  @doc """
  The display family a unit of the quantity belongs to, smallest first; `[]` for a unit
  of no family's shape (spec/05 §4.2). Within the unit's convention (`family/3`), a unit
  belongs to the first family holding a member of its shape — its atoms and exponents,
  prefixes aside and a binary prefix kept apart — so the unit picks among a quantity's
  families: bits, binary prefixes, hertz, watt-hours, US lengths. No unit means the base
  unit.

  ## Examples

      iex> Visualize.Quantity.family(:information, "MiBy")
      ["By", "KiBy", "MiBy", "GiBy", "TiBy"]

      iex> Visualize.Quantity.family(:length, "[ft_i]")
      ["[in_i]", "[ft_i]", "[mi_i]"]

  """
  @spec family(t(), Unit.code() | nil) :: [Unit.code()]
  def family(quantity, unit), do: family(quantity, unit, :as_posted)

  @doc """
  The display family a system shows a unit of the quantity in (spec/05 §4.2, D-158): the
  family the unit's convention names for `:metric`, `:us` or `:uk` when it names one,
  else the unit's own (`family/2`), which is what `:as_posted` always is.

  A quantity read in several conventions — a pressure is gauge, barometric or clinical —
  picks the unit's by its exact code first, then by its shape, else the first, so a
  system chooses within a convention and never across: a barometric `hPa` is shown in
  inches of mercury under `:us`, and a blood pressure in `mm[Hg]` stays in it under every
  system.

  ## Examples

      iex> Visualize.Quantity.family(:mass, "kg", :uk)
      ["[oz_av]", "[lb_av]", "[stone_av]"]

      iex> Visualize.Quantity.family(:duration, "ms", :us)
      ["ns", "us", "ms", "s", "min", "h", "d"]

      iex> Visualize.Quantity.family(:pressure, "hPa", :us)
      ["[in_i'Hg]"]

  """
  @spec family(t(), Unit.code() | nil, system()) :: [Unit.code()]
  def family(quantity, nil, system) do
    case base_unit(quantity) do
      nil -> []
      base -> family(quantity, base, system)
    end
  end

  def family(quantity, unit, system) when system in @systems do
    families = convention(quantity, unit)

    case List.keyfind(families, system, 0) do
      {^system, ladder} -> ladder
      nil -> own_family(families, unit)
    end
  end

  @doc """
  The quantity a code's dimension implies, or `nil` when none of the list has it. A
  dimensionless code holding `%` is a `:ratio`, any other a `:count`, and a code of one
  currency alone (`{iso4217:USD}`) a `:currency`.

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
        if Unit.currency(unit),
          do: :currency,
          else: Enum.find(@all -- @dimensionless, &(Unit.dimension(base_unit(&1)) == dims))
    end
  end

  @doc """
  A measure completed and checked (spec/05 §4.2): a unit alone implies its quantity, a
  quantity alone means its base unit, and a unit whose dimension is not its quantity's is
  refused. A `:ratio` or a `:count` takes any dimensionless unit, and a `:currency` a
  code of one currency alone.

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

  @doc "As `display_unit/3` with `[]` options."
  @spec display_unit([term()], measure()) :: Unit.code() | nil
  def display_unit(domain, measure), do: display_unit(domain, measure, [])

  @doc """
  The member of the system's family that fits a domain in a measure (spec/05 §4.3): the
  largest in which the domain's magnitude is at least 1, else the smallest; a family of
  one member is that member. A measure with no family under the system, or a unit
  without a factor (`Cel`) in its own family, keeps its unit, and so does a zero
  magnitude when the unit is in the family — otherwise the member nearest it is taken.
  No unit is `nil`.

  ## Options

  - `:system` - `:metric`, `:us`, `:uk` or `:as_posted` (default)

  """
  @spec display_unit([term()], measure(), keyword()) :: Unit.code() | nil
  def display_unit(domain, measure, opts) do
    system = Keyword.get(opts, :system, :as_posted)
    %{unit: unit, quantity: quantity} = resolve!(measure)

    if unit == nil or quantity == nil,
      do: unit,
      else: choose(family(quantity, unit, system), unit, magnitude(domain))
  end

  @doc """
  The tick formatter of a realized scale in a measure (spec/05 §4.3): each tick scaled
  into the display unit, written by `Visualize.Format.Auto`'s notation of the scaled
  domain, then followed by the unit's symbol. A log or symlog scale gives each tick its
  own display unit; any other scale but the numeric ones is
  `Visualize.Format.Auto.formatter/2`, the measure unused. A value `ticks/3` placed for
  the same count and system is labeled with the round number it came from, so the round
  trip through the data's unit never shows. Raises `ArgumentError` for a measure
  `resolve/1` refuses.

  ## Options

  - `:count` - the tick count the axis asks for (default `10`)
  - `:locale` - default `"en"`
  - `:system` - the unit system, as `display_unit/3` (default `:as_posted`)

  """
  @spec formatter(struct(), measure(), keyword()) :: (term() -> String.t()) | nil
  def formatter(scale, measure, opts \\ [])

  def formatter(%struct{domain: domain} = scale, measure, opts) when struct in @numeric do
    case resolve!(measure) do
      %{unit: nil} ->
        Format.Auto.formatter(scale, opts)

      %{unit: unit, quantity: :currency} ->
        scaled = for d <- domain, is_number(d), do: d
        money(Format.Auto.number(notation(:count, scaled, opts), opts), unit, opts)

      %{unit: unit, quantity: quantity} = resolved ->
        display = display_unit(domain, resolved, Keyword.take(opts, [:system]))
        scaled = for d <- domain, is_number(d), do: scale(d, unit, display)
        number = Format.Auto.number(notation(quantity, scaled, opts), opts)
        suffix = suffix(display)
        # The values `ticks/3` placed, each labeled with the round number it came from.
        rounds = Map.new(round_ticks(scale, unit, display, Keyword.get(opts, :count, 10)))

        fn
          value when is_number(value) ->
            number.(Map.get_lazy(rounds, value, fn -> scale(value, unit, display) end)) <>
              suffix

          value ->
            to_string(value)
        end
    end
  end

  def formatter(%struct{} = scale, measure, opts) when struct in @logarithmic do
    case resolve!(measure) do
      %{unit: nil} ->
        Format.Auto.formatter(scale, opts)

      %{unit: unit, quantity: :currency} ->
        money(Format.Auto.number(:si, Keyword.take(opts, [:locale])), unit, opts)

      %{unit: posted, quantity: quantity} = resolved ->
        si = Format.Auto.number(:si, Keyword.take(opts, [:locale]))
        unit = log_unit(scale, resolved, Keyword.get(opts, :system, :as_posted))
        decades = decades(quantity, unit)

        fn
          value when is_number(value) ->
            display =
              if value == 0 or decades == [],
                do: unit,
                else: fit(decades, abs(scale(value, posted, unit)), unit)

            si.(scale(value, posted, display)) <> suffix(display)

          value ->
            to_string(value)
        end
    end
  end

  def formatter(scale, measure, opts) do
    resolve!(measure)
    Format.Auto.formatter(scale, opts)
  end

  @doc "As `ticks/3` with `[]` options."
  @spec ticks(struct(), measure()) :: [float()] | nil
  def ticks(scale, measure), do: ticks(scale, measure, [])

  @doc """
  The tick values of a realized scale in a measure when its display unit is not its unit
  (spec/05 §4.3, D-156): round numbers in the display unit — `Visualize.Scale.ticks/2` of
  the domain converted into it — each converted back into the data's unit to be placed.
  `nil` when the display unit is the unit, for a measure with no unit and for a
  `:currency`, and on any scale but `Linear`, `Power` and `Radial`: the scale's own ticks
  are the axis's. `formatter/3` of the same count and system labels each value with its
  round number. Raises `ArgumentError` for a measure `resolve/1` refuses.

  ## Options

  - `:count` - the tick count the axis asks for (default `10`)
  - `:system` - the unit system, as `display_unit/3` (default `:as_posted`)

  ## Examples

      iex> scale = Visualize.Scale.linear() |> Visualize.Scale.domain([0, 100])
      iex> ticks = Visualize.Quantity.ticks(scale, %{unit: "s"}, count: 5)
      [0.0, 30.0, 60.0, 90.0]
      iex> Enum.map(ticks, Visualize.Quantity.formatter(scale, %{unit: "s"}, count: 5))
      ["0 min", "0.5 min", "1 min", "1.5 min"]

      iex> scale = Visualize.Scale.linear() |> Visualize.Scale.domain([0, 900])
      iex> Visualize.Quantity.ticks(scale, %{unit: "ms"})
      nil

  """
  @spec ticks(struct(), measure(), keyword()) :: [float()] | nil
  def ticks(%struct{domain: domain} = scale, measure, opts) when struct in @numeric do
    case resolve!(measure) do
      %{unit: nil} ->
        nil

      %{quantity: :currency} ->
        nil

      %{unit: unit} = resolved ->
        display = display_unit(domain, resolved, Keyword.take(opts, [:system]))

        case round_ticks(scale, unit, display, Keyword.get(opts, :count, 10)) do
          [] -> nil
          pairs -> Enum.map(pairs, &elem(&1, 0))
        end
    end
  end

  def ticks(_scale, measure, _opts) do
    resolve!(measure)
    nil
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
      "°" -> "°"
      "/" <> _ = symbol -> symbol
      symbol -> " " <> symbol
    end
  end

  @doc "As `format/3` with `[]` options."
  @spec format(number(), measure()) :: String.t()
  def format(value, measure), do: format(value, measure, [])

  @doc """
  One value of a measure for a label or a tooltip, not an axis (spec/05 §4.3): a
  `:duration` in the compound form (`1h 24m`, `840ms`), a `:currency` as money in its
  code (`$1,240.00`, `¥1,240`), a `:count` rounded and grouped (`1,240`), and anything
  else to `precision` decimals, then the unit's suffix (`91.40%`, `350°`, `20.50 kg`).
  Raises `ArgumentError` for a measure `resolve/1` refuses.

  ## Options

  - `:precision` - decimals (default `2`); a currency's are its minor units
  - `:locale` - default `"en"`
  - `:system` - the unit system (default `:as_posted`); under another, the value is
    written in its `display_unit/3`

  ## Examples

      iex> Visualize.Quantity.format(5040, %{unit: "s"})
      "1h 24m"

      iex> Visualize.Quantity.format(1240, %{unit: "{iso4217:USD}"})
      "$1,240.00"

      iex> Visualize.Quantity.format(350, %{unit: "deg"}, precision: 0)
      "350°"

      iex> Visualize.Quantity.format(80, %{unit: "kg"}, system: :us)
      "176.37 lb"

  """
  @spec format(number(), measure(), keyword()) :: String.t()
  def format(value, measure, opts) when is_number(value) do
    precision = Keyword.get(opts, :precision, 2)
    locale = Format.Auto.locale!(opts)
    resolved = resolve!(measure)
    %{unit: unit, quantity: quantity} = in_system(value, resolved, opts)
    value = scale(value, resolved.unit, unit)

    case quantity do
      :duration ->
        Format.duration(scale(value, unit, "s"),
          style: :compound,
          precision: precision,
          locale: locale_name(opts)
        )

      :currency ->
        Format.currency(value, code: Unit.currency(unit), locale: locale_name(opts))

      :count ->
        Format.number(round(value), separator: locale.group)

      _other ->
        fixed(value, precision, locale) <> suffix(unit)
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

  # -- one value ------------------------------------------------------------------------

  # The measure a value is written in under a system: its display unit there.
  defp in_system(_value, %{unit: nil} = resolved, _opts), do: resolved
  defp in_system(_value, %{quantity: nil} = resolved, _opts), do: resolved

  defp in_system(value, resolved, opts) do
    case Keyword.get(opts, :system, :as_posted) do
      :as_posted -> resolved
      system -> %{resolved | unit: display_unit([value], resolved, system: system)}
    end
  end

  defp locale_name(opts), do: Keyword.get(opts, :locale, "en")

  defp fixed(value, precision, %{decimal: decimal}) do
    fixed = :erlang.float_to_binary(value * 1.0, decimals: precision)
    if decimal == ".", do: fixed, else: String.replace(fixed, ".", decimal)
  end

  # Money on an axis: the locale's symbol before the number and after its sign, or the
  # code after the number for a code the locale has no symbol for.
  defp money(number, unit, opts) do
    code = Unit.currency(unit)
    symbol = Map.get(Format.Auto.locale!(opts).currency, code)

    fn
      value when is_number(value) ->
        case {number.(value), symbol} do
          {"-" <> magnitude, symbol} when symbol != nil -> "-" <> symbol <> magnitude
          {label, nil} -> label <> " " <> code
          {label, symbol} -> symbol <> label
        end

      value ->
        to_string(value)
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
      case quantity do
        :currency -> Unit.currency(unit) != nil
        quantity when quantity in @dimensionless -> Unit.dimension(unit) == %{}
        quantity -> Unit.dimension(unit) == Unit.dimension(base_unit(quantity))
      end

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

  # -- ticks ----------------------------------------------------------------------------

  # The round ticks of the domain in the display unit, each as `{placed, round}`: the
  # value in the data's unit it is placed at and the display-unit number it labels. None
  # when the display unit is the unit (D-156).
  defp round_ticks(_scale, unit, unit, _count), do: []

  defp round_ticks(%{domain: domain} = scale, unit, display, count) do
    case for(d <- domain, is_number(d), do: Unit.convert(d, unit, display)) do
      [_, _ | _] = converted ->
        for round <- Scale.ticks(%{scale | domain: converted}, count),
            do: {Unit.convert(round, display, unit), round}

      _fewer ->
        []
    end
  end

  # -- scaling --------------------------------------------------------------------------

  # The families of the unit's convention (spec/05 §4.2, D-158): the first convention
  # claiming its exact code, else the first claiming a code of its shape, else the first.
  # Shape alone cannot choose, since `hPa` and `kPa` are one shape; a quantity of one
  # convention has no choice to make.
  defp convention(quantity, unit) do
    case Facts.fetch!(quantity).conventions do
      [{_name, only}] ->
        Keyword.fetch!(only, :families)

      [{_name, first} | _] = conventions ->
        claims = for {_name, convention} <- conventions, do: {claimed(convention), convention}
        shape = shape(unit)

        {_claimed, convention} =
          Enum.find(claims, &(unit in elem(&1, 0))) ||
            Enum.find(claims, {[], first}, fn {claimed, _} ->
              Enum.any?(claimed, &(shape(&1) == shape))
            end)

        Keyword.fetch!(convention, :families)
    end
  end

  # Every code a convention claims: its ladders' members and the codes it holds without
  # a ladder for them.
  defp claimed(convention) do
    Enum.flat_map(Keyword.fetch!(convention, :families), &elem(&1, 1)) ++
      Keyword.fetch!(convention, :also)
  end

  # The first family holding a member of the unit's shape, else none.
  defp own_family(families, unit) do
    shape = shape(unit)

    Enum.find_value(families, [], fn {_system, ladder} ->
      if Enum.any?(ladder, &(shape(&1) == shape)), do: ladder
    end)
  end

  defp in_family?(family, unit), do: Enum.any?(family, &(shape(&1) == shape(unit)))

  # A unit's atoms and exponents, prefixes aside but a binary one kept apart, annotations
  # and integer factors aside: `kBy` and `By` are one shape, `MiBy` another.
  defp shape(unit) do
    unit
    |> components()
    |> Enum.filter(& &1.atom)
    |> Enum.map(&{&1.atom, &1.exponent, &1.prefix in ["Ki", "Mi", "Gi", "Ti"]})
    |> Enum.sort()
  end

  defp atom?(unit, atom), do: unit |> components() |> Enum.any?(&(&1.atom == atom))

  defp bound(nil, _base, _unit), do: nil
  defp bound(value, base, unit), do: Unit.convert(value, base, unit)

  # The member of a family a domain's magnitude chooses (spec/05 §4.3).
  defp choose([], unit, _magnitude), do: unit
  defp choose([member], _unit, _magnitude), do: member

  defp choose(family, unit, magnitude) do
    cond do
      Unit.factor(unit) == nil -> unit
      magnitude != 0 -> fit(family, magnitude, unit)
      in_family?(family, unit) -> unit
      true -> Enum.min_by(family, &abs(:math.log10(Unit.convert(1, unit, &1))))
    end
  end

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
      {n, d} ->
        for member <- family(quantity, unit),
            {mn, md} <- [Unit.factor(member)],
            power_of_ten?(mn * d, md * n),
            do: member

      _affine_or_pi ->
        []
    end
  end

  # The unit a log axis's ticks are written from: the data's, unless the system shows
  # the quantity in another family, then the display unit of the domain there.
  defp log_unit(_scale, %{unit: unit}, :as_posted), do: unit
  defp log_unit(_scale, %{quantity: nil, unit: unit}, _system), do: unit

  defp log_unit(%{domain: domain}, %{unit: unit, quantity: quantity} = resolved, system) do
    if in_family?(family(quantity, unit, system), unit),
      do: unit,
      else: display_unit(domain, resolved, system: system)
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
