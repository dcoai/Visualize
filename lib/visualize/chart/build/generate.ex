defmodule Visualize.Chart.Build.Generate do
  @moduledoc false
  # The builder's mark, transform and scale functions, emitted from `Visualize.Chart.Schema`
  # at compile time (spec/14 §16.6, D-79): one documented function per mark type, per
  # transform op and per scale kind, each delegating to the generic form in
  # `Visualize.Chart.Build`, which is the only module that uses this one. A type added to the
  # schema grows the builder with no edit to it.
  #
  # `injected/0` is what `Visualize.Audit.CodeScan` asks a used module for: a generated
  # function is not in the source of `lib/`, so the surface golden would otherwise miss it.

  alias Visualize.Chart.Schema

  @doc false
  defmacro __using__(_opts) do
    marks() ++ transforms() ++ scales()
  end

  @doc false
  # Every `{name, arity}` this module injects, the default-argument arity included.
  @spec injected() :: [{atom(), arity()}]
  def injected do
    Enum.flat_map(definitions(), fn {name, arity} -> [{name, arity - 1}, {name, arity}] end)
  end

  @doc false
  # The name of the builder function for a scale kind. Every kind takes the suffix, not
  # only `band`, which is a mark type as well (spec/14 §16.6).
  @spec scale_function(atom()) :: atom()
  def scale_function(kind), do: :"#{kind}_scale"

  defp definitions do
    marks = for type <- Schema.mark_types(), do: {type, 3}
    scales = for kind <- Schema.scale_kinds(), do: {scale_function(kind), 2}

    ops = for op <- Schema.transform_ops(), do: {op, 2 + length(positional(op))}

    marks ++ ops ++ scales
  end

  # -- one function per mark type (spec/14 §5.2) ------------------------------------------

  defp marks do
    for type <- Schema.mark_types() do
      doc = mark_doc(type)

      quote do
        @doc unquote(doc)
        @spec unquote(type)(data(), opts() | Visualize.Chart.Var.t(), opts()) :: fragment()
        def unquote(type)(data, channels, opts \\ []) do
          mark(unquote(type), data, channels, opts)
        end
      end
    end
  end

  defp mark_doc(type) do
    %{required: required, optional: optional} = Schema.channels(type)

    """
    A `:#{type}` mark, as `mark/4` of that type (spec/14 §5.2).

    #{sentence("Required channels", required)}#{sentence("Optional channels", optional)}#{sentence("Options", Schema.options(type))}
    """
  end

  # -- one appender per transform op (spec/14 §5.4) ---------------------------------------

  defp transforms do
    for op <- Schema.transform_ops() do
      positional = positional(op)
      args = for key <- positional, do: Macro.var(key, __MODULE__)
      types = for _ <- positional, do: quote(do: term())
      node = {:%{}, [], [{:op, op} | Enum.zip(positional, args)]}
      doc = op_doc(op, positional)

      quote do
        @doc unquote(doc)
        @spec unquote(op)(data(), unquote_splicing(types), opts()) :: map()
        def unquote(op)(data, unquote_splicing(args), opts \\ []) do
          # A positional argument given as `nil` is left out, so `projection(data, nil,
          # field: :shape)` reads a geometry column (spec/14 §5.4.4).
          step(data, Map.reject(unquote(node), fn {_, v} -> is_nil(v) end), opts)
        end
      end
    end
  end

  # The keys an op's builder takes positionally: its required keys — and `fields` for a
  # projection, whose one required key is either of two (spec/14 §5.4.4, §16).
  defp positional(:projection), do: [:fields]
  defp positional(op), do: Schema.transform_keys(op).required

  defp op_doc(op, positional) do
    %{optional: optional} = Schema.transform_keys(op)
    optional = optional -- positional
    args = Enum.map_join(["data" | Enum.map(positional, &to_string/1)] ++ ["opts"], ", ", & &1)

    """
    A `:#{op}` step appended to a data node (spec/14 §5.4).

    `#{op}(#{args})`, with `data` a node `from/1` started or a source name, read as `from/1`
    of it. #{sentence("Its remaining keys", optional)}
    """
  end

  # -- one function per scale kind (spec/14 §4.3) -----------------------------------------

  defp scales do
    for kind <- Schema.scale_kinds() do
      function = scale_function(kind)

      doc =
        "A `:#{kind}` scale declared under the frame, as `scale/3` of that kind " <>
          "(spec/14 §4.3).\n"

      quote do
        @doc unquote(doc)
        @spec unquote(function)(atom(), opts()) :: fragment()
        def unquote(function)(name, opts \\ []) do
          scale(name, unquote(kind), opts)
        end
      end
    end
  end

  defp sentence(_lead, []), do: ""
  defp sentence(lead, keys), do: "#{lead}: #{Enum.map_join(keys, ", ", &"`#{&1}`")}. "
end
