defmodule Visualize.Chart.Builder.Chain do
  @moduledoc """
  A typed color as a chain: a base, then the transforms applied to it in order (spec/14
  §19.10, D-178).

  A color a design writes as `color(:red) |> shade(700) |> alpha(0.8)` is the term
  `{:alpha, {:shade, {:color, :red}, 700}, 0.8}`: transforms nested inside out. The picker
  shows it the way it reads — the base `red`, then `shade 700`, then `alpha 0.8` — and edits
  it step by step: a step added at the end, an amount changed, a step removed, the base
  replaced with the steps kept. Every edit is a function of the value to the value, so what
  the picker builds is exactly the term `Visualize.Color`'s helpers would.

  A blend is a base whose operands are chains of their own, addressed by a path of operand
  positions: `[]` is the color itself, `[1]` the blend's second operand, `[1, 0]` the first
  operand of a blend that operand is.
  """

  alias Visualize.Color
  alias Visualize.Color.Typed
  alias Visualize.Theme

  # The steps a chain can add, in the order the picker offers them; `blend` turns the color
  # into the first operand of a blend.
  @steps [:intensity, :alpha, :lighten, :darken, :saturate, :shade, :contrast, :blend]

  # The amount a step starts at, and its span: the 0–1 transforms, `shade` on 0–1000.
  @starts %{intensity: 0.5, alpha: 0.5, lighten: 0.2, darken: 0.2, saturate: 0.2, shade: 500}

  @typedoc "One step after the base: a transform and its amount, or `:contrast`."
  @type step :: {atom(), number()} | :contrast

  @doc "The steps the picker offers, in order."
  @spec steps() :: [atom(), ...]
  def steps, do: @steps

  @doc """
  The span a step's amount takes: `{min, max, step}`.

      iex> Visualize.Chart.Builder.Chain.span(:shade)
      {0, 1000, 50}

      iex> Visualize.Chart.Builder.Chain.span(:alpha)
      {0, 1, 0.05}
  """
  @spec span(atom()) :: {number(), number(), number()}
  def span(:shade), do: {0, 1000, 50}
  def span(_op), do: {0, 1, 0.05}

  @doc """
  A color as its base and its steps, in the order they are applied.

      iex> Visualize.Chart.Builder.Chain.split({:alpha, {:shade, {:color, :red}, 700}, 0.8})
      {{:color, :red}, [{:shade, 700}, {:alpha, 0.8}]}

      iex> Visualize.Chart.Builder.Chain.split({:contrast, {:color, :bad}})
      {{:color, :bad}, [:contrast]}

      iex> Visualize.Chart.Builder.Chain.split("#abc")
      {"#abc", []}
  """
  @spec split(term()) :: {term(), [step()]}
  def split({op, c, t}) when is_atom(op) and op != :ramp do
    if op in Typed.ops() do
      {base, steps} = split(c)
      {base, steps ++ [{op, t}]}
    else
      {{op, c, t}, []}
    end
  end

  def split({:contrast, :under} = base), do: {base, []}

  def split({:contrast, c}) do
    {base, steps} = split(c)
    {base, steps ++ [:contrast]}
  end

  def split(value), do: {value, []}

  @doc """
  A base and steps joined back into the color they mean; `split/1`'s inverse.

      iex> Visualize.Chart.Builder.Chain.join({:color, :red}, [{:shade, 700}, {:alpha, 0.8}])
      {:alpha, {:shade, {:color, :red}, 700}, 0.8}
  """
  @spec join(term(), [step()]) :: term()
  def join(base, steps) do
    Enum.reduce(steps, base, fn
      :contrast, acc -> {:contrast, acc}
      {op, t}, acc -> {op, acc, t}
    end)
  end

  @doc """
  The color with one edit made at the chain `path` addresses (`[]` the color itself, an
  operand's position into a blend at each level):

  * `{:add, op}` — a step at the end, at its starting amount; `:blend` makes the color the
    first operand of a blend with the theme's background;
  * `{:amount, i, n}` — step `i`'s amount;
  * `{:remove, i}` — step `i` taken out;
  * `{:base, base}` — the base replaced, the steps kept;
  * `{:operand, :add}` / `{:operand, {:remove, i}}` — a blend's operands.

      iex> alias Visualize.Chart.Builder.Chain
      iex> red = {:color, :red}
      iex> red |> Chain.edit([], {:add, :shade}) |> Chain.edit([], {:amount, 0, 700}) |> Chain.edit([], {:add, :alpha})
      {:alpha, {:shade, {:color, :red}, 700}, 0.5}
      iex> Chain.edit({:alpha, {:color, :red}, 0.5}, [], {:base, {:color, :blue}})
      {:alpha, {:color, :blue}, 0.5}
      iex> Chain.edit({:color, :red}, [], {:add, :blend})
      {:blend, [{:color, :red}, {:color, :background}]}
      iex> Chain.edit({:blend, [{:color, :red}, {:color, :blue}]}, [1], {:add, :intensity})
      {:blend, [{:color, :red}, {:intensity, {:color, :blue}, 0.5}]}
  """
  @spec edit(term(), [non_neg_integer()], term()) :: term()
  def edit(value, path, change), do: value |> typed() |> edited(path, change)

  defp edited(value, [], change), do: change(value, change)

  defp edited(value, [i | rest], change) do
    {base, steps} = split(value)

    case base do
      {:blend, operands} when is_list(operands) and i < length(operands) ->
        join({:blend, List.update_at(operands, i, &edit(&1, rest, change))}, steps)

      _other ->
        value
    end
  end

  # A bare name in a color position is the color of that name (D-173): the chain is built on
  # the typed form, so every step it adds is a color `Visualize.Color` would accept.
  defp typed(name) when is_atom(name) and name not in [nil, true, false, :none],
    do: {:color, name}

  defp typed(value), do: value

  defp change(value, {:add, :blend}), do: {:blend, [value, {:color, :background}]}
  defp change(value, {:add, :contrast}), do: {:contrast, value}

  defp change(value, {:add, op}) when is_map_key(@starts, op),
    do: {op, value, Map.fetch!(@starts, op)}

  defp change(value, {:amount, i, n}) do
    {base, steps} = split(value)

    case Enum.at(steps, i) do
      {op, _old} -> join(base, List.replace_at(steps, i, {op, n}))
      _contrast_or_none -> value
    end
  end

  defp change(value, {:remove, i}) do
    {base, steps} = split(value)
    join(base, List.delete_at(steps, i))
  end

  defp change(value, {:base, base}) do
    {_old, steps} = split(value)
    join(base, steps)
  end

  defp change(value, {:operand, op}) do
    {base, steps} = split(value)

    case {base, op} do
      {{:blend, operands}, :add} ->
        join({:blend, operands ++ [{:color, :background}]}, steps)

      {{:blend, [_only]}, {:remove, _i}} ->
        value

      {{:blend, [_, _]} = blend, {:remove, i}} ->
        # A blend of one is its operand: the blend dissolves into what is left.
        {:blend, operands} = blend
        join(Enum.at(operands, 1 - i), steps)

      {{:blend, operands}, {:remove, i}} ->
        join({:blend, List.delete_at(operands, i)}, steps)

      _other ->
        value
    end
  end

  defp change(value, _unknown), do: value

  @doc """
  The color at `path` in a chain — a blend's operand — or `nil`.
  """
  @spec at(term(), [non_neg_integer()]) :: term()
  def at(value, []), do: value

  def at(value, [i | rest]) do
    case split(value) do
      {{:blend, operands}, _steps} when is_list(operands) -> operands |> Enum.at(i) |> at(rest)
      _other -> nil
    end
  end

  @doc """
  The chain as the picker draws it: the base's word and color, and after each step the
  color reached so far, each resolved through `theme` in `:literal` mode — `nil` where a
  name the value reads is not the theme's.

      iex> theme = Visualize.Theme.default()
      iex> [base, step] = Visualize.Chart.Builder.Chain.rows({:alpha, "#ff0000", 0.5}, theme)
      iex> {base.word, base.colour, step.word, step.colour}
      {"#ff0000", "#ff0000", "alpha", "#ff000080"}
  """
  @spec rows(term(), Theme.t() | nil) :: [map()]
  def rows(value, theme) do
    {base, steps} = split(value)

    base_row = %{
      index: nil,
      op: nil,
      word: word(base),
      amount: nil,
      span: nil,
      colour: resolved(base, theme),
      operands: operands(base)
    }

    {rows, _acc} =
      steps
      |> Enum.with_index()
      |> Enum.map_reduce(base, fn {step, i}, acc ->
        acc = join(acc, [step])
        {op, amount} = if step == :contrast, do: {:contrast, nil}, else: step

        {%{
           index: i,
           op: op,
           word: to_string(op),
           amount: amount,
           span: if(amount, do: span(op)),
           colour: resolved(acc, theme),
           operands: []
         }, acc}
      end)

    [base_row | rows]
  end

  defp operands({:blend, operands}) when is_list(operands), do: operands
  defp operands(_base), do: []

  defp word({:blend, _operands}), do: "blend"
  defp word(value), do: expression(value)

  @doc false
  # A color value as a person reads it: a name, a literal, a transform as its call.
  @spec expression(term()) :: String.t()
  def expression({:color, name}), do: to_string(name)
  def expression({:series, i}), do: "series #{i}"
  def expression({:ramp, name, t}), do: "ramp(#{name}, #{t})"
  def expression({:blend, list}), do: "blend(" <> Enum.map_join(list, ", ", &expression/1) <> ")"
  def expression({:contrast, :under}), do: "contrast()"
  def expression({:contrast, c}), do: "contrast(#{expression(c)})"
  def expression({op, c, t}) when is_atom(op), do: "#{op}(#{expression(c)}, #{t})"
  def expression(value) when is_binary(value), do: value
  def expression(value) when is_atom(value), do: to_string(value)
  def expression(value), do: inspect(value)

  @doc """
  A color picked for a field that holds `current` (spec/14 §19.10): where `current` is a
  chain with steps, the picked color is its new base and the steps are kept; otherwise the
  picked color is the whole value.

      iex> Visualize.Chart.Builder.Chain.rebase({:alpha, {:color, :red}, 0.5}, {:color, :blue})
      {:alpha, {:color, :blue}, 0.5}

      iex> Visualize.Chart.Builder.Chain.rebase({:color, :red}, "#123456")
      "#123456"
  """
  @spec rebase(term(), term()) :: term()
  def rebase(current, picked) do
    case split(current) do
      {_base, [_ | _]} -> edit(current, [], {:base, picked})
      {_base, []} -> picked
    end
  end

  @doc false
  # The literal a color resolves to through a theme, or `nil` where it cannot.
  def resolved(value, %Theme{} = theme) do
    cond do
      not Color.value?(value) and not is_atom(value) ->
        nil

      is_atom(value) ->
        resolved({:color, value}, theme)

      Enum.all?(Typed.names(value), &(&1 in Theme.color_names(theme))) ->
        Color.resolve(value, theme, :literal)

      true ->
        nil
    end
  end

  def resolved(_value, _theme), do: nil
end
