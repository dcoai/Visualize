defmodule Visualize.Chart.Frame.Motion do
  @moduledoc false
  # The frame's motion in `:css` output (spec/14 §3.10, §3.11, D-176): each distinct resolved
  # transition or animation an element carries is a class, and one rule in a `<style>` first
  # in the frame's group, so a hundred bars of one motion carry it once.
  #
  # A transition's class is the element's own, and its rule reaches the element and, at no
  # specificity, everything under it — a mark's group moves its children, and a child's own
  # class still wins. The fill and the stroke of an element whose color moves, and of
  # everything under it, are written `oklch()`, so the browser interpolates them in OKLab.
  #
  # An animation's class is a wrapper's, `<g class="vis-animation-<h>">` around the element,
  # so the box a spin turns about is the element's as drawn, its own transform included; the
  # style holds the `@keyframes` of each built-in drawn. A host's keyframes name is written as
  # it is, once it is one CSS identifier.
  #
  # The style ends with the reduced-motion rules, `!important` so no design beats them. In
  # `:literal` mode nothing is written: a canvas reads the keys.

  alias Visualize.Chart.Validator
  alias Visualize.IR.{Element, Motion, Path}

  @reduced_transitions "@media (prefers-reduced-motion: reduce) { [class*=\"vis-transition-\"], " <>
                         "[class*=\"vis-transition-\"] * { transition: none !important; } }"
  @reduced_animations "@media (prefers-reduced-motion: reduce) { [class*=\"vis-animation-\"] " <>
                        "{ animation: none !important; } }"
  @reduced_entrances "@media (prefers-reduced-motion: reduce) { [class*=\"vis-enter-\"] " <>
                       "{ animation: none !important; } }"

  @doc false
  # The tree with every motion written as its class, and the `<style>` the classes need —
  # `[]` when the tree moves nothing or the mode is not `:css`. Raises `ArgumentError` for a
  # host's keyframes name that is not a CSS identifier (spec/14 §10.3).
  @spec apply(Element.t(), atom()) :: {Element.t(), [Element.t()]}
  def apply(tree, :css) do
    case walk(tree, []) do
      {tree, []} ->
        {tree, []}

      {tree, rules} ->
        rules = rules |> Enum.uniq() |> Enum.sort()
        transitions = for {:transition, class, t} <- rules, do: transition_rule(class, t)
        animations = for {:animation, class, a} <- rules, do: animation_rule(class, a)
        entrances = for {:enter, class, e} <- rules, do: enter_rule(class, e)

        keyframes =
          for {kind, _class, %{name: name}} <- rules,
              kind in [:animation, :enter],
              is_atom(name),
              uniq: true do
            Motion.css_keyframes(if kind == :enter, do: {:enter, name}, else: name)
          end

        css =
          transitions ++
            keyframes ++
            animations ++
            entrances ++
            if(transitions == [], do: [], else: [@reduced_transitions]) ++
            if(animations == [], do: [], else: [@reduced_animations]) ++
            if(entrances == [], do: [], else: [@reduced_entrances])

        {tree, [Element.stylesheet(Enum.join(css, "\n"))]}
    end
  end

  def apply(tree, _mode), do: {tree, []}

  defp transition_rule(class, transition),
    do: ".#{class}, :where(.#{class}) * { transition: #{Motion.css_transition(transition)}; }"

  defp animation_rule(class, %{name: name} = animation) do
    if is_binary(name), do: identifier!(name)

    ".#{class} { animation: #{Motion.css_animation(animation)}; " <>
      "transform-box: fill-box; transform-origin: center; }"
  end

  # An entrance runs once, when the element is inserted (spec/14 §3.12).
  defp enter_rule(class, %{name: name} = enter) do
    keyframes = if is_binary(name), do: identifier!(name), else: "vis-enter-#{name}"

    ".#{class} { animation: #{keyframes} #{Path.format_number(enter.duration)}ms #{Motion.css_easing(enter.easing)} 0ms 1; " <>
      "transform-box: fill-box; transform-origin: center; }"
  end

  # `moving` is the color keys the nearest transition above moves.
  defp walk(%Element{style: style, children: children} = element, moving) do
    {animation, style} = Map.pop(style, :animation)
    {enter, style} = Map.pop(style, :enter)
    {exit, style} = Map.pop(style, :exit)

    {style, rules, moving} =
      case Map.pop(style, :transition) do
        {[_ | _] = transition, style} ->
          class = class("transition", transition)
          moved = for {key, _d, _e} <- transition, key in [:fill, :stroke], do: key
          {add_class(style, class), [{:transition, class, transition}], moved}

        {_none, style} ->
          {style, [], moving}
      end

    style =
      Enum.reduce(moving, style, fn key, acc ->
        if Map.has_key?(acc, key), do: Map.update!(acc, key, &Motion.oklch/1), else: acc
      end)

    {children, below} =
      Enum.map_reduce(children, [], fn child, acc ->
        {child, found} = walk(child, moving)
        {child, acc ++ found}
      end)

    element = exiting(%{element | style: style, children: children}, exit)

    {element, rules} = wrap(element, :animation, animation, rules)
    {element, rules} = wrap(element, :enter, enter, rules)
    {element, rules ++ below}
  end

  # An element that leaves by its identity says how (spec/14 §3.12): the hook that holds
  # the chart reads `data-vis-exit` before a patch removes it.
  defp exiting(%Element{attrs: %{"data-vis-id" => _}} = element, %{} = exit) do
    if is_binary(exit.name), do: identifier!(exit.name)
    Element.put_attr(element, "data-vis-exit", Motion.exit_attribute(exit, element))
  end

  defp exiting(element, _exit), do: element

  # An animation and an entrance are a wrapper's, so the box they turn and grow about is
  # the element's as drawn, its own transform included (spec/14 §3.11, §3.12).
  defp wrap(element, _kind, nil, rules), do: {element, rules}

  defp wrap(element, kind, motion, rules) do
    class = class(Atom.to_string(kind), motion)
    {Element.group([element], style: %{class: class}), [{kind, class, motion} | rules]}
  end

  defp identifier!(name) do
    if Validator.Motion.identifier?(name),
      do: name,
      else:
        raise(
          ArgumentError,
          "keyframes name #{inspect(name)} is not a CSS identifier (spec/14 §10.3)"
        )
  end

  defp class(kind, motion) do
    "vis-#{kind}-" <> (motion |> :erlang.phash2() |> Integer.to_string(36) |> String.downcase())
  end

  defp add_class(style, class) do
    Map.update(style, :class, class, fn own -> own <> " " <> class end)
  end
end
