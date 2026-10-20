defmodule Visualize.Chart.CompositeRoundTripTest do
  @moduledoc """
  #713, D-187: a design decomposed into the builder's sites flattens back to itself
  (spec/14 §18.12, spec/12 §6) — every design the library's tests hold, and the two keys
  0.7.0 added that decompose once dropped: a design-level `defaults` and a list-valued style.
  """
  use ExUnit.Case, async: true

  alias Visualize.{BuilderFixture, Chart, Designs}
  alias Visualize.Chart.{Builder, Composite, Migration}

  defp round_trip(design) do
    canonical = Migration.canonical(design)
    {uses, _labels} = Composite.decompose(canonical)

    assert {:ok, flat, %{missing: [], keyless: []}} =
             Composite.flatten(%{composite: %{uses: uses}}, fn _id -> :error end)

    # `version` aside, which flatten writes (spec/14 §18.12).
    {flat |> Migration.canonical() |> Map.delete(:version), Map.delete(canonical, :version)}
  end

  for name <- Designs.names() do
    @name name
    test "#{name} round-trips through its sites" do
      {flat, canonical} = round_trip(Designs.design(@name))
      assert flat == canonical
    end
  end

  test "a design-level defaults and a list-valued style round-trip, each a site of its own" do
    design = %{
      Designs.design(hd(Designs.names()))
      | styles: %{
          outline: %{stroke: %{width: 2}},
          warn: [:warning, :outline],
          thick: [:outline, %{stroke: %{width: 4}}]
        }
    }

    design = Map.put(design, :defaults, %{stroke: %{cap: :round}, line: %{stroke: %{width: 1.5}}})

    {flat, canonical} = round_trip(design)
    assert flat == canonical
    assert flat.defaults == canonical.defaults
    assert flat.styles["warn"] == ["warning", "outline"]

    {uses, labels} = Composite.decompose(Migration.canonical(design))
    assert "defaults" in Map.values(labels)

    assert %{key: "warn", local: %{style: style}} = Enum.find(uses, &(&1.key == "warn"))
    assert Enum.map(style, &to_string/1) == ["warning", "outline"]
  end

  test "the builder imports such a design and draws it with every site selected" do
    design =
      Designs.design(hd(Designs.names()))
      |> Map.put(:version, 3)
      |> Map.update!(
        :styles,
        &Map.merge(&1, %{outline: %{stroke: %{width: 2}}, warn: [:warning, :outline]})
      )
      |> Map.put(:defaults, %{stroke: %{cap: :round}})

    {:ok, json} = Chart.to_json(Chart.from_map!(design))

    socket =
      BuilderFixture.socket(BuilderFixture.parameterized(),
        on_save: :visualize_chart_saved,
        vars: %{},
        theme: nil
      )

    {:noreply, opened} = Builder.handle_event("import", %{"document" => json}, socket)
    assert "defaults" in BuilderFixture.names(opened)
    assert "style warn" in BuilderFixture.names(opened)
    assert BuilderFixture.design(opened).defaults == %{stroke: %{cap: :round}}

    for use <- opened.assigns.uses do
      selected = %{opened | assigns: Map.put(opened.assigns, :selected, use.id)}
      assert BuilderFixture.render(selected) =~ "vis-builder", inspect(use.local)
    end

    # The palette lists the stack in order, and opening it draws its site.
    assert BuilderFixture.render(opened) =~ "[warning, outline]"
    {:noreply, styled} = Builder.handle_event("select_style", %{"name" => "warn"}, opened)
    assert BuilderFixture.render(styled) =~ "vis-builder"
  end

  test "a list-valued style site with no key is keyless" do
    use = %Visualize.Chart.Use{id: {:use, 1}, ref: nil, local: %{style: [:warning]}}
    assert Composite.place(%{style: [:warning]}, use) == :keyless
  end
end
