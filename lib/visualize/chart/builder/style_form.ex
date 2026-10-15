if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.StyleForm do
    @moduledoc """
    A style's form in its parts (spec/14 §18.7, D-178).

    A style is compound parts (§3.1, D-172), and its form is the whole element's keys —
    `extends`, `opacity`, `blend`, `class` — then one fieldset per part, in the schema's
    order: `fill`, `stroke`, `font`, `text`, `effect`, `marker`, `curve`, `transition`,
    `animation`, `enter`, `exit`. A part's controls are its own kind's keys, read from
    `Visualize.Chart.Schema.describe/1`; a node-typed key inside a part is a fieldset of its
    own, and a list of nodes — a gradient's stops — is rows. Nothing here lists a style key.

    A paint's `type` is its first control and decides which of its keys follow (§18.6); a
    part the element does not draw is grayed with a note, where the form is told the
    element's kind (§5.6).

    A control is named by its path within the style — `stroke.width`,
    `fill.stops.1.color`, `transition.fill.duration` — and `locate/2` reads a name back
    through the schema. `write/4` is what an edit at a path means for the node it lands
    in: the top-level parts it rewrites, a type change replacing what only the old type
    meant, a node in the flat keys of version 2 rewritten in its parts.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Builder.{Chain, Editor, Fields, Writes}
    alias Visualize.Chart.{Schema, Validator}
    alias Visualize.Chart.Style.Parts
    alias Visualize.Chart.Var

    # The node kinds edited in their parts: a style, and a container's defaults (§3.8),
    # whose keys are a style's parts and an entry per mark kind of the same parts.
    @kinds [:style, :defaults, :kind_defaults]

    # The suffixes a control's name may end in after its key's path (§18.6).
    @suffixes ["slot", "range", "other"]

    # The paint kinds, whose `type` decides which keys follow it (§18.6).
    @paint_kinds [:paint, :stroke]

    # The keys each paint type reads; every other key of a paint is every type's — its
    # opacity, and a stroke's line (spec/14 §3.5).
    @type_keys %{
      none: [],
      solid: [:color],
      linear: [:stops, :angle],
      radial: [:stops, :center, :radius],
      hatch: [:color, :pattern, :spacing, :width, :background],
      paint: [:name]
    }
    @typed Enum.uniq(Enum.flat_map(Map.values(@type_keys), & &1))

    # The picture a part's enum is chosen by (§18.6), by the kind and the key.
    @glyphs %{
      {:paint, :type} => :paint_type,
      {:stroke, :type} => :paint_type,
      {:stroke, :placement} => :stroke_style,
      {:stroke, :join} => :stroke_linejoin,
      {:stroke, :cap} => :stroke_linecap,
      {:effect, :type} => :effect,
      {:text_layout, :anchor} => :text_anchor,
      {:text_layout, :baseline} => :vertical_align,
      {:marker, :shape} => :symbol,
      {:curve, :type} => :curve
    }

    # A fresh gradient fades its color from 0.8 to 0.1: the area chart's convention.
    @fade [{0, 0.8}, {1, 0.1}]

    @doc """
    Whether a node kind is edited in its parts.

        iex> Visualize.Chart.Builder.StyleForm.kind?(:style)
        true

        iex> Visualize.Chart.Builder.StyleForm.kind?(:mark)
        false
    """
    @spec kind?(atom()) :: boolean()
    def kind?(kind), do: kind in @kinds

    # -- names and writes (spec/14 §18.7) -------------------------------------------------

    @doc """
    A control's name read back through the schema: the spec of the key at that path of a
    node of `kind`, the path, and the suffix the name ends in (`slot`, `range`, `other`, or
    `nil`). A font's `face` is the one name that is two keys: it answers the font's path
    with `face: true`. A name no key of the schema has is `nil`.

        iex> located = Visualize.Chart.Builder.StyleForm.locate(:style, "stroke.width.range")
        iex> {located.path, located.spec.type, located.suffix}
        {[:stroke, :width], :size, "range"}

        iex> Visualize.Chart.Builder.StyleForm.locate(:style, "fill.stops.1.color").path
        [:fill, :stops, 1, :color]

        iex> Visualize.Chart.Builder.StyleForm.locate(:style, "font.face")
        %{path: [:font], face: true}

        iex> Visualize.Chart.Builder.StyleForm.locate(:style, "stroke.nonsense")
        nil
    """
    @spec locate(atom(), String.t()) :: map() | nil
    def locate(kind, name) when is_binary(name), do: walk(kind, String.split(name, "."), [])

    defp walk(kind, [segment | rest], path) do
      case find(kind, segment) do
        nil when segment == "face" and rest == [] ->
          if faced?(kind), do: %{path: path, face: true}

        nil ->
          nil

        spec ->
          descend(spec, spec.type, rest, path ++ [spec.key])
      end
    end

    defp walk(_kind, [], _path), do: nil

    defp descend(spec, _type, [], path), do: %{path: path, spec: spec, suffix: nil}

    defp descend(spec, type, [suffix], path) when suffix in @suffixes do
      if node_type?(type), do: nil, else: %{path: path, spec: spec, suffix: suffix}
    end

    defp descend(_spec, {:node, kind}, rest, path), do: walk(kind, rest, path)

    defp descend(_spec, {:list, {:node, kind}}, [index | rest], path) do
      case Integer.parse(index) do
        {i, ""} when i >= 0 -> walk(kind, rest, path ++ [i])
        _other -> nil
      end
    end

    defp descend(_spec, _type, _rest, _path), do: nil

    defp find(kind, segment),
      do: Enum.find(Schema.describe(kind), &(to_string(&1.key) == segment))

    defp faced?(kind) do
      keys = Enum.map(Schema.describe(kind), & &1.key)
      :weight in keys and :style in keys
    end

    defp node_type?({:node, _kind}), do: true
    defp node_type?({:list, {:node, _kind}}), do: true
    defp node_type?(_type), do: false

    @doc """
    Every write a change to a style's form means (spec/14 §18.7): the control `target`
    submitted `value`, read at its path, written into `node` — the node the write lands in
    — with `seed` the style the site resolves to, which a type change starts a gradient
    from. A name that is no key is no write.

        iex> Visualize.Chart.Builder.StyleForm.changes(:style, "stroke.width", "7", %{}, %{})
        [stroke: {:ok, %{width: 7}}]

        iex> Visualize.Chart.Builder.StyleForm.changes(:style, "font.face", "light_italic", %{font: %{size: 12}}, %{})
        [font: {:ok, %{size: 12, weight: :light, style: :italic}}]

        iex> Visualize.Chart.Builder.StyleForm.changes(:style, "nonsense", "1", %{}, %{})
        []
    """
    @spec changes(atom(), String.t(), String.t() | nil, term(), term()) :: [
            {atom(), {:ok, term()} | :error}
          ]
    def changes(kind, target, value, node, seed) do
      case locate(kind, target) do
        nil ->
          []

        %{face: true, path: path} ->
          case Enum.find(Editor.faces(), fn {face, _w, _s} -> to_string(face) == value end) do
            {_face, weight, style} ->
              writes(
                node,
                [{path ++ [:weight], {:ok, weight}}, {path ++ [:style], {:ok, style}}],
                seed
              )

            nil ->
              []
          end

        %{path: path, spec: spec, suffix: suffix} ->
          parsed = spec.type |> read(suffix, value) |> picked(spec, path, node, seed)
          writes(node, [{path, parsed}], seed)
      end
    end

    # A slot face writes the slot's atom; a host's name the string; every other control
    # reads by its key's type (§18.6).
    # A name of the color table picked is a typed color, `color(:name)` (spec/14 §19.10).
    defp read(_type, "slot", value), do: Editor.named(value)

    defp read({:one_of, [{:enum, _}, :string]}, "other", value),
      do: Editor.submitted(:string, value)

    defp read(type, _suffix, value), do: Editor.submitted(type, value)

    # A color picked for a field holding a chain is the chain's new base (spec/14 §19.10):
    # the field's own value, else the one the site resolves to.
    defp picked({:ok, color}, %{type: :colour}, path, node, seed) do
      current =
        Writes.at(Parts.normalize(map_or_empty(node)), path) ||
          Writes.at(Parts.normalize(map_or_empty(seed)), path)

      {:ok, Chain.rebase(current, color)}
    end

    defp picked(parsed, _spec, _path, _node, _seed), do: parsed

    @doc """
    The top-level writes one edit at a path means for the node it lands in (spec/14 §18.7,
    D-178): `{key, {:ok, value}}` for each top-level key that changes, `{key, :error}` for
    each that goes. The node is read in its parts first, so a node written in the flat keys
    of version 2 is rewritten whole by its first edit. A key blanked removes itself and any
    part it leaves empty. Choosing a paint's `type` keeps only what no type decides and
    what the new one reads, starting a gradient, a solid or a hatch from the color the
    part — else `seed`'s part, the site's resolved style — has.

        iex> Visualize.Chart.Builder.StyleForm.write(%{stroke: :red, stroke_width: 2}, [:stroke, :width], {:ok, 5}, %{})
        [stroke: {:ok, %{type: :solid, color: :red, width: 5}}, stroke_width: :error]

        iex> Visualize.Chart.Builder.StyleForm.write(%{fill: %{type: :solid, color: "#abc", opacity: 0.5}}, [:fill, :type], {:ok, :linear}, %{})
        [fill: {:ok, %{type: :linear, opacity: 0.5, stops: [%{at: 0, color: "#abc", opacity: 0.8}, %{at: 1, color: "#abc", opacity: 0.1}]}}]

        iex> Visualize.Chart.Builder.StyleForm.write(%{stroke: %{width: 2}}, [:stroke, :width], :error, %{})
        [stroke: :error]
    """
    @spec write(term(), [atom() | non_neg_integer()], {:ok, term()} | :error, term()) :: [
            {atom(), {:ok, term()} | :error}
          ]
    def write(node, path, parsed, seed), do: writes(node, [{path, parsed}], seed)

    defp writes(node, edits, seed) do
      raw = if is_map(node) and not is_struct(node), do: node, else: %{}
      seed = if is_map(seed) and not is_struct(seed), do: Parts.normalize(seed), else: %{}

      edits
      |> Enum.reduce(Parts.normalize(raw), fn {path, parsed}, acc ->
        edit(acc, path, parsed, seed)
      end)
      |> diff(raw)
    end

    # A paint's type chosen: the part retyped; every other edit is a put at the path.
    defp edit(node, [part, :type], {:ok, type}, seed) when is_map_key(@type_keys, type) do
      case Map.get(node, part) do
        %Var{} -> Map.put(node, part, %{type: type})
        old -> Map.put(node, part, retyped(part, if(is_map(old), do: old, else: %{}), type, seed))
      end
    end

    defp edit(node, path, parsed, seed), do: node |> inherited(path, seed) |> put(path, parsed)

    # An edit inside a list the node does not hold — a stop's color at a site whose local
    # style has no stops — starts from the list the site resolves to, since a list is one
    # value and the local one replaces it whole (spec/14 §3.5).
    defp inherited(node, path, seed) do
      case Enum.find_index(path, &is_integer/1) do
        nil ->
          node

        at ->
          prefix = Enum.take(path, at)

          case {Writes.at(node, prefix), Writes.at(seed, prefix)} do
            {nil, list} when is_list(list) -> put(node, prefix, {:ok, list})
            _held -> node
          end
      end
    end

    defp retyped(part, old, type, seed) do
      # A stroke's `width` is its line's, every type's; a fill's is a hatch's.
      typed = if part == :stroke, do: @typed -- [:width], else: @typed
      kept = Map.drop(old, [:type | typed])
      own = Map.take(old, Map.fetch!(@type_keys, type))
      color = color(old) || color(Map.get(seed, part)) || {:color, :series_1}

      kept
      |> Map.merge(own)
      |> Map.put(:type, type)
      |> started(type, color)
    end

    defp started(paint, type, color) when type in [:linear, :radial] do
      if Map.has_key?(paint, :stops),
        do: paint,
        else:
          Map.put(paint, :stops, for({at, o} <- @fade, do: %{at: at, color: color, opacity: o}))
    end

    defp started(paint, type, color) when type in [:solid, :hatch],
      do: Map.put_new(paint, :color, color)

    defp started(paint, _type, _color), do: paint

    # The color a part has: its own, else its first stop's.
    defp color(%{color: color}) when color != nil, do: color
    defp color(%{stops: [%{color: color} | _]}), do: color
    defp color(_part), do: nil

    defp put(container, [key], parsed), do: set(container, key, parsed)

    defp put(container, [key | rest], parsed) do
      child =
        case {get(container, key), rest} do
          {nil, [i | _]} when is_integer(i) -> []
          {nil, _rest} -> %{}
          {%Var{}, _rest} -> %{}
          {child, _rest} -> child
        end

      updated = put(child, rest, parsed)
      set(container, key, if(empty?(updated), do: :error, else: {:ok, updated}))
    end

    defp get(map, key) when is_map(map), do: Map.get(map, key)
    defp get(list, i) when is_list(list) and is_integer(i), do: Enum.at(list, i)
    defp get(_other, _key), do: nil

    defp set(map, key, {:ok, value}) when is_map(map), do: Map.put(map, key, value)
    defp set(map, key, :error) when is_map(map), do: Map.delete(map, key)

    defp set(list, i, {:ok, value}) when is_list(list) and is_integer(i) do
      if i < length(list), do: List.replace_at(list, i, value), else: list ++ [value]
    end

    defp set(list, i, :error) when is_list(list) and is_integer(i), do: List.delete_at(list, i)

    defp empty?(value), do: value == %{} or value == []

    # The top-level keys whose value changed, in the node's key order then the new ones.
    defp diff(new, raw) do
      keys = Enum.uniq(Map.keys(raw) ++ Map.keys(new))

      for key <- Enum.sort_by(keys, &to_string/1),
          Map.fetch(raw, key) != Map.fetch(new, key) do
        case Map.fetch(new, key) do
          {:ok, value} -> {key, {:ok, value}}
          :error -> {key, :error}
        end
      end
    end

    @doc """
    The writes an item added to or removed from a list of nodes at `path` means — a
    gradient's stops (§18.6): `:add` appends a copy of the last item at the end of the
    list (a stop at `1`), `{:remove, i}` takes the item out. A node that holds no list
    there starts from `seed`'s, the list the site resolves to.

        iex> node = %{fill: %{type: :linear, stops: [%{at: 0, color: "#abc"}]}}
        iex> Visualize.Chart.Builder.StyleForm.item(node, [:fill, :stops], :add, %{})
        [fill: {:ok, %{type: :linear, stops: [%{at: 0, color: "#abc"}, %{at: 1, color: "#abc"}]}}]
    """
    @spec item(term(), [atom()], :add | {:remove, non_neg_integer()}, term()) :: [
            {atom(), {:ok, term()} | :error}
          ]
    def item(node, path, op, seed) do
      own = Writes.at(Parts.normalize(map_or_empty(node)), path)
      list = List.wrap(own || Writes.at(Parts.normalize(map_or_empty(seed)), path))

      updated =
        case op do
          :add -> list ++ [added(List.last(list))]
          {:remove, i} -> List.delete_at(list, i)
        end

      write(node, path, if(updated == [], do: :error, else: {:ok, updated}), seed)
    end

    defp map_or_empty(node) when is_map(node) and not is_struct(node), do: node
    defp map_or_empty(_node), do: %{}

    defp added(%{} = last), do: Map.put(last, :at, 1)
    defp added(_none), do: %{at: 1, color: {:color, :series_1}}

    # -- the form (spec/14 §18.7) ---------------------------------------------------------

    attr(:kind, :atom, required: true, doc: "the style kind: `:style`, `:defaults`")
    attr(:node, :any, required: true, doc: "the node, in any spelling the design reads")
    attr(:path, :list, default: [])
    attr(:label, :string, default: nil, doc: "the node's label, aimed at by every event")
    attr(:errors, :list, default: [])
    attr(:refs, :map, default: %{})
    attr(:selected, :string, default: nil)
    attr(:found, :string, default: nil)
    attr(:theme, :any, default: nil)
    attr(:defs, :map, default: %{})
    attr(:origins, :map, default: %{})
    attr(:guessed, :any, default: MapSet.new())
    attr(:event, :string, default: "edit", doc: "the event the form's changes push")

    attr(:drawn_by, :atom,
      default: nil,
      doc: "the kind of the element the style draws, whose undrawn parts are grayed (§5.6)"
    )

    attr(:target, :any, default: nil)

    @doc """
    Renders a style's controls in its parts (spec/14 §18.7): the whole element's keys, then
    a `<fieldset class="vis-builder-part">` per part, inside the caller's form.
    """
    def body(assigns) do
      node = shown(assigns.node)
      assigns = assign(assigns, :items, items(assigns.kind, node, [], assigns, true))

      ~H"""
      <div class="vis-builder-style-form">
        <.item :for={item <- @items} item={item} label={@label} selected={@selected} found={@found} event={@event} target={@target} />
      </div>
      """
    end

    attr(:item, :map, required: true)
    attr(:label, :string, default: nil)
    attr(:selected, :string, default: nil)
    attr(:found, :string, default: nil)
    attr(:event, :string, default: "edit")
    attr(:target, :any, default: nil)

    # One item of a style's form: a field, a part (or a node inside one), or a list's rows.
    defp item(%{item: %{kind: :field}} = assigns) do
      ~H"""
      <Fields.field field={@item.field} node_label={@label} selected={@selected} found={@found} target={@target} />
      """
    end

    defp item(%{item: %{kind: :part}} = assigns) do
      ~H"""
      <fieldset class={part_class(@item)} data-builder-part={@item.name}>
        <legend class="vis-builder-part-name">{@item.key}</legend>
        <p :if={@item.note} class="vis-builder-context-note vis-builder-part-note">{@item.note}</p>
        <p :if={@item.variable} class="vis-builder-context-note">{@item.name} = var(:{@item.variable})</p>
        <ul :if={@item.errors != []} class="vis-builder-key-errors">
          <li :for={line <- @item.errors} class="vis-builder-error">{line}</li>
        </ul>
        <.item :for={inner <- @item.items} item={inner} label={@label} selected={@selected} found={@found} event={@event} target={@target} />
      </fieldset>
      """
    end

    defp item(%{item: %{kind: :rows}} = assigns) do
      ~H"""
      <div class="vis-builder-part-rows" data-builder-rows={@item.name}>
        <span class="vis-builder-key">{@item.key}</span>
        <div :for={row <- @item.rows} class="vis-builder-part-row">
          <.item :for={inner <- row.items} item={inner} label={@label} selected={@selected} found={@found} event={@event} target={@target} />
          <button
            type="button"
            class="vis-builder-item-remove"
            phx-click="style_item"
            phx-value-field={@item.name}
            phx-value-op="remove"
            phx-value-index={row.index}
            phx-value-edit={@event}
            phx-value-node={@label}
            phx-target={@target}
            aria-label={"remove #{@item.name} #{row.index}"}
          >×</button>
        </div>
        <button
          type="button"
          class="vis-builder-part-add"
          phx-click="style_item"
          phx-value-field={@item.name}
          phx-value-op="add"
          phx-value-edit={@event}
          phx-value-node={@label}
          phx-target={@target}
          aria-label={"add to #{@item.name}"}
        >+ {singular(@item.key)}</button>
      </div>
      """
    end

    defp part_class(%{note: nil}), do: "vis-builder-part"
    defp part_class(_item), do: "vis-builder-part vis-builder-part-undrawn"

    defp singular(:stops), do: "stop"
    defp singular(key), do: to_string(key)

    # The node in its parts, for the form to show; a variable or anything else is empty.
    defp shown(node) when is_map(node) and not is_struct(node), do: Parts.normalize(node)
    defp shown(_node), do: %{}

    # The items of a node of `kind` at `prefix`: its keys in the schema's order, those its
    # paint type does not read left out, each a field, a part or a list's rows. `top?` is
    # the style itself, whose node-typed keys are its parts and may be grayed.
    defp items(kind, node, prefix, assigns, top?) do
      specs = kind |> Schema.describe() |> visible(kind, node)
      leaves = Enum.reject(specs, &node_type?(&1.type))

      fields =
        leaves
        |> Fields.views(assigns,
          prefix: prefix,
          node: node,
          glyph: &Map.get(@glyphs, {kind, &1.key})
        )
        |> Map.new(&{&1.key, &1})

      undrawn = if top? && assigns.drawn_by, do: Parts.undrawn(assigns.drawn_by), else: []

      Enum.flat_map(specs, fn spec ->
        case spec.type do
          {:node, inner} ->
            [part(inner, spec.key, Map.get(node, spec.key), prefix, assigns, spec.key in undrawn)]

          {:list, {:node, inner}} ->
            [rows(inner, spec.key, Map.get(node, spec.key), prefix, assigns)]

          _leaf ->
            case Map.fetch(fields, spec.key) do
              {:ok, field} -> [%{kind: :field, field: field}]
              :error -> []
            end
        end
      end)
    end

    defp part(kind, key, value, prefix, assigns, undrawn?) do
      path = prefix ++ [key]
      node = if is_map(value) and not is_struct(value), do: value, else: %{}

      %{
        kind: :part,
        key: key,
        name: join(path),
        note: if(undrawn?, do: "not drawn by " <> article(assigns.drawn_by)),
        variable: variable(value),
        # A fault of the part as a whole — a shorthand that does not read — is the part's.
        errors: errors(assigns, path),
        items: if(is_struct(value, Var), do: [], else: items(kind, node, path, assigns, false))
      }
    end

    defp rows(kind, key, value, prefix, assigns) do
      path = prefix ++ [key]
      list = if is_list(value), do: value, else: []

      %{
        kind: :rows,
        key: key,
        name: join(path),
        rows:
          for {row, i} <- Enum.with_index(list) do
            node = if is_map(row) and not is_struct(row), do: row, else: %{}
            %{index: i, items: items(kind, node, path ++ [i], assigns, false)}
          end
      }
    end

    # A paint shows the keys its type reads, and every type's (§18.6); any other kind all.
    defp visible(specs, kind, node) when kind in @paint_kinds do
      typed = if kind == :stroke, do: @typed -- [:width], else: @typed
      reads = Map.get(@type_keys, type_of(node), [])
      Enum.filter(specs, &(&1.key not in typed or &1.key in reads))
    end

    defp visible(specs, _kind, _node), do: specs

    defp type_of(%{type: type}) when is_atom(type), do: type
    defp type_of(_node), do: nil

    defp errors(assigns, path) do
      at = (assigns.path || []) ++ path
      for {^at, _reason} = error <- assigns.errors || [], do: Validator.format(error)
    end

    defp variable(%Var{name: name}), do: to_string(name)
    defp variable(_value), do: nil

    defp join(path), do: Enum.map_join(path, ".", &to_string/1)

    defp article(kind) do
      word = kind |> to_string() |> String.replace("_", " ")
      if String.first(word) in ~w(a e i o u), do: "an " <> word, else: "a " <> word
    end
  end
end
