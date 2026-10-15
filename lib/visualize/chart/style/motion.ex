defmodule Visualize.Chart.Style.Motion do
  @moduledoc false
  # A style's motion parts resolved for the element (spec/14 §3.10, §3.11, D-176).
  #
  # `transition/1` reads a `transition` part — `duration` and `easing` for the fill, the
  # stroke and the opacity, or an entry per property — as the list of `{property, duration,
  # easing}` an element carries (`Visualize.IR.Motion`): each property's own entry, else the
  # part's own keys, else the defaults a scale's transition has (spec/14 §4.3). A property
  # moves when the part names it, or when the part's own `duration` or `easing` moves all
  # three; a duration of `0` moves nothing.

  @properties [:fill, :stroke, :opacity]
  @duration 300
  @easing :cubic_in_out

  @doc false
  # The element keys a motion part projects to.
  @spec keys() :: [atom(), ...]
  def keys, do: [:transition, :animation]

  @doc false
  # Whether a resolved element style carries motion.
  @spec moves?(map()) :: boolean()
  def moves?(style), do: Enum.any?(keys(), &Map.has_key?(style, &1))

  @doc false
  @spec transition(term()) :: [{atom(), number(), atom()}]
  def transition(node) when is_map(node) and not is_struct(node) do
    whole? = Map.has_key?(node, :duration) or Map.has_key?(node, :easing)

    for property <- @properties,
        entry = entry(node, property, whole?),
        entry != nil,
        duration = Map.get(entry, :duration) || Map.get(node, :duration) || @duration,
        is_number(duration) and duration > 0,
        do: {property, duration, Map.get(entry, :easing) || Map.get(node, :easing) || @easing}
  end

  def transition(_node), do: []

  @doc false
  # An `animation` part as the element carries it (spec/14 §3.11): its five keys with the
  # defaults in place; `nil` for a part without a name, or that runs no iteration.
  @spec animation(term()) :: map() | nil
  def animation(%{name: name} = node)
      when not is_struct(node) and ((is_atom(name) and name != nil) or is_binary(name)) do
    case Map.get(node, :iterations) || :infinite do
      n when n == 0 ->
        nil

      iterations ->
        %{
          name: name,
          duration: Map.get(node, :duration) || 1000,
          easing: Map.get(node, :easing) || :linear,
          iterations: iterations,
          delay: Map.get(node, :delay) || 0
        }
    end
  end

  def animation(_node), do: nil

  defp entry(node, property, whole?) do
    case Map.get(node, property) do
      entry when is_map(entry) and not is_struct(entry) -> entry
      _none -> if whole?, do: %{}
    end
  end
end
