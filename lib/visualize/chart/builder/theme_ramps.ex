if Code.ensure_loaded?(Phoenix.Component) do
  defmodule Visualize.Chart.Builder.ThemeRamps do
    @moduledoc """
    The theme editor's ramps and roles, checked as they are edited (spec/14 §20.4, §20.5,
    D-139).

    Each ramp is drawn as the theme interpolates it, again as a colour-vision deficiency
    sees it when one is chosen, and as the lightness of each of its colours — what a reader
    with no hue at all reads. Its anchors are colour inputs of the editor's form, and a
    contract it breaks is said beneath it in the contract's own words
    (`Visualize.Theme.violations/1`). The status roles are drawn at the positions the library
    fixes for them, and set by the colour there.

    This module compiles only when `Phoenix.Component` is loaded (spec/10 §1.1, D-45, D-85).
    """

    use Phoenix.Component

    alias Visualize.Chart.Builder.{Themes, ThemeSheet}
    alias Visualize.Color
    alias Visualize.Color.Vision
    alias Visualize.Theme

    # How many colours a ramp is drawn with: enough that the Lab interpolation reads as a
    # continuum at the inspector's width.
    @steps 24

    @meanings %{
      status: "good → caution → bad",
      thermal: "cold → neutral → hot",
      diverging: "below → at → above",
      sequential: "less → more"
    }

    # The status roles and where the library fixes them on `status` (spec/08 §7.5).
    @positions [good: 0, warning: 0.5, bad: 1]

    attr(:theme, :any, required: true, doc: "the `%Visualize.Theme{}` being edited, unchecked")
    attr(:vision, :atom, default: :none, doc: "the deficiency the ramps are also drawn under")
    attr(:target, :any, default: nil, doc: "the `phx-target` of the section's buttons")

    @doc """
    Renders the *ramps* and *roles* sections (spec/14 §20.4): for each ramp a
    `<div class="vis-builder-theme-ramp">` — the ramp drawn, the ramp as the deficiency sees
    it, the lightness strip, the anchors and any violation — then a row per role. They are
    fieldsets of the editor's form, so their inputs write through `theme_edit`.
    """
    def section(assigns) do
      theme = assigns.theme
      drawn = ThemeSheet.drawable(theme)
      faults = Map.new(Theme.violations(theme))

      assigns =
        assign(assigns,
          ramps: Enum.map(Theme.ramp_names(), &ramp(&1, theme, drawn, assigns.vision, faults)),
          roles: roles(drawn, faults)
        )

      ~H"""
      <fieldset class="vis-builder-theme-section vis-builder-theme-ramps">
        <legend>ramps</legend>
        <div
          :for={ramp <- @ramps}
          class={"vis-builder-theme-ramp" <> if(ramp.fault, do: " vis-builder-theme-ramp-broken", else: "")}
          data-ramp={ramp.name}
        >
          <span class="vis-builder-theme-ramp-name">{ramp.name} <span class="vis-builder-theme-ramp-meaning">{ramp.meaning}</span></span>
          <div class="vis-builder-theme-strip" role="img" aria-label={"#{ramp.name}, as drawn"}>
            <span :for={colour <- ramp.colours} style={"background: #{colour}"}></span>
            <span
              :for={{role, at} <- ramp.markers}
              class="vis-builder-theme-marker"
              style={"left: #{at * 100}%"}
              title={"#{role} stands at #{at}"}
            >{role}</span>
          </div>
          <div
            :if={@vision != :none}
            class="vis-builder-theme-strip vis-builder-theme-strip-vision"
            role="img"
            aria-label={"#{ramp.name}, under #{@vision}"}
            title={"under #{@vision}"}
          >
            <span :for={colour <- ramp.seen} style={"background: #{colour}"}></span>
          </div>
          <div class="vis-builder-theme-strip vis-builder-theme-lightness" role="img" aria-label={"#{ramp.name}, its lightness"} title="lightness, CIE L*">
            <span :for={grey <- ramp.lightness} style={"background: #{grey}"}></span>
          </div>
          <div class="vis-builder-theme-anchors">
            <span :for={{anchor, i} <- ramp.anchors} class="vis-builder-theme-swatch">
              <input
                type="color"
                name={"ramps.#{ramp.name}.#{i}"}
                value={hex(anchor.colour)}
                title={anchor.colour}
                aria-label={"#{ramp.name} anchor #{i + 1}"}
              />
              <span class="vis-builder-theme-l">L* {anchor.l}</span>
              <button
                :if={length(ramp.anchors) > 2}
                type="button"
                class="vis-builder-theme-remove"
                title={"remove #{ramp.name} anchor #{i + 1}"}
                aria-label={"remove #{ramp.name} anchor #{i + 1}"}
                phx-click="theme_anchor_remove"
                phx-value-ramp={ramp.name}
                phx-value-index={i}
                phx-target={@target}
              >×</button>
            </span>
            <button
              type="button"
              class="vis-builder-add"
              title={"resample #{ramp.name} at one more anchor"}
              aria-label={"add a #{ramp.name} anchor"}
              phx-click="theme_anchor_add"
              phx-value-ramp={ramp.name}
              phx-target={@target}
            >+</button>
          </div>
          <p :if={ramp.fault} class="vis-builder-theme-violation">{ramp.fault}</p>
        </div>
      </fieldset>
      <fieldset class="vis-builder-theme-section vis-builder-theme-roles">
        <legend>roles</legend>
        <div :for={role <- @roles} class="vis-builder-theme-role" data-role={role.name}>
          <label class="vis-builder-theme-row">
            <span class="vis-builder-control-label">{role.name} <span class="vis-builder-theme-ramp-meaning">{role.where}</span></span>
            <input
              type="color"
              name={"roles.#{role.name}"}
              value={hex(role.colour)}
              title={role.colour}
              disabled={role.note != nil}
            />
          </label>
          <p :if={role.note} class="vis-builder-context-note">{role.note}</p>
          <p :if={role.fault} class="vis-builder-theme-violation">{role.fault}</p>
        </div>
      </fieldset>
      """
    end

    # One ramp as the section draws it: its colours at `@steps` positions, those colours as
    # the deficiency sees them, their lightness as greys, its anchors with their L*, the
    # status roles' markers, and its fault.
    defp ramp(name, theme, drawn, vision, faults) do
      colours = for k <- 0..(@steps - 1), do: Theme.ramp(drawn, name, k / (@steps - 1))

      %{
        name: name,
        meaning: Map.fetch!(@meanings, name),
        colours: colours,
        seen: Enum.map(colours, &seen(&1, vision)),
        lightness: Enum.map(colours, &grey/1),
        anchors:
          drawn.ramps
          |> Map.fetch!(name)
          |> anchors(Map.get(theme.ramps || %{}, name))
          |> Enum.with_index(),
        markers: if(name == :status, do: @positions, else: []),
        fault: Map.get(faults, {:ramp, name})
      }
    end

    # The anchors as the theme holds them — what the inputs write — with their lightness;
    # the drawn ones where the theme's own cannot be drawn.
    defp anchors(drawn, own) do
      shown =
        if is_list(own) and own != [] and Enum.all?(own, &Themes.readable?/1),
          do: own,
          else: drawn

      for colour <- shown do
        %{
          colour: colour,
          l: colour |> Color.parse() |> Color.to_lab() |> Map.fetch!(:l) |> round()
        }
      end
    end

    defp roles(drawn, faults) do
      status = Map.fetch!(drawn.ramps, :status)

      status_roles =
        for {role, at} <- @positions do
          %{
            name: role,
            where: "status at #{at}",
            colour: Theme.resolve(drawn, role, :literal),
            note:
              if(role == :warning and rem(length(status), 2) == 0,
                do: "status has no anchor at 0.5 — add an anchor to set it"
              ),
            fault: nil
          }
        end

      own_roles =
        for role <- [:info, :neutral] do
          %{
            name: role,
            where: if(role == :info, do: "a blue", else: "no hue"),
            colour: Theme.resolve(drawn, role, :literal),
            note: nil,
            fault: Map.get(faults, {:role, role})
          }
        end

      status_roles ++ own_roles
    end

    defp seen(colour, :none), do: colour

    defp seen(colour, vision),
      do: colour |> Color.parse() |> Vision.simulate(vision) |> Color.to_hex()

    defp grey(colour) do
      %{l: l} = colour |> Color.parse() |> Color.to_lab()
      l |> Color.lab(0, 0) |> Color.to_hex()
    end

    defp hex(value) do
      if Themes.readable?(value),
        do: value |> Color.parse() |> Color.to_hex() |> String.slice(0, 7),
        else: "#000000"
    end
  end
end
