defmodule Visualize.Chart.Var do
  @moduledoc """
  A variable in a design (spec/14 §7.1).

  `Visualize.Chart.var/1` builds one. The term is allowed wherever a value can appear —
  a style value, a text part, a channel, a whole node — and resolves at application. It
  carries only the name: the default is declared once under the design's `vars` (D-59).

  ## Examples

      iex> Visualize.Chart.var(:unit)
      %Visualize.Chart.Var{name: :unit}

  """

  @enforce_keys [:name]
  defstruct [:name]

  @type t :: %__MODULE__{name: atom()}
end
