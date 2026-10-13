if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Axes do
    @moduledoc """
    Axes ticked where their scale is (spec/14 §18.16, #373): the *axes* section of a mark's
    page and of a scale's — one row per position scale, a box per side the scale can stand
    on, a grid box, and a link to each axis's own page.

    `rows/2` reads the design; the builder writes what a tick asks for (`toggle_axis`,
    `toggle_grid`) through the ownership rule of §18.15.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Fragment

    @sides %{x: [:bottom, :top], y: [:left, :right]}

    @typedoc "One row: the scale, its sides with the axis standing there, and its grid."
    @type row :: %{
            scale: atom(),
            frame: atom(),
            sides: [%{side: atom(), word: String.t(), index: non_neg_integer() | nil}],
            grid: boolean(),
            first: non_neg_integer() | nil
          }

    attr(:rows, :list, required: true, doc: "the rows, as `rows/2` gives them")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the section's events")

    @doc "Renders the axes section."
    def section(assigns) do
      ~H"""
      <details class="vis-builder-section vis-builder-axes" open>
        <summary class="vis-builder-section-title" title="the axes that measure this">axes</summary>
        <div :for={row <- @rows} class="vis-builder-axes-row" data-builder-axes={row.scale}>
          <span class="vis-builder-key">{row.scale}</span>
          <label :for={side <- row.sides} class="vis-builder-axes-side">
            <input
              type="checkbox"
              checked={side.index != nil}
              phx-click="toggle_axis"
              phx-value-scale={row.scale}
              phx-value-side={side.side}
              phx-value-frame={row.frame}
              phx-target={@target}
            />
            {side.word}
          </label>
          <label :if={row.first != nil} class="vis-builder-axes-side">
            <input
              type="checkbox"
              checked={row.grid}
              phx-click="toggle_grid"
              phx-value-scale={row.scale}
              phx-value-frame={row.frame}
              phx-target={@target}
            />
            grid
          </label>
          <button
            :for={side <- row.sides}
            :if={side.index != nil}
            type="button"
            class="vis-builder-axes-link"
            title={"frames.#{row.frame}.axes[#{side.index}]: ticks, format, unit …"}
            phx-click="select_node"
            phx-value-node={"frames.#{row.frame}.axes[#{side.index}]"}
            phx-target={@target}
          >{side.word} axis …</button>
        </div>
      </details>
      """
    end

    @doc """
    For each position scale named, the sides an axis of it can stand on — *bottom* and
    *top* for `x`, *left* and *right* for `y`, one nominal side, *shown*, for a polar
    `angle` (`bottom`) or `r` (`top`) — each with the index of the axis standing there in
    `frame.axes`, the first axis of the scale and whether it draws the grid. The axes are
    those of `frame` — the mark's or the scale's own (#615) — and of the design's frame
    when none is given.

        iex> design = %{frames: %{main: %{axes: [%{scale: :x, side: :bottom, grid: true}, %{scale: :y, side: :left}]}}}
        iex> [x, y] = Visualize.Chart.Builder.Axes.rows(design, [:x, :y])
        iex> {x.grid, Enum.map(x.sides, &{&1.side, &1.index}), y.grid, Enum.map(y.sides, &{&1.side, &1.index})}
        {true, [bottom: 0, top: nil], false, [left: 1, right: nil]}
        iex> [r] = Visualize.Chart.Builder.Axes.rows(design, [:r])
        iex> {r.first, r.sides}
        {nil, [%{side: :top, word: "shown", index: nil}]}
    """
    @spec rows(map(), [atom()], atom() | nil) :: [row()]
    def rows(design, scales, frame \\ nil) do
      frame = frame || Fragment.frame_of(design, nil)

      axes =
        design
        |> get_in([:frames, frame, :axes])
        |> List.wrap()
        |> Enum.with_index()

      for scale <- scales do
        mine = for {%{scale: ^scale} = axis, i} <- axes, do: {axis, i}
        first = mine |> List.first() |> then(&(&1 && elem(&1, 1)))

        sides =
          for {side, word} <- sides(scale) do
            index =
              Enum.find_value(mine, fn {axis, i} -> if Map.get(axis, :side) == side, do: i end)

            %{side: side, word: word, index: index}
          end

        %{
          scale: scale,
          frame: frame,
          sides: sides,
          first: first,
          grid: Enum.any?(mine, fn {axis, _} -> Map.get(axis, :grid, false) == true end)
        }
      end
    end

    defp sides(:x), do: Enum.map(@sides.x, &{&1, to_string(&1)})
    defp sides(:y), do: Enum.map(@sides.y, &{&1, to_string(&1)})
    defp sides(:angle), do: [{:bottom, "shown"}]
    defp sides(_r), do: [{:top, "shown"}]
  end
end
