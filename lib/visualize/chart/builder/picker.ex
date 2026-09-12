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

    alias Visualize.Chart.Builder.{Glyphs, Store}
    alias Visualize.Chart.Var

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
    attr(:swatches, :list, default: [], doc: "`{slot, colour}` for the theme's colour slots")
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
          off?: is_nil(assigns.key)
        )

      ~H"""
      <form
        id={@id}
        class="vis-builder-picker"
        phx-change="edit"
        phx-hook="BuilderHook"
        phx-target={@target}
        data-builder-target={@target}
        data-builder-scope="colour"
      >
        <h3 class="vis-builder-context-title">{@key || "colour"}</h3>
        <p :if={@off?} class="vis-builder-context-note">
          click a colour well to set it here, or drag a patch onto any well
        </p>
        <p :if={!@off?} class="vis-builder-picker-reads">{reads(@value)}</p>

        <%= case @face do %>
          <% :colour -> %>
            <div class="vis-builder-swatches" role="radiogroup" aria-label="theme slots">
              <label
                :for={{slot, colour} <- @swatches}
                class={"vis-builder-swatch" <> if(@word == slot, do: " vis-builder-swatch-on", else: "")}
                title={slot}
                style={"--vis-builder-swatch: #{colour}"}
                draggable="true"
                data-builder-colour={slot}
              >
                <input
                  type="radio"
                  name={"#{@key}.slot"}
                  value={slot}
                  checked={@word == slot}
                  disabled={@off?}
                  aria-label={slot}
                />
              </label>
            </div>
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

    # An atom's word, for the controls that carry words: a slot, a glyph's value.
    defp word(value) when is_atom(value) and not is_nil(value), do: to_string(value)
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
