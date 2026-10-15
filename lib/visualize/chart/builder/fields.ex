if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Fields do
    @moduledoc false
    # The fields of a form (spec/14 §18.6, §18.7): one key's control — its name, the widget
    # `Visualize.Chart.Builder.Editor.widget/1` chose, what it shows, its chip or its errors
    # — and the views a form builds its fields from. A node's form (`Editor.form_body/1`)
    # and a style's form in its parts (`Visualize.Chart.Builder.StyleForm`) draw the same
    # fields; a part's key is named by its path within the node (`stroke.width`, D-178).
    #
    # Split from `Visualize.Chart.Builder.Editor`, which had grown past what one module
    # should hold; compiled only with `Phoenix.Component`, as the builder is (spec/10 §1.1,
    # D-45, D-85).

    use Phoenix.Component

    alias Visualize.Chart.Builder.{Chain, Editor, Glyphs, Store}
    alias Visualize.Chart.{Text, Validator, Var}
    alias Visualize.Chart.Validator.Units
    alias Visualize.{Color, Theme}

    attr(:field, :map, required: true)
    attr(:label, :string, default: nil, doc: "the title shown instead of the key's name")

    attr(:node_label, :string,
      default: nil,
      doc: "the node's label, aimed at by the field's events"
    )

    attr(:selected, :string, default: nil)
    attr(:found, :string, default: nil)
    attr(:target, :any, default: nil)

    @doc false
    # One key of the form: its name, its control, its chip or its errors (spec/14 §18.7).
    def field(assigns) do
      ~H"""
      <label
        :if={wrapper(@field) == :label}
        class={field_class(@field, @selected, @found)}
        title={if(Map.get(@field, :guess?), do: "guessed from the source's fields — check it")}
        data-builder-ref={@field.ref && @field.name}
        data-builder-bind={@field.name}
        phx-keyup="select_field"
        phx-value-field={@field.name}
        phx-target={@target}
      >
        <.body field={@field} label={@label} node_label={@node_label} target={@target} />
      </label>
      <div
        :if={wrapper(@field) == :div}
        class={field_class(@field, @selected, @found)}
        title={if(Map.get(@field, :guess?), do: "guessed from the source's fields — check it")}
        data-builder-ref={@field.ref && @field.name}
        data-builder-bind={@field.name}
        phx-keyup="select_field"
        phx-value-field={@field.name}
        phx-target={@target}
      >
        <.body field={@field} label={@label} node_label={@node_label} target={@target} />
      </div>
      """
    end

    attr(:field, :map, required: true)
    attr(:label, :string, default: nil)
    attr(:node_label, :string, default: nil)
    attr(:target, :any, default: nil)

    # What a field holds, whichever element wraps it.
    defp body(assigns) do
      ~H"""
        <span class="vis-builder-key">
          {@label || @field.key}<span
            :if={@field.origin}
            class="vis-builder-origin"
          >{@field.origin}</span>
          <span
            :if={is_nil(@field.variable) and @field.value != nil}
            class="vis-builder-field-handle"
            draggable="true"
            data-builder-promote={@field.name}
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
            phx-value-field={@field.name}
            phx-value-node={@node_label}
            phx-target={@target}
            aria-label={"unbind #{@field.name} from #{@field.variable}"}
            title="unbind"
          >×</button>
        </span>
        <input
          :if={is_nil(@field.variable) and @field.widget == :checkbox}
          type="checkbox"
          name={@field.name}
          value="true"
          checked={@field.checked}
        />
        <span :if={is_nil(@field.variable) and ranged?(@field)} class="vis-builder-ranged">
          <input
            :if={@field.widget == :number}
            type="number"
            name={@field.name}
            value={@field.value}
            placeholder={@field.placeholder}
          />
          <input
            :if={@field.widget == :text}
            type="text"
            name={@field.name}
            value={@field.value}
            placeholder={@field.placeholder}
          />
          <input
            type="range"
            name={"#{@field.name}.range"}
            class="vis-builder-range vis-builder-scrubber"
            style={scrub(@field.slider, @field.range.min, @field.range.max)}
            min={@field.range.min}
            max={@field.range.max}
            step={@field.range.step}
            value={@field.slider}
            aria-label={"#{@field.name}, dragged"}
          />
        </span>
        <input
          :if={is_nil(@field.variable) and @field.widget == :number and not ranged?(@field)}
          type="number"
          name={@field.name}
          value={@field.value}
          placeholder={@field.placeholder}
        />
        <select
          :if={is_nil(@field.variable) and @field.widget == :faces}
          name={@field.face_name}
          class="vis-builder-face-select"
          style={Enum.find_value(@field.faces, &(&1.on? and &1.css))}
          aria-label="face"
        >
          <option :for={row <- @field.faces} value={row.face} style={row.css} selected={row.on?}>
            {row.label}
          </option>
        </select>
        <input
          :if={is_nil(@field.variable) and @field.widget == :text and not ranged?(@field)}
          type="text"
          name={@field.name}
          value={@field.value}
          placeholder={@field.placeholder}
          data-builder-text={@field.text? && "true"}
        />
        <select
          :if={is_nil(@field.variable) and @field.units != []}
          name={"#{@field.name}.unit"}
          class="vis-builder-unit"
          aria-label={"#{@field.name}, its unit"}
        >
          <option value="" selected={@field.unit == nil}>units</option>
          <option :for={unit <- @field.units} value={unit} selected={@field.unit == unit}>{unit_word(unit)}</option>
        </select>
        <span :if={is_nil(@field.variable) and @field.widget == :pair} class="vis-builder-pair">
          <input
            :for={{member, i} <- Enum.with_index(@field.pair)}
            type="number"
            name={"#{@field.name}.#{i}"}
            value={member}
            step="0.05"
            aria-label={"#{@field.name} #{i}"}
          />
        </span>
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
          :if={is_nil(@field.variable) and @field.widget == :color}
          class={well_class(@field.well)}
          style={"--vis-builder-swatch: #{@field.well.color || "transparent"}"}
          title={@field.well.word || "no colour set"}
          role="img"
          aria-label={"#{@field.name}: #{@field.well.word || "not set"}"}
          data-builder-well={@field.name}
        ></span>
        <div :if={is_nil(@field.variable) and @field.widget == :pool} class="vis-builder-pool" role="radiogroup" aria-label={@field.name}>
          <label class={"vis-builder-pool-name" <> if(@field.value == nil, do: " vis-builder-pool-name-on", else: "")}>
            <input type="radio" name={@field.name} value="" checked={@field.value == nil} />
            none
          </label>
          <label
            :for={{value, label} <- @field.options}
            class={"vis-builder-pool-name" <> if(@field.value == value, do: " vis-builder-pool-name-on", else: "")}
          >
            <input type="radio" name={@field.name} value={value} checked={@field.value == value} />
            {label}
          </label>
        </div>
        <input
          :if={is_nil(@field.variable) and @field.widget == :pool}
          type="text"
          name={"#{@field.name}.other"}
          class="vis-builder-declared-name"
          placeholder="or a name the pool lacks"
          aria-label={"#{@field.name}, a name the pool lacks"}
        />
        <select
          :if={is_nil(@field.variable) and @field.widget == :select and @field.glyphs == []}
          name={@field.name}
        >
          <option value=""></option>
          <option
            :for={{value, label} <- @field.options}
            :if={@field.option_groups == nil}
            value={value}
            selected={@field.value == value}
          >{label}</option>
          <optgroup :for={{group, options} <- @field.option_groups || []} label={group}>
            <option
              :for={{value, label} <- options}
              value={value}
              selected={@field.value == value}
            >{label}</option>
          </optgroup>
        </select>
        <input
          :if={is_nil(@field.variable) and @field.other}
          type="text"
          name={"#{@field.name}.other"}
          class="vis-builder-declared-name"
          value={@field.other_value}
          placeholder="or a name the list lacks"
          aria-label={"#{@field.name}, a name the list lacks"}
        />
        <span
          :if={is_nil(@field.variable) and @field.widget == :select and @field.glyphs != []}
          class="vis-builder-glyphs"
          role="radiogroup"
          aria-label={@field.name}
        >
          <label
            :for={{value, svg} <- @field.glyphs}
            class={"vis-builder-glyph" <> if(@field.value == value, do: " vis-builder-glyph-on", else: "")}
            title={value}
          >
            <input
              type="radio"
              name={@field.name}
              value={value}
              checked={@field.value == value}
              aria-label={value}
            />
            {Phoenix.HTML.raw(svg)}
          </label>
        </span>
        <div
          :if={is_nil(@field.variable) and @field.widget == :items and @field.picks}
          class="vis-builder-pool vis-builder-picks"
          role="group"
          aria-label={"#{@field.name}: the columns the rows have"}
        >
          <label
            :for={pick <- @field.picks}
            class={"vis-builder-pool-name" <> if(pick.on?, do: " vis-builder-pool-name-on", else: "") <> if(pick.missing?, do: " vis-builder-pool-name-missing", else: "")}
            title={if(pick.missing?, do: "#{pick.name} — not in the rows", else: pick.name)}
          >
            <input type="checkbox" name={"#{@field.name}.pick[]"} value={pick.name} checked={pick.on?} />
            {pick.name}
          </label>
        </div>
        <div :if={is_nil(@field.variable) and @field.widget == :items} class="vis-builder-items">
          <span :for={{item, index} <- Enum.with_index(@field.items)} :if={!@field.picks or item.chip} class="vis-builder-item-row">
            <span :if={item.chip} class="vis-builder-var-chip vis-builder-var-chip-bound">var(:{item.chip})</span>
            <span :if={!item.chip} class="vis-builder-item-text">{item.text}</span>
            <button
              type="button"
              class="vis-builder-item-remove"
              phx-click="list_remove"
              phx-value-field={@field.name}
              phx-value-node={@node_label}
              phx-value-index={index}
              phx-target={@target}
              aria-label={"remove #{item.text || item.chip} from #{@field.name}"}
            >×</button>
          </span>
          <span class="vis-builder-item-add" data-builder-bind={@field.name}>
            <input
              type="text"
              name={"#{@field.name}.add"}
              class="vis-builder-item-box"
              placeholder="+ add"
              aria-label={"add to #{@field.name}"}
              phx-keydown="list_add"
              phx-key="Enter"
              phx-value-field={@field.name}
              phx-value-node={@node_label}
              phx-target={@target}
            />
          </span>
        </div>
        <textarea
          :if={is_nil(@field.variable) and @field.widget == :textarea}
          name={@field.name}
          placeholder={@field.placeholder}
        >{@field.value}</textarea>
        <ul :if={@field.errors != []} class="vis-builder-key-errors">
          <li :for={line <- @field.errors} class="vis-builder-error">{line}</li>
        </ul>
      """
    end

    # A key is a `<label>`; a radio group of glyphs is a `<div>`, so a click on the key's
    # word picks no radio — a label would hand the click to its first (§18.7).
    defp wrapper(%{glyphs: [_ | _]}), do: :div
    defp wrapper(_field), do: :label

    # The scrubber's bar (§18.6): the value's fraction of its range, as a custom property.
    defp scrub(value, min, max)
         when is_number(value) and is_number(min) and is_number(max) and max > min do
      fraction = (value - min) / (max - min)
      "--vis-builder-scrub: #{Float.round(min(max(fraction, 0), 1) * 100 * 1.0, 1)}%"
    end

    defp scrub(_value, _min, _max), do: "--vis-builder-scrub: 0%"

    # A ranged number's box and slider share one span, the slider over the box (§18.6).
    defp ranged?(field), do: field.range != nil and field.widget in [:number, :text]

    @doc false
    # One field per spec: the control, what it shows, and the key's errors. `assigns` is the
    # form's — the node's kind, path, errors, refs, theme, pool and the rest; `opts` say
    # where the specs' keys sit within the node (`prefix`, D-178), which node holds them
    # (`node`, the node's own by default), how a key's enum is drawn (`glyph`, the key
    # itself by default) and what supplied each value (`origins`).
    def views(specs, assigns, opts \\ []) do
      prefix = Keyword.get(opts, :prefix, [])
      node = Keyword.get(opts, :node, assigns.node)
      node = if is_map(node) and not is_struct(node), do: node, else: %{}
      glyph = Keyword.get(opts, :glyph, & &1.key)
      # A style's form (§18.7): sizes take a unit select, pairs two boxes.
      units? = Keyword.get(opts, :units, false)
      kind = Keyword.get(opts, :kind, assigns.kind)
      origins = Keyword.get(opts, :origins, Map.get(assigns, :origins) || %{})
      refs = Map.get(assigns, :refs) || %{}
      faced? = Enum.any?(specs, &(&1.key == :style)) and Enum.any?(specs, &(&1.key == :weight))
      pool = Map.get(assigns, :pool) || []
      hidden = if assigns.kind == :source, do: Map.get(assigns, :hidden) || [], else: []
      path = Map.get(assigns, :path) || []
      errors = Map.get(assigns, :errors) || []

      for spec <- specs,
          spec.key not in hidden,
          not (faced? and spec.key == :style) do
        widget =
          (pooled(assigns.kind, spec.key, pool) || columned(assigns, spec) ||
             referenced(spec.type, refs))
          |> chosen(spec.type, Map.get(node, spec.key))

        name = name(prefix, spec.key)
        value = Map.get(node, spec.key)
        face? = faced? and spec.key == :weight

        %{
          key: spec.key,
          name: name,
          origin: origin(origins, prefix, spec.key, name),
          guess?:
            MapSet.member?(
              Map.get(assigns, :guessed) || MapSet.new(),
              guess_label(assigns, name)
            ),
          faces: if(face?, do: face_rows(node), else: []),
          face_name: name(prefix, :face),
          # The face list stands in for the weight's box (§18.6); a pair is two boxes.
          widget:
            cond do
              face? -> :faces
              units? and pair(spec, value) != nil -> :pair
              true -> shape(widget)
            end,
          ref: ref_field(spec.type),
          text?: spec.type == :text,
          glyphs: glyphs(glyph.(spec), widget),
          other: other?(spec.type),
          # A size's unit, chosen beside its box (§18.6, #684), where the caller asks.
          units: units_of(units?, kind, spec, value),
          unit: unit_of(value),
          pair: if(units?, do: pair(spec, value)),
          other_value: other_value(spec.type, value),
          range: range(spec.range),
          slider: slider(Map.fetch(node, spec.key), spec),
          dash: dash(spec.key, prefix, value),
          items: items(widget, value),
          options: options(widget),
          option_groups: option_groups(widget),
          checked: value == true,
          value: shown(widget, as_text(spec, Map.fetch(node, spec.key))),
          well: well(widget, value, Map.get(assigns, :theme), Map.get(assigns, :defs) || %{}),
          points: points(spec.key, prefix, node, Map.get(assigns, :theme)),
          picks: picks(assigns.kind, spec.key, value, assigns),
          variable: if(spec.type == :text, do: nil, else: variable_name(value)),
          placeholder: placeholder(assigns, spec, widget),
          errors: key_errors(errors, path ++ prefix ++ [spec.key])
        }
      end
    end

    # A control's name: the key, or its path within the node joined by `.` (D-178).
    defp name([], key), do: to_string(key)
    defp name(prefix, key), do: Enum.map_join(prefix ++ [key], ".", &to_string/1)

    # What supplied a field's value: a top-level key by its key, a part's key by its path,
    # else by the part it is in (the layer that gives the part gives its keys, §18.15).
    defp origin(origins, [], key, _name), do: Map.get(origins, key)

    defp origin(origins, [part | _], _key, name),
      do: Map.get(origins, name) || Map.get(origins, part)

    # A source's default is a pool name, chosen where the host's pool is known (§19.10).
    defp pooled(:source, :default, [_ | _] = pool), do: {:pool, pool}
    defp pooled(_kind, _key, _pool), do: nil

    # A channel on a mark whose source the editor knows picks from its columns (§18.6,
    # #371): the select when the value is unbound or one of them, else the text box with
    # the value as it is, so a literal or a lost column is never hidden.
    defp columned(%{kind: :channels, node: node, path: path} = assigns, %{key: key}) do
      case Map.get(Map.get(assigns, :channel_columns) || %{}, path) do
        [_ | _] = columns ->
          value = Map.get(node, key)

          if value == nil or Enum.any?(columns, &(&1.name == value)),
            do: {:columns, columns},
            else: nil

        _none ->
          nil
      end
    end

    defp columned(_assigns, _spec), do: nil

    # A channel with no source to pick from says what to do first.
    defp placeholder(%{kind: :channels} = assigns, _spec, :text) do
      if Map.get(Map.get(assigns, :channel_columns) || %{}, assigns.path) in [nil, []],
        do: "bind data first",
        else: nil
    end

    defp placeholder(_assigns, spec, widget), do: shown(widget, default(spec))

    # A reference is a choice among the names something declares, so where the caller knows
    # them it is a select rather than a box to spell a name into (spec/14 §18.14). `widget/1`
    # itself stays a function of the type alone, which is what makes it total over the schema.
    defp referenced({:ref, kind} = type, refs) do
      case Map.get(refs, kind) do
        # Names in groups — a style's (§18.14, #685): one optgroup each.
        [{group, _names} | _] = groups when is_binary(group) -> {:select_groups, groups}
        [_ | _] = names -> {:select, names}
        _none -> Editor.widget(type)
      end
    end

    # A key whose type merely *admits* a reference — a style site takes a reference, an
    # inline node or a list of them (spec/14 §3.6) — is still a choice among declared names
    # wherever the caller knows them.
    defp referenced({:one_of, alts} = type, refs) do
      case Enum.find_value(alts, fn alt -> match?({:ref, _}, alt) and alt end) do
        {:ref, _kind} = ref -> narrowed(referenced(ref, refs), type)
        nil -> Editor.widget(type)
      end
    end

    defp referenced(type, _refs), do: Editor.widget(type)

    # A select shows one name; a value it cannot — a stack of several, an inline node — is
    # a literal, which shows the whole value (§18.18 edits a stack).
    defp chosen({select, _names} = widget, _type, value)
         when select in [:select, :select_groups] do
      if is_list(value) or (is_map(value) and not is_struct(value)),
        do: :textarea,
        else: widget
    end

    defp chosen(widget, _type, _value), do: widget

    defp narrowed({:select, names}, _type), do: {:select, names}
    defp narrowed({:select_groups, groups}, _type), do: {:select_groups, groups}
    defp narrowed(_other, type), do: Editor.widget(type)

    # A choice of words or a host's name — an animation's `name` (spec/14 §3.11) — is the
    # select with a box for the name the list lacks (§18.7).
    defp other?({:one_of, [{:enum, _allowed}, :string]}), do: true
    defp other?(_type), do: false

    defp other_value({:one_of, [{:enum, _allowed}, :string]}, value) when is_binary(value),
      do: value

    defp other_value(_type, _value), do: nil

    # A field whose value is a variable is shown as one (spec/14 §19.9), never as the
    # struct's text in a textarea.
    defp variable_name(%Var{name: name}), do: to_string(name)
    defp variable_name(_value), do: nil

    defp shape({:select, _allowed}), do: :select
    defp shape({:select_groups, _groups}), do: :select
    defp shape({:columns, _columns}), do: :select
    defp shape({:pool, _names}), do: :pool
    defp shape({:items, _scalar}), do: :items
    defp shape(widget), do: widget

    # The label a guess is kept under: the node's label and the key (§18.16).
    defp guess_label(%{label: label}, name) when is_binary(label), do: "#{label}.#{name}"
    defp guess_label(_assigns, name), do: name

    defp field_class(field, selected, found) do
      ["vis-builder-field"]
      |> then(&if field.errors != [], do: &1 ++ ["vis-builder-field-needs"], else: &1)
      |> then(&if Map.get(field, :guess?), do: &1 ++ ["vis-builder-field-guess"], else: &1)
      |> then(&if selected == field.name, do: &1 ++ ["vis-builder-field-selected"], else: &1)
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

    # A dash pattern is seen, not decoded: a stroke's `dash` as the SVG attribute it becomes.
    defp dash(:dash, [:stroke], value) when is_binary(value), do: value

    defp dash(:dash, [:stroke], value) when is_list(value),
      do: Enum.map_join(value, " ", &dash_member/1)

    defp dash(_key, _prefix, _value), do: nil

    defp dash_member({n, _unit}), do: to_string(n)
    defp dash_member(n), do: to_string(n)

    # A drawn enum is chosen by its picture (§18.6): one glyph per allowed value, where the
    # key is drawn and every value has one — `kind` is drawn for a frame and not a scale.
    defp glyphs(key, {:select, allowed}) when is_atom(key) and key != nil do
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

    defp options({:columns, columns}),
      do: Enum.map(columns, &{to_string(&1.name), column_word(&1)})

    defp options({:pool, names}), do: Enum.map(names, &{&1, &1})
    defp options(_widget), do: []

    defp option_groups({:select_groups, groups}) do
      for {group, names} <- groups, names != [] do
        {group, Enum.map(names, &{option(&1), option(&1)})}
      end
    end

    defp option_groups(_widget), do: nil

    defp option({kind, n}) when is_atom(kind) and is_integer(n), do: Store.encode_id({kind, n})
    defp option(value), do: to_string(value)

    defp column_word(%{name: name, type: nil}), do: to_string(name)
    defp column_word(%{name: name, type: type}), do: "#{name} · #{type}"

    # The face list's rows (§18.6): each face with its picture's weight and slant, the
    # font's own face marked.
    defp face_rows(node) do
      shown = Editor.face(Map.get(node, :weight), Map.get(node, :style))

      for {face, weight, style} <- Editor.faces() do
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

    # A source's fields as the columns its rows have (§18.6): every column and every
    # declared name, sorted, the declared ones on, a declared name the rows lack marked;
    # nil when the source has no rows to offer.
    defp picks(:source, :fields, value, assigns) do
      name =
        Map.get(assigns, :source_name) ||
          case Map.get(assigns, :path) do
            [:sources, name] -> name
            _other -> nil
          end

      case name && Map.get(Map.get(assigns, :columns) || %{}, name) do
        columns when is_list(columns) and columns != [] ->
          declared = for item <- List.wrap(value), is_atom(item), do: to_string(item)

          for column <- Enum.sort(Enum.uniq(columns ++ declared)) do
            %{name: column, on?: column in declared, missing?: column not in columns}
          end

        _none ->
          nil
      end
    end

    defp picks(_kind, _key, _value, _assigns), do: nil

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

    # An extent is `auto` or `min, max`; a channel that is neither a name nor a number is
    # its literal (#371).
    defp as_text(%{type: :extent}, {:ok, value}), do: {:ok, extent_text(value)}

    defp as_text(%{type: :channel}, {:ok, value}) when not (is_atom(value) or is_number(value)),
      do: {:ok, inspect(value)}

    # A size or a length written in a unit, `{12, :pt}`: the box shows the number, the unit
    # select the unit (§18.6, #684).
    defp as_text(%{type: type}, {:ok, {n, unit}})
         when type in [:size, :length] and is_number(n) and is_atom(unit),
         do: {:ok, n}

    defp as_text(_spec, value), do: value

    # The units a size may be written in, where the form offers a unit select (§18.6): none
    # for a slot word, a variable or a key with no unit.
    defp units_of(false, _kind, _spec, _value), do: []

    defp units_of(true, kind, %{type: type, key: key}, value) when type in [:size, :length] do
      if is_atom(value) and value != nil, do: [], else: Units.units(kind, key)
    end

    defp units_of(true, _kind, _spec, _value), do: []

    defp unit_of({n, unit}) when is_number(n) and is_atom(unit), do: unit
    defp unit_of(_value), do: nil

    defp unit_word(:pct), do: "%"
    defp unit_word(unit), do: to_string(unit)

    # A pair of numbers — a gradient's centre — as two boxes, from the default where the
    # key has none (§18.6, #684).
    defp pair(%{type: {:list, :number}, default: [_, _] = default}, value) do
      case value do
        [a, b] when is_number(a) and is_number(b) -> [a, b]
        _other -> default
      end
    end

    defp pair(_spec, _value), do: nil

    defp extent_text(:auto), do: "auto"
    defp extent_text([lo, hi]), do: "#{bound_text(lo)}, #{bound_text(hi)}"
    defp extent_text(other), do: inspect(other)

    defp bound_text(:auto), do: "auto"
    defp bound_text(%DateTime{} = at), do: DateTime.to_iso8601(at)
    defp bound_text(n) when is_number(n), do: to_string(n)
    defp bound_text(other), do: inspect(other)

    # A paint's well shows its gradient's first stop, under the paint's name (§18.6).
    defp well(:color, {:paint, name}, theme, defs) do
      case Map.get(defs, name) do
        %{stops: [%{color: colour} | _]} -> %{well(colour, theme) | word: to_string(name)}
        _other -> %{color: nil, none?: false, word: to_string(name)}
      end
    end

    defp well(:color, value, theme, _defs), do: well(value, theme)
    defp well(_widget, _value, _theme, _defs), do: %{color: nil, none?: false, word: nil}

    @doc false
    # What a colour well shows for a value (spec/14 §19.10); `Editor.well/2` is its face.
    def well(nil, _theme), do: %{color: nil, none?: false, word: nil}
    def well(:none, _theme), do: %{color: nil, none?: true, word: "none"}
    def well("#" <> _ = hex, _theme), do: %{color: hex, none?: false, word: hex}

    def well({:series, i}, %Theme{} = theme) when is_integer(i) and i >= 1,
      do: well(Theme.series_slot(theme, i), theme)

    # A name of the theme's colour table, written typed (spec/08 §1.9, D-173).
    def well({:color, name}, theme) when is_atom(name), do: well(name, theme)

    def well(slot, %Theme{} = theme) when is_atom(slot) do
      if slot in Theme.color_slots(theme),
        do: %{color: Theme.resolve(theme, slot, :literal), none?: false, word: to_string(slot)},
        else: %{color: nil, none?: false, word: to_string(slot)}
    end

    def well(slot, _theme) when is_atom(slot),
      do: %{color: nil, none?: false, word: to_string(slot)}

    def well(value, _theme) when is_binary(value), do: %{color: value, none?: false, word: value}

    # A transform of colours (D-173): the colour it computes to, under its expression, where
    # every name it reads is the theme's; else the expression alone.
    def well(value, theme) do
      cond do
        not Color.value?(value) ->
          %{color: nil, none?: false, word: nil}

        is_struct(theme, Theme) and resolvable?(value, theme) ->
          %{
            color: Color.resolve(value, theme, :literal),
            none?: false,
            word: Chain.expression(value)
          }

        true ->
          %{color: nil, none?: false, word: Chain.expression(value)}
      end
    end

    defp resolvable?(value, theme) do
      names = Theme.color_slots(theme)
      value |> Color.Typed.names() |> Enum.all?(&(&1 in names))
    end

    # The points between lines a line height means (§18.6): size × (line_height − 1), from
    # the font's size or the theme's.
    defp points(:line_height, [:font], node, theme) do
      height = number_or(Map.get(node, :line_height), 1.2)
      size = number_or(Map.get(node, :size), (theme && theme.font_size) || 12)
      Float.round(size * (height - 1) * 1.0, 1)
    end

    defp points(_key, _prefix, _node, _theme), do: nil

    defp number_or(n, _default) when is_number(n), do: n
    defp number_or(_other, default), do: default

    defp well_class(%{none?: true}), do: "vis-builder-well vis-builder-well-none"
    defp well_class(%{color: nil}), do: "vis-builder-well vis-builder-well-empty"
    defp well_class(_well), do: "vis-builder-well"

    defp default(%{required: true}), do: :error
    defp default(%{default: nil}), do: :error
    defp default(%{default: value}), do: {:ok, value}

    defp shown(_widget, :error), do: nil
    # A variable is shown by the name box, not the typed control (spec/14 §19.9).
    defp shown(_widget, {:ok, %Var{}}), do: nil
    # A colour is the well's to show, never a control's.
    defp shown(:color, {:ok, _value}), do: nil
    # Whole: a literal `inspect/1` cut short at its default limit would read back as less
    # than it is — a theme's palette in its parts is well over fifty terms.
    defp shown(:textarea, {:ok, value}),
      do: inspect(value, limit: :infinity, printable_limit: :infinity)

    defp shown({:select, _}, {:ok, value}), do: option(value)
    defp shown({:select_groups, _}, {:ok, value}), do: option(value)
    defp shown({:columns, _}, {:ok, value}), do: to_string(value)
    defp shown({:pool, _}, {:ok, value}), do: option(value)
    defp shown({:items, _}, {:ok, _value}), do: nil
    defp shown(:items, {:ok, _value}), do: nil
    defp shown(:select, {:ok, value}), do: option(value)
    defp shown(_widget, {:ok, value}) when is_tuple(value), do: inspect(value)
    defp shown(_widget, {:ok, value}), do: to_string(value)

    defp key_errors(errors, path) do
      for {at, _reason} = error <- errors, at == path, do: Validator.format(error)
    end
  end
end
