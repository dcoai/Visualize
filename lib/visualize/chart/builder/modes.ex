if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Modes do
    @moduledoc false
    # The builder's modes (spec/14 §19.9, §20): the shapes the editor takes for an open kind
    # that is not a chart of marks. A composite, a design and every other kind are the
    # design editor, which is the builder itself; a theme is the theme mode
    # (`Visualize.Chart.Builder.ThemeMode`, D-139).
    #
    # A mode is one module with three functions, and this list is the one place a mode is
    # named:
    #
    #   * `events/0` - the events the mode handles, routed to it by
    #     `Visualize.Chart.Builder.handle_event/3` as an area's are;
    #   * `handle_event/3` - each of them;
    #   * `assigns/3` - given the assigns, the open kind and the faults, the render's assigns
    #     for the mode, keyed by the mode (`%{theme_mode: nil}` while it is off), merged into
    #     what `Visualize.Chart.Builder.Editing.editing/1` derives.
    #
    # A new mode — a board (#544) — is a module beside `ThemeMode` and an entry here; the
    # render reads its key as it reads `@theme_mode`.

    alias Visualize.Chart.Builder.ThemeMode

    @modes [ThemeMode]

    @doc false
    # The mode modules, for the router.
    def all, do: @modes

    @doc false
    # Every mode's render assigns: each mode's, `nil` under its key while it is off.
    def assigns(assigns, kind, errors) do
      Enum.reduce(@modes, %{}, &Map.merge(&2, &1.assigns(assigns, kind, errors)))
    end
  end
end
