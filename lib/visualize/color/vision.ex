defmodule Visualize.Color.Vision do
  @moduledoc """
  Colour-vision simulation: how a colour reads to a person with one of the three
  dichromacies (spec/08 §1.8, D-139).

  The model is Machado, Oliveira and Fernandes (2009), "A Physiologically-based Model for
  Simulation of Color Vision Deficiency", *IEEE Transactions on Visualization and Computer
  Graphics* 15(6), 1291–1298, at severity 1.0. A colour is decoded from sRGB to linear RGB,
  multiplied by the deficiency's matrix, clamped to `0..1` and encoded back; its opacity is
  kept. Each matrix's rows sum to 1, so a grey is its own simulation.

  It is a transform for judging a palette by eye — the theme editor draws its ramps and its
  preview through it — and nothing in the library draws through it on its own.

  ## Examples

      iex> red = Visualize.Color.parse("#ff0000")
      iex> Visualize.Color.Vision.simulate(red, :protanopia) |> Visualize.Color.to_hex()
      "#6d5f00"
      iex> grey = Visualize.Color.parse("#808080")
      iex> Visualize.Color.Vision.simulate(grey, :tritanopia) |> Visualize.Color.to_hex()
      "#808080"

  """

  alias Visualize.Color

  @typedoc "A dichromacy the model simulates, or `:none` for the colour as it is."
  @type deficiency :: :protanopia | :deuteranopia | :tritanopia

  # Machado, Oliveira and Fernandes (2009), Table 1 of the supplementary material, the
  # severity 1.0 matrices, rows R, G and B over linear RGB.
  @matrices %{
    protanopia: [
      [0.152286, 1.052583, -0.204868],
      [0.114503, 0.786281, 0.099216],
      [-0.003882, -0.048116, 1.051998]
    ],
    deuteranopia: [
      [0.367322, 0.860646, -0.227968],
      [0.280085, 0.672501, 0.047413],
      [-0.011820, 0.042940, 0.968881]
    ],
    tritanopia: [
      [1.255528, -0.076749, -0.178779],
      [-0.078411, 0.930809, 0.147602],
      [0.004733, 0.691367, 0.303900]
    ]
  }

  @deficiencies [:protanopia, :deuteranopia, :tritanopia]

  @doc "The deficiencies the model simulates: `[:protanopia, :deuteranopia, :tritanopia]`."
  @spec deficiencies() :: [deficiency(), ...]
  def deficiencies, do: @deficiencies

  @doc """
  The deficiency's matrix over linear RGB, as three rows (Machado et al. 2009, severity 1.0).

      iex> Visualize.Color.Vision.matrix(:deuteranopia) |> hd()
      [0.367322, 0.860646, -0.227968]
  """
  @spec matrix(deficiency()) :: [[float()]]
  def matrix(deficiency) when deficiency in @deficiencies, do: Map.fetch!(@matrices, deficiency)
  def matrix(other), do: unknown!(other)

  @doc """
  The colour as the deficiency sees it, its opacity kept; `:none` is the colour itself.
  Any other atom raises `ArgumentError`.
  """
  @spec simulate(Color.t(), deficiency() | :none) :: Color.t()
  def simulate(%Color{} = colour, :none), do: colour

  def simulate(%Color{r: r, g: g, b: b, opacity: opacity}, deficiency)
      when deficiency in @deficiencies do
    linear = Enum.map([r, g, b], &decode(&1 / 255))

    [r, g, b] =
      for row <- matrix(deficiency) do
        row
        |> Enum.zip_with(linear, &(&1 * &2))
        |> Enum.sum()
        |> max(0.0)
        |> min(1.0)
        |> encode()
        |> Kernel.*(255)
        |> round()
      end

    Color.rgb(r, g, b, opacity)
  end

  def simulate(%Color{}, other), do: unknown!(other)

  @doc """
  The text with every `#rrggbb` and `#rgb` colour literal replaced by its simulation, as
  `#rrggbb` — an SVG's fills and strokes, a style's colours. A `#` that is a reference,
  `url(#id)`, is left alone, and so is everything that is not a colour; `:none` is the text.

      iex> Visualize.Color.Vision.recolor(~s|<rect fill="#ff0000" mask="url(#bad)"/>|, :protanopia)
      ~s|<rect fill="#6d5f00" mask="url(#bad)"/>|
  """
  @spec recolor(String.t(), deficiency() | :none) :: String.t()
  def recolor(text, :none) when is_binary(text), do: text

  def recolor(text, deficiency) when is_binary(text) and deficiency in @deficiencies do
    Regex.replace(
      ~r/(?<=["':\s,])#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{3})(?![0-9A-Za-z_-])/,
      text,
      fn literal ->
        literal
        |> Color.parse()
        |> simulate(deficiency)
        |> Color.to_hex()
      end
    )
  end

  def recolor(text, other) when is_binary(text), do: unknown!(other)

  # The sRGB transfer function of IEC 61966-2-1, and its inverse.
  defp decode(c) when c <= 0.04045, do: c / 12.92
  defp decode(c), do: :math.pow((c + 0.055) / 1.055, 2.4)

  defp encode(l) when l <= 0.0031308, do: l * 12.92
  defp encode(l), do: 1.055 * :math.pow(l, 1 / 2.4) - 0.055

  defp unknown!(other) do
    raise ArgumentError,
          "#{inspect(other)} is not a deficiency the model simulates; " <>
            "the deficiencies are #{inspect(@deficiencies)}, or :none"
  end
end
