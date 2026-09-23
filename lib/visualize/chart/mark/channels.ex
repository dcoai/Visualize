defmodule Visualize.Chart.Mark.Channels do
  @moduledoc false
  # Channel resolution for a mark (spec/14 §5.2): every channel read from each row and
  # mapped through the scale it names in the frame kind's table, the band-edge rule for
  # `:band` scales, pixels for a channel that names no declared scale.

  alias Visualize.Chart.Frame.Scales
  alias Visualize.Chart.{Style, Var}
  alias Visualize.Data.Table
  alias Visualize.Scale
  alias Visualize.Scale.Band

  # Channels a mark reads raw whatever scale they name: `series` groups the rows and is
  # mapped through the colour scale per series; a rose's `angle` is mapped by the rose.
  @raw_always [:series, :path]

  @typedoc "A row with its channel readings in pixels: `%{datum: row, x: px, ...}`."
  @type pixel_row :: %{required(:datum) => map(), optional(atom()) => term()}

  @doc false
  # One pixel row per datum, in order; a channel the row cannot place is `nil`.
  @spec pixels(map(), [atom()]) :: [pixel_row()]
  def pixels(ctx, raw \\ []) do
    channels = Map.get(ctx.mark, :channels, %{})
    frame = ctx.frame

    offsets = Map.get(ctx.mark, :offset, %{})

    Enum.map(ctx.rows, fn row ->
      Enum.reduce(channels, %{datum: row}, fn {channel, spec}, acc ->
        value = read(spec, row, frame, ctx.mark, channel)

        pixel =
          cond do
            channel in @raw_always or channel in raw ->
              value

            Map.has_key?(offsets, family(channel)) ->
              offset(frame, ctx.mark, channel, value, row, offsets)

            true ->
              map(frame, ctx.mark, channel, value)
          end

        Map.put(acc, channel, pixel)
      end)
    end)
  end

  # A channel's family: the position scale its edges and position read (spec/14 §4.3).
  defp family(channel) when channel in [:x, :x0, :x1], do: :x
  defp family(channel) when channel in [:y, :y0, :y1], do: :y
  defp family(channel), do: channel

  # A band within a band (spec/14 §5.1, D-109): the outer band's start from the family's
  # scale, then the inner band's placement from the offset scale over the offset field —
  # start, end or centre by the channel. Anything not a band, or a datum either scale
  # cannot place, places nothing.
  defp offset(_frame, _mark, _channel, nil, _row, _offsets), do: nil

  defp offset(frame, mark, channel, value, row, offsets) do
    family = family(channel)

    with %Band{} = outer <- scale_named(frame, Scales.scale_for(frame.kind, mark, family)),
         %Band{} = inner <- scale_named(frame, Scales.offset_scale(mark, family)),
         outer_start when is_number(outer_start) <- Scale.apply(outer, value),
         inner_value when inner_value != nil <- Table.get(row, Map.fetch!(offsets, family)),
         inner_start when is_number(inner_start) <- Scale.apply(inner, inner_value) do
      outer_start + inner_start + Band.bandwidth(inner) * band_share(channel)
    else
      _ -> nil
    end
  end

  defp scale_named(_frame, nil), do: nil
  defp scale_named(frame, name), do: Map.get(frame.scales, name)

  @doc false
  # Whether the mark declares the channel.
  @spec has?(map(), atom()) :: boolean()
  def has?(ctx, channel), do: Map.has_key?(Map.get(ctx.mark, :channels, %{}), channel)

  @doc false
  # The pixel rows whose every listed channel is placed: the per-datum drop of §5.2.
  @spec placed([pixel_row()], [atom()]) :: [pixel_row()]
  def placed(rows, channels), do: Enum.filter(rows, &placed?(&1, channels))

  @doc false
  @spec placed?(pixel_row(), [atom()]) :: boolean()
  def placed?(row, channels), do: Enum.all?(channels, &(Map.get(row, &1) != nil))

  @doc false
  # The realised scale a channel of the mark maps through, or `nil`.
  @spec scale(map(), atom()) :: struct() | nil
  def scale(%{frame: frame, mark: mark}, channel) do
    case Scales.scale_for(frame.kind, mark, channel) do
      nil -> nil
      name -> Map.get(frame.scales, name)
    end
  end

  @doc false
  # An area's default baseline: the pixel of the `y` scale's zero, **clamped to that
  # scale's range** (spec/14 §5.2, #420) — the zero line where zero is in view, the nearer
  # edge of the plot where it is not, since a domain that excludes zero put the fill
  # outside an unclipped plot. `0` without a scale. A baseline the design gives is a
  # channel and is placed as given.
  @spec baseline(map()) :: number()
  def baseline(ctx) do
    case scale(ctx, :y) do
      nil -> 0
      scale -> clamp(Scale.apply(scale, 0), Map.get(scale, :range))
    end
  end

  defp clamp(pixel, range) when is_number(pixel) and is_list(range) do
    case Enum.filter(range, &is_number/1) do
      [] -> pixel
      numbers -> numbers |> Enum.min_max() |> then(fn {lo, hi} -> min(max(pixel, lo), hi) end)
    end
  end

  defp clamp(pixel, _range), do: pixel

  defp read(%Var{name: name}, _row, _frame, _mark, _channel), do: Style.unresolved!(name)
  defp read(n, _row, _frame, _mark, _channel) when is_number(n), do: n
  defp read({:field, field}, row, _frame, _mark, _channel), do: Table.get(row, field)

  # A channel may name its scale's own end (spec/14 §5.2, #420): the reading is the end of
  # that scale's domain and is then mapped like any other, so it follows an inferred
  # domain frame by frame and honours the mark's `scales` rename.
  defp read({:scale, which}, _row, frame, mark, channel) when which in [:min, :max] do
    case scale_named(frame, Scales.scale_for(frame.kind, mark, channel)) do
      nil -> nil
      scale -> domain_end(scale.domain, which)
    end
  end

  defp read(field, row, _frame, _mark, _channel) when is_atom(field), do: Table.get(row, field)

  # The ends of a domain: by value where it is numeric, by position where it is not — the
  # first and the last member, which is the only order a categorical domain has.
  defp domain_end([], _which), do: nil

  defp domain_end(domain, which) do
    if Enum.all?(domain, &is_number/1) do
      {lo, hi} = Enum.min_max(domain)
      if which == :min, do: lo, else: hi
    else
      if which == :min, do: List.first(domain), else: List.last(domain)
    end
  end

  defp map(_frame, _mark, _channel, nil), do: nil

  defp map(frame, mark, channel, value) do
    case Scales.scale_for(frame.kind, mark, channel) do
      nil -> value
      name -> place(Map.get(frame.scales, name), channel, value)
    end
  end

  defp place(nil, _channel, value), do: value

  # Through a band scale an edge channel reads the band's start or end and a position
  # channel its centre (spec/14 §5.2).
  defp place(%Band{} = scale, channel, value) do
    case Scale.apply(scale, value) do
      nil -> nil
      start -> start + Band.bandwidth(scale) * band_share(channel)
    end
  end

  defp place(scale, _channel, value), do: Scale.apply(scale, value)

  defp band_share(channel) when channel in [:x0, :y0], do: 0
  defp band_share(channel) when channel in [:x1, :y1], do: 1
  defp band_share(_position), do: 0.5
end
