defmodule Visualize.Chart.Validator.Generators do
  @moduledoc false
  # The validator's view of a generator call (spec/14 §3.13, D-177): its shape, its name
  # against the registry the read was given, and its arguments.
  #
  # A name no registered module defines is `{:undeclared, :generator, name}`; a name defined
  # at another arity `{:arity, :generator, name, n}`, `n` the arguments the design gives —
  # the context is always the generator's last parameter. Where the registry is not known
  # (`:unknown`, a fragment read alone) the name is not checked, as a fragment's references
  # are not.

  @doc false
  # The faults of a generator's style result at render (spec/14 §3.13, D-177): checked as a
  # `styles` entry is, against the style names the frame knows and its theme's color names.
  # A generator in it is a fault: a result is what a generator computed, never another call.
  @spec style(term(), [atom()], [atom()]) :: [{list(), term()}]
  def style(value, styles, colors) do
    known = %{styles: MapSet.new(styles), colors: MapSet.new(colors), generators: :refused}
    Visualize.Chart.Validator.check_open(Visualize.Chart.Schema.style_entry(), value, known)
  end

  @doc false
  # Whether a term holds a generator call anywhere: a design without one never builds the
  # registry, so a host's configured modules are not loaded to read it.
  @spec present?(term()) :: boolean()
  def present?({:generate, _name, _args}), do: true
  def present?(%_{}), do: false
  def present?(map) when is_map(map), do: Enum.any?(map, fn {_k, v} -> present?(v) end)
  def present?(list) when is_list(list), do: Enum.any?(list, &present?/1)
  def present?(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> present?()
  def present?(_value), do: false

  @doc false
  # The faults of `call` at `path`: `arg` answers each argument's faults at its own path.
  @spec faults(term(), list(), map() | :unknown, (term(), list() -> [{list(), term()}])) ::
          [{list(), term()}]
  def faults({:generate, name, args}, path, registry, arg)
      when is_atom(name) and name not in [nil, true, false] and is_list(args) do
    named = name(name, length(args), path, registry)

    arguments =
      args
      |> Enum.with_index()
      |> Enum.flat_map(fn {value, i} -> arg.(value, path ++ [i]) end)

    named ++ arguments
  end

  def faults(_call, path, _registry, _arg), do: [{path, {:type, :generator}}]

  defp name(_name, _n, _path, :unknown), do: []

  defp name(name, n, path, registry) when is_map(registry) do
    cond do
      Map.has_key?(registry, {name, n + 1}) ->
        []

      Enum.any?(Map.keys(registry), &match?({^name, _}, &1)) ->
        [{path, {:arity, :generator, name, n}}]

      true ->
        [{path, {:undeclared, :generator, name}}]
    end
  end
end
