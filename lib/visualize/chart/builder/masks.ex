if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Masks do
    @moduledoc """
    The context panel over a layer: its keys with mask checkboxes, and its free variables
    (spec/14 §19.5, §19.10).

    A site's mask is the keys removed at that site, so a lower layer shows through
    (§19.5). The panel lists the paths the site's contribution carries — its top-level
    keys, and the keys of each node under them — with a checkbox per path, checked where
    the mask holds it. A site masked as a whole is disabled (§19.3) and is said so rather
    than drawn as every box checked.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Use

    attr(:id, :string, required: true, doc: "the panel's id")
    attr(:use, :any, required: true, doc: "the selected site, a `Visualize.Chart.Use`")
    attr(:label, :string, required: true, doc: "the site's name")

    attr(:fragment, :map,
      required: true,
      doc: "what the site contributes before its mask: the referenced body under its local"
    )

    attr(:free, :list, default: [], doc: "the site's free variables, as `free_vars/1` gives them")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the panel's events")

    @doc """
    Renders the layer's context: a `<form class="vis-builder-masks">` with one checkbox
    per maskable path, and the free variables the site carries.
    """
    def panel(assigns) do
      assigns =
        assign(assigns,
          rows: rows(assigns.fragment, assigns.use),
          disabled?: assigns.use.mask == :all
        )

      ~H"""
      <div id={@id} class="vis-builder-layer-context">
        <h3 class="vis-builder-context-title">{@label}</h3>
        <p :if={@disabled?} class="vis-builder-context-note">
          disabled — every key is masked, so the layers below show through
        </p>
        <p :if={not @disabled? and @rows == []} class="vis-builder-context-note">
          this layer sets nothing yet
        </p>
        <form :if={not @disabled? and @rows != []} class="vis-builder-masks" phx-change="mask" phx-target={@target}>
          <label :for={row <- @rows} class={row.class} title={row.title}>
            <input type="checkbox" name={row.name} value="true" checked={row.masked} />
            <span class="vis-builder-mask-path">{row.name}</span>
          </label>
        </form>
        <p :if={@free != []} class="vis-builder-context-vars">
          needs {Enum.map_join(@free, ", ", &"var(:#{&1.name})")} — bind them on the Variables tab
        </p>
      </div>
      """
    end

    @doc """
    The paths a site's contribution can mask: every top-level key, and the keys of each
    node under one, as `Visualize.Chart.Use.mask/2` takes them (spec/14 §19.5).

        iex> Visualize.Chart.Builder.Masks.paths(%{theme: :dark, frame: %{size: %{}, margin: %{}}})
        [[:frame], [:frame, :margin], [:frame, :size], [:theme]]
    """
    @spec paths(map()) :: [[atom()]]
    def paths(fragment) when is_map(fragment) do
      fragment
      |> Enum.flat_map(fn
        {key, value} when is_map(value) and not is_struct(value) ->
          [[key] | for({inner, _} <- value, is_atom(inner), do: [key, inner])]

        {key, _value} ->
          [[key]]
      end)
      |> Enum.filter(fn path -> Enum.all?(path, &is_atom/1) end)
      |> Enum.sort()
    end

    @doc """
    A mask with a path added or removed, as a checkbox says: checked masks it, unchecked
    does not. A path is spelt as its keys joined by `.`, which is the checkbox's name.
    """
    @spec toggle(Use.t(), String.t(), boolean()) :: Use.t()
    def toggle(%Use{mask: mask} = use, name, checked) when is_list(mask) do
      path = name |> String.split(".") |> Enum.map(&String.to_existing_atom/1)
      without = Enum.reject(mask, &(normal(&1) == path))
      %{use | mask: if(checked, do: without ++ [path], else: without)}
    end

    def toggle(%Use{} = use, _name, _checked), do: use

    defp normal(key) when is_atom(key), do: [key]
    defp normal(path) when is_list(path), do: path

    defp rows(fragment, %Use{mask: mask}) do
      masked = if is_list(mask), do: Enum.map(mask, &normal/1), else: []

      for path <- paths(fragment) do
        name = Enum.map_join(path, ".", &to_string/1)
        on? = path in masked

        %{
          name: name,
          masked: on?,
          class: if(on?, do: "vis-builder-mask vis-builder-mask-on", else: "vis-builder-mask"),
          title: if(on?, do: "masked here: the layer below shows through", else: "mask #{name}")
        }
      end
    end
  end
end
