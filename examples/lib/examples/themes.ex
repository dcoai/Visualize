defmodule Examples.Themes do
  @moduledoc """
  The themes a chart page picks from (spec/14 §12.6, #792, work item #794): one list of
  real `Visualize.Theme` values, each under a key.

  - **The four built-in themes** — Default, Dark, Color-safe and Print — as the library
    ships them (spec/08 §7.2), each with the gallery's font stack.
  - **Six host themes** — Sunrise, Winter, Sunset, Fall, Spring and Summer — built as a
    host builds one, with `Visualize.Theme.new/1`: series and page slots, the theme's own
    `:red`, `:amber`, `:green`, `:blue` and `:gray` tuned to its page, a `sequential` ramp
    from the page to the first color, and a `:title` and a `:grid` style of its own. Each
    holds every contract `Visualize.Theme.check/1` asks (spec/08 §7.5, §7.7).

  The list is the one lookup: a key is matched against the listed keys as a string, so a
  page's event or a URL never makes an atom (D-195).
  """

  alias Examples.Themes.Hosts
  alias Visualize.Theme

  # The list is built once, as the module compiles: `Theme.new/1` checks every host theme's
  # contracts there, so a host theme that breaks one fails the build, not a page.
  @builtins [
    {"default", "Default", "The library's light theme", :default},
    {"dark", "Dark", "The library's dark theme", :dark},
    {"color_safe", "Color-safe",
     "The library's color-vision-safe theme: status runs blue → orange → red", :color_safe},
    {"print", "Print",
     "The library's print theme: white paper, dark ink, the color-safe status ramp, role fills hatched",
     :print}
  ]

  @list (for {key, name, description, builtin} <- @builtins do
           %{
             key: key,
             name: name,
             description: description,
             theme: Theme.merge(Theme.builtin(builtin), font_family: Hosts.font_family())
           }
         end) ++
          (for key <- Hosts.keys() do
             {name, description} = Hosts.info(key)

             %{
               key: Atom.to_string(key),
               name: name,
               description: description,
               theme: Theme.new(Hosts.options(key))
             }
           end)

  @doc """
  Every theme the picker offers, in its order: `%{key, name, description, theme}`, the
  built-in themes first, then the host themes.
  """
  @spec list() :: [
          %{key: String.t(), name: String.t(), description: String.t(), theme: Theme.t()}
        ]
  def list, do: @list

  @doc "The listed keys, the only words a theme is picked by."
  @spec keys() :: [String.t()]
  def keys, do: Enum.map(@list, & &1.key)

  @doc """
  The listed entry of `key`, matched as a string against the listed keys, or `nil` for a
  key the list lacks — never an atom made from it.

      iex> Examples.Themes.entry("print").theme.name
      :print
      iex> Examples.Themes.entry("sunrise").theme.name
      "sunrise"
      iex> Examples.Themes.entry("no_such_theme")
      nil
  """
  @spec entry(term()) :: map() | nil
  def entry(key) when is_binary(key), do: Enum.find(@list, &(&1.key == key))
  def entry(_key), do: nil

  @doc "The theme of `key`, the gallery's Default for `nil` or a key the list lacks."
  @spec theme(term()) :: Theme.t()
  def theme(key), do: (entry(key) || hd(@list)).theme

  @doc """
  The Elixir that builds the theme of a listed `key`, as the Theme lab shows it (#795): a
  built-in theme merged with the gallery's font stack, or a host theme's `Theme.new/1`
  call with its options.
  """
  @spec code(String.t()) :: String.t()
  def code(key) do
    builtin = Enum.find_value(@builtins, fn {k, _n, _d, f} -> if k == key, do: f end)
    host = Enum.find(Hosts.keys(), &(Atom.to_string(&1) == key))

    built =
      cond do
        builtin ->
          "Visualize.Theme.merge(Visualize.Theme.#{builtin}(),\n" <>
            "  font_family: #{inspect(Hosts.font_family())}\n)"

        host ->
          options =
            Enum.map_join(Hosts.options(host), ",\n", fn {name, value} ->
              "#{name}: #{inspect(value, pretty: true, width: 76, limit: :infinity)}"
            end)

          "Visualize.Theme.new(\n" <> indent(options) <> "\n)"
      end

    "theme =\n" <> indent(built) <> "\n\nVisualize.Theme.check(theme)\n#=> :ok\n"
  end

  defp indent(text),
    do: text |> String.split("\n") |> Enum.map_join("\n", &("  " <> &1))

  @doc "The gallery's Default: `Visualize.Theme.default/0` with the gallery's font stack."
  @spec default() :: Theme.t()
  def default, do: hd(@list).theme
end
