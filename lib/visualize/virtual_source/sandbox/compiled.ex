defmodule Visualize.VirtualSource.Sandbox.Compiled do
  @moduledoc """
  A stored function checked and compiled once (spec/08 §10.5.3, D-194): `hash`, the
  SHA-256 of its source; `fun`, the closure; `arity`; and `warnings`, the compiler's,
  each `{line, message}`, printed nowhere.
  """

  @enforce_keys [:hash, :fun, :arity]
  defstruct [:hash, :fun, :arity, warnings: []]

  @type t :: %__MODULE__{
          hash: String.t(),
          fun: function(),
          arity: non_neg_integer(),
          warnings: [{pos_integer() | nil, String.t()}]
        }
end
