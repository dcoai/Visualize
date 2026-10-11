if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.ThemeMode do
    @moduledoc false
    # The theme mode (spec/14 §20, D-139), one of `Visualize.Chart.Builder.Modes`: its events —
    # a field, the series, a ramp's anchors, derive, the vision, the sheet's designs, opening
    # the chart's own theme — and its render assigns. The panel and the pure reading of a
    # control are `Visualize.Chart.Builder.Themes`; the sheet is
    # `Visualize.Chart.Builder.ThemeSheet`.
    #
    # Split from `Visualize.Chart.Builder` by area (#568); compiled only with
    # `Phoenix.Component`, as the builder is (spec/10 §1.1, D-45, D-85).

    import Phoenix.Component, only: [assign: 2, assign: 3, update: 3]
    import Visualize.Chart.Builder.Selection, only: [position: 1]
    import Visualize.Chart.Builder.Workspace, only: [opened_entry: 2]
    import Visualize.Chart.Builder.Writes, only: [locked_notice: 2]

    alias Visualize.{Chart, Theme}
    alias Visualize.Chart.Builder.{Stack, Store, Themes}
    alias Visualize.Chart.{Use, Validator}

    # The events this module handles: `Visualize.Chart.Builder.handle_event/3` routes
    # each here.
    @events ~w(
      theme_edit theme_series_add theme_series_remove theme_anchor_add theme_anchor_remove
      theme_vision theme_derive theme_design_add theme_design_remove open_theme
    )

    @doc false
    def events, do: @events

    # -- the theme mode (spec/14 §20, D-139) ----------------------------------------------

    @doc false
    def handle_event("theme_edit", %{"_target" => [field]} = params, socket) do
      value = Map.get(params, field, "")
      {:noreply, theme_written(socket, &Themes.change(&1, field, value))}
    end

    def handle_event("theme_edit", _params, socket), do: {:noreply, socket}

    def handle_event("theme_series_add", _params, socket) do
      {:noreply, theme_written(socket, &{:ok, Themes.series_added(&1)})}
    end

    def handle_event("theme_series_remove", %{"index" => index}, socket) do
      {:noreply, theme_written(socket, &{:ok, Themes.series_removed(&1, position(index))})}
    end

    def handle_event("theme_anchor_add", %{"ramp" => ramp}, socket) do
      case Themes.ramp_named(ramp) do
        nil -> {:noreply, socket}
        ramp -> {:noreply, theme_written(socket, &{:ok, Themes.anchor_added(&1, ramp)})}
      end
    end

    def handle_event("theme_anchor_remove", %{"ramp" => ramp, "index" => index}, socket) do
      case Themes.ramp_named(ramp) do
        nil ->
          {:noreply, socket}

        ramp ->
          {:noreply,
           theme_written(socket, &{:ok, Themes.anchor_removed(&1, ramp, position(index))})}
      end
    end

    # The deficiency the ramps and the sheet are seen under: the builder's, not the theme's
    # (spec/14 §20.5); a value that names none is normal vision.
    def handle_event("theme_vision", %{"vision" => vision}, socket) do
      seen =
        Enum.find(Visualize.Color.Vision.deficiencies(), :none, &(Atom.to_string(&1) == vision))

      {:noreply, assign(socket, :vision, seen)}
    end

    def handle_event("theme_derive", %{"from" => from}, socket) do
      case Themes.derive_source(from, socket.assigns.store) do
        {:ok, theme} -> {:noreply, theme_written(socket, &{:ok, Themes.derived(&1, theme)})}
        {:error, notice} -> {:noreply, assign(socket, :notice, notice)}
      end
    end

    def handle_event("theme_design_add", %{"id" => submitted}, socket) do
      case Store.decode_id(submitted) do
        {:ok, id} ->
          {:noreply, update(socket, :theme_designs, &if(id in &1, do: &1, else: &1 ++ [id]))}

        :error ->
          {:noreply, socket}
      end
    end

    def handle_event("theme_design_remove", %{"id" => submitted}, socket) do
      case Store.decode_id(submitted) do
        {:ok, id} -> {:noreply, update(socket, :theme_designs, &List.delete(&1, id))}
        :error -> {:noreply, socket}
      end
    end

    # The chart's own theme opened in the theme mode (spec/14 §20.1): the stored entry when
    # the design names one the store holds, so saving updates what the chart draws in; else a
    # new theme of the built-in's or the inline theme's whole node.
    def handle_event("open_theme", _params, socket) do
      %{uses: uses, stack_vars: vars, store: store} = socket.assigns

      value =
        case Stack.design(uses, vars, Stack.fetch(store)) do
          {:ok, design, _report} -> Map.get(design, :theme, :default)
          {:error, _cycle} -> :default
        end

      entry =
        with name when is_atom(name) and name != nil <- value,
             nil <- Theme.builtin(name),
             true <- store != nil,
             {:ok, entry} <- Store.theme_entry(store, name) do
          Map.put(entry, :kind, :theme)
        else
          _new ->
            node = value |> Themes.effective(store) |> Visualize.Chart.Theme.node()
            %{id: nil, name: nil, kind: :theme, fragment: %{theme: node}}
        end

      {:noreply, opened_entry(socket, entry)}
    end

    @doc false
    # The render's assigns for the mode (`Visualize.Chart.Builder.Modes`): `theme_mode`.
    def assigns(assigns, kind, errors), do: %{theme_mode: theme_mode(assigns, kind, errors)}

    # The theme mode (spec/14 §20): while the open chart is a theme, the node the editor
    # writes, the theme it draws as, its faults, what it may derive from, and the designs a
    # person has put on the sheet; `nil` in any other chart.
    defp theme_mode(%{uses: uses, selected: selected, store: store} = assigns, :theme, errors) do
      value =
        case Themes.site(uses, selected) do
          %Use{local: %{theme: value}} -> value
          _none -> nil
        end

      %{
        node: Themes.editable(value, store),
        theme: Themes.effective(value, store),
        faults: Enum.map(errors, &Validator.format/1),
        derive: Themes.derive_choices(store),
        designs: sheet_designs(assigns),
        choices: sheet_choices(store)
      }
    end

    defp theme_mode(_assigns, _kind, _errors), do: nil

    # The designs a person has put on the sheet, each flattened through the store (§19.6).
    defp sheet_designs(%{theme_designs: ids, store: store}) when store != nil do
      fetch = Stack.fetch(store)

      for id <- ids, {:ok, entry} <- [Store.get(store, id)] do
        design =
          case Chart.flatten(entry.fragment, fetch) do
            {:ok, design, _report} -> design
            {:error, {:cycle, _chain}} -> %{}
          end

        %{id: Store.encode_id(id), name: entry.name, design: design}
      end
    end

    defp sheet_designs(_assigns), do: []

    defp sheet_choices(nil), do: []

    defp sheet_choices(store) do
      for %{kind: :composite} = entry <- Store.list(store),
          do: {entry.name, Store.encode_id(entry.id)}
    end

    # One write of the theme mode into the open theme site (spec/14 §20.1).
    defp theme_written(socket, fun) do
      %{uses: uses, selected: selected, store: store} = socket.assigns

      case Themes.written(uses, selected, store, fun) do
        {:ok, uses} -> assign(socket, uses: uses, notice: nil)
        :unchanged -> socket
        {:locked, use} -> assign(socket, :notice, locked_notice(socket.assigns, use))
        :none -> assign(socket, :notice, "this chart holds no theme to edit")
      end
    end
  end
end
