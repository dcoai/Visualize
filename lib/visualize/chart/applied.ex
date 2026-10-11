defmodule Visualize.Chart.Applied do
  @moduledoc """
  A design applied to its data (spec/14 §7.3, §14.10).

  `Visualize.Chart.apply/2` is the only constructor: `chart` is the concrete
  `%Visualize.Chart{}` — no variable and no schema fact anywhere in it, `vars` empty, the
  slot declarations kept as the data contract; `sources` are the bound sources by slot
  name, each as the pool gave it (a delivery as the source it carries); `frame` is the
  `%Visualize.Chart.Frame{}` realised over them, whose `Visualize.Chart.Frame.scales/1` is
  the escape hatch, and `frames` every frame by name. `schemas`, `versions` and `cache`
  are what the schema step found (§7.4): the schema of each slot that has one, the
  schema version each slot's delivery named, and the schema cache with whatever
  `describe:` added, which the caller keeps for its next application.
  `Visualize.Chart.render/2` draws it. The struct has no map or JSON form: it holds the
  data the design was applied to, and a design, its fragments and a binding are what is
  stored (D-65).
  """

  alias Visualize.Chart
  alias Visualize.Chart.Frame
  alias Visualize.Data.Schema
  alias Visualize.Data.Schema.Cache

  @enforce_keys [:chart, :sources, :frame]
  defstruct [
    :chart,
    :sources,
    :frame,
    frames: %{},
    schemas: %{},
    versions: %{},
    cache: %Cache{}
  ]

  @type t :: %__MODULE__{
          chart: Chart.t(),
          sources: %{atom() => term()},
          frame: Frame.t(),
          frames: %{atom() => Frame.t()},
          schemas: %{atom() => Schema.t()},
          versions: %{atom() => String.t() | nil},
          cache: Cache.t()
        }
end
