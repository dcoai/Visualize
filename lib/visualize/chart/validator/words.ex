defmodule Visualize.Chart.Validator.Words do
  @moduledoc false
  # The reasons of spec/14 §10.1 in words, for `Visualize.Chart.Validator.format/1`: one
  # reader serves every error of the layer — the validator's, application's, the schema
  # step's (§7.4) and `compose/2`'s.

  alias Visualize.Chart.Migration
  alias Visualize.Theme

  @doc false
  def words({:weight, key}), do: "every #{key} weight is a positive number"
  def words({:contract, message}), do: "breaks its contract: #{message}"
  def words(:both), do: "says both box and cell: a frame says where it goes once"
  def words(:outside), do: "is outside the design's layout grid"

  def words({:cycle, kind, name}),
    do: "#{kind} #{inspect(name)} is adopted in a circle: a chain of frames returns to it"

  def words({:sync, :frame_kind, kind}),
    do: "joins a sync group over a #{inspect(kind)} frame; only a cartesian frame's x syncs"

  def words({:sync, :x_scale, nil}),
    do: "joins a sync group over a frame with no x scale; a linear or time x is what syncs"

  def words({:sync, :x_scale, kind}) do
    "joins a sync group over a #{inspect(kind)} x scale; only a linear or time x syncs, " <>
      "since the hooks map a shared x by linear interpolation (spec/14 §2.9)"
  end

  def words({:brush, :frame_kind, kind}),
    do: "brushes a #{inspect(kind)} frame; only a cartesian frame's x is brushed"

  def words({:brush, :x_scale, nil}),
    do: "brushes a frame with no x scale; a linear or time x is what a brush selects"

  def words({:brush, :x_scale, kind}) do
    "brushes a #{inspect(kind)} x scale; only a linear or time x is brushed, since the hook " <>
      "turns a brushed pixel into a value by linear interpolation (spec/14 §2.9)"
  end

  def words({:colour_map, kind}) do
    "is a map of colours on a #{inspect(kind)} scale; a map pins categories, which an " <>
      ":ordinal scale has (spec/14 §4.3)"
  end

  def words({:polarity, :range}) do
    "orders a ramp, and this scale does not range over one: give range: {:ramp, name}, " <>
      "or leave a :sequential or :diverging scale's range :auto (spec/14 §4.3)"
  end

  def words({:tiles, :projection, what}) do
    "draws tiles over #{inspect(what)}: tiles lie only under a :geo frame's :mercator " <>
      "projection with a zero centre latitude and no tilt or roll (spec/07 §8.1)"
  end

  def words({:tiles, :attribution}), do: "must say something: the attribution is drawn"
  def words({:tiles, :url}), do: "must hold each of {z}, {x} and {y}"

  # A URL the policy refuses, named by its field and reason and never quoted (§10.3).
  def words({:url, :relative}), do: "the URL is refused: it has no scheme"

  def words({:url, :scheme}),
    do:
      "the URL's scheme is refused: only https (and http when the host allows it) and image data"

  def words({:url, :http}), do: "the URL is refused: http is not allowed by this host; use https"

  def words({:url, :data_type}),
    do: "the URL's data is refused: only image/png, image/jpeg or image/webp"

  def words({:url, :host}), do: "the URL's host is not one this host allows"

  def words({:unsafe, :font_family}),
    do: "a font family may not hold <, >, /, ;, {, }, \\ or a control character"

  def words({:unsafe, :class}), do: "must be CSS class names separated by spaces"
  def words({:tiles, :subdomains}), do: "must name a subdomain for the url's {s}"
  def words(:sweep), do: "must be within a turn, and not zero"
  def words(:radius), do: "must be positive"

  def words({:unit, code, reason}),
    do: "#{inspect(code)} is not a UCUM code visualize reads (#{inspect(reason)}; spec/05 §4.1)"

  def words({:quantity, quantity, code}),
    do: "unit #{inspect(code)} does not measure #{inspect(quantity)} (spec/05 §4.2)"

  def words({:zone, zone, :utc_only_time_zone_database}) do
    "time zone #{inspect(zone)} cannot be shown: the host has no time zone database " <>
      "configured (Calendar.UTCOnlyTimeZoneDatabase)"
  end

  def words({:zone, zone, :time_zone_not_found}),
    do: "time zone #{inspect(zone)} is not known to the host's time zone database"

  def words({:zone, zone, reason}),
    do: "time zone #{inspect(zone)} cannot be shown: #{inspect(reason)}"

  def words({:outside_domain, scale, {:column, field, type}}) do
    "field #{inspect(field)} is a #{inspect(type)} column and scale #{inspect(scale)}'s " <>
      "declared domain holds no such value: every element would draw its unknown colour"
  end

  def words({:outside_domain, scale, value}) do
    "#{inspect(value)} is not in scale #{inspect(scale)}'s declared domain: " <>
      "it would draw the scale's unknown colour"
  end

  def words({:feeds_domain, scale, n}) do
    "a text at the constant #{inspect(n)} holds scale #{inspect(scale)}'s inferred domain " <>
      "open: place it at {:scale, :min} or {:scale, :max}, as a frame label, or declare the domain"
  end

  # The schema step of application (spec/14 §7.4, #552).
  def words({:missing_attribute, slot, field, key}) do
    "the schema bound to slot #{inspect(slot)} does not give field #{inspect(field)} " <>
      "the attribute #{inspect(key)}, which the design requires"
  end

  def words({:schema_type, field, declared, described}) do
    "field #{inspect(field)} is declared #{inspect(declared)} and its schema describes " <>
      "it as #{inspect(described)}"
  end

  # The type check of a binding (spec/14 §7.4, D-153).
  def words({:type_mismatch, slot, field, expected, given}) do
    "field #{inspect(field)} of slot #{inspect(slot)} is #{a_type(given)}, and the scale " <>
      "it is read through needs #{a_type(expected)}"
  end

  # A mark that keeps each entity's latest row (spec/14 §7.3, D-168).
  def words({:identity_required, slot}) do
    "the mark keeps each entity's latest row of slot #{inspect(slot)}, and its feed " <>
      "declares no identity (identity: true on the fields that name an entity)"
  end

  def words({:no_schema, slot}) do
    "slot #{inspect(slot)} needs its feed's schema — it requires attributes or the design " <>
      "reads facts of it — and its source is not a delivery naming a schema version"
  end

  def words({:unknown_schema, feed, version}) do
    "feed #{inspect(feed)}'s schema version #{inspect(version)} is not in the schema " <>
      "cache and there is no describe: to ask the feed for it"
  end

  def words({:describe, feed, reason}),
    do: "feed #{inspect(feed)} could not describe its schema: #{inspect(reason)}"

  def words({:schema_version, feed, version, got}) do
    "feed #{inspect(feed)} describes schema version #{inspect(got)}, and the delivery " <>
      "names #{inspect(version)}: the delivery is not described by the feed's present schema"
  end

  def words({:undeclared_field, source, field}),
    do: "field #{inspect(field)} is not among slot #{inspect(source)}'s fields"

  def words(:required), do: "is required"
  def words(:unknown_key), do: "is not a key of this node"
  def words({:type, type}), do: "must be #{type_words(type)}"

  def words({:ref_kind, wanted, given}),
    do: "is a #{given} id where a #{wanted} was expected"

  def words({:enum, allowed}), do: "must be one of #{list(allowed)}"

  def words({:undeclared, :field, name}) do
    "field #{inspect(name)} is not declared by the mark's source"
  end

  def words({:undeclared, :slot, name}), do: "slot #{inspect(name)} is not a slot of the theme"

  def words({:undeclared, :color, name}),
    do: "color #{inspect(name)} is not a name of the theme's color table"

  def words({:undeclared, kind, name}), do: "#{kind} #{inspect(name)} is not declared"
  def words({:invalid_for, type}), do: "is not read by #{inspect(type)}"

  def words({:unsupported_version, v}) do
    "version #{inspect(v)} is not supported; the current version is #{Migration.current()}"
  end

  def words({:newer_schema, needs, this}), do: "needs schema v#{needs}, this is v#{this}"

  def words({:limit, :depth, max, given}),
    do: "is nested #{given} deep; the limit depth is #{max}"

  def words({:limit, :items, max, given}), do: "holds #{given} items; the limit items is #{max}"

  def words({:limit, :ticks, max, given}),
    do: "asks for #{given} ticks; the limit ticks is #{max}"

  def words({:limit, :iterations, max, given}),
    do: "asks for #{given} layout iterations; the limit iterations is #{max}"

  def words({:limit, :counts, max, given}), do: "asks for #{given}; the limit counts is #{max}"

  # The builder's need of spec/14 §18.16 (#370), worded here so one reader serves it.
  def words({:unscaled, field}) do
    "reads #{inspect(field)} through no scale — say what #{inspect(field)} is under data, " <>
      "or declare the scale under frame"
  end

  # A board's own reasons (spec/15 §3.3, D-141).
  def words({:off_grid, columns}), do: "runs past the board's #{columns} columns"
  def words({:overlap, other}), do: "overlaps cell #{inspect(other)}"
  def words({:window, :both}), do: "says both last and from/to: a window is one or the other"
  def words({:window, :inverted}), do: "has a from that is not before its to"
  def words({:dangling, id}), do: "refers to #{inspect(id)}, which the store does not hold"

  # A snapshot's own reason (spec/15 §12.3, D-150).
  def words(:not_on_board), do: "is not a cell of the snapshot's board"

  # A board's interaction (spec/15 §13.3, D-151).
  def words({:no_board, ref}), do: "names the board #{inspect(ref)}, which the host does not hold"

  def words({:missing, :datum, field}),
    do: "takes #{inspect(field)} from the datum, which has no value for it"

  # A board bundle's import (spec/15 §11.3, D-147).
  def words({:not_carried, id}), do: "refers to #{inspect(id)}, which the bundle does not carry"

  def words({:theme_taken, name}),
    do: "is the theme #{inspect(name)}, a name the store already gives a different theme"

  def words({:store, reason}), do: "the store refused the import: #{inspect(reason)}"

  def words({:cycle, chain}) when is_list(chain),
    do: "reaches itself through #{Enum.map_join(chain, " → ", &inspect/1)}"

  def words({:unbound, :binding, slot}),
    do: "slot #{inspect(slot)} is bound to no feed: the binding names none for it"

  def words({:undescribed, feed}) do
    "feed #{inspect(feed)} has no schema to check the slot's contract against: give the " <>
      "check its schema or a describe function"
  end

  def words(:not_required), do: "binds a slot that no cell's component declares"

  def words({:json, message}), do: "JSON does not parse: #{message}"
  def words({:missing_dependency, :jason}), do: "needs the optional dependency Jason"

  # A theme document that only names a theme (spec/14 §9.3, D-139).
  def words({:unknown_theme, name}) do
    "names the theme #{inspect(name)}, which is not built-in; a theme document holds the theme"
  end

  def words({:unresolved, :var, name}) do
    "variable #{inspect(name)} has no value at application and no default"
  end

  def words({:var_binding, name}) do
    "variable #{inspect(name)} is bound to another variable; resolution is single level"
  end

  def words({:unbound, :source, name}) do
    "slot #{inspect(name)} has no source in the pool under its name or its default"
  end

  def words({:missing_field, field}), do: "has no field #{inspect(field)}"
  def words(:conflict), do: "is declared differently by two fragments"

  def words(:cycle), do: "extends itself, directly or through a chain of `extends`"

  # A text that does not read (spec/14 §7.1).
  def words({:template, :unterminated}), do: ~S|has a #{ with no closing }|

  def words({:template, {:hole, hole}}),
    do:
      ~S|has #{| <>
        hole <>
        ~S|}, which names none of var(:name), field(:name) and fact(:source, :field, :key)|

  # A fault of a composite rather than of a node (spec/14 §19.6): the stack reaching itself.
  def words({:cycle, chain}), do: "the stack refers to itself through #{inspect(chain)}"

  # A map that is many things is no kind of fragment (spec/14 §19.8).
  def words(:many_kinds),
    do: "is many things at once, which is no kind of fragment; make it a composite of sites"

  defp type_words(:integer), do: "an integer"
  defp type_words(:number), do: "a number"
  defp type_words(:boolean), do: "a boolean"
  defp type_words(:string), do: "a string"
  defp type_words(:name), do: "a name (an atom)"
  defp type_words(:field), do: "a field name"
  defp type_words(:field_ref), do: "{:field, name}"
  defp type_words(:fact), do: "fact(source, field, key), each a name"
  defp type_words(:key_order), do: "{:keys, [name, …]}, the series keys bottom first"
  defp type_words(:channel), do: "a field name, a number or {:field, name}"
  defp type_words(:extent), do: "an extent: :auto, [lo, hi] or a list of categories"
  defp type_words(:text), do: ~S|a string, with #{var(:name)} for a variable|

  defp type_words(:anchor) do
    "an anchor: :title, :subtitle, :caption, {:axis, scale}, {:frame, corner | :center} or " <>
      "{:data, [x, y]}"
  end

  defp type_words(:colour) do
    "a colour string, :none, a typed color — color(name), ramp(name, t) with t in 0..1, " <>
      "contrast() — a transform of colors with every number in 0..1, or a paint"
  end

  defp type_words(:theme_colour),
    do:
      type_words(:colour) <>
        ", or a map of pinned steps, an integer in 0..1000 to a colour string"

  defp type_words(:ramp), do: "{:ramp, name} with name one of #{list(Theme.ramp_names())}"
  defp type_words(:size), do: "a number or a theme slot"
  defp type_words(:font), do: "a font string or a theme slot"
  defp type_words(:slot), do: "a theme slot"
  defp type_words(:term), do: "a JSON-representable term"
  defp type_words(:positive), do: "a positive number"
  defp type_words(:non_neg_integer), do: "a non-negative integer"
  defp type_words(:pos_integer), do: "a positive integer"
  defp type_words(:utc_datetime), do: "a DateTime in Etc/UTC"
  defp type_words(:board), do: "a board map"
  defp type_words(:snapshot), do: "a snapshot map"
  defp type_words(:row), do: "a row map"
  defp type_words(:status), do: "one of :loading, :live, :stale or {:down, words}"

  defp type_words(:board_ref),
    do: ":self, or a board's name: an atom, a string or a positive integer"

  defp type_words(:window), do: "nil, %{last: seconds} or %{from: t, to: t}"
  defp type_words({:id, kind}), do: "a #{kind} id, {#{inspect(kind)}, n}"
  defp type_words({:enum, allowed}), do: "one of #{list(allowed)}"
  defp type_words({:list, t}), do: "a list of #{type_words(t)}"
  defp type_words({:map, t}), do: "a map from names to #{type_words(t)}"
  defp type_words({:node, kind}), do: "a #{kind} node"
  defp type_words({:ref, kind}), do: "a declared #{kind} name, or a #{kind} id"
  defp type_words({:one_of, types}), do: Enum.map_join(types, " or ", &type_words/1)

  defp list(atoms), do: Enum.map_join(atoms, ", ", &inspect/1)

  # A schema type as a reader names it (spec/08 §10.1).
  defp a_type(:time), do: "a time"
  defp a_type(:number), do: "a number"
  defp a_type(:category), do: "a category"
  defp a_type(:text), do: "text"
  defp a_type(other), do: inspect(other)
end
