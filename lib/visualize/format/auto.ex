defmodule Visualize.Format.Auto do
  @moduledoc """
  Tick formats derived from what a realised scale already knows: its domain and the tick
  count (spec/05 §3.1, D-134).

  A time domain is formatted by its span and the interval its ticks use — clock times
  within a day, days within a week, dates within a season, months beyond — and a numeric
  one by its magnitude — plain below 1,000, grouped from 1,000, one SI prefix from a
  million. The declarative layer's axis uses these wherever a design gives no `format`
  (spec/14 §4.4).

  Every function takes `locale:`, `"en"` by default and the only locale that ships; any
  other raises `ArgumentError`.

  ## Examples

      iex> Visualize.Format.Auto.notation([0, 90_000])
      :grouped

      iex> Visualize.Format.Auto.number({:si, 6}).(2_500_000)
      "2.5M"

      iex> Visualize.Format.Auto.time_format([~U[2024-03-01 00:00:00Z], ~U[2024-03-01 02:00:00Z]])
      "%H:%M"

  """

  alias Visualize.{Axis, Format, Scale}

  @typedoc "How a numeric domain's ticks are written: by magnitude, or `:si` per value."
  @type notation :: :plain | :grouped | {:si, 6..24} | :si

  @typedoc "A time value a time scale's domain holds."
  @type time :: DateTime.t() | NaiveDateTime.t() | Date.t()

  @day 86_400

  # Per locale: the separators and the time formats of spec/05 §3.1, by row of its table.
  @locales %{
    "en" => %{
      group: ",",
      decimal: ".",
      time: %{
        seconds: "%H:%M:%S",
        clock: "%H:%M",
        weekday_clock: "%a %H:%M",
        weekday: "%a %d",
        date_clock: "%b %d %H:%M",
        date: "%b %d",
        month: "%b %Y",
        year: "%Y"
      }
    }
  }

  # The SI prefixes from a thousand up, largest first: an axis prefix is `M` or above, a
  # value's own from `k`.
  @prefixes [
    {24, "Y"},
    {21, "Z"},
    {18, "E"},
    {15, "P"},
    {12, "T"},
    {9, "G"},
    {6, "M"},
    {3, "k"}
  ]

  @doc """
  The derived formatter of a realised scale, or `nil` when the default label serves (a
  band, ordinal or discretising scale).

  ## Options

  - `:count` - the tick count the axis asks for (default `10`), which chooses a time
    scale's interval
  - `:locale` - default `"en"`

  """
  @spec formatter(struct(), keyword()) :: (term() -> String.t()) | nil
  def formatter(scale, opts \\ [])

  def formatter(%Scale.Time{domain: domain} = scale, opts) do
    spec = time_format(domain, opts)

    fn
      %struct{} = value when struct in [DateTime, NaiveDateTime, Date] ->
        Format.time(Scale.Time.local(scale, value), spec)

      value ->
        to_string(value)
    end
  end

  def formatter(%struct{domain: domain}, opts)
      when struct in [Scale.Linear, Scale.Power, Scale.Radial],
      do: domain |> notation(opts) |> number(opts)

  def formatter(%struct{domain: domain}, opts) when struct in [Scale.Log, Scale.Symlog] do
    case notation(domain, opts) do
      {:si, _exponent} -> number(:si, opts)
      notation -> number(notation, opts)
    end
  end

  def formatter(_scale, opts) do
    locale!(opts)
    nil
  end

  @doc """
  The `Visualize.Format.time/2` specifier for a time domain: by its span, and by whether
  the interval `count` ticks use over it is under a day (spec/05 §3.1).

  ## Options

  - `:count` - the tick count (default `10`)
  - `:locale` - default `"en"`

  """
  @spec time_format([time()], keyword()) :: String.t()
  def time_format([t0, t1], opts \\ []) do
    formats = locale!(opts).time
    span = abs(seconds(t1) - seconds(t0))
    {unit, _n} = Scale.Time.interval(span, Keyword.get(opts, :count, 10))
    sub_day? = unit in [:second, :minute, :hour]

    cond do
      span <= @day and unit == :second -> formats.seconds
      span <= @day -> formats.clock
      span <= 7 * @day and sub_day? -> formats.weekday_clock
      span <= 7 * @day -> formats.weekday
      span <= 92 * @day and sub_day? -> formats.date_clock
      span <= 92 * @day -> formats.date
      unit == :year -> formats.year
      true -> formats.month
    end
  end

  @doc """
  The notation a numeric domain's magnitude — its greatest `|d|` — calls for: `:plain`
  below 1,000, `:grouped` below a million, else `{:si, e}` with `e` the exponent of the
  largest SI prefix not above it (spec/05 §3.1).

  ## Options

  - `:locale` - default `"en"`

  """
  @spec notation([number()], keyword()) :: :plain | :grouped | {:si, 6..24}
  def notation(domain, opts \\ []) do
    locale!(opts)
    magnitude = domain |> Enum.filter(&is_number/1) |> Enum.map(&abs/1) |> Enum.max(fn -> 0 end)

    cond do
      magnitude < 1_000 -> :plain
      magnitude < 1_000_000 -> :grouped
      true -> {:si, magnitude |> prefix() |> elem(0)}
    end
  end

  @doc """
  The formatter of a notation (spec/05 §3.1): `:plain` the default label, `:grouped` it
  grouped in threes, `{:si, e}` every value over `10ᵉ` with that prefix (zero stays `0`),
  `:si` each value with its own prefix from `k` up. A non-number is `to_string/1`.

  ## Options

  - `:locale` - default `"en"`

  """
  @spec number(notation(), keyword()) :: (term() -> String.t())
  def number(notation, opts \\ []) do
    locale = locale!(opts)

    fn
      value when is_number(value) -> write(notation, value, locale)
      value -> to_string(value)
    end
  end

  # -- numbers ----------------------------------------------------------------------------

  defp write(:plain, value, locale), do: value |> Axis.default_label() |> localise(locale)

  defp write(:grouped, value, locale),
    do: value |> Axis.default_label() |> group(locale.group) |> localise(locale)

  defp write({:si, _exponent}, value, _locale) when value == 0, do: "0"

  defp write({:si, exponent}, value, locale) do
    {^exponent, symbol} = List.keyfind(@prefixes, exponent, 0)
    write(:plain, value / :math.pow(10, exponent), locale) <> symbol
  end

  defp write(:si, value, locale) when abs(value) < 1_000, do: write(:plain, value, locale)

  defp write(:si, value, locale) do
    {exponent, _symbol} = prefix(abs(value))
    write({:si, exponent}, value, locale)
  end

  # The largest prefix whose power of ten is at most `magnitude` (at least a thousand).
  defp prefix(magnitude),
    do: Enum.find(@prefixes, fn {exponent, _} -> magnitude >= :math.pow(10, exponent) end)

  # The integer digits of a default label grouped in threes, sign and fraction untouched.
  # The `.` is the default label's point; `localise/2` swaps it afterwards.
  defp group(label, separator) do
    {sign, digits} =
      case label do
        "-" <> rest -> {"-", rest}
        rest -> {"", rest}
      end

    {integer, fraction} =
      case String.split(digits, ".", parts: 2) do
        [integer, fraction] -> {integer, "." <> fraction}
        [integer] -> {integer, ""}
      end

    sign <> thousands(integer, separator) <> fraction
  end

  # ASCII digits in threes from the right: the short head first, then whole threes.
  defp thousands(digits, separator) do
    case rem(byte_size(digits), 3) do
      0 ->
        threes(digits, separator)

      n ->
        head = binary_part(digits, 0, n)
        rest = binary_part(digits, n, byte_size(digits) - n)
        if rest == "", do: head, else: head <> separator <> threes(rest, separator)
    end
  end

  defp threes(<<three::binary-size(3)>>, _separator), do: three

  defp threes(<<three::binary-size(3), rest::binary>>, separator),
    do: three <> separator <> threes(rest, separator)

  defp localise(label, %{decimal: "."}), do: label
  defp localise(label, %{decimal: decimal}), do: String.replace(label, ".", decimal)

  # -- time --------------------------------------------------------------------------------

  defp seconds(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp seconds(%NaiveDateTime{} = ndt), do: NaiveDateTime.diff(ndt, ~N[1970-01-01 00:00:00])
  defp seconds(%Date{} = d), do: Date.diff(d, ~D[1970-01-01]) * @day

  # -- locale ------------------------------------------------------------------------------

  defp locale!(opts) do
    name = Keyword.get(opts, :locale, "en")

    case Map.fetch(@locales, name) do
      {:ok, locale} ->
        locale

      :error ->
        raise ArgumentError,
              "unknown locale #{inspect(name)}: the derived formats ship " <>
                inspect(Map.keys(@locales))
    end
  end
end
