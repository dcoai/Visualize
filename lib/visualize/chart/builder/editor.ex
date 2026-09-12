if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Editor do
    @moduledoc """
    The builder's fragment editor, generated from the schema (spec/14 §18.5-§18.7).

    Nothing here is written by hand. `nodes/1` walks a fragment by the *type* of every key
    it carries, so which nodes a person may open is a query over
    `Visualize.Chart.Schema.describe/1` and not a list; `widget/1` maps a
    `t:Visualize.Chart.Schema.type/0` to a control and `parse/2` reads a submitted string
    back as a value of that type, so a key added to the schema gets its control and a node
    kind added becomes openable, with no edit here (D-86).

    A composite value — a text, an extent, a whole node — is a textarea holding what
    `inspect/1` writes, read back by `parse/2` as a *literal*: the string is parsed with
    `Code.string_to_quoted/1`, never evaluated, and only the vocabulary a design may
    contain is accepted (spec/14 §1.4). A design map therefore cannot acquire a function or
    a term the JSON codec has no form for.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Builder.{Glyphs, Store}
    alias Visualize.Chart.{Fragment, Schema, Validator, Var}

    @typedoc "The control a key's type gets (spec/14 §18.6)."
    @type widget :: :checkbox | :number | :text | :textarea | {:select, [atom()]}

    @typedoc "One editable node of a fragment (spec/14 §18.5)."
    @type node_entry :: %{path: Validator.path(), kind: Schema.kind(), label: String.t()}

    # The facets in the order of spec/14 §1.3, which is the order of the editor's tabs.
    @facets [:binding, :channel, :geometry, :style, :content]

    # Every type that reads as a plain atom naming something the design declares.
    @atom_types [:name, :field, :slot]

    # Every type whose control is a single-line text field (spec/14 §18.6).
    @text_types [:string, :name, :field, :size, :font, :slot]

    # -- the nodes of a fragment (spec/14 §18.5) -------------------------------------------

    @doc """
    The editable nodes of a fragment: one entry per node the schema's walk reaches.

    The root is first and carries the path `[]`; a `{:map, {:node, kind}}` contributes one
    node per declared name in name order, a `{:list, {:node, kind}}` one per element at its
    index, and a `{:one_of, …}` that admits a node kind contributes that node when the
    value is a map. The walk stops at values: a text, an extent, a channel and a reference
    are edited on the node that carries them.

    ## Examples

        iex> fragment = %{version: 1, frame: %{kind: :cartesian, size: %{width: 400}}}
        iex> Enum.map(Visualize.Chart.Builder.Editor.nodes(fragment), & &1.label)
        ["design", "frame", "frame.size"]
        iex> Enum.map(Visualize.Chart.Builder.Editor.nodes(fragment), & &1.kind)
        [:design, :frame, :size]

    """
    @spec nodes(map()) :: [node_entry(), ...]
    def nodes(fragment) when is_map(fragment) do
      case Fragment.wrapped(fragment) do
        {kind, body} -> walk(body, kind, [kind])
        nil -> walk(fragment, :design, [])
      end
    end

    defp walk(node, kind, path) do
      [%{path: path, kind: kind, label: label(path)} | children(node, kind, path)]
    end

    defp children(node, kind, path) do
      Enum.flat_map(Schema.describe(kind), fn spec ->
        case Map.fetch(node, spec.key) do
          {:ok, value} -> descend(spec.type, value, path ++ [spec.key])
          :error -> []
        end
      end)
    end

    defp descend({:node, kind}, value, path) when is_map(value) and not is_struct(value),
      do: walk(value, kind, path)

    defp descend({:map, {:node, _} = inner}, value, path)
         when is_map(value) and not is_struct(value) do
      value
      |> Enum.sort_by(fn {name, _node} -> to_string(name) end)
      |> Enum.flat_map(fn {name, node} -> descend(inner, node, path ++ [name]) end)
    end

    defp descend({:list, {:node, _} = inner}, value, path) when is_list(value) do
      value
      |> Enum.with_index()
      |> Enum.flat_map(fn {node, index} -> descend(inner, node, path ++ [index]) end)
    end

    defp descend({:one_of, types}, value, path) when is_map(value) and not is_struct(value) do
      case Enum.find(types, &match?({:node, _}, &1)) do
        nil -> []
        inner -> descend(inner, value, path)
      end
    end

    defp descend(_type, _value, _path), do: []

    # The path as `Visualize.Chart.Validator.format/1` spells it.
    defp label([]), do: "design"

    defp label(path) do
      Enum.reduce(path, "", fn
        index, acc when is_integer(index) -> "#{acc}[#{index}]"
        key, "" -> "#{key}"
        key, acc -> "#{acc}.#{key}"
      end)
    end

    # -- widgets and values (spec/14 §18.6) -----------------------------------------------

    @doc """
    The control a type gets (spec/14 §18.6).

    ## Examples

        iex> Visualize.Chart.Builder.Editor.widget(:boolean)
        :checkbox
        iex> Visualize.Chart.Builder.Editor.widget({:enum, [:top, :bottom]})
        {:select, [:top, :bottom]}
        iex> Visualize.Chart.Builder.Editor.widget({:ref, :style})
        :text
        iex> Visualize.Chart.Builder.Editor.widget({:node, :size})
        :textarea

    """
    @spec widget(Schema.type()) :: widget()
    def widget(:boolean), do: :checkbox
    def widget(type) when type in [:integer, :number], do: :number
    def widget({:enum, allowed}), do: {:select, allowed}
    def widget(:colour), do: :colour
    def widget(type) when type in @text_types, do: :text
    def widget({:ref, _kind}), do: :text
    def widget({:one_of, [first | _rest]}), do: widget(first)
    def widget(_type), do: :textarea

    @doc """
    A submitted string read back as a value of a type (spec/14 §18.6).

    A blank string is `:error` for every type: blanking a control removes the key rather
    than setting it to nothing. A composite value is read as a literal — parsed with
    `Code.string_to_quoted/1` and never evaluated — and only a number, a string, an atom, a
    boolean, `nil`, a list, a tuple, a map, a `Visualize.Chart.Var` or a `~U` sigil is
    accepted.

    ## Examples

        iex> Visualize.Chart.Builder.Editor.parse(:integer, "42")
        {:ok, 42}
        iex> Visualize.Chart.Builder.Editor.parse({:ref, :style}, "series")
        {:ok, :series}
        iex> Visualize.Chart.Builder.Editor.parse(:colour, "#3b6fa8")
        {:ok, "#3b6fa8"}
        iex> Visualize.Chart.Builder.Editor.parse(:extent, "[0, 100]")
        {:ok, [0, 100]}
        iex> Visualize.Chart.Builder.Editor.parse(:term, "System.halt()")
        :error

    """
    @spec parse(Schema.type(), String.t()) :: {:ok, term()} | :error
    def parse(type, string) when is_binary(string) do
      case String.trim(string) do
        "" -> :error
        trimmed -> read(type, trimmed)
      end
    end

    defp read(:boolean, string) when string in ["true", "on"], do: {:ok, true}
    defp read(:boolean, string) when string in ["false", "off"], do: {:ok, false}
    defp read(:boolean, _string), do: :error
    defp read(:integer, string), do: integer(string)
    defp read(:number, string), do: number(string)
    defp read(:string, string), do: {:ok, string}
    defp read(type, string) when type in @atom_types, do: {:ok, atom(string)}
    # A reference is a local name, or a library id spelt as the DOM carries one (§19.2).
    defp read({:ref, kind}, string) do
      case Store.decode_id(string) do
        {:ok, {^kind, _n} = id} -> {:ok, id}
        _other -> {:ok, atom(string)}
      end
    end

    defp read(type, string) when type in [:colour, :size, :font], do: {:ok, loose(string)}

    defp read({:enum, allowed}, string) do
      case Enum.find(allowed, &(to_string(&1) == string)) do
        nil -> :error
        value -> {:ok, value}
      end
    end

    defp read({:one_of, [first | _rest]}, string), do: read(first, string)
    defp read(_type, string), do: literal(string)

    defp integer(string) do
      case Integer.parse(string) do
        {value, ""} -> {:ok, value}
        _other -> :error
      end
    end

    defp number(string) do
      with :error <- integer(string) do
        case Float.parse(string) do
          {value, ""} -> {:ok, value}
          _other -> :error
        end
      end
    end

    defp atom(":" <> rest), do: String.to_atom(rest)
    defp atom(string), do: String.to_atom(string)

    # What a person means by a bare word in a colour, a size or a font: a leading `:` is an
    # atom, a numeral is a number, and everything else is the string itself.
    defp loose(":" <> rest), do: String.to_atom(rest)

    defp loose(string) do
      case number(string) do
        {:ok, value} -> value
        :error -> string
      end
    end

    # -- the literal reader (spec/14 §18.6, D-86) -----------------------------------------

    defp literal(string) do
      case Code.string_to_quoted(string) do
        {:ok, quoted} -> term(quoted)
        {:error, _reason} -> :error
      end
    end

    defp term(value) when is_number(value) or is_binary(value) or is_atom(value), do: {:ok, value}
    defp term(list) when is_list(list), do: collect(list)

    defp term({:-, _meta, [value]}) when is_number(value), do: {:ok, -value}

    defp term({:{}, _meta, elements}) do
      with {:ok, values} <- collect(elements), do: {:ok, List.to_tuple(values)}
    end

    defp term({:%{}, _meta, pairs}) do
      with {:ok, values} <- collect(pairs), do: {:ok, Map.new(values)}
    end

    defp term({:%, _meta, [{:__aliases__, _, [:Visualize, :Chart, :Var]}, {:%{}, _, pairs}]}) do
      with {:ok, fields} <- collect(pairs), do: var(fields)
    end

    defp term({:sigil_U, _meta, [{:<<>>, _, [text]}, _modifiers]}) when is_binary(text) do
      case DateTime.from_iso8601(text) do
        {:ok, at, _offset} -> {:ok, at}
        {:error, _reason} -> :error
      end
    end

    defp term({left, right}) do
      with {:ok, first} <- term(left), {:ok, second} <- term(right), do: {:ok, {first, second}}
    end

    defp term(_other), do: :error

    # `Visualize.Chart.Var` carries one field and it is required, so a literal that gives
    # anything else is an error rather than a raise.
    defp var(name: name) when is_atom(name), do: {:ok, %Var{name: name}}
    defp var(_fields), do: :error

    defp collect(list) do
      Enum.reduce_while(list, {:ok, []}, fn element, {:ok, acc} ->
        case term(element) do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          :error -> {:halt, :error}
        end
      end)
      |> case do
        {:ok, values} -> {:ok, Enum.reverse(values)}
        :error -> :error
      end
    end

    # -- what a change means (spec/14 §18.6, §19.9) --------------------------------------

    @doc """
    What a change to the form means: the key it is about, and what to write there —
    `{:ok, value}` or `:error` for a removal — or `nil` for a key the kind does not declare
    (spec/14 §18.6, §19.9).

    A form has three controls per key. `key` is the typed control and reads by `parse/2`;
    an unchecked checkbox submits nothing, which is `false` and not a removal, and every
    other control's blank removes the key. `key.mode` is the literal/variable switch:
    *variable* writes `var(:key)` so the field is a variable from that moment, *literal*
    removes the key so the typed control is empty and waiting. `key.var` is the variable's
    name, and a blank one is a removal too.

        iex> Visualize.Chart.Builder.Editor.change(:style, %{"_target" => ["stroke_width"], "stroke_width" => "5"})
        {:stroke_width, {:ok, 5}}

        iex> Visualize.Chart.Builder.Editor.change(:style, %{"_target" => ["fill.mode"], "fill.mode" => "variable"})
        {:fill, {:ok, %Visualize.Chart.Var{name: :fill}}}

        iex> Visualize.Chart.Builder.Editor.change(:style, %{"_target" => ["fill.var"], "fill.var" => "color"})
        {:fill, {:ok, %Visualize.Chart.Var{name: :color}}}

        iex> Visualize.Chart.Builder.Editor.change(:style, %{"_target" => ["fill.mode"], "fill.mode" => "literal"})
        {:fill, :error}

        iex> Visualize.Chart.Builder.Editor.change(:style, %{"_target" => ["nonsense"], "nonsense" => "1"})
        nil
    """
    @spec change(atom(), map()) :: {atom(), {:ok, term()} | :error} | nil
    def change(kind, %{"_target" => [target]} = params) do
      case String.split(target, ".", parts: 2) do
        [key, "mode"] -> with %{key: k} <- key_spec(kind, key), do: {k, mode(params[target], k)}
        [key, "var"] -> with %{key: k} <- key_spec(kind, key), do: {k, variable(params[target])}
        [key, "slot"] -> with %{key: k} <- key_spec(kind, key), do: {k, slot_face(params[target])}
        [key, "range"] -> with spec <- key_spec(kind, key), do: typed(spec, params[target])
        [key] -> with spec <- key_spec(kind, key), do: typed(spec, params[key])
      end
    end

    def change(_kind, _params), do: nil

    defp key_spec(kind, submitted) do
      Enum.find(Schema.describe(kind), &(to_string(&1.key) == submitted))
    end

    defp typed(nil, _value), do: nil
    defp typed(spec, value), do: {spec.key, submitted(spec.type, value)}

    @doc """
    A submitted control's value read as a type, with the one rule `parse/2` cannot know: an
    unchecked checkbox submits nothing, which is `false` and not a removal, while every other
    control's absence or blank is a removal (spec/14 §18.6).

        iex> Visualize.Chart.Builder.Editor.submitted(:boolean, nil)
        {:ok, false}

        iex> Visualize.Chart.Builder.Editor.submitted(:integer, nil)
        :error
    """
    @spec submitted(Schema.type(), String.t() | nil) :: {:ok, term()} | :error
    def submitted(type, nil), do: if(widget(type) == :checkbox, do: {:ok, false}, else: :error)
    def submitted(type, string), do: parse(type, string)

    # A colour's slot face: a theme slot chosen by name, or — blank — the key removed.
    defp slot_face(nil), do: :error
    defp slot_face(string) when is_binary(string), do: parse(:slot, string)

    defp mode("variable", key), do: {:ok, %Var{name: key}}
    defp mode(_literal, _key), do: :error

    @doc """
    A typed variable name as the variable it names, or `:error` for a blank — a removal.
    The name becomes an atom exactly as a typed reference does (spec/14 §18.6, §19.9).

        iex> Visualize.Chart.Builder.Editor.variable(":color_1")
        {:ok, %Visualize.Chart.Var{name: :color_1}}

        iex> Visualize.Chart.Builder.Editor.variable("  ")
        :error
    """
    @spec variable(String.t() | nil) :: {:ok, Var.t()} | :error
    def variable(nil), do: :error

    def variable(string) when is_binary(string) do
      case String.trim(string) do
        "" -> :error
        name -> {:ok, %Var{name: atom(name)}}
      end
    end

    # -- the form (spec/14 §18.7) ---------------------------------------------------------

    @doc """
    The facets a node kind has, in the order of spec/14 §1.3 (spec/14 §18.15).

    The editor renders these as its own strip; the builder renders them beside a node's
    children in one strip, and asks here rather than keeping a second copy of the rule.

        iex> Visualize.Chart.Builder.Editor.facets(:style)
        [:style]

        iex> :binding in Visualize.Chart.Builder.Editor.facets(:mark)
        true
    """
    @spec facets(atom()) :: [Schema.facet()]
    def facets(kind) do
      specs = Schema.describe(kind)
      Enum.filter(@facets, fn facet -> Enum.any?(specs, &(&1.facet == facet)) end)
    end

    attr(:id, :string, default: "vis-builder-editor", doc: "the panel's id, for its datalist")
    attr(:kind, :atom, required: true, doc: "the node kind being edited")
    attr(:node, :map, required: true, doc: "the node's current value")
    attr(:path, :list, default: [], doc: "where the node sits, for its keys' errors")
    attr(:facet, :atom, default: nil, doc: "the open tab, `nil` for the kind's first facet")
    attr(:errors, :list, default: [], doc: "the `{path, reason}` pairs of spec/14 §10.1")

    attr(:refs, :map,
      default: %{},
      doc: "the names and ids a `{:ref, kind}` may take, by kind — ids as `{kind, n}`"
    )

    attr(:selected, :string, default: nil, doc: "the key of the selected field, if any (§19.10)")

    attr(:slots, :list,
      default: [],
      doc: "the theme's colour slots, as strings, for a colour's slot face (spec/14 §19.10)"
    )

    attr(:strip, :boolean,
      default: true,
      doc: "render the facet strip; `false` where the caller does"
    )

    attr(:event, :string, default: "edit", doc: "the `phx-change` the form pushes")
    attr(:origins, :map, default: %{}, doc: "what supplied each key's value, by key")

    attr(:variables, :list,
      default: [],
      doc: "the variable names on offer, for the name's datalist"
    )

    attr(:target, :any, default: nil, doc: "the `phx-target` of the form's events")
    attr(:class, :string, default: nil, doc: "appended to the editor's class")

    @doc """
    Renders one form for one node (spec/10 §15.3).

    The facets of the node kind's keys are the tabs, in the order of spec/14 §1.3; the keys
    of the open tab follow the order `Visualize.Chart.Schema.describe/1` returns them in,
    each with the control `widget/1` chose, the value the node carries or the schema's
    default as a placeholder, and its own errors under it.
    """
    def panel(assigns) do
      specs = Schema.describe(assigns.kind)
      facets = facets(assigns.kind)
      open = if assigns.facet in facets, do: assigns.facet, else: List.first(facets)

      assigns =
        assigns
        |> assign(:facets, facets)
        |> assign(:open, open)
        |> assign(:fields, fields(specs, open, assigns))

      ~H"""
      <div class={class(@class)}>
        <nav :if={@strip} class="vis-builder-tabs">
          <button
            :for={facet <- @facets}
            type="button"
            class={tab(facet, @open)}
            phx-click="facet"
            phx-value-facet={facet}
            phx-target={@target}
          >{facet}</button>
        </nav>
        <datalist id={@id <> "-variables"}>
          <option :for={name <- @variables} value={name}></option>
        </datalist>
        <form
          id={@id <> "-form"}
          class="vis-builder-form"
          phx-change={@event}
          phx-hook="BuilderHook"
          phx-target={@target}
          data-builder-target={@target}
          data-builder-scope="ref"
        >
          <label
            :for={field <- @fields}
            class={"vis-builder-field" <> if(@selected == to_string(field.key), do: " vis-builder-field-selected", else: "")}
            data-builder-ref={field.ref && to_string(field.key)}
            phx-click="select_field"
            phx-keyup="select_field"
            phx-value-field={field.key}
            phx-target={@target}
          >
            <span class="vis-builder-key">
              {field.key}<span
                :if={@origins[field.key]}
                class="vis-builder-origin"
              >{@origins[field.key]}</span>
            </span>
            <select name={"#{field.key}.mode"} class="vis-builder-mode" title="literal, or a variable">
              <option value="literal" selected={is_nil(field.variable)}>literal</option>
              <option value="variable" selected={not is_nil(field.variable)}>variable</option>
            </select>
            <input
              :if={field.variable}
              type="text"
              name={"#{field.key}.var"}
              value={field.variable}
              list={@id <> "-variables"}
              class="vis-builder-var"
              title={"var(:" <> field.variable <> ")"}
            />
            <input
              :if={is_nil(field.variable) and field.widget == :checkbox}
              type="checkbox"
              name={field.key}
              value="true"
              checked={field.checked}
            />
            <input
              :if={is_nil(field.variable) and field.range != nil and field.widget in [:number, :text]}
              type="range"
              name={"#{field.key}.range"}
              class="vis-builder-range"
              min={field.range.min}
              max={field.range.max}
              step={field.range.step}
              value={field.slider}
              aria-label={"#{field.key}, dragged"}
            />
            <input
              :if={is_nil(field.variable) and field.widget == :number}
              type="number"
              name={field.key}
              value={field.value}
              placeholder={field.placeholder}
            />
            <input
              :if={is_nil(field.variable) and field.widget == :text}
              type="text"
              name={field.key}
              value={field.value}
              placeholder={field.placeholder}
            />
            <svg
              :if={is_nil(field.variable) and field.dash != nil}
              class="vis-builder-dash"
              viewBox="0 0 120 8"
              width="120"
              height="8"
              aria-hidden="true"
            >
              <path
                d="M2 4 H118"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-dasharray={field.dash}
              />
            </svg>
            <select
              :if={is_nil(field.variable) and field.widget == :colour}
              name={"#{field.key}.slot"}
              class="vis-builder-slot"
              title="a theme slot"
            >
              <option value="">slot…</option>
              <option :for={slot <- @slots} value={slot} selected={field.slot == slot}>{slot}</option>
            </select>
            <input
              :if={is_nil(field.variable) and field.widget == :colour}
              type="color"
              name={field.key}
              class="vis-builder-colour"
              value={field.value}
              title={field.value || "a colour"}
            />
            <select
              :if={is_nil(field.variable) and field.widget == :select and field.glyphs == []}
              name={field.key}
            >
              <option value=""></option>
              <option
                :for={{value, label} <- field.options}
                value={value}
                selected={field.value == value}
              >{label}</option>
            </select>
            <span
              :if={is_nil(field.variable) and field.widget == :select and field.glyphs != []}
              class="vis-builder-glyphs"
              role="radiogroup"
              aria-label={to_string(field.key)}
            >
              <label
                :for={{value, svg} <- field.glyphs}
                class={"vis-builder-glyph" <> if(field.value == value, do: " vis-builder-glyph-on", else: "")}
                title={value}
              >
                <input
                  type="radio"
                  name={field.key}
                  value={value}
                  checked={field.value == value}
                  aria-label={value}
                />
                {Phoenix.HTML.raw(svg)}
              </label>
            </span>
            <textarea
              :if={is_nil(field.variable) and field.widget == :textarea}
              name={field.key}
              placeholder={field.placeholder}
            >{field.value}</textarea>
            <ul :if={field.errors != []} class="vis-builder-key-errors">
              <li :for={line <- field.errors} class="vis-builder-error">{line}</li>
            </ul>
          </label>
        </form>
      </div>
      """
    end

    defp class(nil), do: "vis-builder-editor"
    defp class(extra), do: "vis-builder-editor " <> extra

    defp tab(facet, facet), do: "vis-builder-tab vis-builder-tab-open"
    defp tab(_facet, _open), do: "vis-builder-tab"

    # One field per key of the open tab: the control, what it shows, and the key's errors.
    defp fields(specs, open, %{node: node, path: path, errors: errors} = assigns) do
      refs = Map.get(assigns, :refs) || %{}

      for spec <- specs, spec.facet == open do
        widget = referenced(spec.type, refs)

        %{
          key: spec.key,
          ref: ref_field(spec.type),
          widget: shape(widget),
          glyphs: glyphs(spec.key, widget),
          range: range(spec.range),
          slider: slider(Map.fetch(node, spec.key), spec),
          dash: dash(spec.key, Map.get(node, spec.key)),
          options: options(widget),
          checked: Map.get(node, spec.key) == true,
          value: shown(widget, Map.fetch(node, spec.key)),
          slot: slot_name(widget, Map.get(node, spec.key)),
          variable: variable_name(Map.get(node, spec.key)),
          placeholder: shown(widget, default(spec)),
          errors: key_errors(errors, path ++ [spec.key])
        }
      end
    end

    # A reference is a choice among the names something declares, so where the caller knows
    # them it is a select rather than a box to spell a name into (spec/14 §18.14). `widget/1`
    # itself stays a function of the type alone, which is what makes it total over the schema.
    defp referenced({:ref, kind} = type, refs) do
      case Map.get(refs, kind) do
        [_ | _] = names -> {:select, names}
        _none -> widget(type)
      end
    end

    # A key whose type merely *admits* a reference — a style site takes a reference, an
    # inline node or a list of them (spec/14 §3.6) — is still a choice among declared names
    # wherever the caller knows them.
    defp referenced({:one_of, alts} = type, refs) do
      case Enum.find_value(alts, fn alt -> match?({:ref, _}, alt) and alt end) do
        {:ref, _kind} = ref -> narrowed(referenced(ref, refs), type)
        nil -> widget(type)
      end
    end

    defp referenced(type, _refs), do: widget(type)

    defp narrowed({:select, names}, _type), do: {:select, names}
    defp narrowed(_other, type), do: widget(type)

    # A field whose value is a variable is shown as one (spec/14 §19.9), never as the
    # struct's text in a textarea.
    defp variable_name(%Var{name: name}), do: to_string(name)
    defp variable_name(_value), do: nil

    defp shape({:select, _allowed}), do: :select
    defp shape(widget), do: widget

    defp range(nil), do: nil
    defp range({min, max, step}), do: %{min: min, max: max, step: step}

    # The slider stands at the value when it is a number, else at the default or the
    # range's floor: a slot word has no place on a slider, and the box still shows it.
    defp slider(_value, %{range: nil}), do: nil
    defp slider({:ok, n}, _spec) when is_number(n), do: n
    defp slider(_other, %{default: d}) when is_number(d), do: d
    defp slider(_other, %{range: {min, _max, _step}}), do: min

    # A dash pattern is seen, not decoded: the value as the SVG attribute it becomes.
    defp dash(:stroke_dasharray, value) when is_binary(value), do: value
    defp dash(:stroke_dasharray, value) when is_list(value), do: Enum.join(value, " ")
    defp dash(_key, _value), do: nil

    # A drawn enum is chosen by its picture (§18.6): one glyph per allowed value, where the
    # key is drawn and every value has one — `kind` is drawn for a frame and not a scale.
    defp glyphs(key, {:select, allowed}) do
      if Glyphs.drawn?(key) do
        pictures = Enum.map(allowed, &{option(&1), Glyphs.glyph(key, &1)})
        if Enum.all?(pictures, fn {_v, svg} -> svg != nil end), do: pictures, else: []
      else
        []
      end
    end

    defp glyphs(_key, _widget), do: []

    # A reference field is a drop target for a library entry of its kind (§19.10).
    defp ref_field({:ref, kind}), do: to_string(kind)
    defp ref_field({:one_of, alts}), do: Enum.find_value(alts, &ref_field/1)
    defp ref_field(_type), do: nil

    # An option is what the control submits and what a person reads: an id is spelt as the
    # DOM carries one, and read back through the same table (§19.2).
    defp options({:select, allowed}), do: Enum.map(allowed, &{option(&1), option(&1)})
    defp options(_widget), do: []

    defp option({kind, n}) when is_atom(kind) and is_integer(n), do: Store.encode_id({kind, n})
    defp option(value), do: to_string(value)

    # A colour is three things (§3.4): the slot face shows a slot, the picker a literal.
    defp slot_name(:colour, slot) when is_atom(slot) and not is_nil(slot), do: to_string(slot)
    defp slot_name(_widget, _value), do: nil

    defp default(%{required: true}), do: :error
    defp default(%{default: nil}), do: :error
    defp default(%{default: value}), do: {:ok, value}

    defp shown(_widget, :error), do: nil
    # A variable is shown by the name box, not the typed control (spec/14 §19.9).
    defp shown(_widget, {:ok, %Var{}}), do: nil
    # A slot is the select's, not the picker's; a picker shows only a hex it can.
    defp shown(:colour, {:ok, "#" <> _ = hex}), do: hex
    defp shown(:colour, {:ok, _other}), do: nil
    defp shown(:textarea, {:ok, value}), do: inspect(value)
    defp shown({:select, _}, {:ok, value}), do: option(value)
    defp shown(:select, {:ok, value}), do: option(value)
    defp shown(_widget, {:ok, value}), do: to_string(value)

    defp key_errors(errors, path) do
      for {at, _reason} = error <- errors, at == path, do: Validator.format(error)
    end
  end
end
