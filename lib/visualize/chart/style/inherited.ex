defmodule Visualize.Chart.Style.Inherited do
  @moduledoc false
  # What an element inherits from its containers (spec/14 §3.8, §3.9, D-174): the style
  # their defaults lay under its own, and the theme the units in either are measured with.
  # `Visualize.Chart.Style.Defaults.at/3` builds it; `Visualize.Chart.Style.node/4` lays a
  # stack over it.

  defstruct style: %{}, theme: nil

  @type t :: %__MODULE__{style: map(), theme: Visualize.Theme.t() | nil}
end
