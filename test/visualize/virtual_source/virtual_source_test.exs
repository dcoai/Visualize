defmodule Visualize.VirtualSourceTest do
  # The virtual source as a value (spec/08 §10.5.5–10.5.10, D-194).
  use ExUnit.Case, async: true

  alias Visualize.Data.Schema
  alias Visualize.VirtualSource

  doctest Visualize.VirtualSource

  # Names the stored functions below use, atoms when this module loads.
  @names ~w(hosts host cpu state trend health load mem region)a
  setup_all do
    {:ok, names: @names}
  end

  @hosts Schema.new!(%{
           t: %{type: :time},
           host: %{type: :category, identity: true},
           cpu: %{type: :number}
         })

  defp health(overrides \\ []) do
    Keyword.merge(
      [
        id: :health,
        from: [hosts: {:window, last: 20}],
        per: :identity,
        schema: %{
          host: %{type: :category, identity: true},
          state: %{type: :category, values: [:ok, :warning, :error]}
        },
        elixir: "fn rows -> %{state: if(List.last(rows).cpu > 90, do: :error, else: :ok)} end"
      ],
      overrides
    )
  end

  describe "new/1: alone" do
    test "the proposal's spelling reads as the map form" do
      assert {:error, faults} = VirtualSource.new(health())
      # List.last/1 is not on the allowlist: the function is checked alone too.
      assert [{[:elixir], {:check, 1, {:restricted, {"List", :last, 1}}}}] = faults

      {:ok, source} =
        VirtualSource.new(health(elixir: "fn rows -> %{state: :ok} end"))

      assert source.from == [{"hosts", %{last: 20}}]
      assert %Schema{} = source.schema
      assert {:ok, ^source} = source |> VirtualSource.to_map() |> VirtualSource.new()
    end

    test "every fault, by path" do
      assert {:error, faults} =
               VirtualSource.new(%{
                 id: nil,
                 from: [{"a", %{last: 0}}, {:a, nil}, :b, {[:x, 1], nil}, {:c, %{bogus: 1}}],
                 schema: %{state: %{type: :category, values: []}},
                 elixir: 3,
                 per: :sideways,
                 extra: 1
               })

      assert faults == [
               {[:elixir], {:type, :string}},
               {[:extra], :unknown_key},
               {[:from, 0, :window, :last], {:type, :pos_integer}},
               {[:from, 1], {:duplicate_input, "a"}},
               {[:from, 2], {:type, :input}},
               {[:from, 3], {:type, :input_name}},
               {[:from, 4, :window], {:type, :input_window}},
               {[:id], {:type, :name}},
               {[:per], {:enum, [:identity]}},
               {[:schema, "state", :values], {:type, :values}}
             ]

      for fault <- faults, do: assert(is_binary(VirtualSource.format_error(fault)))
    end

    test "required keys, one function, inputs read under distinct keys" do
      assert {:error, faults} = VirtualSource.new(%{})
      assert {[:from], :required} in faults
      assert {[:schema], :required} in faults
      assert {[:id], :required} in faults
      assert {[:elixir], :required} in faults

      assert {:error, [{[:function], {:exclusive, :elixir}}]} =
               VirtualSource.new(health(elixir: "fn rows -> rows end", function: :health))

      # A path is read under its last atom; an atom and a string are two keys.
      assert {:error, [{[:from, 1], {:duplicate_input, "hosts"}}]} =
               VirtualSource.new(
                 health(
                   per: nil,
                   from: [{:hosts, nil}, {[:ops, :hosts], nil}],
                   elixir: "fn x -> [] end"
                 )
               )

      # An atom and a string of one spelling are one key (D-195).
      assert {:error, [{[:from, 1], {:duplicate_input, "hosts"}}]} =
               VirtualSource.new(
                 health(per: nil, from: [{:hosts, nil}, {"hosts", nil}], elixir: "fn x -> [] end")
               )
    end

    test "per names its input when there are several" do
      assert {:error, [{[:per], {:per, :ambiguous}}]} =
               VirtualSource.new(health(from: [hosts: nil, load: nil], elixir: "fn x -> x end"))

      assert {:error, [{[:per], {:per, {:unknown_input, "mem"}}}]} =
               VirtualSource.new(
                 health(
                   from: [hosts: nil, load: nil],
                   per: {:identity, :mem},
                   elixir: "fn x -> x end"
                 )
               )

      assert {:ok, _source} =
               VirtualSource.new(
                 health(
                   from: [hosts: nil, load: nil],
                   per: {:identity, :hosts},
                   elixir: "fn x -> x end"
                 )
               )
    end

    test "a keyword list that is not one, and anything else" do
      assert {:error, [{[], {:type, :virtual_source}}]} = VirtualSource.new([1, 2])
      assert {:error, [{[], {:type, :virtual_source}}]} = VirtualSource.new(:nope)
      assert_raise ArgumentError, ~r/not a virtual source/, fn -> VirtualSource.new!(%{}) end
    end
  end

  describe "validate/2: in context" do
    setup do
      {:ok, source: VirtualSource.new!(health(elixir: "fn rows -> %{state: :ok} end"))}
    end

    test "a function reads its inputs' fields and its own", %{source: source} do
      assert :ok = VirtualSource.validate(source, inputs: %{hosts: @hosts})

      reads_mem = %{source | elixir: "fn rows -> %{state: Enum.at(rows, 0).mem} end"}

      assert {:error, [{[:elixir], {:check, 1, {:unknown_field, "mem"}}}]} =
               VirtualSource.validate(reads_mem, inputs: %{hosts: @hosts})

      # An input whose schema is not known leaves the fields unchecked.
      assert :ok = VirtualSource.validate(reads_mem, inputs: %{})
    end

    test "a host function is one the registry holds", %{source: source} do
      hosted = %{source | elixir: nil, function: :health}
      assert :ok = VirtualSource.validate(hosted, functions: %{health: __MODULE__})

      assert {:error, [{[:function], {:undeclared, :function, :health}}]} =
               VirtualSource.validate(hosted, functions: %{})

      assert :ok = VirtualSource.validate(hosted)
    end

    test "a box is checked against its input's schema", %{source: source} do
      boxed = %{source | from: [hosts: %{ranges: %{"nope" => [0, 1]}}]}

      assert {:error, [{[:from, 0, :window, :ranges, "nope"], {:window, :unknown_field}}]} =
               VirtualSource.validate(boxed, inputs: %{hosts: @hosts})
    end

    test "per identity: the input declares one, and the output's is the input's", %{
      source: source
    } do
      no_identity = Schema.new!(%{host: %{type: :category}, cpu: %{type: :number}})

      assert {:error, [{[:per], {:per, :no_identity}}]} =
               VirtualSource.validate(source, inputs: %{hosts: no_identity})

      other = Schema.new!(%{region: %{type: :category, identity: true}, cpu: %{type: :number}})

      assert {:error, [{[:schema], {:per, {:identity, ["region"], ["host"]}}}]} =
               VirtualSource.validate(source, inputs: %{hosts: other})

      numbered = Schema.new!(%{host: %{type: :number, identity: true}, cpu: %{type: :number}})

      assert {:error, [{[:schema, "host"], {:per, {:identity_type, "host", :number, :category}}}]} =
               VirtualSource.validate(source, inputs: %{hosts: numbered})
    end
  end

  describe "conform/2" do
    setup do
      {:ok,
       source:
         VirtualSource.new!(
           id: :health,
           from: [hosts: nil],
           per: :identity,
           schema: %{
             "region" => %{type: :text},
             host: %{type: :category, identity: true},
             state: %{type: :category, values: [:ok, :error]},
             load: %{type: :number},
             t: %{type: :time}
           },
           elixir: "fn x -> x end"
         )}
    end

    test "rows in the schema conform; nil is any field's", %{source: source} do
      rows = [
        %{host: "a", state: :ok, load: 1.5, t: ~U[2026-10-16 00:00:00Z], region: "eu"},
        %{"host" => "b", state: nil, load: nil}
      ]

      assert {:ok, ^rows} = VirtualSource.conform(source, rows)
    end

    test "the first fault, by row and field, never the value", %{source: source} do
      assert {:error, {nil, nil, :not_a_list}} = VirtualSource.conform(source, %{})
      assert {:error, {1, nil, :not_a_row}} = VirtualSource.conform(source, [%{host: "a"}, 3])

      assert {:error, {0, "cpu", :undescribed}} =
               VirtualSource.conform(source, [%{host: "a", cpu: 1}])

      assert {:error, {0, "host", :no_identity}} = VirtualSource.conform(source, [%{state: :ok}])

      assert {:error, {0, "load", {:type, :number}}} =
               VirtualSource.conform(source, [%{host: "a", load: "1"}])

      assert {:error, {0, "t", {:type, :time}}} =
               VirtualSource.conform(source, [%{host: "a", t: 3}])

      assert {:error, {0, "region", {:type, :text}}} =
               VirtualSource.conform(source, [%{host: "a", region: :eu}])

      assert {:error, {0, "state", :not_in_values}} =
               VirtualSource.conform(source, [%{host: "a", state: :warning}])

      assert {:error, {0, "host", {:type, :category}}} =
               VirtualSource.conform(source, [%{host: true}])
    end
  end

  test "conform/2: a value entry's value is the value (D-224)" do
    source =
      VirtualSource.new!(
        id: :health,
        from: [hosts: nil],
        schema: %{
          state: %{
            type: :category,
            values: [%{value: :ok, name: "OK", color: "#2e7d32"}, :warning]
          }
        },
        elixir: "fn x -> x end"
      )

    assert [%{value: "ok", name: "OK", color: "#2e7d32"}, :warning] =
             source.schema.fields["state"].values

    assert {:ok, _} = VirtualSource.conform(source, [%{state: :ok}, %{state: "warning"}])

    assert {:error, {0, "state", :not_in_values}} =
             VirtualSource.conform(source, [%{state: :error}])

    assert {:error, {0, "state", {:type, :category}}} =
             VirtualSource.conform(source, [%{state: %{value: :ok, name: "OK"}}])
  end

  test "key/1 and identity_input/1" do
    assert VirtualSource.key(:hosts) == :hosts
    assert VirtualSource.key("vm.memory") == "vm.memory"
    assert VirtualSource.key([:ops, :health]) == :health
    assert VirtualSource.key(3) == nil

    one = VirtualSource.new!(health(elixir: "fn x -> x end"))
    assert VirtualSource.identity_input(one) == "hosts"
    assert VirtualSource.identity_input(%{one | per: nil}) == nil
    assert VirtualSource.identity_input(%{one | per: {:identity, :load}}) == :load
  end

  describe "resolve/3: one resolver, from the inside out" do
    @paths [[:health], [:ops, :health], [:ops, :box, :load], [:other, :health]]

    test "the nearest definition wins, and an inner one shadows an outer one" do
      assert VirtualSource.resolve(@paths, [:ops, :box], :health) == {:ok, ["ops", "health"]}
      assert VirtualSource.resolve(@paths, [:ops, :box], :load) == {:ok, ["ops", "box", "load"]}
      assert VirtualSource.resolve(@paths, [:elsewhere], :health) == {:ok, ["health"]}
      assert VirtualSource.resolve(@paths, [], :health) == {:ok, ["health"]}
      assert VirtualSource.resolve(@paths, [:ops], :load) == :error
    end

    test "a full path names one exactly, from any scope; a string is never resolved" do
      assert VirtualSource.resolve(@paths, [:ops], [:other, :health]) ==
               {:ok, ["other", "health"]}

      assert VirtualSource.resolve(@paths, [:ops], [:ops, :nope]) == :error
      assert VirtualSource.resolve(@paths, [:ops], {:feed, "health"}) == :error

      assert VirtualSource.resolve(Map.new(@paths, &{&1, nil}), [:ops], :health) ==
               {:ok, ["ops", "health"]}
    end

    test "dotted/1" do
      assert VirtualSource.dotted([:ops, :box, :load]) == "ops.box.load"
    end
  end
end
