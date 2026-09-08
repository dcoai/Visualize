defmodule Visualize.Audit.CodeScan do
  @moduledoc """
  Every public function `lib/` defines, read from source without compiling it.

  A definition is *public* when it is a `def`, `defmacro`, `defguard` or `defdelegate`
  that Elixir would document: `@doc false` hides every arity of the definition it precedes,
  and `@impl` without an explicit `@doc` hides it likewise, default-argument arities
  included (what `Code.fetch_docs/1` reports). Functions a `use` injects are not in the
  source: a module that generates its injections declares them through a zero-arity
  `injected` export, which the scanner asks for, and `GenServer` is listed here (spec/12 §2).

  Each function is versioned with `Surfex.SourceScan.definition_hash/1` over all of its
  clauses, so the golden's `Version` column changes when the definition changes and not when
  the file is reformatted or something above it moves.
  """

  alias Surfex.SourceScan

  @type entry :: %{
          module: String.t(),
          name: atom,
          arity: non_neg_integer,
          hidden?: boolean,
          version: String.t(),
          file: String.t()
        }

  # Functions injected by `use`, per module used: not visible in the source, documented by
  # the injecting module, and public. A module that generates its injections declares them
  # instead, through a zero-arity `injected` export the scanner asks for (spec/12 §2), which
  # is how the builder's schema-generated functions reach the golden (spec/14 §16.6, D-79).

  @definers [:def, :defmacro, :defguard]

  @doc "Every function definition under `root`'s `lib/`, in `{module, name, arity}` order."
  @spec run(String.t()) :: [entry]
  def run(root) do
    # The library's own `lib/` only: `Surfex.SourceScan.lib_sources/1` would also walk
    # `examples/lib/`, which is a consumer, not the surface.
    root
    |> Path.join("lib/**/*.ex")
    |> Path.wildcard()
    |> Enum.flat_map(&scan_file(&1, root))
    |> Enum.sort_by(&{&1.module, &1.name, &1.arity})
  end

  @doc "Scans one source file; `root` makes the recorded path relative."
  @spec scan_file(String.t(), String.t()) :: [entry]
  def scan_file(path, root) do
    path
    |> File.read!()
    |> scan_source(Path.relative_to(path, root))
  end

  @doc "Scans a source string; `file` is what the entries record as their locus."
  @spec scan_source(String.t(), String.t()) :: [entry]
  def scan_source(source, file) do
    source
    |> Code.string_to_quoted!(columns: false)
    |> SourceScan.defmodules()
    |> Enum.flat_map(&scan_module(&1, file))
  end

  defp scan_module({:defmodule, _, [{:__aliases__, _, parts}, [do: body]]}, file) do
    module = Enum.map_join(parts, ".", &Atom.to_string/1)

    {defs, use_injections, _state} =
      body
      |> statements()
      |> Enum.reduce({%{}, [], %{doc: nil, impl?: false}}, &do_statement/2)

    from_source =
      defs
      |> Enum.map(fn {{name, arity}, %{hidden?: hidden?, clauses: clauses}} ->
        %{
          module: module,
          name: name,
          arity: arity,
          hidden?: hidden?,
          version: SourceScan.definition_hash({:__block__, [], Enum.reverse(clauses)}),
          file: file
        }
      end)

    from_use =
      for {name, arity} <- use_injections,
          not Map.has_key?(defs, {name, arity}),
          do: %{
            module: module,
            name: name,
            arity: arity,
            hidden?: false,
            version: "injected",
            file: file
          }

    from_source ++ from_use
  end

  defp statements({:__block__, _, stmts}), do: stmts
  defp statements(nil), do: []
  defp statements(stmt), do: [stmt]

  # The reducer threads a small attribute state through the statements of a module body:
  # `:doc` (nil | :documented | :hidden) and `:impl?`, both consumed by the next definition.

  defp do_statement({:@, _, [{:doc, _, [false]}]}, {defs, inj, state}),
    do: {defs, inj, %{state | doc: :hidden}}

  defp do_statement({:@, _, [{:doc, _, [_]}]}, {defs, inj, state}),
    do: {defs, inj, %{state | doc: :documented}}

  defp do_statement({:@, _, [{:impl, _, [_]}]}, {defs, inj, state}),
    do: {defs, inj, %{state | impl?: true}}

  defp do_statement({:use, _, [{:__aliases__, _, parts} | _]}, {defs, inj, state}) do
    {defs, inj ++ injected(Module.concat(parts)), state}
  end

  defp do_statement({definer, _, [head | _]} = node, {defs, inj, state})
       when definer in @definers do
    {register(defs, head, node, state), inj, %{doc: nil, impl?: false}}
  end

  defp do_statement({:defdelegate, _, [head | _]} = node, {defs, inj, state}) do
    {register(defs, head, node, state), inj, %{doc: nil, impl?: false}}
  end

  # `if`/`unless` wrappers (e.g. `if Code.ensure_loaded?(Phoenix.Component)`) around
  # definitions are walked as if they were the module body.
  defp do_statement({cond_form, _, [_, [do: body]]}, acc) when cond_form in [:if, :unless] do
    body |> statements() |> Enum.reduce(acc, &do_statement/2)
  end

  defp do_statement(_other, acc), do: acc

  # What a `use`d module injects: `GenServer`'s own, and otherwise whatever a module that
  # generates its definitions declares through a zero-arity `injected` export (spec/12 §2).
  defp injected(GenServer), do: [child_spec: 1]

  defp injected(mod) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :injected, 0),
      do: mod.injected(),
      else: []
  end

  defp register(defs, head, node, state) do
    {name, args} = name_and_args(head)
    full = length(args)
    defaults = Enum.count(args, &match?({:\\, _, _}, &1))

    Enum.reduce((full - defaults)..full//1, defs, fn arity, defs ->
      hidden? = hidden?(state, arity == full)

      Map.update(defs, {name, arity}, %{hidden?: hidden?, clauses: [node]}, fn entry ->
        %{entry | clauses: [node | entry.clauses]}
      end)
    end)
  end

  # `@doc false` hides the definition; so does `@impl` without an explicit `@doc`. Both
  # cover every arity a default argument generates, as `Code.fetch_docs/1` reports.
  defp hidden?(%{doc: :hidden}, _full?), do: true
  defp hidden?(%{impl?: true, doc: doc}, _full?) when doc != :documented, do: true
  defp hidden?(_state, _full?), do: false

  defp name_and_args({:when, _, [head | _]}), do: name_and_args(head)
  defp name_and_args({name, _, args}) when is_atom(name) and is_list(args), do: {name, args}
  defp name_and_args({name, _, nil}) when is_atom(name), do: {name, []}
end
