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

    alias Visualize.Chart.Builder.{Chain, Fields, Store, StyleForm}
    alias Visualize.Chart.{Fragment, Schema, Validator, Var}
    alias Visualize.Theme

    @typedoc "The control a key's type gets (spec/14 §18.6)."
    @type widget ::
            :checkbox | :number | :text | :textarea | {:select, [atom()]} | {:pool, [String.t()]}

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

        iex> fragment = %{version: 2, frames: %{main: %{kind: :cartesian}}}
        iex> Enum.map(Visualize.Chart.Builder.Editor.nodes(fragment), & &1.label)
        ["design", "frames.main"]
        iex> Enum.map(Visualize.Chart.Builder.Editor.nodes(fragment), & &1.kind)
        [:design, :frame]

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

    # A style's parts are its form's, not nodes of the strip (§18.7, D-178).
    defp children(_node, kind, _path) when kind in [:style, :defaults, :kind_defaults], do: []

    defp children(node, kind, path) do
      Enum.flat_map(describe(kind), fn spec ->
        case Map.fetch(node, spec.key) do
          {:ok, value} -> descend(spec.type, value, path ++ [spec.key])
          :error -> []
        end
      end)
    end

    defp descend({:node, kind}, value, path) when is_map(value) and not is_struct(value),
      do: walk(value, kind, path)

    # A map of nodes, or of nodes and something else — a frame's `scales`, whose entry may
    # be a scale adopted from another frame (spec/14 §4.3, #384). An entry that is not a
    # node descends to nothing, as any value does.
    defp descend({:map, inner}, value, path)
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

    @doc """
    A path as a person reads it — `design` for the root, else `frame.scales.x`,
    `marks[0].channels` — `Visualize.Chart.Validator.format_path/1`, the one spelling an
    error, a node label and a rendered `data-node` share (§4.7, §18.5).

        iex> Visualize.Chart.Builder.Editor.label([:marks, 0, :style])
        "marks[0].style"
    """
    @spec label([atom() | non_neg_integer()]) :: String.t()
    def label(path), do: Validator.format_path(path)

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
        iex> Visualize.Chart.Builder.Editor.widget({:node, :margin})
        :textarea

    """
    @spec widget(Schema.type()) :: widget()
    def widget(:boolean), do: :checkbox
    def widget(type) when type in [:integer, :number], do: :number
    def widget({:enum, allowed}), do: {:select, allowed}
    def widget(:color), do: :color
    def widget(type) when type in @text_types, do: :text
    def widget({:ref, _kind}), do: :text
    # A channel is a field's name or a constant, an extent `auto` or `min, max` (#371).
    def widget(type) when type in [:channel, :extent], do: :text
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
        iex> Visualize.Chart.Builder.Editor.parse(:color, "#3b6fa8")
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

    defp read(type, string) when type in [:color, :size, :font], do: {:ok, loose(string)}

    defp read({:enum, allowed}, string) do
      case Enum.find(allowed, &(to_string(&1) == string)) do
        nil -> :error
        value -> {:ok, value}
      end
    end

    # A choice of types reads as the first alternative that takes the string, the first
    # first: an animation's `iterations` is a number or `infinite` (spec/14 §3.11).
    defp read({:one_of, alternatives}, string) do
      Enum.reduce_while(alternatives, :error, fn alternative, :error ->
        case read(alternative, string) do
          {:ok, value} -> {:halt, {:ok, value}}
          :error -> {:cont, :error}
        end
      end)
    end

    # A channel: a number is the constant, a bare name the field, anything else a literal.
    defp read(:channel, string) do
      with :error <- number(string) do
        if Regex.match?(~r/^[a-z_][a-zA-Z0-9_?!]*$/, string),
          do: {:ok, String.to_atom(string)},
          else: literal(string)
      end
    end

    # An extent: `auto`, or `min, max` of numbers, ISO 8601 date-times or `auto`; else the
    # literal forms a design can hold (§4.1).
    defp read(:extent, "auto"), do: {:ok, :auto}

    defp read(:extent, string) do
      case String.split(string, ",") do
        [lo, hi] ->
          with {:ok, lo} <- bound(String.trim(lo)), {:ok, hi} <- bound(String.trim(hi)) do
            {:ok, [lo, hi]}
          else
            :error -> literal(string)
          end

        _other ->
          literal(string)
      end
    end

    defp read(_type, string), do: literal(string)

    defp bound("auto"), do: {:ok, :auto}

    defp bound(string) do
      with :error <- number(string) do
        case DateTime.from_iso8601(string) do
          {:ok, at, _offset} -> {:ok, at}
          _other -> :error
        end
      end
    end

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
    the key. `key.slot` is a colour's name face (written `color(:name)`), `key.range` a number's slider and
    `key.other` a name the list lacks, each read as the key. A variable reaches a field as
    a chip dropped on it (§19.9), never as a control of the form, so there is no
    `key.mode` or `key.var`. A style's controls are named by their path and read by
    `changes/3` (§18.7).

        iex> Visualize.Chart.Builder.Editor.change(:mark, %{"_target" => ["data"], "data" => "rows"})
        {:data, {:ok, :rows}}

        iex> Visualize.Chart.Builder.Editor.change(:theme, %{"_target" => ["axis.slot"], "axis.slot" => ""})
        {:axis, :error}

        iex> Visualize.Chart.Builder.Editor.change(:mark, %{"_target" => ["nonsense"], "nonsense" => "1"})
        nil
    """
    @spec change(atom(), map()) :: {atom(), {:ok, term()} | :error} | nil
    def change(kind, %{"_target" => [target]} = params) do
      case String.split(target, ".", parts: 2) do
        [key, "slot"] -> with %{key: k} <- key_spec(kind, key), do: {k, slot_face(params[target])}
        [key, "range"] -> with spec <- key_spec(kind, key), do: typed(spec, params[target])
        [key, "other"] -> with spec <- key_spec(kind, key), do: typed(spec, params[target])
        [_key, "add"] -> nil
        [key] -> with spec <- key_spec(kind, key), do: typed(spec, params[key])
        _other -> nil
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
    Every write a change to the form means (spec/14 §18.6, §18.7), for the node the write
    lands in: one for most controls, as `change/2` reads it; for a style, the top-level
    parts the change rewrites (`Visualize.Chart.Builder.StyleForm.changes/5`) — a font's
    `face` both its keys, a node in the flat keys of version 2 every part. `seed` is the
    style the site resolves to, which a paint's type change starts from.

        iex> Visualize.Chart.Builder.Editor.changes(:style, %{"_target" => ["font.face"], "font.face" => "light_italic"}, %{})
        [font: {:ok, %{weight: :light, style: :italic}}]

        iex> Visualize.Chart.Builder.Editor.changes(:style, %{"_target" => ["stroke.width"], "stroke.width" => "5"}, %{stroke: %{color: "#111"}})
        [stroke: {:ok, %{type: :solid, color: "#111", width: 5}}]

        iex> Visualize.Chart.Builder.Editor.changes(:mark, %{"_target" => ["data"], "data" => "rows"}, %{})
        [data: {:ok, :rows}]

        iex> Visualize.Chart.Builder.Editor.changes(:style, %{"_target" => ["nonsense"], "nonsense" => "1"}, %{})
        []
    """
    @spec changes(atom(), map(), term(), term()) :: [{atom(), {:ok, term()} | :error}]
    def changes(kind, params, node, seed \\ nil)

    def changes(kind, %{"_target" => [target]} = params, node, seed) do
      if StyleForm.kind?(kind),
        do: StyleForm.changes(kind, target, params[target], node, seed || node),
        else: kind |> change(params) |> List.wrap() |> Enum.map(&picked(kind, &1, node))
    end

    def changes(_kind, _params, _node, _seed), do: []

    # A color picked for a key holding a chain is the chain's new base (spec/14 §19.10).
    defp picked(kind, {key, {:ok, color}} = write, node) do
      case key_spec(kind, to_string(key)) do
        %{type: :color} when is_map(node) ->
          {key, {:ok, Chain.rebase(Map.get(node, key), color)}}

        _other ->
          write
      end
    end

    defp picked(_kind, write, _node), do: write

    @doc """
    A name of the color table, as a picked patch submits it, read as the typed color it
    names, `color(:name)` (spec/08 §1.9, spec/14 §19.10); a blank is `:error`, a removal.

        iex> Visualize.Chart.Builder.Editor.named("axis")
        {:ok, {:color, :axis}}

        iex> Visualize.Chart.Builder.Editor.named("")
        :error
    """
    @spec named(String.t() | nil) :: {:ok, term()} | :error
    def named(nil), do: :error

    def named(string) when is_binary(string) do
      case parse(:slot, string) do
        {:ok, name} -> {:ok, {:color, name}}
        :error -> :error
      end
    end

    @doc false
    # The key spec a field's name reads as, and its path within the node (spec/14 §18.7,
    # D-178): a key of the kind, or — for a style — a part's key by its path. `nil` for a
    # name the kind has no key for.
    @spec locate(atom(), String.t()) :: %{path: list(), spec: map()} | nil
    def locate(kind, name) when is_binary(name) do
      if StyleForm.kind?(kind) do
        case StyleForm.locate(kind, name) do
          %{spec: _spec} = located -> located
          _face_or_none -> nil
        end
      else
        case key_spec(kind, name) do
          nil -> nil
          spec -> %{path: [spec.key], spec: spec, suffix: nil}
        end
      end
    end

    def locate(_kind, _name), do: nil

    @doc false
    # The writes a value at a path of a node means: the key's own, or for a style the parts
    # it rewrites (§18.7).
    @spec write(atom(), term(), list(), {:ok, term()} | :error) :: [
            {atom(), {:ok, term()} | :error}
          ]
    def write(kind, node, path, parsed) do
      case {StyleForm.kind?(kind), path} do
        {true, _path} -> StyleForm.write(node, path, parsed, node)
        {false, [key]} -> [{key, parsed}]
      end
    end

    @doc false
    # The value at a field's path of a node, the node read in its parts for a style.
    @spec value_at(atom(), term(), list()) :: term()
    def value_at(kind, node, path) do
      node =
        if StyleForm.kind?(kind) and is_map(node),
          do: Visualize.Chart.Style.normalize(node),
          else: node

      Visualize.Chart.Builder.Writes.at(node, path)
    end

    @doc false
    # The schema as the form shows it: a node's `defaults` (spec/14 §3.8, #651) wait for
    # their editor (#684), and a fragment that carries them keeps them.
    @spec describe(atom()) :: [Schema.key_spec()]
    def describe(kind), do: kind |> Schema.describe() |> Enum.reject(&(&1.key == :defaults))

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
      Enum.find(describe(kind), &(to_string(&1.key) == submitted))
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

    # A colour's name face: a name of the theme's color table, typed, or — blank — the key removed.
    defp slot_face(string), do: named(string)

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
      specs = describe(kind)
      Enum.filter(@facets, fn facet -> Enum.any?(specs, &(&1.facet == facet)) end)
    end

    attr(:id, :string,
      default: nil,
      doc: "the editor's id, which its form carries as `<id>-form`; nil derives it from the node"
    )

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

    attr(:pool, :list,
      default: [],
      doc: "the names of the host's sample sources, for a source's `default` (spec/14 §19.10)"
    )

    attr(:hidden, :list,
      default: [],
      doc:
        "keys the host keeps out of a `:source` form — `default` when it binds by name alone (§19.10)"
    )

    attr(:strip, :boolean,
      default: true,
      doc: "render the facet strip; `false` where the caller does"
    )

    attr(:event, :string, default: "edit", doc: "the `phx-change` the form pushes")
    attr(:origins, :map, default: %{}, doc: "what supplied each key's value, by key")
    attr(:label, :string, default: nil, doc: "the node's label, carried by the form (§18.16)")
    attr(:only, :list, default: nil, doc: "the keys to show; nil for the open facet's")

    attr(:drawn_by, :atom,
      default: nil,
      doc: "for a style, the kind of the element it draws: its undrawn parts are grayed (§18.7)"
    )

    attr(:columns, :map,
      default: %{},
      doc: "the columns the pool's rows have, by source name (§18.6)"
    )

    attr(:source_name, :any, default: nil, doc: "the name a keyed source site is declared under")

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
      facets = facets(assigns.kind)
      open = if assigns.facet in facets, do: assigns.facet, else: List.first(facets)

      assigns =
        assigns
        |> assign(:facets, facets)
        |> assign(:open, open)

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
        <.form_body {form_assigns(assigns)} />
      </div>
      """
    end

    @doc """
    One node's form alone (spec/14 §18.7): the fields of one facet — or, with `only`, of the
    listed keys — as the controls `widget/1` chose, carrying the node's label so an edit in
    it aims at the node (`_node`, `data-builder-node`, §18.16).
    """
    attr(:id, :string,
      default: nil,
      doc: "the editor's id, which the form carries as `<id>-form`; nil derives it from the node"
    )

    attr(:kind, :atom, required: true)
    attr(:node, :map, required: true)
    attr(:path, :list, default: [])

    attr(:label, :string,
      default: nil,
      doc: "the node's label, aimed at by every event of the form"
    )

    attr(:facet, :atom, default: nil)

    attr(:only, :list,
      default: nil,
      doc: "the keys to show, in schema order; nil for the facet's"
    )

    attr(:errors, :list, default: [])
    attr(:refs, :map, default: %{})
    attr(:selected, :string, default: nil)
    attr(:found, :string, default: nil)
    attr(:theme, :any, default: nil)
    attr(:defs, :map, default: %{})
    attr(:pool, :list, default: [])
    attr(:hidden, :list, default: [])

    attr(:columns, :map,
      default: %{},
      doc: "the columns the pool's rows have, by source name (§18.6)"
    )

    attr(:source_name, :any, default: nil, doc: "the name a keyed source site is declared under")
    attr(:channel_columns, :map, default: %{})
    attr(:event, :string, default: "edit")
    attr(:origins, :map, default: %{})

    attr(:locked, :boolean,
      default: false,
      doc: "the node is the library's: the fields are disabled under a note (§18.15)"
    )

    attr(:unlock, :any,
      default: nil,
      doc: "the row of the locked owner, which *unlock* on the note takes (§18.8, #381)"
    )

    attr(:guessed, :any,
      default: MapSet.new(),
      doc: "the field labels — `marks[0].channels.x` — a placed mark guessed (§18.16)"
    )

    attr(:target, :any, default: nil)

    attr(:drawn_by, :atom,
      default: nil,
      doc: "for a style, the kind of the element it draws: its undrawn parts are grayed (§18.7)"
    )

    def form_body(assigns) do
      facets = facets(assigns.kind)
      open = if assigns.facet in facets, do: assigns.facet, else: List.first(facets)
      style? = StyleForm.kind?(assigns.kind)
      only = Map.get(assigns, :only)

      fields =
        if style?,
          do: [],
          else:
            assigns.kind
            |> describe()
            |> Enum.filter(&if(only, do: &1.key in only, else: &1.facet == open))
            |> Fields.views(assigns)

      assigns =
        assigns
        |> assign(:open, open)
        |> assign(:style?, style?)
        |> assign(:form_id, form_id(assigns))
        |> assign(:fields, fields)

      ~H"""
        <form
          id={@form_id}
          class="vis-builder-form"
          phx-change={@event}
          phx-hook="BuilderHook"
          phx-target={@target}
          data-builder-target={@target}
          data-builder-scope="ref"
          data-builder-edit={@event}
          data-builder-node={@label}
          phx-submit="submitted"
        >
          <input :if={@label} type="hidden" name="_node" value={@label} />
          <p :if={@locked} class="vis-builder-context-note vis-builder-locked-note">
            from the library — open it to edit
            <button :if={@label} type="button" class="vis-builder-section-select-button" phx-click="copy_node" phx-value-node={@label} phx-target={@target}>copy</button>
            <button :if={@label} type="button" class="vis-builder-section-select-button" phx-click="override_node" phx-value-node={@label} phx-target={@target}>override</button>
            <button :if={@unlock != nil} type="button" class="vis-builder-section-select-button" title="unlock — copy the entry into this chart and edit it here (spec/14 §18.8)" phx-click="unlock_site" phx-value-index={@unlock} phx-target={@target}>unlock</button>
          </p>
          <fieldset class={"vis-builder-form-body" <> if(@locked, do: " vis-builder-form-locked", else: "")} disabled={@locked}>
          <StyleForm.body
            :if={@style?}
            kind={@kind}
            node={@node}
            path={@path}
            label={@label}
            errors={@errors}
            refs={@refs}
            selected={@selected}
            found={@found}
            theme={@theme}
            defs={@defs}
            origins={@origins}
            guessed={@guessed}
            event={@event}
            drawn_by={@drawn_by}
            target={@target}
          />
          <Fields.field
            :for={field <- @fields}
            field={field}
            node_label={@label}
            selected={@selected}
            found={@found}
            target={@target}
          />
          </fieldset>
        </form>
      """
    end

    # The assigns a panel hands its form: everything the form takes, nothing more.
    @form_keys [
      :id,
      :kind,
      :node,
      :path,
      :label,
      :facet,
      :only,
      :errors,
      :refs,
      :selected,
      :found,
      :theme,
      :defs,
      :pool,
      :hidden,
      :columns,
      :source_name,
      :channel_columns,
      :event,
      :origins,
      :drawn_by,
      :target
    ]
    defp form_assigns(assigns), do: Map.take(assigns, @form_keys)

    # The form's id (spec/10 §15.3, #444): LiveView recovers a form only by its id, so it is
    # the caller's when given and otherwise the node's — its label, else its path, else (at
    # the root) its kind — which tells two node forms on one page apart.
    defp form_id(%{id: id}) when is_binary(id), do: id <> "-form"
    defp form_id(assigns), do: "vis-builder-editor-" <> id_segment(node_name(assigns)) <> "-form"

    defp node_name(%{label: label}) when is_binary(label), do: label
    defp node_name(%{path: [_ | _] = path}), do: label(path)
    defp node_name(%{kind: kind}), do: to_string(kind)

    # A name as a run of an HTML id: letters and digits, every other run one `-`.
    defp id_segment(name), do: name |> String.replace(~r/[^A-Za-z0-9]+/, "-") |> String.trim("-")

    defp class(nil), do: "vis-builder-editor"
    defp class(extra), do: "vis-builder-editor " <> extra

    defp tab(facet, facet), do: "vis-builder-tab vis-builder-tab-open"
    defp tab(_facet, _open), do: "vis-builder-tab"

    @doc """
    What a colour well shows for a value (spec/14 §19.10): the colour it resolves to — a
    slot or a typed colour through the theme, a literal as itself — with the value's word
    as the title; `:none` as no paint; anything else, or no theme for a slot, as nothing.

        iex> Visualize.Chart.Builder.Editor.well("#3b6fa8", Visualize.Theme.default())
        %{color: "#3b6fa8", none?: false, word: "#3b6fa8"}

        iex> Visualize.Chart.Builder.Editor.well(:series_1, Visualize.Theme.default())
        %{color: "#3b6fa8", none?: false, word: "series_1"}

        iex> Visualize.Chart.Builder.Editor.well({:color, :series_1}, Visualize.Theme.default())
        %{color: "#3b6fa8", none?: false, word: "series_1"}

        iex> Visualize.Chart.Builder.Editor.well({:alpha, "#ff0000", 0.5}, Visualize.Theme.default())
        %{color: "#ff000080", none?: false, word: "alpha(#ff0000, 0.5)"}

        iex> Visualize.Chart.Builder.Editor.well(:none, nil)
        %{color: nil, none?: true, word: "none"}

        iex> Visualize.Chart.Builder.Editor.well(nil, nil)
        %{color: nil, none?: false, word: nil}
    """
    @spec well(term(), Theme.t() | nil) :: %{
            color: String.t() | nil,
            none?: boolean(),
            word: String.t() | nil
          }
    def well(value, theme), do: Fields.well(value, theme)
  end
end
