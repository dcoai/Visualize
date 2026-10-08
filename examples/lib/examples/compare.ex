defmodule Examples.Compare do
  @moduledoc """
  A chart run headless through each backend for a fixed count of ticks (spec/14 §12.6,
  #322): the mean render time and the bytes per frame, beside the static bytes — the
  measurement of §12.6's performance page, for any chart of the gallery.
  """

  alias Examples.Frames

  @type row :: %{
          backend: Frames.backend(),
          ticks: pos_integer(),
          avg_render_us: float(),
          avg_bytes: float(),
          static_bytes: non_neg_integer()
        }

  @type cost :: :light | :heavy

  @doc """
  A chart's cost class (spec/14 §12.6, #469): `:heavy` for a chart module whose
  `cost/0` says so — a chart whose purpose is to be expensive, as *Downsampling*'s
  unreduced 50,000 rows are — and `:light` for every other. The comparison still runs a
  heavy chart; the class is what the suite reads, so it compares the light charts in
  full, holds a heavy one comparable at one tick, and holds each class's still render to
  its own budget.
  """
  @spec cost(module()) :: cost()
  def cost(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :cost, 0),
      do: module.cost(),
      else: :light
  end

  @doc """
  One row per backend of `module`: `ticks` frames at `opts_for.(tick)`, each timed, the
  compiled chart of the canvas prepared once outside the timing (it is compiled once per
  run, not per frame).
  """
  @spec run(module(), (non_neg_integer() -> keyword()), pos_integer()) :: [row()]
  def run(module, opts_for, ticks) when ticks > 0 do
    for backend <- Frames.backends(module) do
      state = Frames.prepare(module, opts_for.(0), backend)

      {{times, bytes}, _state} =
        Enum.map_reduce(0..(ticks - 1), state, fn tick, state ->
          {us, {frame, state}} =
            :timer.tc(fn -> Frames.frame(module, opts_for.(tick), backend, state) end)

          {{us, frame.bytes}, state}
        end)
        |> then(fn {pairs, state} -> {Enum.unzip(pairs), state} end)

      %{
        backend: backend,
        ticks: ticks,
        avg_render_us: Enum.sum(times) / ticks,
        avg_bytes: Enum.sum(bytes) / ticks,
        static_bytes: byte_size(Frames.static(state))
      }
    end
  end
end
