defmodule Visualize.Generators do
  @moduledoc """
  A host's generators: styles and colors a design names and the frame computes at render
  (spec/14 §3.13, D-177).

  A design stores a **call**, `generate(:name, args)`, where a style or a color goes; a host
  module defines the generator as ordinary Elixir:

      defmodule MyApp.Generators do
        use Visualize.Generators

        defgenerator tenant_style(tenant_id, ctx) do
          MyApp.Tenants.theme(tenant_id, ctx.assigns).message_style
        end
      end

  `use Visualize.Generators` imports `defgenerator/2` and compiles `__generators__/0`, the
  `{name, arity}` of every generator the module defines. A generator's last parameter is the
  context, `%{theme: theme, vars: vars, assigns: assigns}`; the others are the design's
  arguments, literal terms or a datum's readings of its field bindings.

  The host registers the module — `config :visualize, generators: [MyApp.Generators]`, or
  `generators: [MyApp.Generators]` on `Visualize.Chart.from_map/2`, `Visualize.Chart.apply/2`
  and the other reads and renders — and a name no registered module defines is a validator
  fault when the chart is built. A generator in a style position returns a style (a name,
  a node or a list), one in a color position a typed color (`Visualize.Color`); any other
  result applies nothing and is logged. A generator that raises is not rescued.

  ## Examples

      iex> import Visualize.Generators, only: [generate: 2]
      iex> generate(:tenant_style, [{:field, :tenant}])
      {:generate, :tenant_style, [{:field, :tenant}]}

  """

  @typedoc "A stored generator call (spec/14 §3.13)."
  @type call :: {:generate, atom(), [term()]}

  @typedoc "Each generator `{name, arity}` by the module that defines it."
  @type registry :: %{{atom(), arity()} => module()}

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Visualize.Generators, only: [defgenerator: 2]
      Module.register_attribute(__MODULE__, :visualize_generators, accumulate: true)
      @before_compile Visualize.Generators
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    generators =
      env.module
      |> Module.get_attribute(:visualize_generators)
      |> Enum.reverse()
      |> Enum.uniq()

    quote do
      @doc false
      def __generators__, do: unquote(generators)
    end
  end

  @doc """
  A generator: `defgenerator name(arg, …, ctx) do … end` is a public `def` of that head,
  recorded under the module's `__generators__/0`. The last parameter is the context. A
  generator of several clauses is defined clause by clause, as any function is, and listed
  once.
  """
  defmacro defgenerator(head, body) do
    {name, args} = head!(head, __CALLER__)

    quote do
      @visualize_generators {unquote(name), unquote(length(args))}
      def unquote(head), unquote(body)
    end
  end

  defp head!({:when, _meta, [head, _guard]}, caller), do: head!(head, caller)

  defp head!({name, _meta, args}, _caller) when is_atom(name) and is_list(args) and args != [],
    do: {name, args}

  defp head!(head, caller) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description:
        "defgenerator needs a head with at least the context parameter, " <>
          "`name(arg, ..., ctx)`; got #{Macro.to_string(head)}"
  end

  @doc "As `generate/2` with no arguments."
  @spec generate(atom()) :: call()
  def generate(name), do: generate(name, [])

  @doc """
  The stored call `{:generate, name, args}` a design holds where a style or a color goes
  (spec/14 §3.13). `args` are literal terms or field bindings `{:field, f}`, read per datum.
  Raises `ArgumentError` for a name that is not an atom or arguments that are not a list.
  """
  @spec generate(atom(), [term()]) :: call()
  def generate(name, args)
      when is_atom(name) and name not in [nil, true, false] and is_list(args),
      do: {:generate, name, args}

  def generate(name, args) do
    raise ArgumentError,
          "generate/2 takes a generator's name, an atom, and a list of arguments; " <>
            "got #{inspect(name)} and #{inspect(args)}"
  end

  @doc """
  The registry of `modules` then `config :visualize, generators:` (spec/14 §3.13): each
  generator `{name, arity}` by the module that defines it. Raises `ArgumentError` for a
  module without `__generators__/0` and for a `{name, arity}` two modules define.
  """
  @spec registry([module()]) :: registry()
  def registry(modules \\ []) when is_list(modules) do
    configured = Application.get_env(:visualize, :generators, [])

    (modules ++ configured)
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn module, registry ->
      module |> generators!() |> Enum.reduce(registry, &register(&2, &1, module))
    end)
  end

  defp generators!(module) do
    if is_atom(module) and Code.ensure_loaded?(module) and
         function_exported?(module, :__generators__, 0) do
      module.__generators__()
    else
      raise ArgumentError,
            "#{inspect(module)} is not a generator module: `use Visualize.Generators` " <>
              "defines __generators__/0 (spec/14 §3.13)"
    end
  end

  defp register(registry, key, module) do
    case Map.fetch(registry, key) do
      :error ->
        Map.put(registry, key, module)

      {:ok, other} ->
        {name, arity} = key

        raise ArgumentError,
              "generator #{name}/#{arity} is defined by both #{inspect(other)} and " <>
                "#{inspect(module)}: a design names one generator (spec/14 §3.13)"
    end
  end
end
