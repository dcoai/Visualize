if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Masks do
    @moduledoc """
    The context panel over a layer — its key and its free variables (spec/14 §19.5,
    §19.10) — and the rows of its mask, which the layer's row lists (§18.8, #316).

    A site's mask is the keys removed at that site, so a lower layer shows through
    (§19.5). `rows/2` lists the paths the site's contribution carries — its top-level
    keys, and the keys of each node under them — one checkbox per path under the layer's
    › Mask item, checked where the mask holds it. A site masked as a whole is disabled
    (§19.3) and is said so rather than drawn as every box checked.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    import Visualize.Chart.Names, only: [is_name: 1]

    use Phoenix.Component

    alias Visualize.Chart.Builder.Stack
    alias Visualize.Chart.{Fragment, Use}

    attr(:id, :string, required: true, doc: "the panel's id")
    attr(:use, :any, required: true, doc: "the selected site, a `Visualize.Chart.Use`")
    attr(:label, :string, required: true, doc: "the site's name")

    attr(:fragment, :map,
      required: true,
      doc: "what the site contributes before its mask: the referenced body under its local"
    )

    attr(:free, :list, default: [], doc: "the site's free variables, as `free_vars/1` gives them")

    attr(:keyless, :boolean,
      default: false,
      doc: "whether the site was left out for want of a key"
    )

    attr(:pool, :list,
      default: [],
      doc: "the names of the host's sample sources, sorted (§19.10)"
    )

    attr(:index, :any,
      default: nil,
      doc: "the site's row, which the lock actions take (§18.8, #381)"
    )

    attr(:reverting, :boolean,
      default: false,
      doc: "whether a revert of this site is armed and the next click does it"
    )

    attr(:store?, :boolean, default: false, doc: "whether a store is configured, for *save as*")

    attr(:target, :any, default: nil, doc: "the `phx-target` of the panel's events")

    @doc """
    Renders the layer's context: its *declared as* key control, its lock actions, the
    *save as* form of an inline group (§18.8, #382), its not-placed fault, and the free
    variables the site carries. Its mask is the layer row's (§18.8).
    """
    def panel(assigns) do
      assigns =
        assign(assigns,
          keyed?: keyed?(assigns.fragment),
          choices: choices(assigns),
          actions: actions(assigns.use, assigns.reverting)
        )

      ~H"""
      <div id={@id} class="vis-builder-layer-context">
        <h3 class="vis-builder-context-title">{@label}</h3>
        <p :if={@actions != [] and @index != nil} class="vis-builder-context-actions">
          <span class="vis-builder-context-state">{state_word(@use)}</span>
          <button
            :for={{event, word} <- @actions}
            type="button"
            class="vis-builder-section-select-button"
            phx-click={event}
            phx-value-index={@index}
            phx-target={@target}
          >{word}</button>
        </p>
        <form
          :if={@keyed?}
          id={@id <> "-declared"}
          class="vis-builder-declared-as"
          phx-change="set_key"
          phx-hook="BuilderHook"
          phx-target={@target}
          data-builder-target={@target}
          data-builder-scope="pool"
          phx-submit="submitted"
        >
          <label class="vis-builder-control-label" for={@id <> "-key"}>declared as</label>
          <div :if={@choices} class="vis-builder-pool" role="radiogroup" aria-label="a source of the pool">
            <label class={"vis-builder-pool-name" <> if(@use.key == nil, do: " vis-builder-pool-name-on", else: "")}>
              <input type="radio" name="key" value="" checked={@use.key == nil} />
              none
            </label>
            <label
              :for={name <- @choices}
              class={"vis-builder-pool-name" <> if(to_string(@use.key) == name, do: " vis-builder-pool-name-on", else: "")}
            >
              <input type="radio" name="key" value={name} checked={to_string(@use.key) == name} />
              {name}
            </label>
          </div>
          <input
            id={@id <> "-key"}
            type="text"
            name={if(@choices, do: "key.other", else: "key")}
            class="vis-builder-declared-name"
            value={if(!@choices, do: @use.key && to_string(@use.key))}
            placeholder={if(@choices, do: "or a name the pool lacks", else: "a name")}
            aria-label={if(@choices, do: "a name the pool lacks", else: "declared as")}
          />
        </form>
        <form
          :if={@store? and @index != nil and Stack.group?(@use)}
          id={@id <> "-save"}
          class="vis-builder-site-save"
          phx-submit="save_site"
          phx-target={@target}
        >
          <input type="hidden" name="index" value={@index} />
          <label class="vis-builder-control-label" for={@id <> "-save-name"}>save as</label>
          <input
            id={@id <> "-save-name"}
            type="text"
            name="name"
            class="vis-builder-name"
            placeholder="Group:sub-group:name"
            aria-label="save the group to the library as"
          />
          <button type="submit" class="vis-builder-put">Save to library</button>
        </form>
        <p :if={@keyless} class="vis-builder-context-fault">
          not placed: a {kind_word(@fragment)} needs a name to be declared under
        </p>
        <p :if={@free != []} class="vis-builder-context-vars">
          needs {Enum.map_join(@free, ", ", &"var(:#{&1.name})")} — bind them on the Variables tab
        </p>
      </div>
      """
    end

    # The site's lock actions, by its linkage (spec/14 §18.8, #381): unlock for a linked
    # site, lock for an unlocked one, revert where there is something to revert.
    defp actions(%Use{} = use, reverting?) do
      lock =
        case Stack.linkage(use) do
          :inline -> []
          :unlocked -> [{"lock_site", "lock"}]
          _linked -> [{"unlock_site", "unlock"}]
        end

      revert =
        cond do
          use.origin == nil and (use.ref == nil or map_size(use.local) == 0) -> []
          reverting? -> [{"revert_site", "revert — discards #{map_size(use.local)} edited keys"}]
          true -> [{"revert_site", "revert to original"}]
        end

      lock ++ revert
    end

    defp state_word(%Use{} = use) do
      case Stack.linkage(use) do
        :linked -> "linked to the library"
        :edited -> "linked, with local changes"
        :unlocked -> "unlocked from the library"
        :inline -> ""
      end
    end

    @doc """
    Whether a contribution is of a kind the document keys by name — style, scale, source,
    var — so the site needs a `key` to be declared under (spec/14 §19.3).

        iex> Visualize.Chart.Builder.Masks.keyed?(%{style: %{stroke: "#111"}})
        true

        iex> Visualize.Chart.Builder.Masks.keyed?(%{frames: %{main: %{}}})
        false
    """
    @spec keyed?(map()) :: boolean()
    def keyed?(fragment) do
      case Fragment.wrapped(fragment) do
        {kind, _body} -> kind in [:style, :scale, :source, :var, :gradient]
        nil -> false
      end
    end

    @doc """
    Whether a contribution is a source, whose key is chosen from the host's pool rather
    than typed (spec/14 §19.10).

        iex> Visualize.Chart.Builder.Masks.pooled?(%{source: %{fields: [:t]}})
        true

        iex> Visualize.Chart.Builder.Masks.pooled?(%{style: %{}})
        false
    """
    @spec pooled?(map()) :: boolean()
    def pooled?(fragment), do: match?({:source, _}, Fragment.wrapped(fragment))

    # A source site's choices: the pool's names with the current key kept, or nil for a
    # kind that is named by the person or a pool with nothing to list.
    defp choices(%{fragment: fragment, pool: pool, use: use}) do
      if pooled?(fragment) and pool != [] do
        current = use.key && to_string(use.key)
        if current && current not in pool, do: [current | pool], else: pool
      end
    end

    defp kind_word(fragment) do
      case Fragment.wrapped(fragment) do
        {kind, _body} -> kind
        nil -> "site"
      end
    end

    @doc """
    The paths a site's contribution can mask: every top-level key, and the keys of each
    node under one, as `Visualize.Chart.Use.mask/2` takes them (spec/14 §19.5).

        iex> Visualize.Chart.Builder.Masks.paths(%{theme: :dark, frames: %{"main" => %{legend: %{}, margin: %{}}}})
        [[:frames], [:frames, "main"], [:frames, "main", :legend], [:frames, "main", :margin], [:theme]]
    """
    @spec paths(map()) :: [[atom()]]
    def paths(fragment) when is_map(fragment) do
      fragment
      |> Enum.flat_map(fn
        # `frames` is a map *of* frames, so its parts are one level deeper: a mask names
        # `frames.main.margin`, not `frames.main` (spec/14 §2.1, #383).
        {:frames = key, value} when is_map(value) and not is_struct(value) ->
          inner =
            Enum.flat_map(value, fn {name, node} ->
              parts =
                if is_map(node), do: for({p, _} <- node, is_name(p), do: [key, name, p]), else: []

              [[key, name] | parts]
            end)

          [[key] | inner]

        {key, value} when is_map(value) and not is_struct(value) ->
          [[key] | for({inner, _} <- value, is_name(inner), do: [key, inner])]

        {key, _value} ->
          [[key]]
      end)
      |> Enum.filter(fn path -> Enum.all?(path, &is_name/1) end)
      |> Enum.sort()
    end

    @doc """
    A mask with a path added or removed, as a checkbox says: checked masks it, unchecked
    does not. A path is spelled as its keys joined by `.`, which is the checkbox's name.
    """
    @spec toggle(Use.t(), String.t(), boolean()) :: Use.t()
    def toggle(%Use{mask: mask} = use, name, checked) when is_list(mask) do
      # A key is the schema's atom, a name its string (D-195): nothing is made of the text.
      path = name |> String.split(".") |> Enum.map(&Visualize.Chart.Words.key/1)
      without = Enum.reject(mask, &(normal(&1) == path))
      %{use | mask: if(checked, do: without ++ [path], else: without)}
    end

    def toggle(%Use{} = use, _name, _checked), do: use

    defp normal(key) when is_name(key), do: [key]
    defp normal(path) when is_list(path), do: path

    @doc """
    One row per maskable path of a contribution, for the layer row's › Mask item (spec/14
    §18.8, #316): its name (the keys joined by `.`, which is the checkbox's name), whether
    `use` masks it, and the class and title that say so.

        iex> use = %Visualize.Chart.Use{id: 1, ref: nil, mask: [[:frames, :main, :margin]]}
        iex> rows = Visualize.Chart.Builder.Masks.rows(%{frames: %{main: %{margin: %{top: 1}}}}, use)
        iex> Enum.map(rows, &{&1.name, &1.masked})
        [{"frames", false}, {"frames.main", false}, {"frames.main.margin", true}]
    """
    @spec rows(map(), Use.t()) :: [map()]
    def rows(fragment, %Use{mask: mask}) do
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
