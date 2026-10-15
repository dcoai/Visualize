defmodule Visualize.Chart.Validator.Defaults do
  @moduledoc false
  # The validator's view of a composite's defaults (spec/14 §3.8, §19.6, #651, D-174): a
  # layer or a group of the builder's tree carries them beside its `uses` and `vars`, and
  # they are a `:defaults` node like the design's, checked as one with nothing around them.

  @doc false
  # The faults of a composite's `defaults`, under `[:composite, :defaults | path]`; none
  # when it declares none.
  @spec composite(map(), (map(), atom() -> :ok | {:error, list()})) :: [{list(), term()}]
  def composite(%{defaults: defaults}, validate) do
    case validate.(%{defaults: defaults}, :defaults) do
      :ok -> []
      {:error, errors} -> Enum.map(errors, fn {path, reason} -> {[:composite | path], reason} end)
    end
  end

  def composite(_composite, _validate), do: []
end
