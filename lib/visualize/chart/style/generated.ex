defmodule Visualize.Chart.Style.Generated do
  @moduledoc false
  # Generators at render (spec/14 §3.13, D-177): the runtime a frame carries — the registry
  # of `Visualize.Generators.registry/1`, the design's variables and the host's assigns —
  # and what the frame does with a stored `{:generate, name, args}`.
  #
  # A generator call stands in two places: as a **stack entry**, whose result must be a
  # style, and as a **leaf** in a style's `:colour` position, whose result must be a typed
  # color. `reached/3` finds the calls a stack reaches, each tagged by its place; `memo/4`
  # calls every distinct `(name, arguments)` of a site's rows once; `resolve/5` answers one
  # call's checked result for the style resolution's `pick`, or `nil` — the call applies
  # nothing — logging the fault. Nothing here rescues: a generator that raises raises.

  require Logger

  alias Visualize.Chart.{Migration, Validator, Var}
  alias Visualize.Chart.Style.Parts
  alias Visualize.Chart.Validator.{Colors, Generators, Words}
  alias Visualize.Data.Table
  alias Visualize.Theme

  defstruct modules: [], vars: %{}, assigns: %{}

  @type t :: %__MODULE__{
          modules: [module()],
          vars: %{atom() => term()},
          assigns: map()
        }

  @typedoc "A call's place: a stack entry, or a leaf at a color."
  @type place :: :entry | :leaf

  # The paints a frame draws from its `defs`, which a result may not write in place: the
  # frame holds its gradients before it draws (spec/14 §3.2).
  @drawn [:linear, :radial, :hatch]

  @doc false
  # The runtime of `modules` — with the configuration's, looked up when a generator is first
  # called, so a design without one loads no module — the design's variables and the host's
  # assigns.
  @spec new([module()], map(), map()) :: t()
  def new(modules \\ [], vars \\ %{}, assigns \\ %{}),
    do: %__MODULE__{modules: modules, vars: Map.new(vars), assigns: Map.new(assigns)}

  @doc false
  # The context a generator receives with its arguments (spec/14 §3.13).
  @spec context(t(), Theme.t()) :: %{theme: Theme.t(), vars: map(), assigns: map()}
  def context(%__MODULE__{vars: vars, assigns: assigns}, theme),
    do: %{theme: theme, vars: vars, assigns: assigns}

  @doc false
  # Whether a term is a stored generator call.
  @spec call?(term()) :: boolean()
  def call?({:generate, name, args}), do: is_atom(name) and is_list(args)
  def call?(_term), do: false

  @doc false
  # The generator calls a stack reaches, each `{place, call}`, in the order the stack lays
  # them: its entries, the leaves of its inline nodes and of every style it names — through
  # names, lists and `extends` — and of the style each field entry picks, `picked` mapping
  # an entry to its name (or `nil`). A cycle is the resolution's to raise; here a name met
  # twice is not walked again.
  @spec reached(%{atom() => term()}, term(), map()) :: [{place(), tuple()}]
  def reached(styles, stack, picked), do: reach(styles, stack, picked, [])

  defp reach(_styles, nil, _picked, _seen), do: []
  defp reach(_styles, %Var{}, _picked, _seen), do: []

  defp reach(styles, stack, picked, seen) when is_list(stack),
    do: Enum.flat_map(stack, &reach(styles, &1, picked, seen))

  defp reach(styles, {:field, _} = entry, picked, seen) do
    case Map.get(picked, entry) do
      nil -> []
      name -> named(styles, name, picked, seen)
    end
  end

  defp reach(_styles, {:generate, _, _} = call, _picked, _seen) do
    if call?(call), do: [{:entry, call}], else: []
  end

  defp reach(styles, node, picked, seen) when is_map(node) and not is_struct(node) do
    under =
      case Map.fetch(node, :extends) do
        {:ok, parent} -> reach(styles, parent, picked, seen)
        :error -> []
      end

    under ++ Enum.map(leaves(Map.delete(node, :extends)), &{:leaf, &1})
  end

  defp reach(styles, name, picked, seen) when is_atom(name),
    do: named(styles, name, picked, seen)

  defp reach(_styles, _other, _picked, _seen), do: []

  defp named(styles, name, picked, seen) do
    if name in seen,
      do: [],
      else: reach(styles, Map.get(styles, name), picked, [name | seen])
  end

  # Every call in a node's values, at any depth.
  defp leaves({:generate, _, _} = call), do: if(call?(call), do: [call], else: [])
  defp leaves(%_{}), do: []
  defp leaves(map) when is_map(map), do: map |> Map.values() |> Enum.flat_map(&leaves/1)
  defp leaves(list) when is_list(list), do: Enum.flat_map(list, &leaves/1)
  defp leaves(_value), do: []

  @doc false
  # A node with every leaf call replaced by `resolve.(call)`, its key dropped where that is
  # `nil`: the call applies nothing, so what lies under the node shows through.
  @spec leaf_resolve(map(), (tuple() -> term())) :: map()
  def leaf_resolve(node, resolve) when is_map(node) and not is_struct(node) do
    # A node without a call — nearly every one — is answered as it is, unrebuilt.
    if leaves(node) == [], do: node, else: rebuild(node, resolve)
  end

  defp rebuild(node, resolve) do
    Enum.reduce(node, %{}, fn {key, value}, acc ->
      case leaf_value(value, resolve) do
        nil -> acc
        resolved -> Map.put(acc, key, resolved)
      end
    end)
  end

  defp leaf_value({:generate, _, _} = call, resolve),
    do: if(call?(call), do: resolve.(call), else: call)

  defp leaf_value(%_{} = struct, _resolve), do: struct
  defp leaf_value(map, resolve) when is_map(map), do: rebuild(map, resolve)
  defp leaf_value(value, _resolve), do: value

  @doc false
  # The arguments a call is made with for a datum: each field binding the datum's reading,
  # `nil` without a datum; a literal as it is.
  @spec args([term()], term()) :: [term()]
  def args(args, datum) do
    Enum.map(args, fn
      {:field, field} -> if datum == nil, do: nil, else: Table.get(datum, field)
      literal -> literal
    end)
  end

  @doc false
  # A call's key for a datum: its name and the arguments it is made with.
  @spec key(tuple(), term()) :: {atom(), [term()]}
  def key({:generate, name, args}, datum), do: {name, args(args, datum)}

  @doc false
  # Every distinct key of `keys` called once (spec/14 §3.13), over `memo`: a map from the
  # key to what the generator returned.
  @spec memo(t(), Theme.t(), Enumerable.t(), map()) :: map()
  def memo(runtime, theme, keys, memo \\ %{})
  def memo(_runtime, _theme, [], memo), do: memo

  def memo(runtime, theme, keys, memo) do
    registry = Visualize.Generators.registry(runtime.modules)

    Enum.reduce(keys, memo, fn key, memo ->
      if Map.has_key?(memo, key),
        do: memo,
        else: Map.put(memo, key, call(registry, runtime, theme, key))
    end)
  end

  @doc false
  # One generator called: its module's function of the name, with the arguments and the
  # context. A name the registry lacks at this arity is a host's mistake — the chart was
  # validated against another registry — and raises; a generator's own raise goes through.
  @spec call(t(), Theme.t(), {atom(), [term()]}) :: term()
  def call(%__MODULE__{} = runtime, theme, key),
    do: call(Visualize.Generators.registry(runtime.modules), runtime, theme, key)

  defp call(registry, runtime, theme, {name, args}) do
    arity = length(args) + 1

    case Map.fetch(registry, {name, arity}) do
      {:ok, module} ->
        apply(module, name, args ++ [context(runtime, theme)])

      :error ->
        raise ArgumentError,
              "generator #{name}/#{arity} is not registered for this render: the chart was " <>
                "validated with a registry that defines it (spec/14 §3.13)"
    end
  end

  @doc false
  # One call's checked result for a datum, from `memo` or called now: a style for an
  # entry, a color for a leaf, or `nil` — applying nothing — with the fault logged at
  # `path`, the site's.
  @spec resolve(map(), place(), tuple(), term(), keyword()) :: term()
  def resolve(frame, place, call, datum, opts) do
    {name, _args} = key = key(call, datum)
    memo = Keyword.get(opts, :memo, %{})

    result =
      case Map.fetch(memo, key) do
        {:ok, result} -> result
        :error -> call(Map.get(frame, :generated) || new(), frame.theme, key)
      end

    case checked(place, result, frame) do
      {:ok, value} ->
        value

      {:error, reason} ->
        fault(Keyword.get(opts, :path, []), place, name, reason)
        nil
    end
  end

  @doc false
  # The `pick` of a site with no datum — an axis, a legend, a frame label (spec/14 §3.13):
  # a field entry lays nothing, and a generator is called with its field arguments `nil`.
  @spec pick(map(), list()) :: (term() -> term())
  def pick(frame, path) do
    fn
      {:field, _} -> nil
      {:colour, call} -> resolve(frame, :leaf, call, nil, path: path)
      call -> resolve(frame, :entry, call, nil, path: path)
    end
  end

  @doc false
  # A result checked for its place (spec/14 §3.13): `{:ok, value}`, the value in the shape a
  # design stores it, or `{:error, reason}`.
  @spec checked(place(), term(), map()) :: {:ok, term()} | {:error, term()}
  def checked(:leaf, :none, _frame), do: {:ok, :none}

  # A typed color, its names the theme's: a bare atom is a style's word, never a color's
  # (D-173), and a generator's result is held to the stored form.
  def checked(:leaf, result, frame) do
    case Colors.check(result, [], MapSet.new(Theme.color_names(frame.theme))) do
      [] -> {:ok, result}
      [{_path, reason} | _] -> {:error, reason}
    end
  end

  def checked(:entry, result, frame) do
    style = style(result)

    faults = Generators.style(style, Map.keys(frame.styles), Theme.color_names(frame.theme))

    cond do
      faults != [] -> {:error, faults |> hd() |> elem(1)}
      drawn?(style) -> {:error, {:invalid_for, :generator}}
      true -> {:ok, style}
    end
  end

  # A style result in the stored shape, as a design's is read (spec/14 §3.1, §9).
  defp style(node) when is_map(node) and not is_struct(node),
    do: Migration.canonical(node, :style)

  defp style(list) when is_list(list), do: Enum.map(list, &style/1)
  defp style(other), do: other

  # Whether a style result writes a gradient or a hatch in place.
  defp drawn?(list) when is_list(list), do: Enum.any?(list, &drawn?/1)

  defp drawn?(node) when is_map(node) and not is_struct(node) do
    node = Parts.normalize(node)

    Enum.any?([:fill, :stroke], fn key ->
      match?(%{type: type} when type in @drawn, Map.get(node, key))
    end)
  end

  defp drawn?(_other), do: false

  defp fault(path, place, name, reason) do
    kind = if place == :leaf, do: :color, else: :style

    Logger.warning(
      Validator.format_path(path) <> ": " <> Words.words({:generated, kind, name, reason})
    )
  end
end
