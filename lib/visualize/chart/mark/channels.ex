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

    Enum.map(ctx.rows, fn row ->
      Enum.reduce(channels, %{datum: row}, fn {channel, spec}, acc ->
        value = read(spec, row)

        pixel =
          if channel in @raw_always or channel in raw,
            do: value,
            else: map(frame, ctx.type, channel, value)

        Map.put(acc, channel, pixel)
      end)
    end)
  end

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
  def scale(%{frame: frame, type: type}, channel) do
    case Scales.scale_for(frame.kind, type, channel) do
      nil -> nil
      name -> Map.get(frame.scales, name)
    end
  end

  @doc false
  # The pixel of the `y` scale's zero — an area's baseline — or `0` without a scale.
  @spec baseline(map()) :: number()
  def baseline(ctx) do
    case scale(ctx, :y) do
      nil -> 0
      scale -> Scale.apply(scale, 0)
    end
  end

  defp read(%Var{name: name}, _row), do: Style.unresolved!(name)
  defp read(n, _row) when is_number(n), do: n
  defp read({:field, field}, row), do: Table.get(row, field)
  defp read(field, row) when is_atom(field), do: Table.get(row, field)

  defp map(_frame, _type, _channel, nil), do: nil

  defp map(frame, type, channel, value) do
    case Scales.scale_for(frame.kind, type, channel) do
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
