defmodule Visualize.Board.State do
  @moduledoc """
  A cell's state, decided and drawn (spec/15 §8.4, D-146).

  A cell is always in one state, and every state is drawn deliberately: never a blank
  chart, a crash or a host's spinner. `of/3` decides the state of a cell's slots at the
  board's now; `render/3` draws it as the whole cell, where there is no chart, and
  `banner/3` as one line across the top of a chart, where the last data stays readable.
  Each state has a **role** (spec/08 §7.5, D-135): its colour is the drawing's accent and
  its cue's glyph (spec/14 §21.7, D-142) stands beside the words, so a state reads in
  greyscale as well. Both drawings are in `:css` mode, so a stylesheet themes them as it
  themes the charts.

  | State | Role | Words |
  |---|---|---|
  | `{:crashed, reason}` | `:bad` | Crashed, restarting |
  | `{:down, reason}` | `:bad` | Feed down and the reason |
  | `{:invalid, errors}` | `:bad` | Wrong binding and the first fault |
  | `:loading` | `:info` | Loading… |
  | `:no_data` | `:neutral` | No data yet |
  | `{:stale, age}` | `:warning` | Stale and the age |
  | `:capped` | `:info` | Capped: part of the window |
  | `:live` | — | — |

  ## Examples

      iex> Visualize.Board.State.words({:stale, 330})
      "Stale: 5m30s old"
      iex> Visualize.Board.State.role(:no_data)
      :neutral
      iex> Visualize.Board.State.banner(:live, Visualize.Theme.default(), 300)
      nil

  """

  alias Visualize.Chart.Validator
  alias Visualize.Data.{Delivery, Schema, Table}
  alias Visualize.Feed
  alias Visualize.{Format, Render, Theme}
  alias Visualize.IR.Element
  alias Visualize.Shape.Symbol

  @type t ::
          :loading
          | :no_data
          | :live
          | :capped
          | {:stale, number() | nil}
          | {:down, term()}
          | {:invalid, [Validator.error(), ...]}
          | {:crashed, term()}

  @typedoc "What a cell knows of one slot: its delivery, the delivery's schema and the feed's status."
  @type slot :: %{
          delivery: Delivery.t() | nil,
          schema: Schema.t() | nil,
          status: Visualize.Feed.Monitor.status()
        }

  @banner_height 22

  @doc false
  # The height of `banner/3`'s root, which an export lays out (spec/15 §12.1).
  def banner_height, do: @banner_height

  # -- deciding ---------------------------------------------------------------------------

  @doc """
  The state of a cell's slots at `now` (spec/15 §8.4), the first that holds of: down (a
  slot's feed is down), loading (a slot has no delivery yet), no data (every delivery
  empty), stale (a feed the monitor calls stale, or a newest `DateTime` reading older than
  `stale_after` seconds at `now`), capped (a delivery is `capped`), and live. A cell with
  no slots is live. Crashed is the board's, which draws it for a cell that cannot.
  """
  @spec of(%{atom() => slot()}, DateTime.t() | nil, number() | nil) :: t()
  def of(slots, now, stale_after) when is_map(slots) do
    slots = slots |> Enum.sort() |> Enum.map(&elem(&1, 1))

    cond do
      down = Enum.find_value(slots, &down/1) -> {:down, down}
      Enum.any?(slots, &(&1.delivery == nil)) -> :loading
      slots != [] and Enum.all?(slots, &(Table.rows(&1.delivery) == [])) -> :no_data
      stale = stale(slots, now, stale_after) -> stale
      Enum.any?(slots, & &1.delivery.capped) -> :capped
      true -> :live
    end
  end

  defp down(%{status: {:down, reason}}), do: reason
  defp down(_slot), do: nil

  defp stale(slots, now, stale_after) do
    age = age(slots, now)
    monitor? = Enum.any?(slots, &(&1.status == :stale))

    cond do
      is_number(stale_after) and is_number(age) and age > stale_after -> {:stale, age}
      monitor? -> {:stale, age}
      true -> nil
    end
  end

  # The age in seconds of the newest reading of any slot whose time field holds
  # `DateTime`s, at `now`; `nil` when none does.
  defp age(_slots, nil), do: nil

  defp age(slots, %DateTime{} = now) do
    slots
    |> Enum.flat_map(&newest/1)
    |> Enum.max(DateTime, fn -> nil end)
    |> case do
      nil -> nil
      newest -> DateTime.diff(now, newest, :microsecond) / 1_000_000
    end
  end

  defp newest(%{delivery: %Delivery{} = delivery, schema: %Schema{} = schema}) do
    case Feed.time_field(schema) do
      nil ->
        []

      time ->
        for row <- Table.rows(delivery), %DateTime{} = t <- [Table.get(row, time)], do: t
    end
  end

  defp newest(_slot), do: []

  # -- naming -------------------------------------------------------------------------------

  @doc "A state's role (spec/08 §7.5), whose colour and glyph draw it; `nil` for `:live`."
  @spec role(t()) :: Theme.slot() | nil
  def role({:crashed, _reason}), do: :bad
  def role({:down, _reason}), do: :bad
  def role({:invalid, _errors}), do: :bad
  def role(:loading), do: :info
  def role(:no_data), do: :neutral
  def role({:stale, _age}), do: :warning
  def role(:capped), do: :info
  def role(:live), do: nil

  @doc "A state's words, as the drawings print them; `\"\"` for `:live`."
  @spec words(t()) :: String.t()
  def words({:crashed, _reason}), do: "Crashed, restarting"
  def words({:down, reason}), do: "Feed down: " <> reason(reason)
  def words({:invalid, [error | _]}), do: "Wrong binding: " <> Validator.format(error)
  def words(:loading), do: "Loading…"
  def words(:no_data), do: "No data yet"
  def words({:stale, nil}), do: "Stale"
  def words({:stale, age}), do: "Stale: #{Format.duration(round(age))} old"
  def words(:capped), do: "Capped: part of the window"
  def words(:live), do: ""

  @doc false
  # A down reason as the words print it; a snapshot keeps it so (spec/15 §12.3).
  def reason({:unbound, slot}), do: "#{inspect(slot)} is not bound"
  def reason({:no_feed, feed}), do: "no feed #{inspect(feed)}"
  def reason({:apply, [error | _]}), do: Validator.format(error)
  def reason(reason) when is_binary(reason), do: reason
  def reason(reason), do: inspect(reason, limit: 5, printable_limit: 60)

  # -- drawing ------------------------------------------------------------------------------

  @doc """
  A state drawn as the whole cell (spec/15 §8.4): an accessible SVG root of `{w, h}`
  titled with the words, the theme's `surface` filling it inside a frame of the role's
  colour, and the role's glyph and the words centred in the theme's `text`. `:live` is
  drawn as the empty surface.
  """
  @spec render(t(), Theme.t(), {number(), number()}) :: String.t()
  def render(state, %Theme{} = theme, {w, h}) do
    role = role(state)
    words = words(state)

    accent =
      if role, do: Theme.resolve(theme, role, :css), else: Theme.resolve(theme, :grid, :css)

    cx = w / 2
    cy = h / 2
    size = Theme.resolve(theme, :label_size, :literal)

    children =
      [
        Element.rect(1, 1, max(w - 2, 0), max(h - 2, 0), %{
          class: "vis-cell-state-frame",
          fill: Theme.resolve(theme, :surface, :css),
          stroke: accent,
          stroke_width: 2,
          rx: 4
        })
      ] ++
        if(role,
          do: [
            glyph(role, accent, cx, cy - size, 400),
            Element.text(words, cx, cy + size, %{
              class: "vis-cell-state-words",
              fill: Theme.resolve(theme, :text, :css),
              font_family: Theme.resolve(theme, :font_family, :css),
              font_size: Theme.resolve(theme, :label_size, :css),
              text_anchor: :middle
            })
          ],
          else: []
        )

    w
    |> Element.root(h, title: title(state), responsive: true, children: children)
    |> Element.set_attrs(%{class: "vis-cell-state", data_vis_state: name(state)})
    |> Render.to_string()
  end

  @doc """
  A state drawn as a banner across the top of a chart `width` wide (spec/15 §8.4): an SVG
  root one line high, the role's colour behind the role's glyph and the words in the
  contrast ink of `Visualize.Theme.ink/2`. `nil` for `:live`, which needs none.
  """
  @spec banner(t(), Theme.t(), number()) :: String.t() | nil
  def banner(:live, _theme, _width), do: nil

  def banner(state, %Theme{} = theme, width) do
    role = role(state)
    colour = Theme.resolve(theme, role, :literal)
    ink = Theme.ink(theme, colour)
    h = @banner_height

    children = [
      Element.rect(0, 0, width, h, %{
        class: "vis-cell-banner-ground",
        fill: Theme.resolve(theme, role, :css)
      }),
      glyph(role, ink, h / 2 + 4, h / 2, 120),
      Element.text(words(state), h + 6, h / 2, %{
        class: "vis-cell-banner-words",
        fill: ink,
        font_family: Theme.resolve(theme, :font_family, :css),
        font_size: Theme.resolve(theme, :font_size, :css),
        dominant_baseline: :central
      })
    ]

    width
    |> Element.root(h, title: title(state), children: children)
    |> Element.set_attrs(%{class: "vis-cell-banner", data_vis_state: name(state)})
    |> Render.to_string()
  end

  @doc ~s(A state's name, the `data-vis-state` its drawings carry: `"stale"`, `"down"`, …)
  @spec name(t()) :: String.t()
  def name({tag, _detail}), do: Atom.to_string(tag)
  def name(state) when is_atom(state), do: Atom.to_string(state)

  defp title(:live), do: "Live"
  defp title(state), do: words(state)

  # The role's cue glyph (spec/14 §21.7) at a point, in the role's colour.
  defp glyph(role, colour, x, y, area) do
    %{glyph: glyph} = Theme.cue(role)
    path = Symbol.new() |> Symbol.type(glyph) |> Symbol.size(area) |> Symbol.generate_path(nil)

    path
    |> Element.path(%{class: "vis-cell-state-glyph", fill: colour, stroke: :none})
    |> Element.translate(x, y)
  end
end
