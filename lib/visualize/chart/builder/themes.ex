if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Themes do
    @moduledoc """
    The theme mode's editor (spec/14 §20, D-139): the theme a chart holds, as a node the
    builder writes and as the `%Visualize.Theme{}` it draws as, and the panel that edits it.

    The mode is the builder's shape while the open chart is a theme. Its writes are the
    theme node of one site — the selected site, or the first of the chart that carries a
    theme — and every one goes through `change/3`, a pure reading of one control's value,
    so the panel and the tests agree on what a control means. The theme is drawn unchecked
    — its fields over the default theme, no contract checked — so a theme that breaks a
    contract still draws while a person fixes it, and the validity section says what breaks.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Builder.{Stack, Store, ThemeRamps}
    alias Visualize.Chart.Theme, as: Document
    alias Visualize.Chart.Use
    alias Visualize.{Color, Theme}
    alias Visualize.Color.Vision

    @chrome [:background, :surface, :text, :axis, :grid]
    @sizes [:font_size, :label_size, :title_size]
    @fields [:name, :series | @chrome] ++ [:ramps, :colors, :font_family | @sizes]

    attr(:id, :string, required: true, doc: "the panel's id")

    attr(:node, :map,
      required: true,
      doc: "the theme node being edited, as `editable/2` gives it"
    )

    attr(:theme, :any, required: true, doc: "the `%Visualize.Theme{}` the node draws as")
    attr(:faults, :list, default: [], doc: "the theme's faults, each a line a person reads")
    attr(:derive, :list, default: [], doc: "the themes to derive from, `{label, value}` each")

    attr(:vision, :atom,
      default: :none,
      doc: "the deficiency the ramps and the sheet are seen under"
    )

    attr(:target, :any, default: nil, doc: "the `phx-target` of the panel's events")

    @doc """
    Renders the theme editor (spec/14 §20.2, §20.4, §20.5): *derive from* and the *vision*
    select, then `<form class="vis-builder-theme">` of sections — the theme's name, the
    series, the chrome, the fonts, the ramps and the roles — then the theme's validity.
    """
    def panel(assigns) do
      assigns =
        assign(assigns,
          series: Enum.with_index(assigns.theme.series),
          chrome: Enum.map(@chrome, &{&1, Map.fetch!(assigns.theme, &1)}),
          sizes: Enum.map(@sizes, &{&1, Map.fetch!(assigns.theme, &1)})
        )

      ~H"""
      <div id={@id} class="vis-builder-theme-panel">
        <form id={@id <> "-derive"} class="vis-builder-theme-derive" phx-submit="theme_derive" phx-target={@target}>
          <label class="vis-builder-control-label" for={@id <> "-derive-from"}>derive from</label>
          <select id={@id <> "-derive-from"} name="from">
            <option :for={{label, value} <- @derive} value={value}>{label}</option>
          </select>
          <button type="submit" class="vis-builder-theme-derive-button" title="take every value of that theme, keep this theme's name">Derive</button>
        </form>
        <form id={@id <> "-vision"} class="vis-builder-theme-vision" phx-change="theme_vision" phx-submit="submitted" phx-target={@target}>
          <label class="vis-builder-control-label" for={@id <> "-vision-kind"}>seen with</label>
          <select id={@id <> "-vision-kind"} name="vision">
            <option :for={kind <- [:none | Vision.deficiencies()]} value={kind} selected={kind == @vision}>
              {if kind == :none, do: "normal vision", else: kind}
            </option>
          </select>
        </form>
        <form id={@id <> "-form"} class="vis-builder-theme" phx-change="theme_edit" phx-submit="submitted" phx-target={@target}>
          <fieldset class="vis-builder-theme-section">
            <legend>theme</legend>
            <label class="vis-builder-theme-row">
              <span class="vis-builder-control-label">name</span>
              <input type="text" name="name" value={to_string(@theme.name)} />
            </label>
          </fieldset>
          <fieldset class="vis-builder-theme-section vis-builder-theme-series">
            <legend>series</legend>
            <span :for={{colour, i} <- @series} class="vis-builder-theme-swatch">
              <input type="color" name={"series.#{i}"} value={hex(colour)} title={colour} aria-label={"series #{i + 1}"} />
              <button
                :if={length(@series) > 1}
                type="button"
                class="vis-builder-theme-remove"
                title={"remove series #{i + 1}"}
                aria-label={"remove series #{i + 1}"}
                phx-click="theme_series_remove"
                phx-value-index={i}
                phx-target={@target}
              >×</button>
            </span>
            <button type="button" class="vis-builder-add" title="add a series colour" aria-label="add a series colour" phx-click="theme_series_add" phx-target={@target}>+</button>
          </fieldset>
          <fieldset class="vis-builder-theme-section">
            <legend>chrome</legend>
            <label :for={{slot, colour} <- @chrome} class="vis-builder-theme-row">
              <span class="vis-builder-control-label">{slot}</span>
              <input type="color" name={to_string(slot)} value={hex(colour)} title={colour} />
            </label>
          </fieldset>
          <fieldset class="vis-builder-theme-section">
            <legend>fonts</legend>
            <label class="vis-builder-theme-row">
              <span class="vis-builder-control-label">family</span>
              <input type="text" name="font_family" value={@theme.font_family} style={"font-family: #{@theme.font_family}"} />
            </label>
            <label :for={{key, size} <- @sizes} class="vis-builder-theme-row">
              <span class="vis-builder-control-label">{String.replace(to_string(key), "_", " ")}</span>
              <input type="number" name={to_string(key)} value={size} min="1" step="1" />
            </label>
          </fieldset>
          <ThemeRamps.section theme={@theme} vision={@vision} target={@target} />
        </form>
        <section class="vis-builder-theme-validity">
          <p :if={@faults == []} class="vis-builder-theme-valid">a valid theme — Save to library keeps it</p>
          <ul :if={@faults != []} class="vis-builder-errors">
            <li :for={line <- @faults} class="vis-builder-error">{line}</li>
          </ul>
        </section>
      </div>
      """
    end

    # A colour input takes `#rrggbb` and nothing else; a colour stored in another syntax is
    # shown as its hex, and one that does not read as black, its title saying what it is.
    defp hex(value) do
      if readable?(value),
        do: value |> Color.parse() |> Color.to_hex() |> String.slice(0, 7),
        else: "#000000"
    end

    # -- the theme as the editor holds it -------------------------------------------

    @doc """
    The theme a site holds as the node the editor writes (spec/14 §20.1): a name as the
    whole node of the theme it names — built-in, else the store's — so an edit changes one
    value of the theme a person was looking at; a map as it is; anything else an empty node.
    """
    @spec editable(term(), Store.store() | nil) :: map()
    def editable(value, store) when is_atom(value) and value != nil do
      value |> effective(store) |> Document.node()
    end

    def editable(%{} = node, _store) when not is_struct(node), do: node
    def editable(_value, _store), do: %{}

    @doc """
    The `%Visualize.Theme{}` a design's `theme` value draws as (spec/14 §20.3): a built-in
    name, the store's theme of that name, or a map over the default theme — built unchecked,
    so a theme that breaks a contract still draws. Anything else is the default theme.
    """
    @spec effective(term(), Store.store() | nil) :: Theme.t()
    def effective(name, store) when is_atom(name) and name != nil do
      with nil <- Theme.builtin(name),
           {:ok, theme} <- stored(store, name) do
        theme
      else
        %Theme{} = builtin -> builtin
        _none -> Theme.default()
      end
    end

    def effective(%{} = node, _store) when not is_struct(node) do
      # A theme of its own declares no counterpart unless the node says so (spec/08 §7.3).
      Theme.build(%{Theme.default() | dark: nil}, Map.take(node, @fields))
    end

    def effective(_value, _store), do: Theme.default()

    defp stored(nil, _name), do: :error
    defp stored(store, name), do: Store.theme(store, name)

    @doc """
    The node with one control's value written (spec/14 §20.2), or `:error` for a value that
    does not read — a blank, a colour `Visualize.Color.parse/1` cannot read, a size that is
    not a positive number — so the node is left as it was.

        iex> Visualize.Chart.Builder.Themes.change(%{}, "axis", "#555555")
        {:ok, %{axis: "#555555"}}

        iex> Visualize.Chart.Builder.Themes.change(%{series: ["#111111", "#222222"]}, "series.1", "#333333")
        {:ok, %{series: ["#111111", "#333333"]}}

        iex> Visualize.Chart.Builder.Themes.change(%{}, "font_size", "eleven")
        :error
    """
    @spec change(map(), String.t(), String.t()) :: {:ok, map()} | :error
    def change(node, "name", value) do
      case String.trim(value) do
        "" -> :error
        name -> {:ok, Map.put(node, :name, String.to_atom(name))}
      end
    end

    def change(node, "series." <> index, value) do
      series = Map.get(node, :series, Theme.default().series)

      with {i, ""} <- Integer.parse(index),
           true <- i >= 0 and i < length(series),
           {:ok, colour} <- colour(value) do
        {:ok, Map.put(node, :series, List.replace_at(series, i, colour))}
      else
        _ -> :error
      end
    end

    def change(node, "ramps." <> rest, value) do
      with [name, index] <- String.split(rest, ".", parts: 2),
           ramp when ramp != nil <- ramp_named(name),
           {i, ""} <- Integer.parse(index),
           anchors = anchors(node, ramp),
           true <- i >= 0 and i < length(anchors),
           {:ok, colour} <- colour(value) do
        {:ok, ramp_put(node, ramp, List.replace_at(anchors, i, colour))}
      else
        _ -> :error
      end
    end

    # A status role is set by the colour at its fixed position: the anchor that stands there
    # (spec/14 §20.4); `:warning` has none on an even ramp. `:info` and `:neutral` are colours
    # of the theme's color table (spec/08 §7.1, #663).
    def change(node, "roles." <> role, value) when role in ["info", "neutral"] do
      with {:ok, colour} <- colour(value) do
        colors = node |> Map.get(:colors, %{}) |> Map.put(String.to_existing_atom(role), colour)
        {:ok, Map.put(node, :colors, colors)}
      end
    end

    def change(node, "roles." <> role, value) when role in ["good", "warning", "bad"] do
      anchors = anchors(node, :status)
      n = length(anchors)

      at =
        case role do
          "good" -> 0
          "bad" -> n - 1
          "warning" when rem(n, 2) == 1 -> div(n, 2)
          "warning" -> nil
        end

      with true <- at != nil, {:ok, colour} <- colour(value) do
        {:ok, ramp_put(node, :status, List.replace_at(anchors, at, colour))}
      else
        _ -> :error
      end
    end

    def change(node, "font_family", value) do
      case String.trim(value) do
        "" -> :error
        family -> {:ok, Map.put(node, :font_family, family)}
      end
    end

    def change(node, field, value) do
      cond do
        slot = Enum.find(@chrome, &(Atom.to_string(&1) == field)) ->
          with {:ok, colour} <- colour(value), do: {:ok, Map.put(node, slot, colour)}

        key = Enum.find(@sizes, &(Atom.to_string(&1) == field)) ->
          with {:ok, size} <- size(value), do: {:ok, Map.put(node, key, size)}

        true ->
          :error
      end
    end

    defp colour(value) do
      trimmed = String.trim(value)
      if readable?(trimmed), do: {:ok, trimmed}, else: :error
    end

    @doc false
    # Whether a value is a colour `Visualize.Color.parse/1` reads. A hex with a digit that is
    # not one raises there (spec/08 §1.2), so it is refused here first: an editor reads what
    # a person typed, and a typo is a value left unchanged, not a crash.
    @spec readable?(term()) :: boolean()
    def readable?("#" <> digits = value) do
      String.match?(digits, ~r/\A[0-9a-fA-F]+\z/) and Color.parse(value) != nil
    end

    def readable?(value) when is_binary(value), do: Color.parse(value) != nil
    def readable?(_value), do: false

    defp size(value) do
      case Float.parse(String.trim(value)) do
        {n, ""} when n > 0 -> {:ok, if(n == trunc(n), do: trunc(n), else: n)}
        _ -> :error
      end
    end

    @doc """
    The node with one more series colour: the default palette's colour at the next position,
    cycling, so a new series is distinct from its neighbours.
    """
    @spec series_added(map()) :: map()
    def series_added(node) do
      series = Map.get(node, :series, Theme.default().series)
      palette = Theme.default().series
      Map.put(node, :series, series ++ [Enum.at(palette, rem(length(series), length(palette)))])
    end

    @doc "The node without the series colour at `i`; the last colour stays (spec/08 §7.2)."
    @spec series_removed(map(), non_neg_integer()) :: map()
    def series_removed(node, i) do
      case Map.get(node, :series, Theme.default().series) do
        [_only] -> node
        series -> Map.put(node, :series, List.delete_at(series, i))
      end
    end

    @doc """
    The node with the ramp resampled at one more evenly spaced anchor, each the colour the
    ramp had at its position (spec/14 §20.4): the ramp changes as little as the even spacing
    allows, and the new anchor is there to be moved.

        iex> node = Visualize.Chart.Builder.Themes.anchor_added(%{}, :thermal)
        iex> node.ramps.thermal
        ["#0e68ad", "#acbbd5", "#e3aea6", "#c02e31"]
    """
    @spec anchor_added(map(), Theme.ramp_name()) :: map()
    def anchor_added(node, ramp) do
      anchors = anchors(node, ramp)
      n = length(anchors)
      theme = Theme.build(Theme.default(), %{ramps: %{ramp => anchors}})
      ramp_put(node, ramp, for(k <- 0..n, do: Theme.ramp(theme, ramp, k / n)))
    end

    @doc "The node without the ramp's anchor at `i`; a ramp keeps two anchors (spec/14 §20.4)."
    @spec anchor_removed(map(), Theme.ramp_name(), non_neg_integer()) :: map()
    def anchor_removed(node, ramp, i) do
      case anchors(node, ramp) do
        [_, _] -> node
        anchors -> ramp_put(node, ramp, List.delete_at(anchors, i))
      end
    end

    @doc false
    # The ramp a client's string names, of the four; no atom is made from the string.
    @spec ramp_named(String.t()) :: Theme.ramp_name() | nil
    def ramp_named(name), do: Enum.find(Theme.ramp_names(), &(Atom.to_string(&1) == name))

    # A ramp's anchors as the node holds them, else the default theme's — what it draws as.
    defp anchors(node, ramp) do
      case node |> Map.get(:ramps, %{}) |> Map.get(ramp) do
        [_ | _] = anchors -> anchors
        _none -> Map.fetch!(Theme.default().ramps, ramp)
      end
    end

    defp ramp_put(node, ramp, anchors) do
      Map.put(node, :ramps, node |> Map.get(:ramps, %{}) |> Map.put(ramp, anchors))
    end

    @doc """
    The node with every value of `theme` and the node's own `name` (spec/14 §20.2): a
    variant starts from what it varies. A node with no name takes none, so a new theme does
    not take a built-in theme's name by deriving from it.

        iex> node = Visualize.Chart.Builder.Themes.derived(%{name: :house}, Visualize.Theme.dark())
        iex> {node.name, node.background}
        {:house, "#1b1e24"}
    """
    @spec derived(map(), Theme.t()) :: map()
    def derived(node, %Theme{} = theme) do
      values = Map.delete(Document.node(theme), :name)

      case Map.fetch(node, :name) do
        {:ok, name} -> Map.put(values, :name, name)
        :error -> values
      end
    end

    # -- where the mode writes -----------------------------------------------------

    @doc false
    # The site whose theme the mode edits: the selected one when it carries a theme, else the
    # first of the chart that does; `nil` for a chart that holds none.
    @spec site([Use.t()], term()) :: Use.t() | nil
    def site(uses, selected) do
      holds? = &match?(%Use{local: %{theme: _}}, &1)

      case Stack.get(uses, selected) do
        %Use{} = use -> if holds?.(use), do: use, else: first(uses, holds?)
        nil -> first(uses, holds?)
      end
    end

    defp first(uses, holds?) do
      uses |> Stack.all() |> Enum.map(& &1.use) |> Enum.find(holds?)
    end

    @doc false
    # The uses with the editable theme node of the mode's site replaced by `fun` of it:
    # `{:ok, uses}`, `:unchanged` when `fun` refuses the value, `{:locked, use}` for a site
    # that refers to a library entry, or `:none` for a chart that holds no theme.
    @spec written([Use.t()], term(), Store.store() | nil, (map() -> {:ok, map()} | :error)) ::
            {:ok, [Use.t()]} | :unchanged | {:locked, Use.t()} | :none
    def written(uses, selected, store, fun) do
      case site(uses, selected) do
        nil ->
          :none

        %Use{ref: ref} = use when ref != nil ->
          {:locked, use}

        %Use{id: id, local: %{theme: value}} ->
          case fun.(editable(value, store)) do
            {:ok, node} ->
              {:ok, Stack.update(uses, id, &%{&1 | local: Map.put(&1.local, :theme, node)})}

            :error ->
              :unchanged
          end
      end
    end

    @doc false
    # What *derive from* offers: the built-in themes, then the store's theme entries.
    @spec derive_choices(Store.store() | nil) :: [{String.t(), String.t()}]
    def derive_choices(store) do
      builtins = for name <- Theme.builtins(), do: {to_string(name), "builtin:#{name}"}

      stored =
        if store,
          do:
            for(
              %{kind: :theme} = entry <- Store.list(store),
              do: {entry.name, Store.encode_id(entry.id)}
            ),
          else: []

      builtins ++ stored
    end

    @doc false
    # The theme a *derive from* value names: a built-in, by a name `Theme.builtins/0` holds —
    # no atom is made from the client's string — or a stored entry by its id.
    @spec derive_source(String.t(), Store.store() | nil) ::
            {:ok, Theme.t()} | {:error, String.t()}
    def derive_source("builtin:" <> name, _store) do
      case Enum.find(Theme.builtins(), &(Atom.to_string(&1) == name)) do
        nil -> {:error, "#{name} is not a built-in theme"}
        builtin -> {:ok, Theme.builtin(builtin)}
      end
    end

    def derive_source(value, store) when store != nil do
      with {:ok, id} <- Store.decode_id(value),
           {:ok, entry} <- Store.get(store, id),
           {:ok, theme} <- Document.from_map(entry.fragment) do
        {:ok, theme}
      else
        {:error, _faults} -> {:error, "#{value} is not a theme that reads"}
        :error -> {:error, "the library holds no theme #{value}"}
      end
    end

    def derive_source(value, nil), do: {:error, "the library holds no theme #{value}"}
  end
end
