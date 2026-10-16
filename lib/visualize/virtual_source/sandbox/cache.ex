defmodule Visualize.VirtualSource.Sandbox.Cache do
  @moduledoc """
  Compiled functions by source (spec/08 §10.5.3, D-194): a **value**, held by whatever owns
  the functions — a board's engine, the builder — not a process or a table, as the schema
  cache is (spec/08 §10.3).

  An entry is keyed by the SHA-256 of the source, the arity and the fields it was checked
  against, and holds the compilation's answer, a refusal included, so a source is checked
  and compiled once. A compilation the runner cut short (`:timeout`, `:memory`) is not
  kept, since it says nothing about the source. The cache never evicts.
  """

  alias Visualize.VirtualSource.Sandbox

  defstruct entries: %{}

  @type t :: %__MODULE__{entries: map()}

  @doc "The empty cache."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  `compile(cache, source, opts)`: `{:ok, compiled, cache}` or `{:error, faults, cache}`,
  as `Visualize.VirtualSource.Sandbox.compile/2` answers, compiled at most once per
  source, arity and fields.
  """
  @spec compile(t(), String.t(), keyword()) ::
          {:ok, Sandbox.Compiled.t(), t()} | {:error, [Sandbox.fault(), ...], t()}
  def compile(%__MODULE__{} = cache, source, opts \\ []) when is_binary(source) do
    key = {Sandbox.hash(source), Keyword.get(opts, :arity, 1), fields(opts[:fields])}

    case Map.fetch(cache.entries, key) do
      {:ok, {:ok, compiled}} ->
        {:ok, compiled, cache}

      {:ok, {:error, faults}} ->
        {:error, faults, cache}

      :error ->
        answer = Sandbox.compile(source, opts)

        cache =
          if keep?(answer),
            do: %{cache | entries: Map.put(cache.entries, key, answer)},
            else: cache

        case answer do
          {:ok, compiled} -> {:ok, compiled, cache}
          {:error, faults} -> {:error, faults, cache}
        end
    end
  end

  defp fields(nil), do: nil
  defp fields(fields), do: fields |> Enum.map(&to_string/1) |> Enum.sort() |> Enum.uniq()

  defp keep?({:error, [{nil, {:compile, {_kind, _detail}}}]}), do: false
  defp keep?(_answer), do: true
end
