defmodule Visualize.Quantity.Facts do
  @moduledoc false
  # The facts of each quantity (spec/05 §4.2, D-138, D-155), as data: its base unit, its
  # kind, its bounds in the base unit (a display hint, never validation), its additivity
  # across series and over time, and its display families — ladders of units, smallest
  # first, each tagged with the unit systems it serves (`:any` for every system). The
  # order of `all/0` is spec/05 §4.2's, and a quantity's families are listed metric, US,
  # UK, then the rest: a unit belongs to the first that holds a member of its shape.

  @decimal ~w(By kBy MBy GBy TBy)
  @binary ~w(By KiBy MiBy GiBy TiBy)
  @bits ~w(bit kbit Mbit Gbit Tbit)

  @facts [
    duration: %{
      base: "s",
      kind: :linear,
      bounds: {0, nil},
      across: true,
      over_time: true,
      families: [any: ~w(ns us ms s min h d)]
    },
    information: %{
      base: "By",
      kind: :linear,
      bounds: {0, nil},
      across: true,
      over_time: true,
      families: [any: @decimal, any: @binary, any: @bits]
    },
    data_rate: %{
      base: "By/s",
      kind: :linear,
      bounds: {0, nil},
      across: true,
      over_time: false,
      families:
        for(family <- [@decimal, @binary, @bits], do: {:any, Enum.map(family, &(&1 <> "/s"))})
    },
    frequency: %{
      base: "Hz",
      kind: :linear,
      bounds: {0, nil},
      across: true,
      over_time: false,
      families: [any: ~w(Hz kHz MHz GHz), any: ~w(/h /min /s)]
    },
    ratio: %{base: "1", kind: :linear, bounds: {0, 1}, across: false, over_time: false},
    count: %{base: "1", kind: :linear, bounds: {0, nil}, across: true, over_time: true},
    temperature: %{
      base: "Cel",
      kind: :affine,
      bounds: {nil, nil},
      across: false,
      over_time: false,
      families: [metric: ~w(Cel), us: ~w([degF]), uk: ~w(Cel)]
    },
    length: %{
      base: "m",
      kind: :linear,
      bounds: {0, nil},
      across: true,
      over_time: true,
      families: [
        metric: ~w(mm cm m km),
        us: ~w([in_i] [ft_i] [mi_i]),
        uk: ~w([in_i] [ft_i] [mi_i])
      ]
    },
    speed: %{
      base: "m/s",
      kind: :linear,
      bounds: {0, nil},
      across: false,
      over_time: false,
      families: [metric: ~w(km/h), us: ~w([mi_i]/h), uk: ~w([mi_i]/h)]
    },
    power: %{
      base: "W",
      kind: :linear,
      bounds: {nil, nil},
      across: true,
      over_time: false,
      families: [any: ~w(W kW MW GW)]
    },
    energy: %{
      base: "J",
      kind: :linear,
      bounds: {nil, nil},
      across: true,
      over_time: true,
      families: [any: ~w(J kJ MJ GJ), any: ~w(W.h kW.h MW.h GW.h), any: ~w(cal kcal)]
    },
    pressure: %{
      base: "Pa",
      kind: :linear,
      bounds: {nil, nil},
      across: false,
      over_time: false,
      families: [metric: ~w(Pa kPa MPa), us: ~w([psi]), uk: ~w([psi])]
    },
    area: %{
      base: "m2",
      kind: :linear,
      bounds: {0, nil},
      across: true,
      over_time: true,
      families: [
        metric: ~w(cm2 m2 har km2),
        us: ~w([ft_i]2 [acr_us] [mi_i]2),
        uk: ~w([ft_i]2 [acr_us] [mi_i]2)
      ]
    },
    volume: %{
      base: "l",
      kind: :linear,
      bounds: {0, nil},
      across: true,
      over_time: true,
      families: [
        metric: ~w(ml l m3),
        us: ~w([foz_us] [pt_us] [gal_us]),
        uk: ~w([foz_br] [pt_br] [gal_br])
      ]
    },
    mass: %{
      base: "g",
      kind: :linear,
      bounds: {0, nil},
      across: true,
      over_time: true,
      families: [
        metric: ~w(mg g kg t),
        us: ~w([oz_av] [lb_av]),
        uk: ~w([oz_av] [lb_av] [stone_av])
      ]
    },
    pace: %{
      base: "s/m",
      kind: :linear,
      bounds: {0, nil},
      across: false,
      over_time: false,
      families: [metric: ~w(min/km), us: ~w(min/[mi_i]), uk: ~w(min/[mi_i])]
    },
    angle: %{base: "deg", kind: :cyclic, bounds: {0, 360}, across: false, over_time: false},
    currency: %{base: nil, kind: :linear, bounds: {nil, nil}, across: true, over_time: true},
    electric_potential: %{
      base: "V",
      kind: :linear,
      bounds: {nil, nil},
      across: false,
      over_time: false,
      families: [any: ~w(mV V kV)]
    },
    electric_current: %{
      base: "A",
      kind: :linear,
      bounds: {nil, nil},
      across: true,
      over_time: false,
      families: [any: ~w(mA A)]
    },
    electric_charge: %{
      base: "C",
      kind: :linear,
      bounds: {0, nil},
      across: true,
      over_time: true,
      families: [any: ~w(mA.h A.h)]
    },
    illuminance: %{
      base: "lx",
      kind: :linear,
      bounds: {0, nil},
      across: false,
      over_time: false,
      families: [any: ~w(lx klx)]
    },
    sound_level: %{
      base: "dB[SPL]",
      kind: :logarithmic,
      bounds: {nil, nil},
      across: false,
      over_time: false
    },
    mass_concentration: %{
      base: "g/l",
      kind: :linear,
      bounds: {0, nil},
      across: false,
      over_time: false
    },
    amount_concentration: %{
      base: "mol/l",
      kind: :linear,
      bounds: {0, nil},
      across: false,
      over_time: false
    }
  ]

  @all Keyword.keys(@facts)
  @by_quantity Map.new(@facts, fn {quantity, facts} ->
                 {quantity, Map.put_new(facts, :families, [])}
               end)

  @doc false
  def all, do: @all

  @doc false
  def fetch!(quantity), do: Map.fetch!(@by_quantity, quantity)
end
