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

    alias Visualize.Chart.Builder.{Fills, Glyphs, Store}
    alias Visualize.Chart.{Fragment, Schema, Text, Validator, Var}
    alias Visualize.Theme

    @typedoc "The control a key's type gets (spec/14 §18.6)."
    @type widget :: :checkbox | :number | :text | :textarea | {:select, [atom()]}

    @typedoc "One editable node of a fragment (spec/14 §18.5)."
    @type node_entry :: %{path: Validator.path(), kind: Schema.kind(), label: String.t()}

    # The facets in the order of spec/14 §1.3, which is the order of the editor's tabs.
    @facets [:binding, :channel, :geometry, :style, :content]

    # Every type that reads as a plain atom naming something the design declares.
    @atom_types [:name, :field, :slot]

    # Every type whose control is a single-line text field (spec/14 §18.6).
    @text_types [:string, :name, :field, :size, :font, :slot, :text]

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
    @doc """
    A path as a person reads it — `design` for the root, else `frame.scales.x`,
    `marks[0].channels` — the spelling `Visualize.Chart.Validator.format/1` uses (§18.5).

        iex> Visualize.Chart.Builder.Editor.label([:marks, 0, :style])
        "marks[0].style"
    """
    @spec label([atom() | non_neg_integer()]) :: String.t()
    def label([]), do: "design"

    def label(path) do
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
    # A list of scalars is a list of items, each with an ×, and a + to add one (§18.6).
    def widget({:list, scalar}) when is_atom(scalar) and scalar != :term, do: {:items, scalar}
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
    # A text is a string with interpolation (§7.1): kept as typed, and read by the
    # validator, so a hole that does not read is a fault under the field, not a refusal.
    defp read(:text, string), do: {:ok, string}
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

    `key` is the typed control and reads by `parse/2`; an unchecked checkbox submits
    nothing, which is `false` and not a removal, and every other control's blank removes
    the key. `key.slot` is a colour's slot face and `key.range` a number's slider, both
    read as the key. A variable reaches a field as a chip dropped on it (§19.9), never as
    a control of the form, so there is no `key.mode` or `key.var`.

        iex> Visualize.Chart.Builder.Editor.change(:style, %{"_target" => ["stroke_width"], "stroke_width" => "5"})
        {:stroke_width, {:ok, 5}}

        iex> Visualize.Chart.Builder.Editor.change(:style, %{"_target" => ["fill.slot"], "fill.slot" => ""})
        {:fill, :error}

        iex> Visualize.Chart.Builder.Editor.change(:style, %{"_target" => ["nonsense"], "nonsense" => "1"})
        nil
    """
    @spec change(atom(), map()) :: {atom(), {:ok, term()} | :error} | nil
    def change(kind, %{"_target" => [target]} = params) do
      case String.split(target, ".", parts: 2) do
        [key, "slot"] -> with %{key: k} <- key_spec(kind, key), do: {k, slot_face(params[target])}
        [key, "range"] -> with spec <- key_spec(kind, key), do: typed(spec, params[target])
        [_key, "add"] -> nil
        [key] -> with spec <- key_spec(kind, key), do: typed(spec, params[key])
      end
    end

    def change(_kind, _params), do: nil

    @faces [
      {:regular, :normal, :normal},
      {:italic, :normal, :italic},
      {:light, :light, :normal},
      {:light_italic, :light, :italic},
      {:medium, :medium, :normal},
      {:medium_italic, :medium, :italic},
      {:bold, :bold, :normal},
      {:bold_italic, :bold, :italic}
    ]

    @doc """
    Every write a change to the form means (spec/14 §18.6): one for most controls, as
    `change/2` reads it, and two for a `font_face` — the weight word and the style word
    of the face picked — since a face is one control over two keys.

        iex> Visualize.Chart.Builder.Editor.changes(:style, %{"_target" => ["font_face"], "font_face" => "light_italic"})
        [font_weight: {:ok, :light}, font_style: {:ok, :italic}]

        iex> Visualize.Chart.Builder.Editor.changes(:style, %{"_target" => ["font_face"], "font_face" => "regular"})
        [font_weight: {:ok, :normal}, font_style: {:ok, :normal}]

        iex> Visualize.Chart.Builder.Editor.changes(:style, %{"_target" => ["stroke_width"], "stroke_width" => "5"})
        [stroke_width: {:ok, 5}]

        iex> Visualize.Chart.Builder.Editor.changes(:style, %{"_target" => ["nonsense"], "nonsense" => "1"})
        []
    """
    @spec changes(atom(), map()) :: [{atom(), {:ok, term()} | :error}]
    def changes(kind, %{"_target" => ["font_face"], "font_face" => picked} = _params) do
      with true <- Schema.key(kind, :font_weight) != nil and Schema.key(kind, :font_style) != nil,
           {_face, weight, style} <- Enum.find(@faces, &(to_string(elem(&1, 0)) == picked)) do
        [font_weight: {:ok, weight}, font_style: {:ok, style}]
      else
        _other -> []
      end
    end

    def changes(kind, params), do: List.wrap(change(kind, params))

    @doc """
    The eight faces in order, each with the weight and style it writes (spec/14 §18.6).

        iex> hd(Visualize.Chart.Builder.Editor.faces())
        {:regular, :normal, :normal}
    """
    @spec faces() :: [{atom(), atom(), atom()}]
    def faces, do: @faces

    @doc """
    The face a weight and a style show as (spec/14 §18.6): one of the eight words. A
    missing key reads as `:normal`; an integer weight is the nearest of 300, 400, 500
    and 700.

        iex> Visualize.Chart.Builder.Editor.face(:bold, :italic)
        :bold_italic

        iex> Visualize.Chart.Builder.Editor.face(nil, nil)
        :regular

        iex> Visualize.Chart.Builder.Editor.face(650, nil)
        :bold

        iex> Visualize.Chart.Builder.Editor.face(250, :italic)
        :light_italic
    """
    @spec face(term(), term()) :: atom()
    def face(weight, style) do
      w = weight_word(weight)
      st = if style == :italic, do: :italic, else: :normal
      Enum.find_value(@faces, :regular, fn {face, fw, fs} -> fw == w and fs == st and face end)
    end

    defp weight_word(word) when word in [:light, :normal, :medium, :bold], do: word

    defp weight_word(n) when is_number(n),
      do:
        Enum.min_by([{300, :light}, {400, :normal}, {500, :medium}, {700, :bold}], fn {w, _} ->
          abs(w - n)
        end)
        |> elem(1)

    defp weight_word(_other), do: :normal

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

    attr(:id, :string, default: "vis-builder-editor", doc: "the panel's id")
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

    attr(:found, :string,
      default: nil,
      doc: "a variable name whose fields are highlighted (§19.10)"
    )

    attr(:theme, :any,
      default: nil,
      doc:
        "the `%Visualize.Theme{}` the design names, for what a colour well shows (spec/14 §19.10)"
    )

    attr(:defs, :map,
      default: %{},
      doc: "the design's paints, for a fill's style and its gradient's controls (spec/14 §18.6)"
    )

    attr(:strip, :boolean,
      default: true,
      doc: "render the facet strip; `false` where the caller does"
    )

    attr(:event, :string, default: "edit", doc: "the `phx-change` the form pushes")
    attr(:origins, :map, default: %{}, doc: "what supplied each key's value, by key")

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
        |> assign(:blocks, blocks(fields(specs, open, assigns)))

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
        <form
          id={@id <> "-form"}
          class="vis-builder-form"
          phx-change={@event}
          phx-hook="BuilderHook"
          phx-target={@target}
          data-builder-target={@target}
          data-builder-scope="ref"
          data-builder-edit={@event}
        >
          <%= for {group, fields} <- @blocks do %>
            <fieldset :if={group} class="vis-builder-block">
              <legend class="vis-builder-block-name">{group}</legend>
              <label :if={fill = fill_style(group, fields)} class="vis-builder-field vis-builder-field-fill-style">
                <span class="vis-builder-key">style</span>
                <span class="vis-builder-glyphs" role="radiogroup" aria-label="fill style">
                  <label
                    :for={{style, svg} <- fill.glyphs}
                    class={"vis-builder-glyph" <> if(fill.style == style, do: " vis-builder-glyph-on", else: "")}
                    title={style}
                  >
                    <input type="radio" name="fill_style" value={style} checked={fill.style == style} aria-label={style} />
                    {Phoenix.HTML.raw(svg)}
                  </label>
                </span>
              </label>
              <.field
                :for={field <- fields}
                field={field}
                selected={@selected}
                found={@found}
                origins={@origins}
                target={@target}
              />
            </fieldset>
            <.field
              :for={field <- fields}
              :if={is_nil(group)}
              field={field}
              selected={@selected}
              found={@found}
              origins={@origins}
              target={@target}
            />
          <% end %>
        </form>
      </div>
      """
    end

    attr(:field, :map, required: true)
    attr(:selected, :string, default: nil)
    attr(:found, :string, default: nil)
    attr(:origins, :map, default: %{})
    attr(:target, :any, default: nil)

    # One key of the form: its name, its control, its chip or its errors (spec/14 §18.7).
    defp field(assigns) do
      ~H"""
      <label
        class={field_class(@field, @selected, @found)}
        data-builder-ref={@field.ref && to_string(@field.key)}
        data-builder-bind={@field.key}
        phx-click="select_field"
        phx-keyup="select_field"
        phx-value-field={@field.key}
        phx-target={@target}
      >
        <span class="vis-builder-key">
          {@field.key}<span
            :if={@origins[@field.key]}
            class="vis-builder-origin"
          >{@origins[@field.key]}</span>
          <span
            :if={is_nil(@field.variable) and @field.value != nil}
            class="vis-builder-field-handle"
            draggable="true"
            data-builder-promote={@field.key}
            title="drag to the variables panel to make a variable of this value"
            aria-hidden="true"
          >⠿</span>
        </span>
        <span :if={@field.variable} class="vis-builder-var-chip vis-builder-var-chip-bound">
          var(:{@field.variable})
          <button
            type="button"
            class="vis-builder-var-unbind"
            phx-click="unbind_field"
            phx-value-field={@field.key}
            phx-target={@target}
            aria-label={"unbind #{@field.key} from #{@field.variable}"}
            title="unbind"
          >×</button>
        </span>
        <div :if={is_nil(@field.variable) and @field.fill && @field.fill.gradient} class="vis-builder-gradient">
          <span :for={stop <- @field.fill.stops} class="vis-builder-stop">
            <span
              class={well_class(stop.well)}
              style={"--vis-builder-swatch: #{stop.well.colour || "transparent"}"}
              title={stop.well.word || "no colour set"}
              role="img"
              aria-label={"stop #{stop.index}: #{stop.well.word || "not set"}"}
              data-builder-well={"fill.stop.#{stop.index}"}
              phx-click="select_field"
              phx-value-field={"fill.stop.#{stop.index}"}
              phx-target={@target}
            ></span>
            <input
              type="range"
              name={"fill.stop.#{stop.index}.opacity"}
              class="vis-builder-range"
              min="0"
              max="1"
              step="0.05"
              value={stop.opacity}
              aria-label={"stop #{stop.index} opacity"}
            />
          </span>
          <label :if={@field.fill.style == :linear} class="vis-builder-picker-row">
            <span class="vis-builder-control-label">angle</span>
            <input type="range" name="fill.angle" class="vis-builder-range" min="0" max="360" step="15" value={@field.fill.angle} aria-label="angle" />
            <span class="vis-builder-item-text">{@field.fill.angle}°</span>
          </label>
          <span :if={@field.fill.style == :radial} class="vis-builder-picker-row">
            <span class="vis-builder-control-label">centre</span>
            <input type="number" name="fill.centre.x" min="0" max="1" step="0.05" value={Enum.at(@field.fill.centre, 0)} aria-label="centre x" />
            <input type="number" name="fill.centre.y" min="0" max="1" step="0.05" value={Enum.at(@field.fill.centre, 1)} aria-label="centre y" />
          </span>
        </div>
        <input
          :if={is_nil(@field.variable) and @field.widget == :checkbox}
          type="checkbox"
          name={@field.key}
          value="true"
          checked={@field.checked}
        />
        <span :if={is_nil(@field.variable) and ranged?(@field)} class="vis-builder-ranged">
          <input
            :if={@field.widget == :number}
            type="number"
            name={@field.key}
            value={@field.value}
            placeholder={@field.placeholder}
          />
          <input
            :if={@field.widget == :text}
            type="text"
            name={@field.key}
            value={@field.value}
            placeholder={@field.placeholder}
          />
          <input
            type="range"
            name={"#{@field.key}.range"}
            class="vis-builder-range vis-builder-scrubber"
            min={@field.range.min}
            max={@field.range.max}
            step={@field.range.step}
            value={@field.slider}
            aria-label={"#{@field.key}, dragged"}
          />
        </span>
        <input
          :if={is_nil(@field.variable) and @field.widget == :number and not ranged?(@field)}
          type="number"
          name={@field.key}
          value={@field.value}
          placeholder={@field.placeholder}
        />
        <span
          :if={is_nil(@field.variable) and @field.widget == :faces}
          class="vis-builder-face-list"
          role="radiogroup"
          aria-label="face"
        >
          <label
            :for={row <- @field.faces}
            class={"vis-builder-face-row" <> if(row.on?, do: " vis-builder-face-row-on", else: "")}
            style={row.css}
          >
            <input type="radio" name="font_face" value={row.face} checked={row.on?} aria-label={row.label} />
            {row.label}
          </label>
        </span>
        <input
          :if={is_nil(@field.variable) and @field.widget == :text and not ranged?(@field)}
          type="text"
          name={@field.key}
          value={@field.value}
          placeholder={@field.placeholder}
          data-builder-text={@field.text? && "true"}
        />
        <span :if={is_nil(@field.variable) and @field.points != nil} class="vis-builder-item-text">
          {@field.points} pt between lines
        </span>
        <svg
          :if={is_nil(@field.variable) and @field.dash != nil}
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
            stroke-dasharray={@field.dash}
          />
        </svg>
        <span
          :if={is_nil(@field.variable) and @field.widget == :colour}
          class={well_class(@field.well)}
          style={"--vis-builder-swatch: #{@field.well.colour || "transparent"}"}
          title={@field.well.word || "no colour set"}
          role="img"
          aria-label={"#{@field.key}: #{@field.well.word || "not set"}"}
          data-builder-well={@field.key}
        ></span>
        <select
          :if={is_nil(@field.variable) and @field.widget == :select and @field.glyphs == []}
          name={@field.key}
        >
          <option value=""></option>
          <option
            :for={{value, label} <- @field.options}
            value={value}
            selected={@field.value == value}
          >{label}</option>
        </select>
        <span
          :if={is_nil(@field.variable) and @field.widget == :select and @field.glyphs != []}
          class="vis-builder-glyphs"
          role="radiogroup"
          aria-label={to_string(@field.key)}
        >
          <label
            :for={{value, svg} <- @field.glyphs}
            class={"vis-builder-glyph" <> if(@field.value == value, do: " vis-builder-glyph-on", else: "")}
            title={value}
          >
            <input
              type="radio"
              name={@field.key}
              value={value}
              checked={@field.value == value}
              aria-label={value}
            />
            {Phoenix.HTML.raw(svg)}
          </label>
        </span>
        <div :if={is_nil(@field.variable) and @field.widget == :items} class="vis-builder-items">
          <span :for={{item, index} <- Enum.with_index(@field.items)} class="vis-builder-item-row">
            <span :if={item.chip} class="vis-builder-var-chip vis-builder-var-chip-bound">var(:{item.chip})</span>
            <span :if={!item.chip} class="vis-builder-item-text">{item.text}</span>
            <button
              type="button"
              class="vis-builder-item-remove"
              phx-click="list_remove"
              phx-value-field={@field.key}
              phx-value-index={index}
              phx-target={@target}
              aria-label={"remove #{item.text || item.chip} from #{@field.key}"}
            >×</button>
          </span>
          <span class="vis-builder-item-add" data-builder-bind={@field.key}>
            <input
              type="text"
              name={"#{@field.key}.add"}
              class="vis-builder-item-box"
              placeholder="+ add"
              aria-label={"add to #{@field.key}"}
              phx-keydown="list_add"
              phx-key="Enter"
              phx-value-field={@field.key}
              phx-target={@target}
            />
          </span>
        </div>
        <textarea
          :if={is_nil(@field.variable) and @field.widget == :textarea}
          name={@field.key}
          placeholder={@field.placeholder}
        >{@field.value}</textarea>
        <ul :if={@field.errors != []} class="vis-builder-key-errors">
          <li :for={line <- @field.errors} class="vis-builder-error">{line}</li>
        </ul>
      </label>
      """
    end

    # A ranged number's box and slider share one span, the slider over the box (§18.6).
    defp ranged?(field), do: field.range != nil and field.widget in [:number, :text]

    # The fill block opens with the fill style (§18.6): the fill field's view, when it has one.
    defp fill_style(:fill, fields) do
      case Enum.find(fields, &(&1.key == :fill)) do
        %{variable: nil, fill: fill} -> fill
        _other -> nil
      end
    end

    defp fill_style(_group, _fields), do: nil

    # The open tab's fields as runs of one group (spec/14 §18.7): a run with a group is a
    # block under its heading; a run with none is fields on their own.
    defp blocks(fields), do: Enum.chunk_by(fields, & &1.group) |> Enum.map(&{hd(&1).group, &1})

    defp class(nil), do: "vis-builder-editor"
    defp class(extra), do: "vis-builder-editor " <> extra

    defp tab(facet, facet), do: "vis-builder-tab vis-builder-tab-open"
    defp tab(_facet, _open), do: "vis-builder-tab"

    # One field per key of the open tab: the control, what it shows, and the key's errors.
    defp fields(specs, open, %{node: node, path: path, errors: errors} = assigns) do
      refs = Map.get(assigns, :refs) || %{}

      faced? = Enum.any?(specs, &(&1.key == :font_style))

      for spec <- specs, spec.facet == open, not (faced? and spec.key == :font_style) do
        widget = referenced(spec.type, refs)

        %{
          key: spec.key,
          faces: if(faced? and spec.key == :font_weight, do: face_rows(node), else: []),
          # The face list stands in for the weight's box (§18.6).
          widget: if(faced? and spec.key == :font_weight, do: :faces, else: shape(widget)),
          group: spec.group,
          ref: ref_field(spec.type),
          text?: spec.type == :text,
          glyphs: glyphs(spec.key, widget),
          range: range(spec.range),
          slider: slider(Map.fetch(node, spec.key), spec),
          dash: dash(spec.key, Map.get(node, spec.key)),
          items: items(widget, Map.get(node, spec.key)),
          options: options(widget),
          checked: Map.get(node, spec.key) == true,
          value: shown(widget, as_text(spec, Map.fetch(node, spec.key))),
          well:
            well(
              widget,
              Map.get(node, spec.key),
              Map.get(assigns, :theme),
              Map.get(assigns, :defs) || %{}
            ),
          fill: fill_view(assigns.kind, spec.key, Map.get(node, spec.key), assigns),
          points: points(spec.key, node, Map.get(assigns, :theme)),
          variable: if(spec.type == :text, do: nil, else: variable_name(Map.get(node, spec.key))),
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
    defp shape({:items, _scalar}), do: :items
    defp shape(widget), do: widget

    defp field_class(field, selected, found) do
      ["vis-builder-field"]
      |> then(&if field.errors != [], do: &1 ++ ["vis-builder-field-needs"], else: &1)
      |> then(
        &if selected == to_string(field.key), do: &1 ++ ["vis-builder-field-selected"], else: &1
      )
      |> then(
        &if found != nil and field.variable == found,
          do: &1 ++ ["vis-builder-field-found"],
          else: &1
      )
      |> Enum.join(" ")
    end

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

    # The face list's rows (§18.6): each face with its picture's weight and slant, the
    # node's own face marked.
    defp face_rows(node) do
      shown = face(Map.get(node, :font_weight), Map.get(node, :font_style))

      for {face, weight, style} <- @faces do
        %{
          face: face,
          on?: face == shown,
          css: "font-weight: #{css_weight(weight)}; font-style: #{style}",
          label: face |> to_string() |> String.replace("_", " ")
        }
      end
    end

    defp css_weight(:light), do: 300
    defp css_weight(:normal), do: 400
    defp css_weight(:medium), do: 500
    defp css_weight(:bold), do: 700

    # A list of scalars as its rows: a chip for a variable, the text for anything else.
    defp items({:items, _scalar}, list) when is_list(list) do
      Enum.map(list, fn
        %Var{name: name} -> %{chip: to_string(name), text: nil}
        item when is_binary(item) -> %{chip: nil, text: item}
        item -> %{chip: nil, text: to_string(item)}
      end)
    end

    defp items(_widget, _value), do: []

    # A text shows as its string whichever form holds it (§7.1): a list of parts, or a
    # whole variable, is written as the string with its holes.
    defp as_text(%{type: :text}, {:ok, value}) when is_list(value) or is_struct(value, Var),
      do: {:ok, Text.unparse(List.wrap(value))}

    defp as_text(_spec, value), do: value

    # A paint's well shows its gradient's first stop, under the paint's name (§18.6).
    defp well(:colour, {:paint, name}, theme, defs) do
      case Map.get(defs, name) do
        %{stops: [%{colour: colour} | _]} -> %{well(colour, theme) | word: to_string(name)}
        _other -> %{colour: nil, none?: false, word: to_string(name)}
      end
    end

    defp well(:colour, value, theme, _defs), do: well(value, theme)
    defp well(_widget, _value, _theme, _defs), do: %{colour: nil, none?: false, word: nil}

    # The points between lines a line height means (§18.6): font_size × (line_height − 1),
    # from the node's font size or the theme's.
    defp points(:line_height, node, theme) do
      height = number_or(Map.get(node, :line_height), Schema.default(:style, :line_height) || 1.2)
      size = number_or(Map.get(node, :font_size), (theme && theme.font_size) || 12)
      Float.round(size * (height - 1) * 1.0, 1)
    end

    defp points(_key, _node, _theme), do: nil

    defp number_or(n, _default) when is_number(n), do: n
    defp number_or(_other, default), do: default

    # A style's fill is a fill style (§18.6); any other colour is a well alone.
    defp fill_view(:style, :fill, value, assigns) when not is_struct(value, Var) do
      defs = Map.get(assigns, :defs) || %{}
      view = Fills.view(value, defs, Fills.name(assigns.path))
      theme = Map.get(assigns, :theme)

      %{view | stops: Enum.map(view.stops, &Map.put(&1, :well, well(&1.colour, theme)))}
      |> Map.put(:glyphs, Enum.map(Fills.styles(), &{&1, Glyphs.glyph(:fill_style, &1)}))
    end

    defp fill_view(_kind, _key, _value, _assigns), do: nil

    defp well_class(%{none?: true}), do: "vis-builder-well vis-builder-well-none"
    defp well_class(%{colour: nil}), do: "vis-builder-well vis-builder-well-empty"
    defp well_class(_well), do: "vis-builder-well"

    @doc """
    What a colour well shows for a value (spec/14 §19.10): the colour it resolves to — a
    slot through the theme, a literal as itself — with the value's word as the title;
    `:none` as no paint; anything else, or no theme for a slot, as nothing.

        iex> Visualize.Chart.Builder.Editor.well("#3b6fa8", Visualize.Theme.default())
        %{colour: "#3b6fa8", none?: false, word: "#3b6fa8"}

        iex> Visualize.Chart.Builder.Editor.well(:series_1, Visualize.Theme.default())
        %{colour: "#3b6fa8", none?: false, word: "series_1"}

        iex> Visualize.Chart.Builder.Editor.well(:none, nil)
        %{colour: nil, none?: true, word: "none"}

        iex> Visualize.Chart.Builder.Editor.well(nil, nil)
        %{colour: nil, none?: false, word: nil}
    """
    @spec well(term(), Theme.t() | nil) :: %{
            colour: String.t() | nil,
            none?: boolean(),
            word: String.t() | nil
          }
    def well(nil, _theme), do: %{colour: nil, none?: false, word: nil}
    def well(:none, _theme), do: %{colour: nil, none?: true, word: "none"}
    def well("#" <> _ = hex, _theme), do: %{colour: hex, none?: false, word: hex}

    def well({:series, i}, %Theme{} = theme) when is_integer(i) and i >= 1,
      do: well(Theme.series_slot(theme, i), theme)

    def well(slot, %Theme{} = theme) when is_atom(slot) do
      if slot in Theme.colour_slots(theme),
        do: %{colour: Theme.resolve(theme, slot, :literal), none?: false, word: to_string(slot)},
        else: %{colour: nil, none?: false, word: to_string(slot)}
    end

    def well(slot, _theme) when is_atom(slot),
      do: %{colour: nil, none?: false, word: to_string(slot)}

    def well(value, _theme) when is_binary(value), do: %{colour: value, none?: false, word: value}
    def well(_value, _theme), do: %{colour: nil, none?: false, word: nil}

    defp default(%{required: true}), do: :error
    defp default(%{default: nil}), do: :error
    defp default(%{default: value}), do: {:ok, value}

    defp shown(_widget, :error), do: nil
    # A variable is shown by the name box, not the typed control (spec/14 §19.9).
    defp shown(_widget, {:ok, %Var{}}), do: nil
    # A colour is the well's to show, never a control's.
    defp shown(:colour, {:ok, _value}), do: nil
    defp shown(:textarea, {:ok, value}), do: inspect(value)
    defp shown({:select, _}, {:ok, value}), do: option(value)
    defp shown({:items, _}, {:ok, _value}), do: nil
    defp shown(:items, {:ok, _value}), do: nil
    defp shown(:select, {:ok, value}), do: option(value)
    defp shown(_widget, {:ok, value}), do: to_string(value)

    defp key_errors(errors, path) do
      for {at, _reason} = error <- errors, at == path, do: Validator.format(error)
    end
  end
end
