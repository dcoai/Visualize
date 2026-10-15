defmodule Visualize.Theme.Contract do
  @moduledoc false
  # The meaning contracts of a theme's ramps and roles (spec/08 §7.5, D-135), measured in
  # CIE LCh against the D50 white point. `check/3` answers the first ramp or role that
  # breaks its contract, with a message naming the term it breaks and the values measured,
  # or `:ok`. The tolerances are the spec's, and each says why it is the number it is.

  alias Visualize.Color

  @ramps [:status, :thermal, :diverging, :sequential]
  @roles [:info, :neutral]

  # A hue a reader can name needs this much chroma; below it a colour is a tint.
  @chromatic 20
  # A colour this grey reads as no hue; the built-in midpoints measure 0.0 to 6.3.
  @neutral 10
  # Each step of a monotonic ramp moves lightness this far: about three just-noticeable
  # differences, so the order is visible on a screen and not only on a meter.
  @step 3
  # One hue family: the arc every anchor of at least `@family_chroma` lies within — the
  # tightest round arc that admits every ColorBrewer single-hue scheme (blues spans 42.9°).
  @family 45
  @family_chroma 10
  # The two ends of a diverging ramp are two hues, not one: this far apart at least.
  @apart 60

  @doc false
  @spec ramps() :: [atom(), ...]
  def ramps, do: @ramps

  @doc false
  @spec roles() :: [atom(), ...]
  def roles, do: @roles

  @doc false
  # `:ok`, or `{:error, subject, message}` for the first ramp or role that breaks its
  # contract. A hue contract is read at the positions a design reads — 0, 0.5 and 1 —
  # through the theme's own Lab interpolation, not only at the anchors.
  @spec check(map(), map()) :: :ok | {:error, {:ramp | :color, atom()}, String.t()}
  def check(ramps, roles) when is_map(ramps) and is_map(roles) do
    with :ok <- names(ramps, @ramps, :ramp),
         :ok <- each(ramps, &ramp/2) do
      each(roles, &role/2)
    end
  end

  defp names(map, allowed, kind) do
    case Enum.find(Map.keys(map), &(&1 not in allowed)) do
      nil ->
        :ok

      name ->
        {:error, {kind, name}, "is not a #{kind} of a theme; the #{kind}s are #{list(allowed)}"}
    end
  end

  # Ramps and roles in the order of the spec, so the first fault reported is stable.
  defp each(map, fun) do
    Enum.reduce_while(@ramps ++ @roles, :ok, fn name, :ok ->
      case Map.fetch(map, name) do
        :error ->
          {:cont, :ok}

        {:ok, value} ->
          case fun.(name, value) do
            :ok -> {:cont, :ok}
            {:error, _, _} = error -> {:halt, error}
          end
      end
    end)
  end

  # -- ramps --------------------------------------------------------------------------

  defp ramp(name, anchors) when is_list(anchors) and length(anchors) >= 2 do
    case parse_all(anchors) do
      {:ok, colours} -> contract(name, Enum.zip(anchors, colours))
      {:bad, i, anchor} -> fault(name, "anchor #{i} #{inspect(anchor)} is not a colour")
    end
  end

  defp ramp(name, anchors) when is_list(anchors),
    do: fault(name, "needs at least two anchors, got #{length(anchors)}")

  defp ramp(name, other),
    do: fault(name, "is a list of anchor colours, got #{inspect(other)}")

  defp parse_all(anchors) do
    anchors
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {anchor, i}, {:ok, acc} ->
      case is_binary(anchor) && Color.parse(anchor) do
        %Color{} = colour -> {:cont, {:ok, [Color.to_hcl(colour) | acc]}}
        _ -> {:halt, {:bad, i, anchor}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      bad -> bad
    end
  end

  defp contract(:status, anchors) do
    with :ok <- region(:status, anchors, 0, [:green, :blue], "good (0)"),
         :ok <- region(:status, anchors, 0.5, [:amber], "warning (0.5)"),
         :ok <- region(:status, anchors, 1, [:red], "bad (1)"),
         :ok <- falling_hue(:status, anchors) do
      lightness(:status, anchors)
    end
  end

  defp contract(:thermal, anchors) do
    with :ok <- region(:thermal, anchors, 0, [:blue], "cold (0)"),
         :ok <- neutral(:thermal, anchors, 0.5, "the midpoint (0.5)") do
      region(:thermal, anchors, 1, [:red], "hot (1)")
    end
  end

  defp contract(:diverging, anchors) do
    with :ok <- chromatic(:diverging, anchors, 0, "the low end (0)"),
         :ok <- chromatic(:diverging, anchors, 1, "the high end (1)"),
         :ok <- neutral(:diverging, anchors, 0.5, "the midpoint (0.5)") do
      two_hues(anchors)
    end
  end

  defp contract(:sequential, anchors) do
    with :ok <- family(anchors), do: lightness(:sequential, anchors)
  end

  # The LCh of the ramp at `t`: Lab-interpolated between the anchors about it, as
  # `Visualize.Theme.ramp/3` draws it.
  defp at(anchors, t) do
    n = length(anchors) - 1
    position = t * n
    i = min(trunc(position), n - 1)
    u = position - i

    {a, lch} = Enum.at(anchors, i)
    {b, _} = Enum.at(anchors, i + 1)

    if u == 0,
      do: lch,
      else: Color.to_hcl(Color.interpolate_lab(Color.parse(a), Color.parse(b), u))
  end

  defp region(name, anchors, t, regions, what) do
    lch = at(anchors, t)

    cond do
      lch.c < @chromatic ->
        fault(
          name,
          "#{what} must be #{words(regions)}, but its chroma is " <>
            "#{round1(lch.c)} C* — under #{@chromatic}, a tint with no hue to name"
        )

      hue_region(lch.h) not in regions ->
        fault(
          name,
          "#{what} must be #{words(regions)}, but its hue is #{round1(lch.h)}°, " <>
            "in #{hue_region(lch.h)} (the regions: #{bands()})"
        )

      true ->
        :ok
    end
  end

  defp chromatic(name, anchors, t, what) do
    lch = at(anchors, t)

    if lch.c >= @chromatic,
      do: :ok,
      else:
        fault(
          name,
          "#{what} must be a hue, at least #{@chromatic} C*, but its chroma is " <>
            "#{round1(lch.c)} C*"
        )
  end

  defp neutral(name, anchors, t, what) do
    lch = at(anchors, t)

    if lch.c <= @neutral,
      do: :ok,
      else:
        fault(
          name,
          "#{what} must be neutral, at most #{@neutral} C*, but its chroma is " <>
            "#{round1(lch.c)} C*"
        )
  end

  defp two_hues(anchors) do
    low = at(anchors, 0)
    high = at(anchors, 1)
    apart = arc(low.h, high.h)

    if apart >= @apart,
      do: :ok,
      else:
        fault(
          :diverging,
          "its ends must be two hues at least #{@apart}° apart, but " <>
            "#{round1(low.h)}° and #{round1(high.h)}° are #{round1(apart)}° apart"
        )
  end

  # The hue of every chromatic anchor falls from the first to the last, red's arc read
  # below zero: green → amber → red and blue → orange → red both fall.
  defp falling_hue(name, anchors) do
    hues =
      for {{anchor, lch}, i} <- Enum.with_index(anchors, 1), lch.c >= @chromatic do
        {i, anchor, if(lch.h >= 345, do: lch.h - 360, else: lch.h)}
      end

    hues
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [{_, _, a}, {_, _, b}] -> b > a end)
    |> case do
      nil ->
        :ok

      [{i, a, ha}, {j, b, hb}] ->
        fault(
          name,
          "its hue must fall from good to bad (green or blue → amber → red), but " <>
            "anchor #{j} #{inspect(b)} at #{round1(norm(hb))}° turns back from anchor #{i} " <>
            "#{inspect(a)} at #{round1(norm(ha))}°"
        )
    end
  end

  defp family(anchors) do
    hues = for {_, lch} <- anchors, lch.c >= @family_chroma, do: lch.h
    spread = spread(hues)

    if spread <= @family,
      do: :ok,
      else:
        fault(
          :sequential,
          "must be one hue family, its anchors of #{@family_chroma} C* or " <>
            "more within #{@family}°, but they span #{round1(spread)}° " <>
            "(#{Enum.map_join(hues, ", ", &"#{round1(&1)}°")})"
        )
  end

  # Lightness moves one way by at least `@step` a step, the way the ramp's ends say: either
  # way is the contract, so a dark theme may run its ramps dark → light.
  defp lightness(name, anchors) do
    ls = Enum.map(anchors, fn {anchor, lch} -> {anchor, lch.l} end)
    {_, first} = hd(ls)
    {_, last} = List.last(ls)
    sign = if last >= first, do: 1, else: -1

    ls
    |> Enum.with_index(1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [{{_, a}, _}, {{_, b}, _}] -> (b - a) * sign < @step end)
    |> case do
      nil ->
        :ok

      [{{a, la}, i}, {{b, lb}, j}] ->
        moved = (lb - la) * sign

        how =
          if moved < 0,
            do: "#{round1(-moved)} L* the wrong way",
            else: "only #{round1(moved)} L*"

        fault(
          name,
          "lightness must change one way along the ramp, by at least #{@step} L* a " <>
            "step (its ends say it #{if sign > 0, do: "rises", else: "falls"}); anchor #{j} #{inspect(b)} (L* #{round1(lb)}) " <>
            "moves #{how} from anchor #{i} #{inspect(a)} (L* #{round1(la)})"
        )
    end
  end

  # -- roles --------------------------------------------------------------------------

  defp role(name, colour) do
    case is_binary(colour) && Color.parse(colour) do
      %Color{} = parsed -> role_contract(name, Color.to_hcl(parsed))
      _ -> {:error, {:color, name}, "#{inspect(colour)} is not a colour"}
    end
  end

  defp role_contract(:info, lch) do
    cond do
      lch.c < @chromatic ->
        {:error, {:color, :info},
         "must be a blue, at least #{@chromatic} C*, but its chroma is #{round1(lch.c)} C*"}

      hue_region(lch.h) != :blue ->
        {:error, {:color, :info},
         "must be a blue, but its hue is #{round1(lch.h)}°, in #{hue_region(lch.h)} (the regions: #{bands()})"}

      true ->
        :ok
    end
  end

  defp role_contract(:neutral, lch) do
    if lch.c <= @neutral,
      do: :ok,
      else:
        {:error, {:color, :neutral},
         "must be neutral, at most #{@neutral} C*, but its chroma is #{round1(lch.c)} C*"}
  end

  # -- hue ----------------------------------------------------------------------------

  # The arcs of LCh hue each region names, placed by measuring sRGB's primaries: red 41°,
  # orange 71°, yellow 100°, green 134°, cyan 197°, blue 301°.
  defp hue_region(h) when h < 45 or h >= 345, do: :red
  defp hue_region(h) when h < 100, do: :amber
  defp hue_region(h) when h < 200, do: :green
  defp hue_region(h) when h < 315, do: :blue
  defp hue_region(_h), do: :purple

  defp bands, do: "red < 45° or ≥ 345°, amber 45–100°, green 100–200°, blue 200–315°"

  defp words([one]), do: Atom.to_string(one)
  defp words([a, b]), do: "#{a} or #{b}"

  defp arc(a, b) do
    d = abs(a - b)
    min(d, 360 - d)
  end

  # The smallest arc holding every hue: 360° less the widest gap between neighbours.
  defp spread([]), do: 0
  defp spread([_]), do: 0

  defp spread(hues) do
    sorted = Enum.sort(hues)
    gaps = Enum.zip(sorted, tl(sorted) ++ [hd(sorted) + 360]) |> Enum.map(fn {a, b} -> b - a end)
    360 - Enum.max(gaps)
  end

  defp norm(h) when h < 0, do: h + 360
  defp norm(h), do: h

  defp fault(name, message), do: {:error, {:ramp, name}, message}

  defp round1(x), do: Float.round(x * 1.0, 1)

  defp list(atoms), do: Enum.map_join(atoms, ", ", &inspect/1)
end
