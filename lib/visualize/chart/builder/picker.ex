if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.Picker do
    @moduledoc """
    The context panel as the picker for the selected field (spec/14 §19.10).

    A field is selected by clicking into it, and the panel shows the control its *type*
    deserves at a size the form cannot afford: a colour's patches above its picker, each
    patch draggable onto any colour well of the form (`drop_colour`), a font's
    faces in their own face, an enum's glyphs, a reference's local keys and library
    entries, a ranged number's slider. Every control here writes through the same `edit`
    the form does, under the same names — `key`, `key.slot`, `key.range`, `key.var` — so
    the panel is a bigger view of one field and never a second form.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Builder.{Chain, Glyphs, Store}
    alias Visualize.Chart.Var
    alias Visualize.Theme

    # Faces a person can name without a font panel of their own: the generic families,
    # and the faces every platform ships one of.
    @faces [
      "system-ui",
      "sans-serif",
      "serif",
      "monospace",
      "Helvetica",
      "Arial",
      "Verdana",
      "Georgia",
      "Times New Roman",
      "Courier New"
    ]

    attr(:id, :string, required: true, doc: "the panel's id")

    attr(:key, :any,
      default: nil,
      doc: "the selected field's key; nil shows the picker with nothing to write"
    )

    attr(:spec, :map,
      default: %{type: :colour, range: nil},
      doc: "the key's spec, as `Schema.describe/1` gives it"
    )

    attr(:value, :any, default: nil, doc: "the field's current value, or nil")

    attr(:groups, :list,
      default: [],
      doc: "the theme's color table by name, grouped by use: `{group, [{name, colour}]}`"
    )

    attr(:theme, :any, default: nil, doc: "the theme a chain's steps are previewed through")
    attr(:recent, :list, default: [], doc: "the colour literals the design already uses")
    attr(:refs, :map, default: %{}, doc: "the names and ids a reference may take, by kind")
    attr(:entries, :list, default: [], doc: "the library's entries, for a reference's names")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the panel's events")

    @doc """
    Renders the picker for one field: a `<form class="vis-builder-picker">` whose controls
    write the field through `edit`.
    """
    def panel(assigns) do
      assigns =
        assign(assigns,
          face: face(assigns),
          word: word(assigns.value),
          hues: hues(),
          off?: is_nil(assigns.key),
          chain?: assigns.key != nil and chain?(assigns.value)
        )

      ~H"""
      <form
        :if={@face == :colour and @chain?}
        id={@id <> "-chain"}
        class="vis-builder-chain"
        phx-change="colour_chain"
        phx-target={@target}
        phx-submit="submitted"
      >
        <input type="hidden" name="field" value={@key} />
        <.chain value={@value} theme={@theme} path={[]} field={@key} target={@target} />
      </form>
      <form
        id={@id}
        class="vis-builder-picker"
        phx-change="edit"
        phx-hook="BuilderHook"
        phx-target={@target}
        data-builder-target={@target}
        data-builder-scope="colour"
       phx-submit="submitted">
        <h3 class="vis-builder-context-title">{@key || "colour"}</h3>
        <p :if={@off?} class="vis-builder-context-note">
          click a colour well to set it here, or drag a patch onto any well
        </p>
        <p :if={!@off?} class="vis-builder-picker-reads">{reads(@value)}</p>

        <%= case @face do %>
          <% :colour -> %>
            <p :if={!@off? and !@chain?} class="vis-builder-chain-start">
              <select name={"#{@key}.step"} aria-label="add a step: transform this color" phx-change="colour_chain" phx-value-field={@key} phx-target={@target}>
                <option value="">+ step</option>
                <option :for={step <- Chain.steps()} value={step}>{step}</option>
              </select>
            </p>
            <details
              :for={{group, names} <- @groups}
              class="vis-builder-colour-group"
              open={group != "CSS names"}
            >
              <summary class="vis-builder-colour-group-title">{group}</summary>
              <div class="vis-builder-swatches" role="radiogroup" aria-label={group}>
                <label
                  :for={{name, colour} <- names}
                  class={"vis-builder-swatch" <> if(@word == name, do: " vis-builder-swatch-on", else: "")}
                  title={"#{name} · #{colour || "not in this theme"}"}
                  style={"--vis-builder-swatch: #{colour || "transparent"}"}
                  draggable="true"
                  data-builder-colour={name}
                >
                  <input
                    type="radio"
                    name={"#{@key}.slot"}
                    value={name}
                    checked={@word == name}
                    disabled={@off?}
                    aria-label={name}
                  />
                </label>
              </div>
            </details>
            <div :if={@recent != []} class="vis-builder-swatches" role="radiogroup" aria-label="colours in this chart">
              <label
                :for={colour <- @recent}
                class={"vis-builder-swatch" <> if(@value == colour, do: " vis-builder-swatch-on", else: "")}
                title={colour}
                style={"--vis-builder-swatch: #{colour}"}
                draggable="true"
                data-builder-colour={colour}
              >
                <input type="radio" name={@key} value={colour} checked={@value == colour} disabled={@off?} aria-label={colour} />
              </label>
            </div>
            <div class="vis-builder-hues" role="radiogroup" aria-label="hues">
              <label
                :for={colour <- @hues}
                class={"vis-builder-hue" <> if(@value == colour, do: " vis-builder-hue-on", else: "")}
                title={colour}
                style={"--vis-builder-swatch: #{colour}"}
                draggable="true"
                data-builder-colour={colour}
              >
                <input type="radio" name={@key} value={colour} checked={@value == colour} disabled={@off?} aria-label={colour} />
              </label>
            </div>
            <label class="vis-builder-picker-row">
              <span class="vis-builder-control-label">any colour</span>
              <input type="color" name={@key} class="vis-builder-colour" value={hex(@value)} disabled={@off?} />
            </label>
          <% :font -> %>
            <div class="vis-builder-faces" role="radiogroup" aria-label="faces">
              <label
                :for={family <- faces(@value)}
                class={"vis-builder-face" <> if(@value == family, do: " vis-builder-face-on", else: "")}
                style={"font-family: #{family}"}
              >
                <input type="radio" name={@key} value={family} checked={@value == family} aria-label={family} />
                {family}
              </label>
            </div>
          <% :glyphs -> %>
            <div class="vis-builder-glyphs vis-builder-glyphs-large" role="radiogroup" aria-label={to_string(@key)}>
              <label
                :for={{value, svg} <- glyphs(@key, @spec)}
                class={"vis-builder-glyph" <> if(@word == value, do: " vis-builder-glyph-on", else: "")}
                title={value}
              >
                <input type="radio" name={@key} value={value} checked={@word == value} aria-label={value} />
                {Phoenix.HTML.raw(svg)}
              </label>
            </div>
          <% :enum -> %>
            <div class="vis-builder-words" role="radiogroup" aria-label={to_string(@key)}>
              <label :for={word <- allowed(@spec)} class={"vis-builder-word" <> if(@value == word, do: " vis-builder-word-on", else: "")}>
                <input type="radio" name={@key} value={word} checked={@value == word} />
                {word}
              </label>
            </div>
          <% :reference -> %>
            <div class="vis-builder-choices" role="radiogroup" aria-label={to_string(@key)}>
              <label :for={choice <- choices(@value, @spec, @refs, @entries)} class={"vis-builder-choice" <> if(choice.on?, do: " vis-builder-choice-on", else: "")}>
                <input type="radio" name={@key} value={choice.value} checked={choice.on?} />
                <span class="vis-builder-choice-name">{choice.name}</span>
                <span :if={choice.where} class="vis-builder-choice-where">{choice.where}</span>
              </label>
            </div>
          <% :range -> %>
            <input
              type="range"
              name={"#{@key}.range"}
              class="vis-builder-range vis-builder-range-large"
              min={elem(@spec.range, 0)}
              max={elem(@spec.range, 1)}
              step={elem(@spec.range, 2)}
              value={if(is_number(@value), do: @value, else: elem(@spec.range, 0))}
              aria-label={"#{@key}, dragged"}
            />
            <input type="text" name={@key} class="vis-builder-picker-box" value={shown(@value)} />
          <% :plain -> %>
            <input type="text" name={@key} class="vis-builder-picker-box" value={shown(@value)} />
        <% end %>

      </form>
      """
    end

    attr(:value, :any, required: true)
    attr(:theme, :any, default: nil)
    attr(:path, :list, required: true)
    attr(:field, :string, required: true)
    attr(:target, :any, default: nil)

    # A color's chain (spec/14 §19.10): its base — a blend's operands each a chain of their
    # own — then each step with the color reached so far, its amount and its ×, then + step.
    defp chain(assigns) do
      assigns =
        assign(assigns, rows: Chain.rows(assigns.value, assigns.theme), at: path(assigns.path))

      ~H"""
      <ol class="vis-builder-chain-steps" data-builder-chain={@at}>
        <li :for={row <- @rows} class={"vis-builder-chain-step" <> if(row.op == nil, do: " vis-builder-chain-base", else: "")}>
          <span
            class={"vis-builder-swatch vis-builder-chain-swatch" <> if(row.colour, do: "", else: " vis-builder-well-empty")}
            style={"--vis-builder-swatch: #{row.colour || "transparent"}"}
            title={row.colour || "not resolved in this theme"}
            role="img"
            aria-label={"#{row.word}: #{row.colour || "not resolved"}"}
          ></span>
          <span class="vis-builder-chain-word">{row.word}</span>
          <span :if={row.amount != nil} class="vis-builder-ranged">
            <input type="text" name={"amount|#{@at}|#{row.index}"} value={row.amount} aria-label={"#{row.word} amount"} />
            <input
              type="range"
              name={"amount|#{@at}|#{row.index}"}
              class="vis-builder-range vis-builder-scrubber"
              min={elem(row.span, 0)}
              max={elem(row.span, 1)}
              step={elem(row.span, 2)}
              value={row.amount}
              aria-label={"#{row.word} amount, dragged"}
            />
          </span>
          <button
            :if={row.op != nil}
            type="button"
            class="vis-builder-item-remove"
            phx-click="colour_chain"
            phx-value-field={@field}
            phx-value-path={@at}
            phx-value-op="remove"
            phx-value-index={row.index}
            phx-target={@target}
            aria-label={"remove #{row.word}"}
          >×</button>
          <ol :if={row.operands != []} class="vis-builder-chain-operands">
            <li :for={{operand, i} <- Enum.with_index(row.operands)} class="vis-builder-chain-operand">
              <.chain value={operand} theme={@theme} path={@path ++ [i]} field={@field} target={@target} />
              <button
                :if={length(row.operands) > 1}
                type="button"
                class="vis-builder-item-remove"
                phx-click="colour_chain"
                phx-value-field={@field}
                phx-value-path={@at}
                phx-value-op="operand_remove"
                phx-value-index={i}
                phx-target={@target}
                aria-label={"remove operand #{i}"}
              >×</button>
            </li>
            <li>
              <button
                type="button"
                class="vis-builder-part-add"
                phx-click="colour_chain"
                phx-value-field={@field}
                phx-value-path={@at}
                phx-value-op="operand_add"
                phx-target={@target}
              >+ operand</button>
            </li>
          </ol>
        </li>
        <li class="vis-builder-chain-add">
          <select name={"add|#{@at}"} aria-label="add a step">
            <option value="">+ step</option>
            <option :for={step <- Chain.steps()} value={step}>{step}</option>
          </select>
        </li>
      </ol>
      """
    end

    defp path(path), do: Enum.map_join(path, ".", &to_string/1)

    # A chain worth drawing: a transform, or a blend.
    defp chain?(value) do
      case Chain.split(value) do
        {{:blend, _operands}, _steps} -> true
        {_base, steps} -> steps != []
      end
    end

    @doc """
    The theme's color table by name, grouped by use (spec/14 §19.10): its series, the five
    roles, the furniture, the theme's own colors, and the CSS named colors — each name with
    the color the theme gives it, `nil` where it gives none.

        iex> groups = Visualize.Chart.Builder.Picker.groups(Visualize.Theme.default())
        iex> Enum.map(groups, &elem(&1, 0))
        ["series", "roles", "furniture", "the theme's colors", "CSS names"]
        iex> groups |> List.keyfind("roles", 0) |> elem(1) |> hd()
        {"good", "#4ca34b"}
    """
    @spec groups(Theme.t()) :: [{String.t(), [{String.t(), String.t() | nil}]}]
    def groups(%Theme{} = theme) do
      series = Enum.map(1..length(theme.series)//1, &:"series_#{&1}")
      roles = Theme.role_names()
      furniture = [:axis, :grid, :text, :background, :surface]
      own = theme.colors |> Map.keys() |> Enum.reject(&(&1 in roles)) |> Enum.sort()
      css = Enum.map(Visualize.Color.named_colors(), &String.to_atom/1) -- own

      for {group, names} <- [
            {"series", series},
            {"roles", roles},
            {"furniture", furniture},
            {"the theme's colors", own},
            {"CSS names", Enum.sort(css)}
          ],
          names != [] do
        {group, Enum.map(names, &{to_string(&1), Chain.resolved({:color, &1}, theme)})}
      end
    end

    @doc """
    The face the panel shows a field with, from its key and type (spec/14 §19.10): a
    colour, a font, a drawn enum's glyphs, an enum's words, a reference, a ranged number,
    or a plain box.

        iex> Visualize.Chart.Builder.Picker.face(%{key: :fill, spec: %{type: :colour, range: nil}})
        :colour

        iex> Visualize.Chart.Builder.Picker.face(%{key: :curve, spec: %{type: {:enum, [:linear]}, range: nil}})
        :glyphs
    """
    @spec face(%{key: atom(), spec: map()}) ::
            :colour | :font | :glyphs | :enum | :reference | :range | :plain
    def face(%{key: key, spec: spec}) do
      cond do
        spec.type == :colour ->
          :colour

        spec.type == :font or key == :font_family ->
          :font

        match?({:enum, _}, spec.type) and Glyphs.drawn?(key) and glyphs(key, spec) != [] ->
          :glyphs

        match?({:enum, _}, spec.type) ->
          :enum

        ref_kind(spec.type) != nil ->
          :reference

        spec.range != nil ->
          :range

        true ->
          :plain
      end
    end

    defp glyphs(key, %{type: {:enum, allowed}}) do
      pictures = Enum.map(allowed, &{to_string(&1), Glyphs.glyph(key, &1)})
      if Enum.all?(pictures, fn {_v, svg} -> svg != nil end), do: pictures, else: []
    end

    defp glyphs(_key, _spec), do: []

    defp allowed(%{type: {:enum, allowed}}), do: allowed

    defp ref_kind({:ref, kind}), do: kind
    defp ref_kind({:one_of, alts}), do: Enum.find_value(alts, &ref_kind/1)
    defp ref_kind(_type), do: nil

    # A reference's choices: the document's local keys, then the library's entries of the
    # kind by name, each with its group.
    defp choices(value, spec, refs, entries) do
      kind = ref_kind(spec.type)
      by_id = Map.new(entries, &{&1.id, &1})

      for choice <- Map.get(refs, kind, []) do
        case choice do
          {^kind, _n} = id ->
            entry = Map.get(by_id, id)
            {group, name} = split(entry && entry.name)

            %{
              value: Store.encode_id(id),
              name: name || Store.encode_id(id),
              where: group,
              on?: value == id
            }

          name ->
            %{value: to_string(name), name: to_string(name), where: nil, on?: value == name}
        end
      end
    end

    defp split(nil), do: {nil, nil}

    defp split(stored) do
      case String.split(stored, ":") do
        [name] ->
          {nil, name}

        parts ->
          {parts |> Enum.drop(-1) |> Enum.reject(&(&1 == "")) |> Enum.join(" / "),
           List.last(parts)}
      end
    end

    defp faces(value) when is_binary(value) and value not in @faces, do: [value | @faces]
    defp faces(_value), do: @faces

    # Twelve hues at three lightnesses, as hex: a wheel laid flat, enough to pick a colour
    # by eye and then tune it in the picker below.
    defp hues do
      for l <- [0.72, 0.5, 0.3], h <- Enum.map(0..11, &(&1 * 30)), do: hsl_hex(h, 0.65, l)
    end

    defp hsl_hex(h, s, l) do
      c = (1 - abs(2 * l - 1)) * s
      x = c * (1 - abs(:math.fmod(h / 60, 2) - 1))
      m = l - c / 2

      {r, g, b} =
        cond do
          h < 60 -> {c, x, 0}
          h < 120 -> {x, c, 0}
          h < 180 -> {0, c, x}
          h < 240 -> {0, x, c}
          h < 300 -> {x, 0, c}
          true -> {c, 0, x}
        end

      [r, g, b]
      |> Enum.map(fn v -> round((v + m) * 255) end)
      |> Enum.map_join(&String.pad_leading(Integer.to_string(&1, 16), 2, "0"))
      |> String.downcase()
      |> then(&("#" <> &1))
    end

    # A value's word, for the controls that carry words: a name — a chain's base's — or a
    # glyph's value.
    defp word({:color, name}) when is_atom(name), do: to_string(name)
    defp word(value) when is_atom(value) and not is_nil(value), do: to_string(value)

    defp word(value) when is_tuple(value) do
      case Chain.split(value) do
        {^value, []} -> nil
        {base, _steps} -> word(base)
      end
    end

    defp word(_value), do: nil

    defp hex("#" <> _ = colour), do: colour
    defp hex(_other), do: nil

    defp shown(nil), do: nil
    defp shown(%Var{}), do: nil
    defp shown(value) when is_binary(value), do: value
    defp shown(value) when is_atom(value) or is_number(value), do: to_string(value)
    defp shown(value), do: inspect(value)

    defp reads(nil), do: "not set"
    defp reads(%Var{name: name}), do: "= var(:#{name})"
    defp reads(value) when is_atom(value), do: "= :#{value}"
    defp reads(value) when is_binary(value), do: "= #{value}"
    defp reads(value), do: "= #{inspect(value)}"
  end
end
